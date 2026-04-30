const mysql = require('mysql2/promise');
// El .env ya fue cargado en server.js, no recargar aquí

// Configuración optimizada para múltiples dispositivos móviles concurrentes
const pool = mysql.createPool({
  host: process.env.DB_HOST || 'localhost',
  port: parseInt(process.env.DB_PORT || '3306'),
  user: process.env.DB_USER || 'root',
  password: process.env.DB_PASSWORD || '',
  database: process.env.DB_NAME || 'meslocal',
  waitForConnections: true,
  connectionLimit: parseInt(process.env.DB_POOL_SIZE || '3'),  // Bajo para no saturar MySQL
  queueLimit: 0,               // Sin limite de cola, las peticiones esperan su turno
  connectTimeout: 30000,        // 30 segundos para conectar (más rápido failover)
  enableKeepAlive: true,        // Mantener conexiones vivas
  keepAliveInitialDelay: 10000, // Delay inicial para keep-alive
  timezone: '-06:00',           // Zona horaria México (CST/UTC-6) - para serialización JS
  dateStrings: true,            // Devolver fechas como strings sin conversión
  maxIdle: 3,                   // Máximo conexiones inactivas = connectionLimit
  idleTimeout: 60000,           // Timeout para conexiones inactivas (60s)
});

// Establecer time_zone de MySQL en cada conexión nueva del pool
// Esto asegura que NOW(), CURRENT_TIMESTAMP, etc. devuelvan hora de México
pool.on('connection', (connection) => {
  connection.query("SET time_zone = '-06:00'");
});

// Función helper para obtener fecha/hora actual en zona horaria México
const getMexicoDateTime = () => {
  const now = new Date();
  // Ajustar a UTC-6 (México CST)
  const mexicoTime = new Date(now.getTime() - (6 * 60 * 60 * 1000) + (now.getTimezoneOffset() * 60 * 1000));
  return mexicoTime.toISOString().slice(0, 19).replace('T', ' ');
};

const getMexicoDate = () => {
  return getMexicoDateTime().slice(0, 10);
};

// Monitor de conexiones del pool
let poolStats = {
  totalConnections: 0,
  activeConnections: 0,
  idleConnections: 0,
  waitingRequests: 0
};

const getPoolStats = () => {
  try {
    const poolConfig = pool.pool;
    if (poolConfig) {
      poolStats = {
        totalConnections: poolConfig._allConnections?.length || 0,
        activeConnections: poolConfig._allConnections?.length - poolConfig._freeConnections?.length || 0,
        idleConnections: poolConfig._freeConnections?.length || 0,
        waitingRequests: poolConfig._connectionQueue?.length || 0
      };
    }
  } catch (e) {
    // Silenciar errores de stats
  }
  return poolStats;
};

// Test connection
const testConnection = async () => {
  try {
    const connection = await pool.getConnection();
    console.log('✅ Conexión a MySQL exitosa');
    connection.release();
    return true;
  } catch (error) {
    console.error('❌ Error conectando a MySQL:', error.message);
    return false;
  }
};

// Ejecutar query con timeout y retry
const executeWithRetry = async (queryFn, maxRetries = 3) => {
  let lastError;
  for (let attempt = 1; attempt <= maxRetries; attempt++) {
    try {
      return await queryFn();
    } catch (error) {
      lastError = error;
      // Solo reintentar en errores de conexión, no en errores de lógica
      if (error.code === 'ECONNRESET' || error.code === 'PROTOCOL_CONNECTION_LOST' || error.code === 'ER_CON_COUNT_ERROR') {
        console.warn(`⚠️ Intento ${attempt}/${maxRetries} fallido: ${error.message}`);
        if (attempt < maxRetries) {
          await new Promise(resolve => setTimeout(resolve, 100 * attempt)); // Backoff exponencial
        }
      } else {
        throw error; // Error de lógica, no reintentar
      }
    }
  }
  throw lastError;
};

module.exports = { pool, testConnection, getPoolStats, executeWithRetry, getMexicoDateTime, getMexicoDate };
