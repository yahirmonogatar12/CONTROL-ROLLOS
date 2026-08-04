/**
 * Verifica que getScans arme un BETWEEN correcto con y sin inventory_date_end.
 * node backend/test/pcbScansRange.test.js
 */
const assert = require('assert');

const dbPath = require.resolve('../config/database');
const captured = [];
require.cache[dbPath] = {
  id: dbPath,
  filename: dbPath,
  loaded: true,
  exports: { pool: { query: async (q, p) => { captured.push({ q, p }); return [[]]; } } },
};

const { getScans } = require('../controllers/pcb-inventory.controller');

const res = { json: () => {}, status: () => ({ json: () => {} }) };

(async () => {
  await getScans({ query: { inventory_date: '2026-08-01' } }, res, (e) => { throw e; });
  assert.ok(captured[0].q.includes('inventory_date BETWEEN ? AND ?'));
  assert.deepStrictEqual(captured[0].p.slice(0, 3), ['2026-08-01', '2026-08-01', 'ENTRADA']);

  await getScans(
    { query: { inventory_date: '2026-07-01', inventory_date_end: '2026-08-01', tipo_movimiento: 'SCRAP' } },
    res,
    (e) => { throw e; },
  );
  assert.deepStrictEqual(captured[1].p.slice(0, 3), ['2026-07-01', '2026-08-01', 'SCRAP']);

  console.log('OK');
})();
