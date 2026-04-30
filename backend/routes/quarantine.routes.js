/**
 * Quarantine Routes - Cuarentena
 */

const router = require('express').Router();
const ctrl = require('../controllers/quarantine.controller');

// GET /api/quarantine - Materiales en cuarentena
router.get('/', ctrl.getAll);

// GET /api/quarantine/history/all - Historial completo
router.get('/history/all', ctrl.getAllHistory);

// GET /api/quarantine/:id/history - Historial de un item
router.get('/:id/history', ctrl.getHistory);

// POST /api/quarantine/send - Enviar materiales a cuarentena
router.post('/send', ctrl.send);

// PUT /api/quarantine/:id - Actualizar estado
router.put('/:id', ctrl.update);

// POST /api/quarantine/:id/comment - Agregar comentario
router.post('/:id/comment', ctrl.addComment);

module.exports = router;
