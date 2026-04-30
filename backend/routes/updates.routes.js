const express = require('express');
const router = express.Router();
const updatesController = require('../controllers/updates.controller');

// Verificar actualizaciones disponibles
router.get('/check', updatesController.checkForUpdates);

// Lista de todas las versiones
router.get('/versions', updatesController.getAllVersions);

// Crear nueva versión
router.post('/versions', updatesController.createVersion);

// Actualizar versión
router.put('/versions/:id', updatesController.updateVersion);

// Eliminar versión
router.delete('/versions/:id', updatesController.deleteVersion);

// Descargar instalador
router.get('/download/:version', updatesController.downloadInstaller);

module.exports = router;
