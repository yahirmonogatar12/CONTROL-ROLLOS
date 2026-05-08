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

// GET /api/bom/search - Consulta BOM por PCB/modelo, componente, spec o ubicacion
exports.searchBom = async (req, res, next) => {
  try {
    const {
      q,
      modelo,
      side,
      tipo_material,
      classification,
      limit,
    } = req.query;

    const maxLimit = Math.min(parseInt(limit, 10) || 500, 2000);
    const filters = [];
    const params = [];

    const rawQuery = (q || '').toString().trim();
    const pcbMatch = rawQuery.toUpperCase().match(/EBR\d{8}/);
    const rawModelo = (modelo || '').toString().trim();
    const modeloMatch = rawModelo.toUpperCase().match(/EBR\d{8}/);

    if (rawModelo) {
      filters.push('b.modelo LIKE ?');
      params.push(`%${modeloMatch ? modeloMatch[0] : rawModelo}%`);
    }

    if (rawQuery) {
      const like = `%${rawQuery}%`;
      filters.push(`(
        b.modelo LIKE ?
        OR b.codigo_material LIKE ?
        OR b.numero_parte LIKE ?
        OR b.especificacion_material LIKE ?
        OR b.ubicacion LIKE ?
        OR b.classification LIKE ?
        OR b.tipo_material LIKE ?
        ${pcbMatch ? 'OR b.modelo = ?' : ''}
      )`);
      params.push(like, like, like, like, like, like, like);
      if (pcbMatch) params.push(pcbMatch[0]);
    }

    if (side && side !== 'ALL') {
      filters.push('b.side = ?');
      params.push(side);
    }

    if (tipo_material && tipo_material !== 'ALL') {
      filters.push('b.tipo_material = ?');
      params.push(tipo_material);
    }

    if (classification && classification !== 'ALL') {
      filters.push('b.classification = ?');
      params.push(classification);
    }

    const whereClause = filters.length > 0 ? `WHERE ${filters.join(' AND ')}` : '';

    params.push(maxLimit);

    const [rows] = await pool.query(
      `
      SELECT
        b.id,
        b.modelo,
        b.codigo_material,
        b.numero_parte,
        b.side,
        b.tipo_material,
        b.classification,
        b.especificacion_material,
        b.vender,
        b.cantidad_total,
        b.cantidad_original,
        b.ubicacion,
        b.material_sustituto,
        b.material_original
      FROM bom b
      ${whereClause}
      ORDER BY b.modelo, b.side, b.ubicacion, b.numero_parte
      LIMIT ?
      `,
      params
    );

    res.json({
      success: true,
      data: rows,
      count: rows.length,
      limit: maxLimit,
    });
  } catch (err) {
    next(err);
  }
};
