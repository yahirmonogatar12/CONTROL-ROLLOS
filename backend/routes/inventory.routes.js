/**
 * Inventory Routes - Inventario de Lotes
 */

const router = require('express').Router();
const ctrl = require('../controllers/inventory.controller');

// GET /api/inventory/summary - Inventario agrupado
router.get('/summary', ctrl.getSummary);

// GET /api/inventory/lots - Detalle de lotes
router.get('/lots', ctrl.getLots);

// GET /api/inventory/search-label - Buscar por etiqueta
router.get('/search-label', ctrl.searchByLabel);

// GET /api/inventory/location-search - Buscar ubicación por numero de parte
router.get('/location-search', ctrl.locationSearch);
router.get('/mobile-search', ctrl.mobileSearch);

module.exports = router;
