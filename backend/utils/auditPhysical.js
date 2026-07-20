'use strict';

function normalizeAuditLocation(value) {
  return String(value || '').trim().toUpperCase();
}

function parsePhysicalQuantity(value) {
  const normalized = typeof value === 'string'
    ? value.trim().replace(',', '.')
    : value;
  const quantity = Number(normalized);
  return Number.isFinite(quantity) && quantity > 0 ? quantity : null;
}

function getPhysicalAdjustment(currentStock, physicalQuantity) {
  const before = Number(currentStock || 0);
  const after = parsePhysicalQuantity(physicalQuantity);
  if (!Number.isFinite(before) || before < 0 || after === null) {
    return null;
  }

  const delta = after - before;
  return {
    before,
    after,
    delta,
    quantity: Math.abs(delta),
    movementType: delta > 0 ? 'Entry' : delta < 0 ? 'Exit' : 'None',
    changed: Math.abs(delta) >= 0.0001,
  };
}

module.exports = {
  normalizeAuditLocation,
  parsePhysicalQuantity,
  getPhysicalAdjustment,
};
