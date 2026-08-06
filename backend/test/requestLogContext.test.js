'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const {
  buildRequestLogContext,
  cleanLogValue,
  formatRequestLogContext,
} = require('../utils/requestLogContext');

test('registra el código escaneado y contexto operativo sin imprimir todo el cuerpo', () => {
  const context = buildRequestLogContext({
    method: 'POST',
    originalUrl: '/api/solder-paste/scan?debug=true',
    ip: '::ffff:192.168.2.187',
    headers: { 'x-app-version': '2.2.0' },
    body: {
      code: '  EAE63688401-202607030014  ',
      usuario: '107',
      password: 'no-debe-aparecer',
    },
  });

  assert.deepEqual(context, {
    method: 'POST',
    path: '/api/solder-paste/scan',
    ip: '192.168.2.187',
    scannedCode: 'EAE63688401-202607030014',
    partNumber: null,
    location: null,
    user: '107',
    clientVersion: '2.2.0',
  });

  const formatted = formatRequestLogContext(context);
  assert.match(formatted, /código=EAE63688401-202607030014/);
  assert.match(formatted, /versión=2\.2\.0/);
  assert.doesNotMatch(formatted, /password|no-debe-aparecer/);
});

test('reconoce los nombres usados por auditoría y retorno', () => {
  const context = buildRequestLogContext({
    method: 'POST',
    path: '/api/audit/scan-part-item',
    headers: { 'x-forwarded-for': '10.0.0.8, 10.0.0.1' },
    body: {
      warehousing_code: 'ABC-001',
      numero_parte: 'ABC',
      location: 'B5',
      scanned_by: 'Operador',
    },
  });

  assert.equal(context.scannedCode, 'ABC-001');
  assert.equal(context.partNumber, 'ABC');
  assert.equal(context.location, 'B5');
  assert.equal(context.user, 'Operador');
  assert.equal(context.ip, '10.0.0.8');
  assert.equal(context.clientVersion, null);
  assert.match(formatRequestLogContext(context), /versión=sin-reportar/);
});

test('neutraliza saltos de línea para impedir logs falsificados', () => {
  assert.equal(cleanLogValue('ABC\n❌ Error falso'), 'ABC ❌ Error falso');
});
