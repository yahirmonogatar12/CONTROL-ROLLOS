/**
 * Shortage Routes - Calculo de Faltante de Material SMD
 */

const express = require('express');
const router = express.Router();
const shortageController = require('../controllers/shortage.controller');

router.get('/', shortageController.calculate);
router.get('/lines', shortageController.getLines);

module.exports = router;
