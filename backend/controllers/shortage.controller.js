/**
 * Shortage Controller - Calculo de Faltante de Material SMD
 * Compara demanda del plan de produccion vs inventario disponible
 * Toma en cuenta standard_pack: cada linea necesita sus propios rollos
 */

const { pool } = require('../config/database');

// GET /api/shortage?date=YYYY-MM-DD&line=X
exports.calculate = async (req, res, next) => {
  try {
    const { date, line } = req.query;
    if (!date) return res.status(400).json({ error: 'date parameter is required' });

    // Paso 1: Plan agrupado por modelo Y linea (para calcular rollos por linea)
    let planQuery = `
      SELECT part_no, line, SUM(plan_count) as plan_count
      FROM plan_smt
      WHERE working_date = ?
    `;
    const planParams = [date];
    if (line) {
      planQuery += ' AND line = ?';
      planParams.push(line);
    }
    planQuery += ' GROUP BY part_no, line';
    const [planRows] = await pool.query(planQuery, planParams);

    if (planRows.length === 0) {
      return res.json({
        date,
        line: line || 'ALL',
        plan_lines: 0,
        total_components: 0,
        shortage_count: 0,
        items: [],
      });
    }

    // Paso 1b: Normalizar modelos con sufijo de lado PCB (B=Bottom, T=Top)
    // EBR76683907B y EBR76683907T -> base EBR76683907
    // Se unifican ambos lados para buscar BOM con el modelo base
    const sidesByBase = {};    // { base: Set('B','T') }
    const originalToBase = {}; // { 'EBR76683907B': 'EBR76683907' }

    function getBaseModel(partNo) {
      // Si termina en letra, quitar la letra
      const match = partNo.match(/^(.+[0-9])([A-Za-z])$/);
      if (match) {
        return { base: match[1], side: match[2].toUpperCase() };
      }
      return { base: partNo, side: null };
    }

    // Crear lookup: modelo_base -> { total, byLine: { lineX: qty } }
    const planLookup = {};
    const uniqueModels = new Set();       // modelos base para BOM
    const uniqueOriginals = new Set();    // modelos originales del plan

    for (const p of planRows) {
      uniqueOriginals.add(p.part_no);
      const { base, side } = getBaseModel(p.part_no);
      originalToBase[p.part_no] = base;

      if (side) {
        if (!sidesByBase[base]) sidesByBase[base] = new Set();
        sidesByBase[base].add(side);
      }

      uniqueModels.add(base);
      if (!planLookup[base]) {
        planLookup[base] = { total: 0, byLine: {} };
      }
      const qty = parseFloat(p.plan_count) || 0;
      planLookup[base].total += qty;
      planLookup[base].byLine[p.line] = (planLookup[base].byLine[p.line] || 0) + qty;
    }

    // Detectar modelos con solo un lado (falta B o T)
    const modelsWithMissingSide = [];
    for (const [base, sides] of Object.entries(sidesByBase)) {
      if (sides.size === 1) {
        const existing = [...sides][0];
        const missing = existing === 'B' ? 'T' : 'B';
        modelsWithMissingSide.push({ model: base, existing, missing });
      }
    }

    // Paso 2: BOM por modelos base (batch) - solo classification = 'SMD'
    const modelList = [...uniqueModels];
    const modelPlaceholders = modelList.map(() => '?').join(',');

    const [bomRows] = await pool.query(`
      SELECT
        b.numero_parte,
        b.modelo,
        b.cantidad_total,
        b.especificacion_material
      FROM bom b
      WHERE b.modelo IN (${modelPlaceholders})
        AND b.classification = 'SMD'
    `, modelList);

    // demand: { partNo: { required_qty, byLine: { lineX: qty }, models: Set, bom_spec: string } }
    const demand = {};

    // Modelos base que SI tienen BOM
    const modelsWithBom = new Set();
    for (const bom of bomRows) {
      modelsWithBom.add(bom.modelo);
      const partNo = bom.numero_parte;
      const bomQty = parseFloat(bom.cantidad_total) || 0;
      const plan = planLookup[bom.modelo];
      if (!plan) continue;

      if (!demand[partNo]) {
        demand[partNo] = { required_qty: 0, byLine: {}, models: new Set(), bom_spec: '' };
      }
      demand[partNo].required_qty += bomQty * plan.total;
      demand[partNo].models.add(bom.modelo);

      // Acumular demanda por linea
      for (const [ln, planQty] of Object.entries(plan.byLine)) {
        demand[partNo].byLine[ln] = (demand[partNo].byLine[ln] || 0) + bomQty * planQty;
      }

      if (!demand[partNo].bom_spec && bom.especificacion_material) {
        demand[partNo].bom_spec = bom.especificacion_material;
      }
    }

    // Paso 2b: Fallback a CONSUMO para modelos sin BOM
    const modelsWithoutBom = modelList.filter(m => !modelsWithBom.has(m));

    const modelsWithConsumo = new Set();
    if (modelsWithoutBom.length > 0) {
      try {
        const consumoPlaceholders = modelsWithoutBom.map(() => '?').join(',');
        const [consumoRows] = await pool.query(`
          SELECT Codigo, Part_No_Componente, Cantidad_Consumo
          FROM CONSUMO
          WHERE Codigo IN (${consumoPlaceholders})
            AND Tipo_Proceso = 'SMD'
        `, modelsWithoutBom);

        for (const c of consumoRows) {
          modelsWithConsumo.add(c.Codigo);
          const partNo = c.Part_No_Componente;
          const bomQty = parseFloat(c.Cantidad_Consumo) || 0;
          const plan = planLookup[c.Codigo];
          if (!plan) continue;

          if (!demand[partNo]) {
            demand[partNo] = { required_qty: 0, byLine: {}, models: new Set(), bom_spec: '' };
          }
          demand[partNo].required_qty += bomQty * plan.total;
          demand[partNo].models.add(c.Codigo);

          for (const [ln, planQty] of Object.entries(plan.byLine)) {
            demand[partNo].byLine[ln] = (demand[partNo].byLine[ln] || 0) + bomQty * planQty;
          }
        }
      } catch (e) {
        console.log('CONSUMO fallback error, skipping:', e.message);
      }
    }

    // Modelos sin BOM ni CONSUMO
    const modelsWithoutData = modelsWithoutBom.filter(m => !modelsWithConsumo.has(m));

    const partNumbers = Object.keys(demand);
    if (partNumbers.length === 0) {
      return res.json({
        date,
        line: line || 'ALL',
        plan_lines: uniqueModels.size,
        total_components: 0,
        shortage_count: 0,
        items: [],
      });
    }

    // Paso 3: Resolver equivalencias (batch)
    const equivPlaceholders = partNumbers.map(() => '?').join(',');
    let equivalenceMap = {};

    try {
      const [groupRows] = await pool.query(`
        SELECT original_part_no, reemplazo_part_no, grupo_id
        FROM equivalentes_materiales
        WHERE activo = 1
          AND (original_part_no IN (${equivPlaceholders})
               OR reemplazo_part_no IN (${equivPlaceholders}))
      `, [...partNumbers, ...partNumbers]);

      if (groupRows.length > 0) {
        const groupIds = [...new Set(groupRows.map(r => r.grupo_id))];
        const groupPlaceholders = groupIds.map(() => '?').join(',');
        const [allEquivRows] = await pool.query(`
          SELECT original_part_no, reemplazo_part_no, grupo_id
          FROM equivalentes_materiales
          WHERE activo = 1
            AND grupo_id IN (${groupPlaceholders})
        `, groupIds);

        const groupMembers = {};
        for (const row of allEquivRows) {
          if (!groupMembers[row.grupo_id]) groupMembers[row.grupo_id] = new Set();
          groupMembers[row.grupo_id].add(row.original_part_no);
          groupMembers[row.grupo_id].add(row.reemplazo_part_no);
        }

        const partToGroup = {};
        for (const row of allEquivRows) {
          partToGroup[row.original_part_no] = row.grupo_id;
          partToGroup[row.reemplazo_part_no] = row.grupo_id;
        }

        for (const partNo of partNumbers) {
          const groupId = partToGroup[partNo];
          if (groupId && groupMembers[groupId]) {
            equivalenceMap[partNo] = [...groupMembers[groupId]];
          } else {
            equivalenceMap[partNo] = [partNo];
          }
        }
      }
    } catch (e) {
      console.log('equivalentes_materiales query error, skipping:', e.message);
    }

    for (const partNo of partNumbers) {
      if (!equivalenceMap[partNo]) {
        equivalenceMap[partNo] = [partNo];
      }
    }

    // Paso 4: Inventario (batch)
    const allPartNos = new Set();
    for (const parts of Object.values(equivalenceMap)) {
      parts.forEach(p => allPartNos.add(p));
    }
    partNumbers.forEach(p => allPartNos.add(p));

    const allPartNosList = [...allPartNos];
    const invPlaceholders = allPartNosList.map(() => '?').join(',');
    const [invRows] = await pool.query(`
      SELECT numero_parte, SUM(stock_actual) as stock
      FROM inventario_lotes_smd
      WHERE numero_parte IN (${invPlaceholders})
      GROUP BY numero_parte
    `, allPartNosList);

    const stockMap = {};
    for (const row of invRows) {
      stockMap[row.numero_parte] = parseFloat(row.stock) || 0;
    }

    // Paso 5: Standard pack + spec desde tabla materiales (batch)
    const materialMap = {};
    try {
      const matPlaceholders = allPartNosList.map(() => '?').join(',');
      const [matRows] = await pool.query(`
        SELECT numero_parte,
               IFNULL(unidad_empaque, 0) as standard_pack,
               especificacion_material
        FROM materiales
        WHERE numero_parte IN (${matPlaceholders})
      `, allPartNosList);

      for (const row of matRows) {
        materialMap[row.numero_parte] = {
          standard_pack: parseInt(row.standard_pack) || 0,
          spec: row.especificacion_material || '',
        };
      }
    } catch (e) {
      console.log('Materiales query error:', e.message);
    }

    // Paso 6: Calcular faltante con logica de rollos por linea
    const results = partNumbers.map(partNo => {
      const info = demand[partNo];
      const equivParts = equivalenceMap[partNo] || [partNo];

      let totalStock = 0;
      const stockBreakdown = [];
      for (const ep of equivParts) {
        const s = stockMap[ep] || 0;
        totalStock += s;
        if (s > 0) stockBreakdown.push({ part: ep, stock: s });
      }

      // Spec y standard_pack: buscar en parte original + equivalentes
      let spec = '';
      let standardPack = 0;
      for (const ep of equivParts) {
        const mat = materialMap[ep];
        if (mat) {
          if (!spec && mat.spec) spec = mat.spec;
          if (!standardPack && mat.standard_pack) standardPack = mat.standard_pack;
          if (spec && standardPack) break;
        }
      }
      if (!spec) spec = info.bom_spec || '';

      // Calcular rollos necesarios por linea
      let reelsNeeded = 0;
      let adjustedRequired = info.required_qty;

      if (standardPack > 0) {
        // Cada linea necesita sus propios rollos (no se comparten)
        for (const [ln, lineQty] of Object.entries(info.byLine)) {
          const lineReels = Math.ceil(lineQty / standardPack);
          reelsNeeded += lineReels;
        }
        adjustedRequired = reelsNeeded * standardPack;
      }

      const shortage = Math.round((adjustedRequired - totalStock) * 100) / 100;

      return {
        numero_parte: partNo,
        especificacion: spec,
        required_qty: Math.round(info.required_qty * 100) / 100,
        adjusted_qty: Math.round(adjustedRequired * 100) / 100,
        standard_pack: standardPack,
        reels_needed: reelsNeeded,
        equivalent_parts: equivParts.filter(p => p !== partNo),
        available_stock: totalStock,
        stock_breakdown: stockBreakdown,
        shortage: shortage,
        status: shortage > 0 ? 'SHORTAGE' : 'OK',
        models: [...info.models],
        lines_used: Object.keys(info.byLine),
      };
    });

    // Ordenar: faltantes primero
    results.sort((a, b) => b.shortage - a.shortage);

    res.json({
      date,
      line: line || 'ALL',
      plan_lines: uniqueModels.size,
      total_components: results.length,
      shortage_count: results.filter(r => r.status === 'SHORTAGE').length,
      models_without_data: modelsWithoutData,
      models_with_missing_side: modelsWithMissingSide,
      items: results,
    });
  } catch (err) {
    console.error('Shortage calculate error:', err.message, err.sql || '');
    next(err);
  }
};

// GET /api/shortage/lines?date=YYYY-MM-DD
exports.getLines = async (req, res, next) => {
  try {
    const { date } = req.query;
    if (!date) return res.status(400).json({ error: 'date parameter is required' });

    const [rows] = await pool.query(
      'SELECT DISTINCT line FROM plan_smt WHERE working_date = ? ORDER BY line',
      [date]
    );
    res.json(rows.map(r => r.line));
  } catch (err) {
    next(err);
  }
};
