/**
 * Plan Controller - Plan de Producción y BOM
 * Pantalla Flutter: lib/screens/plan_main/
 */

const { pool } = require('../config/database');

// GET /api/plan/today - Obtiene planes del día actual
exports.getToday = async (req, res, next) => {
  try {
    const { date } = req.query;
    const targetDate = date || new Date().toISOString().split('T')[0];
    
    const [rows] = await pool.query(`
      SELECT 
        id,
        lot_no,
        wo_code,
        working_date,
        line,
        model_code,
        part_no,
        project,
        process,
        plan_count,
        status
      FROM plan_main 
      WHERE working_date = ?
      ORDER BY sequence, lot_no
    `, [targetDate]);
    res.json(rows);
  } catch (err) {
    next(err);
  }
};

// GET /api/plan/bom/:partNo - Obtiene el BOM de un part_no y multiplica por plan_count
exports.getBomByPartNo = async (req, res, next) => {
  try {
    const { partNo } = req.params;
    const { planCount } = req.query;
    const multiplier = parseInt(planCount) || 1;
    
    const [rows] = await pool.query(`
      SELECT 
        id,
        modelo,
        codigo_material,
        numero_parte,
        side,
        tipo_material,
        classification,
        especificacion_material,
        cantidad_total,
        cantidad_original
      FROM bom 
      WHERE modelo = ?
      ORDER BY side, codigo_material
    `, [partNo]);
    
    const bomWithMultiplied = rows.map(row => ({
      ...row,
      material_code: row.codigo_material,
      bom_qty: row.cantidad_total,
      required_qty: (parseFloat(row.cantidad_total) || 0) * multiplier,
      plan_count: multiplier
    }));
    
    res.json(bomWithMultiplied);
  } catch (err) {
    next(err);
  }
};

// GET /api/bom/models - Lista modelos únicos de la tabla bom
exports.getBomModels = async (req, res, next) => {
  try {
    const [rows] = await pool.query(`
      SELECT DISTINCT modelo 
      FROM bom 
      WHERE modelo IS NOT NULL AND modelo != ''
      ORDER BY modelo
    `);
    res.json(rows.map(r => r.modelo));
  } catch (err) {
    next(err);
  }
};

// GET /api/bom/:modelo - Obtiene el BOM de un modelo específico
exports.getBomByModelo = async (req, res, next) => {
  try {
    const { modelo } = req.params;
    const [rows] = await pool.query(`
      SELECT 
        id,
        modelo,
        codigo_material,
        numero_parte,
        side,
        tipo_material,
        classification,
        especificacion_material,
        vender,
        cantidad_total,
        cantidad_original,
        ubicacion,
        posicion_assy,
        material_sustituto,
        material_original,
        registrador,
        fecha_registro
      FROM bom 
      WHERE modelo = ?
      ORDER BY side, codigo_material
    `, [modelo]);
    res.json(rows);
  } catch (err) {
    next(err);
  }
};
