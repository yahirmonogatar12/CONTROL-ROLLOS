'use strict';

const { pool } = require('../config/database');

const REQUIRED_INVOICE_TABLES = [
  'material_invoices',
  'material_invoice_packing_lines',
  'material_invoice_lot_links',
];

let schemaCache;
const SCHEMA_CACHE_MS = 60 * 1000;

function normalizePartNumbers(partNumbers = []) {
  return [...new Set(
    partNumbers
      .map((partNumber) => String(partNumber || '').trim())
      .filter(Boolean),
  )];
}

async function inspectInvoiceSchema(executor = pool) {
  const now = Date.now();
  if (
    executor === pool &&
    schemaCache &&
    now - schemaCache.checkedAt < SCHEMA_CACHE_MS
  ) {
    return schemaCache;
  }

  const placeholders = REQUIRED_INVOICE_TABLES.map(() => '?').join(',');
  const [rows] = await executor.query(
    `SELECT
       COUNT(DISTINCT t.table_name) AS table_count,
       EXISTS(
         SELECT 1
         FROM information_schema.columns c
         WHERE c.table_schema = DATABASE()
           AND c.table_name = 'material_invoices'
           AND c.column_name = 'cerrado_manual'
       ) AS has_manual_close
     FROM information_schema.tables t
     WHERE t.table_schema = DATABASE()
       AND t.table_name IN (${placeholders})`,
    REQUIRED_INVOICE_TABLES,
  );

  const result = {
    available: Number(rows[0]?.table_count || 0) === REQUIRED_INVOICE_TABLES.length,
    hasManualClose: Number(rows[0]?.has_manual_close || 0) === 1,
    checkedAt: now,
  };
  if (executor === pool) schemaCache = result;
  return result;
}

async function getPendingInvoicesByPartNumbers(partNumbers, executor = pool) {
  const uniquePartNumbers = normalizePartNumbers(partNumbers);
  const pendingByPart = new Map();
  if (uniquePartNumbers.length === 0) return pendingByPart;

  try {
    const schema = await inspectInvoiceSchema(executor);
    if (!schema.available) return pendingByPart;

    const placeholders = uniquePartNumbers.map(() => '?').join(',');
    const manualCloseFilter = schema.hasManualClose
      ? 'AND COALESCE(mi.cerrado_manual, 0) = 0'
      : '';
    const [rows] = await executor.query(
      `SELECT
         pk.numero_parte_sistema,
         CAST(SUM(pk.cantidad_packing - COALESCE(ap.aplicado, 0)) AS SIGNED)
           AS cantidad_pendiente_entrada,
         GROUP_CONCAT(
           DISTINCT mi.numero_invoice
           ORDER BY mi.numero_invoice SEPARATOR ', '
         ) AS invoices_pendientes
       FROM material_invoice_packing_lines pk
       JOIN material_invoices mi ON mi.id = pk.invoice_id
       LEFT JOIN (
         SELECT packing_line_id, SUM(cantidad_aplicada) AS aplicado
         FROM material_invoice_lot_links
         WHERE estado = 'APLICADO'
         GROUP BY packing_line_id
       ) ap ON ap.packing_line_id = pk.id
       WHERE mi.estado NOT IN ('APLICADA', 'CANCELADA')
         ${manualCloseFilter}
         AND pk.numero_parte_sistema IN (${placeholders})
         AND pk.cantidad_packing > COALESCE(ap.aplicado, 0)
       GROUP BY pk.numero_parte_sistema`,
      uniquePartNumbers,
    );

    for (const row of rows) {
      pendingByPart.set(String(row.numero_parte_sistema), {
        cantidadPendienteEntrada: Number(row.cantidad_pendiente_entrada || 0),
        invoicesPendientes: String(row.invoices_pendientes || '').trim(),
      });
    }
  } catch (error) {
    // El módulo de invoices pertenece al sistema de almacén. Si aún no está
    // instalado o tiene un esquema anterior, no debe romper el catálogo.
    console.warn('No se pudo consultar material pendiente por invoice:', error.message);
  }

  return pendingByPart;
}

async function attachPendingInvoiceData(rows, executor = pool) {
  const pendingByPart = await getPendingInvoicesByPartNumbers(
    rows.map((row) => row.numero_parte),
    executor,
  );

  return rows.map((row) => {
    const pending = pendingByPart.get(String(row.numero_parte)) || {};
    const quantity = pending.cantidadPendienteEntrada || 0;
    const invoices = pending.invoicesPendientes || '';
    return {
      ...row,
      cantidad_pendiente_entrada: quantity,
      invoices_pendientes: invoices,
      pendiente_entrada_en: invoices,
    };
  });
}

function resetSchemaCacheForTests() {
  schemaCache = undefined;
}

module.exports = {
  normalizePartNumbers,
  inspectInvoiceSchema,
  getPendingInvoicesByPartNumbers,
  attachPendingInvoiceData,
  resetSchemaCacheForTests,
};
