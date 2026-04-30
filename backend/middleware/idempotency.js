const crypto = require('crypto');

const TTL_MS = 15 * 60 * 1000;
const cache = new Map();

function cleanupExpiredEntries() {
  const now = Date.now();
  for (const [key, entry] of cache.entries()) {
    if (now - entry.createdAt > TTL_MS) {
      cache.delete(key);
    }
  }
}

setInterval(cleanupExpiredEntries, 60 * 1000);

function hashBody(rawBody) {
  return crypto
    .createHash('sha256')
    .update(rawBody || '')
    .digest('hex');
}

function buildRequestHash(req) {
  if (typeof req.rawBody === 'string') {
    return hashBody(req.rawBody);
  }

  if (req.body === undefined) {
    return hashBody('');
  }

  return hashBody(JSON.stringify(req.body));
}

function buildCacheKey(req, idempotencyKey) {
  const requestPath = String(req.originalUrl || req.url || '').split('?')[0];
  return `${req.method}:${requestPath}:${idempotencyKey}`;
}

function sanitizeHeaders(headers) {
  const normalized = {};
  for (const [name, value] of Object.entries(headers)) {
    if (value === undefined || value === null) {
      continue;
    }

    const lowerName = name.toLowerCase();
    if (!['content-type', 'content-encoding', 'location'].includes(lowerName)) {
      continue;
    }

    normalized[lowerName] = Array.isArray(value) ? value.join(', ') : String(value);
  }
  return normalized;
}

function replayCachedResponse(res, entry) {
  if (!entry || entry.state !== 'completed') {
    return res.status(409).json({
      error: 'La solicitud idempotente previa no está disponible',
      code: 'IDEMPOTENCY_REPLAY_MISSING',
    });
  }

  for (const [name, value] of Object.entries(entry.headers || {})) {
    res.setHeader(name, value);
  }

  res.status(entry.statusCode || 200);

  if (!entry.bodyBuffer || entry.bodyBuffer.length === 0) {
    return res.end();
  }

  return res.send(entry.bodyBuffer);
}

function idempotencyMiddleware(req, res, next) {
  if (!['POST', 'PUT', 'DELETE'].includes(req.method)) {
    return next();
  }

  const idempotencyKey = req.headers['idempotency-key'];
  if (!idempotencyKey) {
    return next();
  }

  const requestHash = buildRequestHash(req);
  const cacheKey = buildCacheKey(req, idempotencyKey);
  const existingEntry = cache.get(cacheKey);

  if (existingEntry) {
    if (existingEntry.requestHash !== requestHash) {
      return res.status(409).json({
        error: 'La misma Idempotency-Key ya fue usada con otro cuerpo',
        code: 'IDEMPOTENCY_CONFLICT',
      });
    }

    if (existingEntry.state === 'completed') {
      return replayCachedResponse(res, existingEntry);
    }

    return existingEntry.completion
      .then((completedEntry) => replayCachedResponse(res, completedEntry))
      .catch(next);
  }

  let resolveCompletion;
  const completion = new Promise((resolve) => {
    resolveCompletion = resolve;
  });

  const entry = {
    state: 'pending',
    createdAt: Date.now(),
    requestHash,
    completion,
    resolveCompletion,
  };

  cache.set(cacheKey, entry);

  const originalSend = res.send.bind(res);
  const originalEnd = res.end.bind(res);

  const completeEntry = (body) => {
    if (entry.state === 'completed') {
      return;
    }

    entry.state = 'completed';
    entry.statusCode = res.statusCode;
    entry.headers = sanitizeHeaders(res.getHeaders());
    entry.bodyBuffer = body;
    entry.resolveCompletion(entry);
  };

  res.send = (body) => {
    let responseBodyBuffer = null;
    if (body !== undefined && body !== null) {
      if (Buffer.isBuffer(body)) {
        responseBodyBuffer = body;
      } else if (typeof body === 'string') {
        responseBodyBuffer = Buffer.from(body);
      } else {
        responseBodyBuffer = Buffer.from(JSON.stringify(body));
      }
    }

    completeEntry(responseBodyBuffer);
    return originalSend(body);
  };

  res.end = (chunk, encoding, callback) => {
    if (entry.state !== 'completed') {
      let responseBodyBuffer = null;
      if (chunk !== undefined && chunk !== null) {
        responseBodyBuffer = Buffer.isBuffer(chunk)
          ? chunk
          : Buffer.from(chunk, typeof encoding === 'string' ? encoding : undefined);
      }
      completeEntry(responseBodyBuffer);
    }

    return originalEnd(chunk, encoding, callback);
  };

  res.on('close', () => {
    if (entry.state === 'pending') {
      cache.delete(cacheKey);
      entry.resolveCompletion(null);
    }
  });

  next();
}

module.exports = idempotencyMiddleware;
