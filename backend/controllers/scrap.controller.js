/**
 * Scrap Controller - Registro de scrap por escaneo QR
 * Procesos: SMD, IMD, ASSY, COMPONENTE
 * QR Format: TOKEN0;ASSY_TYPE;PART_NO;TOKEN3 (mismo formato PCB)
 */

const { pool, getMexicoDateTime, getMexicoDate } = require('../config/database');
const { FULL_ACCESS_DEPARTMENTS } = require('../config/permissions');

// ============================================
// HELPERS
// ============================================

function normalizeCode(code) {
  return (code || '').trim().toUpperCase().replace(/\s+/g, '');
}

function resolveScrapRegistrationDate(value) {
  const now = getMexicoDateTime();
  const today = getMexicoDate();
  const requestedDate = (value || '').toString().trim();

  // Los clientes anteriores no enviaban fecha; conservar ese flujo usando hoy.
  if (!requestedDate) {
    return { date: today, dateTime: now };
  }

  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(requestedDate);
  if (!match) return null;

  const year = Number(match[1]);
  const month = Number(match[2]);
  const day = Number(match[3]);
  const parsed = new Date(Date.UTC(year, month - 1, day));
  const isRealDate =
    parsed.getUTCFullYear() === year &&
    parsed.getUTCMonth() === month - 1 &&
    parsed.getUTCDate() === day;

  if (!isRealDate || requestedDate > today) return null;

  const currentTime = now.split(' ')[1] || '12:00:00';
  return {
    date: requestedDate,
    dateTime: `${requestedDate} ${currentTime}`,
  };
}

function parseScannedCode(code) {
  const parts = code.split(';').map(s => s.trim()).filter(Boolean);
  // Si no tiene separadores (entrada manual sin QR), tratar todo como part_no
  if (parts.length <= 1) {
    return {
      token0: null,
      assy_type: null,
      part_no: parts[0] || null,
      token3: null,
    };
  }
  return {
    token0: parts[0] || null,
    assy_type: parts[1] || null,
    part_no: parts[2] || null,
    token3: parts[3] || null,
  };
}

async function lookupModelo(partNo, db = pool) {
  if (!partNo) return 'N/A';
  try {
    // Buscar project (modelo) en tabla raw por part_no
    const [rows] = await db.query(
      `SELECT DISTINCT project FROM raw WHERE part_no = ? AND project IS NOT NULL AND project != '' LIMIT 1`,
      [partNo]
    );
    if (rows.length > 0 && rows[0].project) {
      return rows[0].project;
    }
    return 'N/A';
  } catch (_err) {
    return 'N/A';
  }
}

async function buildScrapCodeFields(scannedCode, db = pool) {
  const scannedOriginal = scannedCode.trim();
  const scannedOriginalNorm = normalizeCode(scannedCode);
  const parsed = parseScannedCode(scannedOriginal);
  const modelo = await lookupModelo(parsed.part_no, db);

  let assyType = parsed.assy_type;
  if (!assyType && parsed.part_no) {
    try {
      const [rawRows] = await db.query(
        `SELECT model FROM raw WHERE part_no = ? AND model IS NOT NULL LIMIT 1`,
        [parsed.part_no]
      );
      if (rawRows.length > 0 && rawRows[0].model) {
        assyType = rawRows[0].model;
      }
    } catch (_) {}
  }

  return {
    scannedOriginal,
    scannedOriginalNorm,
    assyType: assyType || null,
    partNo: parsed.part_no,
    modelo,
  };
}

async function getScrapEditUser(userId, db = pool) {
  if (!userId) return { allowed: false, user: null };

  const [users] = await db.query(
    `SELECT id, nombre_completo, departamento, activo
     FROM usuarios_sistema
     WHERE id = ? AND activo = 1
     LIMIT 1`,
    [userId]
  );

  if (users.length === 0) return { allowed: false, user: null };

  const user = users[0];
  if (FULL_ACCESS_DEPARTMENTS.includes(user.departamento)) {
    return { allowed: true, user };
  }

  const [permissions] = await db.query(
    `SELECT id
     FROM user_permissions_materiales
     WHERE user_id = ? AND permission_key = 'edit_scrap_history' AND enabled = 1
     LIMIT 1`,
    [userId]
  );

  return { allowed: permissions.length > 0, user };
}

const VALID_AREAS = ['M1', 'M2', 'M3', 'M4', 'D1', 'D2', 'D3', 'CALIDAD', 'MANTENIMIENTO', 'SMD', 'IMD', 'IPM', 'COATING', 'PROVEEDOR'];
const VALID_PROCESOS = ['SMD', 'IMD', 'ASSY', 'COMPONENTE'];
const COMPONENT_CAPTURE_AREAS = new Set(['IPM']);
const COMPONENT_CAPTURE_PROCESSES = new Set(['COMPONENTE']);

function isComponentCapture(_area, proceso) {
  return COMPONENT_CAPTURE_PROCESSES.has((proceso || '').toString().toUpperCase());
}

// ============================================
// Lookup de raw_barcode por QR escaneado.
// Fuentes en cascada:
//   1) input_main.raw (case-insensitive) -> input_main.raw_barcode
//   2) history_vision.qr_payload/serial_qr (case-insensitive) -> history_vision.barcode
// Devuelve { raw_barcode, source } o { raw_barcode: null, source: null }.
// ============================================
async function findRawBarcode(scannedCode, db = pool) {
  const raw = (scannedCode || '').toString().trim();
  if (!raw) return { raw_barcode: null, source: null };
  const norm = normalizeCode(raw);

  // 1) input_main.raw -> raw_barcode
  try {
    const [rows] = await db.query(
      `SELECT raw_barcode
       FROM input_main
       WHERE (UPPER(raw) = UPPER(?) OR UPPER(raw) = ?)
         AND raw_barcode IS NOT NULL AND raw_barcode <> ''
       ORDER BY ts DESC, id DESC
       LIMIT 1`,
      [raw, norm]
    );
    if (rows.length > 0 && rows[0].raw_barcode) {
      return { raw_barcode: rows[0].raw_barcode, source: 'input_main' };
    }
  } catch (_) {
    // input_main puede no existir en algunos ambientes
  }

  // 2) history_vision.qr_payload/serial_qr -> barcode
  try {
    const [rows] = await db.query(
      `SELECT barcode,
              CASE
                WHEN UPPER(qr_payload) = UPPER(?) OR UPPER(qr_payload) = ?
                  THEN 'history_vision.qr_payload'
                ELSE 'history_vision.serial_qr'
              END AS source
       FROM history_vision
       WHERE (
           UPPER(qr_payload) = UPPER(?)
           OR UPPER(qr_payload) = ?
           OR UPPER(serial_qr) = UPPER(?)
           OR UPPER(serial_qr) = ?
         )
         AND barcode IS NOT NULL AND barcode <> ''
       ORDER BY captured_at_utc DESC, id DESC
       LIMIT 1`,
      [raw, norm, raw, norm, raw, norm]
    );
    if (rows.length > 0 && rows[0].barcode) {
      return { raw_barcode: rows[0].barcode, source: rows[0].source };
    }
  } catch (_) {
    // history_vision puede no existir
  }

  return { raw_barcode: null, source: null };
}

// ============================================
// GET /api/scrap/lookup-raw-barcode?codigo=...
// Devuelve { success, found, raw_barcode, source }
// ============================================
exports.lookupRawBarcode = async (req, res, next) => {
  try {
    const codigo = (req.query.codigo || '').toString().trim();
    if (!codigo) {
      return res.status(400).json({
        success: false,
        found: false,
        message: 'codigo es requerido',
      });
    }
    const result = await findRawBarcode(codigo);
    return res.json({
      success: true,
      found: result.raw_barcode !== null,
      raw_barcode: result.raw_barcode,
      source: result.source,
    });
  } catch (err) {
    next(err);
  }
};

// ============================================
// POST /api/scrap/scan
// Registra un escaneo de scrap
// ============================================
exports.scan = async (req, res, next) => {
  try {
    const {
      scanned_code,
      area,
      proceso,
      motivo_scrap_id,
      comentarios,
      usuario,
      cantidad,
      raw_barcode,
      fecha_registro,
      cliente,
      ubicacion,
    } = req.body;
    const qtyVal = Math.max(1, parseInt(cantidad) || 1);
    const procesoVal = (proceso || '').toString().trim().toUpperCase();
    const clienteVal = (cliente || '').toString().trim().toUpperCase() || null;
    const ubicacionVal = (ubicacion || '').toString().trim().slice(0, 100) || null;
    const registrationDate = resolveScrapRegistrationDate(fecha_registro);

    if (!scanned_code || !scanned_code.trim()) {
      return res.status(400).json({
        success: false,
        message: 'scanned_code es requerido',
        code: 'MISSING_SCANNED_CODE',
      });
    }

    if (!area || !VALID_AREAS.includes(area)) {
      return res.status(400).json({
        success: false,
        message: `area es requerida y debe ser una de: ${VALID_AREAS.join(', ')}`,
        code: 'INVALID_AREA',
      });
    }

    if (!procesoVal || !VALID_PROCESOS.includes(procesoVal)) {
      return res.status(400).json({
        success: false,
        message: `proceso es requerido y debe ser uno de: ${VALID_PROCESOS.join(', ')}`,
        code: 'INVALID_PROCESO',
      });
    }

    if (!motivo_scrap_id) {
      return res.status(400).json({
        success: false,
        message: 'motivo_scrap_id es requerido',
        code: 'MISSING_MOTIVO',
      });
    }

    if (!registrationDate) {
      return res.status(400).json({
        success: false,
        message: 'fecha_registro debe ser una fecha valida y no puede ser futura',
        code: 'INVALID_FECHA_REGISTRO',
      });
    }

    // Resolver raw_barcode como dato opcional. Si el cliente no lo envia,
    // intentamos lookup interno; si tampoco se encuentra, se guarda null.
    let rawBarcodeVal = (raw_barcode || '').toString().trim() || null;
    if (!rawBarcodeVal) {
      const lookup = await findRawBarcode(scanned_code);
      if (lookup.raw_barcode) {
        rawBarcodeVal = lookup.raw_barcode;
      }
    }

    // Parsear QR
    const codeFields = await buildScrapCodeFields(scanned_code);
    const fechaRegistro = registrationDate.date;

    // Los componentes son capturas de lote y pueden repetirse el mismo día.
    // Para PCB se conserva la protección contra doble escaneo.
    if (!isComponentCapture(area, procesoVal)) {
      const [existing] = await pool.query(
        `SELECT id FROM scrap_records
         WHERE scanned_original_norm = ? AND DATE(fecha_registro) = ?`,
        [codeFields.scannedOriginalNorm, fechaRegistro]
      );

      if (existing.length > 0) {
        return res.status(409).json({
          success: false,
          message: 'Este codigo ya fue registrado como scrap en la fecha seleccionada',
          code: 'DUPLICATE_SCAN',
          existing_id: existing[0].id,
        });
      }
    }

    // Obtener texto del motivo
    let motivoTexto = '';
    const [motivoRows] = await pool.query(
      `SELECT motivo FROM scrap_motivos WHERE id = ? AND activo = 1`,
      [motivo_scrap_id]
    );
    if (motivoRows.length > 0) {
      motivoTexto = motivoRows[0].motivo;
    } else {
      return res.status(400).json({
        success: false,
        message: 'Motivo de scrap no encontrado o inactivo',
        code: 'INVALID_MOTIVO',
      });
    }

    const ahora = registrationDate.dateTime;

    const [result] = await pool.query(
      `INSERT INTO scrap_records
        (scanned_original, scanned_original_norm, cliente, assy_type, part_no, raw_barcode, modelo, area, proceso, ubicacion, motivo_scrap_id, motivo_scrap_texto, comentarios, usuario_registro, fecha_registro, cantidad)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
      [
        codeFields.scannedOriginal,
        codeFields.scannedOriginalNorm,
        clienteVal,
        codeFields.assyType,
        codeFields.partNo,
        rawBarcodeVal,
        codeFields.modelo,
        area,
        procesoVal,
        ubicacionVal,
        motivo_scrap_id,
        motivoTexto,
        comentarios || null,
        usuario || null,
        ahora,
        qtyVal,
      ]
    );

    const [inserted] = await pool.query(
      `SELECT *, DATE_FORMAT(fecha_registro, '%Y-%m-%d') as fecha, 
              DATE_FORMAT(fecha_registro, '%H:%i:%s') as hora
       FROM scrap_records WHERE id = ?`,
      [result.insertId]
    );

    res.json({
      success: true,
      data: inserted[0],
    });
  } catch (err) {
    next(err);
  }
};

// ============================================
// GET /api/scrap/records
// Historial de scrap por rango de fecha
// ============================================
exports.getRecords = async (req, res, next) => {
  try {
    const { fecha_inicio, fecha_fin, area, limit } = req.query;

    if (!fecha_inicio || !fecha_fin) {
      return res.status(400).json({
        success: false,
        message: 'fecha_inicio y fecha_fin son requeridos',
      });
    }

    const maxRows = parseInt(limit) || 5000;

    let query = `
      SELECT s.*, 
             DATE_FORMAT(s.fecha_registro, '%Y-%m-%d') as fecha, 
             DATE_FORMAT(s.fecha_registro, '%H:%i:%s') as hora
      FROM scrap_records s
      WHERE DATE(s.fecha_registro) BETWEEN ? AND ?
    `;
    const params = [fecha_inicio, fecha_fin];

    if (area && VALID_AREAS.includes(area)) {
      query += ` AND s.area = ?`;
      params.push(area);
    }

    query += ` ORDER BY s.fecha_registro DESC LIMIT ?`;
    params.push(maxRows);

    const [rows] = await pool.query(query, params);

    res.json({
      success: true,
      data: rows,
      count: rows.length,
    });
  } catch (err) {
    next(err);
  }
};

// ============================================
// PUT /api/scrap/record/:id
// Edita un registro historico de scrap
// ============================================
exports.updateRecord = async (req, res, next) => {
  let connection;

  try {
    connection = await pool.getConnection();
    const { id } = req.params;
    const {
      scanned_code,
      area,
      proceso,
      motivo_scrap_id,
      comentarios,
      cantidad,
      raw_barcode,
      edit_reason,
      edited_by_user_id,
      edited_by_name,
    } = req.body;

    const recordId = parseInt(id, 10);
    const editorUserId = parseInt(edited_by_user_id, 10);
    const qtyVal = parseInt(cantidad, 10);
    const motivoId = parseInt(motivo_scrap_id, 10);
    const procesoVal = (proceso || '').toString().trim().toUpperCase();

    if (!recordId) {
      return res.status(400).json({
        success: false,
        message: 'id invalido',
        code: 'INVALID_ID',
      });
    }

    if (!scanned_code || !scanned_code.trim()) {
      return res.status(400).json({
        success: false,
        message: 'scanned_code es requerido',
        code: 'MISSING_SCANNED_CODE',
      });
    }

    if (!area || !VALID_AREAS.includes(area)) {
      return res.status(400).json({
        success: false,
        message: `area es requerida y debe ser una de: ${VALID_AREAS.join(', ')}`,
        code: 'INVALID_AREA',
      });
    }

    if (!procesoVal || !VALID_PROCESOS.includes(procesoVal)) {
      return res.status(400).json({
        success: false,
        message: `proceso es requerido y debe ser uno de: ${VALID_PROCESOS.join(', ')}`,
        code: 'INVALID_PROCESO',
      });
    }

    if (!motivoId) {
      return res.status(400).json({
        success: false,
        message: 'motivo_scrap_id es requerido',
        code: 'MISSING_MOTIVO',
      });
    }

    if (!qtyVal || qtyVal < 1) {
      return res.status(400).json({
        success: false,
        message: 'cantidad debe ser mayor o igual a 1',
        code: 'INVALID_CANTIDAD',
      });
    }

    if (!edit_reason || !edit_reason.trim()) {
      return res.status(400).json({
        success: false,
        message: 'edit_reason es requerido',
        code: 'MISSING_EDIT_REASON',
      });
    }

    const permission = await getScrapEditUser(editorUserId, connection);
    if (!permission.allowed) {
      return res.status(403).json({
        success: false,
        message: 'No tiene permiso para editar historial de scrap',
        code: 'FORBIDDEN',
      });
    }

    await connection.beginTransaction();

    const [currentRows] = await connection.query(
      `SELECT *
       FROM scrap_records
       WHERE id = ?
       FOR UPDATE`,
      [recordId]
    );

    if (currentRows.length === 0) {
      await connection.rollback();
      return res.status(404).json({
        success: false,
        message: 'Registro no encontrado',
        code: 'NOT_FOUND',
      });
    }

    const current = currentRows[0];
    const codeFields = await buildScrapCodeFields(scanned_code, connection);

    if (!isComponentCapture(area, procesoVal)) {
      const [duplicateRows] = await connection.query(
        `SELECT id
         FROM scrap_records
         WHERE scanned_original_norm = ?
           AND DATE(fecha_registro) = DATE(?)
           AND id <> ?
         LIMIT 1`,
        [codeFields.scannedOriginalNorm, current.fecha_registro, recordId]
      );

      if (duplicateRows.length > 0) {
        await connection.rollback();
        return res.status(409).json({
          success: false,
          message: 'Este codigo ya fue registrado como scrap en la fecha del registro',
          code: 'DUPLICATE_SCAN',
          existing_id: duplicateRows[0].id,
        });
      }
    }

    const [motivoRows] = await connection.query(
      `SELECT motivo FROM scrap_motivos WHERE id = ? AND activo = 1`,
      [motivoId]
    );

    if (motivoRows.length === 0) {
      await connection.rollback();
      return res.status(400).json({
        success: false,
        message: 'Motivo de scrap no encontrado o inactivo',
        code: 'INVALID_MOTIVO',
      });
    }

    const motivoTexto = motivoRows[0].motivo;
    const ahora = getMexicoDateTime();
    const editedByName = edited_by_name || permission.user.nombre_completo;
    const newComentarios = comentarios && comentarios.trim() ? comentarios.trim() : null;

    // raw_barcode: si el cliente envia uno explicito (no undefined), lo respetamos
    // (incluso vacio -> NULL para borrarlo). Si es undefined, conservamos el actual.
    let newRawBarcode;
    if (raw_barcode === undefined) {
      newRawBarcode = current.raw_barcode || null;
    } else {
      const trimmed = (raw_barcode || '').toString().trim();
      newRawBarcode = trimmed.length > 0 ? trimmed : null;
    }

    await connection.query(
      `UPDATE scrap_records
       SET scanned_original = ?,
           scanned_original_norm = ?,
           assy_type = ?,
           part_no = ?,
           raw_barcode = ?,
           modelo = ?,
           area = ?,
           proceso = ?,
           motivo_scrap_id = ?,
           motivo_scrap_texto = ?,
           comentarios = ?,
           cantidad = ?
       WHERE id = ?`,
      [
        codeFields.scannedOriginal,
        codeFields.scannedOriginalNorm,
        codeFields.assyType,
        codeFields.partNo,
        newRawBarcode,
        codeFields.modelo,
        area,
        procesoVal,
        motivoId,
        motivoTexto,
        newComentarios,
        qtyVal,
        recordId,
      ]
    );

    await connection.query(
      `INSERT INTO scrap_record_edits
        (scrap_record_id,
         old_scanned_original, new_scanned_original,
         old_scanned_original_norm, new_scanned_original_norm,
         old_assy_type, new_assy_type,
         old_part_no, new_part_no,
         old_raw_barcode, new_raw_barcode,
         old_modelo, new_modelo,
         old_area, new_area,
         old_proceso, new_proceso,
         old_motivo_scrap_id, new_motivo_scrap_id,
         old_motivo_scrap_texto, new_motivo_scrap_texto,
         old_comentarios, new_comentarios,
         old_cantidad, new_cantidad,
         edit_reason, edited_by_user_id, edited_by_name, edited_at)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
      [
        recordId,
        current.scanned_original,
        codeFields.scannedOriginal,
        current.scanned_original_norm,
        codeFields.scannedOriginalNorm,
        current.assy_type,
        codeFields.assyType,
        current.part_no,
        codeFields.partNo,
        current.raw_barcode || null,
        newRawBarcode,
        current.modelo,
        codeFields.modelo,
        current.area,
        area,
        current.proceso,
        procesoVal,
        current.motivo_scrap_id,
        motivoId,
        current.motivo_scrap_texto,
        motivoTexto,
        current.comentarios,
        newComentarios,
        current.cantidad,
        qtyVal,
        edit_reason.trim(),
        editorUserId,
        editedByName,
        ahora,
      ]
    );

    const [updatedRows] = await connection.query(
      `SELECT *, DATE_FORMAT(fecha_registro, '%Y-%m-%d') as fecha,
              DATE_FORMAT(fecha_registro, '%H:%i:%s') as hora
       FROM scrap_records WHERE id = ?`,
      [recordId]
    );

    await connection.commit();

    res.json({
      success: true,
      data: updatedRows[0],
    });
  } catch (err) {
    try {
      if (connection) await connection.rollback();
    } catch (_) {}
    next(err);
  } finally {
    if (connection) connection.release();
  }
};

// ============================================
// DELETE /api/scrap/record/:id
// Elimina un registro de scrap (para deshacer)
// ============================================
exports.deleteRecord = async (req, res, next) => {
  try {
    const { id } = req.params;

    const [result] = await pool.query(
      `DELETE FROM scrap_records WHERE id = ?`,
      [id]
    );

    if (result.affectedRows === 0) {
      return res.status(404).json({
        success: false,
        message: 'Registro no encontrado',
      });
    }

    res.json({ success: true });
  } catch (err) {
    next(err);
  }
};

// ============================================
// GET /api/scrap/autocomplete?q=xxx&area=yyy&proceso=zzz
// Busca PCBs en tabla raw y componentes en tabla materiales para cualquier area.
// ============================================
exports.autocomplete = async (req, res, next) => {
  try {
    const { q, area, proceso } = req.query;

    if (!q || q.trim().length < 3) {
      return res.json({ success: true, data: [] });
    }

    const searchTerm = `%${q.trim()}%`;

    const [pcbRows] = await pool.query(
      `SELECT DISTINCT
         part_no,
         model,
         project,
         'pcb' AS source_type,
         'PCB' AS source_label
       FROM raw
       WHERE part_no LIKE ? AND part_no IS NOT NULL AND part_no != ''
       ORDER BY part_no
       LIMIT 15`,
      [searchTerm]
    );

    const [componentRows] = await pool.query(
      `SELECT DISTINCT
         numero_parte AS part_no,
         codigo_material AS model,
         especificacion_material AS project,
         'component' AS source_type,
         'COMP' AS source_label
       FROM materiales
       WHERE (
           numero_parte LIKE ?
           OR codigo_material LIKE ?
           OR especificacion_material LIKE ?
         )
         AND numero_parte IS NOT NULL AND numero_parte != ''
       ORDER BY part_no
       LIMIT 15`,
      [searchTerm, searchTerm, searchTerm]
    );

    const prioritizeComponents =
      COMPONENT_CAPTURE_PROCESSES.has((proceso || '').toString().toUpperCase()) ||
      COMPONENT_CAPTURE_AREAS.has(area);
    const rows = prioritizeComponents
      ? [...componentRows, ...pcbRows]
      : [...pcbRows, ...componentRows];

    return res.json({ success: true, data: rows });
  } catch (err) {
    next(err);
  }
};

// Reglas puras expuestas únicamente para pruebas automatizadas.
exports._test = {
  resolveScrapRegistrationDate,
  isComponentCapture,
};
