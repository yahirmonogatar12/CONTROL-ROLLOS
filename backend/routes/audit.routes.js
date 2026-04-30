/**
 * Rutas para Auditoria de Inventario
 * Sistema de verificacion fisica de materiales
 *
 * Agrupa endpoints por rol:
 * - Gestion (PC supervisor): inicia/finaliza y consulta resumen.
 * - Operaciones (movil): escaneo de ubicaciones/materiales.
 * - Audit V2: flujo por numero de parte (confirmacion sin escaneo).
 * - Historial: auditorias completadas y comparaciones.
 */
const express = require('express');
const router = express.Router();
const controller = require('../controllers/audit.controller');

// ============================================
// RUTAS DE GESTION (PC)
// ============================================

// Obtener auditoria activa (Pending/InProgress)
router.get('/active', controller.getActiveAudit);

// Iniciar nueva auditoria (crea ubicaciones/items esperados)
router.post('/start', controller.startAudit);

// Terminar auditoria (genera Missing y salidas por discrepancia)
router.post('/end', controller.endAudit);

// Obtener resumen de auditoria activa para UI supervisor
router.get('/summary', controller.getAuditSummary);

// Obtener ubicaciones de auditoria y conteos (Found/Missing)
router.get('/locations', controller.getAuditLocations);

// Obtener items de una ubicacion con audit_status
router.get('/location-items', controller.getLocationItems);

// ============================================
// RUTAS MOVILES (flujo original)
// ============================================

// Escanear ubicacion (inicia verificacion en esa ubicacion)
router.post('/scan-location', controller.scanLocation);

// Escanear material (marca Found)
router.post('/scan-item', controller.scanItem);

// Marcar material como no encontrado (Missing)
router.post('/mark-missing', controller.markMissing);

// Completar ubicacion (Pending -> Missing y cierre de ubicacion)
router.post('/complete-location', controller.completeLocation);

// ============================================
// RUTAS AUDIT V2 - Flujo por número de parte
// ============================================

// Obtener resumen de partes por ubicación
router.get('/location-summary', controller.getLocationSummary);

// Confirmar parte como OK sin escaneo
router.post('/confirm-part', controller.confirmPart);

// Marcar parte como discrepancia (habilita escaneo)
router.post('/flag-mismatch', controller.flagMismatch);

// Escanear etiqueta individual de una parte en Mismatch
router.post('/scan-part-item', controller.scanPartItem);

// Confirmar faltantes de una parte en Mismatch
router.post('/confirm-missing', controller.confirmMissing);

// ============================================
// RUTAS DE HISTORIAL
// ============================================

// Historial de auditorias (solo Completed)
router.get('/history', controller.getAuditHistory);

// Detalle de auditoria historica (audit + ubicaciones + items)
router.get('/history/:id', controller.getAuditHistoryDetail);

// Comparar dos auditorias (diferencias por numero_parte)
router.get('/compare', controller.compareAudits);

// ============================================
// RUTAS DE APROBACIÓN DE DISCREPANCIAS (PC Supervisor)
// ============================================

// Obtener items pendientes de aprobación
router.get('/pending-approvals', controller.getPendingApprovals);

// Aprobar discrepancia y generar salida
router.post('/approve-discrepancy', controller.approveDiscrepancy);

// Rechazar discrepancia (marcar como encontrado)
router.post('/reject-discrepancy', controller.rejectDiscrepancy);

module.exports = router;
