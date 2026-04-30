/**
 * Plan Routes - Plan de Producción y BOM
 * Pantalla Flutter: lib/screens/plan_main/
 */

const express = require('express');
const router = express.Router();
const planController = require('../controllers/plan.controller');

// Plan routes
router.get('/today', planController.getToday);
router.get('/bom/:partNo', planController.getBomByPartNo);

// BOM routes (montadas en /api/bom)
// Estas se exportan por separado para montarlas con prefijo diferente

module.exports = router;

// Exportar BOM router separado
const bomRouter = express.Router();
bomRouter.get('/models', planController.getBomModels);
bomRouter.get('/:modelo', planController.getBomByModelo);

module.exports.bomRouter = bomRouter;
