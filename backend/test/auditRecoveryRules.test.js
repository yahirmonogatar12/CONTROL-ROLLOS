'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const {
  auditMaterialNeedsRecovery,
  canScanAuditPart,
} = require('../controllers/audit.controller');

test('un lote con salida o desecho de auditoría requiere recuperación', () => {
  assert.equal(auditMaterialNeedsRecovery(null), true);
  assert.equal(auditMaterialNeedsRecovery({ tiene_salida: 1 }), true);
  assert.equal(auditMaterialNeedsRecovery({ total_salida: 10000 }), true);
  assert.equal(auditMaterialNeedsRecovery({ estado_desecho: 1 }), true);
});

test('un lote disponible no activa una recuperación', () => {
  assert.equal(auditMaterialNeedsRecovery({
    tiene_salida: 0,
    total_salida: 0,
    estado_desecho: 0,
  }), false);
});

test('un retorno puede reabrir una parte aunque ya no esté en Mismatch', () => {
  assert.equal(canScanAuditPart('MissingConfirmed', true), true);
  assert.equal(canScanAuditPart(undefined, true), true);
  assert.equal(canScanAuditPart('Mismatch', false), true);
});

test('un escaneo normal conserva la validación de Mismatch', () => {
  assert.equal(canScanAuditPart('MissingConfirmed', false), false);
  assert.equal(canScanAuditPart('VerifiedByScan', false), false);
});
