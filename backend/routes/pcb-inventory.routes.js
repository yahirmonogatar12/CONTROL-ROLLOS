/**
 * PCB Inventory Routes - Inventario de PCBs por escaneo
 */

const router = require('express').Router();
const ctrl = require('../controllers/pcb-inventory.controller');

// POST /api/pcb-inventory/scan - Registrar escaneo
router.post('/scan', ctrl.scan);

// GET /api/pcb-inventory/summary - Resumen agrupado
router.get('/summary', ctrl.getSummary);

// GET /api/pcb-inventory/scans - Historial detallado
router.get('/scans', ctrl.getScans);

// GET /api/pcb-inventory/stock-summary - Inventario actual (entradas - salidas - scrap)
router.get('/stock-summary', ctrl.getStockSummary);

// GET /api/pcb-inventory/stock-detail - Detalle de todos los movimientos
router.get('/stock-detail', ctrl.getStockDetail);

// DELETE /api/pcb-inventory/scan/:id - Eliminar un escaneo
router.delete('/scan/:id', ctrl.deleteScan);

module.exports = router;
