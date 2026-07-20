/**
 * Controlador para Outgoing (Salida de Material)
 * Corresponde a: screens/material_outgoing/
 */
const { pool } = require('../config/database');

function normalizeCode(value) {
  return String(value || '').trim().toUpperCase();
}

function outgoingError(message, code, statusCode = 409) {
  const error = new Error(message);
  error.code = code;
  error.statusCode = statusCode;
  return error;
}

async function lockAndValidateOutgoingStock(connection, {
  codigoMaterial,
  cantidad
}) {
  const isMissingQuantity = cantidad === null
    || cantidad === undefined
    || (typeof cantidad === 'string' && cantidad.trim() === '');
  const outgoingQty = Number(cantidad);

  if (isMissingQuantity || !Number.isFinite(outgoingQty) || outgoingQty < 0) {
    throw outgoingError(
      'La cantidad de salida debe ser un número mayor o igual a cero',
      'INVALID_OUTGOING_QUANTITY',
      400
    );
  }

  const [lotRows] = await connection.query(`
    SELECT id, total_entrada, total_salida, stock_actual
    FROM inventario_lotes_smd
    WHERE codigo_material_recibido = ?
    FOR UPDATE
  `, [codigoMaterial]);

  if (lotRows.length === 0) {
    throw outgoingError(
      'El lote no existe en el inventario disponible',
      'INVENTORY_LOT_NOT_FOUND',
      409
    );
  }

  const availableQty = Number(lotRows[0].stock_actual || 0);
  if (outgoingQty > availableQty) {
    throw outgoingError(
      `Stock insuficiente. Disponible: ${availableQty}; solicitado: ${outgoingQty}`,
      'INSUFFICIENT_STOCK',
      409
    );
  }

  return { outgoingQty, availableQty, inventoryLotId: lotRows[0].id };
}

async function validateOutgoingCodes(codes) {
  const normalizedCodes = [...new Set(codes.map(normalizeCode).filter(Boolean))];
  if (normalizedCodes.length === 0) {
    return [];
  }

  const placeholders = normalizedCodes.map(() => '?').join(', ');
  const [rows] = await pool.query(`
    SELECT
      c.id,
      c.codigo_material_recibido,
      c.numero_parte,
      c.numero_lote_material,
      c.cantidad_actual,
      c.especificacion,
      c.ubicacion_salida,
      c.tiene_salida,
      c.cancelado,
      COALESCE(m.standard_pack, 0) as standard_pack
    FROM control_material_almacen_smd c
    LEFT JOIN materiales m ON c.numero_parte = m.numero_parte
    WHERE c.codigo_material_recibido IN (${placeholders})
  `, normalizedCodes);

  const materialMap = new Map(
    rows.map((row) => [normalizeCode(row.codigo_material_recibido), row])
  );

  const lotIds = rows
    .map((row) => row.numero_lote_material)
    .filter((lotId) => lotId !== null && lotId !== undefined && lotId !== '');

  let blacklistMap = new Map();
  if (lotIds.length > 0) {
    const [blacklistRows] = await pool.query(
      'SELECT lot_id, reason FROM blacklisted_lots WHERE lot_id IN (?)',
      [lotIds]
    );

    blacklistMap = new Map(
      blacklistRows.map((row) => [
        row.lot_id,
        row.reason || 'Sin razón especificada'
      ])
    );
  }

  return normalizedCodes.map((code) => {
    const material = materialMap.get(code);
    if (!material) {
      return {
        inputCode: code,
        valid: false,
        error: 'Material no encontrado',
        code: 'NOT_FOUND'
      };
    }

    if (material.cancelado === 1) {
      return {
        inputCode: code,
        valid: false,
        error: 'Material cancelado',
        code: 'CANCELLED'
      };
    }

    if (material.tiene_salida === 1) {
      return {
        inputCode: code,
        valid: false,
        error: 'Ya tiene salida registrada',
        code: 'ALREADY_HAS_OUTGOING'
      };
    }

    if (material.numero_lote_material && blacklistMap.has(material.numero_lote_material)) {
      return {
        inputCode: code,
        valid: false,
        error: `El lote ${material.numero_lote_material} está en lista negra. Razón: ${blacklistMap.get(material.numero_lote_material)}`,
        code: 'LOT_BLACKLISTED'
      };
    }

    return {
      inputCode: code,
      valid: true,
      material: {
        codigo_material_recibido: material.codigo_material_recibido,
        numero_parte: material.numero_parte,
        numero_lote: material.numero_lote_material,
        cantidad: material.cantidad_actual,
        especificacion: material.especificacion,
        ubicacion: material.ubicacion_salida,
        standard_pack: material.standard_pack || 0
      }
    };
  });
}

// GET /api/outgoing/check-salida/:code - Verificar si tiene salida
const checkSalida = async (req, res, next) => {
  try {
    const { code: rawCode } = req.params;
    const code = (rawCode || '').trim().toUpperCase();
    
    const [rows] = await pool.query(`
      SELECT tiene_salida 
      FROM control_material_almacen_smd 
      WHERE codigo_material_recibido = ?
      LIMIT 1
    `, [code]);

    if (rows.length === 0) {
      return res.status(404).json({ error: 'Material no encontrado', has_outgoing: false });
    }

    const tieneSalida = rows[0].tiene_salida === 1;
    res.json({ 
      has_outgoing: tieneSalida,
      code: code
    });
  } catch (err) {
    next(err);
  }
};

// POST /api/outgoing/validate-batch - Validar múltiples códigos para salida en lote
const validateBatch = async (req, res, next) => {
  try {
    const requestedCodes = Array.isArray(req.body?.codes)
      ? req.body.codes
      : req.body?.code
          ? [req.body.code]
          : [];

    if (requestedCodes.length === 0) {
      return res.status(400).json({
        valid: false,
        error: 'Código requerido',
        code: 'MISSING_CODE'
      });
    }

    const results = await validateOutgoingCodes(requestedCodes);

    if (Array.isArray(req.body?.codes)) {
      return res.json({
        success: true,
        results
      });
    }

    const [result] = results;
    if (!result || result.valid !== true) {
      return res.json({
        valid: false,
        error: result?.error || 'Material no encontrado',
        code: result?.code || 'NOT_FOUND'
      });
    }

    return res.json({
      valid: true,
      material: result.material
    });
  } catch (err) {
    next(err);
  }
};

// POST /api/outgoing/batch - Crear salidas en lote (transacción)
const createBatch = async (req, res, next) => {
  const connection = await pool.getConnection();
  
  try {
    const { materials, usuario_registro } = req.body;
    
    if (!materials || !Array.isArray(materials) || materials.length === 0) {
      return res.status(400).json({ 
        success: false, 
        error: 'Se requiere un array de materiales',
        processed: 0,
        failed: 0
      });
    }

    if (materials.length > 100) {
      return res.status(400).json({ 
        success: false, 
        error: 'Máximo 100 materiales por lote',
        processed: 0,
        failed: 0
      });
    }

    await connection.beginTransaction();

    const results = {
      success: [],
      failed: []
    };

    // Obtener hora de MySQL para consistencia
    const [[{ now: fechaSalida }]] = await connection.query('SELECT NOW() as now');

    for (const material of materials) {
      const code = (material.codigo_material_recibido || '').trim().toUpperCase();
      
      try {
        // Verificar el material (case-insensitive)
        const [checkRows] = await connection.query(`
          SELECT 
            numero_parte,
            numero_lote_material,
            cantidad_actual,
            especificacion,
            tiene_salida,
            cancelado
          FROM control_material_almacen_smd 
          WHERE codigo_material_recibido = ?
          FOR UPDATE
        `, [code]);

        if (checkRows.length === 0) {
          results.failed.push({ code, error: 'No encontrado' });
          continue;
        }

        const mat = checkRows[0];

        if (mat.cancelado === 1) {
          results.failed.push({ code, error: 'Cancelado' });
          continue;
        }

        if (mat.tiene_salida === 1) {
          results.failed.push({ code, error: 'Ya tiene salida' });
          continue;
        }

        // Verificar blacklist
        if (mat.numero_lote_material) {
          const [blacklistCheck] = await connection.query(
            'SELECT reason FROM blacklisted_lots WHERE lot_id = ?',
            [mat.numero_lote_material]
          );
          
          if (blacklistCheck.length > 0) {
            results.failed.push({ code, error: `Lote en lista negra: ${blacklistCheck[0].reason || 'Bloqueado'}` });
            continue;
          }
        }

        const { outgoingQty } = await lockAndValidateOutgoingStock(connection, {
          codigoMaterial: code,
          cantidad: mat.cantidad_actual
        });

        // Insertar salida
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
          code,
          mat.numero_parte,
          mat.numero_lote_material,
          'MOBILE',
          'BATCH SCAN',
          outgoingQty,
          fechaSalida,
          mat.especificacion,
          usuario_registro || 'Mobile User'
        ]);

        // Marcar como tiene salida
        await connection.query(`
          UPDATE control_material_almacen_smd 
          SET tiene_salida = 1 
          WHERE codigo_material_recibido = ?
        `, [code]);

        results.success.push({ 
          code, 
          numero_parte: mat.numero_parte,
          cantidad: outgoingQty
        });

      } catch (itemErr) {
        results.failed.push({ code, error: itemErr.message });
      }
    }

    await connection.commit();

    res.json({
      success: true,
      processed: results.success.length,
      failed: results.failed.length,
      total: materials.length,
      results: results
    });

  } catch (err) {
    await connection.rollback();
    next(err);
  } finally {
    connection.release();
  }
};

// GET /api/outgoing/locations-by-partnumber - Ubicaciones por part numbers
const getLocationsByPartNumber = async (req, res, next) => {
  try {
    const { partNumbers } = req.query;
    
    if (!partNumbers) {
      return res.json({});
    }

    const partNumberList = partNumbers.split(',').map(p => p.trim()).filter(p => p);
    
    if (partNumberList.length === 0) {
      return res.json({});
    }

    const placeholders = partNumberList.map(() => '?').join(',');
    const [rows] = await pool.query(`
      SELECT numero_parte, ubicacion_salida 
      FROM control_material_almacen_smd 
      WHERE numero_parte IN (${placeholders})
        AND (cancelado = 0 OR cancelado IS NULL)
        AND (tiene_salida = 0 OR tiene_salida IS NULL)
      ORDER BY numero_parte
    `, partNumberList);

    const locationsByPartNumber = {};
    rows.forEach(row => {
      const partNumber = row.numero_parte;
      const location = row.ubicacion_salida || '';
      
      if (!locationsByPartNumber[partNumber]) {
        locationsByPartNumber[partNumber] = [];
      }
      
      if (location && !locationsByPartNumber[partNumber].includes(location)) {
        locationsByPartNumber[partNumber].push(location);
      }
    });

    res.json(locationsByPartNumber);
  } catch (err) {
    next(err);
  }
};

// POST /api/outgoing - Crear salida
const create = async (req, res, next) => {
  const connection = await pool.getConnection();

  try {
    const {
      codigo_material_recibido,
      numero_parte,
      numero_lote,
      modelo,
      depto_salida,
      proceso_salida,
      linea_proceso,
      comparacion_escaneada,
      comparacion_resultado,
      cantidad_salida,
      especificacion_material,
      usuario_registro,
      vendedor
    } = req.body;

    const normalizedMaterialCode = normalizeCode(codigo_material_recibido);
    if (!normalizedMaterialCode) {
      throw outgoingError('Código de material requerido', 'MISSING_CODE', 400);
    }

    await connection.beginTransaction();

    // Bloquear la etiqueta y usar sus datos canónicos para que el número de
    // parte o lote recibido en el body no pueda apuntar a otra existencia.
    const [checkRows] = await connection.query(`
      SELECT
        codigo_material_recibido,
        numero_parte,
        numero_lote_material,
        cantidad_actual,
        tiene_salida,
        cancelado
      FROM control_material_almacen_smd
      WHERE codigo_material_recibido = ?
      LIMIT 1
      FOR UPDATE
    `, [normalizedMaterialCode]);

    if (checkRows.length === 0) {
      throw outgoingError('Material no encontrado en inventario', 'NOT_FOUND', 404);
    }

    const warehouseMaterial = checkRows[0];

    if (warehouseMaterial.cancelado === 1) {
      throw outgoingError('Este material está cancelado', 'CANCELLED', 409);
    }

    if (warehouseMaterial.tiene_salida === 1) {
      throw outgoingError(
        'Este material ya tiene una salida registrada',
        'ALREADY_HAS_OUTGOING',
        409
      );
    }

    const { outgoingQty } = await lockAndValidateOutgoingStock(connection, {
      codigoMaterial: warehouseMaterial.codigo_material_recibido,
      cantidad: cantidad_salida
    });

    const labelQty = Number(warehouseMaterial.cantidad_actual || 0);
    if (outgoingQty > labelQty) {
      throw outgoingError(
        `La salida excede la cantidad de la etiqueta. Disponible: ${labelQty}; solicitado: ${outgoingQty}`,
        'INSUFFICIENT_LABEL_STOCK',
        409
      );
    }

    // Siempre usar NOW() de MySQL para fecha_salida y fecha_registro
    const [result] = await connection.query(`
      INSERT INTO control_material_salida_smd (
        codigo_material_recibido,
        numero_parte,
        numero_lote,
        modelo,
        depto_salida,
        proceso_salida,
        linea_proceso,
        comparacion_escaneada,
        comparacion_resultado,
        cantidad_salida,
        fecha_salida,
        fecha_registro,
        especificacion_material,
        usuario_registro,
        vendedor
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NOW(), NOW(), ?, ?, ?)
    `, [
      warehouseMaterial.codigo_material_recibido,
      warehouseMaterial.numero_parte,
      warehouseMaterial.numero_lote_material,
      modelo,
      depto_salida,
      proceso_salida,
      linea_proceso || null,
      comparacion_escaneada || null,
      comparacion_resultado || null,
      outgoingQty,
      especificacion_material,
      usuario_registro,
      vendedor || ''
    ]);

    // Marcar como tiene salida SOLO si la cantidad_salida es > 0
    // Si es 0 (comparación NG), no marcar como tiene salida para permitir salida posterior
    if (outgoingQty > 0) {
      await connection.query(`
        UPDATE control_material_almacen_smd 
        SET tiene_salida = 1 
        WHERE codigo_material_recibido = ?
      `, [warehouseMaterial.codigo_material_recibido]);
    }

    await connection.commit();

    res.status(201).json({
      id: result.insertId,
      message: 'Registro de salida creado exitosamente'
    });
  } catch (err) {
    await connection.rollback();
    next(err);
  } finally {
    connection.release();
  }
};

// GET /api/outgoing - Lista todos
const getAll = async (req, res, next) => {
  try {
    const [rows] = await pool.query(`
      SELECT cms.*, 
             IFNULL(cma.unidad_medida, 'EA') as unidad_medida
      FROM control_material_salida_smd cms
      LEFT JOIN control_material_almacen_smd cma ON cms.codigo_material_recibido = cma.codigo_material_recibido
      ORDER BY cms.fecha_registro DESC
    `);
    res.json(rows);
  } catch (err) {
    next(err);
  }
};

// GET /api/outgoing/search - Buscar
const search = async (req, res, next) => {
  try {
    const { fecha_inicio, fecha_fin, texto } = req.query;
    let query = `
      SELECT cms.*, 
             IFNULL(cma.unidad_medida, 'EA') as unidad_medida
      FROM control_material_salida_smd cms
      LEFT JOIN control_material_almacen_smd cma ON cms.codigo_material_recibido = cma.codigo_material_recibido
      WHERE 1=1
    `;
    const params = [];

    if (fecha_inicio && fecha_fin) {
      query += ' AND DATE(cms.fecha_salida) BETWEEN ? AND ?';
      params.push(fecha_inicio, fecha_fin);
    }
    
    if (texto) {
      query += ` AND (
        cms.codigo_material_recibido LIKE ? OR
        cms.numero_parte LIKE ? OR
        cms.numero_lote LIKE ? OR
        cms.modelo LIKE ? OR
        cms.depto_salida LIKE ? OR
        cms.proceso_salida LIKE ? OR
        cms.especificacion_material LIKE ?
      )`;
      const searchTerm = `%${texto}%`;
      params.push(searchTerm, searchTerm, searchTerm, searchTerm, searchTerm, searchTerm, searchTerm);
    }

    query += ' ORDER BY cms.fecha_salida DESC';

    const [rows] = await pool.query(query, params);
    res.json(rows);
  } catch (err) {
    next(err);
  }
};

const { reserveLabelSequencesWithConnection } = require('../utils/sequenceService');

// POST /api/outgoing/split-lot - Dividir lote y dar salida a los packs
// Soporta: quantities[] para packs de diferentes tamaños (incluye residuos parciales)
// O: standard_pack + packs_count para packs uniformes (compatibilidad legacy)
const splitLot = async (req, res, next) => {
  const connection = await pool.getConnection();
  
  try {
    const {
      original_code,
      standard_pack,
      packs_count,
      quantities, // NUEVO: array de cantidades [100, 100, 100, 50] para soportar residuos
      modelo,
      depto_salida,
      proceso_salida,
      linea_proceso,
      comparacion_escaneada,
      comparacion_resultado,
      usuario_registro
    } = req.body;

    console.log('>>> splitLot recibido:', { original_code, standard_pack, packs_count, quantities });

    // Validaciones básicas
    if (!original_code) {
      return res.status(400).json({
        success: false,
        error: 'Se requiere: original_code'
      });
    }

    // Determinar las cantidades de cada pack
    let packQuantities = [];
    
    if (quantities && Array.isArray(quantities) && quantities.length > 0) {
      // Usar las cantidades específicas enviadas (para Auto Split con residuo)
      packQuantities = quantities.filter(q => q > 0).map(q => parseInt(q, 10));
      if (packQuantities.length === 0) {
        return res.status(400).json({
          success: false,
          error: 'quantities debe contener al menos una cantidad válida > 0'
        });
      }
    } else if (standard_pack && packs_count) {
      // Modo legacy: crear N packs iguales (modal manual)
      if (packs_count < 1 || packs_count > 100) {
        return res.status(400).json({
          success: false,
          error: 'packs_count debe ser entre 1 y 100'
        });
      }
      for (let i = 0; i < packs_count; i++) {
        packQuantities.push(parseInt(standard_pack, 10));
      }
    } else {
      return res.status(400).json({
        success: false,
        error: 'Se requiere: quantities[] o (standard_pack y packs_count)'
      });
    }

    if (packQuantities.length > 100) {
      return res.status(400).json({
        success: false,
        error: 'No se pueden crear más de 100 packs a la vez'
      });
    }

    const totalToExtract = packQuantities.reduce((sum, q) => sum + q, 0);
    console.log('>>> packQuantities:', packQuantities, 'totalToExtract:', totalToExtract);

    await connection.beginTransaction();

    // 1. Obtener el material original y bloquear
    const [originalRows] = await connection.query(`
      SELECT 
        id,
        codigo_material_recibido,
        numero_parte,
        numero_lote_material,
        codigo_material,
        propiedad_material,
        especificacion,
        cantidad_actual,
        cantidad_estandarizada,
        unidad_medida,
        fecha_recibo,
        material_importacion_local,
        ubicacion_salida,
        tiene_salida,
        cancelado,
        iqc_required,
        iqc_status,
        receiving_lot_code
      FROM control_material_almacen_smd 
      WHERE codigo_material_recibido = ?
      FOR UPDATE
    `, [original_code]);

    if (originalRows.length === 0) {
      await connection.rollback();
      return res.status(404).json({
        success: false,
        error: 'Material original no encontrado'
      });
    }

    const original = originalRows[0];

    // Validar que no esté cancelado
    if (original.cancelado === 1) {
      await connection.rollback();
      return res.status(400).json({
        success: false,
        error: 'El material está cancelado'
      });
    }

    // Validar cantidad suficiente
    if (original.cantidad_actual < totalToExtract) {
      await connection.rollback();
      return res.status(400).json({
        success: false,
        error: `Cantidad insuficiente. Disponible: ${original.cantidad_actual}, Requerido: ${totalToExtract}`
      });
    }

    // 2. Obtener fecha actual de MySQL para la salida
    const [[{ now: fechaSalida }]] = await connection.query('SELECT NOW() as now');

    // 3. Generar códigos basados en el código original + sufijo secuencial
    // Ejemplo: 6630JB8007N-202601090002 -> 6630JB8007N-20260109000201, 6630JB8007N-20260109000202, etc.
    // Buscar el último sufijo existente para este código base
    const [existingSplits] = await connection.query(`
      SELECT codigo_material_recibido 
      FROM control_material_almacen_smd 
      WHERE codigo_material_recibido LIKE ?
      ORDER BY codigo_material_recibido DESC 
      LIMIT 1
    `, [`${original_code}%`]);

    let startSuffix = 1;
    if (existingSplits.length > 0) {
      const lastCode = existingSplits[0].codigo_material_recibido;
      // Si el último código es más largo que el original, tiene sufijo
      if (lastCode.length > original_code.length) {
        const suffix = lastCode.slice(original_code.length);
        const lastSuffix = parseInt(suffix, 10);
        if (!isNaN(lastSuffix)) {
          startSuffix = lastSuffix + 1;
        }
      }
    }

    // Generar los nuevos códigos con sufijo (uno por cada pack)
    const newCodes = [];
    for (let i = 0; i < packQuantities.length; i++) {
      const suffix = String(startSuffix + i).padStart(2, '0');
      newCodes.push(`${original_code}${suffix}`);
    }

    console.log('>>> Generando códigos:', newCodes);

    // 4. Crear registros en control_material_almacen_smd para cada pack dividido
    const newLabels = [];
    const outgoingIds = [];

    for (let i = 0; i < packQuantities.length; i++) {
      const newCode = newCodes[i];
      const packQty = packQuantities[i]; // Cantidad específica de este pack
      
      // Insertar nuevo registro de almacén (el pack dividido)
      const [insertResult] = await connection.query(`
        INSERT INTO control_material_almacen_smd (
          codigo_material_recibido,
          numero_parte,
          numero_lote_material,
          codigo_material,
          propiedad_material,
          especificacion,
          cantidad_actual,
          cantidad_estandarizada,
          unidad_medida,
          fecha_recibo,
          material_importacion_local,
          ubicacion_salida,
          tiene_salida,
          cancelado,
          iqc_required,
          iqc_status,
          receiving_lot_code,
          usuario_registro
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 1, 0, ?, ?, ?, ?)
      `, [
        newCode,
        original.numero_parte,
        original.numero_lote_material,
        original.codigo_material,
        original.propiedad_material,
        original.especificacion,
        packQty,
        packQty,
        original.unidad_medida || 'EA',
        original.fecha_recibo,
        original.material_importacion_local,
        original.ubicacion_salida,
        original.iqc_required,
        original.iqc_status || 'NotRequired',
        original.receiving_lot_code,
        usuario_registro || 'Sistema'
      ]);

      // Insertar registro de salida para el pack
      const [outgoingResult] = await connection.query(`
        INSERT INTO control_material_salida_smd (
          codigo_material_recibido,
          numero_parte,
          numero_lote,
          modelo,
          depto_salida,
          proceso_salida,
          linea_proceso,
          comparacion_escaneada,
          comparacion_resultado,
          cantidad_salida,
          fecha_salida,
          fecha_registro,
          especificacion_material,
          usuario_registro
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NOW(), ?, ?)
      `, [
        newCode,
        original.numero_parte,
        original.numero_lote_material,
        modelo || '',
        depto_salida || 'Almacen',
        proceso_salida || 'SMD',
        linea_proceso || null,
        comparacion_escaneada || null,
        comparacion_resultado || null,
        packQty,
        fechaSalida,
        original.especificacion,
        usuario_registro || 'Sistema'
      ]);

      outgoingIds.push(outgoingResult.insertId);

      // Registrar en lot_division
      await connection.query(`
        INSERT INTO lot_division (
          original_code,
          original_qty_before,
          original_qty_after,
          new_code,
          new_qty,
          standard_pack,
          outgoing_id,
          divided_by
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
      `, [
        original_code,
        original.cantidad_actual,
        original.cantidad_actual - totalToExtract,
        newCode,
        packQty,
        packQty,
        outgoingResult.insertId,
        usuario_registro || 'Sistema'
      ]);

      newLabels.push({
        code: newCode,
        qty: packQty,
        part_number: original.numero_parte,
        lot_no: original.numero_lote_material,
        spec: original.especificacion,
        outgoing_id: outgoingResult.insertId
      });
    }

    // 5. Actualizar cantidad del material original
    const newOriginalQty = original.cantidad_actual - totalToExtract;
    await connection.query(`
      UPDATE control_material_almacen_smd 
      SET cantidad_actual = ?
      WHERE codigo_material_recibido = ?
    `, [newOriginalQty, original_code]);

    await connection.commit();

    console.log('>>> División exitosa. Labels creados:', newLabels.length, 'Qty restante:', newOriginalQty);

    res.json({
      success: true,
      message: `División completada: ${packQuantities.length} packs creados`,
      original: {
        code: original_code,
        qty_before: original.cantidad_actual,
        qty_after: newOriginalQty
      },
      new_labels: newLabels,
      total_extracted: totalToExtract
    });

  } catch (err) {
    await connection.rollback();
    console.error('Error en splitLot:', err);
    next(err);
  } finally {
    connection.release();
  }
};

module.exports = {
  checkSalida,
  validateBatch,
  createBatch,
  getLocationsByPartNumber,
  create,
  getAll,
  search,
  splitLot
};

