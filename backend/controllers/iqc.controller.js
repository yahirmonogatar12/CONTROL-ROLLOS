/**
 * IQC Controller - Inspección de Calidad Entrante
 * Pantalla Flutter: lib/screens/iqc/
 */

const { pool } = require('../config/database');

// Helper function para mapear resultados
const mapResult = (val) => {
  if (!val || val === 'Pending') return 'Pending';
  if (val === 'Pass' || val === 'OK') return 'Pass';
  if (val === 'Fail' || val === 'NG') return 'Fail';
  if (val === 'NA') return 'NA';
  return 'Pending';
};

// Mapeo de disposición a iqc_status
const statusMapping = {
  'Release': 'Released',
  'Return': 'Return',
  'Scrap': 'Scrap',
  'Hold': 'Hold',
  'Rework': 'Rework'
};

// Mapeo de disposición a ubicación
const locationMapping = {
  'Return': 'IQC-RETURN',
  'Scrap': 'IQC-SCRAP',
  'Hold': 'IQC-HOLD',
  'Rework': 'IQC-REWORK'
};

// GET /api/iqc/lot/:labelCode - Buscar lote por código de etiqueta escaneada
exports.getLotByLabel = async (req, res, next) => {
  try {
    const { labelCode } = req.params;
    
    if (!labelCode || labelCode.length < 20) {
      return res.status(400).json({ error: 'Código de etiqueta inválido' });
    }

    const receiving_lot_code = labelCode.substring(0, 20);

    const [materials] = await pool.query(`
      SELECT 
        receiving_lot_code,
        codigo_material,
        numero_parte,
        cliente,
        fecha_recibo,
        SUM(cantidad_actual) as total_qty,
        COUNT(*) as total_labels,
        MIN(iqc_status) as iqc_status
      FROM control_material_almacen_smd 
      WHERE receiving_lot_code = ?
      GROUP BY receiving_lot_code, codigo_material, numero_parte, cliente, fecha_recibo
    `, [receiving_lot_code]);

    if (materials.length === 0) {
      return res.status(404).json({ error: 'Lote no encontrado' });
    }

    const lotInfo = materials[0];

    const [inspections] = await pool.query(
      'SELECT * FROM iqc_inspection_lot_smd WHERE receiving_lot_code = ?',
      [receiving_lot_code]
    );

    let inspection = null;
    if (inspections.length > 0) {
      inspection = inspections[0];
    }

    res.json({
      receiving_lot_code,
      scanned_label: labelCode,
      material_code: lotInfo.codigo_material,
      part_number: lotInfo.numero_parte,
      customer: lotInfo.cliente,
      arrival_date: lotInfo.fecha_recibo,
      total_qty_received: lotInfo.total_qty,
      total_labels: lotInfo.total_labels,
      current_iqc_status: lotInfo.iqc_status,
      inspection: inspection
    });
  } catch (err) {
    next(err);
  }
};

// GET /api/iqc/pending - Listar lotes pendientes de inspección
exports.getPending = async (req, res, next) => {
  try {
    const [rows] = await pool.query(`
      SELECT 
        il.*,
        (SELECT COUNT(*) FROM control_material_almacen_smd WHERE receiving_lot_code = il.receiving_lot_code) as label_count
      FROM iqc_inspection_lot_smd il
      WHERE il.status IN ('Pending', 'InProgress')
      ORDER BY il.created_at DESC
    `);
    res.json(rows);
  } catch (err) {
    next(err);
  }
};

// GET /api/iqc/history - Historial de inspecciones cerradas
exports.getHistory = async (req, res, next) => {
  try {
    const { fecha_inicio, fecha_fin, texto } = req.query;
    let query = `
      SELECT 
        id, receiving_lot_code, sample_label_code, sample_label_id,
        material_code, part_number, customer, supplier, arrival_date,
        total_qty_received, total_labels, 
        sample_qty as sample_size, aql_level,
        rohs_result, brightness_result, dimension_result, color_result, appearance_result,
        disposition, status, inspector, inspector_id, remarks,
        created_at, updated_at, closed_at
      FROM iqc_inspection_lot_smd 
      WHERE status = 'Closed'
    `;
    const params = [];

    if (fecha_inicio && fecha_fin) {
      query += ' AND DATE(closed_at) BETWEEN ? AND DATE_ADD(?, INTERVAL 1 DAY)';
      params.push(fecha_inicio, fecha_fin);
    }
    
    if (texto) {
      query += ` AND (
        receiving_lot_code LIKE ? OR
        material_code LIKE ? OR
        part_number LIKE ? OR
        customer LIKE ?
      )`;
      const searchTerm = `%${texto}%`;
      params.push(searchTerm, searchTerm, searchTerm, searchTerm);
    }

    query += ' ORDER BY closed_at DESC';

    const [rows] = await pool.query(query, params);
    res.json(rows);
  } catch (err) {
    next(err);
  }
};

// GET /api/iqc/count-pending - Contador de lotes pendientes (para badge)
exports.countPending = async (req, res, next) => {
  try {
    const [rows] = await pool.query(`
      SELECT COUNT(*) as count FROM iqc_inspection_lot_smd 
      WHERE status IN ('Pending', 'InProgress')
    `);
    res.json({ count: rows[0].count });
  } catch (err) {
    next(err);
  }
};

// GET /api/iqc/inspection/:id - Obtener una inspección por ID
exports.getById = async (req, res, next) => {
  try {
    const [rows] = await pool.query(
      'SELECT * FROM iqc_inspection_lot_smd WHERE id = ?',
      [req.params.id]
    );
    if (rows.length === 0) {
      return res.status(404).json({ error: 'Inspección no encontrada' });
    }
    
    const [details] = await pool.query(
      'SELECT * FROM iqc_inspection_detail_smd WHERE inspection_lot_id = ? ORDER BY sample_number, characteristic',
      [req.params.id]
    );
    
    res.json({ ...rows[0], details });
  } catch (err) {
    next(err);
  }
};

// POST /api/iqc/inspection - Crear o iniciar inspección
exports.create = async (req, res, next) => {
  try {
    console.log('📦 IQC Inspection body:', JSON.stringify(req.body, null, 2));
    
    const {
      receiving_lot_code,
      sample_label_code,
      sample_label_id,
      material_code,
      part_number,
      customer,
      supplier,
      arrival_date,
      total_qty_received,
      total_labels,
      inspector,
      inspector_id,
      sample_size,
      sampling_level,
      aql,
      rohs_result,
      brightness_result,
      dimension_result,
      color_result,
      appearance_result,
      comments
    } = req.body;
    
    const inspectorName = typeof inspector === 'object' ? (inspector?.username || 'unknown') : (inspector || 'unknown');
    const inspectorIdNum = typeof inspector_id === 'object' ? (inspector_id?.id || null) : (inspector_id || null);

    let mysqlArrivalDate = null;
    if (arrival_date) {
      const dateObj = new Date(arrival_date);
      if (!isNaN(dateObj.getTime())) {
        mysqlArrivalDate = dateObj.toISOString().split('T')[0];
      }
    }

    const [existing] = await pool.query(
      `SELECT id, COALESCE(lot_sequence, 1) as lot_sequence 
       FROM iqc_inspection_lot_smd 
       WHERE receiving_lot_code = ? AND status != 'Closed'
       ORDER BY lot_sequence DESC 
       LIMIT 1`,
      [receiving_lot_code]
    );

    let inspectionId;
    let currentLotSequence = 1;

    if (existing.length > 0) {
      inspectionId = existing[0].id;
      currentLotSequence = existing[0].lot_sequence;
      await pool.query(`
        UPDATE iqc_inspection_lot_smd 
        SET sample_label_code = ?, sample_label_id = ?, inspector = ?, inspector_id = ?,
            sample_qty = ?, aql_level = ?,
            rohs_result = ?, brightness_result = ?, dimension_result = ?, color_result = ?, appearance_result = ?,
            remarks = ?, status = 'InProgress', updated_at = NOW()
        WHERE id = ?
      `, [
        sample_label_code, sample_label_id, inspectorName, inspectorIdNum,
        sample_size || null, aql || sampling_level || null,
        mapResult(rohs_result), mapResult(brightness_result), mapResult(dimension_result), mapResult(color_result), mapResult(appearance_result),
        comments || null, inspectionId
      ]);
    } else {
      const [maxSeq] = await pool.query(
        'SELECT MAX(COALESCE(lot_sequence, 1)) as max_seq FROM iqc_inspection_lot_smd WHERE receiving_lot_code = ?',
        [receiving_lot_code]
      );
      currentLotSequence = (maxSeq[0].max_seq || 0) + 1;
      
      const [result] = await pool.query(`
        INSERT INTO iqc_inspection_lot_smd (
          receiving_lot_code, sample_label_code, sample_label_id,
          material_code, part_number, customer, supplier, arrival_date,
          total_qty_received, total_labels, inspector, inspector_id,
          sample_qty, aql_level, rohs_result, brightness_result, dimension_result, color_result, appearance_result,
          remarks, status, lot_sequence
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'InProgress', ?)
      `, [
        receiving_lot_code, sample_label_code, sample_label_id,
        material_code, part_number, customer, supplier, mysqlArrivalDate,
        total_qty_received, total_labels, inspectorName, inspectorIdNum,
        sample_size || null, aql || sampling_level || null,
        mapResult(rohs_result), mapResult(brightness_result), mapResult(dimension_result), mapResult(color_result), mapResult(appearance_result),
        comments || null, currentLotSequence
      ]);
      inspectionId = result.insertId;
    }

    await pool.query(`
      UPDATE control_material_almacen_smd 
      SET iqc_status = 'InProgress' 
      WHERE receiving_lot_code = ? AND COALESCE(inspection_lot_sequence, 1) = ?
    `, [receiving_lot_code, currentLotSequence]);

    res.status(201).json({
      id: inspectionId,
      message: 'Inspección iniciada exitosamente'
    });
  } catch (err) {
    next(err);
  }
};

// PATCH /api/iqc/inspection/:id/result - Actualizar un campo de resultado específico
exports.updateResult = async (req, res, next) => {
  try {
    const { id } = req.params;
    const { field, result } = req.body;
    
    const allowedFields = ['rohs_result', 'brightness_result', 'dimension_result', 'color_result', 'appearance_result'];
    if (!allowedFields.includes(field)) {
      return res.status(400).json({ error: `Campo no permitido: ${field}` });
    }
    
    const allowedResults = ['Pass', 'Fail', 'NA', 'Pending'];
    if (!allowedResults.includes(result)) {
      return res.status(400).json({ error: `Resultado no válido: ${result}` });
    }
    
    const [updateResult] = await pool.query(
      `UPDATE iqc_inspection_lot_smd SET ${field} = ?, updated_at = NOW() WHERE id = ?`,
      [result, id]
    );
    
    if (updateResult.affectedRows === 0) {
      return res.status(404).json({ error: 'Inspección no encontrada' });
    }
    
    res.json({ message: 'Resultado actualizado exitosamente', field, result });
  } catch (err) {
    next(err);
  }
};

// PUT /api/iqc/inspection/:id - Actualizar inspección (resultados parciales)
exports.update = async (req, res, next) => {
  try {
    const { id } = req.params;
    const body = req.body;
    
    const allowedFields = [
      'sample_label_code', 'sample_label_id', 'aql_level', 'sample_qty',
      'qty_sample_ok', 'qty_sample_ng', 'rohs_result', 'brightness_result',
      'dimension_result', 'color_result', 'appearance_result', 'disposition', 'status',
      'inspector', 'inspector_id', 'remarks'
    ];
    
    const fields = {};
    for (const key of allowedFields) {
      if (body[key] !== undefined) {
        fields[key] = body[key];
      }
    }
    
    if (Object.keys(fields).length === 0) {
      return res.status(400).json({ error: 'No hay campos para actualizar' });
    }

    const setClause = Object.keys(fields).map(key => `${key} = ?`).join(', ');
    const values = [...Object.values(fields), id];

    const [result] = await pool.query(
      `UPDATE iqc_inspection_lot_smd SET ${setClause}, updated_at = NOW() WHERE id = ?`,
      values
    );

    if (result.affectedRows === 0) {
      return res.status(404).json({ error: 'Inspección no encontrada' });
    }

    res.json({ message: 'Inspección actualizada exitosamente' });
  } catch (err) {
    next(err);
  }
};

// PUT /api/iqc/close/:id - Cerrar inspección y propagar disposición
exports.close = async (req, res, next) => {
  try {
    const { id } = req.params;
    const { 
      disposition, remarks, inspector, inspector_id,
      rohs_result, brightness_result, dimension_result, color_result, appearance_result
    } = req.body;

    console.log(`📋 Cerrando inspección ID: ${id}`);
    console.log(`   Disposition: ${disposition}`);

    if (!disposition) {
      return res.status(400).json({ error: 'La disposición es requerida' });
    }
    
    const inspectorName = typeof inspector === 'object' ? (inspector?.username || null) : (inspector || null);
    const inspectorIdNum = typeof inspector_id === 'object' ? (inspector_id?.id || null) : (inspector_id || null);

    const [inspections] = await pool.query(
      'SELECT receiving_lot_code, COALESCE(lot_sequence, 1) as lot_sequence FROM iqc_inspection_lot_smd WHERE id = ?',
      [id]
    );

    if (inspections.length === 0) {
      return res.status(404).json({ error: 'Inspección no encontrada' });
    }

    const receiving_lot_code = inspections[0].receiving_lot_code;
    const lot_sequence = inspections[0].lot_sequence;

    console.log(`   receiving_lot_code: ${receiving_lot_code}`);
    console.log(`   lot_sequence: ${lot_sequence}`);

    const newIqcStatus = statusMapping[disposition] || 'Rejected';

    const [updateResult] = await pool.query(`
      UPDATE iqc_inspection_lot_smd 
      SET disposition = ?, status = 'Closed', remarks = ?, 
          inspector = COALESCE(?, inspector), inspector_id = COALESCE(?, inspector_id),
          rohs_result = COALESCE(?, rohs_result),
          brightness_result = COALESCE(?, brightness_result),
          dimension_result = COALESCE(?, dimension_result),
          color_result = COALESCE(?, color_result),
          appearance_result = COALESCE(?, appearance_result),
          closed_at = NOW(), updated_at = NOW()
      WHERE id = ?
    `, [disposition, remarks, inspectorName, inspectorIdNum, 
        rohs_result, brightness_result, dimension_result, color_result, appearance_result, id]);

    console.log(`   ✓ Inspección actualizada, rows affected: ${updateResult.affectedRows}`);

    console.log(`   📦 Actualizando etiquetas: receiving_lot_code=${receiving_lot_code}, lot_sequence=${lot_sequence}, newStatus=${newIqcStatus}`);
    const [labelUpdateResult] = await pool.query(`
      UPDATE control_material_almacen_smd 
      SET iqc_status = ? 
      WHERE receiving_lot_code = ? AND COALESCE(inspection_lot_sequence, 1) = ?
    `, [newIqcStatus, receiving_lot_code, lot_sequence]);
    console.log(`   ✓ Etiquetas actualizadas, rows affected: ${labelUpdateResult.affectedRows}`);

    if (['Return', 'Scrap', 'Hold', 'Rework'].includes(disposition)) {
      await pool.query(`
        UPDATE control_material_almacen_smd 
        SET ubicacion_salida = ? 
        WHERE receiving_lot_code = ? AND COALESCE(inspection_lot_sequence, 1) = ?
      `, [locationMapping[disposition], receiving_lot_code, lot_sequence]);
    }

    res.json({ 
      message: 'Inspección cerrada exitosamente',
      iqc_status: newIqcStatus,
      labels_updated: true
    });
  } catch (err) {
    next(err);
  }
};

// POST /api/iqc/detail - Agregar detalle de medición
exports.addDetail = async (req, res, next) => {
  try {
    const {
      inspection_lot_id,
      sample_number,
      characteristic,
      test_name,
      measured_value,
      unit,
      min_spec,
      max_spec,
      result,
      remarks,
      measured_by
    } = req.body;

    const [insertResult] = await pool.query(`
      INSERT INTO iqc_inspection_detail_smd (
        inspection_lot_id, sample_number, characteristic, test_name,
        measured_value, unit, min_spec, max_spec, result, remarks, measured_by
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    `, [
      inspection_lot_id, sample_number, characteristic, test_name,
      measured_value, unit, min_spec, max_spec, result, remarks, measured_by
    ]);

    res.status(201).json({
      id: insertResult.insertId,
      message: 'Detalle agregado exitosamente'
    });
  } catch (err) {
    next(err);
  }
};

// GET /api/iqc/detail/:inspectionId - Obtener detalles de una inspección
exports.getDetails = async (req, res, next) => {
  try {
    const [rows] = await pool.query(
      'SELECT * FROM iqc_inspection_detail_smd WHERE inspection_lot_id = ? ORDER BY sample_number, characteristic',
      [req.params.inspectionId]
    );
    res.json(rows);
  } catch (err) {
    next(err);
  }
};

// DELETE /api/iqc/detail/:id - Eliminar detalle de medición
exports.deleteDetail = async (req, res, next) => {
  try {
    const [result] = await pool.query(
      'DELETE FROM iqc_inspection_detail_smd WHERE id = ?',
      [req.params.id]
    );

    if (result.affectedRows === 0) {
      return res.status(404).json({ error: 'Detalle no encontrado' });
    }

    res.json({ message: 'Detalle eliminado exitosamente' });
  } catch (err) {
    next(err);
  }
};

// POST /api/iqc/:id/measurements - Guardar mediciones en batch
exports.saveMeasurements = async (req, res, next) => {
  try {
    const inspectionId = req.params.id;
    const { measurements } = req.body;
    
    if (!measurements || !Array.isArray(measurements)) {
      return res.status(400).json({ error: 'measurements array requerido' });
    }
    
    await pool.query('DELETE FROM iqc_inspection_detail_smd WHERE inspection_lot_id = ?', [inspectionId]);
    
    for (const m of measurements) {
      if (m.result && m.result !== 'Pending') {
        await pool.query(`
          INSERT INTO iqc_inspection_detail_smd 
          (inspection_lot_id, sample_number, characteristic, measured_value, result, measured_at)
          VALUES (?, ?, ?, ?, ?, NOW())
        `, [
          inspectionId,
          m.sampleNum,
          m.type,
          m.value || null,
          m.result
        ]);
      }
    }
    
    res.json({ success: true, message: 'Mediciones guardadas exitosamente' });
  } catch (err) {
    next(err);
  }
};

// GET /api/iqc/:id/measurements - Obtener mediciones agrupadas por tipo
exports.getMeasurements = async (req, res, next) => {
  try {
    const inspectionId = req.params.id;
    
    const [rows] = await pool.query(`
      SELECT id, sample_number as sampleNum, characteristic as type, measured_value as value, result
      FROM iqc_inspection_detail_smd 
      WHERE inspection_lot_id = ?
      ORDER BY characteristic, sample_number
    `, [inspectionId]);
    
    const grouped = {
      brightness: [],
      dimension: [],
      color: [],
      appearance: []
    };
    
    for (const row of rows) {
      const type = row.type?.toLowerCase() || 'other';
      if (grouped[type]) {
        grouped[type].push({
          sampleNum: row.sampleNum,
          result: row.result,
          value: row.value || ''
        });
      }
    }
    
    res.json({ success: true, data: grouped });
  } catch (err) {
    next(err);
  }
};

// GET /api/iqc/inspection/:id/can-release - Validar si lote puede liberarse
exports.canRelease = async (req, res, next) => {
  try {
    const [blockingNGs] = await pool.query(`
      SELECT ir.id, ir.judgment, qs.spec_code, qs.inspection_item
      FROM iqc_inspection_result ir
      JOIN quality_specs qs ON ir.spec_id = qs.id
      WHERE ir.inspection_lot_id = ? AND ir.judgment = 'NG' AND qs.is_blocking = 1
    `, [req.params.id]);
    
    res.json({
      canRelease: blockingNGs.length === 0,
      blockingItems: blockingNGs
    });
  } catch (err) {
    next(err);
  }
};
