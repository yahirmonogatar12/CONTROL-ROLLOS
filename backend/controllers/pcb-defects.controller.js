/**
 * PCB Defects Controller - Catalogo de defectos para reparacion PCB
 */
const { pool } = require('../config/database');

function normalizeDefectName(value) {
  return (value || '').toString().trim().toUpperCase();
}

exports.getAll = async (req, res, next) => {
  try {
    const includeInactive = req.query.include_inactive === 'true';
    let query = `
      SELECT id, defect_name, description, is_active, created_by,
             DATE_FORMAT(created_at, '%Y-%m-%d %H:%i:%s') AS created_at_fmt,
             DATE_FORMAT(updated_at, '%Y-%m-%d %H:%i:%s') AS updated_at_fmt
      FROM pcb_defect_catalog
    `;
    if (!includeInactive) query += ' WHERE is_active = 1';
    query += ' ORDER BY defect_name';

    const [rows] = await pool.query(query);
    res.json({ success: true, data: rows });
  } catch (err) {
    next(err);
  }
};

exports.create = async (req, res, next) => {
  try {
    const defectName = normalizeDefectName(req.body.defect_name);
    const description = req.body.description?.toString().trim() || null;
    const createdBy = req.body.created_by?.toString().trim() || null;

    if (!defectName) {
      return res.status(400).json({
        success: false,
        message: 'defect_name es requerido',
        code: 'MISSING_DEFECT_NAME'
      });
    }

    const [existing] = await pool.query(
      'SELECT id, is_active FROM pcb_defect_catalog WHERE defect_name = ?',
      [defectName]
    );

    if (existing.length > 0) {
      if (existing[0].is_active === 0) {
        await pool.query(
          'UPDATE pcb_defect_catalog SET is_active = 1, description = ?, created_by = ? WHERE id = ?',
          [description, createdBy, existing[0].id]
        );
        return res.json({ success: true, id: existing[0].id, reactivated: true });
      }

      return res.status(409).json({
        success: false,
        message: 'Este defecto ya existe',
        code: 'DUPLICATE_DEFECT'
      });
    }

    const [result] = await pool.query(
      `INSERT INTO pcb_defect_catalog (defect_name, description, created_by)
       VALUES (?, ?, ?)`,
      [defectName, description, createdBy]
    );

    res.status(201).json({ success: true, id: result.insertId });
  } catch (err) {
    next(err);
  }
};

exports.update = async (req, res, next) => {
  try {
    const { id } = req.params;
    const defectName = normalizeDefectName(req.body.defect_name);
    const description = req.body.description?.toString().trim() || null;
    const isActive = req.body.is_active === undefined ? 1 : Number(req.body.is_active) ? 1 : 0;

    if (!defectName) {
      return res.status(400).json({
        success: false,
        message: 'defect_name es requerido',
        code: 'MISSING_DEFECT_NAME'
      });
    }

    const [result] = await pool.query(
      `UPDATE pcb_defect_catalog
       SET defect_name = ?, description = ?, is_active = ?
       WHERE id = ?`,
      [defectName, description, isActive, id]
    );

    if (result.affectedRows === 0) {
      return res.status(404).json({ success: false, message: 'Defecto no encontrado' });
    }

    res.json({ success: true });
  } catch (err) {
    if (err.code === 'ER_DUP_ENTRY') {
      return res.status(409).json({
        success: false,
        message: 'Este defecto ya existe',
        code: 'DUPLICATE_DEFECT'
      });
    }
    next(err);
  }
};

exports.remove = async (req, res, next) => {
  try {
    const { id } = req.params;
    const [result] = await pool.query(
      'UPDATE pcb_defect_catalog SET is_active = 0 WHERE id = ?',
      [id]
    );

    if (result.affectedRows === 0) {
      return res.status(404).json({ success: false, message: 'Defecto no encontrado' });
    }

    res.json({ success: true });
  } catch (err) {
    next(err);
  }
};
