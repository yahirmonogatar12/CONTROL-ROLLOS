const test = require('node:test');
const assert = require('node:assert/strict');

const {
  rateLimiter,
  getRateLimitStats
} = require('../middleware/rateLimiter');

const createResponse = () => ({
  headers: {},
  statusCode: null,
  body: null,
  set(name, value) {
    this.headers[name] = value;
    return this;
  },
  status(code) {
    this.statusCode = code;
    return this;
  },
  json(body) {
    this.body = body;
    return this;
  }
});

test('reporta las rutas que originan una ráfaga sin registrar parámetros', () => {
  const ip = '192.0.2.51';
  const warnings = [];
  const originalWarn = console.warn;
  console.warn = (message) => warnings.push(message);

  try {
    for (let index = 0; index < 50; index++) {
      const response = createResponse();
      let passed = false;
      rateLimiter({
        ip,
        method: 'GET',
        originalUrl: `/api/inventory/lots?codigo=SECRETO-${index}`
      }, response, () => {
        passed = true;
      });
      assert.equal(passed, true);
      assert.equal(response.statusCode, null);
    }

    const blockedResponse = createResponse();
    rateLimiter({
      ip,
      method: 'GET',
      originalUrl: '/api/inventory/lots?codigo=SECRETO-50'
    }, blockedResponse, () => assert.fail('La solicitud 51 debe bloquearse'));

    assert.equal(blockedResponse.statusCode, 429);
    assert.equal(blockedResponse.headers['Retry-After'], '1');
    assert.equal(blockedResponse.body.code, 'RATE_LIMIT_EXCEEDED');
    assert.equal(warnings.length, 1);
    assert.match(warnings[0], /GET \/api\/inventory\/lots: 51/);
    assert.doesNotMatch(warnings[0], /SECRETO/);

    const clientStats = getRateLimitStats().clients.find((client) => (
      client.id.startsWith(ip)
    ));
    assert.deepEqual(clientStats.topRoutes, ['GET /api/inventory/lots: 51']);
  } finally {
    console.warn = originalWarn;
  }
});

test('evita inundar el log con una línea por cada solicitud bloqueada', () => {
  const ip = '192.0.2.52';
  const warnings = [];
  const originalWarn = console.warn;
  console.warn = (message) => warnings.push(message);

  try {
    for (let index = 0; index < 74; index++) {
      rateLimiter({
        ip,
        method: 'GET',
        originalUrl: '/api/health'
      }, createResponse(), () => {});
    }

    assert.equal(warnings.length, 1);

    rateLimiter({
      ip,
      method: 'GET',
      originalUrl: '/api/health'
    }, createResponse(), () => {});

    assert.equal(warnings.length, 2);
    assert.match(warnings[1], /75 requests\/second/);
  } finally {
    console.warn = originalWarn;
  }
});
