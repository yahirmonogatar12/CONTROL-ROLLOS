'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { relocateAuditMaterial } = require('../controllers/audit.controller');

function fakeDb() {
  const queries = [];
  return {
    queries,
    async query(sql, params) {
      queries.push({ sql, params });
      return [[], []];
    },
  };
}

const base = {
  warehousingId: 55,
  warehousingCode: '0RH1500C422-202601260013',
  numeroParte: '0RH1500C422',
  fromLocation: 'C29',
  toLocation: 'C30',
  usuario: 'operador',
};

test('reubica el material a la ubicación escaneada', async () => {
  const db = fakeDb();
  assert.equal(await relocateAuditMaterial(db, 7, base), true);

  const sqls = db.queries.map((q) => q.sql);
  // Reingreso en almacén: el material vuelve a inventario en la nueva ubicación.
  assert.ok(sqls.some((s) => /UPDATE control_material_almacen_smd/.test(s)
    && /tiene_salida = 0/.test(s)
    && /fecha_reingreso = NOW\(\)/.test(s)));
  // El snapshot de auditoría se mueve a la ubicación escaneada.
  assert.ok(sqls.some((s) => /UPDATE inventory_audit_item_smd/.test(s)
    && /SET location = \?/.test(s)));
  // Contadores de origen y destino recalculados.
  assert.ok(sqls.some((s) => /UPDATE inventory_audit_part_smd/.test(s)));
  assert.ok(sqls.some((s) => /UPDATE inventory_audit_location_smd/.test(s)));

  const move = db.queries.find((q) => /UPDATE inventory_audit_item_smd/.test(q.sql));
  assert.equal(move.params[0], 'C30');
});

test('no toca nada si la ubicación escaneada es la registrada', async () => {
  const db = fakeDb();
  assert.equal(
    await relocateAuditMaterial(db, 7, { ...base, fromLocation: 'C30' }),
    false,
  );
  assert.equal(db.queries.length, 0);
});

test('no reubica sin ubicación de origen conocida', async () => {
  const db = fakeDb();
  assert.equal(
    await relocateAuditMaterial(db, 7, { ...base, fromLocation: '' }),
    false,
  );
  assert.equal(db.queries.length, 0);
});
