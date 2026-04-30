/**
 * Cancellation Routes - Rutas para solicitudes de cancelación
 * Pantalla Flutter: lib/screens/material_warehousing/
 */

const express = require('express');
const router = express.Router();
const cancellationController = require('../controllers/cancellation.controller');

// Solicitar cancelación
router.post('/request', cancellationController.requestCancellation);

// Obtener solicitudes pendientes (para supervisores)
router.get('/pending', cancellationController.getPendingRequests);

// Obtener conteo de solicitudes pendientes
router.get('/pending/count', cancellationController.getPendingCount);

// Aprobar solicitud
router.post('/:id/approve', cancellationController.approveRequest);

// Rechazar solicitud
router.post('/:id/reject', cancellationController.rejectRequest);

// Historial de una entrada específica
router.get('/history/:warehousingId', cancellationController.getHistory);

// Todas las solicitudes (historial completo)
router.get('/all', cancellationController.getAllRequests);

// Estado de cancelación de una entrada
router.get('/status/:warehousingId', cancellationController.getStatus);

module.exports = router;
