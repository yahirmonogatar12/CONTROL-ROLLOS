/**
 * PCB Inventory Controller - Inventario de PCBs por escaneo
 * Soporta 3 tipos de movimiento: ENTRADA, SALIDA, SCRAP
 * Soporta 3 areas: INVENTARIO, INVENTARIO_REPARACION, REPARACION
 * Soporta 3 procesos: SMD, IMD, ASSY
 * Pantalla Flutter: lib/screens/pcb_inventory/
 */

const crypto = require('node:crypto');
const { pool } = require('../config/database');

// ============================================
// HELPERS
// ============================================

function pad2(value) {
  return value.toString().padStart(2, '0');
}

function formatLocalDateTime(date = new Date()) {
  return `${date.getFullYear()}-${pad2(date.getMonth() + 1)}-${pad2(date.getDate())} `
    + `${pad2(date.getHours())}:${pad2(date.getMinutes())}:${pad2(date.getSeconds())}`;
}

function getLocalDate() {
  return formatLocalDateTime().slice(0, 10);
}

function normalizeClientDateTime(value) {
  if (!value) return null;
  const text = value.toString().trim();
  const match = text.match(
    /^(\d{4})-(\d{2})-(\d{2})[ T](\d{2}):(\d{2}):(\d{2})(?:\.\d+)?(?:Z|[+-]\d{2}:?\d{2})?$/
  );
  if (!match) return null;

  const [, year, month, day, hour, minute, second] = match;
  const candidate = new Date(
    Number(year),
    Number(month) - 1,
    Number(day),
    Number(hour),
    Number(minute),
    Number(second)
  );

  if (
    candidate.getFullYear() !== Number(year)
    || candidate.getMonth() + 1 !== Number(month)
    || candidate.getDate() !== Number(day)
    || candidate.getHours() !== Number(hour)
    || candidate.getMinutes() !== Number(minute)
    || candidate.getSeconds() !== Number(second)
  ) {
    return null;
  }

  return `${year}-${month}-${day} ${hour}:${minute}:${second}`;
}

function normalizeCode(code) {
  return (code || '').trim().toUpperCase().replace(/\s+/g, '');
}

function getEntryLockName(scannedOriginalNorm) {
  const hash = crypto
    .createHash('sha256')
    .update(scannedOriginalNorm)
    .digest('hex')
    .slice(0, 48);
  return `pcb-entry:${hash}`;
}

function getEquivalentNormalizedCodes(scannedOriginalNorm) {
  const canonical = scannedOriginalNorm.replace(/;+$/, '');
  return [canonical, `${canonical};`];
}

function parseScannedCode(code) {
  const parts = code.split(';').map(s => s.trim()).filter(Boolean);
  const normalizedParts = parts.map(part => part.toUpperCase());

  // Formato 2 (igual que Control_produccion): barcode continuo, ej. EBR86093798922509201401.
  // No. parte = EBR + 8 digitos al inicio.
  const ebrMatch = parts.length === 1 && normalizedParts[0].match(/^(EBR\d{8})(.*)$/);
  if (ebrMatch) {
    return {
      token0: null,
      assy_type: null,
      pcb_part_no: ebrMatch[1],
      token3: ebrMatch[2] || null,
    };
  }

  // Formato 1: QR con ';' (TOKEN0;ASSY_TYPE;PART_NO;TOKEN3)
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
const VALID_AREAS = ['INVENTARIO', 'INVENTARIO_REPARACION', 'REPARACION'];
const VALID_TIPOS = ['ENTRADA', 'SALIDA', 'SCRAP'];

function isRepairArea(area) {
  return area === 'INVENTARIO_REPARACION' || area === 'REPARACION';
}

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

async function getInitialStockOptions(connection, pcbPartNo) {
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
     ORDER BY proceso, area, stock_actual DESC, initial_qty DESC`,
    [pcbPartNo]
  );

  return rows.map(row => ({
    pcb_part_no: row.pcb_part_no,
    modelo: row.modelo || 'N/A',
    area: row.area,
    proceso: row.proceso,
    initial_qty: Number(row.initial_qty || 0),
    available_stock: Number(row.stock_actual || 0),
  }));
}

async function getInitialStockOption(connection, pcbPartNo, preferredArea, preferredProceso) {
  const options = await getInitialStockOptions(connection, pcbPartNo);
  if (options.length === 0) return null;
  if (preferredArea && preferredProceso) {
    return options.find(option =>
      option.area === preferredArea && option.proceso === preferredProceso
    ) || null;
  }
  return options[0];
}

const VALID_ARRAY_ROLES = ['SINGLE', 'DEFECT', 'ARRAY_ITEM'];
const VALID_ETAPAS = ['LQC', 'OQC', 'AIS'];

function normalizeOptional(value, { upper = false } = {}) {
  if (value === null || value === undefined) return null;
  const text = value.toString().trim();
  if (!text) return null;
  return upper ? text.toUpperCase() : text;
}

function normalizeDefectsPayload({
  defects,
  defectType,
  componentLocation,
  etapaDeteccion,
  defectSourceArea,
  defectDataId,
  repairArea,
}) {
  if (!repairArea) return [];

  const candidates = Array.isArray(defects) && defects.length > 0
    ? defects
    : [{
      defect_type: defectType,
      component_location: componentLocation,
      etapa_deteccion: etapaDeteccion,
      defect_source_area: defectSourceArea,
      defect_data_id: defectDataId,
    }];

  return candidates.map((item, index) => ({
    sort_order: index + 1,
    defect_type: normalizeOptional(item?.defect_type ?? item?.defect_name, { upper: true }),
    component_location: normalizeOptional(item?.component_location, { upper: true }),
    etapa_deteccion: normalizeOptional(item?.etapa_deteccion, { upper: true }),
    defect_source_area: normalizeOptional(item?.defect_source_area),
    defect_data_id: normalizeOptional(item?.defect_data_id),
  }));
}

async function getEntryDefects(connection, entryScanId) {
  if (!entryScanId) return [];
  const [rows] = await connection.query(
    `SELECT id, entry_scan_id, exit_scan_id, sort_order, defect_type,
            component_location, etapa_deteccion, defect_source_area,
            defect_data_id, repair_status, repaired_at
     FROM pcb_inventory_scan_defects_smd
     WHERE entry_scan_id = ?
     ORDER BY sort_order, id`,
    [entryScanId]
  );
  return rows;
}

async function insertEntryDefects(connection, entryScanId, defects) {
  if (!entryScanId || defects.length === 0) return [];
  const placeholders = defects.map(() => '(?, ?, ?, ?, ?, ?, ?, ?)').join(', ');
  const values = [];
  for (const defect of defects) {
    values.push(
      entryScanId,
      defect.sort_order,
      defect.defect_type,
      defect.component_location,
      defect.etapa_deteccion,
      defect.defect_source_area,
      defect.defect_data_id,
      'PENDING'
    );
  }
  await connection.query(
    `INSERT INTO pcb_inventory_scan_defects_smd
      (entry_scan_id, sort_order, defect_type, component_location,
       etapa_deteccion, defect_source_area, defect_data_id, repair_status)
     VALUES ${placeholders}`,
    values
  );
  await connection.query(
    `UPDATE pcb_inventory_scan_smd
     SET defect_count = ?, source_entry_id = NULL
     WHERE id = ?`,
    [defects.length, entryScanId]
  );
  return getEntryDefects(connection, entryScanId);
}

async function ensureLegacyEntryDefects(connection, entryRow) {
  if (!entryRow?.id || !isRepairArea(entryRow.area)) return [];
  const existing = await getEntryDefects(connection, entryRow.id);
  if (existing.length > 0) return existing;
  if (!entryRow.defect_type) return [];

  return insertEntryDefects(connection, entryRow.id, [{
    sort_order: 1,
    defect_type: normalizeOptional(entryRow.defect_type, { upper: true }),
    component_location: normalizeOptional(entryRow.component_location, { upper: true }),
    etapa_deteccion: normalizeOptional(entryRow.etapa_deteccion, { upper: true }),
    defect_source_area: normalizeOptional(entryRow.defect_source_area),
    defect_data_id: normalizeOptional(entryRow.defect_data_id),
  }]);
}

async function closeEntryDefects(connection, entryScanId, exitScanId, movementType, closedAt) {
  if (!entryScanId) return [];
  const repairStatus = movementType === 'SALIDA' ? 'REPAIRED' : 'SCRAPPED';
  await connection.query(
    `UPDATE pcb_inventory_scan_defects_smd
     SET exit_scan_id = ?, repair_status = ?, repaired_at = ?
     WHERE entry_scan_id = ? AND repair_status = 'PENDING'`,
    [exitScanId, repairStatus, closedAt, entryScanId]
  );
  return getEntryDefects(connection, entryScanId);
}

function summarizeDefects(defects) {
  return defects.map(defect => defect.defect_type).filter(Boolean).join(', ');
}

function buildPreviousRepairData(cycle, defects = []) {
  if (!cycle) return null;

  const repairedDefects = defects.length > 0
    ? defects
    : (cycle.defect_type
      ? [{
        sort_order: 1,
        defect_type: cycle.defect_type,
        component_location: cycle.component_location || null,
        etapa_deteccion: cycle.etapa_deteccion || null,
        defect_source_area: cycle.defect_source_area || null,
        repaired_at: cycle.repaired_at || null,
      }]
      : []);

  return {
    entry_scan_id: cycle.entry_scan_id || null,
    exit_scan_id: cycle.exit_scan_id,
    scanned_original: cycle.scanned_original,
    pcb_part_no: cycle.pcb_part_no,
    modelo: cycle.modelo,
    repair_area: cycle.repair_area || null,
    repaired_at: cycle.repaired_at,
    defects: repairedDefects,
  };
}

// ============================================
// POST /api/pcb-inventory/scan
// Acepta tipo_movimiento: ENTRADA | SALIDA | SCRAP
// Acepta area: INVENTARIO | INVENTARIO_REPARACION | REPARACION
// Acepta proceso: SMD | IMD | ASSY
// ============================================
exports.scan = async (req, res, next) => {
  let connection;
  let entryLockName;
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
      etapa_deteccion,
      defect_source_area,
      defect_data_id,
      defects,
      manual_qty_confirmed,
      initial_stock_area,
      initial_stock_proceso,
      created_at
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
    const initialStockAreaVal = initial_stock_area
      ? initial_stock_area.toString().trim().toUpperCase()
      : null;
    if (initialStockAreaVal && !VALID_AREAS.includes(initialStockAreaVal)) {
      return res.status(400).json({
        success: false,
        message: `initial_stock_area debe ser uno de: ${VALID_AREAS.join(', ')}`,
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
    const initialStockProcesoVal = initial_stock_proceso
      ? initial_stock_proceso.toString().trim().toUpperCase()
      : null;
    if (initialStockProcesoVal && !VALID_PROCESOS.includes(initialStockProcesoVal)) {
      return res.status(400).json({
        success: false,
        message: `initial_stock_proceso debe ser uno de: ${VALID_PROCESOS.join(', ')}`,
        code: 'INVALID_PROCESO'
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
        message: `Codigo invalido: se espera QR con EBR en el 3er token o barcode que inicie con EBR########. Recibido: "${parsed.pcb_part_no || scanned_code.trim()}"`,
        code: 'INVALID_PCB_PART_NO'
      });
    }

    const invDate = inventory_date || getLocalDate();
    const createdAt = normalizeClientDateTime(created_at) || formatLocalDateTime();
    const scannedOriginal = scanned_code.trim();
    const scannedOriginalNorm = normalizeCode(scanned_code);
    const arrayGroupCode = normalizeCode(array_group_code || scannedOriginal);
    const repairArea = isRepairArea(areaVal);
    const roleVal = array_role || (arrayCount > 1 ? (repairArea ? 'DEFECT' : 'ARRAY_ITEM') : 'SINGLE');
    const defectItems = normalizeDefectsPayload({
      defects,
      defectType: defect_type,
      componentLocation: component_location,
      etapaDeteccion: etapa_deteccion,
      defectSourceArea: defect_source_area,
      defectDataId: defect_data_id,
      repairArea,
    });
    for (const defect of defectItems) {
      if (defect.etapa_deteccion && !VALID_ETAPAS.includes(defect.etapa_deteccion)) {
        return res.status(400).json({
          success: false,
          message: `etapa_deteccion debe ser uno de: ${VALID_ETAPAS.join(', ')}`,
          code: 'INVALID_ETAPA_DETECCION'
        });
      }
    }
    if (!VALID_ARRAY_ROLES.includes(roleVal)) {
      return res.status(400).json({
        success: false,
        message: `array_role debe ser uno de: ${VALID_ARRAY_ROLES.join(', ')}`,
        code: 'INVALID_ARRAY_ROLE'
      });
    }

    connection = await pool.getConnection();
    await connection.beginTransaction();

    entryLockName = getEntryLockName(scannedOriginalNorm);
    const [lockRows] = await connection.query(
      'SELECT GET_LOCK(?, 5) AS acquired',
      [entryLockName]
    );

    if (Number(lockRows[0]?.acquired) !== 1) {
      await connection.rollback();
      return res.status(409).json({
        success: false,
        message: 'Otra captura de esta PCB esta en proceso. Intente nuevamente.',
        code: 'PCB_SCAN_BUSY',
      });
    }

    if (tipo === 'ENTRADA') {
      const equivalentCodes = getEquivalentNormalizedCodes(scannedOriginalNorm);
      const [balanceRows] = await connection.query(
        `SELECT area, proceso, SUM(
           CASE WHEN tipo_movimiento = 'ENTRADA' THEN qty
                WHEN tipo_movimiento IN ('SALIDA', 'SCRAP') THEN -qty
                ELSE 0 END
         ) AS remaining_qty
         FROM pcb_inventory_scan_smd
         WHERE scanned_original_norm IN (?, ?)
         GROUP BY area, proceso
         HAVING remaining_qty > 0`,
        equivalentCodes
      );
      const remainingQty = balanceRows.reduce(
        (sum, row) => sum + Number(row.remaining_qty || 0),
        0
      );

      if (remainingQty > 0) {
        const [latestEntries] = await connection.query(
          `SELECT id, inventory_date, area, proceso, array_group_code, created_at
           FROM pcb_inventory_scan_smd
           WHERE tipo_movimiento = 'ENTRADA'
           AND scanned_original_norm IN (?, ?)
           ORDER BY created_at DESC, id DESC
           LIMIT 1`,
          equivalentCodes
        );
        const latestEntry = latestEntries[0] || {};

        await connection.rollback();
        return res.status(409).json({
          success: false,
          message: `Esta PCB ya tiene una entrada activa. Stock pendiente: ${remainingQty}`,
          code: 'PCB_ALREADY_IN_INVENTORY',
          existing_id: latestEntry.id || null,
          available_stock: remainingQty,
          inventory_date: latestEntry.inventory_date || null,
          area: latestEntry.area || null,
          proceso: latestEntry.proceso || null,
          array_group_code: latestEntry.array_group_code || null,
        });
      }
    }

    if (tipo === 'ENTRADA' && repairArea) {
      if (defectItems.length === 0 || defectItems.some(defect => !defect.defect_type)) {
        await connection.rollback();
        return res.status(400).json({
          success: false,
          message: 'Todos los defectos son requeridos para entradas de reparacion',
          code: 'MISSING_DEFECT_TYPE'
        });
      }

      const catalogNames = [...new Set(
        defectItems
          .filter(defect => !defect.defect_data_id)
          .map(defect => defect.defect_type)
      )];
      if (catalogNames.length > 0) {
        const placeholders = catalogNames.map(() => '?').join(', ');
        const [defectRows] = await connection.query(
          `SELECT UPPER(defect_name) AS defect_name
           FROM pcb_defect_catalog
           WHERE UPPER(defect_name) IN (${placeholders})
           AND is_active = 1`,
          catalogNames
        );
        const activeNames = new Set(defectRows.map(row => row.defect_name));
        const invalidName = catalogNames.find(name => !activeNames.has(name));
        if (invalidName) {
          await connection.rollback();
          return res.status(400).json({
            success: false,
            message: `El defecto no existe en el catalogo activo: ${invalidName}`,
            code: 'INVALID_DEFECT_TYPE'
          });
        }
      }
    }

    let sourceForExit = null;
    let manualInitialStockOption = null;
    if (tipo !== 'ENTRADA') {
      // ponytail: remaining = balance agregado del area (todas las entradas - todas las salidas),
      // no entrada.qty - salidas. Lo segundo restaba salidas viejas ya consumidas a una
      // entrada nueva y daba "stock insuficiente" con stock real disponible.
      const [sourceRows] = await connection.query(
        `SELECT entrada.*,
          (
            SELECT COALESCE(SUM(CASE WHEN mov.tipo_movimiento = 'ENTRADA' THEN mov.qty
                                     WHEN mov.tipo_movimiento IN ('SALIDA', 'SCRAP') THEN -mov.qty
                                     ELSE 0 END), 0)
            FROM pcb_inventory_scan_smd mov
            WHERE mov.scanned_original_norm = entrada.scanned_original_norm
            AND mov.area = entrada.area
            AND mov.proceso = entrada.proceso
          ) AS remaining_qty
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
        const arrayWasIncomplete = knownQty < expectedQty;
        const closedArrayCount = arrayWasIncomplete ? knownQty : expectedQty;
        if (arrayWasIncomplete) {
          // Cerrar el array con las PCB realmente vinculadas para poder dar
          // salida a todas las capturadas, aunque faltaran escaneos.
          await connection.query(
            `UPDATE pcb_inventory_scan_smd
             SET array_count = ?,
                 array_role = CASE WHEN ? = 1 THEN 'SINGLE' ELSE array_role END
             WHERE tipo_movimiento = 'ENTRADA'
             AND array_group_code = ?`,
            [closedArrayCount, closedArrayCount, source.array_group_code]
          );
          source.array_count = closedArrayCount;
          if (closedArrayCount === 1) source.array_role = 'SINGLE';
          for (const row of arrayEntries) {
            row.array_count = closedArrayCount;
            if (closedArrayCount === 1) row.array_role = 'SINGLE';
          }
        }

        // ponytail: mismo criterio que la salida simple: balance real por QR+area+proceso
        // sobre la entrada mas reciente de cada llave. Restar salidas a cada entrada
        // mezclaba ciclos viejos del mismo group code (entro SINGLE, salio, volvio a
        // entrar como array) y daba "sin stock" con stock disponible.
        const [balanceRows] = await connection.query(
          `SELECT scanned_original_norm, area, proceso, SUM(
             CASE WHEN tipo_movimiento = 'ENTRADA' THEN qty
                  WHEN tipo_movimiento IN ('SALIDA', 'SCRAP') THEN -qty
                  ELSE 0 END
           ) AS remaining_qty
           FROM pcb_inventory_scan_smd
           WHERE scanned_original_norm IN (?)
           GROUP BY scanned_original_norm, area, proceso`,
          [[...new Set(arrayEntries.map(row => row.scanned_original_norm))]]
        );
        const movementKey = row => `${row.scanned_original_norm}|${row.area}|${row.proceso}`;
        const balanceByKey = new Map(
          balanceRows.map(row => [movementKey(row), Number(row.remaining_qty || 0)])
        );
        const latestEntryByKey = new Map(arrayEntries.map(row => [movementKey(row), row]));

        const pendingRows = [...latestEntryByKey.values()]
          .map(row => ({ ...row, remaining_qty: balanceByKey.get(movementKey(row)) || 0 }))
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
        const repairedDefects = [];
        const arrayComment = comentarios
          ? `${comentarios} | Salida de array por ${scannedOriginal}`
          : `Salida de array por ${scannedOriginal}`;
        for (const row of pendingRows) {
          const rowDefects = await ensureLegacyEntryDefects(connection, row);
          const firstDefect = rowDefects[0] || null;
          const sourceEntryId = isRepairArea(row.area) ? row.id : null;
          const [result] = await connection.query(
            `INSERT INTO pcb_inventory_scan_smd
              (inventory_date, scanned_original, scanned_original_norm, assy_type,
               pcb_part_no, modelo, proceso, area, tipo_movimiento, qty,
               array_count, array_group_code, array_role, defect_type,
               component_location, etapa_deteccion, defect_source_area,
               defect_data_id, source_entry_id, defect_count, comentarios,
               scanned_by, created_at)
             VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
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
              firstDefect?.defect_type || row.defect_type,
              firstDefect?.component_location || row.component_location,
              firstDefect?.etapa_deteccion || row.etapa_deteccion,
              firstDefect?.defect_source_area || row.defect_source_area,
              firstDefect?.defect_data_id || row.defect_data_id,
              sourceEntryId,
              rowDefects.length,
              arrayComment,
              scanned_by || null,
              createdAt,
            ]
          );
          insertedIds.push(result.insertId);
          if (sourceEntryId) {
            const closed = await closeEntryDefects(
              connection,
              sourceEntryId,
              result.insertId,
              tipo,
              createdAt
            );
            repairedDefects.push(...closed);
          }
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
          array_count: closedArrayCount,
          expected_array_count: expectedQty,
          array_closed_incomplete: arrayWasIncomplete,
          repaired_defects: tipo === 'SALIDA' ? repairedDefects : [],
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
        const initialStockOption = await getInitialStockOption(
          connection,
          parsedPartNo,
          initialStockAreaVal,
          initialStockProcesoVal
        );
        if (!initialStockOption || initialStockOption.available_stock < qtyVal) {
          const stockOptions = await getInitialStockOptions(connection, parsedPartNo);
          await connection.rollback();
          return res.status(409).json({
            success: false,
            message: `Stock inicial insuficiente para ${parsedPartNo}. Disponible: ${initialStockOption?.available_stock || 0}`,
            code: 'INSUFFICIENT_STOCK',
            available_stock: initialStockOption?.available_stock || 0,
            requested_qty: qtyVal,
            pcb_part_no: parsedPartNo,
            area: initialStockOption?.area || initialStockAreaVal || null,
            proceso: initialStockOption?.proceso || initialStockProcesoVal || null,
            stock_options: stockOptions,
          });
        }
        manualInitialStockOption = initialStockOption;
      } else {
        const stockOptions = await getInitialStockOptions(connection, parsedPartNo);
        const initialStockOption = stockOptions[0] || null;
        await connection.rollback();
        if (!initialStockOption) {
          return res.status(409).json({
            success: false,
            message: `El QR no existe y no hay inventario inicial disponible para ${parsedPartNo}.`,
            code: 'PCB_QR_NOT_IN_INVENTORY',
            pcb_part_no: parsedPartNo,
            modelo: await lookupModelo(parsedPartNo),
            available_stock: 0,
            stock_options: [],
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
          stock_options: stockOptions,
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
    const sourceDefects = tipo !== 'ENTRADA' && sourceForExit
      ? await ensureLegacyEntryDefects(connection, sourceForExit)
      : [];
    const movementDefects = tipo === 'ENTRADA' ? defectItems : sourceDefects;
    const movementPrimaryDefect = movementDefects[0] || null;
    const sourceEntryId = tipo !== 'ENTRADA' && sourceForExit
      && isRepairArea(sourceForExit.area)
      ? sourceForExit.id
      : null;

    const [result] = await connection.query(
      `INSERT INTO pcb_inventory_scan_smd
        (inventory_date, scanned_original, scanned_original_norm, assy_type,
         pcb_part_no, modelo, proceso, area, tipo_movimiento, qty, array_count,
         array_group_code, array_role, defect_type, component_location,
         etapa_deteccion, defect_source_area, defect_data_id, source_entry_id,
         defect_count, comentarios, scanned_by, created_at)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
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
        movementPrimaryDefect?.defect_type || null,
        movementPrimaryDefect?.component_location || null,
        movementPrimaryDefect?.etapa_deteccion || null,
        movementPrimaryDefect?.defect_source_area || null,
        movementPrimaryDefect?.defect_data_id || null,
        sourceEntryId,
        movementDefects.length,
        comentarios || null,
        scanned_by || null,
        createdAt,
      ]
    );
    const insertedIds = [result.insertId];
    let savedDefects = [];
    if (tipo === 'ENTRADA' && repairArea) {
      savedDefects = await insertEntryDefects(connection, result.insertId, defectItems);
    } else if (sourceEntryId) {
      savedDefects = await closeEntryDefects(
        connection,
        sourceEntryId,
        result.insertId,
        tipo,
        createdAt
      );
    }

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
      defects: tipo === 'ENTRADA' ? savedDefects : [],
      repaired_defects: tipo === 'SALIDA' ? savedDefects : [],
    });

  } catch (err) {
    if (connection) {
      try {
        await connection.rollback();
      } catch (_) {}
    }
    next(err);
  } finally {
    if (connection && entryLockName) {
      try {
        await connection.query('SELECT RELEASE_LOCK(?)', [entryLockName]);
      } catch (_) {}
    }
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

    const invDate = inventory_date || getLocalDate();
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
    const createdAt = formatLocalDateTime();
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
        placeholders.push('(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)');
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
          createdAt,
        );
      });

      const [result] = await connection.query(
        `INSERT INTO pcb_inventory_scan_smd
          (inventory_date, scanned_original, scanned_original_norm, assy_type, pcb_part_no, modelo, proceso, area, tipo_movimiento, qty, array_count, array_group_code, array_role, defect_type, component_location, comentarios, scanned_by, created_at)
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
    const { inventory_date, inventory_date_end, proceso, area, tipo_movimiento, limit } = req.query;

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
        COALESCE(
          (SELECT GROUP_CONCAT(d.defect_type ORDER BY d.sort_order SEPARATOR ', ')
           FROM pcb_inventory_scan_defects_smd d
           WHERE d.entry_scan_id = CASE
             WHEN s.tipo_movimiento = 'ENTRADA' THEN s.id ELSE s.source_entry_id END),
          s.defect_type
        ) AS defect_type,
        COALESCE(
          (SELECT GROUP_CONCAT(COALESCE(d.component_location, '') ORDER BY d.sort_order SEPARATOR ', ')
           FROM pcb_inventory_scan_defects_smd d
           WHERE d.entry_scan_id = CASE
             WHEN s.tipo_movimiento = 'ENTRADA' THEN s.id ELSE s.source_entry_id END),
          s.component_location
        ) AS component_location,
        s.etapa_deteccion,
        s.defect_source_area,
        s.defect_data_id,
        s.source_entry_id,
        s.defect_count,
        comentarios,
        scanned_by,
        created_at,
        DATE_FORMAT(created_at, '%Y-%m-%d %H:%i:%s') as created_at_fmt,
        DATE_FORMAT(created_at, '%H:%i:%s') as hora
      FROM pcb_inventory_scan_smd s
      WHERE s.inventory_date BETWEEN ? AND ? AND s.tipo_movimiento = ?
    `;
    const params = [inventory_date, inventory_date_end || inventory_date, tipo];

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
        COALESCE(
          (SELECT GROUP_CONCAT(d.defect_type ORDER BY d.sort_order SEPARATOR ', ')
           FROM pcb_inventory_scan_defects_smd d
           WHERE d.entry_scan_id = CASE
             WHEN s.tipo_movimiento = 'ENTRADA' THEN s.id ELSE s.source_entry_id END),
          s.defect_type
        ) AS defect_type,
        COALESCE(
          (SELECT GROUP_CONCAT(COALESCE(d.component_location, '') ORDER BY d.sort_order SEPARATOR ', ')
           FROM pcb_inventory_scan_defects_smd d
           WHERE d.entry_scan_id = CASE
             WHEN s.tipo_movimiento = 'ENTRADA' THEN s.id ELSE s.source_entry_id END),
          s.component_location
        ) AS component_location,
        s.etapa_deteccion,
        s.defect_source_area,
        s.defect_data_id,
        s.source_entry_id,
        s.defect_count,
        comentarios,
        scanned_by,
        created_at,
        DATE_FORMAT(created_at, '%Y-%m-%d %H:%i:%s') as created_at_fmt,
        DATE_FORMAT(created_at, '%H:%i:%s') as hora
      FROM pcb_inventory_scan_smd s
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
// GET /api/pcb-inventory/previous-repair?codigo=...
// Ultimo ciclo de reparacion cerrado para una PCB
// ============================================
exports.getPreviousRepair = async (req, res, next) => {
  try {
    const scannedOriginalNorm = normalizeCode(req.query.codigo);
    if (!scannedOriginalNorm) {
      return res.status(400).json({
        success: false,
        message: 'El codigo de PCB es requerido',
        code: 'MISSING_PCB_CODE',
      });
    }

    const equivalentCodes = getEquivalentNormalizedCodes(scannedOriginalNorm);
    const [cycles] = await pool.query(
      `SELECT
         salida.id AS exit_scan_id,
         salida.source_entry_id AS entry_scan_id,
         salida.scanned_original,
         salida.pcb_part_no,
         salida.modelo,
         entrada.area AS repair_area,
         COALESCE(salida.defect_type, entrada.defect_type) AS defect_type,
         COALESCE(salida.component_location, entrada.component_location) AS component_location,
         COALESCE(salida.etapa_deteccion, entrada.etapa_deteccion) AS etapa_deteccion,
         COALESCE(salida.defect_source_area, entrada.defect_source_area) AS defect_source_area,
         DATE_FORMAT(salida.created_at, '%Y-%m-%d %H:%i:%s') AS repaired_at
       FROM pcb_inventory_scan_smd salida
       LEFT JOIN pcb_inventory_scan_smd entrada
         ON entrada.id = salida.source_entry_id
       WHERE salida.tipo_movimiento = 'SALIDA'
         AND salida.scanned_original_norm IN (?, ?)
         AND (salida.source_entry_id IS NOT NULL OR salida.defect_type IS NOT NULL)
       ORDER BY salida.created_at DESC, salida.id DESC
       LIMIT 1`,
      equivalentCodes
    );

    const cycle = cycles[0];
    if (!cycle) {
      return res.json({ success: true, data: null });
    }

    let defects = [];
    if (cycle.entry_scan_id) {
      const [rows] = await pool.query(
        `SELECT sort_order, defect_type, component_location,
                etapa_deteccion, defect_source_area,
                DATE_FORMAT(repaired_at, '%Y-%m-%d %H:%i:%s') AS repaired_at
         FROM pcb_inventory_scan_defects_smd
         WHERE entry_scan_id = ?
           AND exit_scan_id = ?
           AND repair_status = 'REPAIRED'
         ORDER BY sort_order, id`,
        [cycle.entry_scan_id, cycle.exit_scan_id]
      );
      defects = rows;
    }

    return res.json({
      success: true,
      data: buildPreviousRepairData(cycle, defects),
    });
  } catch (err) {
    next(err);
  }
};

function buildPcbHistory(movements, defectRows) {
  const defectsByEntry = new Map();
  for (const defect of defectRows) {
    if (!defectsByEntry.has(defect.entry_scan_id)) defectsByEntry.set(defect.entry_scan_id, []);
    defectsByEntry.get(defect.entry_scan_id).push(defect);
  }

  const items = movements.map(movement => {
    const isEntry = movement.tipo_movimiento === 'ENTRADA';
    // Defectos van en la entrada del ciclo; registros legacy solo traen defect_type en la fila.
    let defects = isEntry ? (defectsByEntry.get(movement.id) || []) : [];
    if (defects.length === 0 && movement.defect_type && (isEntry || !movement.source_entry_id)) {
      defects = [{
        sort_order: 1,
        defect_type: movement.defect_type,
        component_location: movement.component_location || null,
        etapa_deteccion: movement.etapa_deteccion || null,
        defect_source_area: movement.defect_source_area || null,
        repair_status: null,
        repaired_at: null,
      }];
    }
    return {
      id: movement.id,
      tipo_movimiento: movement.tipo_movimiento,
      area: movement.area,
      proceso: movement.proceso,
      pcb_part_no: movement.pcb_part_no,
      modelo: movement.modelo,
      qty: movement.qty,
      array_count: movement.array_count,
      array_role: movement.array_role,
      array_group_code: movement.array_group_code,
      source_entry_id: movement.source_entry_id,
      comentarios: movement.comentarios,
      scanned_by: movement.scanned_by,
      inventory_date: movement.inventory_date,
      created_at: movement.created_at,
      is_repair: isRepairArea(movement.area),
      defects,
    };
  });

  const count = tipo => items.filter(item => item.tipo_movimiento === tipo).length;
  const last = items[items.length - 1] || null;
  return {
    pcb_part_no: last?.pcb_part_no || null,
    modelo: last?.modelo || null,
    summary: {
      total_entradas: count('ENTRADA'),
      total_salidas: count('SALIDA'),
      total_scrap: count('SCRAP'),
      repair_cycles: items.filter(item => item.tipo_movimiento === 'ENTRADA' && item.is_repair).length,
      total_defects: items.reduce((sum, item) => sum + item.defects.length, 0),
      last_movement: last ? { tipo_movimiento: last.tipo_movimiento, area: last.area, created_at: last.created_at } : null,
    },
    movements: items,
  };
}

// ============================================
// GET /api/pcb-inventory/history?codigo=...
// Historial completo de una PCB. Acepta QR con ';' o barcode continuo EBR.
// ============================================
exports.getHistory = async (req, res, next) => {
  try {
    const rawCode = (req.query.codigo || '').toString().trim();
    const scannedOriginalNorm = normalizeCode(rawCode);
    if (!scannedOriginalNorm) {
      return res.status(400).json({
        success: false,
        message: 'El codigo de PCB es requerido',
        code: 'MISSING_PCB_CODE',
      });
    }
    if (!parsePcbPartNo(parseScannedCode(rawCode).pcb_part_no)) {
      return res.status(400).json({
        success: false,
        message: 'Codigo invalido: se espera QR con EBR en el 3er token o barcode que inicie con EBR########',
        code: 'INVALID_PCB_PART_NO',
      });
    }

    const [movements] = await pool.query(
      `SELECT id, tipo_movimiento, area, proceso, pcb_part_no, modelo, qty,
              array_count, array_role, array_group_code, source_entry_id,
              defect_type, component_location, etapa_deteccion, defect_source_area,
              comentarios, scanned_by,
              DATE_FORMAT(inventory_date, '%Y-%m-%d') AS inventory_date,
              DATE_FORMAT(created_at, '%Y-%m-%d %H:%i:%s') AS created_at
       FROM pcb_inventory_scan_smd
       WHERE scanned_original_norm IN (?, ?)
       ORDER BY created_at, id`,
      getEquivalentNormalizedCodes(scannedOriginalNorm)
    );

    const entryIds = movements
      .filter(movement => movement.tipo_movimiento === 'ENTRADA')
      .map(movement => movement.id);
    let defects = [];
    if (entryIds.length > 0) {
      [defects] = await pool.query(
        `SELECT entry_scan_id, exit_scan_id, sort_order, defect_type,
                component_location, etapa_deteccion, defect_source_area, repair_status,
                DATE_FORMAT(repaired_at, '%Y-%m-%d %H:%i:%s') AS repaired_at
         FROM pcb_inventory_scan_defects_smd
         WHERE entry_scan_id IN (?)
         ORDER BY entry_scan_id, sort_order, id`,
        [entryIds]
      );
    }

    res.json({
      success: true,
      data: { scanned_code: scannedOriginalNorm, ...buildPcbHistory(movements, defects) },
    });
  } catch (err) {
    next(err);
  }
};

// ============================================
// DELETE /api/pcb-inventory/scan/:id
// ============================================
exports.deleteScan = async (req, res, next) => {
  let connection;
  try {
    const { id } = req.params;
    connection = await pool.getConnection();
    await connection.beginTransaction();
    const [rows] = await connection.query(
      `SELECT id, tipo_movimiento, source_entry_id
       FROM pcb_inventory_scan_smd
       WHERE id = ?
       FOR UPDATE`,
      [id]
    );
    const scan = rows[0];
    if (!scan) {
      await connection.rollback();
      return res.status(404).json({
        success: false,
        message: 'Escaneo no encontrado'
      });
    }

    if (scan.tipo_movimiento === 'ENTRADA') {
      const [linkedExits] = await connection.query(
        `SELECT id FROM pcb_inventory_scan_smd
         WHERE source_entry_id = ?
         LIMIT 1`,
        [id]
      );
      if (linkedExits.length > 0) {
        await connection.rollback();
        return res.status(409).json({
          success: false,
          message: 'No se puede eliminar una entrada cuyo ciclo ya tiene salida',
          code: 'PCB_CYCLE_ALREADY_CLOSED'
        });
      }
    } else if (scan.source_entry_id) {
      await connection.query(
        `UPDATE pcb_inventory_scan_defects_smd
         SET exit_scan_id = NULL, repair_status = 'PENDING', repaired_at = NULL
         WHERE entry_scan_id = ? AND exit_scan_id = ?`,
        [scan.source_entry_id, id]
      );
    }

    const [result] = await connection.query(
      `DELETE FROM pcb_inventory_scan_smd WHERE id = ?`,
      [id]
    );

    if (result.affectedRows === 0) {
      await connection.rollback();
      return res.status(404).json({
        success: false,
        message: 'Escaneo no encontrado'
      });
    }

    await connection.commit();

    res.json({
      success: true,
      message: 'Escaneo eliminado'
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

exports._test = {
  parseScannedCode,
  buildPcbHistory,
  normalizeDefectsPayload,
  summarizeDefects,
  buildPreviousRepairData,
};
