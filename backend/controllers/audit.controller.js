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

// Funciones WebSocket deshabilitadas (ya no se usan, polling en su lugar)
// Se mantienen para compatibilidad con llamadas existentes en el controlador.
const setWebSocketServer = () => { };
const broadcastAuditUpdate = () => { };

const AUDIT_LOCATION_EXPR = `COALESCE(NULLIF(TRIM(cma.ubicacion_destino), ''), NULLIF(TRIM(cma.ubicacion_salida), ''))`;

function getAuditInventorySnapshotQuery() {
  return `
    SELECT
      cma.id AS warehousing_id,
      il.codigo_material_recibido,
      il.numero_parte,
      il.numero_lote AS numero_lote_material,
      il.stock_actual AS cantidad_actual,
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

    // Obtener todas las ubicaciones con inventario activo.
    // inventario_lotes_smd es la fuente real del stock disponible.
    const [locations] = await pool.query(`
      SELECT
        ai.location,
        COUNT(*) as total_items,
        SUM(ai.cantidad_actual) as total_qty
      FROM (${getAuditInventorySnapshotQuery()}) ai
      GROUP BY ai.location
      ORDER BY ai.location
    `);

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

    // ========== NUEVO: Crear registros por número de parte (audit v2) ==========
    // Agrupar materiales por ubicacion + numero_parte para el flujo de confirmación
    const [partSummary] = await pool.query(`
      SELECT
        ai.location,
        ai.numero_parte,
        COUNT(*) as expected_items,
        SUM(ai.cantidad_actual) as expected_qty
      FROM (${getAuditInventorySnapshotQuery()}) ai
      GROUP BY ai.location, ai.numero_parte
      ORDER BY ai.location, ai.numero_parte
    `);

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
        COUNT(CASE WHEN status = 'Missing' THEN 1 END) as missing_items,
        COUNT(CASE WHEN status = 'Pending' THEN 1 END) as pending_items
      FROM inventory_audit_item_smd
      WHERE audit_id = ?
    `, [auditId]);

    // Si hay discrepancias y se confirma, procesar salidas
    // confirmacion -> crea Missing faltantes + aplica salida real
    let processedCount = 0;
    if (confirmar_discrepancias) {
      // Paso 1: Crear Missing para materiales que NO fueron encontrados
      // Son materiales reales en inventario sin registro Found en audit_item

      // Obtener todas las ubicaciones de esta auditoria (cubre todo el inventario activo)
      const [locations] = await connection.query(`
        SELECT location FROM inventory_audit_location_smd WHERE audit_id = ?
      `, [auditId]);

      for (const loc of locations) {
        // Para cada ubicacion, encontrar materiales sin registro Found y crearles registro Missing
        const [unscannedItems] = await connection.query(`
          SELECT ai.warehousing_id, ai.codigo_material_recibido, ai.location
          FROM (${getAuditInventorySnapshotQuery()}) ai
          LEFT JOIN inventory_audit_item_smd iai ON iai.warehousing_id = ai.warehousing_id AND iai.audit_id = ?
          WHERE ai.location = ?
            AND (iai.id IS NULL OR iai.status != 'Found')
        `, [auditId, loc.location]);

        for (const item of unscannedItems) {
          // Verificar si ya existe registro
          const [existing] = await connection.query(`
            SELECT id FROM inventory_audit_item_smd WHERE audit_id = ? AND warehousing_id = ?
          `, [auditId, item.warehousing_id]);

          if (existing.length === 0) {
            // Crear registro Missing para marcar que el material no aparecio en conteo
            await connection.query(`
              INSERT INTO inventory_audit_item_smd (
                audit_id, warehousing_id, warehousing_code, location, status, scanned_at, scanned_by
              ) VALUES (?, ?, ?, ?, 'Missing', NOW(), ?)
            `, [auditId, item.warehousing_id, item.codigo_material_recibido, item.location, usuario_fin || 'Sistema-NoEncontrado']);
          } else {
            // Actualizar a Missing si esta Pending (no escaneado)
            await connection.query(`
              UPDATE inventory_audit_item_smd SET status = 'Missing', scanned_at = NOW(), scanned_by = ?
              WHERE id = ? AND status = 'Pending'
            `, [usuario_fin || 'Sistema', existing[0].id]);
          }
        }
      }

      // Paso 2: Obtener TODOS los items Missing para dar salida
      // Esto crea registros en control_material_salida_smd y marca el material como desecho/salida
      const [missingItems] = await connection.query(`
        SELECT iai.*, ai.numero_parte, ai.numero_lote_material, ai.cantidad_actual, ai.especificacion
        FROM inventory_audit_item_smd iai
        JOIN (${getAuditInventorySnapshotQuery()}) ai ON iai.warehousing_id = ai.warehousing_id
        WHERE iai.audit_id = ? AND iai.status = 'Missing'
      `, [auditId]);

      const now = new Date();
      const fechaSalida = now.toISOString().slice(0, 19).replace('T', ' ');

      for (const item of missingItems) {
        // Crear salida por discrepancia de inventario
        // Nota: depto_salida/proceso_salida quedan fijos para trazabilidad
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
          item.numero_parte,
          item.numero_lote_material,
          'AUDITORIA',
          'DISCREPANCIA INVENTARIO',
          item.cantidad_actual,
          fechaSalida,
          item.especificacion,
          usuario_fin || 'Sistema'
        ]);

        // Marcar como tiene salida y desecho para excluirlo de inventario activo
        // Esto asegura que no vuelva a entrar en futuras auditorias
        await connection.query(`
          UPDATE control_material_almacen_smd 
          SET tiene_salida = 1, estado_desecho = 1
          WHERE id = ?
        `, [item.warehousing_id]);

        // Actualizar item de auditoria a ProcessedOut para cerrar ciclo
        await connection.query(`
          UPDATE inventory_audit_item_smd 
          SET status = 'ProcessedOut', processed_at = NOW(), processed_by = ?
          WHERE id = ?
        `, [usuario_fin, item.id]);

        processedCount++;
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
        processedOut: processedCount
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
         AND iai.status = 'Missing') as missing_items
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

    // Obtener materiales en esa ubicacion (estado de auditoria incluido)
    // Si no existe registro en inventory_audit_item_smd, el status es Pending
    const [items] = await pool.query(`
      SELECT 
        ai.warehousing_id as id,
        ai.codigo_material_recibido,
        ai.numero_parte,
        ai.numero_lote_material,
        ai.cantidad_actual,
        ai.especificacion,
        ai.fecha_recibo,
        COALESCE(iai.status, 'Pending') as audit_status,
        iai.scanned_at,
        iai.scanned_by
      FROM (${getAuditInventorySnapshotQuery()}) ai
      LEFT JOIN inventory_audit_item_smd iai ON iai.warehousing_id = ai.warehousing_id AND iai.audit_id = ?
      WHERE ai.location = ?
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

    const normalizedLocation = String(location).trim();
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

    // Verificar que la ubicacion exista en inventory_audit_location_smd
    const [loc] = await pool.query(`
      SELECT * FROM inventory_audit_location_smd 
      WHERE audit_id = ? AND location = ?
    `, [auditId, normalizedLocation]);

    if (loc.length === 0) {
      return res.status(404).json({
        error: 'Ubicación no encontrada en la auditoría',
        code: 'LOCATION_NOT_FOUND'
      });
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

    // Obtener items de la ubicación
    const [items] = await pool.query(`
      SELECT 
        ai.warehousing_id,
        ai.codigo_material_recibido,
        ai.numero_parte,
        ai.numero_lote_material,
        ai.cantidad_actual,
        ai.especificacion,
        COALESCE(iai.status, 'Pending') as audit_status
      FROM (${getAuditInventorySnapshotQuery()}) ai
      LEFT JOIN inventory_audit_item_smd iai ON iai.warehousing_id = ai.warehousing_id AND iai.audit_id = ?
      WHERE ai.location = ?
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

    // Buscar el material desde el inventario consolidado.
    const mat = await getAuditInventoryMaterialByCode(warehousing_code);

    if (!mat) {
      return res.json({
        success: false,
        error: 'Material no encontrado',
        code: 'MATERIAL_NOT_FOUND'
      });
    }

    mat.id = mat.warehousing_id;
    mat.ubicacion_salida = mat.location;

    // Verificar si la ubicacion coincide (si se proporciono)
    // Esto evita que se marque Found en ubicacion equivocada
    if (location && mat.location !== location) {
      return res.json({
        success: false,
        error: `El material está registrado en ${mat.ubicacion_salida}, no en ${location}`,
        code: 'WRONG_LOCATION',
        expectedLocation: mat.ubicacion_salida,
        scannedLocation: location
      });
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
      message: 'Material verificado',
      warehousingCode: warehousing_code,
      partNumber: mat.numero_parte,
      location: mat.ubicacion_salida,
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

    if (!mat) {
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
    const { location, usuario } = req.body;

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

    // Obtener items pendientes de esta ubicacion
    // Cualquier pendiente se considera Missing al cerrar ubicacion
    const [pending] = await pool.query(`
      SELECT ai.warehousing_id as id, ai.codigo_material_recibido
      FROM (${getAuditInventorySnapshotQuery()}) ai
      LEFT JOIN inventory_audit_item_smd iai ON iai.warehousing_id = ai.warehousing_id AND iai.audit_id = ?
      WHERE ai.location = ?
        AND (iai.id IS NULL OR iai.status = 'Pending')
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
        `, [usuario || 'Mobile', existingItem[0].id]);
      } else {
        await pool.query(`
          INSERT INTO inventory_audit_item_smd (
            audit_id, warehousing_id, warehousing_code, location, status, scanned_at, scanned_by, notas
          ) VALUES (?, ?, ?, ?, 'Missing', NOW(), ?, 'Marcado automáticamente al completar ubicación')
        `, [auditId, item.id, item.codigo_material_recibido, location, usuario || 'Mobile']);
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
    `, [hasMissing ? 'Discrepancy' : 'Verified', usuario || 'Mobile', auditId, location]);

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
        cma.numero_parte,
        cma.cantidad_actual,
        cma.numero_lote_material
      FROM inventory_audit_item_smd iai
      JOIN control_material_almacen_smd cma ON iai.warehousing_id = cma.id
      WHERE iai.audit_id = ?
      ORDER BY iai.location, cma.numero_parte
    `, [id]);

    // Resumen por número de parte
    const [byPartNumber] = await pool.query(`
      SELECT 
        cma.numero_parte,
        SUM(CASE WHEN iai.status = 'Found' THEN 1 ELSE 0 END) as found_count,
        SUM(CASE WHEN iai.status = 'Missing' THEN 1 ELSE 0 END) as missing_count,
        SUM(CASE WHEN iai.status = 'ProcessedOut' THEN 1 ELSE 0 END) as processed_count
      FROM inventory_audit_item_smd iai
      JOIN control_material_almacen_smd cma ON iai.warehousing_id = cma.id
      WHERE iai.audit_id = ?
      GROUP BY cma.numero_parte
      ORDER BY cma.numero_parte
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
         WHERE iai.audit_id = ial.audit_id AND iai.location = ial.location AND iai.status = 'Missing') as missing_count
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
        cma.numero_parte,
        COUNT(*) as total_items,
        SUM(CASE WHEN iai.status = 'Found' THEN 1 ELSE 0 END) as found_items,
        SUM(CASE WHEN iai.status = 'Missing' THEN 1 ELSE 0 END) as missing_items,
        SUM(cma.cantidad_actual) as total_qty,
        SUM(CASE WHEN iai.status = 'Found' THEN cma.cantidad_actual ELSE 0 END) as qty_found,
        SUM(CASE WHEN iai.status = 'Missing' THEN cma.cantidad_actual ELSE 0 END) as qty_missing
      FROM inventory_audit_item_smd iai
      JOIN control_material_almacen_smd cma ON iai.warehousing_id = cma.id
      WHERE iai.audit_id = ?
      GROUP BY cma.numero_parte
      ORDER BY cma.numero_parte
    `, [audit1]);

    const [items2] = await pool.query(`
      SELECT 
        cma.numero_parte,
        COUNT(*) as total_items,
        SUM(CASE WHEN iai.status = 'Found' THEN 1 ELSE 0 END) as found_items,
        SUM(CASE WHEN iai.status = 'Missing' THEN 1 ELSE 0 END) as missing_items,
        SUM(cma.cantidad_actual) as total_qty,
        SUM(CASE WHEN iai.status = 'Found' THEN cma.cantidad_actual ELSE 0 END) as qty_found,
        SUM(CASE WHEN iai.status = 'Missing' THEN cma.cantidad_actual ELSE 0 END) as qty_missing
      FROM inventory_audit_item_smd iai
      JOIN control_material_almacen_smd cma ON iai.warehousing_id = cma.id
      WHERE iai.audit_id = ?
      GROUP BY cma.numero_parte
      ORDER BY cma.numero_parte
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
      FROM (${getAuditInventorySnapshotQuery()}) ai
      WHERE ai.location = ?
      GROUP BY ai.numero_parte
      ORDER BY ai.numero_parte
    `, [normalizedLocation]);

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

  const total = parts.length;
  const confirmed = parts.filter(p => ['Ok', 'VerifiedByScan', 'MissingConfirmed'].includes(p.status)).length;
  const mismatch = parts.filter(p => p.status === 'Mismatch').length;
  const pending = parts.filter(p => p.status === 'Pending').length;

  return {
    success: true,
    location: normalizedLocation,
    auditId,
    parts,
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
        FROM (${getAuditInventorySnapshotQuery()}) ai
        WHERE ai.location = ?
        GROUP BY ai.numero_parte
        ORDER BY ai.numero_parte
      `, [normalizedLocation]);

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
      SET status = 'Ok', confirmed_by = ?, confirmed_at = NOW()
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
      FROM (${getAuditInventorySnapshotQuery()}) ai
      WHERE ai.location = ? AND ai.numero_parte = ?
    `, [normalizedLocation, numero_parte]);

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
      JOIN control_material_almacen_smd cma ON iai.warehousing_id = cma.id
      SET iai.status = 'Pending', iai.scanned_at = NULL, iai.scanned_by = NULL
      WHERE iai.audit_id = ? AND iai.location = ? AND cma.numero_parte = ?
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

    if (!normalizedLocation || !normalizedCode) {
      return res.status(400).json({ error: 'Se requiere ubicación y código de material' });
    }

    // Buscar auditoría activa
    const [active] = await pool.query(`
      SELECT id FROM inventory_audit_smd WHERE status = 'InProgress' LIMIT 1
    `);

    if (active.length === 0) {
      return res.status(400).json({ error: 'No hay auditoría activa' });
    }

    const auditId = active[0].id;

    // Buscar el material en el inventario consolidado.
    const mat = await getAuditInventoryMaterialByCode(normalizedCode);

    if (!mat) {
      return res.json({ success: false, error: 'Material no encontrado', code: 'MATERIAL_NOT_FOUND' });
    }

    mat.id = mat.warehousing_id;
    mat.ubicacion_salida = mat.location;

    // Verificar ubicaci??n
    const matLocation = String(mat.ubicacion_salida ?? '').trim();

    if (matLocation !== normalizedLocation) {
      return res.json({
        success: false,
        error: `El material est?? en ${matLocation}, no en ${normalizedLocation}`,
        code: 'WRONG_LOCATION'
      });
    }

    // Verificar que la parte esté en Mismatch
    const [partRecord] = await pool.query(`
      SELECT id, status FROM inventory_audit_part_smd
      WHERE audit_id = ? AND location = ? AND numero_parte = ?
    `, [auditId, normalizedLocation, mat.numero_parte]);

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

    // Obtener progreso actualizado
    const [updatedPart] = await pool.query(`
      SELECT expected_items, scanned_items FROM inventory_audit_part_smd WHERE id = ?
    `, [partRecord[0].id]);

    const response = {
      success: true,
      message: 'Material escaneado',
      warehousingCode: normalizedCode,
      partNumber: mat.numero_parte,
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

// POST /api/audit/confirm-missing - Confirmar faltantes de una parte en Mismatch
// Crea salida inmediata para items faltantes (no espera a cierre de auditoría)
const confirmMissing = async (req, res, next) => {
  const connection = await pool.getConnection();

  try {
    const { location, numero_parte, usuario } = req.body;

    if (!location || !numero_parte) {
      connection.release();
      return res.status(400).json({ error: 'Se requiere ubicación y número de parte' });
    }

    // Buscar auditoría activa
    const [active] = await connection.query(`
      SELECT id FROM inventory_audit_smd WHERE status = 'InProgress' LIMIT 1
    `);

    if (active.length === 0) {
      connection.release();
      return res.status(400).json({ error: 'No hay auditoría activa' });
    }

    const auditId = active[0].id;

    // Verificar que la parte esté en Mismatch
    const [partRecord] = await connection.query(`
      SELECT id, status, expected_items, scanned_items
      FROM inventory_audit_part_smd
      WHERE audit_id = ? AND location = ? AND numero_parte = ?
    `, [auditId, location, numero_parte]);

    if (partRecord.length === 0) {
      connection.release();
      return res.json({ success: false, error: 'No se encontró la parte' });
    }

    if (partRecord[0].status !== 'Mismatch') {
      connection.release();
      return res.json({ success: false, error: 'La parte no está en estado Mismatch' });
    }

    await connection.beginTransaction();

    // Marcar como Missing los items no escaneados de esta parte
    // Incluir datos adicionales para crear salida inmediata
    const [unscanned] = await connection.query(`
      SELECT ai.warehousing_id as id, ai.codigo_material_recibido, ai.numero_lote_material, ai.cantidad_actual, ai.especificacion
      FROM (${getAuditInventorySnapshotQuery()}) ai
      LEFT JOIN inventory_audit_item_smd iai ON iai.warehousing_id = ai.warehousing_id AND iai.audit_id = ?
      WHERE ai.location = ? AND ai.numero_parte = ?
        AND (iai.id IS NULL OR iai.status != 'Found')
    `, [auditId, location, numero_parte]);

    const now = new Date();
    const fechaSalida = now.toISOString().slice(0, 19).replace('T', ' ');
    let processedOut = 0;

    for (const item of unscanned) {
      // 1. Registrar/actualizar item de auditoría
      const [existing] = await connection.query(`
        SELECT id FROM inventory_audit_item_smd WHERE audit_id = ? AND warehousing_id = ?
      `, [auditId, item.id]);

      if (existing.length === 0) {
        await connection.query(`
          INSERT INTO inventory_audit_item_smd (
            audit_id, warehousing_id, warehousing_code, location, status, scanned_at, scanned_by, notas, processed_at, processed_by
          ) VALUES (?, ?, ?, ?, 'ProcessedOut', NOW(), ?, 'Faltante confirmado - salida creada inmediatamente', NOW(), ?)
        `, [auditId, item.id, item.codigo_material_recibido, location, usuario || 'Mobile', usuario || 'Mobile']);
      } else {
        await connection.query(`
          UPDATE inventory_audit_item_smd
          SET status = 'ProcessedOut', scanned_at = NOW(), scanned_by = ?, processed_at = NOW(), processed_by = ?
          WHERE id = ?
        `, [usuario || 'Mobile', usuario || 'Mobile', existing[0].id]);
      }

      // 2. Crear salida en control_material_salida_smd
      await connection.query(`
        INSERT INTO control_material_salida_smd (
          codigo_material_recibido, numero_parte, numero_lote,
          depto_salida, proceso_salida, cantidad_salida,
          fecha_salida, fecha_registro, especificacion_material, usuario_registro
        ) VALUES (?, ?, ?, 'AUDITORIA', 'DISCREPANCIA INVENTARIO', ?, ?, NOW(), ?, ?)
      `, [
        item.codigo_material_recibido,
        numero_parte,
        item.numero_lote_material,
        item.cantidad_actual,
        fechaSalida,
        item.especificacion,
        usuario || 'Mobile'
      ]);

      // 3. Marcar material como salida/desecho
      await connection.query(`
        UPDATE control_material_almacen_smd
        SET tiene_salida = 1, estado_desecho = 1
        WHERE id = ?
      `, [item.id]);

      processedOut++;
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
    await checkLocationCompletion(auditId, location);

    const response = {
      success: true,
      message: unscanned.length > 0
        ? `Faltantes confirmados - ${processedOut} salidas creadas`
        : 'Parte verificada por escaneo',
      numero_parte,
      missingItems: unscanned.length,
      processedOut,
      status: finalStatus,
      requiresApproval: false
    };

    if (shouldReturnLocationSummary(req)) {
      const summary = await buildLocationSummaryPayload(auditId, location);
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

  // Ok, VerifiedByScan y MissingConfirmed cuentan como procesados
  const allDone = parts.every(p => ['Ok', 'VerifiedByScan', 'MissingConfirmed'].includes(p.status));
  const hasMissing = parts.some(p => p.status === 'MissingConfirmed');

  if (allDone) {
    // Si hay faltantes confirmados, marca como Discrepancy
    // De lo contrario, Verified
    let locationStatus = 'Verified';
    if (hasMissing) {
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
  getActiveAudit,
  startAudit,
  endAudit,
  getAuditLocations,
  getLocationItems,
  scanLocation,
  scanItem,
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
  confirmMissing,
  // Aprobación de discrepancias (PC)
  getPendingApprovals,
  approveDiscrepancy,
  rejectDiscrepancy
};
