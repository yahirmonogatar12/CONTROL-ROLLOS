/**
 * Controlador para Warehousing (Entrada de Material)
 * Corresponde a: screens/material_warehousing/
 */
const { pool, getMexicoDate } = require('../config/database');
const { findMaterialConfig } = require('../utils/partNumberHelper');
const { getNextLabelSequenceSafe, getNextLabelSequencePreview, getNextInternalLotSequenceSafe, reserveLabelSequences } = require('../utils/sequenceService');

const WAREHOUSE_OUTGOING_START_DATE = process.env.WAREHOUSE_OUTGOING_START_DATE || getMexicoDate();
const WAREHOUSE_OUTGOING_START_DATETIME = `${WAREHOUSE_OUTGOING_START_DATE} 00:00:00`;

// GET /api/warehousing - Lista todos los registros
const getAll = async (req, res, next) => {
  try {
    const [rows] = await pool.query(`
      SELECT cma.*, COALESCE(cma.ubicacion_destino, cma.ubicacion_salida) as location,
             CASE WHEN q.id IS NOT NULL AND q.status NOT IN ('Released', 'Scrapped', 'Returned') THEN 1 ELSE 0 END as in_quarantine
      FROM control_material_almacen_smd cma
      LEFT JOIN quarantine_smd q ON cma.id = q.warehousing_id
      ORDER BY cma.fecha_registro DESC
    `);
    res.json(rows);
  } catch (err) {
    next(err);
  }
};

// GET /api/warehousing/search - Buscar por fechas y/o texto
const search = async (req, res, next) => {
  try {
    const { fecha_inicio, fecha_fin, texto } = req.query;
    let query = `
      SELECT cma.*, COALESCE(cma.ubicacion_destino, cma.ubicacion_salida) as location,
             CASE WHEN q.id IS NOT NULL AND q.status NOT IN ('Released', 'Scrapped', 'Returned') THEN 1 ELSE 0 END as in_quarantine
      FROM control_material_almacen_smd cma
      LEFT JOIN quarantine_smd q ON cma.id = q.warehousing_id
      WHERE 1=1
    `;
    const params = [];

    if (fecha_inicio && fecha_fin) {
      query += ' AND DATE(cma.fecha_recibo) BETWEEN ? AND ?';
      params.push(fecha_inicio, fecha_fin);
    }
    
    if (texto) {
      query += ` AND (
        cma.codigo_material_recibido LIKE ? OR
        cma.codigo_material LIKE ? OR
        cma.codigo_material_original LIKE ? OR
        cma.numero_parte LIKE ? OR
        cma.numero_lote_material LIKE ? OR
        cma.cliente LIKE ? OR
        cma.especificacion LIKE ? OR
        cma.propiedad_material LIKE ? OR
        cma.ubicacion_destino LIKE ?
      )`;
      const searchTerm = `%${texto}%`;
      params.push(searchTerm, searchTerm, searchTerm, searchTerm, searchTerm, searchTerm, searchTerm, searchTerm, searchTerm);
    }

    query += ' ORDER BY cma.fecha_registro DESC';

    const [rows] = await pool.query(query, params);
    res.json(rows);
  } catch (err) {
    next(err);
  }
};

// GET /api/warehousing/by-code/:code - Buscar por código de etiqueta
// Query param: ?forReturn=true para validar que tenga salida (usado en retornos)
const getByCode = async (req, res, next) => {
  try {
    const { code: rawCode } = req.params;
    const code = (rawCode || '').trim().toUpperCase();
    const forReturn = req.query.forReturn === 'true';
    
    // Primero verificar si existe el registro (para dar mejor mensaje de error)
    const [checkRows] = await pool.query(`
      SELECT cancelado, cantidad_actual, tiene_salida
      FROM control_material_almacen_smd
      WHERE UPPER(codigo_material_recibido) = ?
      LIMIT 1
    `, [code]);
    
    if (checkRows.length === 0) {
      return res.status(404).json({ error: 'Registro no encontrado' });
    }
    
    const record = checkRows[0];
    
    if (record.cancelado === 1) {
      return res.status(400).json({ error: 'Este registro está cancelado', code: 'CANCELLED' });
    }
    
    if (record.cantidad_actual <= 0) {
      return res.status(400).json({ error: 'Este lote no tiene cantidad disponible (qty = 0)', code: 'NO_QUANTITY' });
    }
    
    // Solo validar tiene_salida cuando es para retorno
    if (forReturn && record.tiene_salida !== 1) {
      return res.status(400).json({ error: 'Este lote no tiene salidas registradas, no aplica para retorno', code: 'NO_OUTPUT' });
    }
    
    // Si pasa todas las validaciones, obtener datos completos
    const [rows] = await pool.query(`
      SELECT cma.*, COALESCE(cma.ubicacion_destino, cma.ubicacion_salida) as location,
             CASE WHEN q.id IS NOT NULL AND q.status NOT IN ('Released', 'Scrapped', 'Returned') THEN 1 ELSE 0 END as in_quarantine
      FROM control_material_almacen_smd cma
      LEFT JOIN quarantine_smd q ON cma.id = q.warehousing_id
      WHERE cma.codigo_material_recibido = ?
      LIMIT 1
    `, [code]);

    res.json(rows[0]);
  } catch (err) {
    next(err);
  }
};

// GET /api/warehousing/smart-search/:code - Búsqueda inteligente por código, parte o lote
const smartSearch = async (req, res, next) => {
  try {
    const { code } = req.params;
    
    // Primero intentar búsqueda exacta por codigo_material_recibido (case-insensitive)
    let [rows] = await pool.query(`
      SELECT cma.*, COALESCE(cma.ubicacion_destino, cma.ubicacion_salida) as location,
             CASE WHEN q.id IS NOT NULL AND q.status NOT IN ('Released', 'Scrapped', 'Returned') THEN 1 ELSE 0 END as in_quarantine,
             'exact' as match_type
      FROM control_material_almacen_smd cma
      LEFT JOIN quarantine_smd q ON cma.id = q.warehousing_id
      WHERE UPPER(cma.codigo_material_recibido) = ?
      AND cma.cancelado = 0
      AND cma.cantidad_actual > 0
      LIMIT 1
    `, [code]);

    if (rows.length > 0) {
      return res.json({ type: 'single', data: rows[0], match_type: 'exact' });
    }

    // Si no hay exacto, buscar por numero_parte (puede devolver múltiples)
    [rows] = await pool.query(`
      SELECT cma.*, COALESCE(cma.ubicacion_destino, cma.ubicacion_salida) as location,
             CASE WHEN q.id IS NOT NULL AND q.status NOT IN ('Released', 'Scrapped', 'Returned') THEN 1 ELSE 0 END as in_quarantine
      FROM control_material_almacen_smd cma
      LEFT JOIN quarantine_smd q ON cma.id = q.warehousing_id
      WHERE UPPER(cma.numero_parte) = ?
      AND cma.cancelado = 0
      AND cma.cantidad_actual > 0
      ORDER BY cma.fecha_recibo ASC
    `, [code]);

    if (rows.length > 0) {
      return res.json({ type: 'multiple', data: rows, match_type: 'part_number', count: rows.length });
    }

    // Buscar por numero_lote_material
    [rows] = await pool.query(`
      SELECT cma.*, COALESCE(cma.ubicacion_destino, cma.ubicacion_salida) as location,
             CASE WHEN q.id IS NOT NULL AND q.status NOT IN ('Released', 'Scrapped', 'Returned') THEN 1 ELSE 0 END as in_quarantine
      FROM control_material_almacen_smd cma
      LEFT JOIN quarantine_smd q ON cma.id = q.warehousing_id
      WHERE UPPER(cma.numero_lote_material) = ?
      AND cma.cancelado = 0
      AND cma.cantidad_actual > 0
      ORDER BY cma.fecha_recibo ASC
    `, [code]);

    if (rows.length > 0) {
      return res.json({ type: rows.length === 1 ? 'single' : 'multiple', data: rows.length === 1 ? rows[0] : rows, match_type: 'lot_number', count: rows.length });
    }

    // Búsqueda parcial por numero_parte (LIKE)
    [rows] = await pool.query(`
      SELECT cma.*, COALESCE(cma.ubicacion_destino, cma.ubicacion_salida) as location,
             CASE WHEN q.id IS NOT NULL AND q.status NOT IN ('Released', 'Scrapped', 'Returned') THEN 1 ELSE 0 END as in_quarantine
      FROM control_material_almacen_smd cma
      LEFT JOIN quarantine_smd q ON cma.id = q.warehousing_id
      WHERE cma.numero_parte LIKE ?
      AND cma.cancelado = 0
      AND cma.cantidad_actual > 0
      ORDER BY cma.fecha_recibo ASC
      LIMIT 50
    `, [`%${code}%`]);

    if (rows.length > 0) {
      return res.json({ type: 'multiple', data: rows, match_type: 'partial', count: rows.length });
    }

    return res.status(404).json({ error: 'No se encontraron registros' });
  } catch (err) {
    next(err);
  }
};

// GET /api/warehousing/next-sequence - Siguiente secuencia para etiqueta (SEGURO - sin race conditions)
const getNextSequence = async (req, res, next) => {
  try {
    const { partNumber, date } = req.query;
    
    if (!partNumber || !date) {
      return res.status(400).json({ error: 'Se requiere partNumber y date' });
    }

    // Usar el servicio seguro con transacción y bloqueo
    const result = await getNextLabelSequenceSafe(partNumber, date);
    res.json(result);
  } catch (err) {
    next(err);
  }
};

// GET /api/warehousing/next-sequence-preview - Siguiente secuencia SOLO PARA PREVIEW (no actualiza cache)
const getNextSequencePreview = async (req, res, next) => {
  try {
    const { partNumber, date } = req.query;
    
    if (!partNumber || !date) {
      return res.status(400).json({ error: 'Se requiere partNumber y date' });
    }

    // Usar el servicio de preview que NO actualiza el cache
    const result = await getNextLabelSequencePreview(partNumber, date);
    res.json(result);
  } catch (err) {
    next(err);
  }
};

// GET /api/warehousing/reserve-sequences - Reservar múltiples secuencias de forma atómica
const reserveSequences = async (req, res, next) => {
  try {
    const { partNumber, date, count } = req.query;
    
    if (!partNumber || !date) {
      return res.status(400).json({ error: 'Se requiere partNumber y date' });
    }

    const numCount = parseInt(count, 10) || 1;
    
    // Reservar múltiples secuencias de forma atómica
    const result = await reserveLabelSequences(partNumber, date, numCount);
    res.json(result);
  } catch (err) {
    next(err);
  }
};

// GET /api/warehousing/next-internal-lot-sequence - Siguiente secuencia de lote interno (SEGURO)
const getNextInternalLotSequence = async (req, res, next) => {
  try {
    // Usar el servicio seguro con transacción y bloqueo
    const result = await getNextInternalLotSequenceSafe();
    res.json({ 
      nextSequence: result.nextSequence,
      nextLotNumber: result.nextLotNumber 
    });
  } catch (err) {
    next(err);
  }
};

// GET /api/warehousing/fifo-check - Validación FIFO
const fifoCheck = async (req, res, next) => {
  try {
    const { material_code, current_date } = req.query;
    
    if (!material_code) {
      return res.status(400).json({ error: 'Se requiere material_code' });
    }

    const [rows] = await pool.query(`
      SELECT codigo_material_recibido, fecha_recibo, cantidad_actual
      FROM control_material_almacen_smd 
      WHERE codigo_material = ? 
        AND cantidad_actual > 0
        AND fecha_recibo < ?
      ORDER BY fecha_recibo ASC 
      LIMIT 1
    `, [material_code, current_date || new Date().toISOString().split('T')[0]]);

    if (rows.length > 0) {
      const older = rows[0];
      res.json({ 
        has_older: true,
        older_code: older.codigo_material_recibido,
        older_date: older.fecha_recibo ? new Date(older.fecha_recibo).toLocaleDateString() : '',
        older_qty: older.cantidad_actual
      });
    } else {
      res.json({ has_older: false });
    }
  } catch (err) {
    next(err);
  }
};

// GET /api/warehousing/:id - Obtener por ID
const getById = async (req, res, next) => {
  try {
    const [rows] = await pool.query(`
      SELECT cma.*, COALESCE(cma.ubicacion_destino, cma.ubicacion_salida) as location
      FROM control_material_almacen_smd cma
      WHERE cma.id = ?
    `, [req.params.id]);
    
    if (rows.length === 0) {
      return res.status(404).json({ error: 'Registro no encontrado' });
    }
    res.json(rows[0]);
  } catch (err) {
    next(err);
  }
};

// POST /api/warehousing - Crear entrada
const create = async (req, res, next) => {
  try {
    console.log('📥 POST /api/warehousing - Body recibido:', JSON.stringify(req.body, null, 2));
    const {
      forma_material,
      cliente,
      codigo_material_original,
      codigo_material,
      material_importacion_local,
      fecha_recibo,
      fecha_fabricacion,
      cantidad_actual,
      numero_lote_material,
      codigo_material_recibido,
      numero_parte,
      cantidad_estandarizada,
      codigo_material_final,
      propiedad_material,
      especificacion,
      material_importacion_local_final,
      estado_desecho,
      ubicacion_salida,
      ubicacion_destino,
      vendedor,
      iqc_required,
      usuario_registro,
      unidad_medida
    } = req.body;

    // ========================================
    // VERIFICAR SI EL LOTE ESTÁ EN BLACKLIST
    // ========================================
    let isBlacklisted = false;
    let blacklistReason = null;
    
    if (numero_lote_material) {
      const [blacklistCheck] = await pool.query(
        'SELECT * FROM blacklisted_lots WHERE lot_id = ?',
        [numero_lote_material]
      );
      
      if (blacklistCheck.length > 0) {
        isBlacklisted = true;
        blacklistReason = blacklistCheck[0].reason;
        console.log(`⚠️ BLACKLIST: Lote ${numero_lote_material} está en lista negra. Se enviará a IQC automáticamente.`);
      }
    }

    // Calcular receiving_lot_code y label_seq
    let receiving_lot_code = null;
    let label_seq = null;
    
    if (codigo_material_recibido && codigo_material_recibido.length >= 20) {
      receiving_lot_code = codigo_material_recibido.substring(0, 20);
      const seqPart = codigo_material_recibido.substring(20);
      label_seq = parseInt(seqPart, 10) || null;
    }

    // Si está en blacklist, forzar IQC
    const iqcRequired = isBlacklisted || iqc_required === 1 || iqc_required === true || iqc_required === '1';
    const iqc_status = iqcRequired ? 'Pending' : 'NotRequired';
    
    // Usar fecha/hora de MySQL (NOW()) para consistencia
    const [result] = await pool.query(`
      INSERT INTO control_material_almacen_smd (
        forma_material, cliente, codigo_material_original, codigo_material,
        material_importacion_local, fecha_recibo, fecha_fabricacion,
        cantidad_actual, numero_lote_material, codigo_material_recibido,
        numero_parte, cantidad_estandarizada, codigo_material_final,
        propiedad_material, especificacion, material_importacion_local_final,
        estado_desecho, ubicacion_salida, ubicacion_destino, vendedor, receiving_lot_code, label_seq,
        iqc_required, iqc_status, usuario_registro, fecha_registro, unidad_medida
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NOW(), ?)
    `, [
      forma_material, cliente, codigo_material_original, codigo_material,
      material_importacion_local, fecha_recibo, fecha_fabricacion,
      cantidad_actual, numero_lote_material, codigo_material_recibido,
      numero_parte, cantidad_estandarizada, codigo_material_final,
      propiedad_material, especificacion, material_importacion_local_final,
      estado_desecho || 0, ubicacion_salida, ubicacion_destino || '', vendedor || '', receiving_lot_code, label_seq,
      iqcRequired ? 1 : 0, iqc_status, usuario_registro, unidad_medida || 'EA'
    ]);

    // Si requiere IQC, crear registro en iqc_inspection_lot_smd
    let inspectionLotSequence = 1;
    if (iqcRequired && receiving_lot_code) {
      try {
        const [existingLot] = await pool.query(
          `SELECT id, status, COALESCE(lot_sequence, 1) as lot_sequence 
           FROM iqc_inspection_lot_smd 
           WHERE receiving_lot_code = ? 
           ORDER BY lot_sequence DESC 
           LIMIT 1`,
          [receiving_lot_code]
        );

        let needsNewLot = false;
        let newLotSequence = 1;

        if (existingLot.length === 0) {
          needsNewLot = true;
          newLotSequence = 1;
        } else if (existingLot[0].status === 'Closed') {
          needsNewLot = true;
          newLotSequence = existingLot[0].lot_sequence + 1;
        } else {
          inspectionLotSequence = existingLot[0].lot_sequence;
          await pool.query(`
            UPDATE iqc_inspection_lot_smd 
            SET total_qty_received = total_qty_received + ?,
                total_labels = total_labels + 1
            WHERE id = ?
          `, [cantidad_actual || 0, existingLot[0].id]);
        }

        if (needsNewLot) {
          // Buscar config IQC por part number exacto o base (sin versión)
          const config = await findMaterialConfig(
            pool, 
            numero_parte, 
            'rohs_enabled, brightness_enabled, dimension_enabled, color_enabled, appearance_enabled'
          ) || {};
          
          const rohsResult = config.rohs_enabled ? 'Pending' : 'NA';
          const brightnessResult = config.brightness_enabled ? 'Pending' : 'NA';
          const dimensionResult = config.dimension_enabled ? 'Pending' : 'NA';
          const colorResult = config.color_enabled ? 'Pending' : 'NA';
          const appearanceResult = config.appearance_enabled ? 'Pending' : 'NA';
          
          await pool.query(`
            INSERT INTO iqc_inspection_lot_smd (
              receiving_lot_code, material_code, part_number, customer,
              arrival_date, total_qty_received, total_labels, status, lot_sequence,
              rohs_result, brightness_result, dimension_result, color_result, appearance_result
            ) VALUES (?, ?, ?, ?, ?, ?, 1, 'Pending', ?, ?, ?, ?, ?, ?)
          `, [
            receiving_lot_code, codigo_material, numero_parte, cliente,
            fecha_recibo ? fecha_recibo.split('T')[0] : new Date().toISOString().split('T')[0],
            cantidad_actual || 0, newLotSequence,
            rohsResult, brightnessResult, dimensionResult, colorResult, appearanceResult
          ]);
          
          inspectionLotSequence = newLotSequence;
        }

        await pool.query(`
          UPDATE control_material_almacen_smd 
          SET inspection_lot_sequence = ? 
          WHERE id = ?
        `, [inspectionLotSequence, result.insertId]);

      } catch (iqcErr) {
        console.log('Nota: Error al crear registro IQC:', iqcErr.message);
      }
    }

    res.status(201).json({
      id: result.insertId,
      message: isBlacklisted 
        ? `Registro creado. ALERTA: El lote ${numero_lote_material} está en lista negra y fue enviado a inspección IQC automáticamente.`
        : 'Registro creado exitosamente',
      receiving_lot_code,
      iqc_status,
      blacklisted: isBlacklisted,
      blacklist_reason: blacklistReason
    });
  } catch (err) {
    console.error('❌ Error en POST /api/warehousing:', err.message);
    console.error('   SQL Error Code:', err.code);
    console.error('   SQL State:', err.sqlState);
    next(err);
  }
};

// PUT /api/warehousing/:id - Actualizar
const update = async (req, res, next) => {
  try {
    const { id } = req.params;
    const fields = req.body;
    
    delete fields.id;
    delete fields.fecha_registro;
    
    if (Object.keys(fields).length === 0) {
      return res.status(400).json({ error: 'No hay campos para actualizar' });
    }

    const setClause = Object.keys(fields).map(key => `${key} = ?`).join(', ');
    const values = [...Object.values(fields), id];

    const [result] = await pool.query(
      `UPDATE control_material_almacen_smd SET ${setClause} WHERE id = ?`,
      values
    );

    if (result.affectedRows === 0) {
      return res.status(404).json({ error: 'Registro no encontrado' });
    }

    res.json({ message: 'Registro actualizado exitosamente' });
  } catch (err) {
    next(err);
  }
};

// PUT /api/warehousing/bulk-update - Actualizar múltiples registros
const bulkUpdate = async (req, res, next) => {
  const connection = await pool.getConnection();
  try {
    const { ids, fields } = req.body;
    
    if (!ids || !Array.isArray(ids) || ids.length === 0) {
      return res.status(400).json({ error: 'Se requiere al menos un ID' });
    }
    
    if (!fields || Object.keys(fields).length === 0) {
      return res.status(400).json({ error: 'No hay campos para actualizar' });
    }
    
    // Campos permitidos para actualización masiva
    const allowedFields = ['numero_lote_material', 'ubicacion_salida', 'cantidad_actual', 'cancelado'];
    const filteredFields = {};
    
    for (const key of Object.keys(fields)) {
      if (allowedFields.includes(key) && fields[key] !== null && fields[key] !== undefined) {
        filteredFields[key] = fields[key];
      }
    }
    
    if (Object.keys(filteredFields).length === 0) {
      return res.status(400).json({ error: 'No hay campos válidos para actualizar' });
    }
    
    await connection.beginTransaction();
    
    const setClause = Object.keys(filteredFields).map(key => `${key} = ?`).join(', ');
    const values = Object.values(filteredFields);
    
    let successCount = 0;
    let errorCount = 0;
    const errors = [];
    
    for (const id of ids) {
      try {
        const [result] = await connection.query(
          `UPDATE control_material_almacen_smd SET ${setClause} WHERE id = ?`,
          [...values, id]
        );
        if (result.affectedRows > 0) {
          successCount++;
        } else {
          errorCount++;
          errors.push({ id, error: 'Registro no encontrado' });
        }
      } catch (err) {
        errorCount++;
        errors.push({ id, error: err.message });
      }
    }
    
    await connection.commit();
    
    res.json({
      success: true,
      message: `Actualización completada: ${successCount} exitosos, ${errorCount} errores`,
      successCount,
      errorCount,
      errors: errors.length > 0 ? errors : undefined
    });
  } catch (err) {
    await connection.rollback();
    next(err);
  } finally {
    connection.release();
  }
};

// DELETE /api/warehousing/:id - Marcar como cancelado (no elimina, mantiene historial)
const deleteEntry = async (req, res, next) => {
  try {
    const [result] = await pool.query(
      'UPDATE control_material_almacen_smd SET cancelado = 1 WHERE id = ?',
      [req.params.id]
    );

    if (result.affectedRows === 0) {
      return res.status(404).json({ error: 'Registro no encontrado' });
    }

    res.json({ message: 'Registro marcado como cancelado' });
  } catch (err) {
    next(err);
  }
};

// GET /api/warehousing/count-iqc-pending - Contar materiales pendientes de IQC
const countIqcPending = async (req, res, next) => {
  try {
    const [rows] = await pool.query(`
      SELECT COUNT(*) as count 
      FROM control_material_almacen_smd 
      WHERE iqc_required = 1 AND iqc_status = 'Pending'
    `);
    res.json({ count: rows[0].count });
  } catch (err) {
    next(err);
  }
};

// POST /api/warehousing/bulk-import - Importación masiva desde CSV
const bulkImport = async (req, res, next) => {
  const connection = await pool.getConnection();
  
  try {
    const { entries, usuario_registro } = req.body;
    
    if (!entries || !Array.isArray(entries) || entries.length === 0) {
      return res.status(400).json({ error: 'Se requiere un array de entradas' });
    }

    const CHUNK_SIZE = 500;
    const results = {
      total: entries.length,
      success: 0,
      failed: 0,
      errors: []
    };

    // Procesar en chunks
    for (let i = 0; i < entries.length; i += CHUNK_SIZE) {
      const chunk = entries.slice(i, i + CHUNK_SIZE);
      const chunkNumber = Math.floor(i / CHUNK_SIZE) + 1;
      
      try {
        await connection.beginTransaction();
        
        const validRows = [];
        // Obtener hora de MySQL para consistencia
        const [[{ now }]] = await connection.query('SELECT NOW() as now');
        
        for (let j = 0; j < chunk.length; j++) {
          const entry = chunk[j];
          const rowIndex = i + j + 1; // 1-based row number for error reporting
          
          // Validar campos requeridos
          const requiredFields = ['codigo_material_recibido', 'numero_parte', 'cantidad_actual', 'fecha_recibo', 'ubicacion_salida', 'especificacion'];
          const missingFields = requiredFields.filter(field => !entry[field] && entry[field] !== 0);
          
          if (missingFields.length > 0) {
            results.errors.push({
              row: rowIndex,
              codigo: entry.codigo_material_recibido || 'N/A',
              error: `Campos requeridos faltantes: ${missingFields.join(', ')}`
            });
            results.failed++;
            continue;
          }
          
          // Calcular campos derivados
          const codigo = entry.codigo_material_recibido;
          const receivingLotCode = codigo.substring(0, 20);
          const labelSeq = parseInt(codigo.slice(-4)) || 0;
          
          // Preparar valores (orden debe coincidir con columnas del INSERT)
          validRows.push([
            codigo,                                           // codigo_material_recibido
            receivingLotCode,                                 // receiving_lot_code
            labelSeq,                                         // label_seq
            entry.numero_parte,                               // numero_parte
            entry.numero_parte,                               // codigo_material (copia de numero_parte)
            entry.numero_parte,                               // codigo_material_original
            entry.numero_lote_material || 'N/A',              // numero_lote_material (trigger requiere NOT NULL)
            entry.cantidad_actual,                            // cantidad_actual
            entry.unidad_empaque || 'EA',                     // cantidad_estandarizada (unidad de empaque)
            entry.especificacion,                             // especificacion
            entry.fecha_recibo,                               // fecha_recibo
            entry.fecha_fabricacion || null,                  // fecha_fabricacion (opcional)
            entry.ubicacion_salida,                           // ubicacion_salida
            'LGEMN',                                          // cliente
            'Customer Supply',                                // propiedad_material
            entry.material_importacion_local || 'Local',      // material_importacion_local
            'OriginCode',                                     // forma_material
            0,                                                // estado_desecho
            0,                                                // cancelado
            0,                                                // tiene_salida
            0,                                                // iqc_required
            'NotRequired',                                    // iqc_status
            usuario_registro || 'bulk_import',                // usuario_registro
            now,                                              // fecha_registro
            'EA'                                              // unidad_medida
          ]);
        }
        
        // Insertar filas válidas en bulk
        if (validRows.length > 0) {
          const insertQuery = `
            INSERT INTO control_material_almacen_smd (
              codigo_material_recibido,
              receiving_lot_code,
              label_seq,
              numero_parte,
              codigo_material,
              codigo_material_original,
              numero_lote_material,
              cantidad_actual,
              cantidad_estandarizada,
              especificacion,
              fecha_recibo,
              fecha_fabricacion,
              ubicacion_salida,
              cliente,
              propiedad_material,
              material_importacion_local,
              forma_material,
              estado_desecho,
              cancelado,
              tiene_salida,
              iqc_required,
              iqc_status,
              usuario_registro,
              fecha_registro,
              unidad_medida
            ) VALUES ?
          `;
          
          await connection.query(insertQuery, [validRows]);
          results.success += validRows.length;
        }
        
        await connection.commit();
        console.log(`Bulk import chunk ${chunkNumber}: ${validRows.length} éxitos, ${chunk.length - validRows.length} errores`);
        
      } catch (chunkErr) {
        await connection.rollback();
        // Marcar todo el chunk como fallido
        for (let j = 0; j < chunk.length; j++) {
          const entry = chunk[j];
          const rowIndex = i + j + 1;
          results.errors.push({
            row: rowIndex,
            codigo: entry.codigo_material_recibido || 'N/A',
            error: `Error en chunk: ${chunkErr.message}`
          });
        }
        results.failed += chunk.length;
        console.error(`Bulk import chunk ${chunkNumber} failed:`, chunkErr.message);
      }
    }
    
    res.json({
      success: true,
      message: `Importación completada: ${results.success} éxitos, ${results.failed} errores`,
      results
    });
    
  } catch (err) {
    await connection.rollback();
    next(err);
  } finally {
    connection.release();
  }
};

// Crear entrada en almacen_smd copiando datos de control_material_almacen
async function insertAlmacenSmdIfMissing(connection, source, usuarioRegistro, fechaRegistro, ubicacionDestino = null) {
  const [exists] = await connection.query(`
    SELECT id FROM control_material_almacen_smd
    WHERE codigo_material_recibido = ?
    LIMIT 1
  `, [source.codigo_material_recibido]);

  if (exists.length > 0) return false;

  // Los datos vienen de control_material_almacen (source)
  await connection.query(`
    INSERT INTO control_material_almacen_smd (
      forma_material,
      cliente,
      codigo_material_original,
      codigo_material,
      material_importacion_local,
      fecha_recibo,
      fecha_fabricacion,
      cantidad_actual,
      numero_lote_material,
      codigo_material_recibido,
      numero_parte,
      cantidad_estandarizada,
      codigo_material_final,
      propiedad_material,
      especificacion,
      material_importacion_local_final,
      estado_desecho,
      ubicacion_salida,
      ubicacion_destino,
      vendedor,
      usuario_registro,
      fecha_registro,
      unidad_medida,
      receiving_lot_code,
      label_seq,
      iqc_required,
      iqc_status,
      inspection_lot_sequence
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
  `, [
    source.forma_material || 'WarehouseOut',
    source.cliente || null,
    source.codigo_material_original || null,
    source.codigo_material || source.material_codigo || null,
    source.material_importacion_local || null,
    fechaRegistro,  // fecha_recibo = momento de entrada en SMD
    source.fecha_fabricacion || null,
    source.cantidad_actual || 0,
    source.numero_lote_material || 'N/A',
    source.codigo_material_recibido,
    source.numero_parte,
    source.cantidad_estandarizada || null,
    source.codigo_material_final || source.codigo_material || null,
    source.propiedad_material || 'SMD',
    source.especificacion || source.especificacion_material || source.material_especificacion || null,
    source.material_importacion_local_final || null,
    source.estado_desecho || 0,
    ubicacionDestino || source.ubicacion_salida || null,  // ubicacion_salida = destino ingresado
    ubicacionDestino || source.ubicacion_salida || null,  // ubicacion_destino = destino ingresado
    source.vendedor || source.material_vendedor || null,
    usuarioRegistro,
    fechaRegistro,  // fecha_registro = momento de entrada en SMD
    source.unidad_medida || 'EA',
    source.receiving_lot_code || null,
    source.label_seq || null,
    source.iqc_required || 0,
    source.iqc_status || 'NotRequired',
    source.inspection_lot_sequence || 1
  ]);

  return true;
}

// GET /api/warehousing/pending-from-warehouse - Salidas de almacén pendientes de confirmar (SMD)
function buildPendingWarehouseGroups(rows) {
  const groups = new Map();

  for (const row of rows) {
    const partNumber = row.numero_parte || '-';
    if (!groups.has(partNumber)) {
      groups.set(partNumber, {
        numero_parte: partNumber,
        total_qty: 0,
        count: 0,
        latest_date: row.fecha_salida || null,
        ubicacion_rollos: row.ubicacion_rollos || '',
        items: []
      });
    }

    const group = groups.get(partNumber);
    const qty = Number(row.cantidad_salida || 0);
    group.total_qty += Number.isFinite(qty) ? qty : 0;
    group.count += 1;
    if (row.fecha_salida && (!group.latest_date || row.fecha_salida > group.latest_date)) {
      group.latest_date = row.fecha_salida;
    }

    group.items.push({
      id: row.id,
      numero_parte: row.numero_parte,
      codigo_material_recibido: row.codigo_material_recibido,
      cantidad_salida: row.cantidad_salida,
      fecha_salida: row.fecha_salida,
      ubicacion_rollos: row.ubicacion_rollos || ''
    });
  }

  return Array.from(groups.values()).sort((a, b) =>
    String(b.latest_date || '').localeCompare(String(a.latest_date || ''))
  );
}

async function lookupWarehouseMaterial(codigo, { directEntry = false } = {}) {
  const normalizedCode = String(codigo || '').trim();
  if (!normalizedCode) {
    return { success: false, error: 'missing_code', message: 'Se requiere código' };
  }

  const [rows] = await pool.query(`
    SELECT 
      cma.*,
      m.especificacion_material,
      m.unidad_empaque,
      m.unidad_medida,
      m.ubicacion_material,
      m.ubicacion_rollos,
      m.vendedor as material_vendedor
    FROM control_material_almacen cma
    LEFT JOIN materiales m ON cma.numero_parte = m.numero_parte
    WHERE UPPER(cma.codigo_material_recibido) = UPPER(?)
    LIMIT 1
  `, [normalizedCode]);

  if (rows.length === 0) {
    return {
      success: false,
      error: 'material_not_found',
      message: 'Material no encontrado en almacén'
    };
  }

  const material = rows[0];

  if (!directEntry && material.tiene_salida !== 1) {
    return {
      success: false,
      error: 'no_warehouse_exit',
      message: 'Este material no tiene salida de almacén'
    };
  }

  if (material.cancelado === 1) {
    return {
      success: false,
      error: 'cancelled',
      message: 'Este material está cancelado'
    };
  }

  const [existsInSmd] = await pool.query(`
    SELECT id FROM control_material_almacen_smd
    WHERE codigo_material_recibido = ?
    LIMIT 1
  `, [material.codigo_material_recibido]);

  if (existsInSmd.length > 0) {
    return {
      success: false,
      error: 'already_in_smd',
      message: 'Este material ya existe en el almacén SMD'
    };
  }

  return {
    success: true,
    data: {
      id: material.id,
      codigo_material_recibido: material.codigo_material_recibido,
      numero_parte: material.numero_parte,
      codigo_material: material.codigo_material,
      codigo_material_original: material.codigo_material_original,
      especificacion: material.especificacion_material || material.especificacion,
      cantidad_actual: material.cantidad_actual,
      cantidad_estandarizada: material.cantidad_estandarizada,
      unidad_medida: material.unidad_medida || 'EA',
      numero_lote_material: material.numero_lote_material,
      ubicacion: material.ubicacion_material || material.ubicacion_salida,
      ubicacion_rollos: material.ubicacion_rollos || null,
      vendedor: material.material_vendedor || material.vendedor,
      fecha_recibo: material.fecha_recibo,
      fecha_fabricacion: material.fecha_fabricacion,
      cliente: material.cliente,
      forma_material: material.forma_material,
      propiedad_material: material.propiedad_material,
      material_importacion_local: material.material_importacion_local
    }
  };
}

const getPendingFromWarehouse = async (req, res, next) => {
  try {
    const { fechaInicio, fechaFin, compact, grouped } = req.query;
    
    // Usar fechas del query o valores por defecto
    let startDate = WAREHOUSE_OUTGOING_START_DATETIME;
    let endDate = null;
    
    if (fechaInicio) {
      startDate = `${fechaInicio} 00:00:00`;
    }
    if (fechaFin) {
      endDate = `${fechaFin} 23:59:59`;
    }
    
    let query = `
      SELECT 
        cms.*,
        m.codigo_material as material_codigo,
        m.propiedad_material,
        m.especificacion_material as material_especificacion,
        m.unidad_empaque,
        m.unidad_medida,
        m.ubicacion_material,
        m.ubicacion_rollos,
        m.vendedor as material_vendedor
      FROM control_material_salida cms
      LEFT JOIN materiales m ON cms.numero_parte = m.numero_parte
      WHERE (cms.confirmado = 0 OR cms.confirmado IS NULL)
        AND (cms.cancelado = 0 OR cms.cancelado IS NULL)
        AND (cms.rechazado = 0 OR cms.rechazado IS NULL)
        AND cms.fecha_salida >= ?
        ${endDate ? 'AND cms.fecha_salida <= ?' : ''}
        AND UPPER(COALESCE(m.propiedad_material, '')) = 'SMD'
      ORDER BY cms.fecha_salida DESC
    `;
    
    const params = endDate ? [startDate, endDate] : [startDate];
    const [rows] = await pool.query(query, params);

    const response = {
      start_date: fechaInicio || WAREHOUSE_OUTGOING_START_DATE,
      end_date: fechaFin || null,
      count: rows.length,
      data: rows
    };

    if ((compact === '1' || compact === 'true') && grouped === 'part') {
      response.groups = buildPendingWarehouseGroups(rows);
    }

    res.json(response);
  } catch (err) {
    next(err);
  }
};

// GET /api/warehousing/search-warehouse-material - Buscar material en control_material_almacen por código escaneado
const searchWarehouseMaterial = async (req, res, next) => {
  try {
    const { codigo, direct_entry } = req.query;
    const result = await lookupWarehouseMaterial(codigo, {
      directEntry: direct_entry === '1' || direct_entry === 'true'
    });
    return res.json(result);

    const isDirectEntry = direct_entry === '1' || direct_entry === 'true';
    
    if (!codigo) {
      return res.status(400).json({ success: false, error: 'Se requiere código' });
    }

    // Buscar en control_material_almacen por codigo_material_recibido
    const [rows] = await pool.query(`
      SELECT 
        cma.*,
        m.especificacion_material,
        m.unidad_empaque,
        m.unidad_medida,
        m.ubicacion_material,
        m.ubicacion_rollos,
        m.vendedor as material_vendedor
      FROM control_material_almacen cma
      LEFT JOIN materiales m ON cma.numero_parte = m.numero_parte
      WHERE UPPER(cma.codigo_material_recibido) = UPPER(?)
      LIMIT 1
    `, [codigo]);

    if (rows.length === 0) {
      return res.json({ 
        success: false, 
        error: 'material_not_found',
        message: 'Material no encontrado en almacén' 
      });
    }

    const material = rows[0];

    // Verificar si tiene salida de almacén (skip en modo entrada directa)
    if (!isDirectEntry && material.tiene_salida !== 1) {
      return res.json({ 
        success: false, 
        error: 'no_warehouse_exit',
        message: 'Este material no tiene salida de almacén' 
      });
    }

    // Verificar si está cancelado
    if (material.cancelado === 1) {
      return res.json({ 
        success: false, 
        error: 'cancelled',
        message: 'Este material está cancelado' 
      });
    }

    // Verificar si ya fue confirmado en SMD (ya existe en control_material_almacen_smd)
    const [existsInSmd] = await pool.query(`
      SELECT id FROM control_material_almacen_smd
      WHERE codigo_material_recibido = ?
      LIMIT 1
    `, [material.codigo_material_recibido]);

    if (existsInSmd.length > 0) {
      return res.json({
        success: false,
        error: 'already_in_smd',
        message: 'Este material ya existe en el almacén SMD'
      });
    }

    // Material válido, devolver datos para rellenar formulario
    res.json({
      success: true,
      data: {
        id: material.id,
        codigo_material_recibido: material.codigo_material_recibido,
        numero_parte: material.numero_parte,
        codigo_material: material.codigo_material,
        codigo_material_original: material.codigo_material_original,
        especificacion: material.especificacion_material || material.especificacion,
        cantidad_actual: material.cantidad_actual,
        cantidad_estandarizada: material.cantidad_estandarizada,
        unidad_medida: material.unidad_medida || 'EA',
        numero_lote_material: material.numero_lote_material,
        ubicacion: material.ubicacion_material || material.ubicacion_salida,
        ubicacion_rollos: material.ubicacion_rollos || null,
        vendedor: material.material_vendedor || material.vendedor,
        fecha_recibo: material.fecha_recibo,
        fecha_fabricacion: material.fecha_fabricacion,
        cliente: material.cliente,
        forma_material: material.forma_material,
        propiedad_material: material.propiedad_material,
        material_importacion_local: material.material_importacion_local
      }
    });
  } catch (err) {
    next(err);
  }
};

// POST /api/warehousing/search-warehouse-materials - Buscar multiples materiales para batching movil
const searchWarehouseMaterials = async (req, res, next) => {
  try {
    const codes = Array.isArray(req.body?.codes) ? req.body.codes : [];
    const isDirectEntry = req.body?.direct_entry === true || req.body?.direct_entry === '1';

    if (codes.length === 0) {
      return res.status(400).json({ success: false, error: 'Se requiere al menos un código' });
    }

    const uniqueCodes = [...new Set(
      codes.map((code) => String(code || '').trim()).filter(Boolean)
    )].slice(0, 20);

    const results = await Promise.all(uniqueCodes.map(async (code) => ({
      inputCode: code,
      ...await lookupWarehouseMaterial(code, { directEntry: isDirectEntry })
    })));

    res.json({
      success: true,
      results
    });
  } catch (err) {
    next(err);
  }
};

// GET /api/warehousing/rejected-from-warehouse - Historial de salidas rechazadas (SMD)
const getRejectedFromWarehouse = async (req, res, next) => {
  try {
    const [rows] = await pool.query(`
      SELECT 
        cms.*,
        m.codigo_material as material_codigo,
        m.propiedad_material,
        m.especificacion_material as material_especificacion,
        m.unidad_empaque,
        m.unidad_medida,
        m.ubicacion_material,
        m.vendedor as material_vendedor
      FROM control_material_salida cms
      LEFT JOIN materiales m ON cms.numero_parte = m.numero_parte
      WHERE cms.rechazado = 1
        AND cms.fecha_salida >= ?
        AND UPPER(COALESCE(m.propiedad_material, '')) = 'SMD'
      ORDER BY cms.rechazado_at DESC, cms.fecha_salida DESC
    `, [WAREHOUSE_OUTGOING_START_DATETIME]);

    res.json({
      start_date: WAREHOUSE_OUTGOING_START_DATE,
      count: rows.length,
      data: rows
    });
  } catch (err) {
    next(err);
  }
};
// POST /api/warehousing/confirm-from-warehouse - Confirmar salida de almacén como entrada SMD
const confirmFromWarehouse = async (req, res, next) => {
  const connection = await pool.getConnection();
  try {
    const { id, codigo_material_recibido, usuario, ubicacion_destino } = req.body;

    if (!id && !codigo_material_recibido) {
      return res.status(400).json({ error: 'Se requiere id o codigo_material_recibido' });
    }

    await connection.beginTransaction();

    let salida = null;
    let sourceTable = '';

    const isDirectEntry = req.body.direct_entry === true || req.body.direct_entry === '1';

    // Primero buscar en control_material_almacen
    if (codigo_material_recibido) {
      // En modo entrada directa, no exigir tiene_salida = 1
      const tieneSalidaFilter = isDirectEntry ? '' : 'AND cma.tiene_salida = 1';
      const [almacenRows] = await connection.query(`
        SELECT 
          cma.*,
          m.codigo_material as material_codigo,
          m.propiedad_material,
          m.especificacion_material as material_especificacion,
          m.unidad_empaque,
          m.unidad_medida,
          m.ubicacion_material,
          m.vendedor as material_vendedor
        FROM control_material_almacen cma
        LEFT JOIN materiales m ON cma.numero_parte = m.numero_parte
        WHERE UPPER(cma.codigo_material_recibido) = UPPER(?)
          ${tieneSalidaFilter}
          AND (cma.cancelado = 0 OR cma.cancelado IS NULL)
        LIMIT 1
      `, [codigo_material_recibido]);

      if (almacenRows.length > 0) {
        salida = almacenRows[0];
        sourceTable = 'control_material_almacen';
      }
    }

    // Si no encontrado en almacen, buscar en control_material_salida
    if (!salida) {
      const whereClause = id ? 'cms.id = ?' : 'cms.codigo_material_recibido = ?';
      const whereParam = id || codigo_material_recibido;

      const [rows] = await connection.query(`
        SELECT 
          cms.*,
          m.codigo_material as material_codigo,
          m.propiedad_material,
          m.especificacion_material as material_especificacion,
          m.unidad_empaque,
          m.unidad_medida,
          m.ubicacion_material,
          m.vendedor as material_vendedor
        FROM control_material_salida cms
        LEFT JOIN materiales m ON cms.numero_parte = m.numero_parte
        WHERE ${whereClause}
          AND (cms.cancelado = 0 OR cms.cancelado IS NULL)
          AND (cms.rechazado = 0 OR cms.rechazado IS NULL)
          AND cms.fecha_salida >= ?
        LIMIT 1
      `, [whereParam, WAREHOUSE_OUTGOING_START_DATETIME]);

      if (rows.length > 0) {
        salida = rows[0];
        sourceTable = 'control_material_salida';
      }
    }

    if (!salida) {
      await connection.rollback();
      return res.status(404).json({ error: 'Salida no encontrada o fuera de rango' });
    }

    // Verificar si ya fue confirmado (campo diferente según tabla de origen)
    const isAlreadyConfirmed = sourceTable === 'control_material_almacen'
      ? salida.confirmado_smd === 1
      : salida.confirmado === 1;

    if (isAlreadyConfirmed) {
      await connection.rollback();
      return res.json({ success: true, already_confirmed: true });
    }

    // Verificar que es SMD (solo para control_material_salida)
    if (sourceTable === 'control_material_salida' && String(salida.propiedad_material || '').toUpperCase() !== 'SMD') {
      await connection.rollback();
      return res.status(400).json({ error: 'El material no es SMD' });
    }

    // Obtener hora de MySQL para consistencia
    const [[{ now: fechaRegistro }]] = await connection.query('SELECT NOW() as now');
    const usuarioRegistro = usuario || salida.usuario_registro || 'Sistema';

    // Usar ubicacion_destino si se proporciona
    const ubicacionDestinoFinal = ubicacion_destino || null;

    const insertedAlmacen = await insertAlmacenSmdIfMissing(connection, salida, usuarioRegistro, fechaRegistro, ubicacionDestinoFinal);

    // Actualizar la tabla de origen
    if (sourceTable === 'control_material_salida') {
      await connection.query(`
        UPDATE control_material_salida
        SET confirmado = 1,
            confirmado_por = ?,
            confirmado_at = ?
        WHERE id = ?
      `, [usuarioRegistro, fechaRegistro, salida.id]);
    } else {
      // Para control_material_almacen, marcar como confirmado
      await connection.query(`
        UPDATE control_material_almacen
        SET confirmado_smd = 1,
            confirmado_smd_por = ?,
            confirmado_smd_at = ?
        WHERE id = ?
      `, [usuarioRegistro, fechaRegistro, salida.id]);
    }

    await connection.commit();
    res.json({
      success: true,
      codigo_material_recibido: salida.codigo_material_recibido,
      inserted_almacen: insertedAlmacen
    });
  } catch (err) {
    await connection.rollback();
    next(err);
  } finally {
    connection.release();
  }
};


// POST /api/warehousing/confirm-from-warehouse-by-part - Confirmar por numero de parte
const confirmFromWarehouseByPart = async (req, res, next) => {
  const connection = await pool.getConnection();
  try {
    const { numero_parte, usuario } = req.body;

    if (!numero_parte) {
      return res.status(400).json({ error: 'Se requiere numero_parte' });
    }

    await connection.beginTransaction();

    const [rows] = await connection.query(`
      SELECT 
        cms.*,
        m.codigo_material as material_codigo,
        m.propiedad_material,
        m.especificacion_material as material_especificacion,
        m.unidad_empaque,
        m.unidad_medida,
        m.ubicacion_material,
        m.vendedor as material_vendedor
      FROM control_material_salida cms
      LEFT JOIN materiales m ON cms.numero_parte = m.numero_parte
      WHERE cms.numero_parte = ?
        AND (cms.confirmado = 0 OR cms.confirmado IS NULL)
        AND (cms.cancelado = 0 OR cms.cancelado IS NULL)
        AND (cms.rechazado = 0 OR cms.rechazado IS NULL)
        AND cms.fecha_salida >= ?
        AND UPPER(COALESCE(m.propiedad_material, '')) = 'SMD'
      ORDER BY cms.fecha_salida ASC
    `, [numero_parte, WAREHOUSE_OUTGOING_START_DATETIME]);

    if (rows.length === 0) {
      await connection.rollback();
      return res.status(404).json({ error: 'No hay salidas pendientes para este numero de parte' });
    }

    // Obtener hora de MySQL para consistencia
    const [[{ now: fechaRegistro }]] = await connection.query('SELECT NOW() as now');
    const usuarioRegistro = usuario || 'Sistema';
    let confirmed = 0;
    let skipped = 0;

    for (const salida of rows) {
      const insertedAlmacen = await insertAlmacenSmdIfMissing(connection, salida, usuarioRegistro, fechaRegistro);

      await connection.query(`
        UPDATE control_material_salida
        SET confirmado = 1,
            confirmado_por = ?,
            confirmado_at = ?
        WHERE id = ?
      `, [usuarioRegistro, fechaRegistro, salida.id]);

      if (insertedAlmacen) {
        confirmed++;
      } else {
        skipped++;
      }
    }

    await connection.commit();
    res.json({
      success: true,
      numero_parte,
      total: rows.length,
      confirmed,
      skipped
    });
  } catch (err) {
    await connection.rollback();
    next(err);
  } finally {
    connection.release();
  }
};

// POST /api/warehousing/confirm-from-warehouse-by-ids - Confirmar por ids seleccionados
const confirmFromWarehouseByIds = async (req, res, next) => {
  const connection = await pool.getConnection();
  try {
    const { ids, usuario, ubicacion_destino, ubicaciones_por_id } = req.body;

    if (!Array.isArray(ids) || ids.length === 0) {
      return res.status(400).json({ error: 'Se requiere lista de ids' });
    }

    // Validar que haya ubicaciones (ya sea una global o por cada id)
    const tieneUbicacionGlobal = ubicacion_destino && ubicacion_destino.trim() !== '';
    const tieneUbicacionesPorId = ubicaciones_por_id && typeof ubicaciones_por_id === 'object' && Object.keys(ubicaciones_por_id).length > 0;
    
    if (!tieneUbicacionGlobal && !tieneUbicacionesPorId) {
      return res.status(400).json({ error: 'Se requiere ubicación destino' });
    }

    const cleanIds = ids
      .map((id) => parseInt(id, 10))
      .filter((id) => Number.isFinite(id) && id > 0);

    if (cleanIds.length === 0) {
      return res.status(400).json({ error: 'Lista de ids invalida' });
    }

    await connection.beginTransaction();

    const placeholders = cleanIds.map(() => '?').join(', ');
    
    // Log para debug: contar cuántos IDs se recibieron vs cuántos pasan el filtro
    console.log(`[confirmFromWarehouseByIds] IDs recibidos: ${cleanIds.length}`);
    
    const [rows] = await connection.query(`
      SELECT 
        cms.*,
        m.codigo_material as material_codigo,
        m.propiedad_material,
        m.especificacion_material as material_especificacion,
        m.unidad_empaque,
        m.unidad_medida,
        m.ubicacion_material,
        m.vendedor as material_vendedor
      FROM control_material_salida cms
      LEFT JOIN materiales m ON cms.numero_parte = m.numero_parte
      WHERE cms.id IN (${placeholders})
        AND (cms.confirmado = 0 OR cms.confirmado IS NULL)
        AND (cms.cancelado = 0 OR cms.cancelado IS NULL)
        AND (cms.rechazado = 0 OR cms.rechazado IS NULL)
        AND cms.fecha_salida >= ?
        AND UPPER(COALESCE(m.propiedad_material, '')) = 'SMD'
      ORDER BY cms.fecha_salida ASC
    `, [...cleanIds, WAREHOUSE_OUTGOING_START_DATETIME]);

    console.log(`[confirmFromWarehouseByIds] Registros que pasan filtro: ${rows.length}`);

    if (rows.length === 0) {
      await connection.rollback();
      return res.status(404).json({ error: 'No hay salidas pendientes para los ids seleccionados' });
    }

    // Obtener hora de MySQL para consistencia
    const [[{ now: fechaRegistro }]] = await connection.query('SELECT NOW() as now');
    const usuarioRegistro = usuario || 'Sistema';
    let confirmed = 0;
    let skipped = 0;

    // ========== BATCH PROCESSING ==========
    
    // 1. Obtener todos los codigo_material_recibido que ya existen en almacén
    const codigosRecibidos = rows.map(r => r.codigo_material_recibido);
    const [existentes] = await connection.query(`
      SELECT codigo_material_recibido FROM control_material_almacen_smd
      WHERE codigo_material_recibido IN (?)
    `, [codigosRecibidos]);
    const codigosExistentes = new Set(existentes.map(e => e.codigo_material_recibido));
    
    // 2. Preparar datos para INSERT batch (solo los que no existen)
    const insertValues = [];
    const idsToConfirm = [];
    
    for (const salida of rows) {
      // Obtener ubicación
      let ubicacionFinal = ubicacion_destino ? ubicacion_destino.trim() : '';
      if (tieneUbicacionesPorId && ubicaciones_por_id[salida.id.toString()]) {
        ubicacionFinal = ubicaciones_por_id[salida.id.toString()].trim();
      }
      
      if (!ubicacionFinal) {
        skipped++;
        continue;
      }
      
      idsToConfirm.push(salida.id);
      
      // Solo agregar al batch si no existe
      if (!codigosExistentes.has(salida.codigo_material_recibido)) {
        const codigoMaterial = salida.material_codigo || null;
        const especificacion = salida.especificacion_material || salida.material_especificacion || null;
        
        insertValues.push([
          'WarehouseOut',
          null,
          null,
          codigoMaterial,
          null,
          fechaRegistro,  // fecha_recibo = fecha actual de confirmación
          fechaRegistro,  // fecha_fabricacion = fecha actual de confirmación
          salida.cantidad_salida || 0,
          salida.numero_lote,
          salida.codigo_material_recibido,
          salida.numero_parte,
          salida.unidad_empaque || null,
          codigoMaterial,
          salida.propiedad_material || null,
          especificacion,
          null,
          0,
          salida.ubicacion_material || null,
          ubicacionFinal,
          salida.vendedor || salida.material_vendedor || null,
          usuarioRegistro,
          fechaRegistro,
          salida.unidad_medida || 'EA'
        ]);
      } else {
        skipped++;
      }
    }
    
    // 3. INSERT batch de almacén
    if (insertValues.length > 0) {
      await connection.query(`
        INSERT INTO control_material_almacen_smd (
          forma_material, cliente, codigo_material_original, codigo_material,
          material_importacion_local, fecha_recibo, fecha_fabricacion, cantidad_actual,
          numero_lote_material, codigo_material_recibido, numero_parte, cantidad_estandarizada,
          codigo_material_final, propiedad_material, especificacion, material_importacion_local_final,
          estado_desecho, ubicacion_salida, ubicacion_destino, vendedor,
          usuario_registro, fecha_registro, unidad_medida
        ) VALUES ?
      `, [insertValues]);
      confirmed = insertValues.length;
    }
    
    // 4. UPDATE batch de confirmación
    if (idsToConfirm.length > 0) {
      await connection.query(`
        UPDATE control_material_salida
        SET confirmado = 1,
            confirmado_por = ?,
            confirmado_at = ?
        WHERE id IN (?)
      `, [usuarioRegistro, fechaRegistro, idsToConfirm]);
    }
    
    // ========== END BATCH PROCESSING ==========

    await connection.commit();
    
    const filtered = cleanIds.length - rows.length;
    console.log(`[confirmFromWarehouseByIds] Confirmados: ${confirmed}, Skipped (duplicados): ${skipped}, Filtrados: ${filtered}`);
    
    res.json({
      success: true,
      requested: cleanIds.length,
      filtered: filtered,
      total: rows.length,
      confirmed,
      skipped,
      note: skipped > 0 ? `${skipped} ya existían en almacén` : null
    });
  } catch (err) {
    await connection.rollback();
    next(err);
  } finally {
    connection.release();
  }
};



// POST /api/warehousing/reject-from-warehouse-by-part - Rechazar por numero de parte
const rejectFromWarehouseByPart = async (req, res, next) => {
  const connection = await pool.getConnection();
  try {
    const { numero_parte, usuario, motivo } = req.body;

    if (!numero_parte) {
      return res.status(400).json({ error: 'Se requiere numero_parte' });
    }
    if (!motivo || motivo.trim() === '') {
      return res.status(400).json({ error: 'Se requiere motivo' });
    }

    await connection.beginTransaction();

    const [rows] = await connection.query(`
      SELECT 
        cms.id
      FROM control_material_salida cms
      LEFT JOIN materiales m ON cms.numero_parte = m.numero_parte
      WHERE cms.numero_parte = ?
        AND (cms.confirmado = 0 OR cms.confirmado IS NULL)
        AND (cms.cancelado = 0 OR cms.cancelado IS NULL)
        AND (cms.rechazado = 0 OR cms.rechazado IS NULL)
        AND cms.fecha_salida >= ?
        AND UPPER(COALESCE(m.propiedad_material, '')) = 'SMD'
      ORDER BY cms.fecha_salida ASC
    `, [numero_parte, WAREHOUSE_OUTGOING_START_DATETIME]);

    if (rows.length === 0) {
      await connection.rollback();
      return res.status(404).json({ error: 'No hay salidas pendientes para este numero de parte' });
    }

    // Obtener hora de MySQL para consistencia
    const [[{ now: fechaRegistro }]] = await connection.query('SELECT NOW() as now');
    const usuarioRegistro = usuario || 'Sistema';

    const [update] = await connection.query(`
      UPDATE control_material_salida cms
      LEFT JOIN materiales m ON cms.numero_parte = m.numero_parte
      SET cms.rechazado = 1,
          cms.rechazado_por = ?,
          cms.rechazado_at = ?,
          cms.rechazado_motivo = ?
      WHERE cms.numero_parte = ?
        AND (cms.confirmado = 0 OR cms.confirmado IS NULL)
        AND (cms.cancelado = 0 OR cms.cancelado IS NULL)
        AND (cms.rechazado = 0 OR cms.rechazado IS NULL)
        AND cms.fecha_salida >= ?
        AND UPPER(COALESCE(m.propiedad_material, '')) = 'SMD'
    `, [usuarioRegistro, fechaRegistro, motivo.trim(), numero_parte, WAREHOUSE_OUTGOING_START_DATETIME]);

    await connection.commit();
    res.json({
      success: true,
      numero_parte,
      rejected: update.affectedRows
    });
  } catch (err) {
    await connection.rollback();
    next(err);
  } finally {
    connection.release();
  }
};

// POST /api/warehousing/reject-from-warehouse-by-ids - Rechazar por ids seleccionados
const rejectFromWarehouseByIds = async (req, res, next) => {
  const connection = await pool.getConnection();
  try {
    const { ids, usuario, motivo } = req.body;

    if (!Array.isArray(ids) || ids.length === 0) {
      return res.status(400).json({ error: 'Se requiere lista de ids' });
    }
    if (!motivo || motivo.trim() === '') {
      return res.status(400).json({ error: 'Se requiere motivo' });
    }

    const cleanIds = ids
      .map((id) => parseInt(id, 10))
      .filter((id) => Number.isFinite(id) && id > 0);

    if (cleanIds.length === 0) {
      return res.status(400).json({ error: 'Lista de ids invalida' });
    }

    await connection.beginTransaction();

    const placeholders = cleanIds.map(() => '?').join(', ');
    // Obtener hora de MySQL para consistencia
    const [[{ now: rechazadoAt }]] = await connection.query('SELECT NOW() as now');
    const [update] = await connection.query(`
      UPDATE control_material_salida cms
      LEFT JOIN materiales m ON cms.numero_parte = m.numero_parte
      SET cms.rechazado = 1,
          cms.rechazado_por = ?,
          cms.rechazado_at = ?,
          cms.rechazado_motivo = ?
      WHERE cms.id IN (${placeholders})
        AND (cms.confirmado = 0 OR cms.confirmado IS NULL)
        AND (cms.cancelado = 0 OR cms.cancelado IS NULL)
        AND (cms.rechazado = 0 OR cms.rechazado IS NULL)
        AND cms.fecha_salida >= ?
        AND UPPER(COALESCE(m.propiedad_material, '')) = 'SMD'
    `, [usuario || 'Sistema', rechazadoAt, motivo.trim(), ...cleanIds, WAREHOUSE_OUTGOING_START_DATETIME]);

    await connection.commit();
    res.json({
      success: true,
      rejected: update.affectedRows
    });
  } catch (err) {
    await connection.rollback();
    next(err);
  } finally {
    connection.release();
  }
};

// POST /api/warehousing/verify-direct-entry-password
const verifyDirectEntryPassword = async (req, res) => {
  const { password } = req.body;
  const correctPassword = process.env.DIRECT_ENTRY_PASSWORD || 'smd2026';
  
  if (password === correctPassword) {
    return res.json({ success: true });
  }
  return res.status(401).json({ success: false, error: 'Contraseña incorrecta' });
};

module.exports = {
  getAll,
  search,
  getByCode,
  smartSearch,
  getNextSequence,
  getNextSequencePreview,
  getNextInternalLotSequence,
  reserveSequences,
  fifoCheck,
  getById,
  create,
  update,
  bulkUpdate,
  delete: deleteEntry,
  countIqcPending,
  bulkImport,
  getPendingFromWarehouse,
  getRejectedFromWarehouse,
  searchWarehouseMaterial,
  searchWarehouseMaterials,
  confirmFromWarehouse,
  confirmFromWarehouseByPart,
  confirmFromWarehouseByIds,
  rejectFromWarehouseByPart,
  rejectFromWarehouseByIds,
  verifyDirectEntryPassword
};

