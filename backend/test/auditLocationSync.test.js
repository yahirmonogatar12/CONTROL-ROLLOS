'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const {
  syncAuditLocationWithInventory,
} = require('../controllers/audit.controller');

const material = {
  warehousing_id: 501,
  codigo_material_recibido: '0CH5100J106-202607080002',
  numero_parte: '0CH5100J106',
  numero_lote_material: 'IA6131CM1',
  cantidad_actual: 4000,
  especificacion: 'CAP',
  fecha_recibo: '2026-07-29 10:00:00',
  location: 'A15',
};

function fakeDb(existingItem = null, options = {}) {
  const queries = [];
  return {
    queries,
    async query(sql, params) {
      queries.push({ sql, params });

      if (/WHERE UPPER\(TRIM\(ai\.location\)\) = \?/.test(sql)) {
        return [[...(options.liveItems ?? [material])], []];
      }
      if (/SELECT id, location\s+FROM inventory_audit_item_smd/.test(sql)) {
        return [existingItem ? [existingItem] : [], []];
      }
      if (/active_inventory\.codigo_material_recibido IS NULL/.test(sql)) {
        return [[...(options.inactiveItems ?? [])], []];
      }
      return [{ affectedRows: 1 }, []];
    },
  };
}

test('incorpora a la auditoría un material registrado después del snapshot', async () => {
  const db = fakeDb();
  const result = await syncAuditLocationWithInventory(
    db,
    5,
    ' a15 ',
    '107',
  );

  assert.equal(result.insertedItems, 1);
  assert.equal(result.relocatedItems, 0);
  assert.equal(result.removedItems, 0);

  const insert = db.queries.find((query) =>
    /INSERT INTO inventory_audit_item_smd/.test(query.sql));
  assert.ok(insert);
  assert.equal(insert.params[0], 5);
  assert.equal(insert.params[1], material.warehousing_id);
  assert.equal(insert.params[3], 'A15');

  assert.ok(db.queries.some((query) =>
    /INSERT INTO inventory_audit_part_smd/.test(query.sql)));
  assert.ok(db.queries.some((query) =>
    /UPDATE inventory_audit_location_smd/.test(query.sql)));
  assert.ok(db.queries.some((query) =>
    /UPDATE inventory_audit_smd/.test(query.sql)));
});

test('no duplica un material que ya pertenece a la ubicación', async () => {
  const db = fakeDb({ id: 91, location: 'A15' });
  const result = await syncAuditLocationWithInventory(db, 5, 'A15', '107');

  assert.equal(result.insertedItems, 0);
  assert.equal(result.relocatedItems, 0);
  assert.equal(result.removedItems, 0);
  assert.equal(
    db.queries.some((query) =>
      /INSERT INTO inventory_audit_item_smd/.test(query.sql)),
    false,
  );
});

test('mueve el snapshot si inventario ya registra el material en otra ubicación', async () => {
  const db = fakeDb({ id: 91, location: 'A14' });
  const result = await syncAuditLocationWithInventory(db, 5, 'A15', '107');

  assert.equal(result.insertedItems, 0);
  assert.equal(result.relocatedItems, 1);
  assert.equal(result.removedItems, 0);
  assert.deepEqual(result.affectedLocations.sort(), ['A14', 'A15']);

  const move = db.queries.find((query) =>
    /UPDATE inventory_audit_item_smd/.test(query.sql));
  assert.ok(move);
  assert.equal(move.params[0], 'A15');
  assert.equal(move.params.at(-1), 91);
});

test('retira de la auditoría un material con salida completa', async () => {
  const db = fakeDb(null, {
    liveItems: [],
    inactiveItems: [{ id: 91 }],
  });
  const result = await syncAuditLocationWithInventory(db, 5, 'A15', '107');

  assert.equal(result.insertedItems, 0);
  assert.equal(result.relocatedItems, 0);
  assert.equal(result.removedItems, 1);

  const removal = db.queries.find((query) =>
    /DELETE FROM inventory_audit_item_smd/.test(query.sql));
  assert.ok(removal);
  assert.deepEqual(removal.params, [5, 91]);

  assert.ok(db.queries.some((query) =>
    /DELETE iap\s+FROM inventory_audit_part_smd/.test(query.sql)));
  assert.ok(db.queries.some((query) =>
    /UPDATE inventory_audit_location_smd/.test(query.sql)));
  assert.ok(db.queries.some((query) =>
    /UPDATE inventory_audit_smd/.test(query.sql)));
});
