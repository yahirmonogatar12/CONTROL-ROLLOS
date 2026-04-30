/**
 * Quality Specs Controller - Especificaciones de Calidad
 * Relacionado con: lib/screens/iqc/
 */

const { pool } = require('../config/database');
const { getBasePartNumber } = require('../utils/partNumberHelper');

// Helper: Función de validación de specs
function validateSpecItem(item) {
  const errors = [];
  
  if (!item.numero_parte) errors.push('numero_parte requerido');
  if (!item.spec_code) errors.push('spec_code requerido');
  if (!item.inspection_item) errors.push('inspection_item requerido');
  
  // BRIGHTNESS y DIMENSION requieren valores numéricos y son bloqueantes
  if (['BRIGHTNESS', 'DIMENSION'].includes(item.spec_code)) {
    item.measure_type = 'Continuous';
    item.is_blocking = 1;
    if (item.target_value === null || item.target_value === undefined || item.target_value === '') 
      errors.push(`${item.spec_code} requiere target_value`);
    if (item.lsl === null || item.lsl === undefined || item.lsl === '') 
      errors.push(`${item.spec_code} requiere LSL`);
    if (item.usl === null || item.usl === undefined || item.usl === '') 
      errors.push(`${item.spec_code} requiere USL`);
  }
  
  // ROHS es Discrete y NO bloqueante
  if (item.spec_code === 'ROHS') {
    item.measure_type = 'Discrete';
    item.is_blocking = 0;
  }
  
  // COLOR, APPEARANCE, FUNCTION son Discrete
  if (['COLOR', 'APPEARANCE', 'FUNCTION', 'OTHER'].includes(item.spec_code)) {
    item.measure_type = 'Discrete';
  }
  
  return errors;
}

// GET /api/quality-specs - Listar specs con filtros
exports.getAll = async (req, res, next) => {
  try {
    const { numero_parte, spec_code, is_active } = req.query;
    let query = `
      SELECT qs.*, m.codigo_material, m.clasificacion 
      FROM quality_specs qs
      LEFT JOIN materiales m ON qs.numero_parte = m.numero_parte
      WHERE 1=1
    `;
    const params = [];
    
    if (numero_parte) {
      query += ' AND qs.numero_parte LIKE ?';
      params.push(`%${numero_parte}%`);
    }
    if (spec_code) {
      query += ' AND qs.spec_code = ?';
      params.push(spec_code);
    }
    if (is_active !== undefined && is_active !== '') {
      query += ' AND qs.is_active = ?';
      params.push(is_active);
    }
    
    query += ' ORDER BY qs.numero_parte, qs.order_index';
    const [rows] = await pool.query(query, params);
    res.json(rows);
  } catch (err) {
    next(err);
  }
};

// GET /api/quality-specs/part/:partNumber - Specs por part number (para inspección)
exports.getByPartNumber = async (req, res, next) => {
  try {
    const partNumber = req.params.partNumber;
    const basePN = getBasePartNumber(partNumber);
    
    // Buscar por part number exacto o base (sin versión)
    const [rows] = await pool.query(
      `SELECT * FROM quality_specs 
       WHERE (numero_parte = ? OR numero_parte = ?) AND is_active = 1 
       ORDER BY CASE WHEN numero_parte = ? THEN 0 ELSE 1 END, order_index`,
      [partNumber, basePN, partNumber]
    );
    res.json(rows);
  } catch (err) {
    next(err);
  }
};

// GET /api/quality-specs/:id - Obtener spec por ID
exports.getById = async (req, res, next) => {
  try {
    const [rows] = await pool.query('SELECT * FROM quality_specs WHERE id = ?', [req.params.id]);
    if (rows.length === 0) {
      return res.status(404).json({ error: 'Spec no encontrada' });
    }
    res.json(rows[0]);
  } catch (err) {
    next(err);
  }
};

// POST /api/quality-specs - Crear spec
exports.create = async (req, res, next) => {
  try {
    const spec = req.body;
    const errors = validateSpecItem(spec);
    if (errors.length > 0) {
      return res.status(400).json({ error: errors.join(', ') });
    }
    
    if (spec.target_value === '') spec.target_value = null;
    if (spec.lsl === '') spec.lsl = null;
    if (spec.usl === '') spec.usl = null;
    
    const [result] = await pool.query('INSERT INTO quality_specs SET ?', spec);
    res.json({ id: result.insertId, ...spec });
  } catch (err) {
    next(err);
  }
};

// PUT /api/quality-specs/:id - Actualizar spec
exports.update = async (req, res, next) => {
  try {
    const spec = req.body;
    delete spec.id;
    delete spec.created_at;
    
    const errors = validateSpecItem(spec);
    if (errors.length > 0) {
      return res.status(400).json({ error: errors.join(', ') });
    }
    
    if (spec.target_value === '') spec.target_value = null;
    if (spec.lsl === '') spec.lsl = null;
    if (spec.usl === '') spec.usl = null;
    
    await pool.query('UPDATE quality_specs SET ? WHERE id = ?', [spec, req.params.id]);
    res.json({ success: true });
  } catch (err) {
    next(err);
  }
};

// DELETE /api/quality-specs/:id - Soft delete
exports.delete = async (req, res, next) => {
  try {
    await pool.query('UPDATE quality_specs SET is_active = 0 WHERE id = ?', [req.params.id]);
    res.json({ success: true });
  } catch (err) {
    next(err);
  }
};

// POST /api/quality-specs/bulk-upload - Carga masiva desde Excel
exports.bulkUpload = async (req, res, next) => {
  try {
    const { specs, created_by } = req.body;
    let inserted = 0, updated = 0, errors = [];
    
    for (const spec of specs) {
      try {
        spec.created_by = created_by;
        spec.is_active = 1;
        
        const validationErrors = validateSpecItem(spec);
        if (validationErrors.length > 0) {
          errors.push({ row: `${spec.numero_parte} - ${spec.inspection_item}`, errors: validationErrors });
          continue;
        }
        
        if (spec.target_value === '') spec.target_value = null;
        if (spec.lsl === '') spec.lsl = null;
        if (spec.usl === '') spec.usl = null;
        
        const [existing] = await pool.query(
          'SELECT id FROM quality_specs WHERE numero_parte = ? AND spec_code = ? AND inspection_item = ?',
          [spec.numero_parte, spec.spec_code, spec.inspection_item]
        );
        
        if (existing.length > 0) {
          delete spec.created_by;
          await pool.query('UPDATE quality_specs SET ? WHERE id = ?', [spec, existing[0].id]);
          updated++;
        } else {
          await pool.query('INSERT INTO quality_specs SET ?', spec);
          inserted++;
        }
      } catch (e) {
        errors.push({ row: spec.numero_parte || 'unknown', errors: [e.message] });
      }
    }
    
    res.json({ inserted, updated, errors, total: specs.length });
  } catch (err) {
    next(err);
  }
};

// POST /api/quality-specs/copy - Copiar specs de un part number a otro
exports.copy = async (req, res, next) => {
  try {
    const { from_part, to_part, created_by } = req.body;
    
    const [targetMaterial] = await pool.query(
      'SELECT numero_parte FROM materiales WHERE numero_parte = ?', [to_part]
    );
    if (targetMaterial.length === 0) {
      return res.status(400).json({ error: 'Part number destino no existe en materiales' });
    }
    
    const [sourceSpecs] = await pool.query(
      'SELECT * FROM quality_specs WHERE numero_parte = ? AND is_active = 1', [from_part]
    );
    
    if (sourceSpecs.length === 0) {
      return res.status(400).json({ error: 'No hay specs en el part number origen' });
    }
    
    let inserted = 0;
    for (const spec of sourceSpecs) {
      const [existing] = await pool.query(
        'SELECT id FROM quality_specs WHERE numero_parte = ? AND spec_code = ? AND inspection_item = ?',
        [to_part, spec.spec_code, spec.inspection_item]
      );
      
      if (existing.length === 0) {
        delete spec.id;
        spec.numero_parte = to_part;
        spec.created_by = created_by;
        spec.created_at = new Date();
        await pool.query('INSERT INTO quality_specs SET ?', spec);
        inserted++;
      }
    }
    
    res.json({ copied: inserted, total: sourceSpecs.length });
  } catch (err) {
    next(err);
  }
};
