/**
 * Quarantine Controller - Cuarentena
 * Pantalla Flutter: lib/screens/quarantine/
 */

const { pool } = require('../config/database');

// GET /api/quarantine - Obtener materiales en cuarentena
exports.getAll = async (req, res, next) => {
  try {
    const { status } = req.query;
    let query = `SELECT * FROM quarantine_smd`;
    const params = [];
    
    if (status) {
      query += ` WHERE status = ?`;
      params.push(status);
    }
    
    query += ` ORDER BY created_at DESC`;
    
    const [rows] = await pool.query(query, params);
    res.json(rows);
  } catch (err) {
    next(err);
  }
};

// GET /api/quarantine/:id/history - Obtener historial de un item de cuarentena
exports.getHistory = async (req, res, next) => {
  try {
    const { id } = req.params;
    const [rows] = await pool.query(
      `SELECT * FROM quarantine_history_smd WHERE quarantine_id = ? ORDER BY action_at DESC`,
      [id]
    );
    res.json(rows);
  } catch (err) {
    next(err);
  }
};

// GET /api/quarantine/history/all - Historial completo de cuarentena (items cerrados)
exports.getAllHistory = async (req, res, next) => {
  try {
    const { fecha_inicio, fecha_fin } = req.query;
    let query = `SELECT q.*, 
                   (SELECT COUNT(*) FROM quarantine_history_smd WHERE quarantine_id = q.id) as history_count
                 FROM quarantine_smd q 
                 WHERE q.status != 'InQuarantine'`;
    const params = [];
    
    if (fecha_inicio && fecha_fin) {
      query += ` AND DATE(q.closed_at) BETWEEN ? AND ?`;
      params.push(fecha_inicio, fecha_fin);
    }
    
    query += ` ORDER BY q.closed_at DESC`;
    
    const [rows] = await pool.query(query, params);
    res.json(rows);
  } catch (err) {
    next(err);
  }
};

// POST /api/quarantine/send - Enviar materiales a cuarentena (bulk)
exports.send = async (req, res, next) => {
  try {
    const { items, reason, userId, userName } = req.body;
    
    if (!items || !Array.isArray(items) || items.length === 0) {
      return res.status(400).json({ error: 'No items provided' });
    }
    
    const created = [];
    const errors = [];
    
    for (const item of items) {
      try {
        const [existing] = await pool.query(
          `SELECT id, en_cuarentena FROM control_material_almacen_smd WHERE codigo_material_recibido = ?`,
          [item.codigo_material_recibido]
        );
        
        if (existing.length === 0) {
          errors.push({ codigo: item.codigo_material_recibido, error: 'Material not found' });
          continue;
        }
        
        if (existing[0].en_cuarentena === 1) {
          errors.push({ codigo: item.codigo_material_recibido, error: 'Already in quarantine' });
          continue;
        }
        
        const [result] = await pool.query(
          `INSERT INTO quarantine_smd (
            warehousing_id, codigo_material_recibido, part_number, material_code,
            cantidad, especificacion, ubicacion_original, reason,
            created_by_id, created_by_name
          ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
          [
            item.id || existing[0].id,
            item.codigo_material_recibido,
            item.numero_parte || item.part_number,
            item.codigo_material || item.material_code,
            item.cantidad_actual || item.cantidad || 0,
            item.especificacion,
            item.ubicacion_salida || item.ubicacion_original,
            reason,
            userId,
            userName
          ]
        );
        
        const quarantineId = result.insertId;
        
        await pool.query(
          `INSERT INTO quarantine_history_smd (quarantine_id, action, new_status, comments, action_by_id, action_by_name)
           VALUES (?, 'Created', 'InQuarantine', ?, ?, ?)`,
          [quarantineId, reason, userId, userName]
        );
        
        await pool.query(
          `UPDATE control_material_almacen_smd SET en_cuarentena = 1 WHERE codigo_material_recibido = ?`,
          [item.codigo_material_recibido]
        );
        
        created.push({ id: quarantineId, codigo: item.codigo_material_recibido });
      } catch (e) {
        errors.push({ codigo: item.codigo_material_recibido, error: e.message });
      }
    }
    
    res.status(201).json({ 
      success: true, 
      created: created.length, 
      errors: errors.length,
      createdItems: created,
      errorItems: errors 
    });
  } catch (err) {
    next(err);
  }
};

// PUT /api/quarantine/:id - Actualizar estado de cuarentena
exports.update = async (req, res, next) => {
  try {
    const { id } = req.params;
    const { status, comments, userId, userName } = req.body;
    
    const [current] = await pool.query(
      `SELECT status, codigo_material_recibido, cantidad FROM quarantine_smd WHERE id = ?`, 
      [id]
    );
    if (current.length === 0) {
      return res.status(404).json({ error: 'Quarantine item not found' });
    }
    
    const oldStatus = current[0].status;
    const codigo = current[0].codigo_material_recibido;
    
    let action = 'StatusChanged';
    if (status === 'Released') action = 'Released';
    else if (status === 'Scrapped') action = 'Scrapped';
    else if (status === 'Returned') action = 'Returned';
    
    const updateFields = ['updated_at = NOW()'];
    const updateValues = [];
    
    if (status) {
      updateFields.push('status = ?');
      updateValues.push(status);
      
      if (status !== 'InQuarantine') {
        updateFields.push('closed_at = NOW()', 'closed_by_id = ?', 'closed_by_name = ?');
        updateValues.push(userId, userName);
      }
    }
    
    updateValues.push(id);
    await pool.query(`UPDATE quarantine_smd SET ${updateFields.join(', ')} WHERE id = ?`, updateValues);
    
    await pool.query(
      `INSERT INTO quarantine_history_smd (quarantine_id, action, old_status, new_status, comments, action_by_id, action_by_name)
       VALUES (?, ?, ?, ?, ?, ?, ?)`,
      [id, action, oldStatus, status || oldStatus, comments, userId, userName]
    );
    
    if (status === 'Released') {
      await pool.query(
        `UPDATE control_material_almacen_smd SET en_cuarentena = 0 WHERE codigo_material_recibido = ?`,
        [codigo]
      );
    }
    
    if (status === 'Scrapped' || status === 'Returned') {
      await pool.query(
        `UPDATE control_material_almacen_smd SET en_cuarentena = 0, estado_desecho = 1 WHERE codigo_material_recibido = ?`,
        [codigo]
      );
      
      await pool.query(
        `UPDATE inventario_lotes_smd SET total_salida = total_entrada WHERE codigo_material_recibido = ?`,
        [codigo]
      );
    }
    
    res.json({ success: true, message: 'Quarantine updated' });
  } catch (err) {
    next(err);
  }
};

// POST /api/quarantine/:id/comment - Agregar comentario a cuarentena
exports.addComment = async (req, res, next) => {
  try {
    const { id } = req.params;
    const { comments, userId, userName } = req.body;
    
    const [current] = await pool.query(`SELECT status FROM quarantine_smd WHERE id = ?`, [id]);
    if (current.length === 0) {
      return res.status(404).json({ error: 'Quarantine item not found' });
    }
    
    await pool.query(
      `INSERT INTO quarantine_history_smd (quarantine_id, action, old_status, new_status, comments, action_by_id, action_by_name)
       VALUES (?, 'CommentAdded', ?, ?, ?, ?, ?)`,
      [id, current[0].status, current[0].status, comments, userId, userName]
    );
    
    await pool.query(`UPDATE quarantine_smd SET updated_at = NOW() WHERE id = ?`, [id]);
    
    res.json({ success: true, message: 'Comment added' });
  } catch (err) {
    next(err);
  }
};
