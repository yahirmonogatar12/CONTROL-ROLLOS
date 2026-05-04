/**
 * PCB Inventory Controller - Inventario de PCBs por escaneo
 * Soporta 3 tipos de movimiento: ENTRADA, SALIDA, SCRAP
 * Soporta 2 areas: INVENTARIO, REPARACION
 * Soporta 3 procesos: SMD, IMD, ASSY
 * Pantalla Flutter: lib/screens/pcb_inventory/
 */

const { pool } = require('../config/database');

// ============================================
// HELPERS
// ============================================

function normalizeCode(code) {
  return (code || '').trim().toUpperCase().replace(/\s+/g, '');
}

function parseScannedCode(code) {
  const parts = code.split(';').map(s => s.trim()).filter(Boolean);
  const normalizedParts = parts.map(part => part.toUpperCase());
  return {
    token0: normalizedParts[0] || null,
    assy_type: normalizedParts[1] || null,
    pcb_part_no: normalizedParts[2] || null,
    token3: normalizedParts[3] || null,
  };
}

function parsePcbPartNo(value) {
  const partNo = (value || '').toString().trim().toUpperCase();
  return /^EBR\d{8}$/.test(partNo) ? partNo : null;
}

async function lookupModelo(pcbPartNo) {
  try {
    const [rows] = await pool.query(
      `SELECT DISTINCT modelo FROM bom WHERE modelo = ? OR numero_parte = ? LIMIT 1`,
      [pcbPartNo, pcbPartNo]
    );
    if (rows.length > 0 && rows[0].modelo) {
      return rows[0].modelo;
    }
    return 'N/A';
  } catch (err) {
    return 'N/A';
  }
}

async function lookupModelosBatch(connection, pcbPartNos) {
  const uniquePartNos = [...new Set((pcbPartNos || []).filter(Boolean))];
  const defaultMap = new Map(uniquePartNos.map(partNo => [partNo, 'N/A']));
  if (uniquePartNos.length === 0) return defaultMap;

  const placeholders = uniquePartNos.map(() => '?').join(', ');
  const [rows] = await connection.query(
    `SELECT numero_parte, modelo
     FROM bom
     WHERE numero_parte IN (${placeholders})
        OR modelo IN (${placeholders})`,
    [...uniquePartNos, ...uniquePartNos]
  );

  for (const row of rows) {
    const numeroParte = (row.numero_parte || '').toString().trim().toUpperCase();
    const modelo = (row.modelo || '').toString().trim();
    if (!modelo) continue;

    if (defaultMap.has(numeroParte) && defaultMap.get(numeroParte) === 'N/A') {
      defaultMap.set(numeroParte, modelo);
    }

    const modeloUpper = modelo.toUpperCase();
    if (defaultMap.has(modeloUpper) && defaultMap.get(modeloUpper) === 'N/A') {
      defaultMap.set(modeloUpper, modelo);
    }
  }

  return defaultMap;
}

const VALID_PROCESOS = ['SMD', 'IMD', 'ASSY'];
const VALID_AREAS = ['INVENTARIO', 'REPARACION'];
const VALID_TIPOS = ['ENTRADA', 'SALIDA', 'SCRAP'];

function parseArrayCount(value) {
  const parsed = parseInt(value, 10);
  return Number.isInteger(parsed) && parsed > 0 ? parsed : 1;
}

function parseQty(value) {
  const parsed = parseInt(value, 10);
  return Number.isInteger(parsed) && parsed > 0 ? parsed : 1;
}

function parseStrictQty(value) {
  const parsed = parseInt(value, 10);
  return Number.isInteger(parsed) && parsed > 0 ? parsed : null;
}

async function getPartStock(connection, pcbPartNo, area, proceso) {
  const [rows] = await connection.query(
    `SELECT
       SUM(CASE WHEN tipo_movimiento = 'ENTRADA' THEN qty ELSE 0 END)
       - SUM(CASE WHEN tipo_movimiento IN ('SALIDA', 'SCRAP') THEN qty ELSE 0 END) AS stock_actual
     FROM pcb_inventory_scan_smd
     WHERE pcb_part_no = ?
     AND area = ?
     AND proceso = ?`,
    [pcbPartNo, area, proceso]
  );
  return Number(rows[0]?.stock_actual || 0);
}

async function getInitialStockOption(connection, pcbPartNo) {
  const [rows] = await connection.query(
    `SELECT
       pcb_part_no,
       MAX(modelo) AS modelo,
       area,
       proceso,
       SUM(CASE WHEN tipo_movimiento = 'ENTRADA'
             AND scanned_original_norm LIKE 'INITIAL:%' THEN qty ELSE 0 END) AS initial_qty,
       SUM(CASE WHEN tipo_movimiento = 'ENTRADA' THEN qty ELSE 0 END)
       - SUM(CASE WHEN tipo_movimiento IN ('SALIDA', 'SCRAP') THEN qty ELSE 0 END) AS stock_actual
     FROM pcb_inventory_scan_smd
     WHERE pcb_part_no = ?
     GROUP BY pcb_part_no, area, proceso
     HAVING initial_qty > 0 AND stock_actual > 0
     ORDER BY stock_actual DESC, initial_qty DESC
     LIMIT 1`,
    [pcbPartNo]
  );

  if (rows.length === 0) return null;
  return {
    pcb_part_no: rows[0].pcb_part_no,
    modelo: rows[0].modelo || 'N/A',
    area: rows[0].area,
    proceso: rows[0].proceso,
    available_stock: Number(rows[0].stock_actual || 0),
  };
}

const VALID_ARRAY_ROLES = ['SINGLE', 'DEFECT', 'ARRAY_ITEM'];

// ============================================
// POST /api/pcb-inventory/scan
// Acepta tipo_movimiento: ENTRADA | SALIDA | SCRAP
// Acepta area: INVENTARIO | REPARACION
// Acepta proceso: SMD | IMD | ASSY
// ============================================
exports.scan = async (req, res, next) => {
  let connection;
  try {
    const {
      scanned_code,
      inventory_date,
      proceso,
      area,
      tipo_movimiento,
      comentarios,
      scanned_by,
      array_count,
      qty,
      array_group_code,
      array_role,
      defect_type,
      component_location,
      manual_qty_confirmed
    } = req.body;

    if (!scanned_code || !scanned_code.trim()) {
      return res.status(400).json({
        success: false,
        message: 'scanned_code es requerido',
        code: 'MISSING_SCANNED_CODE'
      });
    }

    if (!proceso || !VALID_PROCESOS.includes(proceso)) {
      return res.status(400).json({
        success: false,
        message: `proceso es requerido y debe ser uno de: ${VALID_PROCESOS.join(', ')}`,
        code: 'INVALID_PROCESO'
      });
    }

    const areaVal = area || 'INVENTARIO';
    if (!VALID_AREAS.includes(areaVal)) {
      return res.status(400).json({
        success: false,
        message: `area debe ser uno de: ${VALID_AREAS.join(', ')}`,
        code: 'INVALID_AREA'
      });
    }

    const tipo = tipo_movimiento || 'ENTRADA';
    if (!VALID_TIPOS.includes(tipo)) {
      return res.status(400).json({
        success: false,
        message: `tipo_movimiento debe ser uno de: ${VALID_TIPOS.join(', ')}`,
        code: 'INVALID_TIPO_MOVIMIENTO'
      });
    }

    const arrayCount = parseArrayCount(array_count);
    if (arrayCount > 99) {
      return res.status(400).json({
        success: false,
        message: 'array_count no puede ser mayor a 99',
        code: 'INVALID_ARRAY_COUNT'
      });
    }

    const qtyVal = parseQty(qty);
    if (tipo === 'ENTRADA' && qtyVal > 99) {
      return res.status(400).json({
        success: false,
        message: 'qty no puede ser mayor a 99',
        code: 'INVALID_QTY'
      });
    }

    const parsed = parseScannedCode(scanned_code.trim());

    const parsedPartNo = parsePcbPartNo(parsed.pcb_part_no);
    if (!parsedPartNo) {
      return res.status(400).json({
        success: false,
        message: `El 3er token debe ser un EBR valido (formato EBR########). Recibido: "${parsed.pcb_part_no || ''}"`,
        code: 'INVALID_PCB_PART_NO'
      });
    }

    const invDate = inventory_date || new Date().toISOString().slice(0, 10);
    const scannedOriginal = scanned_code.trim();
    const scannedOriginalNorm = normalizeCode(scanned_code);
    const arrayGroupCode = normalizeCode(array_group_code || scannedOriginal);
    const roleVal = array_role || (arrayCount > 1 ? (areaVal === 'REPARACION' ? 'DEFECT' : 'ARRAY_ITEM') : 'SINGLE');
    const defectTypeVal = areaVal === 'REPARACION' && defect_type
      ? defect_type.toString().trim().toUpperCase()
      : null;
    const componentLocationVal = areaVal === 'REPARACION' && component_location
      ? component_location.toString().trim().toUpperCase()
      : null;
    if (!VALID_ARRAY_ROLES.includes(roleVal)) {
      return res.status(400).json({
        success: false,
        message: `array_role debe ser uno de: ${VALID_ARRAY_ROLES.join(', ')}`,
        code: 'INVALID_ARRAY_ROLE'
      });
    }

    connection = await pool.getConnection();
    await connection.beginTransaction();

    if (tipo === 'ENTRADA' && areaVal === 'REPARACION') {
      if (!defectTypeVal) {
        await connection.rollback();
        return res.status(400).json({
          success: false,
          message: 'defect_type es requerido para entradas de reparacion',
          code: 'MISSING_DEFECT_TYPE'
        });
      }

      const [defectRows] = await connection.query(
        `SELECT id
         FROM pcb_defect_catalog
         WHERE defect_name = ?
         AND is_active = 1
         LIMIT 1`,
        [defectTypeVal]
      );

      if (defectRows.length === 0) {
        await connection.rollback();
        return res.status(400).json({
          success: false,
          message: 'El defecto no existe en el catalogo activo',
          code: 'INVALID_DEFECT_TYPE'
        });
      }
    }

    let sourceForExit = null;
    let manualInitialStockOption = null;
    if (tipo !== 'ENTRADA') {
      const [sourceRows] = await connection.query(
        `SELECT entrada.*,
          entrada.qty - COALESCE((
            SELECT SUM(salida.qty)
            FROM pcb_inventory_scan_smd salida
            WHERE salida.scanned_original_norm = entrada.scanned_original_norm
            AND salida.area = entrada.area
            AND salida.proceso = entrada.proceso
            AND salida.tipo_movimiento IN ('SALIDA', 'SCRAP')
          ), 0) AS remaining_qty
         FROM pcb_inventory_scan_smd entrada
         WHERE entrada.tipo_movimiento = 'ENTRADA'
         AND entrada.scanned_original_norm = ?
         ORDER BY entrada.created_at DESC, entrada.id DESC
         LIMIT 1`,
        [scannedOriginalNorm]
      );

      const source = sourceRows[0];
      sourceForExit = source || null;
      if (source && source.array_group_code && Number(source.array_count || 1) > 1) {
        const [arrayEntries] = await connection.query(
          `SELECT *
           FROM pcb_inventory_scan_smd
           WHERE tipo_movimiento = 'ENTRADA'
           AND array_group_code = ?
           ORDER BY id`,
          [source.array_group_code]
        );

        const knownQty = arrayEntries.reduce((sum, row) => sum + Number(row.qty || 0), 0);
        const expectedQty = Number(source.array_count || knownQty);
        if (knownQty < expectedQty) {
          await connection.rollback();
          return res.status(409).json({
            success: false,
            message: `Array incompleto: registrados ${knownQty} de ${expectedQty}. Escanea todas las PCBs del array antes de dar salida.`,
            code: 'ARRAY_INCOMPLETE',
            known_qty: knownQty,
            expected_qty: expectedQty,
          });
        }

        const [outRows] = await connection.query(
          `SELECT scanned_original_norm, area, SUM(qty) AS out_qty
           FROM pcb_inventory_scan_smd
           WHERE array_group_code = ?
           AND tipo_movimiento IN ('SALIDA', 'SCRAP')
           GROUP BY scanned_original_norm, area`,
          [source.array_group_code]
        );
        const outByCodeArea = new Map(
          outRows.map(row => [`${row.scanned_original_norm}|${row.area}`, Number(row.out_qty || 0)])
        );

        const pendingRows = arrayEntries
          .map(row => {
            const key = `${row.scanned_original_norm}|${row.area}`;
            const remainingQty = Number(row.qty || 0) - (outByCodeArea.get(key) || 0);
            return { ...row, remaining_qty: remainingQty };
          })
          .filter(row => row.remaining_qty > 0);

        if (pendingRows.length === 0) {
          await connection.rollback();
          return res.status(409).json({
            success: false,
            message: 'Este array ya no tiene PCBs pendientes de salida',
            code: 'ARRAY_ALREADY_OUT',
          });
        }

        const insertedIds = [];
        const arrayComment = comentarios
          ? `${comentarios} | Salida de array por ${scannedOriginal}`
          : `Salida de array por ${scannedOriginal}`;
        for (const row of pendingRows) {
          const [result] = await connection.query(
            `INSERT INTO pcb_inventory_scan_smd
              (inventory_date, scanned_original, scanned_original_norm, assy_type, pcb_part_no, modelo, proceso, area, tipo_movimiento, qty, array_count, array_group_code, array_role, defect_type, component_location, comentarios, scanned_by)
             VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
            [
              invDate,
              row.scanned_original,
              row.scanned_original_norm,
              row.assy_type,
              row.pcb_part_no,
              row.modelo,
              row.proceso,
              row.area,
              tipo,
              row.remaining_qty,
              row.array_count,
              row.array_group_code,
              row.array_role,
              row.defect_type,
              row.component_location,
              arrayComment,
              scanned_by || null,
            ]
          );
          insertedIds.push(result.insertId);
        }

        const [inserted] = await connection.query(
          `SELECT *, DATE_FORMAT(created_at, '%Y-%m-%d %H:%i:%s') as created_at_fmt
           FROM pcb_inventory_scan_smd
           WHERE id IN (${insertedIds.map(() => '?').join(', ')})
           ORDER BY FIELD(id, ${insertedIds.map(() => '?').join(', ')})`,
          [...insertedIds, ...insertedIds]
        );

        await connection.commit();
        return res.json({
          success: true,
          data: inserted[0],
          rows: inserted,
          inserted_ids: insertedIds,
          total_qty: pendingRows.reduce((sum, row) => sum + Number(row.remaining_qty || 0), 0),
          array_exit: true,
          array_group_code: source.array_group_code,
          array_count: expectedQty,
        });
      }

      if (source) {
        const remainingQty = Number(source.remaining_qty || 0);
        if (remainingQty < qtyVal) {
          await connection.rollback();
          return res.status(409).json({
            success: false,
            message: `Este QR no tiene stock suficiente. Disponible: ${remainingQty}`,
            code: 'INSUFFICIENT_QR_STOCK',
            available_stock: remainingQty,
            pcb_part_no: source.pcb_part_no,
            area: source.area,
            proceso: source.proceso,
          });
        }
      } else if (manual_qty_confirmed === true) {
        const initialStockOption = await getInitialStockOption(connection, parsedPartNo);
        if (!initialStockOption || initialStockOption.available_stock < qtyVal) {
          await connection.rollback();
          return res.status(409).json({
            success: false,
            message: `Stock inicial insuficiente para ${parsedPartNo}. Disponible: ${initialStockOption?.available_stock || 0}`,
            code: 'INSUFFICIENT_STOCK',
            available_stock: initialStockOption?.available_stock || 0,
            requested_qty: qtyVal,
            pcb_part_no: parsedPartNo,
            area: initialStockOption?.area || null,
            proceso: initialStockOption?.proceso || null,
          });
        }
        manualInitialStockOption = initialStockOption;
      } else {
        const initialStockOption = await getInitialStockOption(connection, parsedPartNo);
        await connection.rollback();
        if (!initialStockOption) {
          return res.status(409).json({
            success: false,
            message: `El QR no existe y no hay inventario inicial disponible para ${parsedPartNo}.`,
            code: 'PCB_QR_NOT_IN_INVENTORY',
            pcb_part_no: parsedPartNo,
            modelo: await lookupModelo(parsedPartNo),
            available_stock: 0,
            manual_allowed: false,
          });
        }
        return res.status(409).json({
          success: false,
          message: `El QR no existe en inventario. Capture cantidad para dar salida por No. Parte ${parsedPartNo}.`,
          code: 'PCB_QR_NOT_IN_INVENTORY',
          pcb_part_no: parsedPartNo,
          modelo: initialStockOption.modelo,
          available_stock: initialStockOption.available_stock,
          area: initialStockOption.area,
          proceso: initialStockOption.proceso,
          manual_allowed: true,
          initial_stock_exit: true,
        });
      }
    }

    const movementArea = sourceForExit
      ? sourceForExit.area
      : (manualInitialStockOption ? manualInitialStockOption.area : areaVal);
    const movementProceso = sourceForExit
      ? sourceForExit.proceso
      : (manualInitialStockOption ? manualInitialStockOption.proceso : proceso);
    const movementModelo = sourceForExit
      ? sourceForExit.modelo
      : (manualInitialStockOption ? manualInitialStockOption.modelo : await lookupModelo(parsedPartNo));

    // Verificar duplicado por dia + codigo + tipo_movimiento + area
    const [existing] = await connection.query(
      `SELECT id, area FROM pcb_inventory_scan_smd
       WHERE inventory_date = ? AND scanned_original_norm = ? AND tipo_movimiento = ? AND area = ?`,
      [invDate, scannedOriginalNorm, tipo, movementArea]
    );

    if (existing.length > 0) {
      await connection.rollback();
      return res.status(409).json({
        success: false,
        message: `Este codigo ya fue registrado hoy como ${tipo} en area ${existing[0].area}`,
        code: 'DUPLICATE_SCAN',
        existing_id: existing[0].id
      });
    }

    const [result] = await connection.query(
      `INSERT INTO pcb_inventory_scan_smd
        (inventory_date, scanned_original, scanned_original_norm, assy_type, pcb_part_no, modelo, proceso, area, tipo_movimiento, qty, array_count, array_group_code, array_role, defect_type, component_location, comentarios, scanned_by)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
      [
        invDate,
        scannedOriginal,
        scannedOriginalNorm,
        parsed.assy_type,
        parsedPartNo,
        movementModelo,
        movementProceso,
        movementArea,
        tipo,
        qtyVal,
        arrayCount,
        arrayGroupCode,
        roleVal,
        defectTypeVal,
        componentLocationVal,
        comentarios || null,
        scanned_by || null,
      ]
    );
    const insertedIds = [result.insertId];

    const [inserted] = await connection.query(
      `SELECT *, DATE_FORMAT(created_at, '%Y-%m-%d %H:%i:%s') as created_at_fmt
       FROM pcb_inventory_scan_smd
       WHERE id = ?`,
      insertedIds
    );

    await connection.commit();

    res.json({
      success: true,
      data: inserted[0],
      rows: inserted,
      inserted_ids: insertedIds,
      total_qty: qtyVal,
    });

  } catch (err) {
    if (connection) {
      try {
        await connection.rollback();
      } catch (_) {}
    }
    next(err);
  } finally {
    if (connection) connection.release();
  }
};

// ============================================
// POST /api/pcb-inventory/initial-stock/bulk
// Carga inventario inicial por No. Parte + Cantidad, sin escaneo QR.
// ============================================
exports.bulkInitialStock = async (req, res, next) => {
  let connection;
  try {
    const {
      inventory_date,
      area,
      proceso,
      comentarios,
      scanned_by,
      items,
    } = req.body;

    const invDate = inventory_date || new Date().toISOString().slice(0, 10);
    const areaVal = area || 'INVENTARIO';
    if (!VALID_AREAS.includes(areaVal)) {
      return res.status(400).json({
        success: false,
        message: `area debe ser uno de: ${VALID_AREAS.join(', ')}`,
        code: 'INVALID_AREA',
      });
    }

    if (!proceso || !VALID_PROCESOS.includes(proceso)) {
      return res.status(400).json({
        success: false,
        message: `proceso es requerido y debe ser uno de: ${VALID_PROCESOS.join(', ')}`,
        code: 'INVALID_PROCESO',
      });
    }

    if (!Array.isArray(items) || items.length === 0) {
      return res.status(400).json({
        success: false,
        message: 'items es requerido',
        code: 'MISSING_ITEMS',
      });
    }

    const errors = [];
    const grouped = new Map();
    items.forEach((item, index) => {
      const rowNumber = Number(item?.row_number || index + 2);
      const partNo = parsePcbPartNo(item?.pcb_part_no);
      const qtyVal = parseStrictQty(item?.qty);

      if (!partNo) {
        errors.push({
          row: rowNumber,
          pcb_part_no: item?.pcb_part_no || '',
          message: 'No. Parte PCB invalido (esperado EBR########)',
          code: 'INVALID_PCB_PART_NO',
        });
        return;
      }

      if (!qtyVal) {
        errors.push({
          row: rowNumber,
          pcb_part_no: partNo,
          message: 'Cantidad invalida',
          code: 'INVALID_QTY',
        });
        return;
      }

      grouped.set(partNo, (grouped.get(partNo) || 0) + qtyVal);
    });

    if (grouped.size === 0) {
      return res.status(400).json({
        success: false,
        message: 'No hay filas validas para importar',
        code: 'NO_VALID_ROWS',
        rows_received: items.length,
        valid_rows: 0,
        inserted: 0,
        total_qty: 0,
        errors,
      });
    }

    connection = await pool.getConnection();
    await connection.beginTransaction();

    const insertedIds = [];
    const nowToken = Date.now();
    const initialComment = comentarios && comentarios.toString().trim()
      ? `Inventario inicial | ${comentarios.toString().trim()}`
      : 'Inventario inicial';
    const groupedEntries = Array.from(grouped.entries());
    const modeloMap = await lookupModelosBatch(
      connection,
      groupedEntries.map(([partNo]) => partNo)
    );

    const chunkSize = 250;
    for (let offset = 0; offset < groupedEntries.length; offset += chunkSize) {
      const chunk = groupedEntries.slice(offset, offset + chunkSize);
      const values = [];
      const placeholders = [];

      chunk.forEach(([partNo, qtyVal], index) => {
        const insertIndex = offset + index + 1;
        const scannedOriginal = `INITIAL:${partNo}:${nowToken}:${insertIndex}`;
        placeholders.push('(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)');
        values.push(
          invDate,
          scannedOriginal,
          normalizeCode(scannedOriginal),
          null,
          partNo,
          modeloMap.get(partNo) || 'N/A',
          proceso,
          areaVal,
          'ENTRADA',
          qtyVal,
          1,
          normalizeCode(scannedOriginal),
          'SINGLE',
          null,
          null,
          initialComment,
          scanned_by || null,
        );
      });

      const [result] = await connection.query(
        `INSERT INTO pcb_inventory_scan_smd
          (inventory_date, scanned_original, scanned_original_norm, assy_type, pcb_part_no, modelo, proceso, area, tipo_movimiento, qty, array_count, array_group_code, array_role, defect_type, component_location, comentarios, scanned_by)
         VALUES ${placeholders.join(', ')}`,
        values
      );

      const firstInsertId = Number(result.insertId || 0);
      const affectedRows = Number(result.affectedRows || 0);
      for (let i = 0; i < affectedRows; i += 1) {
        insertedIds.push(firstInsertId + i);
      }
    }

    await connection.commit();

    return res.json({
      success: true,
      message: 'Inventario inicial importado',
      rows_received: items.length,
      valid_rows: items.length - errors.length,
      grouped_rows: grouped.size,
      inserted: insertedIds.length,
      inserted_ids: insertedIds,
      total_qty: Array.from(grouped.values()).reduce((sum, qtyVal) => sum + qtyVal, 0),
      errors,
    });
  } catch (err) {
    if (connection) {
      try {
        await connection.rollback();
      } catch (_) {}
    }
    next(err);
  } finally {
    if (connection) connection.release();
  }
};

// ============================================
// GET /api/pcb-inventory/summary
// Filtra por tipo_movimiento (ENTRADA, SALIDA, SCRAP) y opcionalmente por area
// ============================================
exports.getSummary = async (req, res, next) => {
  try {
    const { inventory_date, proceso, area, tipo_movimiento } = req.query;

    if (!inventory_date) {
      return res.status(400).json({
        success: false,
        message: 'inventory_date es requerido'
      });
    }

    const tipo = tipo_movimiento || 'ENTRADA';

    let query = `
      SELECT
        pcb_part_no,
        modelo,
        proceso,
        area,
        SUM(qty) as qty
      FROM pcb_inventory_scan_smd
      WHERE inventory_date = ? AND tipo_movimiento = ?
    `;
    const params = [inventory_date, tipo];

    if (proceso && proceso !== 'ALL') {
      query += ` AND proceso = ?`;
      params.push(proceso);
    }
    if (area && area !== 'ALL') {
      query += ` AND area = ?`;
      params.push(area);
    }

    query += ` GROUP BY pcb_part_no, modelo, proceso, area ORDER BY pcb_part_no, proceso`;

    const [rows] = await pool.query(query, params);

    res.json({
      success: true,
      data: rows,
      total: rows.reduce((sum, r) => sum + Number(r.qty || 0), 0)
    });

  } catch (err) {
    next(err);
  }
};

// ============================================
// GET /api/pcb-inventory/scans
// Filtra por tipo_movimiento (ENTRADA, SALIDA, SCRAP) y opcionalmente por area
// ============================================
exports.getScans = async (req, res, next) => {
  try {
    const { inventory_date, proceso, area, tipo_movimiento, limit } = req.query;

    if (!inventory_date) {
      return res.status(400).json({
        success: false,
        message: 'inventory_date es requerido'
      });
    }

    const tipo = tipo_movimiento || 'ENTRADA';
    const maxLimit = Math.min(parseInt(limit) || 300, 5000);

    let query = `
      SELECT
        id,
        inventory_date,
        scanned_original,
        assy_type,
        pcb_part_no,
        modelo,
        proceso,
        area,
        tipo_movimiento,
        qty,
        array_count,
        array_group_code,
        array_role,
        defect_type,
        component_location,
        comentarios,
        scanned_by,
        created_at,
        DATE_FORMAT(created_at, '%Y-%m-%d %H:%i:%s') as created_at_fmt,
        DATE_FORMAT(created_at, '%H:%i:%s') as hora
      FROM pcb_inventory_scan_smd
      WHERE inventory_date = ? AND tipo_movimiento = ?
    `;
    const params = [inventory_date, tipo];

    if (proceso && proceso !== 'ALL') {
      query += ` AND proceso = ?`;
      params.push(proceso);
    }
    if (area && area !== 'ALL') {
      query += ` AND area = ?`;
      params.push(area);
    }

    query += ` ORDER BY created_at DESC LIMIT ?`;
    params.push(maxLimit);

    const [rows] = await pool.query(query, params);

    res.json({
      success: true,
      data: rows,
      count: rows.length
    });

  } catch (err) {
    next(err);
  }
};

// ============================================
// GET /api/pcb-inventory/stock-summary
// Inventario actual computado: entradas - salidas - scrap
// Agrupado tambien por area
// ============================================
exports.getStockSummary = async (req, res, next) => {
  try {
    const { numero_parte, area, proceso, include_zero_stock, fecha_inicio, fecha_fin } = req.query;

    let dateFilter = '';
    const params = [];

    if (fecha_inicio && fecha_fin) {
      dateFilter = 'AND inventory_date BETWEEN ? AND ?';
      params.push(fecha_inicio, fecha_fin);
    }

    let partFilter = '';
    if (numero_parte && numero_parte.trim()) {
      partFilter = 'AND pcb_part_no LIKE ?';
      params.push(`%${numero_parte.trim()}%`);
    }

    let areaFilter = '';
    if (area && area !== 'ALL') {
      areaFilter = 'AND area = ?';
      params.push(area);
    }

    let procesoFilter = '';
    if (proceso && proceso !== 'ALL') {
      procesoFilter = 'AND proceso = ?';
      params.push(proceso);
    }

    const query = `
      SELECT
        pcb_part_no,
        modelo,
        proceso,
        area,
        SUM(CASE WHEN tipo_movimiento = 'ENTRADA' THEN qty ELSE 0 END) AS total_entrada,
        SUM(CASE WHEN tipo_movimiento = 'SALIDA'  THEN qty ELSE 0 END) AS total_salida,
        SUM(CASE WHEN tipo_movimiento = 'SCRAP'   THEN qty ELSE 0 END) AS total_scrap,
        SUM(CASE WHEN tipo_movimiento = 'ENTRADA' THEN qty ELSE 0 END)
          - SUM(CASE WHEN tipo_movimiento = 'SALIDA' THEN qty ELSE 0 END)
          - SUM(CASE WHEN tipo_movimiento = 'SCRAP'  THEN qty ELSE 0 END) AS stock_actual
      FROM pcb_inventory_scan_smd
      WHERE 1=1 ${dateFilter} ${partFilter} ${areaFilter} ${procesoFilter}
      GROUP BY pcb_part_no, modelo, proceso, area
      ${include_zero_stock === 'true' ? '' : 'HAVING stock_actual > 0'}
      ORDER BY pcb_part_no, proceso, area
    `;

    const [rows] = await pool.query(query, params);

    res.json({
      success: true,
      data: rows,
      total_rows: rows.length,
      total_stock: rows.reduce((sum, r) => sum + Number(r.stock_actual || 0), 0),
    });
  } catch (err) {
    next(err);
  }
};

// ============================================
// GET /api/pcb-inventory/stock-detail
// Detalle de todos los movimientos para inventario
// ============================================
exports.getStockDetail = async (req, res, next) => {
  try {
    const { numero_parte, area, proceso, include_zero_stock, fecha_inicio, fecha_fin, limit } = req.query;
    const maxLimit = Math.min(parseInt(limit) || 2000, 10000);

    let dateFilter = '';
    const params = [];

    if (fecha_inicio && fecha_fin) {
      dateFilter = 'AND inventory_date BETWEEN ? AND ?';
      params.push(fecha_inicio, fecha_fin);
    }

    let partFilter = '';
    if (numero_parte && numero_parte.trim()) {
      partFilter = 'AND pcb_part_no LIKE ?';
      params.push(`%${numero_parte.trim()}%`);
    }

    let areaFilter = '';
    if (area && area !== 'ALL') {
      areaFilter = 'AND area = ?';
      params.push(area);
    }

    let procesoFilter = '';
    if (proceso && proceso !== 'ALL') {
      procesoFilter = 'AND proceso = ?';
      params.push(proceso);
    }

    params.push(maxLimit);

    const query = `
      SELECT
        id,
        inventory_date,
        scanned_original,
        assy_type,
        pcb_part_no,
        modelo,
        proceso,
        area,
        tipo_movimiento,
        qty,
        array_count,
        array_group_code,
        array_role,
        defect_type,
        component_location,
        comentarios,
        scanned_by,
        created_at,
        DATE_FORMAT(created_at, '%Y-%m-%d %H:%i:%s') as created_at_fmt,
        DATE_FORMAT(created_at, '%H:%i:%s') as hora
      FROM pcb_inventory_scan_smd
      WHERE 1=1 ${dateFilter} ${partFilter} ${areaFilter} ${procesoFilter}
      ORDER BY created_at DESC
      LIMIT ?
    `;

    const [rows] = await pool.query(query, params);

    res.json({
      success: true,
      data: rows,
      count: rows.length,
    });
  } catch (err) {
    next(err);
  }
};

// ============================================
// DELETE /api/pcb-inventory/scan/:id
// ============================================
exports.deleteScan = async (req, res, next) => {
  try {
    const { id } = req.params;

    const [result] = await pool.query(
      `DELETE FROM pcb_inventory_scan_smd WHERE id = ?`,
      [id]
    );

    if (result.affectedRows === 0) {
      return res.status(404).json({
        success: false,
        message: 'Escaneo no encontrado'
      });
    }

    res.json({
      success: true,
      message: 'Escaneo eliminado'
    });

  } catch (err) {
    next(err);
  }
};
