/**
 * Reentry Routes - Rutas de Reingreso/Reubicación
 */

const express = require('express');
const router = express.Router();
const controller = require('../controllers/reentry.controller');

// GET - Buscar material por código
router.get('/by-code/:code', controller.getByCode);
router.post('/by-codes', controller.getByCodes);

// GET - Historial de reingresos
router.get('/history', controller.getReentryHistory);

// PUT - Actualizar ubicación individual
router.put('/:id/location', controller.updateLocation);

// POST - Reingreso masivo
router.post('/bulk', controller.bulkReentry);

module.exports = router;
