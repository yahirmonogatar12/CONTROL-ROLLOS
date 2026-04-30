/**
 * Materials Routes - Catálogo de Materiales
 * Pantalla Flutter: lib/screens/material_control/
 */

const express = require('express');
const materialsController = require('../controllers/materials.controller');

// Main router (montado en /api/materiales)
const router = express.Router();
router.get('/', materialsController.getAll);
router.get('/by-code/:materialCode', materialsController.getByCode);
router.get('/by-part-number/:partNumber', materialsController.getByPartNumber);
router.post('/', materialsController.create);
router.post('/parse-barcode', materialsController.parseBarcode);
router.post('/bulk-update-comparacion', materialsController.bulkUpdateComparacion);
router.post('/bulk-update-ubicacion-rollos', materialsController.bulkUpdateUbicacionRollos);
router.post('/validate-part-numbers', materialsController.validatePartNumbers);
router.post('/create-simple', materialsController.createSimple);
router.put('/:numeroParte', materialsController.update);
router.put('/:numeroParte/comparacion', materialsController.updateComparacion);
router.delete('/:numeroParte', materialsController.delete);

// IQC Config routes
router.get('/iqc-required', materialsController.getIqcRequired);
router.put('/:numeroParte/iqc-required', materialsController.setIqcRequired);
router.get('/iqc-config', materialsController.getIqcConfigList);
router.get('/:partNumber/iqc-config', materialsController.getIqcConfig);
router.put('/:numeroParte/iqc-config', materialsController.updateIqcConfig);
router.post('/iqc-config/bulk', materialsController.bulkUpdateIqcConfig);

// Material codes router (montado en /api/materials)
const materialCodesRouter = express.Router();
materialCodesRouter.get('/', materialsController.getMaterialCodes);

module.exports = router;
module.exports.materialCodesRouter = materialCodesRouter;
