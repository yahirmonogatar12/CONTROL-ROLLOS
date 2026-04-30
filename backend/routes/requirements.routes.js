/**
 * Requirements Routes - Rutas de Requerimientos de Material
 * Pantalla Flutter: lib/screens/material_requirements/
 */

const express = require('express');
const router = express.Router();
const controller = require('../controllers/requirements.controller');

// Rutas de listado y utilidades (antes de /:id)
router.get('/', controller.getAll);
router.get('/pending-by-area', controller.getPendingByArea);
router.get('/pending-for-outgoing', controller.getPendingForOutgoing);
router.get('/count-pending', controller.getCountPending);
router.get('/areas', controller.getAreas);
router.get('/import-bom/:modelo', controller.importFromBom);
router.post('/link-outgoing', controller.linkOutgoing);

// CRUD de requerimientos
router.get('/:id', controller.getById);
router.post('/', controller.create);
router.put('/:id', controller.update);
router.delete('/:id', controller.cancel);

// Items de requerimiento
router.get('/:id/items', controller.getItems);
router.post('/:id/items', controller.addItems);
router.post('/:id/items/delete-multiple', controller.removeMultipleItems);
router.put('/:id/items/:itemId', controller.updateItem);
router.delete('/:id/items/:itemId', controller.removeItem);

module.exports = router;
