'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const {
  normalizeAuditLocation,
  parsePhysicalQuantity,
  getPhysicalAdjustment,
} = require('../utils/auditPhysical');

test('normaliza el QR de ubicación antes de registrarlo', () => {
  assert.equal(normalizeAuditLocation('  a3 '), 'A3');
});

test('acepta cantidad física decimal con punto o coma', () => {
  assert.equal(parsePhysicalQuantity('12.5'), 12.5);
  assert.equal(parsePhysicalQuantity('12,5'), 12.5);
  assert.equal(parsePhysicalQuantity(7), 7);
});

test('rechaza cantidades físicas vacías, cero, negativas o inválidas', () => {
  for (const value of ['', 0, -1, 'abc', null, undefined]) {
    assert.equal(parsePhysicalQuantity(value), null);
  }
});

test('clasifica el ajuste de inventario como entrada o salida', () => {
  assert.deepEqual(getPhysicalAdjustment(10, 14), {
    before: 10,
    after: 14,
    delta: 4,
    quantity: 4,
    movementType: 'Entry',
    changed: true,
  });
  assert.equal(getPhysicalAdjustment(10, 6).movementType, 'Exit');
  assert.equal(getPhysicalAdjustment(10, 10).changed, false);
});

test('nunca acepta un stock anterior negativo', () => {
  assert.equal(getPhysicalAdjustment(-1, 4), null);
});
