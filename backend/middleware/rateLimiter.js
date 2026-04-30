/**
 * Rate Limiter simple para proteger el servidor de sobrecarga
 * Especialmente útil cuando hay múltiples dispositivos móviles escaneando
 */

// Almacenar requests por IP/dispositivo
const requestCounts = new Map();
const WINDOW_MS = 1000; // Ventana de 1 segundo
const MAX_REQUESTS_PER_WINDOW = 50; // Máximo 50 requests por segundo por IP

// Limpiar contadores viejos cada minuto
setInterval(() => {
  const now = Date.now();
  for (const [key, data] of requestCounts.entries()) {
    if (now - data.windowStart > 60000) {
      requestCounts.delete(key);
    }
  }
}, 60000);

/**
 * Middleware de rate limiting por IP
 * Permite ráfagas pero protege contra abuso
 */
const rateLimiter = (req, res, next) => {
  const clientId = req.ip || req.connection.remoteAddress || 'unknown';
  const now = Date.now();
  
  let clientData = requestCounts.get(clientId);
  
  if (!clientData || now - clientData.windowStart > WINDOW_MS) {
    // Nueva ventana
    clientData = {
      windowStart: now,
      count: 1
    };
    requestCounts.set(clientId, clientData);
    return next();
  }
  
  clientData.count++;
  
  if (clientData.count > MAX_REQUESTS_PER_WINDOW) {
    console.warn(`⚠️ Rate limit exceeded for ${clientId}: ${clientData.count} requests/second`);
    return res.status(429).json({
      error: 'Demasiadas solicitudes. Por favor espere un momento.',
      code: 'RATE_LIMIT_EXCEEDED',
      retryAfter: Math.ceil((WINDOW_MS - (now - clientData.windowStart)) / 1000)
    });
  }
  
  next();
};

/**
 * Rate limiter específico para operaciones de escritura (más estricto)
 */
const writeRateLimiter = (req, res, next) => {
  const clientId = req.ip || req.connection.remoteAddress || 'unknown';
  const key = `write_${clientId}`;
  const now = Date.now();
  
  let clientData = requestCounts.get(key);
  
  // Máximo 10 escrituras por segundo
  if (!clientData || now - clientData.windowStart > WINDOW_MS) {
    clientData = {
      windowStart: now,
      count: 1
    };
    requestCounts.set(key, clientData);
    return next();
  }
  
  clientData.count++;
  
  if (clientData.count > 10) {
    console.warn(`⚠️ Write rate limit exceeded for ${clientId}`);
    return res.status(429).json({
      error: 'Demasiadas operaciones de escritura. Por favor espere.',
      code: 'WRITE_RATE_LIMIT_EXCEEDED',
      retryAfter: 1
    });
  }
  
  next();
};

/**
 * Obtener estadísticas de rate limiting
 */
const getRateLimitStats = () => {
  const stats = {
    activeClients: requestCounts.size,
    clients: []
  };
  
  for (const [key, data] of requestCounts.entries()) {
    if (!key.startsWith('write_')) {
      stats.clients.push({
        id: key.substring(0, 20) + '...',
        requests: data.count,
        windowAge: Date.now() - data.windowStart
      });
    }
  }
  
  return stats;
};

module.exports = { rateLimiter, writeRateLimiter, getRateLimitStats };
