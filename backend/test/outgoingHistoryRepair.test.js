const test = require('node:test');
const assert = require('node:assert/strict');

const {
  assertExpectedScope,
  summarizeCandidates
} = require('../services/outgoingHistoryRepairService');

test('summarizeCandidates cuenta registros y suma el stock actual', () => {
  assert.deepEqual(
    summarizeCandidates([
      { stock_actual: '2500.00' },
      { stock_actual: 4000 }
    ]),
    { count: 2, totalQuantity: 6500 }
  );
});

test('assertExpectedScope acepta el alcance confirmado', () => {
  assert.doesNotThrow(() => assertExpectedScope(
    { count: 2, totalQuantity: 6500 },
    { expectedCount: 2, expectedTotal: 6500 }
  ));
});

test('assertExpectedScope rechaza cambios de cantidad o total', () => {
  assert.throws(
    () => assertExpectedScope(
      { count: 3, totalQuantity: 6500 },
      { expectedCount: 2, expectedTotal: 6500 }
    ),
    /Alcance inesperado/
  );
  assert.throws(
    () => assertExpectedScope(
      { count: 2, totalQuantity: 6400 },
      { expectedCount: 2, expectedTotal: 6500 }
    ),
    /Alcance inesperado/
  );
});
