const { pool } = require('../config/database');

// GET /api/return - Obtener todas las devoluciones
exports.getAll = async (req, res, next) => {
  try {
    const [rows] = await pool.query(`
      SELECT 
        mr.*,
        cma.especificacion as material_spec,
        cma.codigo_material as material_code,
        cma.cantidad_estandarizada as packaging_unit,
        IFNULL(cma.unidad_medida, 'EA') as unidad_medida
      FROM material_return_smd mr
      LEFT JOIN control_material_almacen_smd cma ON mr.warehousing_id = cma.id
      ORDER BY mr.return_datetime DESC
    `);
    res.json(rows);
  } catch (err) {
    next(err);
  }
};

// GET /api/return/search - Buscar devoluciones por fecha y texto
exports.search = async (req, res, next) => {
  try {
    const { fechaInicio, fechaFin, texto } = req.query;
    
    let query = `
      SELECT 
        mr.*,
        cma.especificacion as material_spec,
        cma.codigo_material as material_code,
        cma.cantidad_estandarizada as packaging_unit,
        IFNULL(cma.unidad_medida, 'EA') as unidad_medida
      FROM material_return_smd mr
      LEFT JOIN control_material_almacen_smd cma ON mr.warehousing_id = cma.id
      WHERE 1=1
    `;
    
    const params = [];
    
    if (fechaInicio && fechaFin) {
      query += ` AND DATE(mr.return_datetime) BETWEEN ? AND ?`;
      params.push(fechaInicio, fechaFin);
    } else if (fechaInicio) {
      query += ` AND DATE(mr.return_datetime) >= ?`;
      params.push(fechaInicio);
    } else if (fechaFin) {
      query += ` AND DATE(mr.return_datetime) <= ?`;
      params.push(fechaFin);
    }

    // Búsqueda por texto (Lot No, código material, número parte, etc.)
    if (texto && texto.trim()) {
      const searchText = `%${texto.trim()}%`;
      query += ` AND (
        mr.material_lot_no LIKE ? OR
        mr.material_warehousing_code LIKE ? OR
        mr.part_number LIKE ? OR
        cma.especificacion LIKE ? OR
        cma.codigo_material LIKE ?
      )`;
      params.push(searchText, searchText, searchText, searchText, searchText);
    }
    
    query += ` ORDER BY mr.return_datetime DESC`;
    
    const [rows] = await pool.query(query, params);
    res.json(rows);
  } catch (err) {
    next(err);
  }
};

// GET /api/return/by-warehousing/:code - Obtener info de entrada por código de almacenamiento
exports.getWarehousingInfo = async (req, res, next) => {
  try {
    const { code } = req.params;
    
    const [rows] = await pool.query(`
      SELECT 
        id,
        codigo_material_recibido as material_warehousing_code,
        codigo_material as material_code,
        numero_parte as part_number,
        numero_lote_material as material_lot_no,
        cantidad_estandarizada as packaging_unit,
        cantidad_actual as remain_qty,
        especificacion as material_spec
      FROM control_material_almacen_smd
      WHERE codigo_material_recibido = ? AND estado_desecho = 0
    `, [code]);
    
    if (rows.length === 0) {
      return res.status(404).json({ error: 'Warehousing entry not found or already disposed' });
    }
    
    res.json(rows[0]);
  } catch (err) {
    next(err);
  }
};

// POST /api/return - Crear una nueva devolución
exports.create = async (req, res, next) => {
  try {
    const {
      warehousing_id,
      material_warehousing_code,
      part_number,
      material_lot_no,
      return_qty,
      returned_by,
      remarks
    } = req.body;
    
    // Validar campos requeridos
    if (!material_warehousing_code || !return_qty) {
      return res.status(400).json({ error: 'Warehousing code and return quantity are required' });
    }
    
    // Obtener la cantidad actual REAL de la BD (no confiar en el frontend)
    let currentQty = 0;
    if (warehousing_id) {
      const [rows] = await pool.query(
        'SELECT cantidad_actual FROM control_material_almacen_smd WHERE id = ?',
        [warehousing_id]
      );
      if (rows.length > 0) {
        currentQty = rows[0].cantidad_actual || 0;
      }
    }
    
    // Insertar la devolución usando la estructura real de la tabla
    const [result] = await pool.query(`
      INSERT INTO material_return_smd (
        warehousing_id,
        material_warehousing_code,
        part_number,
        material_lot_no,
        return_qty,
        remarks,
        returned_by,
        return_datetime
      ) VALUES (?, ?, ?, ?, ?, ?, ?, NOW())
    `, [
      warehousing_id,
      material_warehousing_code,
      part_number,
      material_lot_no,
      return_qty,
      remarks || null,
      returned_by
    ]);
    
    // Actualizar cantidad en la entrada original - REEMPLAZAR con la cantidad devuelta
    // return_qty es la cantidad que QUEDA/REGRESA al almacén
    // Y resetear tiene_salida a 0 para permitir nueva salida
    const newQty = return_qty;
    if (warehousing_id) {
      // Obtener datos del registro original para actualizar inventario_lotes_smd
      const [originalData] = await pool.query(
        'SELECT numero_parte, numero_lote_material, codigo_material_recibido FROM control_material_almacen_smd WHERE id = ?',
        [warehousing_id]
      );
      
      await pool.query(`
        UPDATE control_material_almacen_smd
        SET cantidad_actual = ?,
            tiene_salida = 0
        WHERE id = ?
      `, [newQty, warehousing_id]);
      
      // Actualizar inventario_lotes_smd - RESTAR la cantidad devuelta del total_salida
      if (originalData.length > 0) {
        const { numero_parte, numero_lote_material, codigo_material_recibido } = originalData[0];
        await pool.query(`
          UPDATE inventario_lotes_smd
          SET total_salida = GREATEST(0, total_salida - ?)
          WHERE codigo_material_recibido = ?
            AND numero_parte = ?
            AND numero_lote = ?
        `, [return_qty, codigo_material_recibido, numero_parte, numero_lote_material]);
      }
    }
    
    res.status(201).json({
      success: true,
      message: 'Return created successfully',
      id: result.insertId,
      new_qty: newQty
    });
  } catch (err) {
    next(err);
  }
};

// GET /api/return/:id - Obtener una devolución por ID
exports.getById = async (req, res, next) => {
  try {
    const { id } = req.params;
    
    const [rows] = await pool.query(`
      SELECT 
        mr.*,
        cma.especificacion as material_spec,
        cma.codigo_material as material_code,
        cma.cantidad_estandarizada as packaging_unit
      FROM material_return_smd mr
      LEFT JOIN control_material_almacen_smd cma ON mr.warehousing_id = cma.id
      WHERE mr.id = ?
    `, [id]);
    
    if (rows.length === 0) {
      return res.status(404).json({ error: 'Return not found' });
    }
    
    res.json(rows[0]);
  } catch (err) {
    next(err);
  }
};

// DELETE /api/return/:id - Eliminar una devolución (revertir cantidades - RESTAR porque se había sumado)
exports.delete = async (req, res, next) => {
  try {
    const { id } = req.params;
    
    // Obtener la devolución primero
    const [returns] = await pool.query('SELECT * FROM material_return_smd WHERE id = ?', [id]);
    
    if (returns.length === 0) {
      return res.status(404).json({ error: 'Return not found' });
    }
    
    const returnData = returns[0];
    
    // Revertir la cantidad en la entrada original (RESTAR porque al crear se sumó)
    if (returnData.warehousing_id) {
      await pool.query(`
        UPDATE control_material_almacen_smd
        SET cantidad_actual = cantidad_actual - ?
        WHERE id = ?
      `, [returnData.cantidad_devuelta, returnData.warehousing_id]);
    }
    
    // Eliminar la devolución
    await pool.query('DELETE FROM material_return_smd WHERE id = ?', [id]);
    
    res.json({ success: true, message: 'Return deleted and quantities reverted' });
  } catch (err) {
    next(err);
  }
};
