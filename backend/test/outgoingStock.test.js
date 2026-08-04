const test = require('node:test');
const assert = require('node:assert/strict');

const {
  resolveOutgoingQuantity
} = require('../services/outgoingStockService');

test('la salida completa usa el stock actual aunque el cliente envíe cero', () => {
  const result = resolveOutgoingQuantity({
    availableQty: 37,
    requestedQty: 0,
    useAvailableStock: true
  });

  assert.equal(result, 37);
});

test('rechaza una salida completa cuando el stock actual es cero', () => {
  assert.throws(
    () => resolveOutgoingQuantity({
      availableQty: 0,
      useAvailableStock: true
    }),
    (error) => error.code === 'NO_AVAILABLE_STOCK'
  );
});
