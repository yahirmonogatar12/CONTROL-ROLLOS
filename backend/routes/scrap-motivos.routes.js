/**
 * Scrap Motivos Routes - Catalogo de motivos de scrap
 */
const express = require('express');
const router = express.Router();
const ctrl = require('../controllers/scrap-motivos.controller');

router.get('/', ctrl.getAll);
router.post('/', ctrl.create);
router.put('/:id', ctrl.update);
router.delete('/:id', ctrl.delete);

module.exports = router;

