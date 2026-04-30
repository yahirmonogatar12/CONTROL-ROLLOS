const express = require('express');
const router = express.Router();
const returnController = require('../controllers/return.controller');

// GET /api/return - Obtener todas las devoluciones
router.get('/', returnController.getAll);

// GET /api/return/search - Buscar devoluciones por fecha
router.get('/search', returnController.search);

// GET /api/return/by-warehousing/:code - Obtener info de entrada por código
router.get('/by-warehousing/:code', returnController.getWarehousingInfo);

// GET /api/return/:id - Obtener una devolución por ID
router.get('/:id', returnController.getById);

// POST /api/return - Crear una nueva devolución
router.post('/', returnController.create);

// DELETE /api/return/:id - Eliminar una devolución
router.delete('/:id', returnController.delete);

module.exports = router;
