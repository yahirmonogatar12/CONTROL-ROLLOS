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

// GET /api/bom/search - Consulta BOM vigente por PCB/modelo, componente, spec o ubicacion
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
      const likeModelo = `%${modeloMatch ? modeloMatch[0] : rawModelo}%`;
      filters.push(`(
        b.root_part_no LIKE ?
        OR b.bom_part_no LIKE ?
      )`);
      params.push(likeModelo, likeModelo);
    }

    if (rawQuery) {
      const like = `%${rawQuery}%`;
      filters.push(`(
        b.root_part_no LIKE ?
        OR b.bom_part_no LIKE ?
        OR b.item_no LIKE ?
        OR b.alt_item_no LIKE ?
        OR b.item_name LIKE ?
        OR b.item_name_en LIKE ?
        OR b.spec LIKE ?
        OR b.alt_spec LIKE ?
        OR b.location_text LIKE ?
        OR b.item_class LIKE ?
        OR b.process_name LIKE ?
        OR b.item_process LIKE ?
        OR b.maker LIKE ?
        ${pcbMatch ? 'OR b.root_part_no = ? OR b.bom_part_no LIKE ?' : ''}
      )`);
      params.push(
        like,
        like,
        like,
        like,
        like,
        like,
        like,
        like,
        like,
        like,
        like,
        like,
        like
      );
      if (pcbMatch) params.push(pcbMatch[0], `${pcbMatch[0]}%`);
    }

    if (side && side !== 'ALL') {
      filters.push('(b.bom_suffix = ? OR b.bom_kind = ?)');
      params.push(side);
      params.push(side);
    }

    if (tipo_material && tipo_material !== 'ALL') {
      filters.push('b.process_name = ?');
      params.push(tipo_material);
    }

    if (classification && classification !== 'ALL') {
      filters.push('b.item_class = ?');
      params.push(classification);
    }

    const whereClause = filters.length > 0 ? `AND ${filters.join(' AND ')}` : '';

    params.push(maxLimit);

    const [rows] = await pool.query(
      `
      SELECT
        b.item_seq AS id,
        b.root_part_no AS modelo,
        b.bom_part_no AS codigo_material,
        b.item_no AS numero_parte,
        b.bom_kind AS side,
        b.process_name AS tipo_material,
        b.item_class AS classification,
        b.spec AS especificacion_material,
        b.maker AS vender,
        b.qty AS cantidad_total,
        b.qty AS cantidad_original,
        b.location_text AS ubicacion,
        b.alt_item_no AS material_sustituto,
        b.item_no AS material_original,
        b.bom_part_no,
        b.bom_kind,
        b.bom_rev,
        b.item_name,
        b.item_name_en,
        b.unit,
        b.item_process,
        b.alt_spec,
        b.alt_item_name,
        b.alt_maker
      FROM v_ecos_bom_current b
      WHERE 1=1
      ${whereClause}
      ORDER BY b.root_part_no, b.bom_rev, b.location_text, b.item_no
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
