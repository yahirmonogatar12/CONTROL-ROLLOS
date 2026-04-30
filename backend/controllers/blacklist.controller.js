/**
 * Blacklist Controller - Gestión de lista negra de lotes
 */
const { pool } = require('../config/database');

/**
 * GET /api/blacklist - Obtener todos los lotes en lista negra
 */
exports.getAll = async (req, res, next) => {
  try {
    const [rows] = await pool.query(
      `SELECT * FROM blacklisted_lots ORDER BY created_at DESC`
    );
    res.json(rows);
  } catch (err) {
    next(err);
  }
};

/**
 * GET /api/blacklist/search - Buscar con filtros
 */
exports.search = async (req, res, next) => {
  try {
    const { fecha_inicio, fecha_fin, texto } = req.query;
    let query = `SELECT * FROM blacklisted_lots WHERE 1=1`;
    const params = [];

    if (fecha_inicio && fecha_fin) {
      query += ' AND work_date BETWEEN ? AND ?';
      params.push(fecha_inicio, fecha_fin);
    }

    if (texto) {
      query += ` AND (lot_id LIKE ? OR product_name LIKE ? OR production_line LIKE ? OR equipment LIKE ?)`;
      const searchTerm = `%${texto}%`;
      params.push(searchTerm, searchTerm, searchTerm, searchTerm);
    }

    query += ' ORDER BY created_at DESC';
    const [rows] = await pool.query(query, params);
    res.json(rows);
  } catch (err) {
    next(err);
  }
};

/**
 * GET /api/blacklist/check/:lotId - Verificar si un lote está en lista negra
 */
exports.checkLot = async (req, res, next) => {
  try {
    const { lotId } = req.params;
    const [rows] = await pool.query(
      'SELECT * FROM blacklisted_lots WHERE lot_id = ?',
      [lotId]
    );
    
    if (rows.length > 0) {
      res.json({ 
        blacklisted: true, 
        lot: rows[0],
        message: `El lote ${lotId} está en la lista negra` 
      });
    } else {
      res.json({ blacklisted: false });
    }
  } catch (err) {
    next(err);
  }
};

/**
 * POST /api/blacklist - Agregar lote a lista negra
 */
exports.add = async (req, res, next) => {
  try {
    const { 
      work_date, production_line, product_name, lot_id,
      indicated_qty, produced_qty, quantity_ea, ek_data,
      process, equipment, equipment_entry_date, reason, blocked_by
    } = req.body;
    
    if (!lot_id) {
      return res.status(400).json({ error: 'El LOT ID es requerido' });
    }
    
    // Verificar si ya existe
    const [existing] = await pool.query(
      'SELECT id FROM blacklisted_lots WHERE lot_id = ?',
      [lot_id]
    );
    
    if (existing.length > 0) {
      return res.status(400).json({ error: 'Este LOT ID ya está en la lista negra' });
    }
    
    const [result] = await pool.query(
      `INSERT INTO blacklisted_lots (
        work_date, production_line, product_name, lot_id,
        indicated_qty, produced_qty, quantity_ea, ek_data,
        process, equipment, equipment_entry_date, reason, blocked_by
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
      [
        work_date || null, production_line || null, product_name || null, lot_id,
        indicated_qty || null, produced_qty || null, quantity_ea || null, ek_data || null,
        process || null, equipment || null, equipment_entry_date || null, reason || null, blocked_by || null
      ]
    );
    
    res.status(201).json({ 
      success: true, 
      id: result.insertId,
      message: `LOT ${lot_id} agregado a la lista negra` 
    });
  } catch (err) {
    next(err);
  }
};

/**
 * PUT /api/blacklist/:id - Actualizar registro
 */
exports.update = async (req, res, next) => {
  try {
    const { id } = req.params;
    const fields = req.body;
    
    delete fields.id;
    delete fields.created_at;
    
    if (Object.keys(fields).length === 0) {
      return res.status(400).json({ error: 'No hay campos para actualizar' });
    }

    const setClause = Object.keys(fields).map(key => `${key} = ?`).join(', ');
    const values = [...Object.values(fields), id];

    const [result] = await pool.query(
      `UPDATE blacklisted_lots SET ${setClause} WHERE id = ?`,
      values
    );

    if (result.affectedRows === 0) {
      return res.status(404).json({ error: 'Registro no encontrado' });
    }

    res.json({ success: true, message: 'Registro actualizado' });
  } catch (err) {
    next(err);
  }
};

/**
 * DELETE /api/blacklist/:id - Eliminar lote de lista negra
 */
exports.remove = async (req, res, next) => {
  try {
    const { id } = req.params;
    
    const [result] = await pool.query(
      'DELETE FROM blacklisted_lots WHERE id = ?',
      [id]
    );
    
    if (result.affectedRows === 0) {
      return res.status(404).json({ error: 'Registro no encontrado' });
    }
    
    res.json({ success: true, message: 'Registro eliminado de la lista negra' });
  } catch (err) {
    next(err);
  }
};
