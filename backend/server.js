const express = require('express');
const cors = require('cors');
const path = require('path');
const fs = require('fs');

// Determinar la ruta del archivo .env
function getEnvPath() {
  const exeDir = path.dirname(process.execPath);
  const exeEnvPath = path.join(exeDir, '.env');

  if (fs.existsSync(exeEnvPath)) {
    console.log('📂 Usando .env desde:', exeEnvPath);
    return exeEnvPath;
  }

  const devEnvPath = path.join(__dirname, '.env');
  if (fs.existsSync(devEnvPath)) {
    console.log('📂 Usando .env desde:', devEnvPath);
    return devEnvPath;
  }

  const cwdEnvPath = path.join(process.cwd(), '.env');
  console.log('📂 Buscando .env en:', cwdEnvPath);
  return cwdEnvPath;
}

require('dotenv').config({ path: getEnvPath() });

const { pool, testConnection, getPoolStats } = require('./config/database');
const { runMigrations } = require('./utils/dbMigrations');
const { startDiscoveryService } = require('./utils/udpDiscovery');
const errorHandler = require('./middleware/errorHandler');
const gzipJsonBodyParser = require('./middleware/gzipJsonBodyParser');
const idempotencyMiddleware = require('./middleware/idempotency');
const responseCompression = require('./middleware/responseCompression');
const { rateLimiter, writeRateLimiter, getRateLimitStats } = require('./middleware/rateLimiter');

// ============================================
// IMPORTAR RUTAS MODULARIZADAS
// ============================================

// Fase 1: Warehousing y Outgoing
const warehousingRoutes = require('./routes/warehousing.routes');
const outgoingRoutes = require('./routes/outgoing.routes');

// Fase 2: Plan, Auth, Materials, IQC, Quality Specs, Quarantine
const planRoutes = require('./routes/plan.routes');
const { authRouter, usersRouter, departmentsRouter, cargosRouter, permissionsRouter } = require('./routes/auth.routes');
const materialesRoutes = require('./routes/materials.routes');
const { materialCodesRouter } = require('./routes/materials.routes');
const iqcRoutes = require('./routes/iqc.routes');
const qualitySpecsRoutes = require('./routes/quality-specs.routes');
const quarantineRoutes = require('./routes/quarantine.routes');

// Fase 3: Inventory y Customers
const inventoryRoutes = require('./routes/inventory.routes');
const customersRoutes = require('./routes/customers.routes');

// Fase 4: Cancellation (Solicitudes de cancelación)
const cancellationRoutes = require('./routes/cancellation.routes');

// Fase 5: Material Return (Devoluciones)
const returnRoutes = require('./routes/return.routes');

// Fase 6: Print (Impresión remota para móviles)
const printRoutes = require('./routes/print.routes');

// Fase 7: Audit (Sistema de auditoría de inventario)
const auditRoutes = require('./routes/audit.routes');

// Fase 8: Blacklist (Lista negra de lotes)
const blacklistRoutes = require('./routes/blacklist.routes');

// Fase 9: Updates (Sistema de actualizaciones remotas)
const updatesRoutes = require('./routes/updates.routes');

// Fase 9.5: SMT Material Requests (solicitudes desde lineas SMT)
const smtRequestsRoutes = require('./routes/smt-requests.routes');

// Fase 10: Requirements (Requerimientos de material)
const requirementsRoutes = require('./routes/requirements.routes');

// Fase 11: Reentry (Reingreso/Reubicación de materiales)
const reentryRoutes = require('./routes/reentry.routes');

// Fase 12: Shortage (Calculo de faltante de material SMD)
const shortageRoutes = require('./routes/shortage.routes');

// Fase 13: PCB Inventory (Inventario de PCBs por escaneo)
const pcbInventoryRoutes = require('./routes/pcb-inventory.routes');
const pcbDefectsRoutes = require('./routes/pcb-defects.routes');

const app = express();
const jsonParser = express.json({
  limit: '50mb',
  verify: (req, res, buf) => {
    req.rawBody = buf.toString('utf8');
  }
});

// ============================================
// MIDDLEWARES
// ============================================
app.use(cors());
app.use(gzipJsonBodyParser);
app.use((req, res, next) => {
  if (req._body || req.body !== undefined) {
    return next();
  }
  return jsonParser(req, res, next);
});  // Aumentado para bulk imports
app.use(express.urlencoded({ limit: '50mb', extended: true }));

// Rate limiting para proteger contra sobrecarga (múltiples dispositivos)
app.use(rateLimiter);
app.use(idempotencyMiddleware);
app.use(responseCompression);

// Rate limiting más estricto para operaciones de escritura
app.post('*', writeRateLimiter);
app.put('*', writeRateLimiter);
app.delete('*', writeRateLimiter);

// ============================================
// RUTAS MODULARIZADAS
// ============================================

// Fase 1: Warehousing y Outgoing
app.use('/api/warehousing', warehousingRoutes);
app.use('/api/outgoing', outgoingRoutes);

// Fase 2: Plan, Auth, Materials, IQC, Quality Specs, Quarantine
app.use('/api/plan', planRoutes);
app.use('/api/bom', planRoutes);
app.use('/api/auth', authRouter);
app.use('/api/users', usersRouter);
app.use('/api/departments', departmentsRouter);
app.use('/api/cargos', cargosRouter);
app.use('/api/permissions', permissionsRouter);
app.use('/api/materiales', materialesRoutes);
app.use('/api/materials', materialCodesRouter);
app.use('/api/iqc', iqcRoutes);
app.use('/api/quality-specs', qualitySpecsRoutes);
app.use('/api/quarantine', quarantineRoutes);

// Fase 3: Inventory y Customers
app.use('/api/inventory', inventoryRoutes);
app.use('/api/customers', customersRoutes);

// Fase 4: Cancellation
app.use('/api/cancellation', cancellationRoutes);

// Fase 5: Material Return
app.use('/api/return', returnRoutes);

// Fase 6: Print (Impresión remota para móviles)
app.use('/api/print', printRoutes);

// Fase 7: Audit (Sistema de auditoría de inventario)
app.use('/api/audit', auditRoutes);

// Fase 8: Blacklist (Lista negra de lotes)
app.use('/api/blacklist', blacklistRoutes);

// Fase 9: Updates (Sistema de actualizaciones remotas)
app.use('/api/updates', updatesRoutes);

// Fase 9.5: SMT Material Requests
app.use('/api/smt-requests', smtRequestsRoutes);

// Fase 10: Requirements (Requerimientos de material)
app.use('/api/requirements', requirementsRoutes);

// Fase 11: Reentry (Reingreso/Reubicación)
app.use('/api/reentry', reentryRoutes);

// Fase 12: Shortage (Calculo de faltante de material)
app.use('/api/shortage', shortageRoutes);

// Fase 13: PCB Inventory (Inventario de PCBs por escaneo)
app.use('/api/pcb-inventory', pcbInventoryRoutes);
app.use('/api/pcb-defects', pcbDefectsRoutes);

// ============================================
// RUTA DE PRUEBA (Health Check)
// ============================================
app.get('/api/health', async (req, res) => {
  const dbConnected = await testConnection();
  const poolStats = getPoolStats();
  const rateLimitStats = getRateLimitStats();

  res.json({
    status: 'OK',
    database: dbConnected ? 'Connected' : 'Disconnected',
    pool: poolStats,
    rateLimiting: {
      activeClients: rateLimitStats.activeClients
    },
    server: {
      uptime: Math.floor(process.uptime()),
      memory: {
        used: Math.round(process.memoryUsage().heapUsed / 1024 / 1024),
        total: Math.round(process.memoryUsage().heapTotal / 1024 / 1024),
        unit: 'MB'
      }
    },
    timestamp: new Date().toISOString()
  });
});

// ============================================
// RUTA DE DIAGNÓSTICO DETALLADO (solo para debug)
// ============================================
app.get('/api/health/detailed', async (req, res) => {
  const dbConnected = await testConnection();
  const poolStats = getPoolStats();
  const rateLimitStats = getRateLimitStats();

  res.json({
    status: 'OK',
    database: {
      connected: dbConnected,
      pool: poolStats
    },
    rateLimiting: rateLimitStats,
    server: {
      uptime: Math.floor(process.uptime()),
      uptimeFormatted: formatUptime(process.uptime()),
      memory: process.memoryUsage(),
      nodeVersion: process.version,
      platform: process.platform
    },
    timestamp: new Date().toISOString()
  });
});

// Helper para formatear uptime
function formatUptime(seconds) {
  const days = Math.floor(seconds / 86400);
  const hours = Math.floor((seconds % 86400) / 3600);
  const minutes = Math.floor((seconds % 3600) / 60);
  return `${days}d ${hours}h ${minutes}m`;
}

// ============================================
// RUTA PARA MARCAR REGISTROS COMO CANCELADOS
// ============================================
app.post('/api/admin/cancel-all-records', async (req, res) => {
  try {
    // Marcar como cancelado (el historial se mantiene)
    const [resultAlmacen] = await pool.query(
      'UPDATE control_material_almacen_smd SET cancelado = 1 WHERE cancelado = 0'
    );

    let resultSalida = { affectedRows: 0 };
    let resultReturn = { affectedRows: 0 };

    try {
      [resultSalida] = await pool.query(
        'UPDATE control_material_salida_smd SET cancelado = 1 WHERE cancelado = 0'
      );
    } catch (e) { /* columna no existe */ }

    try {
      [resultReturn] = await pool.query(
        'UPDATE material_return_smd SET cancelado = 1 WHERE cancelado = 0'
      );
    } catch (e) { /* columna no existe */ }

    res.json({
      success: true,
      message: 'Registros marcados como cancelados (historial mantenido)',
      affected: {
        almacen: resultAlmacen.affectedRows,
        salida: resultSalida.affectedRows,
        return: resultReturn.affectedRows
      }
    });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// ============================================
// MIDDLEWARE DE ERRORES
// ============================================
app.use(errorHandler);

// ============================================
// INICIAR SERVIDOR
// ============================================
const PORT = process.env.PORT || 3010;
const HOST = process.env.HOST || '0.0.0.0'; // Escuchar en todas las interfaces

// Función para obtener la IP local
function getLocalIP() {
  const os = require('os');
  const interfaces = os.networkInterfaces();
  for (const name of Object.keys(interfaces)) {
    for (const iface of interfaces[name]) {
      // Ignorar interfaces internas y IPv6
      if (iface.family === 'IPv4' && !iface.internal) {
        return iface.address;
      }
    }
  }
  return 'localhost';
}

// Solo iniciar servidor si no es Vercel (serverless)
if (process.env.VERCEL !== '1') {
  // Iniciar servidor Express directamente
  app.listen(PORT, HOST, async () => {
    const localIP = getLocalIP();
    console.log(`API escuchando en:`);
    console.log(`   - Local:   http://localhost:${PORT}`);
    console.log(`   - Red:     http://${localIP}:${PORT}`);
    console.log(`Usa la dirección de Red para conectar desde dispositivos móviles`);
    await testConnection();
    await runMigrations();

    // Iniciar servicio de auto-descubrimiento UDP
    const discovery = startDiscoveryService(PORT);
    console.log(`📡 Auto-descubrimiento UDP activo en puerto ${discovery.getInfo().discoveryPort}`);
  });
}

// Exportar para Vercel serverless
module.exports = app;
