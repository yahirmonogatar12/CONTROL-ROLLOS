/**
 * Blacklist Routes - Rutas para gestión de lista negra de lotes
 */
const express = require('express');
const router = express.Router();
const blacklistController = require('../controllers/blacklist.controller');

// GET /api/blacklist - Obtener todos los lotes en lista negra
router.get('/', blacklistController.getAll);

// GET /api/blacklist/search - Buscar con filtros
router.get('/search', blacklistController.search);

// GET /api/blacklist/check/:lotId - Verificar si un lote está en lista negra
router.get('/check/:lotId', blacklistController.checkLot);

// POST /api/blacklist - Agregar lote a lista negra
router.post('/', blacklistController.add);

// PUT /api/blacklist/:id - Actualizar registro
router.put('/:id', blacklistController.update);

// DELETE /api/blacklist/:id - Eliminar lote de lista negra
router.delete('/:id', blacklistController.remove);

module.exports = router;
