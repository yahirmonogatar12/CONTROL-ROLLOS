'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const {
  normalizeWarehouseLocation,
  warehouseLocationKey,
  splitConfiguredWarehouseLocations,
  configuredWarehouseLocationsInclude,
} = require('../utils/warehouseLocations');

test('normaliza la ubicación escaneada sin distinguir mayúsculas', () => {
  assert.equal(normalizeWarehouseLocation('  f41  '), 'F41');
  assert.equal(warehouseLocationKey(' R 1-01 '), 'R1-01');
});

test('separa las ubicaciones configuradas en Control de Materiales', () => {
  assert.deepEqual(
    splitConfiguredWarehouseLocations('F41, F42 , r 1-01'),
    ['F41', 'F42', 'R1-01'],
  );
});

test('la coincidencia es por ubicación completa y no por texto parcial', () => {
  assert.equal(
    configuredWarehouseLocationsInclude('F41, F42', 'f41'),
    true,
  );
  assert.equal(
    configuredWarehouseLocationsInclude('F41, F42', 'F4'),
    false,
  );
});
