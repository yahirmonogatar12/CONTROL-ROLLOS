/**
 * Rate Limiter simple para proteger el servidor de sobrecarga
 * Especialmente útil cuando hay múltiples dispositivos móviles escaneando
 */

// Almacenar requests por IP/dispositivo
const requestCounts = new Map();
const WINDOW_MS = 1000; // Ventana de 1 segundo
const MAX_REQUESTS_PER_WINDOW = 50; // Máximo 50 requests por segundo por IP
const MAX_ROUTES_IN_LOG = 5;

const getRequestRoute = (req) => {
  const method = String(req.method || 'UNKNOWN').toUpperCase();
  const path = String(req.originalUrl || req.url || '/')
    .split('?')[0];
  return `${method} ${path}`;
};

const registerRoute = (clientData, req) => {
  const route = getRequestRoute(req);
  const currentCount = clientData.routes.get(route) || 0;
  clientData.routes.set(route, currentCount + 1);
};

const getTopRoutes = (clientData) => Array.from(clientData.routes.entries())
  .sort((left, right) => right[1] - left[1])
  .slice(0, MAX_ROUTES_IN_LOG)
  .map(([route, count]) => `${route}: ${count}`);

const shouldLogGeneralLimit = (count) => (
  count === MAX_REQUESTS_PER_WINDOW + 1 || count % 25 === 0
);

const shouldLogWriteLimit = (count) => count === 11 || count % 10 === 0;

// Limpiar contadores viejos cada minuto
const cleanupTimer = setInterval(() => {
  const now = Date.now();
  for (const [key, data] of requestCounts.entries()) {
    if (now - data.windowStart > 60000) {
      requestCounts.delete(key);
    }
  }
}, 60000);
cleanupTimer.unref?.();

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
      count: 1,
      routes: new Map()
    };
    registerRoute(clientData, req);
    requestCounts.set(clientId, clientData);
    return next();
  }
  
  clientData.count++;
  registerRoute(clientData, req);
  
  if (clientData.count > MAX_REQUESTS_PER_WINDOW) {
    if (shouldLogGeneralLimit(clientData.count)) {
      const topRoutes = getTopRoutes(clientData).join(' | ');
      console.warn(
        `⚠️ Rate limit exceeded for ${clientId}: ${clientData.count} requests/second | ${topRoutes}`
      );
    }
    const retryAfter = Math.max(
      1,
      Math.ceil((WINDOW_MS - (now - clientData.windowStart)) / 1000)
    );
    res.set('Retry-After', String(retryAfter));
    return res.status(429).json({
      error: 'Demasiadas solicitudes. Por favor espere un momento.',
      code: 'RATE_LIMIT_EXCEEDED',
      retryAfter
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
      count: 1,
      routes: new Map()
    };
    registerRoute(clientData, req);
    requestCounts.set(key, clientData);
    return next();
  }
  
  clientData.count++;
  registerRoute(clientData, req);
  
  if (clientData.count > 10) {
    if (shouldLogWriteLimit(clientData.count)) {
      const topRoutes = getTopRoutes(clientData).join(' | ');
      console.warn(
        `⚠️ Write rate limit exceeded for ${clientId}: ${clientData.count} requests/second | ${topRoutes}`
      );
    }
    res.set('Retry-After', '1');
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
        windowAge: Date.now() - data.windowStart,
        topRoutes: getTopRoutes(data)
      });
    }
  }
  
  return stats;
};

module.exports = { rateLimiter, writeRateLimiter, getRateLimitStats };
