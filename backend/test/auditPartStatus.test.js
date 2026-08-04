'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { resolveAuditPartStatus } = require('../controllers/audit.controller');

test('todo escaneado cierra la parte como verificada', () => {
  assert.equal(
    resolveAuditPartStatus({ pending_items: 0, processed_out_items: 0 }),
    'VerifiedByScan',
  );
});

test('faltantes ya procesados no dejan la parte en Mismatch', () => {
  // El bug: ProcessedOut contaba como pendiente y la ubicacion nunca se cerraba.
  assert.equal(
    resolveAuditPartStatus({ pending_items: 0, processed_out_items: 2 }),
    'MissingConfirmed',
  );
});

test('etiquetas sin resolver mantienen la parte en Mismatch', () => {
  assert.equal(
    resolveAuditPartStatus({ pending_items: 1, processed_out_items: 3 }),
    'Mismatch',
  );
});
