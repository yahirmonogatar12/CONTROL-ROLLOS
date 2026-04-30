/**
 * Quality Specs Routes - Especificaciones de Calidad
 * Relacionado con: lib/screens/iqc/
 */

const express = require('express');
const router = express.Router();
const qualitySpecsController = require('../controllers/quality-specs.controller');

// CRUD
router.get('/', qualitySpecsController.getAll);
router.get('/part/:partNumber', qualitySpecsController.getByPartNumber);
router.get('/:id', qualitySpecsController.getById);
router.post('/', qualitySpecsController.create);
router.put('/:id', qualitySpecsController.update);
router.delete('/:id', qualitySpecsController.delete);

// Bulk operations
router.post('/bulk-upload', qualitySpecsController.bulkUpload);
router.post('/copy', qualitySpecsController.copy);

module.exports = router;
