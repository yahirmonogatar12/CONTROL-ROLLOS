/**
 * Customers Routes - Catálogo de Clientes
 */

const router = require('express').Router();
const ctrl = require('../controllers/customers.controller');

// GET /api/customers - Lista clientes únicos
router.get('/', ctrl.getAll);

module.exports = router;
