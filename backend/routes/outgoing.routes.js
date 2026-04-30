/**
 * Rutas para Outgoing (Salida de Material)
 * Corresponde a: screens/material_outgoing/
 */
const express = require('express');
const router = express.Router();
const controller = require('../controllers/outgoing.controller');

// Rutas específicas primero
router.get('/check-salida/:code', controller.checkSalida);
router.get('/locations-by-partnumber', controller.getLocationsByPartNumber);
router.get('/search', controller.search);

// Rutas para salida en lote (móvil)
router.post('/validate-batch', controller.validateBatch);
router.post('/batch', controller.createBatch);

// Ruta para división de lotes
router.post('/split-lot', controller.splitLot);

// Rutas CRUD
router.get('/', controller.getAll);
router.post('/', controller.create);

module.exports = router;
