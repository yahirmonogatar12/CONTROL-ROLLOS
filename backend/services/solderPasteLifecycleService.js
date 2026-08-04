'use strict';

const { pool } = require('../config/database');
const { FULL_ACCESS_DEPARTMENTS } = require('../config/permissions');
const {
  signalSolderPasteEventsAvailable,
} = require('./solderPasteLocalNotificationHub');

const STATUS = Object.freeze({
  TEMPERING: 'TEMPERING',
  READY_FOR_AGITATION: 'READY_FOR_AGITATION',
  AGITATING: 'AGITATING',
  READY_FOR_LINE: 'READY_FOR_LINE',
  IN_LINE: 'IN_LINE',
  CONSUMED: 'CONSUMED',
  SCRAP: 'SCRAP',
  CANCELLED: 'CANCELLED',
  RETURNED_TO_COLD: 'RETURNED_TO_COLD',
});

const ALLOWED_LINES = new Set(['SMT A', 'SMT B', 'SMT C', 'SMT D']);
const PRE_LINE_STATUSES = new Set([
  STATUS.TEMPERING,
  STATUS.READY_FOR_AGITATION,
  STATUS.AGITATING,
  STATUS.READY_FOR_LINE,
]);
const RESERVED_STATUSES = [
  ...PRE_LINE_STATUSES,
  STATUS.IN_LINE,
  STATUS.CONSUMED,
  STATUS.SCRAP,
];
const RESTARTABLE_STATUSES = new Set([
  STATUS.CANCELLED,
  STATUS.RETURNED_TO_COLD,
]);
const RETURN_TO_COLD_STATUSES = new Set([
  STATUS.TEMPERING,
  STATUS.READY_FOR_AGITATION,
  STATUS.AGITATING,
  STATUS.READY_FOR_LINE,
  STATUS.IN_LINE,
]);
const SCRAP_RETURN_PERMISSION = 'authorize_solder_paste_scrap_return';
const SCRAP_REASON = 'Pasta de soldadura vencida en línea (12 h)';
const READY_FOR_AGITATION_SCRAP_REASON =
  'Pasta de soldadura excedió 8 h lista para agitación';
const INVENTORY_SOURCE = Object.freeze({
  WAREHOUSE: 'WAREHOUSE',
  SMD_LEGACY: 'SMD_LEGACY',
});

function normalizeCode(value) {
  return String(value || '').trim().toUpperCase();
}

function lifecycleError(message, code, statusCode = 409) {
  const error = new Error(message);
  error.code = code;
  error.statusCode = statusCode;
  return error;
}

function nextActionForStatus(status) {
  switch (status) {
    case STATUS.TEMPERING:
      return 'Esperar el tiempo restante a temperatura ambiente';
    case STATUS.READY_FOR_AGITATION:
      return 'Agitar antes de 8 h o regresar al refrigerador';
    case STATUS.AGITATING:
      return 'Esperar a que termine el temporizador de 60 segundos';
    case STATUS.READY_FOR_LINE:
      return 'Seleccionar SMT A, B, C o D';
    case STATUS.IN_LINE:
      return 'Utilizar antes del vencimiento, marcar Material consumido o retornar al almacén';
    case STATUS.CONSUMED:
      return 'Proceso terminado; no se requiere otra acción';
    case STATUS.SCRAP:
      return 'Depositar en scrap; si nunca llegó a línea, un usuario autorizado puede retornarlo';
    case STATUS.CANCELLED:
      return 'Proceso cancelado; puede iniciarse nuevamente si corresponde';
    case STATUS.RETURNED_TO_COLD:
      return 'Material regresado al refrigerador; puede iniciar otro ciclo respetando FIFO';
    default:
      return 'Retirar del refrigerador e iniciar acondicionamiento desde Proceso y seguimiento';
  }
}

function severityForStatus(status) {
  if ([STATUS.SCRAP].includes(status)) return 'danger';
  if ([STATUS.READY_FOR_AGITATION, STATUS.READY_FOR_LINE].includes(status)) return 'warning';
  if ([STATUS.CONSUMED].includes(status)) return 'success';
  if ([STATUS.CANCELLED, STATUS.RETURNED_TO_COLD].includes(status)) return 'neutral';
  return 'info';
}

const PROCESS_SELECT = `
  SELECT sp.*,
         CASE
           WHEN sp.status IN ('TEMPERING', 'READY_FOR_AGITATION')
                AND sp.agitation_deadline_at IS NOT NULL
                AND NOW() >= sp.agitation_deadline_at
             THEN 'SCRAP'
           WHEN sp.status = 'TEMPERING' AND NOW() >= sp.ambient_ready_at
             THEN 'READY_FOR_AGITATION'
           WHEN sp.status = 'AGITATING' AND NOW() >= sp.agitation_ready_at
             THEN 'READY_FOR_LINE'
           WHEN sp.status = 'IN_LINE' AND NOW() >= sp.expires_at
             THEN 'SCRAP'
           ELSE sp.status
         END AS effective_status,
         (sp.status = 'TEMPERING' AND NOW() >= sp.ambient_ready_at) AS ambient_due,
         (sp.status IN ('TEMPERING', 'READY_FOR_AGITATION')
           AND sp.agitation_deadline_at IS NOT NULL
           AND NOW() >= sp.agitation_deadline_at) AS ready_for_agitation_due,
         (sp.status = 'AGITATING' AND NOW() >= sp.agitation_ready_at) AS agitation_due,
         (sp.status = 'IN_LINE' AND NOW() >= sp.expires_at) AS line_due,
         GREATEST(0, TIMESTAMPDIFF(SECOND, NOW(), sp.ambient_ready_at)) AS ambient_remaining_seconds,
         GREATEST(0, TIMESTAMPDIFF(SECOND, NOW(), sp.agitation_deadline_at)) AS ready_for_agitation_remaining_seconds,
         GREATEST(0, TIMESTAMPDIFF(SECOND, NOW(), sp.agitation_ready_at)) AS agitation_remaining_seconds,
         GREATEST(0, TIMESTAMPDIFF(SECOND, NOW(), sp.expires_at)) AS line_remaining_seconds,
         TIMESTAMPDIFF(SECOND, sp.removed_from_cold_at, LEAST(NOW(), sp.ambient_ready_at)) AS ambient_elapsed_seconds
  FROM solder_paste_process_smd sp
`;

function decorateProcess(row) {
  if (!row) return null;
  const status = row.effective_status || row.status;
  return {
    ...row,
    status,
    persisted_status: row.status,
    next_action: nextActionForStatus(status),
    severity: severityForStatus(status),
  };
}

async function addEvent(connection, processId, eventType, fromStatus, toStatus, user, metadata = null) {
  await connection.query(`
    INSERT INTO solder_paste_event_smd
      (process_id, event_type, from_status, to_status, usuario, metadata, created_at)
    VALUES (?, ?, ?, ?, ?, ?, NOW())
  `, [
    processId,
    eventType,
    fromStatus || null,
    toStatus || null,
    user || 'Sistema',
    metadata ? JSON.stringify(metadata) : null,
  ]);
}

async function getProcessById(executor, processId, { lock = false } = {}) {
  const [rows] = await executor.query(
    `${PROCESS_SELECT} WHERE sp.id = ?${lock ? ' FOR UPDATE' : ''}`,
    [processId],
  );
  return rows[0] || null;
}

async function getScrapReasonId(connection, reason) {
  await connection.query(`
    INSERT IGNORE INTO scrap_motivos
      (motivo, activo, creado_por, fecha_creacion)
    VALUES (?, 1, 'Sistema', NOW())
  `, [reason]);
  const [rows] = await connection.query(
    'SELECT id FROM scrap_motivos WHERE motivo = ? LIMIT 1',
    [reason],
  );
  if (rows.length === 0) {
    throw lifecycleError('No fue posible resolver el motivo automático de scrap', 'SCRAP_REASON_NOT_FOUND', 500);
  }
  return rows[0].id;
}

async function scrapLockedProcess(connection, process) {
  const readyExpired = process.status === STATUS.READY_FOR_AGITATION
    && Number(process.ready_for_agitation_due || 0) === 1;
  const lineExpired = process.status === STATUS.IN_LINE
    && Number(process.line_due || 0) === 1;
  if (!readyExpired && !lineExpired) {
    return process;
  }

  const reason = readyExpired ? READY_FOR_AGITATION_SCRAP_REASON : SCRAP_REASON;
  const eventType = readyExpired
    ? 'READY_FOR_AGITATION_EXPIRED'
    : 'LINE_LIFE_EXPIRED';
  const reasonId = await getScrapReasonId(connection, reason);
  const normalized = normalizeCode(process.codigo_material_recibido).replace(/\s+/g, '');
  const [result] = await connection.query(`
    INSERT INTO scrap_records
      (scanned_original, scanned_original_norm, assy_type, part_no, modelo,
       area, proceso, motivo_scrap_id, motivo_scrap_texto, comentarios,
       usuario_registro, cantidad, fecha_registro)
    VALUES (?, ?, NULL, ?, 'N/A', 'SMD', 'SMT', ?, ?, ?, 'Sistema', 1, NOW())
  `, [
    process.codigo_material_recibido,
    normalized,
    process.numero_parte || null,
    reasonId,
    reason,
    readyExpired
      ? `Sin agitar durante 8 h | Cantidad retirada: ${process.issued_quantity || 0} ${process.unit || ''}`.trim()
      : `Línea: ${process.line_code || 'N/A'} | Cantidad retirada: ${process.issued_quantity || 0} ${process.unit || ''}`.trim(),
  ]);

  await connection.query(`
    UPDATE solder_paste_process_smd
    SET status = ?, scrapped_at = NOW(), scrap_record_id = ?, updated_at = NOW(), updated_by = 'Sistema'
    WHERE id = ? AND status = ?
  `, [STATUS.SCRAP, result.insertId, process.id, process.status]);
  await addEvent(
    connection,
    process.id,
    eventType,
    process.status,
    STATUS.SCRAP,
    'Sistema',
    {
      scrap_record_id: result.insertId,
      stage: readyExpired ? STATUS.READY_FOR_AGITATION : STATUS.IN_LINE,
      line: process.line_code || null,
    },
  );
  return getProcessById(connection, process.id, { lock: true });
}

async function reconcileLockedProcess(connection, process) {
  let current = process;
  if (current.status === STATUS.TEMPERING && Number(current.ambient_due || 0) === 1) {
    await connection.query(`
      UPDATE solder_paste_process_smd
      SET status = ?, updated_at = NOW(), updated_by = 'Sistema'
      WHERE id = ? AND status = ?
    `, [STATUS.READY_FOR_AGITATION, current.id, STATUS.TEMPERING]);
    await addEvent(
      connection,
      current.id,
      'AMBIENT_READY',
      STATUS.TEMPERING,
      STATUS.READY_FOR_AGITATION,
      'Sistema',
    );
    current = await getProcessById(connection, current.id, { lock: true });
  }

  if (
    current.status === STATUS.READY_FOR_AGITATION
    && Number(current.ready_for_agitation_due || 0) === 1
  ) {
    current = await scrapLockedProcess(connection, current);
  }

  if (current.status === STATUS.AGITATING && Number(current.agitation_due || 0) === 1) {
    await connection.query(`
      UPDATE solder_paste_process_smd
      SET status = ?,
          agitation_completed_at = COALESCE(agitation_completed_at, agitation_ready_at),
          updated_at = NOW(), updated_by = 'Sistema'
      WHERE id = ? AND status = ?
    `, [STATUS.READY_FOR_LINE, current.id, STATUS.AGITATING]);
    await addEvent(
      connection,
      current.id,
      'AGITATION_COMPLETED',
      STATUS.AGITATING,
      STATUS.READY_FOR_LINE,
      'Sistema',
    );
    current = await getProcessById(connection, current.id, { lock: true });
  }

  if (current.status === STATUS.IN_LINE && Number(current.line_due || 0) === 1) {
    current = await scrapLockedProcess(connection, current);
  }
  return current;
}

async function withTransaction(callback) {
  const connection = await pool.getConnection();
  try {
    await connection.beginTransaction();
    const result = await callback(connection);
    await connection.commit();
    // El evento ya está confirmado en MySQL: avisar a los móviles conectados.
    // El móvil usa su cursor para decidir si realmente hay algo que mostrar.
    try {
      signalSolderPasteEventsAvailable();
    } catch (error) {
      console.error(`No se pudo señalizar Control de pasta por WebSocket: ${error.message}`);
    }
    return result;
  } catch (error) {
    await connection.rollback();
    throw error;
  } finally {
    connection.release();
  }
}

async function scanMaterial({ code, usuario, usuarioId, enforceFifo = true }) {
  const normalizedCode = normalizeCode(code);
  if (!normalizedCode) {
    throw lifecycleError('Código de material requerido', 'MISSING_CODE', 400);
  }

  return withTransaction(async (connection) => {
    const [warehouseRows] = await connection.query(`
      SELECT cma.id, cma.codigo_material_recibido, cma.numero_parte,
             cma.numero_lote_material, cma.codigo_material, cma.fecha_recibo,
             cma.cantidad_actual, cma.unidad_medida,
             cma.especificacion, cma.vendedor,
             cma.cancelado, cma.estado_desecho, cma.tiene_salida,
             COALESCE(cma.en_cuarentena, 0) AS en_cuarentena
      FROM control_material_almacen cma
      WHERE cma.codigo_material_recibido = ?
      ORDER BY cma.id DESC
      LIMIT 1
      FOR UPDATE
    `, [normalizedCode]);

    if (warehouseRows.length === 0) {
      throw lifecycleError('Material no encontrado en el inventario de almacén', 'MATERIAL_NOT_FOUND', 404);
    }
    const material = warehouseRows[0];

    const [latestRows] = await connection.query(`
      SELECT * FROM solder_paste_process_smd
      WHERE codigo_material_recibido = ?
      ORDER BY cycle_no DESC, id DESC
      LIMIT 1
      FOR UPDATE
    `, [material.codigo_material_recibido]);

    if (
      latestRows.length > 0
      && !RESTARTABLE_STATUSES.has(latestRows[0].status)
    ) {
      let current = await getProcessById(connection, latestRows[0].id, { lock: true });
      current = await reconcileLockedProcess(connection, current);
      return decorateProcess(await getProcessById(connection, current.id));
    }

    if (Number(material.cancelado || 0) === 1) {
      throw lifecycleError('El material está cancelado', 'MATERIAL_CANCELLED');
    }
    if (Number(material.estado_desecho || 0) === 1) {
      throw lifecycleError('El material está marcado como desecho', 'MATERIAL_DISPOSED');
    }
    if (Number(material.en_cuarentena || 0) === 1) {
      throw lifecycleError('El material está en cuarentena', 'MATERIAL_QUARANTINED');
    }
    if (Number(material.tiene_salida || 0) === 1 || Number(material.cantidad_actual || 0) <= 0) {
      throw lifecycleError('El material no tiene stock disponible', 'NO_AVAILABLE_STOCK');
    }

    const fifoField = material.codigo_material ? 'codigo_material' : 'numero_parte';
    const fifoValue = material.codigo_material || material.numero_parte;
    if (enforceFifo && fifoValue && material.fecha_recibo) {
      const [fifoRows] = await connection.query(`
        SELECT id, codigo_material_recibido, fecha_recibo, cantidad_actual
        FROM control_material_almacen
        WHERE ${fifoField} = ?
          AND DATE(fecha_recibo) < DATE(?)
          AND cantidad_actual > 0
          AND COALESCE(cancelado, 0) = 0
          AND COALESCE(estado_desecho, 0) = 0
          AND COALESCE(en_cuarentena, 0) = 0
          AND COALESCE(tiene_salida, 0) = 0
        ORDER BY DATE(fecha_recibo) ASC, id ASC
        LIMIT 1
        FOR UPDATE
      `, [fifoValue, material.fecha_recibo]);
      const fifoMaterial = fifoRows[0];
      if (fifoMaterial) {
        throw lifecycleError(
          `FIFO: primero debe utilizar la etiqueta ${fifoMaterial.codigo_material_recibido}`,
          'FIFO_VIOLATION',
        );
      }
    }

    if (material.numero_lote_material) {
      const [blacklistRows] = await connection.query(
        'SELECT reason FROM blacklisted_lots WHERE lot_id = ? LIMIT 1',
        [material.numero_lote_material],
      );
      if (blacklistRows.length > 0) {
        throw lifecycleError(
          `El lote está en lista negra: ${blacklistRows[0].reason || 'Sin razón especificada'}`,
          'LOT_BLACKLISTED',
        );
      }
    }

    const issuedQuantity = Number(material.cantidad_actual || 0);
    const [outgoing] = await connection.query(`
      INSERT INTO control_material_salida
        (codigo_material_recibido, numero_parte, numero_lote, modelo, linea_proceso,
         depto_salida, proceso_salida, cantidad_salida,
         fecha_salida, fecha_registro, especificacion_material,
         usuario_registro, vendedor)
      VALUES (?, ?, ?, NULL, NULL, 'SMT', 'PASTA_SOLDADURA', ?, NOW(), NOW(), ?, ?, ?)
    `, [
      material.codigo_material_recibido,
      material.numero_parte,
      material.numero_lote_material,
      issuedQuantity,
      material.especificacion || null,
      usuario || 'Sistema',
      material.vendedor || '',
    ]);
    await connection.query(`
      UPDATE control_material_almacen
      SET tiene_salida = 1
      WHERE id = ? AND codigo_material_recibido = ?
    `, [material.id, material.codigo_material_recibido]);

    const cycleNo = latestRows.length > 0 ? Number(latestRows[0].cycle_no || 0) + 1 : 1;
    const [inserted] = await connection.query(`
      INSERT INTO solder_paste_process_smd
        (warehousing_id, inventory_lot_id, inventory_source, codigo_material_recibido,
         numero_parte, numero_lote, cycle_no, status,
         issued_quantity, unit, inventory_outgoing_id,
         removed_from_cold_at, ambient_ready_at, agitation_deadline_at,
         started_by, started_by_id,
         created_at, updated_at, updated_by)
      VALUES (?, NULL, ?, ?, ?, ?, ?, ?, ?, ?, ?,
              NOW(), DATE_ADD(NOW(), INTERVAL 2 HOUR), DATE_ADD(NOW(), INTERVAL 10 HOUR),
              ?, ?, NOW(), NOW(), ?)
    `, [
      material.id,
      INVENTORY_SOURCE.WAREHOUSE,
      material.codigo_material_recibido,
      material.numero_parte,
      material.numero_lote_material,
      cycleNo,
      STATUS.TEMPERING,
      issuedQuantity,
      material.unidad_medida || 'EA',
      outgoing.insertId,
      usuario || 'Sistema',
      usuarioId || null,
      usuario || 'Sistema',
    ]);
    await addEvent(
      connection,
      inserted.insertId,
      'REMOVED_FROM_COLD',
      null,
      STATUS.TEMPERING,
      usuario,
      {
        warehousing_id: material.id,
        inventory_source: INVENTORY_SOURCE.WAREHOUSE,
        outgoing_id: outgoing.insertId,
        quantity: issuedQuantity,
        fifo_enforced: enforceFifo,
      },
    );
    return decorateProcess(await getProcessById(connection, inserted.insertId));
  });
}

async function startAgitation({ processId, usuario }) {
  return withTransaction(async (connection) => {
    let process = await getProcessById(connection, processId, { lock: true });
    if (!process) throw lifecycleError('Proceso no encontrado', 'PROCESS_NOT_FOUND', 404);
    process = await reconcileLockedProcess(connection, process);
    if (process.status === STATUS.SCRAP) return decorateProcess(process);
    if (process.status === STATUS.AGITATING || process.status === STATUS.READY_FOR_LINE) {
      return decorateProcess(await getProcessById(connection, process.id));
    }
    if (process.status !== STATUS.READY_FOR_AGITATION) {
      throw lifecycleError('El material todavía no está listo para agitación', 'NOT_READY_FOR_AGITATION');
    }
    await connection.query(`
      UPDATE solder_paste_process_smd
      SET status = ?, agitation_started_at = NOW(),
          agitation_ready_at = DATE_ADD(NOW(), INTERVAL 60 SECOND),
          updated_at = NOW(), updated_by = ?
      WHERE id = ?
    `, [STATUS.AGITATING, usuario || 'Sistema', process.id]);
    await addEvent(
      connection,
      process.id,
      'AGITATION_STARTED',
      STATUS.READY_FOR_AGITATION,
      STATUS.AGITATING,
      usuario,
    );
    return decorateProcess(await getProcessById(connection, process.id));
  });
}

async function assignLine({ processId, line, usuario }) {
  const normalizedLine = String(line || '').trim().toUpperCase();
  if (!ALLOWED_LINES.has(normalizedLine)) {
    throw lifecycleError('La línea debe ser SMT A, SMT B, SMT C o SMT D', 'INVALID_LINE', 400);
  }

  return withTransaction(async (connection) => {
    let process = await getProcessById(connection, processId, { lock: true });
    if (!process) throw lifecycleError('Proceso no encontrado', 'PROCESS_NOT_FOUND', 404);
    process = await reconcileLockedProcess(connection, process);
    if (process.status === STATUS.SCRAP) return decorateProcess(process);
    if (process.status === STATUS.IN_LINE && process.line_code === normalizedLine) {
      return decorateProcess(await getProcessById(connection, process.id));
    }
    if (process.status !== STATUS.READY_FOR_LINE) {
      throw lifecycleError('La agitación todavía no ha terminado', 'NOT_READY_FOR_LINE');
    }

    const legacySource = (process.inventory_source || INVENTORY_SOURCE.SMD_LEGACY) === INVENTORY_SOURCE.SMD_LEGACY;
    let stock = Number(process.issued_quantity || 0);
    let unit = process.unit || 'EA';
    let outgoingId = Number(process.inventory_outgoing_id || 0);
    if (legacySource) {
      const [warehouseRows] = await connection.query(`
        SELECT id, codigo_material_recibido, numero_parte, numero_lote_material,
               cantidad_actual, especificacion, vendedor, unidad_medida,
               cancelado, estado_desecho, tiene_salida,
               COALESCE(en_cuarentena, 0) AS en_cuarentena
        FROM control_material_almacen_smd
        WHERE id = ? AND codigo_material_recibido = ?
        LIMIT 1 FOR UPDATE
      `, [process.warehousing_id, process.codigo_material_recibido]);
      if (warehouseRows.length === 0) {
        throw lifecycleError('La etiqueta de almacén ya no existe', 'WAREHOUSE_ENTRY_NOT_FOUND', 404);
      }
      const material = warehouseRows[0];
      if (Number(material.cancelado || 0) === 1 || Number(material.estado_desecho || 0) === 1 || Number(material.en_cuarentena || 0) === 1) {
        throw lifecycleError('El material fue bloqueado y no puede enviarse a línea', 'MATERIAL_BLOCKED');
      }
      if (Number(material.tiene_salida || 0) === 1) {
        throw lifecycleError('El material ya tiene una salida registrada', 'ALREADY_HAS_OUTGOING');
      }
      const [lotRows] = await connection.query(`
        SELECT id, stock_actual FROM inventario_lotes_smd
        WHERE codigo_material_recibido = ? LIMIT 1 FOR UPDATE
      `, [material.codigo_material_recibido]);
      stock = Number(lotRows[0]?.stock_actual || 0);
      if (lotRows.length === 0 || stock <= 0) {
        throw lifecycleError('El lote no tiene stock disponible', 'NO_AVAILABLE_STOCK');
      }
      unit = material.unidad_medida || 'EA';
      const [outgoing] = await connection.query(`
        INSERT INTO control_material_salida_smd
          (codigo_material_recibido, numero_parte, numero_lote, modelo,
           depto_salida, proceso_salida, linea_proceso, cantidad_salida,
           fecha_salida, fecha_registro, especificacion_material,
           usuario_registro, vendedor)
        VALUES (?, ?, ?, NULL, 'SMT', 'PASTA_SOLDADURA', ?, ?, NOW(), NOW(), ?, ?, ?)
      `, [
        material.codigo_material_recibido,
        material.numero_parte,
        material.numero_lote_material,
        normalizedLine,
        stock,
        material.especificacion || null,
        usuario || 'Sistema',
        material.vendedor || '',
      ]);
      outgoingId = outgoing.insertId;
      await connection.query(`
        UPDATE control_material_almacen_smd SET tiene_salida = 1
        WHERE id = ?
      `, [material.id]);
    } else if (outgoingId > 0) {
      const [outgoingRows] = await connection.query(`
        SELECT id, cantidad_salida, cancelado
        FROM control_material_salida
        WHERE id = ? AND codigo_material_recibido = ?
        LIMIT 1 FOR UPDATE
      `, [outgoingId, process.codigo_material_recibido]);
      if (outgoingRows.length === 0) {
        throw lifecycleError('No se encontró la salida de Almacén creada en el primer escaneo', 'WAREHOUSE_OUTGOING_NOT_FOUND', 404);
      }
      if (Number(outgoingRows[0].cancelado || 0) === 1) {
        throw lifecycleError('La salida de Almacén está cancelada', 'WAREHOUSE_OUTGOING_CANCELLED');
      }
      stock = Number(process.issued_quantity || outgoingRows[0].cantidad_salida || 0);
      if (stock <= 0) {
        throw lifecycleError('La salida de Almacén no tiene cantidad válida', 'NO_AVAILABLE_STOCK');
      }
      await connection.query(`
        UPDATE control_material_salida
        SET linea_proceso = ?
        WHERE id = ?
      `, [normalizedLine, outgoingId]);
    } else {
      // Compatibilidad con procesos WAREHOUSE iniciados antes de que la salida
      // se moviera al primer escaneo.
      const [warehouseRows] = await connection.query(`
        SELECT id, codigo_material_recibido, numero_parte, numero_lote_material,
               cantidad_actual, especificacion, vendedor, unidad_medida,
               cancelado, estado_desecho, tiene_salida,
               COALESCE(en_cuarentena, 0) AS en_cuarentena
        FROM control_material_almacen
        WHERE id = ? AND codigo_material_recibido = ?
        LIMIT 1 FOR UPDATE
      `, [process.warehousing_id, process.codigo_material_recibido]);
      if (warehouseRows.length === 0) {
        throw lifecycleError('La etiqueta de almacén ya no existe', 'WAREHOUSE_ENTRY_NOT_FOUND', 404);
      }
      const material = warehouseRows[0];
      if (Number(material.cancelado || 0) === 1 || Number(material.estado_desecho || 0) === 1 || Number(material.en_cuarentena || 0) === 1) {
        throw lifecycleError('El material fue bloqueado y no puede enviarse a línea', 'MATERIAL_BLOCKED');
      }
      if (Number(material.tiene_salida || 0) === 1) {
        throw lifecycleError('El material ya tiene una salida registrada', 'ALREADY_HAS_OUTGOING');
      }
      stock = Number(material.cantidad_actual || 0);
      unit = material.unidad_medida || 'EA';
      if (stock <= 0) {
        throw lifecycleError('El material no tiene cantidad disponible en almacén', 'NO_AVAILABLE_STOCK');
      }
      const [outgoing] = await connection.query(`
        INSERT INTO control_material_salida
          (codigo_material_recibido, numero_parte, numero_lote, modelo, linea_proceso,
           depto_salida, proceso_salida, cantidad_salida,
           fecha_salida, fecha_registro, especificacion_material,
           usuario_registro, vendedor)
        VALUES (?, ?, ?, NULL, ?, 'SMT', 'PASTA_SOLDADURA', ?, NOW(), NOW(), ?, ?, ?)
      `, [
        material.codigo_material_recibido,
        material.numero_parte,
        material.numero_lote_material,
        normalizedLine,
        stock,
        material.especificacion || null,
        usuario || 'Sistema',
        material.vendedor || '',
      ]);
      outgoingId = outgoing.insertId;
      await connection.query(`
        UPDATE control_material_almacen SET tiene_salida = 1
        WHERE id = ?
      `, [material.id]);
    }
    await connection.query(`
      UPDATE solder_paste_process_smd
      SET status = ?, line_code = ?, line_started_at = NOW(),
          expires_at = DATE_ADD(NOW(), INTERVAL 12 HOUR),
          issued_quantity = ?, unit = ?, inventory_outgoing_id = ?,
          updated_at = NOW(), updated_by = ?
      WHERE id = ? AND status = ?
    `, [
      STATUS.IN_LINE,
      normalizedLine,
      stock,
      unit,
      outgoingId,
      usuario || 'Sistema',
      process.id,
      STATUS.READY_FOR_LINE,
    ]);
    await addEvent(
      connection,
      process.id,
      'ASSIGNED_TO_LINE',
      STATUS.READY_FOR_LINE,
      STATUS.IN_LINE,
      usuario,
      {
        line: normalizedLine,
        quantity: stock,
        outgoing_id: outgoingId,
        inventory_source: legacySource ? INVENTORY_SOURCE.SMD_LEGACY : INVENTORY_SOURCE.WAREHOUSE,
      },
    );
    return decorateProcess(await getProcessById(connection, process.id));
  });
}

async function consume({ processId, usuario }) {
  return withTransaction(async (connection) => {
    let process = await getProcessById(connection, processId, { lock: true });
    if (!process) throw lifecycleError('Proceso no encontrado', 'PROCESS_NOT_FOUND', 404);
    process = await reconcileLockedProcess(connection, process);
    if (process.status === STATUS.SCRAP) return decorateProcess(process);
    if (process.status === STATUS.CONSUMED) return decorateProcess(process);
    if (process.status !== STATUS.IN_LINE) {
      throw lifecycleError('Solo un material vigente en línea puede marcarse como consumido', 'NOT_IN_LINE');
    }
    await connection.query(`
      UPDATE solder_paste_process_smd
      SET status = ?, consumed_at = NOW(), updated_at = NOW(), updated_by = ?
      WHERE id = ?
    `, [STATUS.CONSUMED, usuario || 'Sistema', process.id]);
    await addEvent(connection, process.id, 'CONSUMED', STATUS.IN_LINE, STATUS.CONSUMED, usuario);
    return decorateProcess(await getProcessById(connection, process.id));
  });
}

async function releaseWarehouseOutgoing(connection, process) {
  let warehouseOutgoingCancelled = false;
  if (
    process.inventory_source === INVENTORY_SOURCE.WAREHOUSE
    && Number(process.inventory_outgoing_id || 0) > 0
  ) {
    const [cancelledOutgoing] = await connection.query(`
      UPDATE control_material_salida
      SET cancelado = 1
      WHERE id = ? AND codigo_material_recibido = ?
        AND COALESCE(cancelado, 0) = 0
    `, [process.inventory_outgoing_id, process.codigo_material_recibido]);
    warehouseOutgoingCancelled = Number(cancelledOutgoing.affectedRows || 0) > 0;
    await connection.query(`
      UPDATE control_material_almacen cma
      SET cma.tiene_salida = 0
      WHERE cma.id = ? AND cma.codigo_material_recibido = ?
        AND NOT EXISTS (
          SELECT 1
          FROM control_material_salida cms
          WHERE cms.codigo_material_recibido = cma.codigo_material_recibido
            AND COALESCE(cms.cancelado, 0) = 0
            AND cms.cantidad_salida > 0
        )
    `, [process.warehousing_id, process.codigo_material_recibido]);
  }
  return warehouseOutgoingCancelled;
}

async function createWarehouseReturn(connection, process, usuario) {
  if (process.inventory_source !== INVENTORY_SOURCE.WAREHOUSE) {
    return {
      warehouseReturnCreated: false,
      materialReturnId: null,
      returnQuantity: null,
      newWarehouseQuantity: null,
      newOutgoingQuantity: null,
      outgoingId: null,
    };
  }

  const warehousingId = Number(process.warehousing_id || 0);
  const outgoingId = Number(process.inventory_outgoing_id || 0);
  if (warehousingId <= 0 || outgoingId <= 0) {
    throw lifecycleError(
      'El proceso no tiene una entrada y salida de Almacén válidas para registrar el retorno',
      'WAREHOUSE_RETURN_DATA_MISSING',
    );
  }

  const [warehouseRows] = await connection.query(`
    SELECT id, numero_parte, numero_lote_material,
           codigo_material_recibido, cantidad_actual, tiene_salida
    FROM control_material_almacen
    WHERE id = ? AND codigo_material_recibido = ?
    LIMIT 1 FOR UPDATE
  `, [warehousingId, process.codigo_material_recibido]);
  if (warehouseRows.length === 0) {
    throw lifecycleError(
      'No se encontró la entrada original de Almacén para registrar el retorno',
      'WAREHOUSE_ENTRY_NOT_FOUND',
      404,
    );
  }
  const warehouse = warehouseRows[0];

  const [outgoingRows] = await connection.query(`
    SELECT id, cantidad_salida
    FROM control_material_salida
    WHERE id = ? AND codigo_material_recibido = ?
      AND cantidad_salida > 0
    LIMIT 1 FOR UPDATE
  `, [outgoingId, process.codigo_material_recibido]);
  if (outgoingRows.length === 0) {
    throw lifecycleError(
      'No se encontró una salida pendiente de Almacén para registrar el retorno',
      'WAREHOUSE_OUTGOING_NOT_FOUND',
      404,
    );
  }
  const outgoing = outgoingRows[0];
  const currentOutgoingQuantity = Number(outgoing.cantidad_salida || 0);
  const returnQuantity = Number(process.issued_quantity || currentOutgoingQuantity);
  if (!Number.isFinite(returnQuantity) || returnQuantity <= 0) {
    throw lifecycleError(
      'La cantidad a retornar debe ser mayor que cero',
      'INVALID_RETURN_QUANTITY',
      400,
    );
  }
  if (returnQuantity > currentOutgoingQuantity) {
    throw lifecycleError(
      `La cantidad a retornar (${returnQuantity}) excede la salida pendiente (${currentOutgoingQuantity})`,
      'RETURN_QUANTITY_EXCEEDS_OUTGOING',
      400,
    );
  }

  const description = process.status === STATUS.IN_LINE
    ? `Retorno de pasta de soldadura desde ${process.line_code || 'línea'} al refrigerador de Almacén`
    : 'Retorno de pasta de soldadura al refrigerador de Almacén';
  const [materialReturn] = await connection.query(`
    INSERT INTO material_return (
      warehousing_id,
      warehousing_code,
      numero_parte,
      numero_lote_material,
      cantidad_devuelta,
      motivo_devolucion,
      descripcion_motivo,
      estado,
      registrado_por,
      fecha_creacion
    ) VALUES (?, ?, ?, ?, ?, 'Otro', ?, 'Pending', ?, NOW())
  `, [
    warehouse.id,
    warehouse.codigo_material_recibido,
    warehouse.numero_parte || process.numero_parte || null,
    warehouse.numero_lote_material || process.numero_lote || null,
    returnQuantity,
    description,
    usuario || 'Sistema',
  ]);

  const newOutgoingQuantity = Math.max(0, currentOutgoingQuantity - returnQuantity);
  await connection.query(
    'UPDATE control_material_salida SET cantidad_salida = ? WHERE id = ?',
    [newOutgoingQuantity, outgoing.id],
  );

  const currentWarehouseQuantity = Number(warehouse.cantidad_actual || 0);
  const currentHasOutgoing = Number(warehouse.tiene_salida || 0);
  const newWarehouseQuantity = currentHasOutgoing === 1
    ? returnQuantity
    : currentWarehouseQuantity + returnQuantity;
  await connection.query(
    'UPDATE control_material_almacen SET cantidad_actual = ?, tiene_salida = 0 WHERE id = ?',
    [newWarehouseQuantity, warehouse.id],
  );

  return {
    warehouseReturnCreated: true,
    materialReturnId: materialReturn.insertId,
    returnQuantity,
    newWarehouseQuantity,
    newOutgoingQuantity,
    outgoingId: outgoing.id,
  };
}

async function authorizeScrapReturn(connection, usuarioId) {
  const normalizedUserId = Number(usuarioId || 0);
  if (!Number.isInteger(normalizedUserId) || normalizedUserId <= 0) {
    throw lifecycleError(
      'Se requiere autorización especial para retornar una pasta marcada como scrap',
      'SCRAP_RETURN_PERMISSION_REQUIRED',
      403,
    );
  }

  const [userRows] = await connection.query(`
    SELECT id, username, nombre_completo, departamento
    FROM usuarios_sistema
    WHERE id = ? AND activo = 1
    LIMIT 1
  `, [normalizedUserId]);
  if (userRows.length === 0) {
    throw lifecycleError(
      'El usuario que autoriza el retorno no existe o está inactivo',
      'SCRAP_RETURN_PERMISSION_REQUIRED',
      403,
    );
  }
  const user = userRows[0];
  if (FULL_ACCESS_DEPARTMENTS.includes(user.departamento)) return user;

  const [permissionRows] = await connection.query(`
    SELECT id
    FROM user_permissions_materiales
    WHERE user_id = ? AND permission_key = ? AND enabled = 1
    LIMIT 1
  `, [normalizedUserId, SCRAP_RETURN_PERMISSION]);
  if (permissionRows.length === 0) {
    throw lifecycleError(
      'No cuenta con autorización para retornar una pasta marcada como scrap',
      'SCRAP_RETURN_PERMISSION_REQUIRED',
      403,
    );
  }
  return user;
}

async function returnToCold({ processId, usuario, usuarioId }) {
  return withTransaction(async (connection) => {
    let process = await getProcessById(connection, processId, { lock: true });
    if (!process) throw lifecycleError('Proceso no encontrado', 'PROCESS_NOT_FOUND', 404);
    process = await reconcileLockedProcess(connection, process);
    if (process.status === STATUS.RETURNED_TO_COLD) {
      return decorateProcess(process);
    }

    const returningScrap = process.status === STATUS.SCRAP;
    let authorizingUser = null;
    if (returningScrap) {
      if (process.line_started_at || process.line_code) {
        throw lifecycleError(
          'Una pasta marcada como scrap después de llegar a línea no puede regresar al refrigerador',
          'OPENED_SCRAP_RETURN_FORBIDDEN',
        );
      }
      if (process.inventory_source !== INVENTORY_SOURCE.WAREHOUSE) {
        throw lifecycleError(
          'Solo el scrap sin abrir del almacén general puede regresar al refrigerador',
          'SCRAP_RETURN_NOT_ALLOWED',
        );
      }
      authorizingUser = await authorizeScrapReturn(connection, usuarioId);
    } else if (!RETURN_TO_COLD_STATUSES.has(process.status)) {
      throw lifecycleError(
        'Este estado del proceso no permite retornar la pasta al refrigerador',
        'RETURN_TO_COLD_NOT_ALLOWED',
      );
    }
    if (
      process.status === STATUS.IN_LINE
      && process.inventory_source !== INVENTORY_SOURCE.WAREHOUSE
    ) {
      throw lifecycleError(
        'El retorno desde línea solo está disponible para material del almacén general',
        'RETURN_TO_COLD_NOT_ALLOWED',
      );
    }

    const previousStatus = process.status;
    const warehouseReturn = await createWarehouseReturn(connection, process, usuario);
    let scrapRecordRemoved = false;
    const reversedScrapRecordId = returningScrap
      ? Number(process.scrap_record_id || 0) || null
      : null;
    if (reversedScrapRecordId) {
      const [deletedScrap] = await connection.query(
        'DELETE FROM scrap_records WHERE id = ?',
        [reversedScrapRecordId],
      );
      scrapRecordRemoved = Number(deletedScrap.affectedRows || 0) > 0;
    }
    await connection.query(`
      UPDATE solder_paste_process_smd
      SET scrapped_at = CASE WHEN status = 'SCRAP' THEN NULL ELSE scrapped_at END,
          scrap_record_id = CASE WHEN status = 'SCRAP' THEN NULL ELSE scrap_record_id END,
          status = ?, returned_to_cold_at = NOW(), returned_by = ?,
          updated_at = NOW(), updated_by = ?
      WHERE id = ? AND status = ?
    `, [
      STATUS.RETURNED_TO_COLD,
      usuario || 'Sistema',
      usuario || 'Sistema',
      process.id,
      previousStatus,
    ]);
    await addEvent(
      connection,
      process.id,
      'RETURNED_TO_COLD',
      previousStatus,
      STATUS.RETURNED_TO_COLD,
      usuario,
      {
        outgoing_id: warehouseReturn.outgoingId || process.inventory_outgoing_id || null,
        warehouse_return_created: warehouseReturn.warehouseReturnCreated,
        material_return_id: warehouseReturn.materialReturnId,
        return_quantity: warehouseReturn.returnQuantity,
        new_warehouse_quantity: warehouseReturn.newWarehouseQuantity,
        new_outgoing_quantity: warehouseReturn.newOutgoingQuantity,
        returned_from_line: previousStatus === STATUS.IN_LINE,
        line: process.line_code || null,
        destination: 'WAREHOUSE_COLD_STORAGE',
        restart_on_next_scan: true,
        scrap_return_authorized: returningScrap,
        authorized_by_user_id: authorizingUser?.id || null,
        authorized_by: authorizingUser?.username
          || authorizingUser?.nombre_completo
          || null,
        reversed_scrap_record_id: reversedScrapRecordId,
        scrap_record_removed: scrapRecordRemoved,
      },
    );
    return decorateProcess(await getProcessById(connection, process.id));
  });
}

async function cancel({ processId, usuario }) {
  return withTransaction(async (connection) => {
    let process = await getProcessById(connection, processId, { lock: true });
    if (!process) throw lifecycleError('Proceso no encontrado', 'PROCESS_NOT_FOUND', 404);
    process = await reconcileLockedProcess(connection, process);
    if (process.status === STATUS.CANCELLED) return decorateProcess(process);
    if (process.status === STATUS.SCRAP) return decorateProcess(process);
    if (!PRE_LINE_STATUSES.has(process.status)) {
      throw lifecycleError('El proceso ya no puede cancelarse después de asignar línea', 'CANCELLATION_NOT_ALLOWED');
    }
    const warehouseOutgoingCancelled = await releaseWarehouseOutgoing(connection, process);
    await connection.query(`
      UPDATE solder_paste_process_smd
      SET status = ?, cancelled_at = NOW(), cancelled_by = ?,
          updated_at = NOW(), updated_by = ?
      WHERE id = ?
    `, [STATUS.CANCELLED, usuario || 'Sistema', usuario || 'Sistema', process.id]);
    await addEvent(
      connection,
      process.id,
      'CANCELLED',
      process.status,
      STATUS.CANCELLED,
      usuario,
      {
        outgoing_id: process.inventory_outgoing_id || null,
        warehouse_outgoing_cancelled: warehouseOutgoingCancelled,
      },
    );
    return decorateProcess(await getProcessById(connection, process.id));
  });
}

async function getStatusByCode(code) {
  const normalizedCode = normalizeCode(code);
  if (!normalizedCode) {
    throw lifecycleError('Código requerido', 'MISSING_CODE', 400);
  }
  const [processRows] = await pool.query(`
    ${PROCESS_SELECT}
    WHERE sp.codigo_material_recibido = ?
    ORDER BY sp.cycle_no DESC, sp.id DESC
    LIMIT 1
  `, [normalizedCode]);
  if (processRows.length > 0) {
    let row = processRows[0];
    if (
      Number(row.ambient_due || 0) === 1
      || Number(row.ready_for_agitation_due || 0) === 1
      || Number(row.agitation_due || 0) === 1
      || Number(row.line_due || 0) === 1
    ) {
      row = await withTransaction(async (connection) => {
        const locked = await getProcessById(connection, row.id, { lock: true });
        return reconcileLockedProcess(connection, locked);
      });
    }
    const process = decorateProcess(row);
    const [eventRows] = await pool.query(`
      SELECT id, event_type, from_status, to_status, usuario, metadata, created_at
      FROM solder_paste_event_smd WHERE process_id = ? ORDER BY id DESC
    `, [process.id]);
    return { found: true, inventory_status: 'PROCESS_FOUND', process, events: eventRows };
  }

  const [inventoryRows] = await pool.query(`
    SELECT cma.codigo_material_recibido, cma.numero_parte, cma.cancelado,
           cma.estado_desecho, cma.tiene_salida,
           COALESCE(cma.en_cuarentena, 0) AS en_cuarentena,
           COALESCE(cma.cantidad_actual, 0) AS stock_actual
    FROM control_material_almacen cma
    WHERE cma.codigo_material_recibido = ?
    ORDER BY cma.id DESC LIMIT 1
  `, [normalizedCode]);
  if (inventoryRows.length === 0) {
    return {
      found: false,
      inventory_status: 'NOT_FOUND',
      message: 'Etiqueta no encontrada en el inventario de almacén',
      next_action: 'Verificar que la etiqueta pertenezca a Control de material de almacén',
      severity: 'danger',
      process: null,
      events: [],
    };
  }
  const item = inventoryRows[0];
  let inventoryStatus = 'AVAILABLE';
  let message = 'Material disponible sin proceso iniciado';
  let nextAction = nextActionForStatus(null);
  let severity = 'info';
  if (Number(item.cancelado || 0) === 1) {
    inventoryStatus = 'CANCELLED'; message = 'La etiqueta está cancelada'; nextAction = 'Solicitar revisión de almacén'; severity = 'danger';
  } else if (Number(item.estado_desecho || 0) === 1) {
    inventoryStatus = 'DISPOSED'; message = 'La etiqueta está marcada como desecho'; nextAction = 'No utilizar el material'; severity = 'danger';
  } else if (Number(item.en_cuarentena || 0) === 1) {
    inventoryStatus = 'QUARANTINED'; message = 'La etiqueta está en cuarentena'; nextAction = 'Esperar liberación de Calidad'; severity = 'warning';
  } else if (Number(item.tiene_salida || 0) === 1 || Number(item.stock_actual || 0) <= 0) {
    inventoryStatus = 'NO_STOCK'; message = 'La etiqueta no tiene stock disponible'; nextAction = 'No iniciar el proceso'; severity = 'danger';
  }
  return {
    found: true,
    inventory_status: inventoryStatus,
    message,
    next_action: nextAction,
    severity,
    inventory: item,
    process: null,
    events: [],
  };
}

async function listProcesses({ status, search, limit = 200 } = {}) {
  // La consulta del tablero también reconcilia vencimientos para que una
  // cuenta regresiva en cero cambie de estado sin esperar al job periódico.
  await reconcileAll();

  const params = [];
  let where = 'WHERE 1=1';
  if (status) {
    where += ' AND sp.status = ?';
    params.push(status);
  }
  if (search) {
    where += ' AND (sp.codigo_material_recibido LIKE ? OR sp.numero_parte LIKE ? OR sp.line_code LIKE ?)';
    const pattern = `%${search}%`;
    params.push(pattern, pattern, pattern);
  }
  params.push(Math.min(Math.max(Number(limit) || 200, 1), 1000));
  const [rows] = await pool.query(`
    ${PROCESS_SELECT}
    ${where}
    ORDER BY sp.updated_at DESC, sp.id DESC
    LIMIT ?
  `, params);
  return rows.map(decorateProcess);
}

async function listEvents({ afterId = 0, limit = 200 } = {}) {
  const [rows] = await pool.query(`
    SELECT e.*, p.codigo_material_recibido, p.numero_parte, p.line_code
    FROM solder_paste_event_smd e
    JOIN solder_paste_process_smd p ON p.id = e.process_id
    WHERE e.id > ?
    ORDER BY e.id ASC
    LIMIT ?
  `, [Number(afterId) || 0, Math.min(Math.max(Number(limit) || 200, 1), 1000)]);
  return rows;
}

async function reconcileAll() {
  const [rows] = await pool.query(`
    SELECT id FROM solder_paste_process_smd
    WHERE (status = 'TEMPERING' AND ambient_ready_at <= NOW())
       OR (status = 'READY_FOR_AGITATION' AND agitation_deadline_at <= NOW())
       OR (status = 'AGITATING' AND agitation_ready_at <= NOW())
       OR (status = 'IN_LINE' AND expires_at <= NOW())
    ORDER BY id ASC
    LIMIT 500
  `);
  for (const row of rows) {
    await withTransaction(async (connection) => {
      const process = await getProcessById(connection, row.id, { lock: true });
      if (process) await reconcileLockedProcess(connection, process);
    });
  }
  return rows.length;
}

async function findReservation(executor, code, { lock = false } = {}) {
  const normalizedCode = normalizeCode(code);
  if (!normalizedCode) return null;
  const placeholders = RESERVED_STATUSES.map(() => '?').join(', ');
  const [rows] = await executor.query(`
    SELECT id, status, codigo_material_recibido
    FROM solder_paste_process_smd
    WHERE codigo_material_recibido = ? AND status IN (${placeholders})
    ORDER BY id DESC LIMIT 1${lock ? ' FOR UPDATE' : ''}
  `, [normalizedCode, ...RESERVED_STATUSES]);
  return rows[0] || null;
}

async function assertNotReserved(executor, code, options = {}) {
  const reservation = await findReservation(executor, code, options);
  if (reservation) {
    throw lifecycleError(
      `La etiqueta está controlada por el proceso de pasta de soldadura (${reservation.status})`,
      'SOLDER_PASTE_RESERVED',
    );
  }
}

async function assertReturnAllowed(executor, code, { lock = false } = {}) {
  const normalizedCode = normalizeCode(code);
  const placeholders = RESERVED_STATUSES.map(() => '?').join(', ');
  const [rows] = await executor.query(`
    SELECT id, status FROM solder_paste_process_smd
    WHERE codigo_material_recibido = ?
      AND status IN (${placeholders})
    ORDER BY id DESC LIMIT 1${lock ? ' FOR UPDATE' : ''}
  `, [normalizedCode, ...RESERVED_STATUSES]);
  if (rows.length > 0) {
    if (PRE_LINE_STATUSES.has(rows[0].status)) {
      throw lifecycleError(
        `La etiqueta está reservada por el proceso de pasta de soldadura (${rows[0].status})`,
        'SOLDER_PASTE_RESERVED',
      );
    }
    throw lifecycleError(
      'La pasta de soldadura enviada a línea nunca puede regresar al inventario',
      'SOLDER_PASTE_RETURN_FORBIDDEN',
    );
  }
}

module.exports = {
  STATUS,
  ALLOWED_LINES,
  SCRAP_REASON,
  READY_FOR_AGITATION_SCRAP_REASON,
  SCRAP_RETURN_PERMISSION,
  INVENTORY_SOURCE,
  normalizeCode,
  nextActionForStatus,
  scanMaterial,
  startAgitation,
  assignLine,
  consume,
  returnToCold,
  cancel,
  getStatusByCode,
  listProcesses,
  listEvents,
  reconcileAll,
  assertNotReserved,
  assertReturnAllowed,
};
