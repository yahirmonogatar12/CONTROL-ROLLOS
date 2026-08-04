/**
 * Controlador para Auditoría de Inventario
 * Sistema de verificación física de materiales en almacén
 * 
 * Flujo:
 * 1. Supervisor inicia auditoría desde PC
 * 2. Operadores móviles escanean ubicaciones y materiales
 * 3. Supervisor ve progreso con auto-refresh cada 10 segundos
 * 4. Al terminar, supervisor confirma discrepancias
 * 5. Materiales no encontrados se dan de salida
 *
 * Tablas clave:
 * - inventory_audit_smd: sesion y totales de la auditoria
 * - inventory_audit_location_smd: ubicaciones incluidas y progreso
 * - inventory_audit_item_smd: items verificados (Found/Missing/ProcessedOut)
 *
 * Alcance: solo inventario activo de inventario_lotes_smd
 * (stock_actual > 0 y con ubicacion valida resuelta desde control_material_almacen_smd).
 */
const { pool } = require('../config/database');
const {
  normalizeAuditLocation,
  parsePhysicalQuantity,
  getPhysicalAdjustment
} = require('../utils/auditPhysical');

// Funciones WebSocket deshabilitadas (ya no se usan, polling en su lugar)
// Se mantienen para compatibilidad con llamadas existentes en el controlador.
const setWebSocketServer = () => { };
const broadcastAuditUpdate = () => { };

const AUDIT_LOCATION_EXPR = `COALESCE(NULLIF(TRIM(cma.ubicacion_destino), ''), NULLIF(TRIM(cma.ubicacion_salida), ''))`;
const AUDIT_ITEM_PART_EXPR = 'COALESCE(iai.numero_parte_snapshot, cma.numero_parte)';
const AUDIT_ITEM_LOT_EXPR = 'COALESCE(iai.numero_lote_material_snapshot, cma.numero_lote_material)';
const AUDIT_ITEM_QTY_EXPR = 'COALESCE(iai.cantidad_snapshot, cma.cantidad_actual)';
const AUDIT_ITEM_SPEC_EXPR = 'COALESCE(iai.especificacion_snapshot, cma.especificacion)';
const AUDIT_ITEM_RECEIPT_EXPR = 'COALESCE(iai.fecha_recibo_snapshot, cma.fecha_recibo)';

function getAuditInventorySnapshotQuery() {
  return `
    SELECT
      cma.id AS warehousing_id,
      il.codigo_material_recibido,
      il.numero_parte,
      il.numero_lote AS numero_lote_material,
      il.stock_actual AS cantidad_actual,
      il.total_salida,
      cma.tiene_salida,
      ${AUDIT_LOCATION_EXPR} AS location,
      COALESCE(cma.especificacion, '') AS especificacion,
      cma.fecha_recibo
    FROM inventario_lotes_smd il
    JOIN (
      SELECT c1.*
      FROM control_material_almacen_smd c1
      INNER JOIN (
        SELECT codigo_material_recibido, MAX(id) AS max_id
        FROM control_material_almacen_smd
        GROUP BY codigo_material_recibido
      ) latest ON latest.max_id = c1.id
    ) cma ON cma.codigo_material_recibido = il.codigo_material_recibido
    WHERE il.stock_actual > 0
      AND ${AUDIT_LOCATION_EXPR} IS NOT NULL
      AND ${AUDIT_LOCATION_EXPR} <> ''
  `;
}

// Fuente estable de la auditoria. A diferencia de inventario_lotes_smd, estos
// datos no desaparecen cuando una salida deja stock_actual en cero.
function getPersistedAuditItemsQuery() {
  return `
    SELECT
      iai.id AS audit_item_id,
      iai.audit_id,
      iai.warehousing_id,
      iai.warehousing_code AS codigo_material_recibido,
      iai.location,
      ${AUDIT_ITEM_PART_EXPR} AS numero_parte,
      ${AUDIT_ITEM_LOT_EXPR} AS numero_lote_material,
      ${AUDIT_ITEM_QTY_EXPR} AS cantidad_actual,
      ${AUDIT_ITEM_SPEC_EXPR} AS especificacion,
      ${AUDIT_ITEM_RECEIPT_EXPR} AS fecha_recibo,
      iai.physical_quantity,
      iai.physical_quantity_recorded_at,
      iai.physical_quantity_recorded_by,
      iai.is_new_inventory,
      iai.status AS audit_status,
      iai.scanned_at,
      iai.scanned_by,
      iai.processed_at,
      iai.processed_by
    FROM inventory_audit_item_smd iai
    LEFT JOIN control_material_almacen_smd cma ON cma.id = iai.warehousing_id
  `;
}

// Registra la salida y garantiza que inventario_lotes_smd quede descontado en
// la misma transaccion. Normalmente lo hace trg_salida_bi_guard_smd; la verificacion
// posterior cubre instalaciones donde el trigger no exista o este desfasado.
async function createImmediateAuditOutgoing(connection, item, usuario) {
  const [lotRows] = await connection.query(`
    SELECT id, total_salida, stock_actual
    FROM inventario_lotes_smd
    WHERE codigo_material_recibido = ?
    LIMIT 1
    FOR UPDATE
  `, [item.warehousing_code]);

  if (lotRows.length === 0) {
    throw new Error(`Lote de inventario no encontrado para ${item.warehousing_code}`);
  }

  const stockBefore = Number(lotRows[0].stock_actual || 0);
  if (stockBefore <= 0) {
    return { created: false, quantity: 0, stockAfter: stockBefore };
  }

  // Una discrepancia de auditoria retira la existencia completa que el lote
  // tiene en ese momento, no una cantidad CMA que pudo quedar obsoleta.
  const quantity = stockBefore;
  const totalSalidaBefore = Number(lotRows[0].total_salida || 0);

  const [outgoingResult] = await connection.query(`
    INSERT INTO control_material_salida_smd (
      codigo_material_recibido,
      numero_parte,
      numero_lote,
      depto_salida,
      proceso_salida,
      cantidad_salida,
      fecha_salida,
      fecha_registro,
      especificacion_material,
      usuario_registro
    ) VALUES (?, ?, ?, 'AUDITORIA', 'DISCREPANCIA INVENTARIO', ?, NOW(), NOW(), ?, ?)
  `, [
    item.warehousing_code,
    item.numero_parte,
    item.numero_lote_material,
    quantity,
    item.especificacion || null,
    usuario || 'Sistema'
  ]);

  const [afterTriggerRows] = await connection.query(`
    SELECT total_salida, stock_actual
    FROM inventario_lotes_smd
    WHERE id = ?
    FOR UPDATE
  `, [lotRows[0].id]);

  const expectedTotalSalida = totalSalidaBefore + quantity;
  const totalSalidaAfterTrigger = Number(afterTriggerRows[0]?.total_salida || 0);
  if (totalSalidaAfterTrigger + 0.0001 < expectedTotalSalida) {
    await connection.query(`
      UPDATE inventario_lotes_smd
      SET total_salida = ?, ultima_salida = NOW()
      WHERE id = ?
    `, [expectedTotalSalida, lotRows[0].id]);
  }

  // Una salida de auditoria no es desecho. Mantener estado_desecho intacto
  // permite que el flujo normal de devolucion reactive el material.
  await connection.query(`
    UPDATE control_material_almacen_smd
    SET tiene_salida = 1
    WHERE id = ?
  `, [item.warehousing_id]);

  const [finalRows] = await connection.query(`
    SELECT stock_actual FROM inventario_lotes_smd WHERE id = ?
  `, [lotRows[0].id]);

  return {
    created: true,
    outgoingId: outgoingResult.insertId,
    quantity,
    stockAfter: Number(finalRows[0]?.stock_actual || 0)
  };
}

async function getAuditInventoryMaterialByCode(warehousingCode) {
  const [rows] = await pool.query(`
    SELECT *
    FROM (${getAuditInventorySnapshotQuery()}) ai
    WHERE ai.codigo_material_recibido = ?
    LIMIT 1
  `, [warehousingCode]);

  return rows[0] || null;
}

async function getAuditInventoryMaterialByWarehousingId(warehousingId) {
  const [rows] = await pool.query(`
    SELECT *
    FROM (${getAuditInventorySnapshotQuery()}) ai
    WHERE ai.warehousing_id = ?
    LIMIT 1
  `, [warehousingId]);

  return rows[0] || null;
}

// Sincroniza una ubicación de la auditoría con el inventario activo. Incorpora
// materiales registrados después del snapshot, refleja reubicaciones y retira
// del snapshot los materiales que tuvieron una salida completa. La
// trazabilidad de esas salidas permanece en control_material_salida_smd.
async function syncAuditLocationWithInventory(
  connection,
  auditId,
  location,
  usuario = 'Mobile'
) {
  const normalizedLocation = normalizeAuditLocation(location);
  const [liveItems] = await connection.query(`
    SELECT *
    FROM (${getAuditInventorySnapshotQuery()}) ai
    WHERE UPPER(TRIM(ai.location)) = ?
    ORDER BY ai.codigo_material_recibido
  `, [normalizedLocation]);

  const affectedLocations = new Set([normalizedLocation]);
  let insertedItems = 0;
  let relocatedItems = 0;

  for (const material of liveItems) {
    const [existingItems] = await connection.query(`
      SELECT id, location
      FROM inventory_audit_item_smd
      WHERE audit_id = ?
        AND (warehousing_id = ? OR warehousing_code = ?)
      ORDER BY (warehousing_id = ?) DESC
      LIMIT 1
      FOR UPDATE
    `, [
      auditId,
      material.warehousing_id,
      material.codigo_material_recibido,
      material.warehousing_id
    ]);

    if (existingItems.length === 0) {
      await connection.query(`
        INSERT INTO inventory_audit_item_smd (
          audit_id,
          warehousing_id,
          warehousing_code,
          location,
          numero_parte_snapshot,
          numero_lote_material_snapshot,
          cantidad_snapshot,
          especificacion_snapshot,
          fecha_recibo_snapshot,
          status,
          notas
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 'Pending', ?)
      `, [
        auditId,
        material.warehousing_id,
        material.codigo_material_recibido,
        normalizedLocation,
        material.numero_parte,
        material.numero_lote_material,
        material.cantidad_actual,
        material.especificacion || null,
        material.fecha_recibo || null,
        'Sincronizado desde inventario activo durante la auditoría'
      ]);
      insertedItems += 1;
      continue;
    }

    const previousLocation = normalizeAuditLocation(existingItems[0].location);
    if (previousLocation && previousLocation !== normalizedLocation) {
      affectedLocations.add(previousLocation);
      await connection.query(`
        UPDATE inventory_audit_item_smd
        SET location = ?,
            numero_parte_snapshot = ?,
            numero_lote_material_snapshot = ?,
            cantidad_snapshot = ?,
            especificacion_snapshot = ?,
            fecha_recibo_snapshot = ?,
            physical_quantity = NULL,
            physical_quantity_recorded_at = NULL,
            physical_quantity_recorded_by = NULL,
            status = 'Pending',
            scanned_at = NULL,
            scanned_by = NULL,
            processed_at = NULL,
            processed_by = NULL,
            notas = CONCAT_WS(
              ' | ',
              NULLIF(notas, ''),
              ?
            )
        WHERE id = ?
      `, [
        normalizedLocation,
        material.numero_parte,
        material.numero_lote_material,
        material.cantidad_actual,
        material.especificacion || null,
        material.fecha_recibo || null,
        `Sincronizado de ${previousLocation} a ${normalizedLocation} desde inventario activo`,
        existingItems[0].id
      ]);
      relocatedItems += 1;
    }
  }

  // Un material desaparece del inventario activo cuando su salida deja el
  // stock en cero. Retirarlo únicamente del snapshot activo evita mostrarlo
  // como pendiente o faltante; el movimiento de salida conserva la
  // trazabilidad operativa.
  const [inactiveItems] = await connection.query(`
    SELECT iai.id
    FROM inventory_audit_item_smd iai
    LEFT JOIN inventario_lotes_smd active_inventory
      ON active_inventory.codigo_material_recibido = iai.warehousing_code
      AND active_inventory.stock_actual > 0
    WHERE iai.audit_id = ?
      AND iai.location = ?
      AND iai.status <> 'ProcessedOut'
      AND active_inventory.codigo_material_recibido IS NULL
    FOR UPDATE
  `, [auditId, normalizedLocation]);

  let removedItems = 0;
  if (inactiveItems.length > 0) {
    const inactiveIds = inactiveItems.map(item => item.id);
    const placeholders = inactiveIds.map(() => '?').join(', ');
    const [deleteResult] = await connection.query(`
      DELETE FROM inventory_audit_item_smd
      WHERE audit_id = ? AND id IN (${placeholders})
    `, [auditId, ...inactiveIds]);
    removedItems = Number(deleteResult.affectedRows || 0);
  }

  if (insertedItems === 0 && relocatedItems === 0 && removedItems === 0) {
    return {
      insertedItems,
      relocatedItems,
      removedItems,
      affectedLocations: [normalizedLocation]
    };
  }

  for (const affectedLocation of affectedLocations) {
    // Crear las partes nuevas y recalcular las ya existentes. Si cambió la
    // cantidad esperada, se reabre la parte para que el operador la confirme.
    await connection.query(`
      INSERT INTO inventory_audit_part_smd (
        audit_id,
        location,
        numero_parte,
        expected_items,
        expected_qty,
        status
      )
      SELECT
        iai.audit_id,
        iai.location,
        ${AUDIT_ITEM_PART_EXPR} AS numero_parte,
        COUNT(*) AS expected_items,
        SUM(${AUDIT_ITEM_QTY_EXPR}) AS expected_qty,
        'Pending'
      FROM inventory_audit_item_smd iai
      LEFT JOIN control_material_almacen_smd cma ON cma.id = iai.warehousing_id
      WHERE iai.audit_id = ? AND iai.location = ?
      GROUP BY iai.audit_id, iai.location, ${AUDIT_ITEM_PART_EXPR}
      ON DUPLICATE KEY UPDATE
        status = IF(
          expected_items <> VALUES(expected_items)
            OR expected_qty <> VALUES(expected_qty),
          'Pending',
          status
        ),
        scanned_items = IF(
          expected_items <> VALUES(expected_items)
            OR expected_qty <> VALUES(expected_qty),
          0,
          scanned_items
        ),
        scanned_qty = IF(
          expected_items <> VALUES(expected_items)
            OR expected_qty <> VALUES(expected_qty),
          0,
          scanned_qty
        ),
        confirmed_by = IF(
          expected_items <> VALUES(expected_items)
            OR expected_qty <> VALUES(expected_qty),
          NULL,
          confirmed_by
        ),
        confirmed_at = IF(
          expected_items <> VALUES(expected_items)
            OR expected_qty <> VALUES(expected_qty),
          NULL,
          confirmed_at
        ),
        expected_items = VALUES(expected_items),
        expected_qty = VALUES(expected_qty)
    `, [auditId, affectedLocation]);

    await connection.query(`
      DELETE iap
      FROM inventory_audit_part_smd iap
      WHERE iap.audit_id = ?
        AND iap.location = ?
        AND NOT EXISTS (
          SELECT 1
          FROM inventory_audit_item_smd iai
          LEFT JOIN control_material_almacen_smd cma
            ON cma.id = iai.warehousing_id
          WHERE iai.audit_id = iap.audit_id
            AND iai.location = iap.location
            AND ${AUDIT_ITEM_PART_EXPR} = iap.numero_parte
        )
    `, [auditId, affectedLocation]);

    await connection.query(`
      UPDATE inventory_audit_location_smd ial
      SET total_items = (
            SELECT COUNT(*)
            FROM inventory_audit_item_smd iai
            WHERE iai.audit_id = ial.audit_id
              AND iai.location = ial.location
          ),
          total_qty = (
            SELECT COALESCE(SUM(iai.cantidad_snapshot), 0)
            FROM inventory_audit_item_smd iai
            WHERE iai.audit_id = ial.audit_id
              AND iai.location = ial.location
          ),
          status = 'InProgress',
          completed_at = NULL,
          completed_by = NULL,
          started_at = COALESCE(started_at, NOW()),
          started_by = COALESCE(started_by, ?)
      WHERE ial.audit_id = ? AND ial.location = ?
    `, [usuario || 'Mobile', auditId, affectedLocation]);
  }

  await connection.query(`
    UPDATE inventory_audit_smd ia
    SET total_locations = (
          SELECT COUNT(*)
          FROM inventory_audit_location_smd ial
          WHERE ial.audit_id = ia.id
        ),
        total_items = (
          SELECT COUNT(*)
          FROM inventory_audit_item_smd iai
          WHERE iai.audit_id = ia.id
        )
    WHERE ia.id = ?
  `, [auditId]);

  return {
    insertedItems,
    relocatedItems,
    removedItems,
    affectedLocations: [...affectedLocations]
  };
}

function isInventoryCountableIqcStatus(status) {
  return ['Released', 'NotRequired'].includes(String(status || 'NotRequired'));
}

function auditRecoveryError(code, error, extra = {}) {
  return { success: false, code, error, ...extra };
}

// La etiqueta escaneada en la auditoria existe fisicamente, asi que un registro
// cancelado o rechazado no la oculta: solo se prefiere el registro limpio si hay
// varios. Al darle entrada se reactiva (ver insertAutomaticAuditWarehouseEntry).
async function findAutomaticAuditEntrySource(connection, warehousingCode) {
  const [warehouseRows] = await connection.query(`
    SELECT
      cma.*,
      m.especificacion_material,
      m.unidad_medida AS catalog_unidad_medida,
      m.ubicacion_material,
      m.vendedor AS material_vendedor,
      m.propiedad_material AS catalog_propiedad_material,
      'control_material_almacen' AS source_table
    FROM control_material_almacen cma
    LEFT JOIN materiales m ON m.numero_parte = cma.numero_parte
    WHERE cma.codigo_material_recibido = ?
    ORDER BY COALESCE(cma.cancelado, 0) ASC, cma.id DESC
    LIMIT 1
    FOR UPDATE
  `, [warehousingCode]);

  if (warehouseRows.length > 0) {
    return warehouseRows[0];
  }

  const [outgoingRows] = await connection.query(`
    SELECT
      cms.id,
      cms.codigo_material_recibido,
      cms.numero_parte,
      cms.numero_lote AS numero_lote_material,
      cms.cantidad_salida AS cantidad_actual,
      cms.especificacion_material AS especificacion,
      cms.vendedor,
      cms.fecha_salida AS fecha_recibo,
      cms.usuario_registro,
      cms.cancelado,
      cms.rechazado,
      m.codigo_material,
      m.codigo_material AS codigo_material_final,
      m.propiedad_material,
      m.unidad_medida AS catalog_unidad_medida,
      m.especificacion_material,
      m.ubicacion_material,
      m.vendedor AS material_vendedor,
      'WarehouseOut' AS forma_material,
      0 AS iqc_required,
      'NotRequired' AS iqc_status,
      'control_material_salida' AS source_table
    FROM control_material_salida cms
    LEFT JOIN materiales m ON m.numero_parte = cms.numero_parte
    WHERE cms.codigo_material_recibido = ?
    ORDER BY COALESCE(cms.cancelado, 0) ASC, COALESCE(cms.rechazado, 0) ASC, cms.id DESC
    LIMIT 1
    FOR UPDATE
  `, [warehousingCode]);

  return outgoingRows[0] || null;
}

async function insertAutomaticAuditWarehouseEntry(
  connection,
  source,
  location,
  usuario
) {
  const code = String(source.codigo_material_recibido || '').trim();
  const partNumber = String(source.numero_parte || '').trim();
  const lotNumber = String(
    source.numero_lote_material || source.numero_lote || ''
  ).trim();
  const quantity = Number(source.cantidad_actual || source.cantidad_salida || 0);
  const iqcRequired = Number(source.iqc_required || 0) === 1;
  const iqcStatus = String(
    source.iqc_status || (iqcRequired ? 'Pending' : 'NotRequired')
  );

  if (!code || !partNumber || !lotNumber || !Number.isFinite(quantity) || quantity <= 0) {
    return auditRecoveryError(
      'AUTO_ENTRY_INCOMPLETE_SOURCE',
      'El material existe, pero no tiene parte, lote o cantidad válida para crear la entrada'
    );
  }

  if (!isInventoryCountableIqcStatus(iqcStatus)) {
    return auditRecoveryError(
      'IQC_NOT_RELEASED',
      `El material requiere liberación de IQC antes de entrar al inventario (estado: ${iqcStatus})`
    );
  }

  // El dueño del material vive en el catálogo `materiales`. En
  // control_material_almacen la columna propiedad_material siempre vale
  // 'Customer Supply' (tipo de suministro), asi que no sirve para este filtro.
  const ownership = String(
    source.catalog_propiedad_material ?? source.propiedad_material ?? ''
  ).trim().toUpperCase();

  if (ownership && ownership !== 'SMD' && ownership !== 'CUSTOMER SUPPLY') {
    return auditRecoveryError(
      'MATERIAL_NOT_SMD',
      `El material pertenece al almacén ${ownership}, no a SMD`
    );
  }

  const receivingLotCode = source.receiving_lot_code
    || (code.length >= 20 ? code.substring(0, 20) : null);
  const labelSeq = source.label_seq
    || (code.length > 20 ? parseInt(code.substring(20), 10) || null : null);

  const [insertResult] = await connection.query(`
    INSERT INTO control_material_almacen_smd (
      forma_material,
      cliente,
      codigo_material_original,
      codigo_material,
      material_importacion_local,
      fecha_recibo,
      fecha_fabricacion,
      cantidad_actual,
      numero_lote_material,
      codigo_material_recibido,
      numero_parte,
      cantidad_estandarizada,
      codigo_material_final,
      propiedad_material,
      especificacion,
      material_importacion_local_final,
      estado_desecho,
      ubicacion_salida,
      ubicacion_destino,
      vendedor,
      usuario_registro,
      fecha_registro,
      unidad_medida,
      receiving_lot_code,
      label_seq,
      iqc_required,
      iqc_status,
      inspection_lot_sequence,
      tiene_salida
    ) VALUES (?, ?, ?, ?, ?, NOW(), ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0, ?, ?, ?, ?, NOW(), ?, ?, ?, ?, ?, ?, 0)
  `, [
    source.forma_material || 'AuditAutoEntry',
    source.cliente || null,
    source.codigo_material_original || null,
    source.codigo_material || source.material_codigo || null,
    source.material_importacion_local || null,
    source.fecha_fabricacion || null,
    quantity,
    lotNumber,
    code,
    partNumber,
    source.cantidad_estandarizada || null,
    source.codigo_material_final || source.codigo_material || null,
    'SMD', // el resto de control_material_almacen_smd usa 'SMD' sin excepcion
    source.especificacion || source.especificacion_material || null,
    source.material_importacion_local_final || null,
    location,
    location,
    source.vendedor || source.material_vendedor || null,
    usuario,
    source.unidad_medida || source.catalog_unidad_medida || 'EA',
    receivingLotCode,
    labelSeq,
    iqcRequired ? 1 : 0,
    iqcStatus,
    source.inspection_lot_sequence || 1
  ]);

  // El conteo fisico manda: si el registro origen estaba cancelado/rechazado se
  // reactiva junto con la entrada, para que almacen e inventario coincidan.
  const sourceWasVoided = Number(source.cancelado || 0) === 1
    || Number(source.rechazado || 0) === 1;

  if (source.source_table === 'control_material_almacen') {
    await connection.query(`
      UPDATE control_material_almacen
      SET cancelado = 0,
          confirmado_smd = 1,
          confirmado_smd_por = ?,
          confirmado_smd_at = NOW()
      WHERE id = ?
    `, [usuario, source.id]);
  } else if (source.source_table === 'control_material_salida') {
    await connection.query(`
      UPDATE control_material_salida
      SET cancelado = 0,
          rechazado = 0,
          confirmado = 1,
          confirmado_por = ?,
          confirmado_at = NOW()
      WHERE id = ?
    `, [usuario, source.id]);
  }

  return {
    success: true,
    warehousingId: insertResult.insertId,
    quantity,
    sourceWasVoided
  };
}

async function ensureAutomaticMaterialInAudit(
  connection,
  auditId,
  material,
  location,
  usuario,
  action
) {
  const [existingItems] = await connection.query(`
    SELECT id, status
    FROM inventory_audit_item_smd
    WHERE audit_id = ? AND warehousing_id = ?
    LIMIT 1
    FOR UPDATE
  `, [auditId, material.warehousing_id]);

  if (existingItems.length > 0) {
    if (action !== 'none') {
      await connection.query(`
        UPDATE inventory_audit_item_smd
        SET status = 'Pending',
            scanned_at = NULL,
            scanned_by = NULL,
            processed_at = NULL,
            processed_by = NULL,
            notas = CONCAT_WS(' | ', NULLIF(notas, ''), ?)
        WHERE id = ?
      `, [`Entrada automática por escaneo de auditoría (${action})`, existingItems[0].id]);

      await connection.query(`
        UPDATE inventory_audit_part_smd
        SET status = 'Mismatch',
            flagged_by = ?,
            flagged_at = NOW()
        WHERE audit_id = ?
          AND location = ?
          AND numero_parte = ?
          AND status = 'MissingConfirmed'
      `, [usuario, auditId, location, material.numero_parte]);

      await connection.query(`
        UPDATE inventory_audit_location_smd
        SET status = 'InProgress',
            completed_at = NULL,
            completed_by = NULL
        WHERE audit_id = ?
          AND location = ?
          AND status = 'Discrepancy'
      `, [auditId, location]);
    }
    return false;
  }

  const [locationRows] = await connection.query(`
    SELECT id
    FROM inventory_audit_location_smd
    WHERE audit_id = ? AND location = ?
    LIMIT 1
    FOR UPDATE
  `, [auditId, location]);

  if (locationRows.length === 0) {
    await connection.query(`
      INSERT INTO inventory_audit_location_smd (
        audit_id, location, status, total_items, total_qty, started_at, started_by
      ) VALUES (?, ?, 'InProgress', 1, ?, NOW(), ?)
    `, [auditId, location, material.cantidad_actual, usuario]);

    await connection.query(`
      UPDATE inventory_audit_smd
      SET total_locations = total_locations + 1,
          total_items = total_items + 1
      WHERE id = ?
    `, [auditId]);
  } else {
    await connection.query(`
      UPDATE inventory_audit_location_smd
      SET total_items = total_items + 1,
          total_qty = total_qty + ?,
          status = 'InProgress',
          completed_at = NULL,
          completed_by = NULL
      WHERE id = ?
    `, [material.cantidad_actual, locationRows[0].id]);

    await connection.query(`
      UPDATE inventory_audit_smd
      SET total_items = total_items + 1
      WHERE id = ?
    `, [auditId]);
  }

  await connection.query(`
    INSERT INTO inventory_audit_item_smd (
      audit_id,
      warehousing_id,
      warehousing_code,
      location,
      numero_parte_snapshot,
      numero_lote_material_snapshot,
      cantidad_snapshot,
      especificacion_snapshot,
      fecha_recibo_snapshot,
      status,
      notas
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 'Pending', ?)
  `, [
    auditId,
    material.warehousing_id,
    material.codigo_material_recibido,
    location,
    material.numero_parte,
    material.numero_lote_material,
    material.cantidad_actual,
    material.especificacion || null,
    material.fecha_recibo || null,
    `Entrada automática por escaneo de auditoría (${action})`
  ]);

  await connection.query(`
    INSERT INTO inventory_audit_part_smd (
      audit_id,
      location,
      numero_parte,
      expected_items,
      expected_qty,
      status,
      flagged_by,
      flagged_at
    ) VALUES (?, ?, ?, 1, ?, 'Mismatch', ?, NOW())
    ON DUPLICATE KEY UPDATE
      expected_items = expected_items + 1,
      expected_qty = expected_qty + VALUES(expected_qty),
      status = 'Mismatch',
      flagged_by = VALUES(flagged_by),
      flagged_at = NOW()
  `, [
    auditId,
    location,
    material.numero_parte,
    material.cantidad_actual,
    usuario
  ]);

  return true;
}

// Confirmacion fisica durante la auditoria: si la etiqueta se escanea en una
// ubicacion distinta a la registrada, el material se mueve a la escaneada en
// lugar de rechazar el escaneo (el operador tiene el material en la mano).
// Devuelve true si hubo reubicacion.
async function relocateAuditMaterial(db, auditId, {
  warehousingId,
  warehousingCode,
  numeroParte,
  fromLocation,
  toLocation,
  usuario
}) {
  const from = String(fromLocation || '').trim();
  const to = String(toLocation || '').trim();
  if (!from || !to || from === to) return false;

  if (warehousingId) {
    await db.query(`
      UPDATE control_material_almacen_smd
      SET tiene_salida = 0,
          ubicacion_anterior = ?,
          ubicacion_salida = ?,
          ubicacion_destino = ?,
          fecha_reingreso = NOW(),
          usuario_reingreso = ?
      WHERE id = ?
    `, [from, to, to, usuario || 'Mobile', warehousingId]);
  }

  await db.query(`
    UPDATE inventory_audit_item_smd
    SET location = ?,
        notas = CONCAT_WS(' | ', NULLIF(notas, ''), ?)
    WHERE audit_id = ? AND warehousing_code = ?
  `, [to, `Reubicado de ${from} a ${to} por confirmacion fisica en auditoria`, auditId, warehousingCode]);

  await db.query(`
    INSERT IGNORE INTO inventory_audit_part_smd (
      audit_id, location, numero_parte, expected_items, expected_qty,
      status, flagged_by, flagged_at
    ) VALUES (?, ?, ?, 0, 0, 'Mismatch', ?, NOW())
  `, [auditId, to, numeroParte, usuario || 'Mobile']);

  // Contadores esperados de origen y destino: recalcular desde los items.
  await db.query(`
    UPDATE inventory_audit_part_smd iap
    SET expected_items = (
          SELECT COUNT(*)
          FROM inventory_audit_item_smd iai
          LEFT JOIN control_material_almacen_smd cma ON cma.id = iai.warehousing_id
          WHERE iai.audit_id = iap.audit_id
            AND iai.location = iap.location
            AND ${AUDIT_ITEM_PART_EXPR} = iap.numero_parte
        ),
        expected_qty = (
          SELECT COALESCE(SUM(${AUDIT_ITEM_QTY_EXPR}), 0)
          FROM inventory_audit_item_smd iai
          LEFT JOIN control_material_almacen_smd cma ON cma.id = iai.warehousing_id
          WHERE iai.audit_id = iap.audit_id
            AND iai.location = iap.location
            AND ${AUDIT_ITEM_PART_EXPR} = iap.numero_parte
        )
    WHERE iap.audit_id = ? AND iap.numero_parte = ? AND iap.location IN (?, ?)
  `, [auditId, numeroParte, from, to]);

  await db.query(`
    UPDATE inventory_audit_location_smd ial
    SET total_items = (
          SELECT COUNT(*) FROM inventory_audit_item_smd iai
          WHERE iai.audit_id = ial.audit_id AND iai.location = ial.location
        ),
        total_qty = (
          SELECT COALESCE(SUM(COALESCE(iai.physical_quantity, iai.cantidad_snapshot)), 0)
          FROM inventory_audit_item_smd iai
          WHERE iai.audit_id = ial.audit_id AND iai.location = ial.location
        )
    WHERE ial.audit_id = ? AND ial.location IN (?, ?)
  `, [auditId, from, to]);

  return true;
}

async function recoverAuditMaterialForScan(
  auditId,
  warehousingCode,
  requestedLocation,
  usuario,
  expectedPartNumber = null
) {
  const connection = await pool.getConnection();
  const normalizedCode = String(warehousingCode || '').trim();
  const normalizedRequestedLocation = String(requestedLocation || '').trim();
  const normalizedExpectedPart = String(expectedPartNumber || '').trim();
  const userName = usuario || 'Mobile';

  try {
    await connection.beginTransaction();

    const [snapshotRows] = await connection.query(`
      SELECT location
      FROM inventory_audit_item_smd
      WHERE audit_id = ? AND warehousing_code = ?
      LIMIT 1
      FOR UPDATE
    `, [auditId, normalizedCode]);

    const snapshotLocation = String(snapshotRows[0]?.location || '').trim();
    // El escaneo confirma fisicamente donde esta el material: si el snapshot lo
    // tenia en otra ubicacion, se reubica a la escaneada (no se rechaza).
    const relocatedFrom = (
      snapshotLocation
      && normalizedRequestedLocation
      && snapshotLocation !== normalizedRequestedLocation
    ) ? snapshotLocation : null;

    const [existingRows] = await connection.query(`
      SELECT
        cma.*,
        il.id AS inventory_lot_id,
        il.total_entrada,
        il.total_salida,
        il.stock_actual
      FROM control_material_almacen_smd cma
      LEFT JOIN inventario_lotes_smd il
        ON il.codigo_material_recibido = cma.codigo_material_recibido
      WHERE cma.codigo_material_recibido = ?
      ORDER BY cma.id DESC
      LIMIT 1
      FOR UPDATE
    `, [normalizedCode]);

    let action = 'none';
    // La ubicacion escaneada manda sobre el snapshot: es la fisica confirmada.
    let targetLocation = normalizedRequestedLocation || snapshotLocation;
    let warehousingId = null;

    if (existingRows.length > 0) {
      const material = existingRows[0];

      if (
        normalizedExpectedPart
        && String(material.numero_parte || '').trim() !== normalizedExpectedPart
      ) {
        await connection.rollback();
        return auditRecoveryError(
          'WRONG_PART',
          `El material pertenece a la parte ${material.numero_parte}, no a ${normalizedExpectedPart}`
        );
      }

      if (Number(material.cancelado || 0) === 1 || Number(material.estado_desecho || 0) === 1) {
        await connection.rollback();
        return auditRecoveryError(
          'MATERIAL_NOT_ELIGIBLE',
          'El material está cancelado o marcado como desecho y no puede entrar automáticamente'
        );
      }

      if (!isInventoryCountableIqcStatus(material.iqc_status)) {
        await connection.rollback();
        return auditRecoveryError(
          'IQC_NOT_RELEASED',
          `El material requiere liberación de IQC antes de entrar al inventario (estado: ${material.iqc_status})`
        );
      }

      targetLocation = targetLocation
        || String(material.ubicacion_destino || material.ubicacion_salida || '').trim();
      if (!targetLocation) {
        await connection.rollback();
        return auditRecoveryError(
          'LOCATION_REQUIRED_FOR_AUTO_ENTRY',
          'Se requiere la ubicación para crear la entrada automática'
        );
      }

      const quantity = Number(material.cantidad_actual || 0);
      const totalSalidaBefore = Number(material.total_salida || 0);
      const stockBefore = Number(material.stock_actual || 0);

      if (!Number.isFinite(quantity) || quantity <= 0) {
        await connection.rollback();
        return auditRecoveryError(
          'INVALID_AUTO_ENTRY_QUANTITY',
          'El material no tiene una cantidad válida para recuperar'
        );
      }

      if (material.inventory_lot_id && totalSalidaBefore > 0) {
        const returnQty = Math.max(0, totalSalidaBefore);

        await connection.query(`
          INSERT INTO material_return_smd (
            warehousing_id,
            material_warehousing_code,
            part_number,
            material_lot_no,
            material_spec,
            remain_qty,
            return_qty,
            remarks,
            returned_by,
            return_datetime
          ) VALUES (?, ?, ?, ?, ?, 0, ?, ?, ?, NOW())
        `, [
          material.id,
          material.codigo_material_recibido,
          material.numero_parte,
          material.numero_lote_material,
          material.especificacion || null,
          returnQty,
          `Entrada automática por escaneo de auditoría #${auditId} en ${targetLocation}`,
          userName
        ]);

        const expectedTotalSalida = Math.max(0, totalSalidaBefore - returnQty);
        await connection.query(`
          UPDATE inventario_lotes_smd
          SET total_salida = ?
          WHERE id = ?
        `, [expectedTotalSalida, material.inventory_lot_id]);
        action = 'automatic_return';
      } else if (!material.inventory_lot_id || stockBefore <= 0) {
        await connection.query(`
          INSERT INTO inventario_lotes_smd (
            codigo_material_recibido,
            numero_parte,
            numero_lote,
            total_entrada,
            total_salida,
            unidad_medida,
            primer_recibo
          ) VALUES (?, ?, ?, ?, 0, ?, COALESCE(?, NOW()))
          ON DUPLICATE KEY UPDATE
            total_entrada = GREATEST(total_entrada, VALUES(total_entrada)),
            total_salida = 0
        `, [
          material.codigo_material_recibido,
          material.numero_parte,
          material.numero_lote_material,
          quantity,
          material.unidad_medida || 'EA',
          material.fecha_recibo || null
        ]);
        action = 'automatic_entry';
      }

      const currentLocation = String(
        material.ubicacion_destino || material.ubicacion_salida || ''
      ).trim();
      if (
        action === 'none'
        && (
          Number(material.tiene_salida || 0) === 1
          || currentLocation !== targetLocation
        )
      ) {
        action = 'automatic_reentry';
      }

      await connection.query(`
        UPDATE control_material_almacen_smd
        SET tiene_salida = 0,
            ubicacion_anterior = CASE
              WHEN COALESCE(NULLIF(TRIM(ubicacion_destino), ''), NULLIF(TRIM(ubicacion_salida), '')) <> ?
              THEN COALESCE(NULLIF(TRIM(ubicacion_destino), ''), NULLIF(TRIM(ubicacion_salida), ''))
              ELSE ubicacion_anterior
            END,
            ubicacion_salida = ?,
            ubicacion_destino = ?,
            fecha_reingreso = CASE WHEN ? <> 'none' THEN NOW() ELSE fecha_reingreso END,
            usuario_reingreso = CASE WHEN ? <> 'none' THEN ? ELSE usuario_reingreso END
        WHERE id = ?
      `, [
        targetLocation,
        targetLocation,
        targetLocation,
        action,
        action,
        userName,
        material.id
      ]);

      warehousingId = material.id;
    } else {
      if (!targetLocation) {
        await connection.rollback();
        return auditRecoveryError(
          'LOCATION_REQUIRED_FOR_AUTO_ENTRY',
          'Se requiere la ubicación para crear la entrada automática'
        );
      }

      const source = await findAutomaticAuditEntrySource(connection, normalizedCode);
      if (!source) {
        await connection.rollback();
        return auditRecoveryError(
          'MATERIAL_NOT_FOUND',
          'Material no encontrado en inventario ni en las entradas de almacén'
        );
      }

      if (
        normalizedExpectedPart
        && String(source.numero_parte || '').trim() !== normalizedExpectedPart
      ) {
        await connection.rollback();
        return auditRecoveryError(
          'WRONG_PART',
          `El material pertenece a la parte ${source.numero_parte}, no a ${normalizedExpectedPart}`
        );
      }

      const inserted = await insertAutomaticAuditWarehouseEntry(
        connection,
        source,
        targetLocation,
        userName
      );
      if (!inserted.success) {
        await connection.rollback();
        return inserted;
      }

      warehousingId = inserted.warehousingId;
      action = 'automatic_entry';
    }

    const [materialRows] = await connection.query(`
      SELECT *
      FROM (${getAuditInventorySnapshotQuery()}) ai
      WHERE ai.warehousing_id = ?
      LIMIT 1
    `, [warehousingId]);

    if (materialRows.length === 0) {
      await connection.rollback();
      return auditRecoveryError(
        'AUTO_ENTRY_NOT_IN_INVENTORY',
        'La entrada se preparó, pero no quedó disponible en el inventario'
      );
    }

    const recoveredMaterial = materialRows[0];
    await ensureAutomaticMaterialInAudit(
      connection,
      auditId,
      recoveredMaterial,
      targetLocation,
      userName,
      action
    );

    if (relocatedFrom) {
      await relocateAuditMaterial(connection, auditId, {
        warehousingId: recoveredMaterial.warehousing_id,
        warehousingCode: normalizedCode,
        numeroParte: recoveredMaterial.numero_parte,
        fromLocation: relocatedFrom,
        toLocation: targetLocation,
        usuario: userName
      });
    }

    await connection.commit();
    return {
      success: true,
      material: { ...recoveredMaterial, location: targetLocation },
      action,
      automaticEntry: action !== 'none',
      relocatedFrom
    };
  } catch (err) {
    await connection.rollback();
    throw err;
  } finally {
    connection.release();
  }
}

async function ensureAuditLocationRecord(
  connection,
  auditId,
  location,
  usuario
) {
  await connection.query(`
    INSERT INTO inventory_location_catalog_smd (
      location, active, source, created_at, last_seen_at
    ) VALUES (?, 1, 'AuditScan', NOW(), NOW())
    ON DUPLICATE KEY UPDATE active = 1, last_seen_at = NOW()
  `, [location]);

  const [inserted] = await connection.query(`
    INSERT IGNORE INTO inventory_audit_location_smd (
      audit_id, location, status, total_items, total_qty,
      started_at, started_by
    ) VALUES (?, ?, 'InProgress', 0, 0, NOW(), ?)
  `, [auditId, location, usuario]);

  if (inserted.affectedRows > 0) {
    await connection.query(`
      UPDATE inventory_audit_smd
      SET total_locations = total_locations + 1
      WHERE id = ?
    `, [auditId]);
  }

  return inserted.affectedRows > 0;
}

// Status de la parte tras recontar sus etiquetas. ProcessedOut ya se resolvio
// (faltante confirmado con salida creada), asi que no bloquea el cierre de la
// ubicacion; solo cambia Verified por Discrepancy.
function resolveAuditPartStatus(stats) {
  if (Number(stats?.pending_items || 0) > 0) return 'Mismatch';
  if (Number(stats?.processed_out_items || 0) > 0) return 'MissingConfirmed';
  return 'VerifiedByScan';
}

async function registerPhysicalItem(req, res, next) {
  const connection = await pool.getConnection();
  const location = normalizeAuditLocation(req.body.location);
  const warehousingCode = String(req.body.warehousing_code || '').trim();
  const suppliedPart = String(req.body.numero_parte || '').trim();
  const suppliedLot = String(req.body.numero_lote || '').trim();
  const suppliedSpec = String(req.body.especificacion || '').trim();
  const suppliedUnit = String(req.body.unidad_medida || 'EA').trim() || 'EA';
  let physicalQuantity = parsePhysicalQuantity(req.body.physical_quantity);
  const usuario = String(req.body.usuario || 'Mobile');
  const usuarioId = Number(req.body.usuario_id || 0) || null;

  // physical_quantity es opcional: si no viene, el backend deriva la cantidad
  // desde la etiqueta en almacén o la fuente automática (salida/almacén general).
  if (!location || !warehousingCode) {
    connection.release();
    return res.status(400).json({
      success: false,
      code: 'INVALID_PHYSICAL_ITEM',
      error: 'Se requiere ubicación y código de material'
    });
  }

  try {
    await connection.beginTransaction();

    const [active] = await connection.query(`
      SELECT id
      FROM inventory_audit_smd
      WHERE status = 'InProgress'
      ORDER BY created_at DESC
      LIMIT 1
      FOR UPDATE
    `);
    if (active.length === 0) {
      await connection.rollback();
      return res.status(400).json({
        success: false,
        code: 'NO_ACTIVE_AUDIT',
        error: 'No hay auditoría activa'
      });
    }

    const auditId = active[0].id;
    await ensureAuditLocationRecord(
      connection,
      auditId,
      location,
      usuario
    );

    // Ubicaciones de origen a recalcular tras una reubicación automática.
    const relocatedFrom = new Set();

    const [auditItems] = await connection.query(`
      SELECT id, warehousing_id, location, numero_parte_snapshot,
             numero_lote_material_snapshot, cantidad_snapshot, status
      FROM inventory_audit_item_smd
      WHERE audit_id = ? AND warehousing_code = ?
      LIMIT 1
      FOR UPDATE
    `, [auditId, warehousingCode]);
    if (
      auditItems.length > 0
      && String(auditItems[0].location || '').trim() !== location
    ) {
      // Reubicación automática: el material se escaneó en otra ubicación.
      const previous = String(auditItems[0].location || '').trim();
      if (previous) relocatedFrom.add(previous);
      await connection.query(`
        UPDATE inventory_audit_item_smd
        SET location = ?,
            notas = CONCAT_WS(' | ', NULLIF(notas, ''), ?)
        WHERE id = ?
      `, [
        location,
        `Reubicado de ${previous} a ${location} durante auditoría`,
        auditItems[0].id
      ]);
      auditItems[0].location = location;
    }

    let [materialRows] = await connection.query(`
      SELECT
        cma.*,
        il.id AS inventory_lot_id,
        il.total_entrada,
        il.total_salida,
        il.stock_actual
      FROM control_material_almacen_smd cma
      LEFT JOIN inventario_lotes_smd il
        ON il.codigo_material_recibido = cma.codigo_material_recibido
      WHERE cma.codigo_material_recibido = ?
      ORDER BY cma.id DESC
      LIMIT 1
      FOR UPDATE
    `, [warehousingCode]);

    let createdInventory = false;
    if (materialRows.length === 0) {
      const automaticSource = await findAutomaticAuditEntrySource(
        connection,
        warehousingCode
      );

      // Sin cantidad explícita: tomar la de la fuente automática.
      if (physicalQuantity === null) {
        const sourceQty = Number(
          automaticSource?.cantidad_actual
            || automaticSource?.cantidad_salida
            || 0
        );
        if (sourceQty > 0) physicalQuantity = sourceQty;
      }

      // Advertencia: el código nunca existió en inventario SMD ni en almacén.
      if (!automaticSource && !suppliedPart) {
        await connection.rollback();
        return res.status(404).json({
          success: false,
          code: 'CODE_NOT_FOUND',
          error: `El código ${warehousingCode} no existe en inventario SMD ni en almacén`
        });
      }

      const newPart = suppliedPart || String(
        automaticSource?.numero_parte || ''
      ).trim();
      const newLot = suppliedLot || String(
        automaticSource?.numero_lote_material
          || automaticSource?.numero_lote
          || ''
      ).trim();

      if (!newPart || !newLot) {
        await connection.rollback();
        return res.status(409).json({
          success: false,
          code: 'NEW_MATERIAL_DETAILS_REQUIRED',
          error: 'El material es nuevo. Capture número de parte y número de lote'
        });
      }

      if (physicalQuantity === null || physicalQuantity <= 0) {
        await connection.rollback();
        return res.status(404).json({
          success: false,
          code: 'CODE_NOT_FOUND',
          error: `No se pudo determinar la cantidad para ${warehousingCode}`
        });
      }

      const [catalogRows] = await connection.query(`
        SELECT * FROM materiales
        WHERE numero_parte = ?
        LIMIT 1
      `, [newPart]);
      const catalog = catalogRows[0] || {};
      const inserted = await insertAutomaticAuditWarehouseEntry(
        connection,
        {
          ...(automaticSource || {}),
          codigo_material_recibido: warehousingCode,
          numero_parte: newPart,
          numero_lote_material: newLot,
          cantidad_actual: physicalQuantity,
          especificacion: suppliedSpec
            || automaticSource?.especificacion
            || automaticSource?.especificacion_material
            || catalog.especificacion_material
            || null,
          codigo_material: automaticSource?.codigo_material
            || catalog.codigo_material
            || null,
          codigo_material_final: automaticSource?.codigo_material_final
            || automaticSource?.codigo_material
            || catalog.codigo_material
            || null,
          propiedad_material: 'SMD',
          unidad_medida: automaticSource?.unidad_medida
            || suppliedUnit
            || catalog.unidad_medida
            || 'EA',
          vendedor: automaticSource?.vendedor || catalog.vendedor || null,
          forma_material: automaticSource?.forma_material
            || 'AuditPhysicalEntry',
          iqc_required: automaticSource?.iqc_required || 0,
          iqc_status: automaticSource?.iqc_status || 'NotRequired'
        },
        location,
        usuario
      );
      if (!inserted.success) {
        await connection.rollback();
        return res.status(409).json(inserted);
      }

      createdInventory = true;
      [materialRows] = await connection.query(`
        SELECT
          cma.*,
          il.id AS inventory_lot_id,
          il.total_entrada,
          il.total_salida,
          il.stock_actual
        FROM control_material_almacen_smd cma
        LEFT JOIN inventario_lotes_smd il
          ON il.codigo_material_recibido = cma.codigo_material_recibido
        WHERE cma.id = ?
        LIMIT 1
        FOR UPDATE
      `, [inserted.warehousingId]);
    }

    const material = materialRows[0];

    // Sin cantidad explícita: usar la de la etiqueta (registro de almacén).
    if (physicalQuantity === null) {
      physicalQuantity = Number(material.cantidad_actual || 0);
    }
    if (physicalQuantity === null || physicalQuantity <= 0) {
      await connection.rollback();
      return res.status(409).json({
        success: false,
        code: 'INVALID_PHYSICAL_ITEM',
        error: `El material ${warehousingCode} no tiene una cantidad válida para registrar`
      });
    }

    // Un rollo con registro anulado (cancelado) que aparece físicamente en la
    // auditoría se reactiva y se cuenta. Las decisiones de calidad (cuarentena
    // e IQC) siguen bloqueando más abajo aunque el rollo estuviera cancelado.
    let reactivatedFromCancelled = false;
    if (Number(material.cancelado || 0) === 1) {
      await connection.query(`
        UPDATE control_material_almacen_smd
        SET cancelado = 0
        WHERE id = ?
      `, [material.id]);
      material.cancelado = 0;
      reactivatedFromCancelled = true;
    }

    // Un material en desecho por discrepancia de auditoría (marcado faltante y
    // luego encontrado físicamente) se retorna a inventario. El desecho de
    // calidad (cuarentena Scrapped/Returned) sí sigue bloqueado.
    let returnedFromDesecho = false;
    if (Number(material.estado_desecho || 0) === 1) {
      const [scrapRows] = await connection.query(`
        SELECT 1 FROM quarantine_smd
        WHERE codigo_material_recibido = ?
          AND status IN ('Scrapped', 'Returned')
        LIMIT 1
      `, [warehousingCode]);
      if (scrapRows.length > 0) {
        await connection.rollback();
        return res.status(409).json({
          success: false,
          code: 'MATERIAL_NOT_ELIGIBLE',
          error: 'El material fue desechado por calidad (cuarentena) y no puede retornarse'
        });
      }
      await connection.query(`
        UPDATE control_material_almacen_smd
        SET estado_desecho = 0
        WHERE id = ?
      `, [material.id]);
      material.estado_desecho = 0;
      returnedFromDesecho = true;
    }
    if (!isInventoryCountableIqcStatus(material.iqc_status)) {
      await connection.rollback();
      return res.status(409).json({
        success: false,
        code: 'IQC_NOT_RELEASED',
        error: `El material no está liberado por IQC (${material.iqc_status})`
      });
    }

    const currentLocation = String(
      material.ubicacion_destino || material.ubicacion_salida || ''
    ).trim();
    const stockBefore = Number(material.stock_actual || 0);
    if (
      !createdInventory
      && stockBefore > 0
      && currentLocation
      && currentLocation !== location
    ) {
      // Reubicación automática: el material está registrado en otra ubicación.
      // El UPDATE de control_material_almacen_smd más abajo lo mueve a la
      // ubicación escaneada; aquí solo marcamos el origen para recalcular.
      relocatedFrom.add(currentLocation);
    }

    let inventoryLotId = material.inventory_lot_id;
    let stockAfter = stockBefore;
    const adjustment = getPhysicalAdjustment(stockBefore, physicalQuantity);
    if (!adjustment) {
      await connection.rollback();
      return res.status(409).json({
        success: false,
        code: 'INVALID_INVENTORY_STATE',
        error: 'El inventario actual no tiene una cantidad válida para ajustarse'
      });
    }
    let delta = adjustment.delta;

    if (!inventoryLotId) {
      const [lotInsert] = await connection.query(`
        INSERT INTO inventario_lotes_smd (
          codigo_material_recibido, numero_parte, numero_lote,
          total_entrada, total_salida, unidad_medida, primer_recibo
        ) VALUES (?, ?, ?, ?, 0, ?, NOW())
      `, [
        warehousingCode,
        material.numero_parte,
        material.numero_lote_material,
        physicalQuantity,
        material.unidad_medida || suppliedUnit
      ]);
      inventoryLotId = lotInsert.insertId;
      stockAfter = physicalQuantity;
      delta = physicalQuantity;
      createdInventory = true;
    } else if (Math.abs(delta) >= 0.0001) {
      if (delta > 0) {
        await connection.query(`
          UPDATE inventario_lotes_smd
          SET total_entrada = total_entrada + ?
          WHERE id = ?
        `, [delta, inventoryLotId]);
      } else {
        await connection.query(`
          UPDATE inventario_lotes_smd
          SET total_salida = total_salida + ?, ultima_salida = NOW()
          WHERE id = ?
        `, [Math.abs(delta), inventoryLotId]);
      }

      const [[updatedLot]] = await connection.query(`
        SELECT stock_actual
        FROM inventario_lotes_smd
        WHERE id = ?
        FOR UPDATE
      `, [inventoryLotId]);
      stockAfter = Number(updatedLot?.stock_actual || 0);
      if (Math.abs(stockAfter - physicalQuantity) >= 0.0001) {
        throw new Error('No fue posible sincronizar la cantidad física con el inventario');
      }

      await connection.query(`
        INSERT INTO inventory_adjustment_smd (
          warehousing_id, inventory_lot_id, codigo_material_recibido,
          numero_parte, numero_lote, quantity_before, quantity_after,
          adjustment_quantity, movement_type, reason,
          usuario_registro, usuario_registro_id
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      `, [
        material.id,
        inventoryLotId,
        warehousingCode,
        material.numero_parte,
        material.numero_lote_material,
        stockBefore,
        stockAfter,
        Math.abs(delta),
        delta > 0 ? 'Entry' : 'Exit',
        `Conteo físico auditoría ${auditId} en ${location}`,
        usuario,
        usuarioId
      ]);
    }

    await connection.query(`
      UPDATE control_material_almacen_smd
      SET tiene_salida = 0,
          ubicacion_salida = ?,
          ubicacion_destino = ?
      WHERE id = ?
    `, [location, location, material.id]);

    const partNumber = String(material.numero_parte || suppliedPart).trim();
    const lotNumber = String(
      material.numero_lote_material || suppliedLot
    ).trim();
    const expectedQuantity = auditItems.length > 0
      ? Number(auditItems[0].cantidad_snapshot || 0)
      : 0;
    const isNewAuditItem = auditItems.length === 0;

    if (auditItems.length > 0) {
      await connection.query(`
        UPDATE inventory_audit_item_smd
        SET status = 'Found',
            scanned_at = NOW(),
            scanned_by = ?,
            physical_quantity = ?,
            physical_quantity_recorded_at = NOW(),
            physical_quantity_recorded_by = ?,
            notas = CONCAT_WS(' | ', NULLIF(notas, ''), ?)
        WHERE id = ?
      `, [
        usuario,
        physicalQuantity,
        usuario,
        `Cantidad física capturada: ${physicalQuantity}`,
        auditItems[0].id
      ]);
    } else {
      await connection.query(`
        INSERT INTO inventory_audit_item_smd (
          audit_id, warehousing_id, warehousing_code, location,
          numero_parte_snapshot, numero_lote_material_snapshot,
          cantidad_snapshot, especificacion_snapshot, fecha_recibo_snapshot,
          physical_quantity, physical_quantity_recorded_at,
          physical_quantity_recorded_by, is_new_inventory,
          status, scanned_at, scanned_by, notas
        ) VALUES (?, ?, ?, ?, ?, ?, 0, ?, NOW(), ?, NOW(), ?, ?,
                  'Found', NOW(), ?, ?)
      `, [
        auditId,
        material.id,
        warehousingCode,
        location,
        partNumber,
        lotNumber,
        suppliedSpec || material.especificacion || null,
        physicalQuantity,
        usuario,
        createdInventory ? 1 : 0,
        usuario,
        createdInventory
          ? 'Material nuevo dado de alta durante auditoría'
          : 'Material adicional encontrado durante auditoría'
      ]);
      await connection.query(`
        UPDATE inventory_audit_smd
        SET total_items = total_items + 1
        WHERE id = ?
      `, [auditId]);
    }

    await connection.query(`
      INSERT INTO inventory_audit_part_smd (
        audit_id, location, numero_parte, expected_items, expected_qty,
        status, scanned_items, scanned_qty, confirmed_by, confirmed_at
      ) VALUES (?, ?, ?, 0, 0, 'VerifiedByScan', 1, ?, ?, NOW())
      ON DUPLICATE KEY UPDATE
        confirmed_by = VALUES(confirmed_by),
        confirmed_at = NOW()
    `, [auditId, location, partNumber, physicalQuantity, usuario]);

    const [[partScanStats]] = await connection.query(`
      SELECT
        SUM(CASE WHEN status = 'Found' THEN 1 ELSE 0 END) AS scanned_items,
        COALESCE(SUM(
          CASE WHEN status = 'Found'
            THEN COALESCE(physical_quantity, cantidad_snapshot)
            ELSE 0
          END
        ), 0) AS scanned_qty,
        -- ProcessedOut ya fue resuelto (faltante confirmado con salida creada),
        -- no es pendiente: si contara, la parte volvia a Mismatch y la
        -- ubicacion nunca se cerraba en verde.
        SUM(CASE WHEN status NOT IN ('Found', 'ProcessedOut') THEN 1 ELSE 0 END) AS pending_items,
        SUM(CASE WHEN status = 'ProcessedOut' THEN 1 ELSE 0 END) AS processed_out_items
      FROM inventory_audit_item_smd
      WHERE audit_id = ? AND location = ? AND numero_parte_snapshot = ?
    `, [auditId, location, partNumber]);

    await connection.query(`
      UPDATE inventory_audit_part_smd
      SET scanned_items = ?,
          scanned_qty = ?,
          status = ?,
          confirmed_by = ?,
          confirmed_at = NOW()
      WHERE audit_id = ? AND location = ? AND numero_parte = ?
    `, [
      Number(partScanStats?.scanned_items || 0),
      Number(partScanStats?.scanned_qty || 0),
      resolveAuditPartStatus(partScanStats),
      usuario,
      auditId,
      location,
      partNumber
    ]);

    await connection.query(`
      UPDATE inventory_audit_location_smd ial
      SET total_items = (
            SELECT COUNT(*) FROM inventory_audit_item_smd iai
            WHERE iai.audit_id = ial.audit_id AND iai.location = ial.location
          ),
          total_qty = (
            SELECT COALESCE(SUM(COALESCE(iai.physical_quantity, iai.cantidad_snapshot)), 0)
            FROM inventory_audit_item_smd iai
            WHERE iai.audit_id = ial.audit_id AND iai.location = ial.location
          ),
          status = 'InProgress',
          completed_at = NULL,
          completed_by = NULL
      WHERE ial.audit_id = ? AND ial.location = ?
    `, [auditId, location]);

    // Reubicación automática: recalcular totales de las ubicaciones de origen
    // para que descuenten el material que se movió a la ubicación escaneada.
    for (const oldLocation of relocatedFrom) {
      if (!oldLocation || oldLocation === location) continue;
      await connection.query(`
        UPDATE inventory_audit_location_smd ial
        SET total_items = (
              SELECT COUNT(*) FROM inventory_audit_item_smd iai
              WHERE iai.audit_id = ial.audit_id AND iai.location = ial.location
            ),
            total_qty = (
              SELECT COALESCE(SUM(COALESCE(iai.physical_quantity, iai.cantidad_snapshot)), 0)
              FROM inventory_audit_item_smd iai
              WHERE iai.audit_id = ial.audit_id AND iai.location = ial.location
            )
        WHERE ial.audit_id = ? AND ial.location = ?
      `, [auditId, oldLocation]);
    }

    await connection.commit();
    await checkLocationCompletion(auditId, location);

    const relocatedFromList = [...relocatedFrom].filter(
      (loc) => loc && loc !== location
    );
    const wasRelocated = relocatedFromList.length > 0;

    return res.json({
      success: true,
      message: reactivatedFromCancelled
        ? `Material reactivado (estaba cancelado) en ${location} y contado`
        : returnedFromDesecho
          ? `Material retornado a inventario en ${location} y contado`
          : wasRelocated
            ? `Material reubicado de ${relocatedFromList.join(', ')} a ${location} y contado`
            : createdInventory
              ? 'Material nuevo dado de alta y contado'
              : Math.abs(delta) >= 0.0001
                ? 'Cantidad física aplicada al inventario'
                : 'Cantidad física confirmada',
      auditId,
      location,
      warehousingCode,
      partNumber,
      lotNumber,
      expectedQuantity,
      physicalQuantity,
      quantityDifference: physicalQuantity - expectedQuantity,
      stockBefore,
      stockAfter,
      createdInventory,
      addedToAudit: isNewAuditItem,
      relocated: wasRelocated,
      relocatedFrom: relocatedFromList,
      returned: returnedFromDesecho,
      reactivated: reactivatedFromCancelled
    });
  } catch (err) {
    try {
      await connection.rollback();
    } catch (_) {
      // Conservar el error original.
    }
    next(err);
  } finally {
    connection.release();
  }
}

// ============================================
// GESTION DE AUDITORIA (PC)
// ============================================

// GET /api/audit/active - Obtener auditoria activa
// Devuelve la ultima auditoria con status Pending/InProgress.
const getActiveAudit = async (req, res, next) => {
  try {
    const [rows] = await pool.query(`
      SELECT * FROM inventory_audit_smd 
      WHERE status IN ('Pending', 'InProgress')
      ORDER BY created_at DESC 
      LIMIT 1
    `);

    if (rows.length === 0) {
      return res.json({ active: false, audit: null });
    }

    res.json({ active: true, audit: rows[0] });
  } catch (err) {
    next(err);
  }
};

// POST /api/audit/start - Iniciar nueva auditoria
// 1) Bloquea si existe auditoria activa.
// 2) Genera codigo AUD-YYYYMMDD-HHmm.
// 3) Toma ubicaciones con inventario activo y crea inventory_audit_location_smd.
// 4) Crea inventory_audit_part_smd agrupando por ubicacion + numero_parte.
// 5) Inserta inventory_audit_smd con totales globales.
const startAudit = async (req, res, next) => {
  try {
    const { usuario_inicio, notas } = req.body;

    // Verificar que no haya auditoria activa (Pending o InProgress)
    const [existing] = await pool.query(`
      SELECT id FROM inventory_audit_smd 
      WHERE status IN ('Pending', 'InProgress')
    `);

    if (existing.length > 0) {
      return res.status(400).json({
        error: 'Ya existe una auditoría activa',
        code: 'AUDIT_ALREADY_ACTIVE'
      });
    }

    // Generar codigo de auditoria con timestamp para trazabilidad
    const now = new Date();
    const auditCode = `AUD-${now.getFullYear()}${String(now.getMonth() + 1).padStart(2, '0')}${String(now.getDate()).padStart(2, '0')}-${String(now.getHours()).padStart(2, '0')}${String(now.getMinutes()).padStart(2, '0')}`;

    // Obtener el inventario activo y combinarlo con el catálogo persistente.
    // El catálogo incluye ubicaciones vacías descubiertas en auditorías previas.
    const [inventoryLocations] = await pool.query(`
      SELECT
        ai.location,
        COUNT(*) as total_items,
        SUM(ai.cantidad_actual) as total_qty
      FROM (${getAuditInventorySnapshotQuery()}) ai
      GROUP BY ai.location
      ORDER BY ai.location
    `);

    const [catalogLocations] = await pool.query(`
      SELECT location
      FROM inventory_location_catalog_smd
      WHERE active = 1
      ORDER BY location
    `);

    const locationsByCode = new Map();
    for (const row of catalogLocations) {
      const location = String(row.location || '').trim();
      if (location) {
        locationsByCode.set(location, {
          location,
          total_items: 0,
          total_qty: 0
        });
      }
    }
    for (const row of inventoryLocations) {
      const location = String(row.location || '').trim();
      if (location) {
        locationsByCode.set(location, {
          location,
          total_items: Number(row.total_items || 0),
          total_qty: Number(row.total_qty || 0)
        });
      }
    }
    const locations = [...locationsByCode.values()].sort((a, b) =>
      a.location.localeCompare(b.location, undefined, { numeric: true })
    );

    // Crear auditoria con resumen global (ubicaciones e items esperados)
    const [result] = await pool.query(`
      INSERT INTO inventory_audit_smd (
        audit_code, status, usuario_inicio, notas,
        total_locations, total_items, fecha_inicio, created_at
      ) VALUES (?, 'InProgress', ?, ?, ?, ?, NOW(), NOW())
    `, [
      auditCode,
      usuario_inicio || 'Sistema',
      notas || null,
      locations.length,
      locations.reduce((sum, loc) => sum + loc.total_items, 0)
    ]);

    const auditId = result.insertId;

    // Crear detalle de ubicaciones en status Pending
    // Estas se van moviendo a InProgress/Verified/Discrepancy por los escaneos
    for (const loc of locations) {
      await pool.query(`
        INSERT INTO inventory_audit_location_smd (
          audit_id, location, total_items, total_qty, status
        ) VALUES (?, ?, ?, ?, 'Pending')
      `, [auditId, loc.location, loc.total_items, loc.total_qty]);
    }

    // Congelar todos los lotes incluidos. Sin este snapshot los materiales
    // desaparecian de la auditoria en cuanto una salida llevaba su stock a 0.
    await pool.query(`
      INSERT INTO inventory_audit_item_smd (
        audit_id,
        warehousing_id,
        warehousing_code,
        location,
        numero_parte_snapshot,
        numero_lote_material_snapshot,
        cantidad_snapshot,
        especificacion_snapshot,
        fecha_recibo_snapshot,
        status
      )
      SELECT
        ?,
        ai.warehousing_id,
        ai.codigo_material_recibido,
        ai.location,
        ai.numero_parte,
        ai.numero_lote_material,
        ai.cantidad_actual,
        ai.especificacion,
        ai.fecha_recibo,
        'Pending'
      FROM (${getAuditInventorySnapshotQuery()}) ai
    `, [auditId]);

    // ========== NUEVO: Crear registros por número de parte (audit v2) ==========
    // Agrupar materiales por ubicacion + numero_parte para el flujo de confirmación
    const [partSummary] = await pool.query(`
      SELECT
        iai.location,
        iai.numero_parte_snapshot AS numero_parte,
        COUNT(*) as expected_items,
        SUM(iai.cantidad_snapshot) as expected_qty
      FROM inventory_audit_item_smd iai
      WHERE iai.audit_id = ?
      GROUP BY iai.location, iai.numero_parte_snapshot
      ORDER BY iai.location, iai.numero_parte_snapshot
    `, [auditId]);

    // Insertar registros de partes
    for (const part of partSummary) {
      await pool.query(`
        INSERT INTO inventory_audit_part_smd (
          audit_id, location, numero_parte, expected_items, expected_qty, status
        ) VALUES (?, ?, ?, ?, ?, 'Pending')
      `, [auditId, part.location, part.numero_parte, part.expected_items, part.expected_qty]);
    }
    // ==========================================================================

    // Broadcast inicio de auditoria (hoy no-op, queda para compatibilidad)
    broadcastAuditUpdate({
      action: 'audit_started',
      auditId,
      auditCode,
      totalLocations: locations.length
    });

    res.json({
      success: true,
      auditId,
      auditCode,
      totalLocations: locations.length,
      totalItems: locations.reduce((sum, loc) => sum + loc.total_items, 0),
      totalParts: partSummary.length
    });
  } catch (err) {
    next(err);
  }
};

// POST /api/audit/end - Terminar auditoria
// Paso critico: genera Missing faltantes y convierte Missing a salidas reales.
const endAudit = async (req, res, next) => {
  const connection = await pool.getConnection();

  try {
    const { auditId, usuario_fin, confirmar_discrepancias } = req.body;

    await connection.beginTransaction();

    // Verificar auditoria activa antes de cerrar (evita doble cierre)
    const [audit] = await connection.query(`
      SELECT * FROM inventory_audit_smd WHERE id = ? AND status = 'InProgress'
    `, [auditId]);

    if (audit.length === 0) {
      await connection.rollback();
      return res.status(404).json({ error: 'Auditoría no encontrada o ya finalizada' });
    }

    // Obtener estadisticas de ubicaciones e items para cerrar la auditoria
    // Estas cifras quedan guardadas en inventory_audit_smd para reportes
    const [stats] = await connection.query(`
      SELECT 
        COUNT(CASE WHEN status = 'Verified' THEN 1 END) as verified_locations,
        COUNT(CASE WHEN status = 'Discrepancy' THEN 1 END) as discrepancy_locations,
        COUNT(CASE WHEN status = 'Pending' THEN 1 END) as pending_locations
      FROM inventory_audit_location_smd
      WHERE audit_id = ?
    `, [auditId]);

    const [itemStats] = await connection.query(`
      SELECT 
        COUNT(CASE WHEN status = 'Found' THEN 1 END) as found_items,
        COUNT(CASE WHEN status IN ('Missing', 'ProcessedOut') THEN 1 END) as missing_items,
        COUNT(CASE WHEN status = 'Pending' THEN 1 END) as pending_items
      FROM inventory_audit_item_smd
      WHERE audit_id = ?
    `, [auditId]);

    // La ruta confirm-missing genera las salidas en el momento. Al cerrar solo
    // se procesan faltantes legacy que ya quedaron confirmados en una ubicacion
    // Discrepancy; nunca se convierten ubicaciones pendientes en salida masiva.
    let processedCount = 0;
    let processedQty = 0;
    if (confirmar_discrepancias) {
      const [missingItems] = await connection.query(`
        SELECT
          iai.id AS audit_item_id,
          iai.warehousing_id,
          iai.warehousing_code,
          ${AUDIT_ITEM_PART_EXPR} AS numero_parte,
          ${AUDIT_ITEM_LOT_EXPR} AS numero_lote_material,
          ${AUDIT_ITEM_SPEC_EXPR} AS especificacion
        FROM inventory_audit_item_smd iai
        LEFT JOIN control_material_almacen_smd cma ON cma.id = iai.warehousing_id
        JOIN inventory_audit_location_smd ial
          ON ial.audit_id = iai.audit_id AND ial.location = iai.location
        WHERE iai.audit_id = ?
          AND iai.status = 'Missing'
          AND ial.status = 'Discrepancy'
        FOR UPDATE
      `, [auditId]);

      for (const item of missingItems) {
        const outgoing = await createImmediateAuditOutgoing(
          connection,
          item,
          usuario_fin || 'Sistema'
        );

        await connection.query(`
          UPDATE inventory_audit_item_smd 
          SET status = 'ProcessedOut', processed_at = NOW(), processed_by = ?
          WHERE id = ?
        `, [usuario_fin || 'Sistema', item.audit_item_id]);

        if (outgoing.created) {
          processedCount++;
          processedQty += outgoing.quantity;
        }
      }
    }

    // Finalizar auditoria con resumen de ubicaciones e items
    // status pasa a Completed y se guarda resumen final para historico
    await connection.query(`
      UPDATE inventory_audit_smd SET
        status = 'Completed',
        fecha_fin = NOW(),
        usuario_fin = ?,
        verified_locations = ?,
        discrepancy_locations = ?,
        found_items = ?,
        missing_items = ?
      WHERE id = ?
    `, [
      usuario_fin || 'Sistema',
      stats[0].verified_locations,
      stats[0].discrepancy_locations,
      itemStats[0].found_items || 0,
      itemStats[0].missing_items || 0,
      auditId
    ]);

    await connection.commit();

    // Broadcast fin de auditoria (hoy no-op)
    // Mantener payload por compatibilidad con UI/polling
    broadcastAuditUpdate({
      action: 'audit_ended',
      auditId,
      stats: {
        verifiedLocations: stats[0].verified_locations,
        discrepancyLocations: stats[0].discrepancy_locations,
        foundItems: itemStats[0].found_items || 0,
        missingItems: itemStats[0].missing_items || 0
      }
    });

    res.json({
      success: true,
      message: 'Auditoría finalizada',
      stats: {
        verifiedLocations: stats[0].verified_locations,
        discrepancyLocations: stats[0].discrepancy_locations,
        foundItems: itemStats[0].found_items || 0,
        missingItems: itemStats[0].missing_items || 0,
        processedOut: processedCount,
        processedQty
      }
    });
  } catch (err) {
    await connection.rollback();
    next(err);
  } finally {
    connection.release();
  }
};

// GET /api/audit/locations - Obtener ubicaciones de auditoria activa
// Si no se pasa auditId, usa la auditoria InProgress actual.
const getAuditLocations = async (req, res, next) => {
  try {
    let { auditId } = req.query;

    if (!auditId) {
      // Buscar auditoria activa (solo InProgress)
      const [active] = await pool.query(`
      SELECT id FROM inventory_audit_smd WHERE status = 'InProgress' LIMIT 1
    `);

      if (active.length === 0) {
        return res.json({ locations: [], auditActive: false });
      }

      auditId = active[0].id;
    }

    const [locations] = await pool.query(`
      SELECT 
        ial.*,
        (SELECT COUNT(*) FROM inventory_audit_item_smd iai 
         WHERE iai.audit_id = ial.audit_id 
         AND iai.location = ial.location 
         AND iai.status = 'Found') as scanned_items,
        (SELECT COUNT(*) FROM inventory_audit_item_smd iai 
         WHERE iai.audit_id = ial.audit_id 
         AND iai.location = ial.location 
         AND iai.status IN ('Missing', 'ProcessedOut')) as missing_items
      FROM inventory_audit_location_smd ial
      WHERE ial.audit_id = ?
      ORDER BY ial.location
    `, [auditId]);

    res.json({ locations, auditActive: true, auditId });
  } catch (err) {
    next(err);
  }
};

// GET /api/audit/location-items - Obtener items de una ubicacion
// Devuelve items activos con su audit_status (Pending/Found/Missing).
const getLocationItems = async (req, res, next) => {
  try {
    const { location } = req.query;

    if (!location) {
      return res.status(400).json({ error: 'Se requiere ubicación' });
    }

    // Buscar auditoría activa
    const [active] = await pool.query(`
      SELECT id FROM inventory_audit_smd WHERE status = 'InProgress' LIMIT 1
    `);

    if (active.length === 0) {
      return res.status(400).json({ error: 'No hay auditoría activa', code: 'NO_ACTIVE_AUDIT' });
    }

    const auditId = active[0].id;

    // Obtener el snapshot de materiales de esa ubicacion. Las salidas ya
    // procesadas siguen visibles con status ProcessedOut.
    const [items] = await pool.query(`
      SELECT 
        ai.warehousing_id as id,
        ai.codigo_material_recibido,
        ai.numero_parte,
        ai.numero_lote_material,
        ai.cantidad_actual,
        ai.especificacion,
        ai.fecha_recibo,
        ai.physical_quantity,
        ai.physical_quantity_recorded_at,
        ai.physical_quantity_recorded_by,
        ai.is_new_inventory,
        ai.audit_status,
        ai.scanned_at,
        ai.scanned_by
      FROM (${getPersistedAuditItemsQuery()}) ai
      WHERE ai.audit_id = ? AND ai.location = ?
      ORDER BY ai.codigo_material_recibido
    `, [auditId, location]);

    res.json({ items, location, auditId });
  } catch (err) {
    next(err);
  }
};

// ============================================
// OPERACIONES MOVILES
// ============================================

// POST /api/audit/scan-location - Escanear ubicacion (inicia verificacion de esa ubicacion)
// Cambia la ubicacion a InProgress y devuelve lista de items esperados.
const scanLocation = async (req, res, next) => {
  try {
    const { location, usuario } = req.body;

    if (!location) {
      return res.status(400).json({ error: 'Se requiere ubicación' });
    }

    const normalizedLocation = normalizeAuditLocation(location);
    // Buscar auditoría activa
    const [active] = await pool.query(`
      SELECT id FROM inventory_audit_smd WHERE status = 'InProgress' LIMIT 1
    `);

    if (active.length === 0) {
      return res.status(400).json({
        error: 'No hay auditoría activa',
        code: 'NO_ACTIVE_AUDIT'
      });
    }

    const auditId = active[0].id;

    // Cualquier QR válido pasa a formar parte del catálogo físico. Si estaba
    // vacío o nunca apareció en inventario, quedará precargado en la próxima
    // auditoría.
    await pool.query(`
      INSERT INTO inventory_location_catalog_smd (
        location, active, source, created_at, last_seen_at
      ) VALUES (?, 1, 'AuditScan', NOW(), NOW())
      ON DUPLICATE KEY UPDATE active = 1, last_seen_at = NOW()
    `, [normalizedLocation]);

    // Crear la ubicación dentro de la auditoría si todavía no estaba en el
    // snapshot. Esto permite verificar ubicaciones nuevas o físicamente vacías.
    let [loc] = await pool.query(`
      SELECT * FROM inventory_audit_location_smd 
      WHERE audit_id = ? AND location = ?
    `, [auditId, normalizedLocation]);

    let createdLocation = false;
    if (loc.length === 0) {
      const [insertedLocation] = await pool.query(`
        INSERT IGNORE INTO inventory_audit_location_smd (
          audit_id, location, status, total_items, total_qty,
          started_at, started_by
        ) VALUES (?, ?, 'InProgress', 0, 0, NOW(), ?)
      `, [auditId, normalizedLocation, usuario || 'Mobile']);
      createdLocation = insertedLocation.affectedRows > 0;
      if (createdLocation) {
        await pool.query(`
          UPDATE inventory_audit_smd
          SET total_locations = total_locations + 1
          WHERE id = ?
        `, [auditId]);
      }
      [loc] = await pool.query(`
        SELECT * FROM inventory_audit_location_smd
        WHERE audit_id = ? AND location = ?
      `, [auditId, normalizedLocation]);
    }

    // Marcar ubicacion como en progreso
    // Solo cambia si estaba Pending para no pisar estados finales
    if (loc[0].status === 'Pending') {
      await pool.query(`
        UPDATE inventory_audit_location_smd 
        SET status = 'InProgress', started_at = NOW(), started_by = ?
        WHERE id = ?
      `, [usuario || 'Mobile', loc[0].id]);
    }

    // El snapshot se creó al iniciar la auditoría. Antes de devolver la
    // ubicación, incorporar materiales que hayan entrado o cambiado de
    // ubicación mientras la auditoría seguía abierta.
    const syncConnection = await pool.getConnection();
    let inventorySync;
    try {
      await syncConnection.beginTransaction();
      inventorySync = await syncAuditLocationWithInventory(
        syncConnection,
        auditId,
        normalizedLocation,
        usuario || 'Mobile'
      );
      await syncConnection.commit();
    } catch (syncError) {
      await syncConnection.rollback();
      throw syncError;
    } finally {
      syncConnection.release();
    }

    // Obtener items de la ubicación
    const [items] = await pool.query(`
      SELECT 
        ai.warehousing_id,
        ai.codigo_material_recibido,
        ai.numero_parte,
        ai.numero_lote_material,
        ai.cantidad_actual,
        ai.especificacion,
        ai.audit_status
      FROM (${getPersistedAuditItemsQuery()}) ai
      WHERE ai.audit_id = ? AND ai.location = ?
      ORDER BY ai.codigo_material_recibido
    `, [auditId, normalizedLocation]);

    // Broadcast actualizacion (hoy no-op)
    broadcastAuditUpdate({
      action: 'location_started',
      auditId,
      location: normalizedLocation,
      startedBy: usuario
    });

    const response = {
      success: true,
      location: normalizedLocation,
      auditId,
      items,
      totalItems: items.length,
      pendingItems: items.filter(i => i.audit_status === 'Pending').length,
      scannedItems: items.filter(i => i.audit_status === 'Found').length
    };
    response.createdLocation = createdLocation;
    response.emptyLocation = items.length === 0;
    response.inventorySync = inventorySync;

    if (shouldReturnLocationSummary(req)) {
      const summary = await buildLocationSummaryPayload(auditId, normalizedLocation);
      response.parts = summary.parts;
      response.progress = summary.progress;
    }

    res.json(response);
  } catch (err) {
    next(err);
  }
};

// POST /api/audit/reopen-location - Reabrir una ubicación cerrada.
// Conserva el snapshot y reinicia sus estados para mantener trazabilidad.
const reopenLocation = async (req, res, next) => {
  const connection = await pool.getConnection();
  try {
    const normalizedLocation = String(req.body.location ?? '').trim();
    const usuario = req.body.usuario || 'Mobile';
    if (!normalizedLocation) {
      return res.status(400).json({ error: 'Se requiere ubicación' });
    }

    await connection.beginTransaction();
    const [active] = await connection.query(`
      SELECT id FROM inventory_audit_smd
      WHERE status = 'InProgress' LIMIT 1 FOR UPDATE
    `);
    if (active.length === 0) {
      await connection.rollback();
      return res.status(400).json({ error: 'No hay auditoría activa', code: 'NO_ACTIVE_AUDIT' });
    }

    const auditId = active[0].id;
    const [locations] = await connection.query(`
      SELECT id, status FROM inventory_audit_location_smd
      WHERE audit_id = ? AND location = ? LIMIT 1 FOR UPDATE
    `, [auditId, normalizedLocation]);
    if (locations.length === 0) {
      await connection.rollback();
      return res.status(404).json({ error: 'Ubicación no encontrada en la auditoría', code: 'LOCATION_NOT_FOUND' });
    }
    if (!['Verified', 'Discrepancy'].includes(locations[0].status)) {
      await connection.rollback();
      return res.json({ success: false, error: 'La ubicación todavía no está cerrada', status: locations[0].status });
    }

    await connection.query(`
      UPDATE inventory_audit_location_smd
      SET status = 'InProgress', started_at = NOW(), started_by = ?,
          completed_at = NULL, completed_by = NULL
      WHERE id = ?
    `, [usuario, locations[0].id]);
    await connection.query(`
      UPDATE inventory_audit_part_smd
      SET status = 'Pending', confirmed_by = NULL, confirmed_at = NULL,
          flagged_by = NULL, flagged_at = NULL,
          scanned_items = 0, scanned_qty = 0
      WHERE audit_id = ? AND location = ?
    `, [auditId, normalizedLocation]);
    await connection.query(`
      UPDATE inventory_audit_item_smd
      SET status = 'Pending', scanned_at = NULL, scanned_by = NULL,
          processed_at = NULL, processed_by = NULL
      WHERE audit_id = ? AND location = ?
    `, [auditId, normalizedLocation]);

    await connection.commit();
    res.json({ success: true, auditId, location: normalizedLocation, status: 'InProgress' });
  } catch (err) {
    await connection.rollback();
    next(err);
  } finally {
    connection.release();
  }
};

// POST /api/audit/scan-item - Escanear material
// Reglas: valida auditoria activa, material existente y ubicacion correcta.
const scanItem = async (req, res, next) => {
  try {
    const { warehousing_code, location, usuario } = req.body;

    if (!warehousing_code) {
      return res.status(400).json({ error: 'Se requiere código de material' });
    }

    // Buscar auditoría activa
    const [active] = await pool.query(`
      SELECT id FROM inventory_audit_smd WHERE status = 'InProgress' LIMIT 1
    `);

    if (active.length === 0) {
      return res.status(400).json({ error: 'No hay auditoría activa', code: 'NO_ACTIVE_AUDIT' });
    }

    const auditId = active[0].id;

    // Buscar el material desde el inventario consolidado. Si ya tuvo salida
    // o nunca fue ingresado a SMD, recuperarlo/crearlo en la ubicación
    // escaneada antes de registrarlo como encontrado.
    let mat = await getAuditInventoryMaterialByCode(warehousing_code);
    let automaticRecovery = null;

    if (
      !mat
      || Number(mat.tiene_salida || 0) === 1
      || Number(mat.total_salida || 0) > 0
    ) {
      automaticRecovery = await recoverAuditMaterialForScan(
        auditId,
        warehousing_code,
        location,
        usuario
      );

      if (!automaticRecovery.success) {
        return res.json(automaticRecovery);
      }
      mat = automaticRecovery.material;
    }

    mat.id = mat.warehousing_id;
    mat.ubicacion_salida = mat.location;

    // El escaneo confirma fisicamente el material en esta ubicacion: si estaba
    // registrado en otra, se reubica (reingreso) en vez de rechazar el escaneo.
    const directRelocationFrom = location && mat.location !== location
      ? String(mat.location || '').trim()
      : null;
    const relocatedFrom = automaticRecovery?.relocatedFrom || directRelocationFrom;
    if (directRelocationFrom) {
      await relocateAuditMaterial(pool, auditId, {
        warehousingId: mat.id,
        warehousingCode: warehousing_code,
        numeroParte: mat.numero_parte,
        fromLocation: directRelocationFrom,
        toLocation: location,
        usuario
      });
      mat.location = location;
      mat.ubicacion_salida = location;
    }

    // Verificar si ya fue escaneado para evitar duplicados
    // Si existe y esta Found, se bloquea nuevo escaneo
    const [existing] = await pool.query(`
      SELECT id, status FROM inventory_audit_item_smd
      WHERE audit_id = ? AND warehousing_id = ?
    `, [auditId, mat.id]);

    if (existing.length > 0 && existing[0].status === 'Found') {
      return res.json({
        success: false,
        error: 'Este material ya fue escaneado',
        code: 'ALREADY_SCANNED'
      });
    }

    // Registrar escaneo: crea o actualiza inventory_audit_item_smd como Found
    if (existing.length > 0) {
      await pool.query(`
        UPDATE inventory_audit_item_smd SET
          status = 'Found',
          scanned_at = NOW(),
          scanned_by = ?
        WHERE id = ?
      `, [usuario || 'Mobile', existing[0].id]);
    } else {
      await pool.query(`
        INSERT INTO inventory_audit_item_smd (
          audit_id, warehousing_id, warehousing_code, location, status, scanned_at, scanned_by
        ) VALUES (?, ?, ?, ?, 'Found', NOW(), ?)
      `, [auditId, mat.id, warehousing_code, mat.ubicacion_salida, usuario || 'Mobile']);
    }

    // Verificar si la ubicacion esta completa con el snapshot guardado al iniciar la auditoria.
    const [locationStats] = await pool.query(`
      SELECT 
        (SELECT total_items FROM inventory_audit_location_smd
         WHERE audit_id = ? AND location = ?) as total,
        (SELECT COUNT(*) FROM inventory_audit_item_smd 
         WHERE audit_id = ? AND location = ? AND status = 'Found') as scanned
    `, [auditId, mat.ubicacion_salida, auditId, mat.ubicacion_salida]);

    const isLocationComplete = locationStats[0].total === locationStats[0].scanned;

    if (isLocationComplete) {
      await pool.query(`
        UPDATE inventory_audit_location_smd SET
          status = 'Verified',
          completed_at = NOW()
        WHERE audit_id = ? AND location = ?
      `, [auditId, mat.ubicacion_salida]);
    }

    // Broadcast actualizacion (hoy no-op)
    broadcastAuditUpdate({
      action: 'item_scanned',
      auditId,
      location: mat.ubicacion_salida,
      warehousingCode: warehousing_code,
      scannedBy: usuario,
      locationComplete: isLocationComplete,
      locationStats: {
        total: locationStats[0].total,
        scanned: locationStats[0].scanned
      }
    });

    res.json({
      success: true,
      message: relocatedFrom
        ? `Material reubicado de ${relocatedFrom} a ${location} y verificado`
        : automaticRecovery?.automaticEntry
          ? 'Material ingresado automáticamente y verificado'
          : 'Material verificado',
      warehousingCode: warehousing_code,
      partNumber: mat.numero_parte,
      location: mat.ubicacion_salida,
      relocated: relocatedFrom !== null,
      relocatedFrom,
      automaticEntry: automaticRecovery?.automaticEntry === true || relocatedFrom !== null,
      inventoryAction: automaticRecovery?.action || 'none',
      locationComplete: isLocationComplete,
      locationStats: {
        total: locationStats[0].total,
        scanned: locationStats[0].scanned
      }
    });
  } catch (err) {
    next(err);
  }
};

// POST /api/audit/mark-missing - Marcar material como no encontrado
// Crea o actualiza inventory_audit_item_smd con status Missing y pone la ubicacion en Discrepancy.
const markMissing = async (req, res, next) => {
  try {
    const { warehousing_id, location, usuario, notas } = req.body;

    if (!warehousing_id) {
      return res.status(400).json({ error: 'Se requiere ID del material' });
    }

    // Buscar auditoría activa
    const [active] = await pool.query(`
      SELECT id FROM inventory_audit_smd WHERE status = 'InProgress' LIMIT 1
    `);

    if (active.length === 0) {
      return res.status(400).json({ error: 'No hay auditoría activa' });
    }

    const auditId = active[0].id;

    // Obtener datos del material desde el inventario consolidado.
    const mat = await getAuditInventoryMaterialByWarehousingId(warehousing_id);

    if (
      !mat
      || Number(mat.tiene_salida || 0) === 1
      || Number(mat.total_salida || 0) > 0
    ) {
      return res.status(404).json({ error: 'Material no encontrado' });
    }

    mat.ubicacion_salida = mat.location;

    // Verificar si ya existe registro
    const [existing] = await pool.query(`
      SELECT id FROM inventory_audit_item_smd
      WHERE audit_id = ? AND warehousing_id = ?
    `, [auditId, warehousing_id]);

    if (existing.length > 0) {
      await pool.query(`
        UPDATE inventory_audit_item_smd SET
          status = 'Missing',
          scanned_at = NOW(),
          scanned_by = ?,
          notas = ?
        WHERE id = ?
      `, [usuario || 'Mobile', notas, existing[0].id]);
    } else {
      await pool.query(`
        INSERT INTO inventory_audit_item_smd (
          audit_id, warehousing_id, warehousing_code, location, status, scanned_at, scanned_by, notas
        ) VALUES (?, ?, ?, ?, 'Missing', NOW(), ?, ?)
      `, [auditId, warehousing_id, mat.codigo_material_recibido, mat.ubicacion_salida, usuario || 'Mobile', notas]);
    }

    // Actualizar estado de ubicacion para reflejar discrepancia
    await pool.query(`
      UPDATE inventory_audit_location_smd SET
        status = 'Discrepancy'
      WHERE audit_id = ? AND location = ? AND status != 'Discrepancy'
    `, [auditId, mat.ubicacion_salida]);

    // Broadcast actualizacion (hoy no-op)
    broadcastAuditUpdate({
      action: 'item_missing',
      auditId,
      location: mat.ubicacion_salida,
      warehousingCode: mat.codigo_material_recibido,
      markedBy: usuario
    });

    res.json({
      success: true,
      message: 'Material marcado como no encontrado',
      note: 'El supervisor deberá confirmar esta discrepancia al finalizar la auditoría'
    });
  } catch (err) {
    next(err);
  }
};

// POST /api/audit/complete-location - Marcar ubicacion como completada
// Cierra la ubicacion y marca pendientes como Missing automaticamente.
const completeLocation = async (req, res, next) => {
  try {
    const location = normalizeAuditLocation(req.body.location);
    const usuario = req.body.usuario || req.body.completedBy || 'Mobile';

    if (!location) {
      return res.status(400).json({ error: 'Se requiere ubicación' });
    }

    // Buscar auditoría activa
    const [active] = await pool.query(`
      SELECT id FROM inventory_audit_smd WHERE status = 'InProgress' LIMIT 1
    `);

    if (active.length === 0) {
      return res.status(400).json({ error: 'No hay auditoría activa' });
    }

    const auditId = active[0].id;

    // Obtener items pendientes del snapshot de esta ubicacion.
    // Cualquier pendiente se considera Missing al cerrar ubicacion.
    const [pending] = await pool.query(`
      SELECT warehousing_id AS id, warehousing_code AS codigo_material_recibido
      FROM inventory_audit_item_smd
      WHERE audit_id = ? AND location = ? AND status = 'Pending'
    `, [auditId, location]);

    // Marcar items pendientes como Missing
    // Mantiene trazabilidad de quien cerro la ubicacion
    for (const item of pending) {
      const [existingItem] = await pool.query(`
        SELECT id FROM inventory_audit_item_smd WHERE audit_id = ? AND warehousing_id = ?
      `, [auditId, item.id]);

      if (existingItem.length > 0) {
        await pool.query(`
          UPDATE inventory_audit_item_smd SET
            status = 'Missing',
            scanned_at = NOW(),
            scanned_by = ?,
            notas = 'Marcado automáticamente al completar ubicación'
          WHERE id = ?
        `, [usuario, existingItem[0].id]);
      } else {
        await pool.query(`
          INSERT INTO inventory_audit_item_smd (
            audit_id, warehousing_id, warehousing_code, location, status, scanned_at, scanned_by, notas
          ) VALUES (?, ?, ?, ?, 'Missing', NOW(), ?, 'Marcado automáticamente al completar ubicación')
        `, [auditId, item.id, item.codigo_material_recibido, location, usuario]);
      }
    }

    // Actualizar estado de ubicacion: Verified si todo encontrado, Discrepancy si faltantes
    const hasMissing = pending.length > 0;
    await pool.query(`
      UPDATE inventory_audit_location_smd SET
        status = ?,
        completed_at = NOW(),
        completed_by = ?
      WHERE audit_id = ? AND location = ?
    `, [hasMissing ? 'Discrepancy' : 'Verified', usuario, auditId, location]);

    // Broadcast actualizacion (hoy no-op)
    broadcastAuditUpdate({
      action: 'location_completed',
      auditId,
      location,
      status: hasMissing ? 'Discrepancy' : 'Verified',
      missingItems: pending.length,
      completedBy: usuario
    });

    res.json({
      success: true,
      location,
      status: hasMissing ? 'Discrepancy' : 'Verified',
      missingItems: pending.length
    });
  } catch (err) {
    next(err);
  }
};

// ============================================
// HISTORIAL (CONSULTA)
// ============================================

// GET /api/audit/history - Historial de auditorias
// Filtra por rango de fechas opcional y solo status Completed.
const getAuditHistory = async (req, res, next) => {
  try {
    const { fecha_inicio, fecha_fin } = req.query;

    let query = `
      SELECT 
        ia.*,
        (SELECT COUNT(*) FROM inventory_audit_location_smd ial WHERE ial.audit_id = ia.id) as total_locations_count
      FROM inventory_audit_smd ia
      WHERE ia.status = 'Completed'
    `;
    const params = [];

    if (fecha_inicio && fecha_fin) {
      query += ' AND DATE(ia.fecha_inicio) BETWEEN ? AND ?';
      params.push(fecha_inicio, fecha_fin);
    }

    query += ' ORDER BY ia.fecha_inicio DESC LIMIT 100';

    const [rows] = await pool.query(query, params);
    res.json(rows);
  } catch (err) {
    next(err);
  }
};

// GET /api/audit/history/:id - Detalle de una auditoria historica
// Devuelve auditoria, ubicaciones, items y resumen por numero de parte.
const getAuditHistoryDetail = async (req, res, next) => {
  try {
    const { id } = req.params;

    // Auditoría
    const [audit] = await pool.query(`
      SELECT * FROM inventory_audit_smd WHERE id = ?
    `, [id]);

    if (audit.length === 0) {
      return res.status(404).json({ error: 'Auditoría no encontrada' });
    }

    // Ubicaciones
    const [locations] = await pool.query(`
      SELECT * FROM inventory_audit_location_smd WHERE audit_id = ? ORDER BY location
    `, [id]);

    // Items individuales con detalles del material
    const [items] = await pool.query(`
      SELECT 
        iai.id,
        iai.warehousing_code,
        iai.location,
        iai.status,
        iai.scanned_at,
        iai.scanned_by,
        ${AUDIT_ITEM_PART_EXPR} AS numero_parte,
        ${AUDIT_ITEM_QTY_EXPR} AS cantidad_actual,
        ${AUDIT_ITEM_LOT_EXPR} AS numero_lote_material
      FROM inventory_audit_item_smd iai
      LEFT JOIN control_material_almacen_smd cma ON iai.warehousing_id = cma.id
      WHERE iai.audit_id = ?
      ORDER BY iai.location, numero_parte
    `, [id]);

    // Resumen por número de parte
    const [byPartNumber] = await pool.query(`
      SELECT 
        ${AUDIT_ITEM_PART_EXPR} AS numero_parte,
        SUM(CASE WHEN iai.status = 'Found' THEN 1 ELSE 0 END) as found_count,
        SUM(CASE WHEN iai.status = 'Missing' THEN 1 ELSE 0 END) as missing_count,
        SUM(CASE WHEN iai.status = 'ProcessedOut' THEN 1 ELSE 0 END) as processed_count
      FROM inventory_audit_item_smd iai
      LEFT JOIN control_material_almacen_smd cma ON iai.warehousing_id = cma.id
      WHERE iai.audit_id = ?
      GROUP BY ${AUDIT_ITEM_PART_EXPR}
      ORDER BY numero_parte
    `, [id]);

    res.json({
      audit: audit[0],
      locations,
      items,
      byPartNumber
    });
  } catch (err) {
    next(err);
  }
};

// GET /api/audit/summary - Resumen de auditoria activa
// Agrupa estadisticas por status para UI y supervisores.
const getAuditSummary = async (req, res, next) => {
  try {
    // Buscar auditoria activa (solo InProgress)
    const [active] = await pool.query(`
      SELECT * FROM inventory_audit_smd WHERE status = 'InProgress' LIMIT 1
    `);

    if (active.length === 0) {
      return res.json({ active: false });
    }

    const auditId = active[0].id;

    // Estadísticas de ubicaciones
    const [locStats] = await pool.query(`
      SELECT 
        status,
        COUNT(*) as count
      FROM inventory_audit_location_smd
      WHERE audit_id = ?
      GROUP BY status
    `, [auditId]);

    // Estadísticas de items
    const [itemStats] = await pool.query(`
      SELECT 
        status,
        COUNT(*) as count
      FROM inventory_audit_item_smd
      WHERE audit_id = ?
      GROUP BY status
    `, [auditId]);

    // Ubicaciones detalladas
    const [locations] = await pool.query(`
      SELECT 
        ial.*,
        (SELECT COUNT(*) FROM inventory_audit_item_smd iai 
         WHERE iai.audit_id = ial.audit_id AND iai.location = ial.location AND iai.status = 'Found') as found_count,
        (SELECT COUNT(*) FROM inventory_audit_item_smd iai 
         WHERE iai.audit_id = ial.audit_id AND iai.location = ial.location
           AND iai.status IN ('Missing', 'ProcessedOut')) as missing_count
      FROM inventory_audit_location_smd ial
      WHERE ial.audit_id = ?
      ORDER BY 
        CASE ial.status 
          WHEN 'Discrepancy' THEN 1 
          WHEN 'InProgress' THEN 2 
          WHEN 'Verified' THEN 3 
          ELSE 4 
        END,
        ial.location
    `, [auditId]);

    res.json({
      active: true,
      audit: active[0],
      locationStats: locStats,
      itemStats: itemStats,
      locations
    });
  } catch (err) {
    next(err);
  }
};

// GET /api/audit/compare - Comparar dos auditorias
// Compara por numero_parte y cantidades para ver variaciones entre periodos.
const compareAudits = async (req, res, next) => {
  try {
    const { audit1, audit2 } = req.query;

    if (!audit1 || !audit2) {
      return res.status(400).json({ error: 'Se requieren dos auditorías para comparar' });
    }

    // Obtener items de ambas auditorías agrupados SOLO por número de parte
    // Hacer JOIN con control_material_almacen_smd para obtener numero_parte y cantidad
    const [items1] = await pool.query(`
      SELECT 
        ${AUDIT_ITEM_PART_EXPR} AS numero_parte,
        COUNT(*) as total_items,
        SUM(CASE WHEN iai.status = 'Found' THEN 1 ELSE 0 END) as found_items,
        SUM(CASE WHEN iai.status IN ('Missing', 'ProcessedOut') THEN 1 ELSE 0 END) as missing_items,
        SUM(${AUDIT_ITEM_QTY_EXPR}) as total_qty,
        SUM(CASE WHEN iai.status = 'Found' THEN ${AUDIT_ITEM_QTY_EXPR} ELSE 0 END) as qty_found,
        SUM(CASE WHEN iai.status IN ('Missing', 'ProcessedOut') THEN ${AUDIT_ITEM_QTY_EXPR} ELSE 0 END) as qty_missing
      FROM inventory_audit_item_smd iai
      LEFT JOIN control_material_almacen_smd cma ON iai.warehousing_id = cma.id
      WHERE iai.audit_id = ?
      GROUP BY ${AUDIT_ITEM_PART_EXPR}
      ORDER BY numero_parte
    `, [audit1]);

    const [items2] = await pool.query(`
      SELECT 
        ${AUDIT_ITEM_PART_EXPR} AS numero_parte,
        COUNT(*) as total_items,
        SUM(CASE WHEN iai.status = 'Found' THEN 1 ELSE 0 END) as found_items,
        SUM(CASE WHEN iai.status IN ('Missing', 'ProcessedOut') THEN 1 ELSE 0 END) as missing_items,
        SUM(${AUDIT_ITEM_QTY_EXPR}) as total_qty,
        SUM(CASE WHEN iai.status = 'Found' THEN ${AUDIT_ITEM_QTY_EXPR} ELSE 0 END) as qty_found,
        SUM(CASE WHEN iai.status IN ('Missing', 'ProcessedOut') THEN ${AUDIT_ITEM_QTY_EXPR} ELSE 0 END) as qty_missing
      FROM inventory_audit_item_smd iai
      LEFT JOIN control_material_almacen_smd cma ON iai.warehousing_id = cma.id
      WHERE iai.audit_id = ?
      GROUP BY ${AUDIT_ITEM_PART_EXPR}
      ORDER BY numero_parte
    `, [audit2]);

    // Crear mapa de items de auditoría 1 (solo por numero_parte)
    const map1 = new Map();
    items1.forEach(item => {
      map1.set(item.numero_parte, item);
    });

    // Crear mapa de items de auditoría 2 (solo por numero_parte)
    const map2 = new Map();
    items2.forEach(item => {
      map2.set(item.numero_parte, item);
    });

    // Combinar todas las claves únicas
    const allKeys = new Set([...map1.keys(), ...map2.keys()]);

    // Generar comparación
    const comparison = [];
    allKeys.forEach(numeroParte => {
      const item1 = map1.get(numeroParte);
      const item2 = map2.get(numeroParte);

      const qty1 = item1 ? (item1.found_items || 0) : 0;
      const qty2 = item2 ? (item2.found_items || 0) : 0;
      const diff = qty2 - qty1;

      // Cantidades de material
      const totalQty1 = item1 ? (item1.total_qty || 0) : 0;
      const totalQty2 = item2 ? (item2.total_qty || 0) : 0;
      const qtyFound1 = item1 ? (item1.qty_found || 0) : 0;
      const qtyFound2 = item2 ? (item2.qty_found || 0) : 0;
      const qtyMissing1 = item1 ? (item1.qty_missing || 0) : 0;
      const qtyMissing2 = item2 ? (item2.qty_missing || 0) : 0;

      comparison.push({
        numero_parte: numeroParte,
        qty1: qty1,
        qty2: qty2,
        missing1: item1 ? (item1.missing_items || 0) : 0,
        missing2: item2 ? (item2.missing_items || 0) : 0,
        // Cantidades de material
        total_qty1: totalQty1,
        total_qty2: totalQty2,
        qty_found1: qtyFound1,
        qty_found2: qtyFound2,
        qty_missing1: qtyMissing1,
        qty_missing2: qtyMissing2,
        qty_difference: qtyFound2 - qtyFound1,
        difference: diff,
        status: diff > 0 ? 'increased' : (diff < 0 ? 'decreased' : 'same')
      });
    });

    // Ordenar por diferencia (los mayores cambios primero)
    comparison.sort((a, b) => Math.abs(b.difference) - Math.abs(a.difference));

    // Obtener info de las auditorías
    const [audits] = await pool.query(`
      SELECT id, audit_code, fecha_inicio, fecha_fin, status
      FROM inventory_audit_smd
      WHERE id IN (?, ?)
    `, [audit1, audit2]);

    res.json({
      audit1: audits.find(a => a.id == audit1),
      audit2: audits.find(a => a.id == audit2),
      comparison,
      summary: {
        totalItems: comparison.length,
        increased: comparison.filter(c => c.status === 'increased').length,
        decreased: comparison.filter(c => c.status === 'decreased').length,
        same: comparison.filter(c => c.status === 'same').length
      }
    });
  } catch (err) {
    next(err);
  }
};

// ============================================
// AUDIT V2 - Flujo por número de parte
// ============================================

async function enrichAuditPartSummary(auditId, location, parts) {
  const [locationRows] = await pool.query(`
    SELECT status FROM inventory_audit_location_smd
    WHERE audit_id = ? AND location = ? LIMIT 1
  `, [auditId, location]);

  const [lotRows] = await pool.query(`
    SELECT
      ai.numero_parte,
      ai.numero_lote_material AS numero_lote,
      SUM(ai.cantidad_actual) AS stock_actual
    FROM (${getAuditInventorySnapshotQuery()}) ai
    WHERE ai.location = ?
    GROUP BY ai.numero_parte, ai.numero_lote_material
    ORDER BY ai.numero_parte, ai.numero_lote_material
  `, [location]);

  const [physicalRows] = await pool.query(`
    SELECT
      numero_parte_snapshot AS numero_parte,
      COUNT(CASE WHEN physical_quantity IS NOT NULL THEN 1 END) AS physical_items,
      COALESCE(SUM(
        CASE WHEN physical_quantity IS NOT NULL THEN physical_quantity ELSE 0 END
      ), 0) AS physical_qty,
      COALESCE(SUM(
        CASE WHEN physical_quantity IS NOT NULL
          THEN physical_quantity - COALESCE(cantidad_snapshot, 0)
          ELSE 0
        END
      ), 0) AS quantity_difference,
      COALESCE(SUM(is_new_inventory), 0) AS new_items
    FROM inventory_audit_item_smd
    WHERE audit_id = ? AND location = ?
    GROUP BY numero_parte_snapshot
  `, [auditId, location]);
  const physicalByPart = new Map(
    physicalRows.map(row => [String(row.numero_parte || ''), row])
  );

  const lotsByPart = new Map();
  for (const lot of lotRows) {
    if (!lotsByPart.has(lot.numero_parte)) {
      lotsByPart.set(lot.numero_parte, []);
    }
    lotsByPart.get(lot.numero_parte).push({
      numero_lote: lot.numero_lote,
      stock_actual: Number(lot.stock_actual || 0)
    });
  }
  for (const part of parts) {
    part.lotes = lotsByPart.get(part.numero_parte) || [];
    const physical = physicalByPart.get(String(part.numero_parte || ''));
    part.physical_items = Number(physical?.physical_items || 0);
    part.physical_qty = Number(physical?.physical_qty || 0);
    part.quantity_difference = Number(physical?.quantity_difference || 0);
    part.new_items = Number(physical?.new_items || 0);
  }

  return locationRows[0]?.status || 'Pending';
}

// GET /api/audit/location-summary - Resumen de partes por ubicación
// Devuelve lista de partes con cantidades esperadas y status
async function buildLocationSummaryPayload(auditId, location) {
  const normalizedLocation = String(location || '').trim();

  const [parts] = await pool.query(`
    SELECT 
      iap.id,
      iap.numero_parte,
      iap.expected_items,
      iap.expected_qty,
      iap.status,
      iap.scanned_items,
      iap.scanned_qty,
      iap.confirmed_by,
      iap.confirmed_at,
      iap.flagged_by,
      iap.flagged_at
    FROM inventory_audit_part_smd iap
    WHERE iap.audit_id = ? AND iap.location = ?
    ORDER BY iap.numero_parte
  `, [auditId, normalizedLocation]);

  if (parts.length === 0) {
    const [summary] = await pool.query(`
      SELECT 
        ai.numero_parte,
        COUNT(*) as expected_items,
        SUM(ai.cantidad_actual) as expected_qty
      FROM (${getPersistedAuditItemsQuery()}) ai
      WHERE ai.audit_id = ? AND ai.location = ?
      GROUP BY ai.numero_parte
      ORDER BY ai.numero_parte
    `, [auditId, normalizedLocation]);

    if (summary.length > 0) {
      for (const part of summary) {
        await pool.query(`
          INSERT INTO inventory_audit_part_smd (
            audit_id, location, numero_parte, expected_items, expected_qty, status
          ) VALUES (?, ?, ?, ?, ?, 'Pending')
        `, [auditId, normalizedLocation, part.numero_parte, part.expected_items, part.expected_qty]);
      }

      const [partsRefreshed] = await pool.query(`
        SELECT 
          iap.id,
          iap.numero_parte,
          iap.expected_items,
          iap.expected_qty,
          iap.status,
          iap.scanned_items,
          iap.scanned_qty,
          iap.confirmed_by,
          iap.confirmed_at,
          iap.flagged_by,
          iap.flagged_at
        FROM inventory_audit_part_smd iap
        WHERE iap.audit_id = ? AND iap.location = ?
        ORDER BY iap.numero_parte
      `, [auditId, normalizedLocation]);

      parts.splice(0, parts.length, ...partsRefreshed);
    }
  }

  const locationStatus = await enrichAuditPartSummary(
    auditId,
    normalizedLocation,
    parts
  );
  const total = parts.length;
  const confirmed = parts.filter(p => ['Ok', 'VerifiedByScan', 'MissingConfirmed'].includes(p.status)).length;
  const mismatch = parts.filter(p => p.status === 'Mismatch').length;
  const pending = parts.filter(p => p.status === 'Pending').length;

  return {
    success: true,
    location: normalizedLocation,
    auditId,
    parts,
    locationStatus,
    progress: {
      total,
      confirmed,
      mismatch,
      pending
    }
  };
}

function shouldReturnLocationSummary(req) {
  const queryMode = String(req.query?.response_mode || '').toLowerCase();
  const bodyMode = String(req.body?.response_mode || '').toLowerCase();
  const querySummary = String(req.query?.return_summary || '').toLowerCase();
  const bodySummary = String(req.body?.return_summary || '').toLowerCase();

  return queryMode === 'summary'
    || bodyMode === 'summary'
    || querySummary === '1'
    || querySummary === 'true'
    || bodySummary === '1'
    || bodySummary === 'true';
}

const getLocationSummary = async (req, res, next) => {
  try {
    const { location } = req.query;

    if (!location) {
      return res.status(400).json({ error: 'Se requiere ubicación' });
    }

    const normalizedLocation = String(location).trim();
    // Buscar auditoría activa
    const [active] = await pool.query(`
      SELECT id FROM inventory_audit_smd WHERE status = 'InProgress' LIMIT 1
    `);

    if (active.length === 0) {
      return res.status(400).json({ error: 'No hay auditoría activa', code: 'NO_ACTIVE_AUDIT' });
    }

    const auditId = active[0].id;

    // Obtener resumen por parte de inventory_audit_part_smd
    const [parts] = await pool.query(`
      SELECT 
        iap.id,
        iap.numero_parte,
        iap.expected_items,
        iap.expected_qty,
        iap.status,
        iap.scanned_items,
        iap.scanned_qty,
        iap.confirmed_by,
        iap.confirmed_at,
        iap.flagged_by,
        iap.flagged_at
      FROM inventory_audit_part_smd iap
      WHERE iap.audit_id = ? AND iap.location = ?
      ORDER BY iap.numero_parte
    `, [auditId, normalizedLocation]);

    // Si no hay registros en inventory_audit_part_smd (auditorias antiguas), generarlos al vuelo
    if (parts.length === 0) {
      const [summary] = await pool.query(`
        SELECT 
          ai.numero_parte,
          COUNT(*) as expected_items,
          SUM(ai.cantidad_actual) as expected_qty
        FROM (${getPersistedAuditItemsQuery()}) ai
        WHERE ai.audit_id = ? AND ai.location = ?
        GROUP BY ai.numero_parte
        ORDER BY ai.numero_parte
      `, [auditId, normalizedLocation]);

      if (summary.length > 0) {
        for (const part of summary) {
          await pool.query(`
            INSERT INTO inventory_audit_part_smd (
              audit_id, location, numero_parte, expected_items, expected_qty, status
            ) VALUES (?, ?, ?, ?, ?, 'Pending')
          `, [auditId, normalizedLocation, part.numero_parte, part.expected_items, part.expected_qty]);
        }

        const [partsRefreshed] = await pool.query(`
          SELECT 
            iap.id,
            iap.numero_parte,
            iap.expected_items,
            iap.expected_qty,
            iap.status,
            iap.scanned_items,
            iap.scanned_qty,
            iap.confirmed_by,
            iap.confirmed_at,
            iap.flagged_by,
            iap.flagged_at
          FROM inventory_audit_part_smd iap
          WHERE iap.audit_id = ? AND iap.location = ?
          ORDER BY iap.numero_parte
        `, [auditId, normalizedLocation]);

        parts.splice(0, parts.length, ...partsRefreshed);
      }
    }


    const locationStatus = await enrichAuditPartSummary(
      auditId,
      normalizedLocation,
      parts
    );

    // Calcular progreso
    const total = parts.length;
    const confirmed = parts.filter(p => ['Ok', 'VerifiedByScan', 'MissingConfirmed'].includes(p.status)).length;
    const mismatch = parts.filter(p => p.status === 'Mismatch').length;
    const pending = parts.filter(p => p.status === 'Pending').length;

    res.json({
      success: true,
      location: normalizedLocation,
      auditId,
      parts,
      locationStatus,
      progress: {
        total,
        confirmed,
        mismatch,
        pending
      }
    });
  } catch (err) {
    next(err);
  }
};

// POST /api/audit/confirm-part - Confirmar parte como OK sin escaneo
const confirmPart = async (req, res, next) => {
  try {
    const { location, numero_parte, usuario } = req.body;

    const normalizedLocation = String(location ?? '').trim();

    if (!normalizedLocation || !numero_parte) {
      return res.status(400).json({ error: 'Se requiere ubicación y número de parte' });
    }

    // Buscar auditoría activa
    const [active] = await pool.query(`
      SELECT id FROM inventory_audit_smd WHERE status = 'InProgress' LIMIT 1
    `);

    if (active.length === 0) {
      return res.status(400).json({ error: 'No hay auditoría activa' });
    }

    const auditId = active[0].id;

    // Actualizar status de la parte a Ok
    const [result] = await pool.query(`
      UPDATE inventory_audit_part_smd 
      SET status = 'Ok', confirmed_by = ?, confirmed_at = NOW(),
          scanned_items = expected_items,
          scanned_qty = expected_qty
      WHERE audit_id = ? AND location = ? AND numero_parte = ? AND status = 'Pending'
    `, [usuario || 'Mobile', auditId, normalizedLocation, numero_parte]);

    if (result.affectedRows === 0) {
      return res.json({
        success: false,
        error: 'La parte no está pendiente o no existe'
      });
    }

    // Crear registros Found en inventory_audit_item_smd para todas las etiquetas de esta parte
    const [items] = await pool.query(`
      SELECT ai.warehousing_id as id, ai.codigo_material_recibido, ai.location as ubicacion_salida
      FROM (${getPersistedAuditItemsQuery()}) ai
      WHERE ai.audit_id = ? AND ai.location = ? AND ai.numero_parte = ?
    `, [auditId, normalizedLocation, numero_parte]);

    for (const item of items) {
      // Insertar o actualizar como Found
      const [existing] = await pool.query(`
        SELECT id FROM inventory_audit_item_smd WHERE audit_id = ? AND warehousing_id = ?
      `, [auditId, item.id]);

      if (existing.length === 0) {
        await pool.query(`
          INSERT INTO inventory_audit_item_smd (
            audit_id, warehousing_id, warehousing_code, location, status, scanned_at, scanned_by, notas
          ) VALUES (?, ?, ?, ?, 'Found', NOW(), ?, 'Confirmado por parte OK')
        `, [auditId, item.id, item.codigo_material_recibido, normalizedLocation, usuario || 'Mobile']);
      } else {
        await pool.query(`
          UPDATE inventory_audit_item_smd SET status = 'Found', scanned_at = NOW(), scanned_by = ?
          WHERE id = ?
        `, [usuario || 'Mobile', existing[0].id]);
      }
    }

    // Verificar si todas las partes de la ubicación están confirmadas
    await checkLocationCompletion(auditId, normalizedLocation);

    const response = {
      success: true,
      message: 'Parte confirmada OK',
      numero_parte,
      itemsConfirmed: items.length
    };

    if (shouldReturnLocationSummary(req)) {
      const summary = await buildLocationSummaryPayload(auditId, normalizedLocation);
      response.parts = summary.parts;
      response.progress = summary.progress;
    }

    res.json(response);
  } catch (err) {
    next(err);
  }
};

// POST /api/audit/flag-mismatch - Marcar parte como discrepancia
const flagMismatch = async (req, res, next) => {
  try {
    const { location, numero_parte, usuario } = req.body;

    const normalizedLocation = String(location ?? '').trim();

    if (!normalizedLocation || !numero_parte) {
      return res.status(400).json({ error: 'Se requiere ubicación y número de parte' });
    }

    // Buscar auditoría activa
    const [active] = await pool.query(`
      SELECT id FROM inventory_audit_smd WHERE status = 'InProgress' LIMIT 1
    `);

    if (active.length === 0) {
      return res.status(400).json({ error: 'No hay auditoría activa' });
    }

    const auditId = active[0].id;

    // Actualizar status de la parte a Mismatch
    const [result] = await pool.query(`
      UPDATE inventory_audit_part_smd 
      SET status = 'Mismatch', flagged_by = ?, flagged_at = NOW(), scanned_items = 0, scanned_qty = 0
      WHERE audit_id = ? AND location = ? AND numero_parte = ? AND status = 'Pending'
    `, [usuario || 'Mobile', auditId, normalizedLocation, numero_parte]);

    if (result.affectedRows === 0) {
      return res.json({
        success: false,
        error: 'La parte no está pendiente o no existe'
      });
    }

    // Marcar ubicación como InProgress
    await pool.query(`
      UPDATE inventory_audit_location_smd 
      SET status = 'InProgress', started_at = NOW(), started_by = ?
      WHERE audit_id = ? AND location = ? AND status = 'Pending'
    `, [usuario || 'Mobile', auditId, normalizedLocation]);

    await pool.query(`
      UPDATE inventory_audit_item_smd iai
      LEFT JOIN control_material_almacen_smd cma ON iai.warehousing_id = cma.id
      SET iai.status = 'Pending', iai.scanned_at = NULL, iai.scanned_by = NULL
      WHERE iai.audit_id = ? AND iai.location = ?
        AND ${AUDIT_ITEM_PART_EXPR} = ?
        AND iai.status IN ('Found', 'Missing')
    `, [auditId, normalizedLocation, numero_parte]);

    const response = {
      success: true,
      message: 'Parte marcada como discrepancia - Escanee las etiquetas',
      numero_parte
    };

    if (shouldReturnLocationSummary(req)) {
      const summary = await buildLocationSummaryPayload(auditId, normalizedLocation);
      response.parts = summary.parts;
      response.progress = summary.progress;
    }

    res.json(response);
  } catch (err) {
    next(err);
  }
};

// POST /api/audit/scan-part-item - Escanear etiqueta individual de una parte en Mismatch
const scanPartItem = async (req, res, next) => {
  try {
    const { location, numero_parte, warehousing_code, usuario } = req.body;

    const normalizedLocation = String(location ?? '').trim();
    const normalizedCode = String(warehousing_code ?? '').trim();
    const normalizedPart = String(numero_parte ?? '').trim();

    if (!normalizedLocation || !normalizedCode || !normalizedPart) {
      return res.status(400).json({ error: 'Se requiere ubicación, número de parte y código de material' });
    }

    // Buscar auditoría activa
    const [active] = await pool.query(`
      SELECT id FROM inventory_audit_smd WHERE status = 'InProgress' LIMIT 1
    `);

    if (active.length === 0) {
      return res.status(400).json({ error: 'No hay auditoría activa' });
    }

    const auditId = active[0].id;

    // Validar la parte seleccionada antes de cualquier recuperación de
    // inventario, para que un código de otra parte no genere una entrada.
    const [partRecord] = await pool.query(`
      SELECT id, status FROM inventory_audit_part_smd
      WHERE audit_id = ? AND location = ? AND numero_parte = ?
    `, [auditId, normalizedLocation, normalizedPart]);

    if (partRecord.length === 0) {
      return res.json({ success: false, error: 'No se encontró la parte en la auditoría' });
    }

    if (partRecord[0].status !== 'Mismatch') {
      return res.json({
        success: false,
        error: 'Solo se pueden escanear etiquetas de partes marcadas como discrepancia',
        code: 'PART_NOT_MISMATCH'
      });
    }

    // Buscar el material en el inventario consolidado. Los códigos con salida
    // o todavía no ingresados a SMD se recuperan en esta ubicación.
    let mat = await getAuditInventoryMaterialByCode(normalizedCode);
    let automaticRecovery = null;

    if (
      !mat
      || Number(mat.tiene_salida || 0) === 1
      || Number(mat.total_salida || 0) > 0
    ) {
      automaticRecovery = await recoverAuditMaterialForScan(
        auditId,
        normalizedCode,
        normalizedLocation,
        usuario,
        normalizedPart
      );

      if (!automaticRecovery.success) {
        return res.json(automaticRecovery);
      }
      mat = automaticRecovery.material;
    }

    mat.id = mat.warehousing_id;
    mat.ubicacion_salida = mat.location;

    if (String(mat.numero_parte || '').trim() !== normalizedPart) {
      return res.json({
        success: false,
        error: `El material pertenece a la parte ${mat.numero_parte}, no a ${normalizedPart}`,
        code: 'WRONG_PART'
      });
    }

    // Ubicacion: el escaneo confirma fisicamente el material aqui, asi que si
    // estaba registrado en otra ubicacion se reubica en vez de rechazarlo.
    const matLocation = String(mat.ubicacion_salida ?? '').trim();
    const relocated = await relocateAuditMaterial(pool, auditId, {
      warehousingId: mat.id,
      warehousingCode: normalizedCode,
      numeroParte: normalizedPart,
      fromLocation: matLocation,
      toLocation: normalizedLocation,
      usuario
    });
    if (relocated) mat.ubicacion_salida = normalizedLocation;

    // Verificar si ya fue escaneado
    const [existing] = await pool.query(`
      SELECT id, status FROM inventory_audit_item_smd
      WHERE audit_id = ? AND warehousing_id = ?
    `, [auditId, mat.id]);

    if (existing.length > 0 && existing[0].status === 'Found') {
      return res.json({ success: false, error: 'Este material ya fue escaneado', code: 'ALREADY_SCANNED' });
    }

    // Registrar escaneo
    if (existing.length > 0) {
      await pool.query(`
        UPDATE inventory_audit_item_smd SET status = 'Found', scanned_at = NOW(), scanned_by = ?
        WHERE id = ?
      `, [usuario || 'Mobile', existing[0].id]);
    } else {
      await pool.query(`
        INSERT INTO inventory_audit_item_smd (
          audit_id, warehousing_id, warehousing_code, location, status, scanned_at, scanned_by
        ) VALUES (?, ?, ?, ?, 'Found', NOW(), ?)
      `, [auditId, mat.id, normalizedCode, normalizedLocation, usuario || 'Mobile']);
    }

    // Actualizar contadores de la parte
    await pool.query(`
      UPDATE inventory_audit_part_smd 
      SET scanned_items = scanned_items + 1, scanned_qty = scanned_qty + ?
      WHERE id = ?
    `, [mat.cantidad_actual, partRecord[0].id]);

    // Si ya no queda ninguna etiqueta sin resolver, cerrar la parte sin esperar
    // a "Terminar escaneo": no hay faltantes que confirmar. Sin esto la parte
    // se quedaba en Mismatch y la ubicacion nunca pasaba a verde.
    const [[partScanStats]] = await pool.query(`
      SELECT
        SUM(CASE WHEN iai.status NOT IN ('Found', 'ProcessedOut') THEN 1 ELSE 0 END) AS pending_items,
        SUM(CASE WHEN iai.status = 'ProcessedOut' THEN 1 ELSE 0 END) AS processed_out_items
      FROM inventory_audit_item_smd iai
      LEFT JOIN control_material_almacen_smd cma ON cma.id = iai.warehousing_id
      WHERE iai.audit_id = ? AND iai.location = ? AND ${AUDIT_ITEM_PART_EXPR} = ?
    `, [auditId, normalizedLocation, normalizedPart]);

    if (Number(partScanStats?.pending_items || 0) === 0) {
      await pool.query(`
        UPDATE inventory_audit_part_smd
        SET status = ?, confirmed_by = ?, confirmed_at = NOW()
        WHERE id = ?
      `, [
        resolveAuditPartStatus(partScanStats),
        usuario || 'Mobile',
        partRecord[0].id
      ]);
      await checkLocationCompletion(auditId, normalizedLocation);
    }

    // Obtener progreso actualizado
    const [updatedPart] = await pool.query(`
      SELECT expected_items, scanned_items FROM inventory_audit_part_smd WHERE id = ?
    `, [partRecord[0].id]);

    const relocatedFrom = automaticRecovery?.relocatedFrom
      || (relocated ? matLocation : null);
    const response = {
      success: true,
      message: relocatedFrom
        ? `Material reubicado de ${relocatedFrom} a ${normalizedLocation} y escaneado`
        : automaticRecovery?.automaticEntry
          ? 'Material ingresado automáticamente y escaneado'
          : 'Material escaneado',
      warehousingCode: normalizedCode,
      partNumber: mat.numero_parte,
      relocated: relocatedFrom !== null,
      relocatedFrom,
      automaticEntry: automaticRecovery?.automaticEntry === true || relocatedFrom !== null,
      inventoryAction: automaticRecovery?.action || 'none',
      progress: {
        scanned: updatedPart[0].scanned_items,
        expected: updatedPart[0].expected_items
      }
    };

    if (shouldReturnLocationSummary(req)) {
      const summary = await buildLocationSummaryPayload(auditId, normalizedLocation);
      response.parts = summary.parts;
      response.progress = {
        ...summary.progress,
        scanned: updatedPart[0].scanned_items,
        expected: updatedPart[0].expected_items
      };
    }

    res.json(response);
  } catch (err) {
    next(err);
  }
};

// POST /api/audit/reopen-part - Reabrir una parte sin eliminar su snapshot.
const reopenPart = async (req, res, next) => {
  const connection = await pool.getConnection();
  try {
    const normalizedLocation = String(req.body.location ?? '').trim();
    const normalizedPart = String(req.body.numero_parte ?? '').trim();
    const usuario = req.body.usuario || 'Mobile';
    if (!normalizedLocation || !normalizedPart) {
      return res.status(400).json({ error: 'Se requiere ubicación y número de parte' });
    }

    await connection.beginTransaction();
    const [active] = await connection.query(`
      SELECT id FROM inventory_audit_smd
      WHERE status = 'InProgress' LIMIT 1 FOR UPDATE
    `);
    if (active.length === 0) {
      await connection.rollback();
      return res.status(400).json({ error: 'No hay auditoría activa', code: 'NO_ACTIVE_AUDIT' });
    }

    const auditId = active[0].id;
    const [parts] = await connection.query(`
      SELECT id, status FROM inventory_audit_part_smd
      WHERE audit_id = ? AND location = ? AND numero_parte = ?
      LIMIT 1 FOR UPDATE
    `, [auditId, normalizedLocation, normalizedPart]);
    if (parts.length === 0) {
      await connection.rollback();
      return res.status(404).json({ error: 'Parte no encontrada en la auditoría', code: 'PART_NOT_FOUND' });
    }
    if (parts[0].status === 'Pending') {
      await connection.rollback();
      return res.json({ success: false, error: 'La parte ya está pendiente', status: 'Pending' });
    }

    await connection.query(`
      UPDATE inventory_audit_part_smd
      SET status = 'Pending', confirmed_by = NULL, confirmed_at = NULL,
          flagged_by = NULL, flagged_at = NULL,
          scanned_items = 0, scanned_qty = 0
      WHERE id = ?
    `, [parts[0].id]);
    await connection.query(`
      UPDATE inventory_audit_location_smd
      SET status = 'InProgress', started_at = NOW(), started_by = ?,
          completed_at = NULL, completed_by = NULL
      WHERE audit_id = ? AND location = ?
    `, [usuario, auditId, normalizedLocation]);
    await connection.query(`
      UPDATE inventory_audit_item_smd iai
      LEFT JOIN control_material_almacen_smd cma ON cma.id = iai.warehousing_id
      SET iai.status = 'Pending', iai.scanned_at = NULL, iai.scanned_by = NULL,
          iai.processed_at = NULL, iai.processed_by = NULL
      WHERE iai.audit_id = ? AND iai.location = ?
        AND ${AUDIT_ITEM_PART_EXPR} = ?
    `, [auditId, normalizedLocation, normalizedPart]);

    await connection.commit();
    res.json({
      success: true,
      auditId,
      location: normalizedLocation,
      numero_parte: normalizedPart,
      previousStatus: parts[0].status,
      newStatus: 'Pending'
    });
  } catch (err) {
    await connection.rollback();
    next(err);
  } finally {
    connection.release();
  }
};

// POST /api/audit/undo-mismatch - Cancelar la discrepancia o confirmar OK.
const undoMismatch = async (req, res, next) => {
  const connection = await pool.getConnection();
  try {
    const normalizedLocation = String(req.body.location ?? '').trim();
    const normalizedPart = String(req.body.numero_parte ?? '').trim();
    const usuario = req.body.usuario || 'Mobile';
    const confirmOk = req.body.confirm_ok === true || Number(req.body.confirm_ok) === 1;
    if (!normalizedLocation || !normalizedPart) {
      return res.status(400).json({ error: 'Se requiere ubicación y número de parte' });
    }

    await connection.beginTransaction();
    const [active] = await connection.query(`
      SELECT id FROM inventory_audit_smd
      WHERE status = 'InProgress' LIMIT 1 FOR UPDATE
    `);
    if (active.length === 0) {
      await connection.rollback();
      return res.status(400).json({ error: 'No hay auditoría activa', code: 'NO_ACTIVE_AUDIT' });
    }

    const auditId = active[0].id;
    const [parts] = await connection.query(`
      SELECT id, status FROM inventory_audit_part_smd
      WHERE audit_id = ? AND location = ? AND numero_parte = ?
      LIMIT 1 FOR UPDATE
    `, [auditId, normalizedLocation, normalizedPart]);
    if (parts.length === 0 || parts[0].status !== 'Mismatch') {
      await connection.rollback();
      return res.json({ success: false, error: 'La parte no está en discrepancia' });
    }

    if (confirmOk) {
      await connection.query(`
        UPDATE inventory_audit_part_smd
        SET status = 'Ok', confirmed_by = ?, confirmed_at = NOW(),
            scanned_items = expected_items, scanned_qty = expected_qty
        WHERE id = ?
      `, [usuario, parts[0].id]);
      await connection.query(`
        UPDATE inventory_audit_item_smd iai
        LEFT JOIN control_material_almacen_smd cma ON cma.id = iai.warehousing_id
        SET iai.status = 'Found', iai.scanned_at = NOW(), iai.scanned_by = ?,
            iai.processed_at = NULL, iai.processed_by = NULL
        WHERE iai.audit_id = ? AND iai.location = ?
          AND ${AUDIT_ITEM_PART_EXPR} = ?
      `, [usuario, auditId, normalizedLocation, normalizedPart]);
    } else {
      await connection.query(`
        UPDATE inventory_audit_part_smd
        SET status = 'Pending', flagged_by = NULL, flagged_at = NULL,
            scanned_items = 0, scanned_qty = 0
        WHERE id = ?
      `, [parts[0].id]);
      await connection.query(`
        UPDATE inventory_audit_item_smd iai
        LEFT JOIN control_material_almacen_smd cma ON cma.id = iai.warehousing_id
        SET iai.status = 'Pending', iai.scanned_at = NULL, iai.scanned_by = NULL,
            iai.processed_at = NULL, iai.processed_by = NULL
        WHERE iai.audit_id = ? AND iai.location = ?
          AND ${AUDIT_ITEM_PART_EXPR} = ?
      `, [auditId, normalizedLocation, normalizedPart]);
    }

    await connection.commit();
    await checkLocationCompletion(auditId, normalizedLocation);
    res.json({
      success: true,
      numero_parte: normalizedPart,
      newStatus: confirmOk ? 'Ok' : 'Pending'
    });
  } catch (err) {
    await connection.rollback();
    next(err);
  } finally {
    connection.release();
  }
};

// POST /api/audit/confirm-missing - Confirmar faltantes de una parte en Mismatch
// Crea salida inmediata para items faltantes (no espera a cierre de auditoría)
const confirmMissing = async (req, res, next) => {
  const connection = await pool.getConnection();

  try {
    const { location, numero_parte, usuario } = req.body;
    const normalizedLocation = String(location ?? '').trim();
    const normalizedPart = String(numero_parte ?? '').trim();

    if (!normalizedLocation || !normalizedPart) {
      return res.status(400).json({ error: 'Se requiere ubicación y número de parte' });
    }

    // Buscar auditoría activa
    const [active] = await connection.query(`
      SELECT id FROM inventory_audit_smd WHERE status = 'InProgress' LIMIT 1
    `);

    if (active.length === 0) {
      return res.status(400).json({ error: 'No hay auditoría activa' });
    }

    const auditId = active[0].id;

    // Verificar que la parte esté en Mismatch
    const [partRecord] = await connection.query(`
      SELECT id, status, expected_items, scanned_items
      FROM inventory_audit_part_smd
      WHERE audit_id = ? AND location = ? AND numero_parte = ?
    `, [auditId, normalizedLocation, normalizedPart]);

    if (partRecord.length === 0) {
      return res.json({ success: false, error: 'No se encontró la parte' });
    }

    if (partRecord[0].status !== 'Mismatch') {
      return res.json({ success: false, error: 'La parte no está en estado Mismatch' });
    }

    await connection.beginTransaction();

    // El snapshot define que etiquetas pertenecen a la auditoria; el stock
    // actual del lote define la cantidad exacta que se debe retirar ahora.
    const [unscanned] = await connection.query(`
      SELECT
        iai.id AS audit_item_id,
        iai.warehousing_id,
        iai.warehousing_code,
        ${AUDIT_ITEM_PART_EXPR} AS numero_parte,
        ${AUDIT_ITEM_LOT_EXPR} AS numero_lote_material,
        ${AUDIT_ITEM_SPEC_EXPR} AS especificacion
      FROM inventory_audit_item_smd iai
      LEFT JOIN control_material_almacen_smd cma ON cma.id = iai.warehousing_id
      WHERE iai.audit_id = ?
        AND iai.location = ?
        AND ${AUDIT_ITEM_PART_EXPR} = ?
        AND iai.status NOT IN ('Found', 'ProcessedOut')
      FOR UPDATE
    `, [auditId, normalizedLocation, normalizedPart]);

    let processedOut = 0;
    let processedQty = 0;

    for (const item of unscanned) {
      const outgoing = await createImmediateAuditOutgoing(
        connection,
        item,
        usuario || 'Mobile'
      );

      await connection.query(`
        UPDATE inventory_audit_item_smd
        SET status = 'ProcessedOut',
            scanned_at = NOW(),
            scanned_by = ?,
            processed_at = NOW(),
            processed_by = ?,
            notas = ?
        WHERE id = ?
      `, [
        usuario || 'Mobile',
        usuario || 'Mobile',
        outgoing.created
          ? 'Faltante confirmado - salida creada inmediatamente'
          : 'Faltante confirmado - el lote ya no tenia stock',
        item.audit_item_id
      ]);

      if (outgoing.created) {
        processedOut++;
        processedQty += outgoing.quantity;
      }
    }

    // Status final: MissingConfirmed si hay faltantes, o VerifiedByScan si todo fue encontrado
    const finalStatus = unscanned.length > 0 ? 'MissingConfirmed' : 'VerifiedByScan';

    await connection.query(`
      UPDATE inventory_audit_part_smd
      SET status = ?, confirmed_by = ?, confirmed_at = NOW()
      WHERE id = ?
    `, [finalStatus, usuario || 'Mobile', partRecord[0].id]);

    await connection.commit();

    // Verificar si todas las partes de la ubicación están confirmadas
    await checkLocationCompletion(auditId, normalizedLocation);

    const response = {
      success: true,
      message: unscanned.length > 0
        ? `Faltantes confirmados - ${processedOut} salidas creadas`
        : 'Parte verificada por escaneo',
      numero_parte: normalizedPart,
      missingItems: unscanned.length,
      processedOut,
      processedQty,
      status: finalStatus,
      requiresApproval: false
    };

    if (shouldReturnLocationSummary(req)) {
      const summary = await buildLocationSummaryPayload(auditId, normalizedLocation);
      response.parts = summary.parts;
      response.progress = summary.progress;
    }

    res.json(response);
  } catch (err) {
    await connection.rollback();
    next(err);
  } finally {
    connection.release();
  }
};

// Helper: Verificar si la ubicación está completa
async function checkLocationCompletion(auditId, location) {
  const [parts] = await pool.query(`
    SELECT status FROM inventory_audit_part_smd
    WHERE audit_id = ? AND location = ?
  `, [auditId, location]);

  const [[physicalStats]] = await pool.query(`
    SELECT COUNT(*) AS discrepancy_count
    FROM inventory_audit_item_smd
    WHERE audit_id = ?
      AND location = ?
      AND physical_quantity IS NOT NULL
      AND (
        is_new_inventory = 1
        OR ABS(physical_quantity - COALESCE(cantidad_snapshot, 0)) >= 0.0001
      )
  `, [auditId, location]);

  // Ok, VerifiedByScan y MissingConfirmed cuentan como procesados
  const allDone = parts.every(p => ['Ok', 'VerifiedByScan', 'MissingConfirmed'].includes(p.status));
  const hasMissing = parts.some(p => p.status === 'MissingConfirmed');

  if (allDone) {
    // Si hay faltantes confirmados, marca como Discrepancy
    // De lo contrario, Verified
    let locationStatus = 'Verified';
    if (hasMissing || Number(physicalStats?.discrepancy_count || 0) > 0) {
      locationStatus = 'Discrepancy';
    }

    await pool.query(`
      UPDATE inventory_audit_location_smd 
      SET status = ?, completed_at = NOW()
      WHERE audit_id = ? AND location = ?
    `, [locationStatus, auditId, location]);
  }
}

// ============================================
// APROBACIÓN DE DISCREPANCIAS (PC Supervisor)
// ============================================

// GET /api/audit/pending-approvals - Obtener items pendientes de aprobación
const getPendingApprovals = async (req, res, next) => {
  try {
    const { auditId } = req.query;

    let whereClause = "iai.status = 'PendingApproval'";
    const params = [];

    if (auditId) {
      whereClause += " AND iai.audit_id = ?";
      params.push(auditId);
    }

    const [items] = await pool.query(`
      SELECT 
        iai.id,
        iai.audit_id,
        iai.warehousing_id,
        iai.warehousing_code,
        iai.location,
        iai.status,
        iai.scanned_at,
        iai.scanned_by,
        iai.notas,
        ai.numero_parte,
        ai.numero_lote_material,
        ai.cantidad_actual,
        ai.especificacion,
        ia.audit_code
      FROM inventory_audit_item_smd iai
      JOIN (${getAuditInventorySnapshotQuery()}) ai ON iai.warehousing_id = ai.warehousing_id
      JOIN inventory_audit_smd ia ON iai.audit_id = ia.id
      WHERE ${whereClause}
      ORDER BY iai.location, ai.numero_parte
    `, params);

    // Agrupar por ubicación y número de parte
    const grouped = {};
    for (const item of items) {
      const key = `${item.location}-${item.numero_parte}`;
      if (!grouped[key]) {
        grouped[key] = {
          location: item.location,
          numero_parte: item.numero_parte,
          audit_id: item.audit_id,
          audit_code: item.audit_code,
          items: [],
          total_qty: 0
        };
      }
      grouped[key].items.push(item);
      grouped[key].total_qty += item.cantidad_actual || 0;
    }

    res.json({
      success: true,
      pendingApprovals: Object.values(grouped),
      totalItems: items.length
    });
  } catch (err) {
    next(err);
  }
};

// POST /api/audit/approve-discrepancy - Aprobar discrepancia y generar salida
const approveDiscrepancy = async (req, res, next) => {
  const connection = await pool.getConnection();

  try {
    const { location, numero_parte, audit_id, usuario } = req.body;

    if (!location || !numero_parte || !audit_id) {
      return res.status(400).json({ error: 'Se requiere ubicación, número de parte y ID de auditoría' });
    }

    await connection.beginTransaction();

    // Obtener items pendientes de aprobación
    const [pendingItems] = await connection.query(`
      SELECT iai.*, ai.numero_lote_material, ai.cantidad_actual, ai.especificacion
      FROM inventory_audit_item_smd iai
      JOIN (${getAuditInventorySnapshotQuery()}) ai ON iai.warehousing_id = ai.warehousing_id
      WHERE iai.audit_id = ? 
        AND iai.location = ? 
        AND ai.numero_parte = ?
        AND iai.status = 'PendingApproval'
    `, [audit_id, location, numero_parte]);

    if (pendingItems.length === 0) {
      await connection.rollback();
      return res.json({ success: false, error: 'No hay items pendientes de aprobación' });
    }

    const now = new Date();
    const fechaSalida = now.toISOString().slice(0, 19).replace('T', ' ');
    let processedCount = 0;

    for (const item of pendingItems) {
      // Crear salida por discrepancia de inventario
      await connection.query(`
        INSERT INTO control_material_salida_smd (
          codigo_material_recibido,
          numero_parte,
          numero_lote,
          depto_salida,
          proceso_salida,
          cantidad_salida,
          fecha_salida,
          fecha_registro,
          especificacion_material,
          usuario_registro
        ) VALUES (?, ?, ?, ?, ?, ?, ?, NOW(), ?, ?)
      `, [
        item.warehousing_code,
        numero_parte,
        item.numero_lote_material,
        'AUDITORIA',
        'DISCREPANCIA INVENTARIO',
        item.cantidad_actual,
        fechaSalida,
        item.especificacion,
        usuario || 'Sistema'
      ]);

      // Marcar material como salida/desecho
      await connection.query(`
        UPDATE control_material_almacen_smd 
        SET tiene_salida = 1, estado_desecho = 1
        WHERE id = ?
      `, [item.warehousing_id]);

      // Actualizar item a ProcessedOut
      await connection.query(`
        UPDATE inventory_audit_item_smd 
        SET status = 'ProcessedOut', processed_at = NOW(), processed_by = ?
        WHERE id = ?
      `, [usuario || 'Sistema', item.id]);

      processedCount++;
    }

    // Actualizar parte a MissingConfirmed
    await connection.query(`
      UPDATE inventory_audit_part_smd 
      SET status = 'MissingConfirmed'
      WHERE audit_id = ? AND location = ? AND numero_parte = ? AND status = 'PendingApproval'
    `, [audit_id, location, numero_parte]);

    // Actualizar ubicación si ya no tiene más pendientes
    const [remainingPending] = await connection.query(`
      SELECT COUNT(*) as cnt FROM inventory_audit_part_smd
      WHERE audit_id = ? AND location = ? AND status = 'PendingApproval'
    `, [audit_id, location]);

    if (remainingPending[0].cnt === 0) {
      await connection.query(`
        UPDATE inventory_audit_location_smd 
        SET status = 'Discrepancy'
        WHERE audit_id = ? AND location = ? AND status = 'PendingApproval'
      `, [audit_id, location]);
    }

    await connection.commit();

    res.json({
      success: true,
      message: `Discrepancia aprobada - ${processedCount} items procesados como salida`,
      processedCount
    });
  } catch (err) {
    await connection.rollback();
    next(err);
  } finally {
    connection.release();
  }
};

// POST /api/audit/reject-discrepancy - Rechazar discrepancia (marcar como Found)
const rejectDiscrepancy = async (req, res, next) => {
  try {
    const { location, numero_parte, audit_id, usuario, notas } = req.body;

    if (!location || !numero_parte || !audit_id) {
      return res.status(400).json({ error: 'Se requiere ubicación, número de parte y ID de auditoría' });
    }

    // Obtener items pendientes de aprobación
    const [pendingItems] = await pool.query(`
      SELECT iai.id
      FROM inventory_audit_item_smd iai
      JOIN (${getAuditInventorySnapshotQuery()}) ai ON iai.warehousing_id = ai.warehousing_id
      WHERE iai.audit_id = ? 
        AND iai.location = ? 
        AND ai.numero_parte = ?
        AND iai.status = 'PendingApproval'
    `, [audit_id, location, numero_parte]);

    if (pendingItems.length === 0) {
      return res.json({ success: false, error: 'No hay items pendientes de aprobación' });
    }

    // Marcar todos los items como Found (rechazar discrepancia)
    for (const item of pendingItems) {
      await pool.query(`
        UPDATE inventory_audit_item_smd 
        SET status = 'Found', processed_at = NOW(), processed_by = ?, 
            notas = CONCAT(IFNULL(notas, ''), ' | Discrepancia rechazada: ', ?)
        WHERE id = ?
      `, [usuario || 'Sistema', notas || 'Sin notas', item.id]);
    }

    // Actualizar parte a VerifiedByScan (rechazado = encontrado)
    await pool.query(`
      UPDATE inventory_audit_part_smd 
      SET status = 'VerifiedByScan'
      WHERE audit_id = ? AND location = ? AND numero_parte = ? AND status = 'PendingApproval'
    `, [audit_id, location, numero_parte]);

    // Actualizar ubicación si ya no tiene más pendientes
    const [remainingPending] = await pool.query(`
      SELECT COUNT(*) as cnt FROM inventory_audit_part_smd
      WHERE audit_id = ? AND location = ? AND status = 'PendingApproval'
    `, [audit_id, location]);

    if (remainingPending[0].cnt === 0) {
      // Verificar si hay algún MissingConfirmed
      const [hasMissing] = await pool.query(`
        SELECT COUNT(*) as cnt FROM inventory_audit_part_smd
        WHERE audit_id = ? AND location = ? AND status = 'MissingConfirmed'
      `, [audit_id, location]);

      const newStatus = hasMissing[0].cnt > 0 ? 'Discrepancy' : 'Verified';

      await pool.query(`
        UPDATE inventory_audit_location_smd 
        SET status = ?
        WHERE audit_id = ? AND location = ?
      `, [newStatus, audit_id, location]);
    }

    res.json({
      success: true,
      message: `Discrepancia rechazada - ${pendingItems.length} items marcados como encontrados`,
      rejectedCount: pendingItems.length
    });
  } catch (err) {
    next(err);
  }
};

module.exports = {
  setWebSocketServer,
  broadcastAuditUpdate,
  relocateAuditMaterial,
  syncAuditLocationWithInventory,
  resolveAuditPartStatus,
  getActiveAudit,
  startAudit,
  endAudit,
  getAuditLocations,
  getLocationItems,
  scanLocation,
  reopenLocation,
  scanItem,
  registerPhysicalItem,
  markMissing,
  completeLocation,
  getAuditHistory,
  getAuditHistoryDetail,
  getAuditSummary,
  compareAudits,
  // Audit v2 - Flujo por parte
  getLocationSummary,
  confirmPart,
  flagMismatch,
  scanPartItem,
  reopenPart,
  undoMismatch,
  confirmMissing,
  // Aprobación de discrepancias (PC)
  getPendingApprovals,
  approveDiscrepancy,
  rejectDiscrepancy
};
