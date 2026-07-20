/**
 * Scrap Routes - Registro de scrap por escaneo QR
 */
const express = require('express');
const router = express.Router();
const ctrl = require('../controllers/scrap.controller');

router.get('/lookup-raw-barcode', ctrl.lookupRawBarcode);
router.post('/scan', ctrl.scan);
router.get('/records', ctrl.getRecords);
router.get('/autocomplete', ctrl.autocomplete);
router.put('/record/:id', ctrl.updateRecord);
router.delete('/record/:id', ctrl.deleteRecord);

module.exports = router;

