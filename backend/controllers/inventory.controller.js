/**
 * Inventory Controller - Inventario de Lotes
 * Pantalla Flutter: lib/screens/inventory/
 */

const { pool } = require('../config/database');

// GET /api/inventory/summary - Inventario agrupado por numero_parte
exports.getSummary = async (req, res, next) => {
  try {
    const { numero_parte, include_zero_stock, fecha_inicio, fecha_fin } = req.query;
    const includeZero = include_zero_stock === 'true';
    const params = [];
    
    // Si hay rango de fechas, calcular inventario histórico
    if (fecha_inicio && fecha_fin) {
      // Ajustar fechas para incluir todo el día
      const fechaInicioCompleta = `${fecha_inicio} 00:00:00`;
      const fechaFinCompleta = `${fecha_fin} 23:59:59`;
      
      // Entradas/Salidas: Solo del período especificado (para ver movimiento)
      // Stock: Inventario REAL al final del período (todas entradas hasta fecha_fin - todas salidas hasta fecha_fin)
      let query = `
        SELECT
          cma.numero_parte,
          MAX(COALESCE(m.especificacion_material, cma.especificacion)) as especificacion,
          SUM(CASE WHEN cma.fecha_recibo BETWEEN ? AND ? THEN cma.cantidad_actual ELSE 0 END) AS total_entrada,
          COALESCE(SUM(cms_periodo.cantidad_salida), 0) AS total_salida,
          (SUM(CASE WHEN cma.fecha_recibo <= ? THEN cma.cantidad_actual ELSE 0 END) - COALESCE(SUM(cms_historico.cantidad_salida), 0)) AS stock_total,
          COUNT(DISTINCT CASE WHEN cma.fecha_recibo BETWEEN ? AND ? THEN cma.numero_lote_material END) AS lotes_distintos,
          SUM(CASE WHEN (CASE WHEN cma.fecha_recibo <= ? THEN cma.cantidad_actual ELSE 0 END - COALESCE(cms_historico.sal_individual, 0)) > 0 THEN 1 ELSE 0 END) AS lotes_con_stock,
          MAX(IFNULL(m.unidad_medida, 'EA')) as unidad_medida
        FROM control_material_almacen_smd cma
        LEFT JOIN materiales m ON cma.numero_parte = m.numero_parte
        LEFT JOIN (
          SELECT codigo_material_recibido, SUM(cantidad_salida) as cantidad_salida
          FROM control_material_salida_smd
          WHERE fecha_salida BETWEEN ? AND ? AND (cancelado = 0 OR cancelado IS NULL)
          GROUP BY codigo_material_recibido
        ) cms_periodo ON cma.codigo_material_recibido = cms_periodo.codigo_material_recibido
        LEFT JOIN (
          SELECT codigo_material_recibido, SUM(cantidad_salida) as cantidad_salida, SUM(cantidad_salida) as sal_individual
          FROM control_material_salida_smd
          WHERE fecha_salida <= ? AND (cancelado = 0 OR cancelado IS NULL)
          GROUP BY codigo_material_recibido
        ) cms_historico ON cma.codigo_material_recibido = cms_historico.codigo_material_recibido
        WHERE cma.cancelado = 0
          AND cma.iqc_status IN ('Released', 'NotRequired')
          AND (
            cma.fecha_recibo BETWEEN ? AND ?
            OR cms_periodo.codigo_material_recibido IS NOT NULL
          )
      `;
      params.push(
        fechaInicioCompleta, fechaFinCompleta,  // para total_entrada (período)
        fechaFinCompleta,                        // para stock_total (entradas hasta fecha_fin)
        fechaInicioCompleta, fechaFinCompleta,  // para lotes_distintos
        fechaFinCompleta,                        // para lotes_con_stock
        fechaInicioCompleta, fechaFinCompleta,  // para cms_periodo (salidas del período)
        fechaFinCompleta,                        // para cms_historico (salidas hasta fecha_fin)
        fechaInicioCompleta, fechaFinCompleta   // para fecha_recibo en WHERE
      );
      
      if (numero_parte) {
        query += ` AND cma.numero_parte LIKE ?`;
        params.push(`%${numero_parte}%`);
      }
      
      query += ` GROUP BY cma.numero_parte`;
      if (!includeZero) {
        query += ` HAVING stock_total > 0`;
      }
      query += ` ORDER BY cma.numero_parte`;
      
      const [rows] = await pool.query(query, params);
      return res.json(rows);
    }
    
    // Inventario actual desde inventario_lotes_smd
    let query = `
      SELECT
        il.numero_parte,
        MAX(COALESCE(m.especificacion_material, cma.especificacion)) as especificacion,
        SUM(il.total_entrada) AS total_entrada,
        SUM(il.total_salida) AS total_salida,
        SUM(il.stock_actual) AS stock_total,
        COUNT(DISTINCT il.numero_lote) AS lotes_distintos,
        SUM(CASE WHEN il.stock_actual > 0 THEN 1 ELSE 0 END) AS lotes_con_stock,
        MAX(IFNULL(m.unidad_medida, 'EA')) as unidad_medida,
        MAX(COALESCE(cma.ubicacion_destino, cma.ubicacion_salida)) as ubicacion
      FROM inventario_lotes_smd il
      LEFT JOIN control_material_almacen_smd cma ON il.codigo_material_recibido = cma.codigo_material_recibido
      LEFT JOIN materiales m ON il.numero_parte = m.numero_parte
    `;
    
    if (numero_parte) {
      query += ` WHERE il.numero_parte LIKE ?`;
      params.push(`%${numero_parte}%`);
    }
    
    query += ` GROUP BY il.numero_parte`;
    if (!includeZero) {
      query += ` HAVING stock_total > 0`;
    }
    query += ` ORDER BY il.numero_parte`;
    
    const [rows] = await pool.query(query, params);
    res.json(rows);
  } catch (err) {
    next(err);
  }
};

// GET /api/inventory/lots - Detalle de lotes con info de warehousing
exports.getLots = async (req, res, next) => {
  try {
    const { numero_parte, codigo_material_recibido, include_zero_stock, fecha_inicio, fecha_fin } = req.query;
    const includeZero = include_zero_stock === 'true';
    const params = [];
    
    console.log('📊 getLots params:', { numero_parte, codigo_material_recibido, include_zero_stock, fecha_inicio, fecha_fin });
    
    // detectar si la columna en_cuarentena existe en control_material_almacen_smd (evita errores en instalaciones parciales)
    const [[colCheck]] = await pool.query(
      `SELECT COUNT(*) AS cnt FROM INFORMATION_SCHEMA.COLUMNS
       WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'control_material_almacen_smd' AND COLUMN_NAME = 'en_cuarentena'`
    );
    const enCuarentenaExpr = colCheck && colCheck.cnt ? `COALESCE(cma.en_cuarentena, 0) as in_quarantine` : `0 as in_quarantine`;

    // Si hay rango de fechas, calcular inventario histórico
    if (fecha_inicio && fecha_fin) {
      // Ajustar fecha_fin para incluir todo el día (hasta 23:59:59)
      const fechaInicioCompleta = `${fecha_inicio} 00:00:00`;
      const fechaFinCompleta = `${fecha_fin} 23:59:59`;
      
      console.log('🗓️ Usando filtro de fechas:', fechaInicioCompleta, 'a', fechaFinCompleta);
      // Entradas/Salidas: Solo del período especificado (para ver movimiento)
      // Stock: Inventario REAL al final del período (todas entradas hasta fecha_fin - todas salidas hasta fecha_fin)
      let query = `
        SELECT
          cma.numero_parte,
          cma.numero_lote_material as numero_lote,
          cma.codigo_material_recibido,
          CASE WHEN cma.fecha_recibo BETWEEN ? AND ? THEN cma.cantidad_actual ELSE 0 END as total_entrada,
          COALESCE(cms_periodo.cantidad_salida, 0) as total_salida,
          (CASE WHEN cma.fecha_recibo <= ? THEN cma.cantidad_actual ELSE 0 END - COALESCE(cms_historico.cantidad_salida, 0)) as stock_actual,
          cma.id as warehousing_id,
          cma.codigo_material,
          COALESCE(m.especificacion_material, cma.especificacion) as especificacion,
          ${enCuarentenaExpr},
          IFNULL(m.unidad_medida, 'EA') as unidad_medida,
          COALESCE(cma.ubicacion_destino, cma.ubicacion_salida) as ubicacion,
          DATE_FORMAT(cma.fecha_recibo, '%Y-%m-%d') as fecha_recibo,
          cms_periodo.ultima_fecha_salida as fecha_salida,
          cma.usuario_registro as usuario_entrada,
          cms_periodo.usuario_salida as usuario_salida
        FROM control_material_almacen_smd cma
        LEFT JOIN materiales m ON cma.numero_parte = m.numero_parte
        LEFT JOIN (
          SELECT codigo_material_recibido, 
                 SUM(cantidad_salida) as cantidad_salida,
                 MAX(DATE_FORMAT(fecha_salida, '%Y-%m-%d')) as ultima_fecha_salida,
                 MAX(usuario_registro) as usuario_salida
          FROM control_material_salida_smd
          WHERE fecha_salida BETWEEN ? AND ? AND (cancelado = 0 OR cancelado IS NULL)
          GROUP BY codigo_material_recibido
        ) cms_periodo ON cma.codigo_material_recibido = cms_periodo.codigo_material_recibido
        LEFT JOIN (
          SELECT codigo_material_recibido, 
                 SUM(cantidad_salida) as cantidad_salida
          FROM control_material_salida_smd
          WHERE fecha_salida <= ? AND (cancelado = 0 OR cancelado IS NULL)
          GROUP BY codigo_material_recibido
        ) cms_historico ON cma.codigo_material_recibido = cms_historico.codigo_material_recibido
        WHERE cma.cancelado = 0
          AND cma.iqc_status IN ('Released', 'NotRequired')
          AND (
            cma.fecha_recibo BETWEEN ? AND ?
            OR cms_periodo.codigo_material_recibido IS NOT NULL
          )
      `;
      params.push(
        fechaInicioCompleta, fechaFinCompleta,  // para total_entrada CASE (período)
        fechaFinCompleta,                        // para stock_actual (entradas hasta fecha_fin)
        fechaInicioCompleta, fechaFinCompleta,  // para cms_periodo subquery
        fechaFinCompleta,                        // para cms_historico subquery
        fechaInicioCompleta, fechaFinCompleta   // para fecha_recibo en WHERE
      );
      
      if (!includeZero) {
        query += ` AND (CASE WHEN cma.fecha_recibo <= '${fechaFinCompleta}' THEN cma.cantidad_actual ELSE 0 END - COALESCE(cms_historico.cantidad_salida, 0)) > 0`;
      }
      
      if (numero_parte) {
        query += ` AND cma.numero_parte LIKE ?`;
        params.push(`%${numero_parte}%`);
      }
      
      if (codigo_material_recibido) {
        query += ` AND cma.codigo_material_recibido LIKE ?`;
        params.push(`%${codigo_material_recibido}%`);
      }
      
      query += ` ORDER BY cma.numero_parte, cma.numero_lote_material`;
      
      console.log('🔍 Query con fechas:', query);
      console.log('📌 Params:', params);
      
      const [rows] = await pool.query(query, params);
      console.log('📋 Resultados con filtro de fecha:', rows.length);
      return res.json(rows);
    }
    
    // Inventario actual desde inventario_lotes_smd
    console.log('📦 Usando inventario actual (sin filtro de fechas)');
    let query = `
      SELECT
        il.numero_parte,
        il.numero_lote,
        il.codigo_material_recibido,
        il.total_entrada,
        il.total_salida,
        il.stock_actual,
        cma.id as warehousing_id,
        cma.codigo_material,
        COALESCE(m.especificacion_material, cma.especificacion) as especificacion,
        ${enCuarentenaExpr},
        IFNULL(m.unidad_medida, 'EA') as unidad_medida,
        COALESCE(cma.ubicacion_destino, cma.ubicacion_salida) as ubicacion,
        DATE_FORMAT(cma.fecha_recibo, '%Y-%m-%d') as fecha_recibo,
        (
          SELECT MAX(DATE_FORMAT(fecha_salida, '%Y-%m-%d'))
          FROM control_material_salida_smd cms
          WHERE cms.codigo_material_recibido = il.codigo_material_recibido
            AND (cms.cancelado = 0 OR cms.cancelado IS NULL)
        ) as fecha_salida,
        cma.usuario_registro as usuario_entrada,
        (
          SELECT MAX(usuario_registro)
          FROM control_material_salida_smd cms
          WHERE cms.codigo_material_recibido = il.codigo_material_recibido
            AND (cms.cancelado = 0 OR cms.cancelado IS NULL)
        ) as usuario_salida
      FROM inventario_lotes_smd il
      LEFT JOIN control_material_almacen_smd cma ON il.codigo_material_recibido = cma.codigo_material_recibido
      LEFT JOIN materiales m ON il.numero_parte = m.numero_parte
    `;
    
    const whereConditions = [];
    if (!includeZero) {
      whereConditions.push('il.stock_actual > 0');
    }
    
    if (numero_parte) {
      whereConditions.push('il.numero_parte LIKE ?');
      params.push(`%${numero_parte}%`);
    }
    
    if (codigo_material_recibido) {
      whereConditions.push('il.codigo_material_recibido LIKE ?');
      params.push(`%${codigo_material_recibido}%`);
    }
    
    if (whereConditions.length > 0) {
      query += ` WHERE ${whereConditions.join(' AND ')}`;
    }
    
    query += ` ORDER BY il.numero_parte, il.numero_lote`;
    
    const [rows] = await pool.query(query, params);
    res.json(rows);
  } catch (err) {
    next(err);
  }
};

// GET /api/inventory/search-label - Buscar por etiqueta exacta
exports.searchByLabel = async (req, res, next) => {
  try {
    const { codigo } = req.query;
    
    if (!codigo) {
      return res.json([]);
    }
    
    const [rows] = await pool.query(`
      SELECT
        codigo_material_recibido,
        numero_parte,
        numero_lote,
        total_entrada,
        total_salida,
        stock_actual
      FROM inventario_lotes_smd
      WHERE codigo_material_recibido = ?
    `, [codigo]);
    
    res.json(rows);
  } catch (err) {
    next(err);
  }
};

// GET /api/inventory/location-search - Buscar ubicación por numero de parte
// Soporta: codigo completo (EAE63746601-202601230002), numero de parte exacto o parcial
exports.locationSearch = async (req, res, next) => {
  try {
    const { numero_parte } = req.query;
    
    if (!numero_parte) {
      return res.status(400).json({ error: 'numero_parte es requerido' });
    }
    
    let nparte = numero_parte.trim().toUpperCase();
    
    // Si viene con formato barcode NPARTE-LOTE, extraer solo NPARTE
    if (nparte.includes('-')) {
      nparte = nparte.split('-')[0];
    }
    
    // 1. Buscar en tabla materiales - exacto primero, si no hay resultados buscar con LIKE
    let [matRows] = await pool.query(`
      SELECT numero_parte, ubicacion_rollos, ubicacion_material, 
             especificacion_material AS especificacion, vendedor
      FROM materiales
      WHERE numero_parte = ?
    `, [nparte]);
    
    // Si no hay match exacto, buscar coincidencias parciales
    if (matRows.length === 0) {
      [matRows] = await pool.query(`
        SELECT numero_parte, ubicacion_rollos, ubicacion_material, 
               especificacion_material AS especificacion, vendedor
        FROM materiales
        WHERE numero_parte LIKE ?
        ORDER BY numero_parte
        LIMIT 20
      `, [`%${nparte}%`]);
    }
    
    if (matRows.length === 0) {
      return res.status(404).json({ error: 'Número de parte no encontrado en materiales' });
    }
    
    // 2. Para cada material encontrado, buscar ubicaciones registradas
    const results = [];
    for (const mat of matRows) {
      const [ubicRows] = await pool.query(`
        SELECT DISTINCT COALESCE(ubicacion_destino, ubicacion_salida) AS ubicacion
        FROM control_material_almacen_smd
        WHERE numero_parte = ?
          AND cancelado = 0
          AND COALESCE(ubicacion_destino, ubicacion_salida) IS NOT NULL
          AND COALESCE(ubicacion_destino, ubicacion_salida) != ''
        ORDER BY ubicacion
        LIMIT 10
      `, [mat.numero_parte]);
      
      results.push({
        numero_parte: mat.numero_parte,
        ubicacion_rollos: mat.ubicacion_rollos || '',
        ubicacion_material: mat.ubicacion_material || '',
        especificacion: mat.especificacion || '',
        vendedor: mat.vendedor || '',
        ubicaciones_registradas: ubicRows.map(r => r.ubicacion),
      });
    }
    
    res.json(results);
  } catch (err) {
    next(err);
  }
};

// GET /api/inventory/mobile-search - Busqueda compacta para movil
exports.mobileSearch = async (req, res, next) => {
  try {
    const rawQuery = String(req.query.q || '').trim();
    if (!rawQuery) {
      return res.status(400).json({ error: 'q es requerido' });
    }

    const normalizedQuery = rawQuery.toUpperCase();
    const dashIndex = normalizedQuery.lastIndexOf('-');
    const partQuery = dashIndex > 0 &&
            /^\d{8,}$/.test(normalizedQuery.substring(dashIndex + 1))
        ? normalizedQuery.substring(0, dashIndex)
        : normalizedQuery;

    const [exactRows] = await pool.query(`
      SELECT
        il.numero_parte,
        COALESCE(m.especificacion_material, cma.especificacion) AS material_description,
        il.stock_actual AS stock_total,
        1 AS lotes_distintos,
        IFNULL(m.unidad_medida, 'EA') AS unidad_medida,
        COALESCE(cma.ubicacion_destino, cma.ubicacion_salida) AS ubicacion,
        il.codigo_material_recibido
      FROM inventario_lotes_smd il
      LEFT JOIN control_material_almacen_smd cma ON il.codigo_material_recibido = cma.codigo_material_recibido
      LEFT JOIN materiales m ON il.numero_parte = m.numero_parte
      WHERE UPPER(il.codigo_material_recibido) = ?
        AND il.stock_actual > 0
      ORDER BY il.stock_actual DESC
      LIMIT 20
    `, [normalizedQuery]);

    if (exactRows.length > 0) {
      return res.json({
        success: true,
        query: rawQuery,
        match_type: 'label',
        results: exactRows
      });
    }

    const [summaryRows] = await pool.query(`
      SELECT
        il.numero_parte,
        MAX(COALESCE(m.especificacion_material, cma.especificacion)) AS material_description,
        SUM(il.stock_actual) AS stock_total,
        COUNT(DISTINCT il.numero_lote) AS lotes_distintos,
        MAX(IFNULL(m.unidad_medida, 'EA')) AS unidad_medida,
        MAX(COALESCE(cma.ubicacion_destino, cma.ubicacion_salida)) AS ubicacion
      FROM inventario_lotes_smd il
      LEFT JOIN control_material_almacen_smd cma ON il.codigo_material_recibido = cma.codigo_material_recibido
      LEFT JOIN materiales m ON il.numero_parte = m.numero_parte
      WHERE il.stock_actual > 0
        AND UPPER(il.numero_parte) LIKE ?
      GROUP BY il.numero_parte
      ORDER BY (UPPER(il.numero_parte) = ?) DESC, il.numero_parte
      LIMIT 50
    `, [`%${partQuery}%`, partQuery]);

    res.json({
      success: true,
      query: rawQuery,
      match_type: 'part',
      results: summaryRows
    });
  } catch (err) {
    next(err);
  }
};
