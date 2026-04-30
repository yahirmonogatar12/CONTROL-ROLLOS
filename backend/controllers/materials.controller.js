/**
 * Materials Controller - Catálogo de Materiales
 * Pantalla Flutter: lib/screens/material_control/
 */

const { pool } = require('../config/database');
const { getBasePartNumber } = require('../utils/partNumberHelper');

// GET /api/materials - Lista códigos de material únicos
exports.getMaterialCodes = async (req, res, next) => {
  try {
    const [rows] = await pool.query(`
      SELECT DISTINCT 
        codigo_material as code,
        codigo_material_original as name,
        especificacion as spec
      FROM control_material_almacen_smd 
      WHERE codigo_material IS NOT NULL AND codigo_material != ''
      ORDER BY codigo_material
    `);
    res.json(rows);
  } catch (err) {
    next(err);
  }
};

// GET /api/materiales - Lista de materiales desde tabla materiales
exports.getAll = async (req, res, next) => {
  try {
    const [rows] = await pool.query(`
      SELECT 
        numero_parte,
        codigo_material,
        propiedad_material,
        clasificacion,
        especificacion_material,
        unidad_empaque,
        ubicacion_material,
        ubicacion_rollos,
        vendedor,
        prohibido_sacar,
        reparable,
        nivel_msl,
        espesor_msl,
        fecha_registro,
        cantidad,
        classification,
        usuario_registro,
        IFNULL(iqc_required, 0) as iqc_required,
        IFNULL(assign_internal_lot, 0) as assign_internal_lot,
        IFNULL(dividir_lote, 1) as dividir_lote,
        IFNULL(standard_pack, 0) as standard_pack,
        version,
        IFNULL(unidad_medida, 'EA') as unidad_medida,
        comparacion
      FROM materiales 
      WHERE propiedad_material = 'SMD'
      ORDER BY fecha_registro DESC
    `);
    res.json(rows);
  } catch (err) {
    next(err);
  }
};

// GET /api/materiales/by-code/:materialCode - Obtener material por código
exports.getByCode = async (req, res, next) => {
  try {
    const { materialCode } = req.params;
    const [rows] = await pool.query(`
      SELECT 
        numero_parte,
        codigo_material,
        propiedad_material,
        clasificacion,
        especificacion_material,
        unidad_empaque,
        ubicacion_material,
        vendedor,
        prohibido_sacar,
        nivel_msl,
        espesor_msl,
        IFNULL(iqc_required, 0) as iqc_required,
        IFNULL(assign_internal_lot, 0) as assign_internal_lot,
        IFNULL(dividir_lote, 0) as dividir_lote,
        standard_pack,
        version,
        IFNULL(unidad_medida, 'EA') as unidad_medida
      FROM materiales 
      WHERE codigo_material = ?
      LIMIT 1
    `, [materialCode]);

    if (rows.length === 0) {
      return res.status(404).json({ error: 'Material no encontrado' });
    }

    res.json(rows[0]);
  } catch (err) {
    next(err);
  }
};

// GET /api/materiales/by-part-number/:partNumber - Obtener material por número de parte
exports.getByPartNumber = async (req, res, next) => {
  try {
    const { partNumber } = req.params;
    
    // Buscar primero coincidencia exacta
    let [rows] = await pool.query(`
      SELECT 
        numero_parte,
        codigo_material,
        propiedad_material,
        clasificacion,
        especificacion_material,
        unidad_empaque,
        ubicacion_material,
        vendedor,
        prohibido_sacar,
        nivel_msl,
        espesor_msl,
        IFNULL(iqc_required, 0) as iqc_required,
        IFNULL(assign_internal_lot, 0) as assign_internal_lot,
        IFNULL(dividir_lote, 0) as dividir_lote,
        standard_pack,
        comparacion,
        version,
        IFNULL(unidad_medida, 'EA') as unidad_medida
      FROM materiales 
      WHERE numero_parte = ?
      LIMIT 1
    `, [partNumber]);

    // Si no hay coincidencia exacta, buscar con base part number (sin sufijos)
    if (rows.length === 0) {
      const basePartNumber = getBasePartNumber(partNumber);
      if (basePartNumber !== partNumber) {
        [rows] = await pool.query(`
          SELECT 
            numero_parte,
            codigo_material,
            propiedad_material,
            clasificacion,
            especificacion_material,
            unidad_empaque,
            ubicacion_material,
            vendedor,
            prohibido_sacar,
            nivel_msl,
            espesor_msl,
            IFNULL(iqc_required, 0) as iqc_required,
            IFNULL(assign_internal_lot, 0) as assign_internal_lot,
            IFNULL(dividir_lote, 0) as dividir_lote,
            standard_pack,
            comparacion,
            version,
            IFNULL(unidad_medida, 'EA') as unidad_medida
          FROM materiales 
          WHERE numero_parte = ?
          LIMIT 1
        `, [basePartNumber]);
      }
    }

    if (rows.length === 0) {
      return res.status(404).json({ error: 'Material no encontrado por número de parte' });
    }

    res.json(rows[0]);
  } catch (err) {
    next(err);
  }
};

// POST /api/materiales - Crear nuevo material
exports.create = async (req, res, next) => {
  try {
    const {
      numero_parte,
      codigo_material,
      propiedad_material,
      clasificacion,
      especificacion_material,
      unidad_empaque,
      ubicacion_material,
      ubicacion_rollos,
      vendedor,
      prohibido_sacar,
      nivel_msl,
      espesor_msl,
      assign_internal_lot,
      dividir_lote,
      standard_pack,
      usuario_registro,
      version,
      unidad_medida
    } = req.body;

    if (!numero_parte || !codigo_material || !propiedad_material || !especificacion_material || !unidad_empaque) {
      return res.status(400).json({
        error: 'Campos requeridos faltantes: numero_parte, codigo_material, propiedad_material, especificacion_material, unidad_empaque',
        code: 'MISSING_REQUIRED_FIELDS'
      });
    }

    const [existing] = await pool.query(
      'SELECT numero_parte FROM materiales WHERE numero_parte = ?',
      [numero_parte]
    );

    if (existing.length > 0) {
      return res.status(400).json({
        error: 'El número de parte ya existe',
        code: 'DUPLICATE_PART_NUMBER'
      });
    }

    await pool.query(`
      INSERT INTO materiales (
        numero_parte, codigo_material, propiedad_material, clasificacion,
        especificacion_material, unidad_empaque, ubicacion_material, ubicacion_rollos, vendedor,
        prohibido_sacar, nivel_msl, espesor_msl, fecha_registro,
        usuario_registro, iqc_required, assign_internal_lot, dividir_lote, standard_pack, version, unidad_medida
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NOW(), ?, 0, ?, ?, ?, ?, ?)
    `, [
      numero_parte,
      codigo_material,
      propiedad_material,
      clasificacion || null,
      especificacion_material,
      unidad_empaque,
      ubicacion_material || null,
      ubicacion_rollos || null,
      vendedor || null,
      prohibido_sacar || 0,
      nivel_msl || null,
      espesor_msl || null,
      usuario_registro || null,
      assign_internal_lot || 0,
      dividir_lote !== undefined ? (dividir_lote ? 1 : 0) : 1,
      standard_pack || null,
      version || null,
      unidad_medida || 'EA'
    ]);

    res.status(201).json({ message: 'Material creado exitosamente', numero_parte });
  } catch (err) {
    next(err);
  }
};

// PUT /api/materiales/:numeroParte - Actualizar material existente
exports.update = async (req, res, next) => {
  try {
    const { numeroParte } = req.params;
    const {
      codigo_material,
      propiedad_material,
      clasificacion,
      especificacion_material,
      unidad_empaque,
      ubicacion_material,
      ubicacion_rollos,
      vendedor,
      prohibido_sacar,
      nivel_msl,
      espesor_msl,
      assign_internal_lot,
      dividir_lote,
      standard_pack,
      usuario_registro,
      version,
      unidad_medida,
      comparacion
    } = req.body;

    console.log(`UPDATE material [${numeroParte}] - ubicacion_rollos recibido: '${ubicacion_rollos}', tipo: ${typeof ubicacion_rollos}`);

    if (!codigo_material || !propiedad_material || !especificacion_material || !unidad_empaque) {
      console.log(`UPDATE material [${numeroParte}] - RECHAZADO: campos requeridos faltantes`, {
        codigo_material: !!codigo_material,
        propiedad_material: !!propiedad_material,
        especificacion_material: !!especificacion_material,
        unidad_empaque: !!unidad_empaque
      });
      return res.status(400).json({
        error: 'Campos requeridos faltantes: codigo_material, propiedad_material, especificacion_material, unidad_empaque',
        code: 'MISSING_REQUIRED_FIELDS'
      });
    }

    const [existing] = await pool.query(
      'SELECT numero_parte FROM materiales WHERE numero_parte = ?',
      [numeroParte]
    );

    if (existing.length === 0) {
      return res.status(404).json({
        error: 'Material no encontrado',
        code: 'NOT_FOUND'
      });
    }

    const ubicacionRollosValue = ubicacion_rollos !== undefined && ubicacion_rollos !== null && ubicacion_rollos !== '' 
      ? ubicacion_rollos 
      : null;

    const [updateResult] = await pool.query(`
      UPDATE materiales SET
        codigo_material = ?,
        propiedad_material = ?,
        clasificacion = ?,
        especificacion_material = ?,
        unidad_empaque = ?,
        ubicacion_material = ?,
        ubicacion_rollos = ?,
        vendedor = ?,
        prohibido_sacar = ?,
        nivel_msl = ?,
        espesor_msl = ?,
        assign_internal_lot = ?,
        dividir_lote = ?,
        standard_pack = ?,
        usuario_registro = ?,
        version = ?,
        unidad_medida = ?,
        comparacion = ?
      WHERE numero_parte = ?
    `, [
      codigo_material,
      propiedad_material,
      clasificacion || null,
      especificacion_material,
      unidad_empaque,
      ubicacion_material || null,
      ubicacionRollosValue,
      vendedor || null,
      prohibido_sacar || 0,
      nivel_msl || null,
      espesor_msl || null,
      assign_internal_lot || 0,
      dividir_lote !== undefined ? (dividir_lote ? 1 : 0) : 1,
      standard_pack || null,
      usuario_registro || null,
      version || null,
      unidad_medida || 'EA',
      comparacion || null,
      numeroParte
    ]);

    console.log(`UPDATE material [${numeroParte}] - affectedRows: ${updateResult.affectedRows}, changedRows: ${updateResult.changedRows}, ubicacion_rollos guardado: '${ubicacionRollosValue}'`);

    if (updateResult.affectedRows === 0) {
      return res.status(500).json({
        error: 'No se pudo actualizar el material (0 filas afectadas)',
        code: 'UPDATE_FAILED'
      });
    }

    res.json({ success: true, message: 'Material actualizado exitosamente', numero_parte: numeroParte });
  } catch (err) {
    next(err);
  }
};

// DELETE /api/materiales/:numeroParte - Eliminar material
exports.delete = async (req, res, next) => {
  try {
    const { numeroParte } = req.params;

    const [existing] = await pool.query(
      'SELECT numero_parte FROM materiales WHERE numero_parte = ?',
      [numeroParte]
    );

    if (existing.length === 0) {
      return res.status(404).json({
        error: 'Material no encontrado',
        code: 'NOT_FOUND'
      });
    }

    await pool.query('DELETE FROM materiales WHERE numero_parte = ?', [numeroParte]);

    res.json({ message: 'Material eliminado exitosamente', numero_parte: numeroParte });
  } catch (err) {
    next(err);
  }
};

// ============================================
// IQC Configuration
// ============================================

// GET /api/materiales/iqc-required - Materiales que requieren IQC
exports.getIqcRequired = async (req, res, next) => {
  try {
    const [rows] = await pool.query(
      'SELECT numero_parte, codigo_material, clasificacion FROM materiales WHERE iqc_required = 1'
    );
    res.json(rows);
  } catch (err) {
    next(err);
  }
};

// PUT /api/materiales/:numeroParte/iqc-required - Marcar material como iqc_required
exports.setIqcRequired = async (req, res, next) => {
  try {
    const { iqc_required } = req.body;
    await pool.query(
      'UPDATE materiales SET iqc_required = ? WHERE numero_parte = ?',
      [iqc_required ? 1 : 0, req.params.numeroParte]
    );
    res.json({ success: true });
  } catch (err) {
    next(err);
  }
};

// GET /api/materiales/iqc-config - Lista materiales con configuración IQC
exports.getIqcConfigList = async (req, res, next) => {
  try {
    const [rows] = await pool.query(`
      SELECT 
        numero_parte,
        codigo_material,
        clasificacion,
        especificacion_material,
        COALESCE(iqc_required, 0) as iqc_required,
        COALESCE(rohs_enabled, 0) as rohs_enabled,
        COALESCE(brightness_enabled, 0) as brightness_enabled,
        COALESCE(brightness_sampling_level, 'S-1') as brightness_sampling_level,
        COALESCE(brightness_aql_level, '2.5') as brightness_aql_level,
        brightness_target,
        brightness_lsl,
        brightness_usl,
        COALESCE(dimension_enabled, 0) as dimension_enabled,
        COALESCE(dimension_sampling_level, 'S-1') as dimension_sampling_level,
        COALESCE(dimension_aql_level, '2.5') as dimension_aql_level,
        dimension_length,
        dimension_length_tol,
        dimension_width,
        dimension_width_tol,
        dimension_height,
        dimension_height_tol,
        COALESCE(color_enabled, 0) as color_enabled,
        COALESCE(color_sampling_level, 'S-1') as color_sampling_level,
        COALESCE(color_aql_level, '2.5') as color_aql_level,
        color_spec,
        COALESCE(appearance_enabled, 0) as appearance_enabled,
        COALESCE(appearance_sampling_level, 'S-1') as appearance_sampling_level,
        COALESCE(appearance_aql_level, '2.5') as appearance_aql_level,
        appearance_spec
      FROM materiales
      ORDER BY iqc_required DESC, numero_parte
    `);
    res.json(rows);
  } catch (err) {
    next(err);
  }
};

// GET /api/materiales/:partNumber/iqc-config - Obtener configuración IQC de un material
exports.getIqcConfig = async (req, res, next) => {
  try {
    const { partNumber } = req.params;
    const basePN = getBasePartNumber(partNumber);

    // Buscar por part number exacto o base (sin versión como -A, -1.1)
    const [rows] = await pool.query(`
      SELECT 
        numero_parte,
        COALESCE(iqc_required, 0) as iqc_required,
        COALESCE(rohs_enabled, 0) as rohs_enabled,
        COALESCE(brightness_enabled, 0) as brightness_enabled,
        COALESCE(brightness_sampling_level, 'S-1') as brightness_sampling_level,
        COALESCE(brightness_aql_level, '2.5') as brightness_aql_level,
        brightness_target, brightness_lsl, brightness_usl,
        COALESCE(dimension_enabled, 0) as dimension_enabled,
        COALESCE(dimension_sampling_level, 'S-1') as dimension_sampling_level,
        COALESCE(dimension_aql_level, '2.5') as dimension_aql_level,
        dimension_length, dimension_length_tol,
        dimension_width, dimension_width_tol,
        dimension_height, dimension_height_tol,
        COALESCE(color_enabled, 0) as color_enabled,
        COALESCE(color_sampling_level, 'S-1') as color_sampling_level,
        COALESCE(color_aql_level, '2.5') as color_aql_level,
        color_spec,
        COALESCE(appearance_enabled, 0) as appearance_enabled,
        COALESCE(appearance_sampling_level, 'S-1') as appearance_sampling_level,
        COALESCE(appearance_aql_level, '2.5') as appearance_aql_level,
        appearance_spec
      FROM materiales
      WHERE numero_parte = ? OR numero_parte = ?
      ORDER BY CASE WHEN numero_parte = ? THEN 0 ELSE 1 END
      LIMIT 1
    `, [partNumber, basePN, partNumber]);

    if (rows.length === 0) {
      return res.status(404).json({ error: 'Material not found' });
    }

    res.json(rows[0]);
  } catch (err) {
    next(err);
  }
};

// PUT /api/materiales/:numeroParte/iqc-config - Actualizar configuración IQC
exports.updateIqcConfig = async (req, res, next) => {
  try {
    const { numeroParte } = req.params;
    const body = req.body;

    const allowedFields = [
      'iqc_required',
      'rohs_enabled', 'rohs_sampling_level', 'rohs_aql_level',
      'brightness_enabled', 'brightness_sampling_level', 'brightness_aql_level',
      'brightness_target', 'brightness_lsl', 'brightness_usl',
      'dimension_enabled', 'dimension_sampling_level', 'dimension_aql_level',
      'dimension_length', 'dimension_length_tol',
      'dimension_width', 'dimension_width_tol',
      'dimension_height', 'dimension_height_tol',
      'color_enabled', 'color_sampling_level', 'color_aql_level', 'color_spec',
      'appearance_enabled', 'appearance_sampling_level', 'appearance_aql_level', 'appearance_spec',
      'sampling_level', 'aql_level', 'dimension_spec'
    ];

    const updates = [];
    const values = [];

    for (const field of allowedFields) {
      if (body[field] !== undefined) {
        updates.push(`${field} = ?`);
        values.push(body[field]);
      }
    }

    if (updates.length === 0) {
      return res.status(400).json({ success: false, message: 'No fields to update' });
    }

    values.push(numeroParte);

    await pool.query(
      `UPDATE materiales SET ${updates.join(', ')} WHERE numero_parte = ?`,
      values
    );

    res.json({ success: true, message: 'Configuration updated' });
  } catch (err) {
    next(err);
  }
};

// POST /api/materiales/iqc-config/bulk - Bulk update configuración IQC
exports.bulkUpdateIqcConfig = async (req, res, next) => {
  try {
    const { configs } = req.body;
    if (!Array.isArray(configs)) {
      return res.status(400).json({ error: 'configs must be an array' });
    }

    let updated = 0;
    const errors = [];

    for (const config of configs) {
      try {
        if (!config.numero_parte) continue;

        const updates = [];
        const values = [];

        if (config.iqc_required !== undefined) { updates.push('iqc_required = ?'); values.push(config.iqc_required); }
        if (config.sampling_level !== undefined) { updates.push('sampling_level = ?'); values.push(config.sampling_level); }
        if (config.aql_level !== undefined) { updates.push('aql_level = ?'); values.push(config.aql_level); }
        if (config.rohs_enabled !== undefined) { updates.push('rohs_enabled = ?'); values.push(config.rohs_enabled); }
        if (config.brightness_enabled !== undefined) { updates.push('brightness_enabled = ?'); values.push(config.brightness_enabled); }
        if (config.dimension_enabled !== undefined) { updates.push('dimension_enabled = ?'); values.push(config.dimension_enabled); }
        if (config.color_enabled !== undefined) { updates.push('color_enabled = ?'); values.push(config.color_enabled); }
        if (config.brightness_target !== undefined) { updates.push('brightness_target = ?'); values.push(config.brightness_target); }
        if (config.brightness_lsl !== undefined) { updates.push('brightness_lsl = ?'); values.push(config.brightness_lsl); }
        if (config.brightness_usl !== undefined) { updates.push('brightness_usl = ?'); values.push(config.brightness_usl); }
        if (config.dimension_spec !== undefined) { updates.push('dimension_spec = ?'); values.push(config.dimension_spec); }

        if (updates.length > 0) {
          values.push(config.numero_parte);
          await pool.query(
            `UPDATE materiales SET ${updates.join(', ')} WHERE numero_parte = ?`,
            values
          );
          updated++;
        }
      } catch (e) {
        errors.push({ numero_parte: config.numero_parte, error: e.message });
      }
    }

    res.json({ success: true, updated, errors, total: configs.length });
  } catch (err) {
    next(err);
  }
};

// POST /api/materiales/parse-barcode - Parsear código de barras y encontrar material
exports.parseBarcode = async (req, res, next) => {
  try {
    const { barcode } = req.body;

    if (!barcode) {
      return res.status(400).json({ error: 'Barcode is required' });
    }

    const scannedCode = barcode.toUpperCase();

    // Obtener todos los materiales
    const [materiales] = await pool.query(`
      SELECT 
        numero_parte,
        codigo_material,
        propiedad_material,
        clasificacion,
        especificacion_material,
        unidad_empaque,
        ubicacion_material,
        IFNULL(iqc_required, 0) as iqc_required,
        IFNULL(assign_internal_lot, 0) as assign_internal_lot,
        IFNULL(unidad_medida, 'EA') as unidad_medida
      FROM materiales 
      WHERE codigo_material IS NOT NULL AND codigo_material != ''
      ORDER BY codigo_material
    `);

    // Buscar el material con codigo_material más parecido
    let bestMatch = null;
    let bestMatchScore = 0;

    for (const material of materiales) {
      const codigoMaterial = (material.codigo_material || '').toUpperCase();
      if (!codigoMaterial) continue;

      let score = 0;

      // Si el código escaneado contiene el codigo_material completo - alta prioridad
      if (scannedCode.includes(codigoMaterial)) {
        score = codigoMaterial.length * 10;
      } else {
        // Buscar coincidencia parcial - caracteres consecutivos que coinciden
        for (let len = codigoMaterial.length; len >= 5; len--) {
          const substring = codigoMaterial.substring(0, len);
          if (scannedCode.includes(substring)) {
            score = len;
            break;
          }
        }
      }

      if (score > bestMatchScore) {
        bestMatchScore = score;
        bestMatch = material;
      }
    }

    if (bestMatch && bestMatchScore >= 5) {
      res.json({
        found: true,
        material: bestMatch,
        matchScore: bestMatchScore,
        matchedCode: bestMatch.codigo_material
      });
    } else {
      res.json({
        found: false,
        message: 'No matching material found'
      });
    }
  } catch (err) {
    next(err);
  }
};

// POST /api/materiales/bulk-update-comparacion - Actualización masiva de comparaciones
exports.bulkUpdateComparacion = async (req, res, next) => {
  try {
    const { items } = req.body;
    
    if (!items || !Array.isArray(items) || items.length === 0) {
      return res.status(400).json({
        error: 'Se requiere un array de items con numero_parte y comparacion',
        code: 'INVALID_DATA'
      });
    }
    
    let updated = 0;
    let notFound = [];
    let errors = [];
    
    for (const item of items) {
      const numeroParte = (item.numero_parte || item.numeroParte || '').toString().trim();
      const comparacion = (item.comparacion || item.Comparacion || '').toString().trim();
      
      if (!numeroParte) {
        continue;
      }
      
      try {
        const [result] = await pool.query(
          'UPDATE materiales SET comparacion = ? WHERE numero_parte = ?',
          [comparacion || null, numeroParte]
        );
        
        if (result.affectedRows > 0) {
          updated++;
        } else {
          notFound.push(numeroParte);
        }
      } catch (err) {
        errors.push({ numero_parte: numeroParte, error: err.message });
      }
    }
    
    res.json({
      success: true,
      message: `Actualizados: ${updated}, No encontrados: ${notFound.length}, Errores: ${errors.length}`,
      updated,
      notFound,
      errors
    });
  } catch (err) {
    next(err);
  }
};

// POST /api/materiales/bulk-update-ubicacion-rollos - Actualización masiva de ubicación rollos
exports.bulkUpdateUbicacionRollos = async (req, res, next) => {
  try {
    const { items } = req.body;
    
    if (!items || !Array.isArray(items) || items.length === 0) {
      return res.status(400).json({
        error: 'Se requiere un array de items con numero_parte y ubicacion_rollos',
        code: 'INVALID_DATA'
      });
    }
    
    let updated = 0;
    let notFound = [];
    let errors = [];
    
    for (const item of items) {
      const numeroParte = (item.numero_parte || item.numeroParte || '').toString().trim();
      const ubicacionRollos = (item.ubicacion_rollos || item.ubicacionRollos || '').toString().trim();
      
      if (!numeroParte) {
        continue;
      }
      
      try {
        const [result] = await pool.query(
          'UPDATE materiales SET ubicacion_rollos = ? WHERE numero_parte = ?',
          [ubicacionRollos || null, numeroParte]
        );
        
        if (result.affectedRows > 0) {
          updated++;
        } else {
          notFound.push(numeroParte);
        }
      } catch (err) {
        errors.push({ numero_parte: numeroParte, error: err.message });
      }
    }
    
    res.json({
      success: true,
      message: `Actualizados: ${updated}, No encontrados: ${notFound.length}, Errores: ${errors.length}`,
      updated,
      notFound,
      errors
    });
  } catch (err) {
    next(err);
  }
};

// POST /api/materiales/validate-part-numbers - Validar cuáles números de parte existen en el sistema
exports.validatePartNumbers = async (req, res, next) => {
  try {
    const { partNumbers } = req.body;
    
    if (!partNumbers || !Array.isArray(partNumbers) || partNumbers.length === 0) {
      return res.status(400).json({
        error: 'Se requiere un array de números de parte',
        code: 'INVALID_DATA'
      });
    }
    
    // Obtener todos los números de parte que existen
    const placeholders = partNumbers.map(() => '?').join(',');
    const [existingRows] = await pool.query(
      `SELECT numero_parte FROM materiales WHERE numero_parte IN (${placeholders})`,
      partNumbers
    );
    
    const existingSet = new Set(existingRows.map(r => r.numero_parte));
    
    const results = partNumbers.map(pn => ({
      numero_parte: pn,
      exists: existingSet.has(pn)
    }));
    
    const existCount = results.filter(r => r.exists).length;
    const notExistCount = results.filter(r => !r.exists).length;
    
    res.json({
      success: true,
      results,
      existCount,
      notExistCount
    });
  } catch (err) {
    next(err);
  }
};

// POST /api/materiales/create-simple - Crear material con numero_parte, comparacion y ubicacion_rollos
exports.createSimple = async (req, res, next) => {
  try {
    const { numero_parte, comparacion, ubicacion_rollos } = req.body;
    
    if (!numero_parte) {
      return res.status(400).json({
        error: 'El número de parte es requerido',
        code: 'MISSING_PART_NUMBER'
      });
    }
    
    // Verificar si ya existe
    const [existing] = await pool.query(
      'SELECT numero_parte FROM materiales WHERE numero_parte = ?',
      [numero_parte]
    );
    
    if (existing.length > 0) {
      return res.status(400).json({
        error: 'El número de parte ya existe',
        code: 'DUPLICATE_PART_NUMBER'
      });
    }
    
    // Insertar con valores por defecto para campos requeridos
    await pool.query(`
      INSERT INTO materiales (
        numero_parte, 
        comparacion,
        ubicacion_rollos,
        codigo_material,
        propiedad_material,
        especificacion_material,
        unidad_empaque,
        fecha_registro
      ) VALUES (?, ?, ?, ?, 'SMD', '-', '-', NOW())
    `, [
      numero_parte,
      comparacion || null,
      ubicacion_rollos || null,
      numero_parte // usar numero_parte como codigo_material por defecto
    ]);
    
    res.json({ 
      success: true, 
      message: 'Material creado exitosamente',
      numero_parte 
    });
  } catch (err) {
    next(err);
  }
};

// PUT /api/materiales/:numeroParte/comparacion - Actualizar comparacion y ubicacion_rollos
exports.updateComparacion = async (req, res, next) => {
  try {
    const { numeroParte } = req.params;
    const { comparacion, ubicacion_rollos } = req.body;
    
    const [existing] = await pool.query(
      'SELECT numero_parte, ubicacion_rollos FROM materiales WHERE numero_parte = ?',
      [numeroParte]
    );
    
    if (existing.length === 0) {
      return res.status(404).json({
        error: 'Material no encontrado',
        code: 'NOT_FOUND'
      });
    }
    
    const newUbicacionRollos = ubicacion_rollos !== undefined && ubicacion_rollos !== null && ubicacion_rollos !== '' 
      ? ubicacion_rollos 
      : (ubicacion_rollos === '' ? null : existing[0].ubicacion_rollos);

    console.log(`UPDATE comparacion [${numeroParte}] - ubicacion_rollos recibido: '${ubicacion_rollos}', valor a guardar: '${newUbicacionRollos}', anterior: '${existing[0].ubicacion_rollos}'`);
    
    const [updateResult] = await pool.query(
      'UPDATE materiales SET comparacion = ?, ubicacion_rollos = ? WHERE numero_parte = ?',
      [comparacion || null, newUbicacionRollos, numeroParte]
    );

    console.log(`UPDATE comparacion [${numeroParte}] - affectedRows: ${updateResult.affectedRows}, changedRows: ${updateResult.changedRows}`);
    
    if (updateResult.affectedRows === 0) {
      return res.status(500).json({
        error: 'No se pudo actualizar (0 filas afectadas)',
        code: 'UPDATE_FAILED'
      });
    }

    res.json({ 
      success: true, 
      message: 'Comparación actualizada exitosamente',
      numero_parte: numeroParte 
    });
  } catch (err) {
    next(err);
  }
};
