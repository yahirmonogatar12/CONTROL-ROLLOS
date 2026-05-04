/**
 * PCB Defects Routes - Catalogo de defectos para reparacion PCB
 */
const router = require('express').Router();
const ctrl = require('../controllers/pcb-defects.controller');

router.get('/', ctrl.getAll);
router.post('/', ctrl.create);
router.put('/:id', ctrl.update);
router.delete('/:id', ctrl.remove);

module.exports = router;
