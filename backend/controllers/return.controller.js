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
  const connection = await pool.getConnection();

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

    const parsedReturnQty = Number(return_qty);
    if (!Number.isFinite(parsedReturnQty) || parsedReturnQty <= 0) {
      return res.status(400).json({ error: 'Return quantity must be greater than zero' });
    }

    await connection.beginTransaction();

    const warehousingQuery = warehousing_id
      ? [
          `SELECT id, codigo_material_recibido, numero_parte, numero_lote_material,
                  cantidad_actual, tiene_salida
           FROM control_material_almacen_smd WHERE id = ? FOR UPDATE`,
          [warehousing_id]
        ]
      : [
          `SELECT id, codigo_material_recibido, numero_parte, numero_lote_material,
                  cantidad_actual, tiene_salida
           FROM control_material_almacen_smd
           WHERE codigo_material_recibido = ? LIMIT 1 FOR UPDATE`,
          [material_warehousing_code]
        ];

    const [warehousingRows] = await connection.query(
      warehousingQuery[0],
      warehousingQuery[1]
    );

    if (warehousingRows.length === 0) {
      await connection.rollback();
      return res.status(404).json({ error: 'Warehousing entry not found' });
    }

    const material = warehousingRows[0];
    const realPartNumber = material.numero_parte || part_number;
    const realLotNo = material.numero_lote_material || material_lot_no;
    const realCode = material.codigo_material_recibido || material_warehousing_code;

    const [lotRows] = await connection.query(`
      SELECT id, total_entrada, total_salida
      FROM inventario_lotes_smd
      WHERE codigo_material_recibido = ?
      LIMIT 1
      FOR UPDATE
    `, [realCode]);

    if (lotRows.length === 0) {
      await connection.rollback();
      return res.status(404).json({ error: 'Inventory lot not found' });
    }

    const totalSalidaBefore = Number(lotRows[0].total_salida || 0);
    if (parsedReturnQty > totalSalidaBefore) {
      await connection.rollback();
      return res.status(400).json({
        error: `Return quantity (${parsedReturnQty}) exceeds outgoing quantity (${totalSalidaBefore})`
      });
    }

    // El trigger trg_return_ai_smd descuenta total_salida dentro de esta misma
    // transaccion. Se usan los datos reales del almacen para evitar otro lote.
    const [result] = await connection.query(`
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
      material.id,
      realCode,
      realPartNumber,
      realLotNo,
      parsedReturnQty,
      remarks || null,
      returned_by
    ]);

    const [afterTriggerRows] = await connection.query(`
      SELECT total_salida FROM inventario_lotes_smd WHERE id = ? FOR UPDATE
    `, [lotRows[0].id]);
    const expectedTotalSalida = Math.max(0, totalSalidaBefore - parsedReturnQty);
    const totalSalidaAfterTrigger = Number(afterTriggerRows[0]?.total_salida || 0);
    if (totalSalidaAfterTrigger - 0.0001 > expectedTotalSalida) {
      await connection.query(`
        UPDATE inventario_lotes_smd SET total_salida = ? WHERE id = ?
      `, [expectedTotalSalida, lotRows[0].id]);
    }

    const currentQty = Number(material.cantidad_actual || 0);
    const newQty = Number(material.tiene_salida || 0) === 1
      ? parsedReturnQty
      : currentQty + parsedReturnQty;

    await connection.query(`
      UPDATE control_material_almacen_smd
      SET cantidad_actual = ?, tiene_salida = 0
      WHERE id = ?
    `, [newQty, material.id]);

    // trg_almacen_au_smd interpreta un cambio de cantidad_actual como ajuste
    // de entrada. En una devolucion la entrada historica no cambia: restaurar
    // ambos acumulados deja stock_actual exactamente en la cantidad retornada.
    await connection.query(`
      UPDATE inventario_lotes_smd
      SET total_entrada = ?, total_salida = ?
      WHERE id = ?
    `, [
      Number(lotRows[0].total_entrada || 0),
      expectedTotalSalida,
      lotRows[0].id
    ]);

    // Si la salida fue generada por una auditoria aun activa, el retorno debe
    // reabrir esa parte; de lo contrario la auditoria queda ProcessedOut
    // mientras inventario_lotes_smd vuelve a mostrar stock.
    const [auditItems] = await connection.query(`
      SELECT iai.id, iai.audit_id, iai.location
      FROM inventory_audit_item_smd iai
      JOIN inventory_audit_smd ia ON ia.id = iai.audit_id
      WHERE ia.status = 'InProgress'
        AND iai.warehousing_id = ?
        AND iai.status = 'ProcessedOut'
      FOR UPDATE
    `, [material.id]);

    for (const auditItem of auditItems) {
      await connection.query(`
        UPDATE inventory_audit_item_smd
        SET status = 'Found',
            scanned_at = NOW(),
            scanned_by = ?,
            processed_at = NULL,
            processed_by = NULL,
            notas = CONCAT_WS(' | ', NULLIF(notas, ''), 'Retorno durante auditoria activa')
        WHERE id = ?
      `, [returned_by || 'Sistema', auditItem.id]);

      await connection.query(`
        UPDATE inventory_audit_part_smd
        SET status = 'Mismatch',
            flagged_by = ?,
            flagged_at = NOW()
        WHERE audit_id = ?
          AND location = ?
          AND numero_parte = ?
          AND status = 'MissingConfirmed'
      `, [returned_by || 'Sistema', auditItem.audit_id, auditItem.location, realPartNumber]);

      await connection.query(`
        UPDATE inventory_audit_location_smd
        SET status = 'InProgress', completed_at = NULL, completed_by = NULL
        WHERE audit_id = ? AND location = ? AND status = 'Discrepancy'
      `, [auditItem.audit_id, auditItem.location]);
    }

    await connection.commit();

    res.status(201).json({
      success: true,
      message: 'Return created successfully',
      id: result.insertId,
      new_qty: newQty,
      audit_reopened: auditItems.length > 0
    });
  } catch (err) {
    await connection.rollback();
    next(err);
  } finally {
    connection.release();
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
