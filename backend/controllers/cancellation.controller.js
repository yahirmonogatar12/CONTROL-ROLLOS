/**
 * Cancellation Controller - Solicitudes de Cancelación de Entradas
 * Pantalla Flutter: lib/screens/material_warehousing/
 * 
 * Flujo:
 * 1. Usuario solicita cancelación (con motivo)
 * 2. Supervisor aprueba o rechaza
 * 3. Si aprueba -> entrada se marca como cancelada
 */

const { pool } = require('../config/database');

// ============================================
// SOLICITUDES DE CANCELACIÓN
// ============================================

// POST /api/cancellation/request - Solicitar cancelación de una entrada
exports.requestCancellation = async (req, res, next) => {
  try {
    const { warehousingId, reason, requestedBy, requestedById } = req.body;
    
    if (!warehousingId || !reason || !requestedBy) {
      return res.status(400).json({ 
        error: 'Se requiere warehousingId, reason y requestedBy' 
      });
    }
    
    // Verificar que la entrada existe y no está ya cancelada
    const [entry] = await pool.query(
      'SELECT id, codigo_material_recibido, cancelado FROM control_material_almacen_smd WHERE id = ?',
      [warehousingId]
    );
    
    if (entry.length === 0) {
      return res.status(404).json({ error: 'Entrada no encontrada' });
    }
    
    if (entry[0].cancelado === 1) {
      return res.status(400).json({ error: 'Esta entrada ya está cancelada' });
    }
    
    // Verificar si ya existe una solicitud pendiente para esta entrada
    const [existing] = await pool.query(
      'SELECT id FROM cancellation_requests WHERE warehousing_id = ? AND status = ?',
      [warehousingId, 'Pending']
    );
    
    if (existing.length > 0) {
      return res.status(400).json({ error: 'Ya existe una solicitud de cancelación pendiente para esta entrada' });
    }
    
    // Crear la solicitud
    const [result] = await pool.query(`
      INSERT INTO cancellation_requests 
      (warehousing_id, warehousing_code, status, requested_by, requested_by_id, requested_at, reason)
      VALUES (?, ?, ?, ?, ?, NOW(), ?)
    `, [warehousingId, entry[0].codigo_material_recibido, 'Pending', requestedBy, requestedById || null, reason]);
    
    res.status(201).json({ 
      success: true, 
      message: 'Solicitud de cancelación enviada',
      id: result.insertId
    });
    
  } catch (err) {
    next(err);
  }
};

// GET /api/cancellation/pending - Obtener solicitudes pendientes (para supervisores)
exports.getPendingRequests = async (req, res, next) => {
  try {
    const [requests] = await pool.query(`
      SELECT 
        cr.id,
        cr.warehousing_id,
        cr.warehousing_code,
        cr.status,
        cr.requested_by,
        cr.requested_at,
        cr.reason,
        cma.numero_parte,
        cma.numero_lote_material,
        cma.cantidad_actual,
        cma.codigo_material
      FROM cancellation_requests cr
      LEFT JOIN control_material_almacen_smd cma ON cr.warehousing_id = cma.id
      WHERE cr.status = ?
      ORDER BY cr.requested_at DESC
    `, ['Pending']);
    
    res.json(requests);
  } catch (err) {
    next(err);
  }
};

// GET /api/cancellation/pending/count - Obtener conteo de solicitudes pendientes
exports.getPendingCount = async (req, res, next) => {
  try {
    const [result] = await pool.query(
      'SELECT COUNT(*) as count FROM cancellation_requests WHERE status = ?',
      ['Pending']
    );
    res.json({ count: result[0].count });
  } catch (err) {
    next(err);
  }
};

// POST /api/cancellation/:id/approve - Aprobar solicitud de cancelación
exports.approveRequest = async (req, res, next) => {
  try {
    const { id } = req.params;
    const { reviewedBy, reviewedById, reviewNotes } = req.body;
    
    if (!reviewedBy) {
      return res.status(400).json({ error: 'Se requiere reviewedBy' });
    }
    
    // Obtener la solicitud
    const [requests] = await pool.query(
      'SELECT * FROM cancellation_requests WHERE id = ? AND status = ?',
      [id, 'Pending']
    );
    
    if (requests.length === 0) {
      return res.status(404).json({ error: 'Solicitud no encontrada o ya procesada' });
    }
    
    const request = requests[0];
    
    // Iniciar transacción
    const connection = await pool.getConnection();
    await connection.beginTransaction();
    
    try {
      // Actualizar la solicitud como aprobada
      await connection.query(`
        UPDATE cancellation_requests 
        SET status = ?, 
            reviewed_by = ?, 
            reviewed_by_id = ?,
            reviewed_at = NOW(),
            review_notes = ?
        WHERE id = ?
      `, ['Approved', reviewedBy, reviewedById || null, reviewNotes || null, id]);
      
      // Marcar la entrada como cancelada
      await connection.query(
        'UPDATE control_material_almacen_smd SET cancelado = 1 WHERE id = ?',
        [request.warehousing_id]
      );
      
      await connection.commit();
      
      res.json({ 
        success: true, 
        message: 'Cancelación aprobada. La entrada ha sido cancelada.'
      });
      
    } catch (err) {
      await connection.rollback();
      throw err;
    } finally {
      connection.release();
    }
    
  } catch (err) {
    next(err);
  }
};

// POST /api/cancellation/:id/reject - Rechazar solicitud de cancelación
exports.rejectRequest = async (req, res, next) => {
  try {
    const { id } = req.params;
    const { reviewedBy, reviewedById, reviewNotes } = req.body;
    
    if (!reviewedBy || !reviewNotes) {
      return res.status(400).json({ error: 'Se requiere reviewedBy y reviewNotes (motivo del rechazo)' });
    }
    
    // Verificar que existe y está pendiente
    const [requests] = await pool.query(
      'SELECT id FROM cancellation_requests WHERE id = ? AND status = ?',
      [id, 'Pending']
    );
    
    if (requests.length === 0) {
      return res.status(404).json({ error: 'Solicitud no encontrada o ya procesada' });
    }
    
    // Actualizar como rechazada
    await pool.query(`
      UPDATE cancellation_requests 
      SET status = ?, 
          reviewed_by = ?, 
          reviewed_by_id = ?,
          reviewed_at = NOW(),
          review_notes = ?
      WHERE id = ?
    `, ['Rejected', reviewedBy, reviewedById || null, reviewNotes, id]);
    
    res.json({ 
      success: true, 
      message: 'Solicitud rechazada'
    });
    
  } catch (err) {
    next(err);
  }
};

// GET /api/cancellation/history/:warehousingId - Obtener historial de solicitudes de una entrada
exports.getHistory = async (req, res, next) => {
  try {
    const { warehousingId } = req.params;
    
    const [history] = await pool.query(`
      SELECT 
        id, status, requested_by, requested_at, reason,
        reviewed_by, reviewed_at, review_notes
      FROM cancellation_requests 
      WHERE warehousing_id = ?
      ORDER BY requested_at DESC
    `, [warehousingId]);
    
    res.json(history);
  } catch (err) {
    next(err);
  }
};

// GET /api/cancellation/all - Obtener todas las solicitudes (historial completo)
exports.getAllRequests = async (req, res, next) => {
  try {
    const { status, limit = 100 } = req.query;
    
    let query = `
      SELECT 
        cr.id,
        cr.warehousing_id,
        cr.warehousing_code,
        cr.status,
        cr.requested_by,
        cr.requested_at,
        cr.reason,
        cr.reviewed_by,
        cr.reviewed_at,
        cr.review_notes,
        cma.numero_parte,
        cma.numero_lote_material
      FROM cancellation_requests cr
      LEFT JOIN control_material_almacen_smd cma ON cr.warehousing_id = cma.id
    `;
    
    const params = [];
    if (status) {
      query += ' WHERE cr.status = ?';
      params.push(status);
    }
    
    query += ' ORDER BY cr.requested_at DESC LIMIT ?';
    params.push(parseInt(limit));
    
    const [requests] = await pool.query(query, params);
    res.json(requests);
  } catch (err) {
    next(err);
  }
};

// GET /api/cancellation/status/:warehousingId - Obtener estado actual de cancelación de una entrada
exports.getStatus = async (req, res, next) => {
  try {
    const { warehousingId } = req.params;
    
    // Verificar si está cancelada
    const [entry] = await pool.query(
      'SELECT cancelado FROM control_material_almacen_smd WHERE id = ?',
      [warehousingId]
    );
    
    if (entry.length === 0) {
      return res.status(404).json({ error: 'Entrada no encontrada' });
    }
    
    // Buscar solicitud pendiente
    const [pending] = await pool.query(
      'SELECT id, requested_by, requested_at, reason FROM cancellation_requests WHERE warehousing_id = ? AND status = ?',
      [warehousingId, 'Pending']
    );
    
    res.json({
      isCancelled: entry[0].cancelado === 1,
      hasPendingRequest: pending.length > 0,
      pendingRequest: pending.length > 0 ? pending[0] : null
    });
  } catch (err) {
    next(err);
  }
};
