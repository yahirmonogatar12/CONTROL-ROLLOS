'use strict';

const { pool } = require('../config/database');

const LIFECYCLE_STATUSES = ['ACTIVE', 'SCRAP', 'REPAIR', 'RETIRED'];

function normalizeCode(value) {
  return String(value || '').trim().toUpperCase();
}

// El No PCB llega con la version pegada y en formatos que no son uniformes:
// EAX67860915-1.0, EAX67860917 1.0, EAX01882201-D, EAX69871901 VER D e incluso
// EAX67445308-1.0 TOP. El BOM tambien trae version (EAX65150407-1.0). Lo que
// identifica al PCB es la base -- prefijo alfabetico + digitos -- asi que ambos
// lados se recortan ahi para poder compararlos.
function normalizePcbNo(value) {
  const raw = String(value || '').trim().toUpperCase();
  if (!raw) return null;
  const base = raw.match(/^([A-Z]+\d+)(?:[\s-]|$)/);
  if (base) return base[1];
  // Formato inesperado: se recorta solo una version numerica al final antes
  // que devolver algo mutilado.
  return raw.replace(/[\s-]+\d+(?:\.\d+)*$/, '').trim() || null;
}

// Limite 0/NULL = sin limite. El conteo sube por plan_count al autorizar.
function isLimitReached(asset) {
  const limit = Number(asset?.use_limit ?? 0);
  return limit > 0 && Number(asset?.use_count ?? 0) >= limit;
}

function normalizeMysqlDate(value) {
  if (!value) return null;
  const parsed = value instanceof Date ? value : new Date(value);
  if (Number.isNaN(parsed.getTime())) return String(value).slice(0, 10);
  return parsed.toISOString().slice(0, 10);
}

function normalizeMysqlDateTime(value) {
  const parsed = value ? (value instanceof Date ? value : new Date(value)) : new Date();
  if (Number.isNaN(parsed.getTime())) return new Date();
  return parsed.toISOString().slice(0, 19).replace('T', ' ');
}

exports.listAssets = async (req, res, next) => {
  try {
    const type = normalizeCode(req.query.type);
    const status = normalizeCode(req.query.status);
    const location = String(req.query.location || '').trim();
    const search = String(req.query.search || '').trim();
    const params = [];
    const where = [];
    if (type === 'METAL_MASK' || type === 'SQUEEGEE') {
      where.push('asset_type = ?');
      params.push(type);
    }
    if (status === 'BLOCKED') {
      where.push('(use_limit IS NOT NULL AND use_limit > 0 AND use_count >= use_limit)');
    } else if (status) {
      where.push('lifecycle_status = ?');
      params.push(status);
    }
    if (location) {
      where.push('location_code LIKE ?');
      params.push(`%${location}%`);
    }
    if (search) {
      where.push('(control_code LIKE ? OR asset_no LIKE ? OR location_code LIKE ? OR pcb_no LIKE ?)');
      const like = `%${search}%`;
      params.push(like, like, like, like);
    }
    const [assets] = await pool.query(`
      SELECT id, asset_type, control_code, asset_no, location_code, pcb_no,
             production_date_raw, side, lifecycle_status, thickness_mm,
             use_count, use_limit, assignment_count, active, last_used_at, source_file
      FROM tooling_asset_smd
      ${where.length ? `WHERE ${where.join(' AND ')}` : ''}
      ORDER BY asset_type, control_code
    `, params);
    res.json({ success: true, assets });
  } catch (error) {
    next(error);
  }
};

// Alta manual de herramentales que no vienen del Excel base.
exports.createAsset = async (req, res, next) => {
  try {
    const body = req.body || {};
    const assetType = normalizeCode(body.asset_type);
    const controlCode = normalizeCode(body.control_code);
    if (assetType !== 'METAL_MASK' && assetType !== 'SQUEEGEE') {
      return res.status(400).json({ success: false, error: 'Tipo invalido' });
    }
    if (!controlCode) {
      return res.status(400).json({ success: false, error: 'No control requerido' });
    }
    const status = normalizeCode(body.lifecycle_status) || 'ACTIVE';
    if (!LIFECYCLE_STATUSES.includes(status)) {
      return res.status(400).json({ success: false, error: `Estado invalido: ${status}` });
    }
    const rawLimit = String(body.use_limit ?? '').trim();
    let useLimit = null;
    if (rawLimit !== '') {
      const parsed = Number(rawLimit);
      if (!Number.isFinite(parsed) || parsed < 0) {
        return res.status(400).json({ success: false, error: 'Limite de uso invalido' });
      }
      useLimit = Math.floor(parsed);
    }

    const [existing] = await pool.query(
      'SELECT id FROM tooling_asset_smd WHERE control_code = ? LIMIT 1',
      [controlCode]
    );
    if (existing.length) {
      return res.status(409).json({ success: false, error: `${controlCode} ya esta registrado` });
    }

    const isMask = assetType === 'METAL_MASK';
    const thickness = String(body.thickness_mm ?? '').trim();
    if (thickness !== '' && !Number.isFinite(Number(thickness))) {
      return res.status(400).json({ success: false, error: 'Espesor invalido' });
    }

    await pool.query(`
      INSERT INTO tooling_asset_smd (
        asset_type, control_code, asset_no, location_code, lifecycle_status,
        use_limit, pcb_no, production_date_raw, thickness_mm, side,
        active, source_file
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'ALTA MANUAL')
    `, [
      assetType,
      controlCode,
      String(body.asset_no || '').trim() || controlCode.replace(/-\d+$/, ''),
      String(body.location_code || '').trim() || null,
      status,
      useLimit,
      // Solo la Metal Mask tiene PCB, fecha de produccion y espesor; el
      // Squeegee no los ocupa y se guardan nulos (la UI los muestra como N/A).
      isMask ? normalizePcbNo(body.pcb_no) : null,
      isMask ? String(body.production_date_raw || '').trim() || null : null,
      isMask && thickness !== '' ? Number(thickness) : null,
      isMask ? String(body.side || '').trim().toUpperCase() || null : null,
      status === 'ACTIVE' ? 1 : 0,
    ]);

    const [rows] = await pool.query(
      'SELECT * FROM tooling_asset_smd WHERE control_code = ? LIMIT 1',
      [controlCode]
    );
    res.status(201).json({ success: true, asset: rows[0] });
  } catch (error) {
    next(error);
  }
};

// Ubicacion / estado / limite de uso editables desde el grid de control.
exports.updateAsset = async (req, res, next) => {
  try {
    const code = normalizeCode(req.params.code);
    if (!code) return res.status(400).json({ success: false, error: 'Codigo requerido' });
    const body = req.body || {};
    const sets = [];
    const params = [];
    if (body.location_code !== undefined) {
      sets.push('location_code = ?');
      params.push(String(body.location_code || '').trim() || null);
    }
    if (body.lifecycle_status !== undefined) {
      const status = normalizeCode(body.lifecycle_status);
      if (!LIFECYCLE_STATUSES.includes(status)) {
        return res.status(400).json({ success: false, error: `Estado invalido: ${status}` });
      }
      sets.push('lifecycle_status = ?', 'active = ?');
      params.push(status, status === 'ACTIVE' ? 1 : 0);
    }
    const [current] = await pool.query(
      'SELECT asset_type FROM tooling_asset_smd WHERE control_code = ? LIMIT 1',
      [code]
    );
    if (!current.length) {
      return res.status(404).json({ success: false, error: 'Herramental no encontrado' });
    }
    const editingMask = current[0].asset_type === 'METAL_MASK';
    const maskOnly = ['pcb_no', 'production_date_raw', 'side', 'thickness_mm']
      .filter((field) => body[field] !== undefined);
    if (!editingMask && maskOnly.length) {
      return res.status(400).json({
        success: false,
        error: 'El Squeegee no ocupa PCB, fecha de produccion ni espesor',
      });
    }

    if (body.pcb_no !== undefined) {
      sets.push('pcb_no = ?');
      params.push(normalizePcbNo(body.pcb_no));
    }
    if (body.production_date_raw !== undefined) {
      sets.push('production_date_raw = ?');
      params.push(String(body.production_date_raw || '').trim() || null);
    }
    if (body.side !== undefined) {
      sets.push('side = ?');
      params.push(String(body.side || '').trim().toUpperCase() || null);
    }
    if (body.thickness_mm !== undefined) {
      const raw = String(body.thickness_mm ?? '').trim();
      if (raw === '') {
        sets.push('thickness_mm = NULL');
      } else if (!Number.isFinite(Number(raw))) {
        return res.status(400).json({ success: false, error: 'Espesor invalido' });
      } else {
        sets.push('thickness_mm = ?');
        params.push(Number(raw));
      }
    }
    if (body.use_limit !== undefined) {
      const raw = String(body.use_limit ?? '').trim();
      if (raw === '') {
        sets.push('use_limit = NULL');
      } else {
        const limit = Number(raw);
        if (!Number.isFinite(limit) || limit < 0) {
          return res.status(400).json({ success: false, error: 'Limite de uso invalido' });
        }
        sets.push('use_limit = ?');
        params.push(Math.floor(limit));
      }
    }
    if (!sets.length) return res.status(400).json({ success: false, error: 'Nada que actualizar' });
    params.push(code);
    const [result] = await pool.query(
      `UPDATE tooling_asset_smd SET ${sets.join(', ')} WHERE control_code = ?`,
      params
    );
    if (result.affectedRows === 0) {
      return res.status(404).json({ success: false, error: 'Herramental no encontrado' });
    }
    const [rows] = await pool.query(
      'SELECT * FROM tooling_asset_smd WHERE control_code = ? LIMIT 1',
      [code]
    );
    res.json({ success: true, asset: rows[0] });
  } catch (error) {
    next(error);
  }
};

exports.summary = async (_req, res, next) => {
  try {
    const [rows] = await pool.query(`
      SELECT
        SUM(asset_type = 'METAL_MASK') AS metal_masks,
        SUM(asset_type = 'SQUEEGEE') AS squeegees,
        SUM(asset_type = 'METAL_MASK' AND active = 1) AS masks_available,
        SUM(asset_type = 'METAL_MASK' AND lifecycle_status = 'SCRAP') AS masks_scrap,
        SUM(CASE WHEN asset_type = 'METAL_MASK' THEN use_count ELSE 0 END) AS total_mask_uses,
        SUM(assignment_count) AS total_assignments
      FROM tooling_asset_smd
    `);
    const [recent] = await pool.query(`
      SELECT id, event_id, plan_id, lot_no, part_no, model_code, line_code,
             working_date, shift, plan_count, metal_mask_code, squeegee_code,
             count_source, planned_uses, assigned_at
      FROM tooling_plan_assignment_smd
      ORDER BY assigned_at DESC, id DESC
      LIMIT 25
    `);
    res.json({ success: true, summary: rows[0] || {}, recentAssignments: recent });
  } catch (error) {
    next(error);
  }
};

exports.validate = async (req, res, next) => {
  try {
    const code = normalizeCode(req.body?.code);
    if (!code) return res.status(400).json({ success: false, error: 'Código requerido' });
    const [rows] = await pool.query(`
      SELECT id, asset_type, control_code, lifecycle_status, active, use_count, use_limit
      FROM tooling_asset_smd WHERE control_code = ? LIMIT 1
    `, [code]);
    if (!rows[0]) return res.status(404).json({ success: false, error: 'Código no registrado' });
    const asset = rows[0];
    const limitReached = isLimitReached(asset);
    const available = Number(asset.active) === 1 && asset.lifecycle_status !== 'SCRAP' && !limitReached;
    res.status(available ? 200 : 409).json({
      success: available,
      available,
      asset,
      error: available
        ? null
        : limitReached
          ? `Límite de uso alcanzado (${asset.use_count}/${asset.use_limit})`
          : `Herramental no disponible (${asset.lifecycle_status})`,
    });
  } catch (error) {
    next(error);
  }
};

// Historial de uso completo. Sin filtros devuelve lo mas reciente; con `code`
// devuelve la vida entera de un herramental, sea mask o squeegee.
exports.listAssignments = async (req, res, next) => {
  try {
    const limit = Math.min(2000, Math.max(1, Number(req.query.limit) || 200));
    const code = normalizeCode(req.query.code);
    const line = String(req.query.line || '').trim();
    const from = String(req.query.from || '').trim();
    const to = String(req.query.to || '').trim();
    const where = [];
    const params = [];
    if (code) {
      where.push('(metal_mask_code = ? OR squeegee_code = ?)');
      params.push(code, code);
    }
    if (line) {
      where.push('line_code = ?');
      params.push(line);
    }
    if (from) {
      where.push('working_date >= ?');
      params.push(from);
    }
    if (to) {
      where.push('working_date <= ?');
      params.push(to);
    }
    params.push(limit);
    const [assignments] = await pool.query(`
      SELECT id, event_id, plan_source, plan_id, lot_no, part_no, model_code,
             line_code, working_date, shift, plan_count, metal_mask_code,
             squeegee_code, count_source, planned_uses, assigned_at
      FROM tooling_plan_assignment_smd
      ${where.length ? `WHERE ${where.join(' AND ')}` : ''}
      ORDER BY assigned_at DESC, id DESC
      LIMIT ?
    `, params);

    // Totales de la seleccion, para no obligar a sumar la columna a mano.
    const [totals] = await pool.query(`
      SELECT COUNT(*) AS eventos,
             COALESCE(SUM(planned_uses), 0) AS usos,
             MIN(working_date) AS desde,
             MAX(working_date) AS hasta
      FROM tooling_plan_assignment_smd
      ${where.length ? `WHERE ${where.join(' AND ')}` : ''}
    `, params.slice(0, -1));

    res.json({ success: true, assignments, totals: totals[0] || {} });
  } catch (error) {
    next(error);
  }
};

exports.assignPlan = async (req, res, next) => {
  const body = req.body || {};
  const eventId = String(body.event_id || body.eventId || '').trim();
  const planId = Number(body.plan_id || body.planId || 0);
  const metalMaskCode = normalizeCode(body.metal_mask_code || body.metalMaskCode);
  const squeegeeCode = normalizeCode(body.squeegee_code || body.squeegeeCode);
  const squeegeeCode2 = normalizeCode(body.squeegee_code_2 || body.squeegeeCode2);
  const plannedUses = Math.max(0, Number(body.planned_uses ?? body.plan_count ?? body.planCount) || 0);
  const workingDate = normalizeMysqlDate(body.working_date || body.workingDate);
  const assignedAt = normalizeMysqlDateTime(body.assigned_at || body.assignedAt);
  if (!eventId || !planId || !metalMaskCode || !squeegeeCode || !workingDate) {
    return res.status(400).json({ success: false, error: 'Asignación incompleta' });
  }

  const connection = await pool.getConnection();
  try {
    await connection.beginTransaction();
    const [assets] = await connection.query(`
      SELECT control_code, asset_type, lifecycle_status, active, use_count, use_limit
      FROM tooling_asset_smd WHERE control_code IN (?, ?, ?)
    `, [metalMaskCode, squeegeeCode, squeegeeCode2 || squeegeeCode]);
    const mask = assets.find((a) => a.control_code === metalMaskCode && a.asset_type === 'METAL_MASK');
    const squeegee = assets.find((a) => a.control_code === squeegeeCode && a.asset_type === 'SQUEEGEE');
    if (!mask || Number(mask.active) !== 1 || mask.lifecycle_status === 'SCRAP') {
      const error = new Error('Metal Mask inválida o no disponible');
      error.statusCode = 409;
      throw error;
    }
    if (isLimitReached(mask)) {
      const error = new Error(`Metal Mask ${metalMaskCode} alcanzó su límite de uso (${mask.use_count}/${mask.use_limit})`);
      error.statusCode = 409;
      throw error;
    }
    if (!squeegee || Number(squeegee.active) !== 1) {
      const error = new Error('Squeegee inválido o no disponible');
      error.statusCode = 409;
      throw error;
    }
    if (isLimitReached(squeegee)) {
      const error = new Error(`Squeegee ${squeegeeCode} alcanzó su límite de uso (${squeegee.use_count}/${squeegee.use_limit})`);
      error.statusCode = 409;
      throw error;
    }

    const [insert] = await connection.query(`
      INSERT IGNORE INTO tooling_plan_assignment_smd (
        event_id, plan_source, plan_id, lot_no, part_no, model_code, line_code,
        working_date, shift, plan_count, metal_mask_code, squeegee_code,
        squeegee_code_2, count_source, planned_uses, assigned_at
      ) VALUES (?, 'plan_smt', ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'PLAN', ?, ?)
    `, [
      eventId,
      planId,
      body.lot_no || body.lotNo || null,
      body.part_no || body.partNo || null,
      body.model_code || body.modelCode || null,
      body.line_code || body.lineId || 'SMT',
      workingDate,
      body.shift || null,
      Math.max(0, Number(body.plan_count ?? body.planCount) || 0),
      metalMaskCode,
      squeegeeCode,
      squeegeeCode2 || null,
      plannedUses,
      assignedAt,
    ]);

    if (insert.affectedRows > 0) {
      await connection.query(`
        UPDATE tooling_asset_smd SET use_count = use_count + ?,
          assignment_count = assignment_count + 1, last_used_at = NOW()
        WHERE control_code = ?
      `, [plannedUses, metalMaskCode]);
      await connection.query(`
        UPDATE tooling_asset_smd SET use_count = use_count + ?,
          assignment_count = assignment_count + 1,
          last_used_at = NOW() WHERE control_code = ?
      `, [plannedUses, squeegeeCode]);
      if (squeegeeCode2) {
        await connection.query(`
          UPDATE tooling_asset_smd SET use_count = use_count + ?,
            assignment_count = assignment_count + 1,
            last_used_at = NOW() WHERE control_code = ?
        `, [plannedUses, squeegeeCode2]);
      }
    }
    await connection.commit();
    res.status(insert.affectedRows > 0 ? 201 : 200).json({
      success: true,
      created: insert.affectedRows > 0,
      message: insert.affectedRows > 0 ? 'Herramentales asignados al plan' : 'Plan ya contabilizado',
    });
  } catch (error) {
    await connection.rollback();
    if (error.statusCode) return res.status(error.statusCode).json({ success: false, error: error.message });
    next(error);
  } finally {
    connection.release();
  }
};

exports._test = { isLimitReached, LIFECYCLE_STATUSES, normalizePcbNo };
