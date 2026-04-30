/**
 * IQC Routes - Inspección de Calidad Entrante
 * Pantalla Flutter: lib/screens/iqc/
 */

const express = require('express');
const router = express.Router();
const iqcController = require('../controllers/iqc.controller');

// Lot lookup
router.get('/lot/:labelCode', iqcController.getLotByLabel);

// Pending and history
router.get('/pending', iqcController.getPending);
router.get('/history', iqcController.getHistory);
router.get('/count-pending', iqcController.countPending);

// Inspection CRUD
router.get('/inspection/:id', iqcController.getById);
router.get('/inspection/:id/can-release', iqcController.canRelease);
router.post('/inspection', iqcController.create);
router.patch('/inspection/:id/result', iqcController.updateResult);
router.put('/inspection/:id', iqcController.update);
router.put('/close/:id', iqcController.close);

// Details
router.post('/detail', iqcController.addDetail);
router.get('/detail/:inspectionId', iqcController.getDetails);
router.delete('/detail/:id', iqcController.deleteDetail);

// Measurements
router.post('/:id/measurements', iqcController.saveMeasurements);
router.get('/:id/measurements', iqcController.getMeasurements);

module.exports = router;
