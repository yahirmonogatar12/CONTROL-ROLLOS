/**
 * Rutas para Warehousing (Entrada de Material)
 * Corresponde a: screens/material_warehousing/
 */
const express = require('express');
const router = express.Router();
const controller = require('../controllers/warehousing.controller');

// Rutas específicas primero (antes de /:id)
router.get('/search', controller.search);
router.get('/by-code/:code', controller.getByCode);
router.get('/smart-search/:code', controller.smartSearch);
router.get('/next-sequence', controller.getNextSequence);
router.get('/next-sequence-preview', controller.getNextSequencePreview);  // Nueva: preview sin afectar cache
router.get('/reserve-sequences', controller.reserveSequences);  // Nueva: reservar múltiples secuencias atómicamente
router.get('/next-internal-lot-sequence', controller.getNextInternalLotSequence);
router.get('/fifo-check', controller.fifoCheck);
router.get('/count-iqc-pending', controller.countIqcPending);
router.get('/pending-from-warehouse', controller.getPendingFromWarehouse);
router.get('/rejected-from-warehouse', controller.getRejectedFromWarehouse);
router.get('/search-warehouse-material', controller.searchWarehouseMaterial);
router.post('/search-warehouse-materials', controller.searchWarehouseMaterials);
router.post('/bulk-import', controller.bulkImport);  // Importación masiva desde CSV
router.post('/confirm-from-warehouse', controller.confirmFromWarehouse);
router.post('/confirm-from-warehouse-by-part', controller.confirmFromWarehouseByPart);
router.post('/confirm-from-warehouse-by-ids', controller.confirmFromWarehouseByIds);
router.post('/reject-from-warehouse-by-part', controller.rejectFromWarehouseByPart);
router.post('/reject-from-warehouse-by-ids', controller.rejectFromWarehouseByIds);
router.post('/verify-direct-entry-password', controller.verifyDirectEntryPassword);
router.put('/bulk-update', controller.bulkUpdate);  // Actualización masiva de múltiples registros

// Rutas CRUD estándar
router.get('/', controller.getAll);
router.get('/:id', controller.getById);
router.post('/', controller.create);
router.put('/:id', controller.update);
router.delete('/:id', controller.delete);

module.exports = router;


