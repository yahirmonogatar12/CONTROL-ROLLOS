/**
 * Scrap Motivos Controller - Catalogo de motivos de scrap
 * CRUD para configurar los motivos disponibles al registrar scrap
 */

const { pool, getMexicoDateTime } = require('../config/database');

// ============================================
// GET /api/scrap-motivos
// Lista todos los motivos (activos por defecto)
// ============================================
exports.getAll = async (req, res, next) => {
  try {
    const includeInactive = req.query.includeInactive === 'true';

    let query = `
      SELECT id, motivo, activo, creado_por, fecha_creacion, actualizado_por, fecha_actualizacion
      FROM scrap_motivos
    `;
    if (!includeInactive) {
      query += ` WHERE activo = 1`;
    }
    query += ` ORDER BY motivo ASC`;

    const [rows] = await pool.query(query);

    res.json({
      success: true,
      data: rows,
      total: rows.length,
    });
  } catch (err) {
    next(err);
  }
};

// ============================================
// POST /api/scrap-motivos
// Crea un nuevo motivo de scrap
// ============================================
exports.create = async (req, res, next) => {
  try {
    const { motivo } = req.body;

    if (!motivo || !motivo.trim()) {
      return res.status(400).json({
        success: false,
        message: 'El motivo es requerido',
        code: 'MISSING_MOTIVO',
      });
    }

    const usuario = req.body.usuario || 'Sistema';
    const ahora = getMexicoDateTime();

    const [result] = await pool.query(
      `INSERT INTO scrap_motivos (motivo, activo, creado_por, fecha_creacion)
       VALUES (?, 1, ?, ?)`,
      [motivo.trim(), usuario, ahora]
    );

    const [inserted] = await pool.query(
      `SELECT * FROM scrap_motivos WHERE id = ?`,
      [result.insertId]
    );

    res.json({
      success: true,
      data: inserted[0],
    });
  } catch (err) {
    if (err.code === 'ER_DUP_ENTRY') {
      return res.status(409).json({
        success: false,
        message: 'Ya existe un motivo con ese nombre',
        code: 'DUPLICATE_MOTIVO',
      });
    }
    next(err);
  }
};

// ============================================
// PUT /api/scrap-motivos/:id
// Actualiza un motivo de scrap
// ============================================
exports.update = async (req, res, next) => {
  try {
    const { id } = req.params;
    const { motivo, activo } = req.body;
    const usuario = req.body.usuario || 'Sistema';
    const ahora = getMexicoDateTime();

    const updates = [];
    const params = [];

    if (motivo !== undefined) {
      updates.push('motivo = ?');
      params.push(motivo.trim());
    }
    if (activo !== undefined) {
      updates.push('activo = ?');
      params.push(activo ? 1 : 0);
    }

    if (updates.length === 0) {
      return res.status(400).json({
        success: false,
        message: 'Nada que actualizar',
      });
    }

    updates.push('actualizado_por = ?');
    params.push(usuario);
    updates.push('fecha_actualizacion = ?');
    params.push(ahora);
    params.push(id);

    await pool.query(
      `UPDATE scrap_motivos SET ${updates.join(', ')} WHERE id = ?`,
      params
    );

    const [updated] = await pool.query(
      `SELECT * FROM scrap_motivos WHERE id = ?`,
      [id]
    );

    res.json({
      success: true,
      data: updated[0] || null,
    });
  } catch (err) {
    if (err.code === 'ER_DUP_ENTRY') {
      return res.status(409).json({
        success: false,
        message: 'Ya existe un motivo con ese nombre',
        code: 'DUPLICATE_MOTIVO',
      });
    }
    next(err);
  }
};

// ============================================
// DELETE /api/scrap-motivos/:id
// Soft-delete: desactiva el motivo
// ============================================
exports.delete = async (req, res, next) => {
  try {
    const { id } = req.params;
    const usuario = req.body.usuario || req.query.usuario || 'Sistema';
    const ahora = getMexicoDateTime();

    await pool.query(
      `UPDATE scrap_motivos SET activo = 0, actualizado_por = ?, fecha_actualizacion = ? WHERE id = ?`,
      [usuario, ahora, id]
    );

    res.json({ success: true });
  } catch (err) {
    next(err);
  }
};

