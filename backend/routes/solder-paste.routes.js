'use strict';

const express = require('express');
const controller = require('../controllers/solder-paste.controller');

const router = express.Router();

router.get('/processes', controller.getAll);
router.get('/events', controller.getEvents);
router.get('/local-notifications', controller.getLocalNotifications);
router.get('/status/:code', controller.getStatus);
router.post('/scan', controller.scan);
router.post('/:id/agitation/start', controller.startAgitation);
router.post('/:id/line', controller.assignLine);
router.post('/:id/consume', controller.consume);
router.post('/:id/return-to-cold', controller.returnToCold);
router.post('/:id/cancel', controller.cancel);

module.exports = router;
