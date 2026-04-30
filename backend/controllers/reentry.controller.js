/**
 * Reentry Controller - Controlador de Reingreso/Reubicacion
 * Permite mover materiales a nuevas ubicaciones
 */

const { pool } = require('../config/database');

async function findMaterialByCode(code) {
  const normalizedCode = String(code || '').trim();
  if (!normalizedCode) {
    return null;
  }

  const [rows] = await pool.query(`
    SELECT
      id,
      codigo_material_recibido,
      numero_parte,
      especificacion,
      cantidad_actual,
      ubicacion_salida,
      numero_lote_material,
      cliente,
      fecha_recibo,
      unidad_medida
    FROM control_material_almacen_smd
    WHERE codigo_material_recibido = ?
      AND (cancelado IS NULL OR cancelado = 0)
      AND cantidad_actual > 0
    LIMIT 1
  `, [normalizedCode]);

  if (rows.length > 0) {
    return rows[0];
  }

  const [partialRows] = await pool.query(`
    SELECT
      id,
      codigo_material_recibido,
      numero_parte,
      especificacion,
      cantidad_actual,
      ubicacion_salida,
      numero_lote_material,
      cliente,
      fecha_recibo,
      unidad_medida
    FROM control_material_almacen_smd
    WHERE codigo_material_recibido LIKE ?
      AND (cancelado IS NULL OR cancelado = 0)
      AND cantidad_actual > 0
    ORDER BY fecha_recibo DESC
    LIMIT 1
  `, [`%${normalizedCode}%`]);

  return partialRows[0] || null;
}

/**
 * GET /api/reentry/by-code/:code
 * Buscar material por codigo de almacen (codigo_material_recibido) para reingreso
 */
const getByCode = async (req, res, next) => {
  try {
    const { code } = req.params;

    if (!code || code.trim() === '') {
      return res.status(400).json({ error: 'Codigo requerido' });
    }

    console.log('[Reentry] Buscando material con codigo:', code.trim());

    const material = await findMaterialByCode(code);

    console.log('[Reentry] Material encontrado:', !!material);

    if (!material) {
      return res.status(404).json({ error: 'Material no encontrado o sin stock' });
    }

    res.json(material);
  } catch (err) {
    console.error('[Reentry] Error en getByCode:', err);
    next(err);
  }
};

/**
 * POST /api/reentry/by-codes
 * Buscar multiples materiales por codigo para batching en movil
 */
const getByCodes = async (req, res, next) => {
  try {
    const codes = Array.isArray(req.body?.codes) ? req.body.codes : [];
    if (codes.length === 0) {
      return res.status(400).json({ error: 'Se requiere al menos un codigo' });
    }

    const uniqueCodes = [...new Set(
      codes.map((code) => String(code || '').trim()).filter(Boolean)
    )].slice(0, 20);

    const results = await Promise.all(uniqueCodes.map(async (code) => {
      const material = await findMaterialByCode(code);
      return {
        inputCode: code,
        found: !!material,
        material: material || null,
        error: material ? null : 'Material no encontrado o sin stock'
      };
    }));

    res.json({
      success: true,
      results
    });
  } catch (err) {
    console.error('[Reentry] Error en getByCodes:', err);
    next(err);
  }
};

/**
 * PUT /api/reentry/:id/location
 * Actualizar ubicacion de un material (reingreso individual)
 * Guarda historial: ubicacion_anterior, fecha_reingreso, usuario_reingreso
 */
const updateLocation = async (req, res, next) => {
  try {
    const { id } = req.params;
    const { nueva_ubicacion, usuario_reingreso } = req.body;

    if (!nueva_ubicacion || nueva_ubicacion.trim() === '') {
      return res.status(400).json({
        error: 'La nueva ubicacion es obligatoria',
        code: 'LOCATION_REQUIRED'
      });
    }

    console.log('[Reentry] Actualizando ubicacion del material ID:', id, '-> Nueva ubicacion:', nueva_ubicacion);

    const [current] = await pool.query(
      'SELECT ubicacion_salida, codigo_material_recibido FROM control_material_almacen_smd WHERE id = ?',
      [id]
    );

    if (current.length === 0) {
      return res.status(404).json({ error: 'Registro no encontrado' });
    }

    const ubicacion_anterior = current[0].ubicacion_salida;

    await pool.query(`
      UPDATE control_material_almacen_smd
      SET ubicacion_salida = ?,
          ubicacion_destino = ?,
          ubicacion_anterior = ?,
          fecha_reingreso = NOW(),
          usuario_reingreso = ?
      WHERE id = ?
    `, [nueva_ubicacion.trim(), nueva_ubicacion.trim(), ubicacion_anterior, usuario_reingreso || null, id]);

    console.log('[Reentry] Ubicacion actualizada correctamente');

    res.json({
      success: true,
      message: 'Ubicacion actualizada exitosamente',
      codigo: current[0].codigo_material_recibido,
      ubicacion_anterior,
      nueva_ubicacion: nueva_ubicacion.trim()
    });
  } catch (err) {
    console.error('[Reentry] Error en updateLocation:', err);
    next(err);
  }
};

/**
 * POST /api/reentry/bulk
 * Reingreso masivo (multiples materiales a la misma ubicacion)
 * Guarda historial: ubicacion_anterior, fecha_reingreso, usuario_reingreso
 */
const bulkReentry = async (req, res, next) => {
  const connection = await pool.getConnection();

  try {
    const { ids, nueva_ubicacion, usuario_reingreso } = req.body;

    if (!ids || !Array.isArray(ids) || ids.length === 0) {
      return res.status(400).json({ error: 'Se requiere al menos un ID' });
    }

    if (!nueva_ubicacion || nueva_ubicacion.trim() === '') {
      return res.status(400).json({ error: 'La nueva ubicacion es obligatoria' });
    }

    console.log('[Reentry] Reingreso masivo de', ids.length, 'materiales a ubicacion:', nueva_ubicacion);

    await connection.beginTransaction();

    const [[{ now: fechaReingreso }]] = await connection.query('SELECT NOW() as now');

    let successCount = 0;
    let errorCount = 0;
    const results = [];

    for (const id of ids) {
      try {
        const [current] = await connection.query(
          'SELECT ubicacion_salida, codigo_material_recibido FROM control_material_almacen_smd WHERE id = ?',
          [id]
        );

        if (current.length === 0) {
          errorCount++;
          results.push({ id, success: false, error: 'No encontrado' });
          continue;
        }

        const ubicacion_anterior = current[0].ubicacion_salida;

        await connection.query(`
          UPDATE control_material_almacen_smd
          SET ubicacion_salida = ?,
              ubicacion_destino = ?,
              ubicacion_anterior = ?,
              fecha_reingreso = ?,
              usuario_reingreso = ?
          WHERE id = ?
        `, [nueva_ubicacion.trim(), nueva_ubicacion.trim(), ubicacion_anterior, fechaReingreso, usuario_reingreso || null, id]);

        successCount++;
        results.push({
          id,
          success: true,
          codigo: current[0].codigo_material_recibido,
          ubicacion_anterior,
          nueva_ubicacion: nueva_ubicacion.trim()
        });
      } catch (err) {
        errorCount++;
        results.push({ id, success: false, error: err.message });
      }
    }

    await connection.commit();

    console.log('[Reentry] Reingreso completado:', successCount, 'exitosos,', errorCount, 'errores');

    res.json({
      success: true,
      message: `${successCount} materiales reubicados exitosamente`,
      total: ids.length,
      successCount,
      errorCount,
      results
    });
  } catch (err) {
    await connection.rollback();
    console.error('[Reentry] Error en bulkReentry:', err);
    next(err);
  } finally {
    connection.release();
  }
};

/**
 * GET /api/reentry/history
 * Obtener historial de reingresos
 */
const getReentryHistory = async (req, res, next) => {
  try {
    const { fecha_inicio, fecha_fin, texto, limit = 100 } = req.query;

    let whereClause = 'WHERE fecha_reingreso IS NOT NULL';
    const params = [];

    if (fecha_inicio && fecha_fin) {
      whereClause += ' AND DATE(fecha_reingreso) BETWEEN ? AND ?';
      params.push(fecha_inicio, fecha_fin);
    }

    if (texto && texto.trim()) {
      const searchText = `%${texto.trim()}%`;
      whereClause += ` AND (
        numero_lote_material LIKE ? OR
        codigo_material_recibido LIKE ? OR
        numero_parte LIKE ? OR
        especificacion LIKE ? OR
        cliente LIKE ?
      )`;
      params.push(searchText, searchText, searchText, searchText, searchText);
    }

    const [rows] = await pool.query(`
      SELECT
        id,
        codigo_material_recibido,
        numero_parte,
        especificacion,
        cantidad_actual,
        ubicacion_salida,
        ubicacion_anterior,
        fecha_reingreso,
        usuario_reingreso,
        numero_lote_material,
        cliente
      FROM control_material_almacen_smd
      ${whereClause}
      ORDER BY fecha_reingreso DESC
      LIMIT ?
    `, [...params, parseInt(limit, 10)]);

    res.json(rows);
  } catch (err) {
    console.error('[Reentry] Error en getReentryHistory:', err);
    next(err);
  }
};

module.exports = {
  getByCode,
  getByCodes,
  updateLocation,
  bulkReentry,
  getReentryHistory
};
