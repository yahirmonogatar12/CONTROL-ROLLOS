'use strict';

const express = require('express');
const controller = require('../controllers/tooling.controller');

const router = express.Router();

router.get('/assets', controller.listAssets);
router.get('/summary', controller.summary);
router.get('/assignments', controller.listAssignments);
router.post('/assets', controller.createAsset);
router.patch('/assets/:code', controller.updateAsset);
router.post('/validate', controller.validate);
router.post('/assignments', controller.assignPlan);

module.exports = router;
