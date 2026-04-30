/**
 * Agregador de rutas
 * Registra todos los módulos de rutas
 */
const express = require('express');
const router = express.Router();

// ============================================
// IMPORTAR MÓDULOS DE RUTAS
// ============================================

// Fase 1: Warehousing y Outgoing
const warehousingRoutes = require('./warehousing.routes');
const outgoingRoutes = require('./outgoing.routes');

// Fase 2: Plan, Auth, Materials, IQC, Quality Specs, Quarantine, Shortage
const planRoutes = require('./plan.routes');
const shortageRoutes = require('./shortage.routes');
const { authRouter, usersRouter, departmentsRouter, cargosRouter, permissionsRouter } = require('./auth.routes');
const materialesRoutes = require('./materials.routes');
const { materialCodesRouter } = require('./materials.routes');
const iqcRoutes = require('./iqc.routes');
const qualitySpecsRoutes = require('./quality-specs.routes');
const quarantineRoutes = require('./quarantine.routes');

// Fase 3: Inventory y Customers
const inventoryRoutes = require('./inventory.routes');
const customersRoutes = require('./customers.routes');

// Fase 4: Cancellation (Solicitudes de cancelación)
const cancellationRoutes = require('./cancellation.routes');

// Fase 5: Material Return (Devolución de Material)
const returnRoutes = require('./return.routes');

// Fase 6: Print (Impresión remota para móviles)
const printRoutes = require('./print.routes');

// ============================================
// REGISTRAR RUTAS
// ============================================

// Fase 1
router.use('/warehousing', warehousingRoutes);
router.use('/outgoing', outgoingRoutes);

// Fase 2
router.use('/plan', planRoutes);
router.use('/bom', planRoutes);
router.use('/shortage', shortageRoutes);
router.use('/auth', authRouter);
router.use('/users', usersRouter);
router.use('/departments', departmentsRouter);
router.use('/cargos', cargosRouter);
router.use('/permissions', permissionsRouter);
router.use('/materiales', materialesRoutes);
router.use('/materials', materialCodesRouter);
router.use('/iqc', iqcRoutes);
router.use('/quality-specs', qualitySpecsRoutes);
router.use('/quarantine', quarantineRoutes);

// Fase 3
router.use('/inventory', inventoryRoutes);
router.use('/customers', customersRoutes);

// Fase 4
router.use('/cancellation', cancellationRoutes);

// Fase 5
router.use('/return', returnRoutes);

// Fase 6
router.use('/print', printRoutes);

module.exports = router;
