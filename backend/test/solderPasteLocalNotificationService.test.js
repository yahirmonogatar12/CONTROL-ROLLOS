const test = require('node:test');
const assert = require('node:assert/strict');

const {
  buildNotification,
  getLocalNotificationFeed,
} = require('../services/solderPasteLocalNotificationService');

function fakePool({ maxId = 12, rows = [] } = {}) {
  const calls = [];
  return {
    calls,
    async query(sql, params = []) {
      calls.push({ sql, params });
      if (/COALESCE\(MAX\(id\)/i.test(sql)) return [[{ max_id: maxId }]];
      if (/SELECT e\.id/i.test(sql)) return [rows];
      throw new Error(`Consulta no simulada: ${sql}`);
    },
  };
}

test('la primera consulta inicializa el cursor sin enviar eventos históricos', async () => {
  const pool = fakePool({ maxId: 85 });
  const feed = await getLocalNotificationFeed(pool);

  assert.deepEqual(feed, {
    cursor: 85,
    events: [],
    hasMore: false,
    initialized: true,
  });
  assert.equal(pool.calls.length, 1);
});

test('devuelve solo eventos posteriores al cursor con texto listo para Android', async () => {
  const pool = fakePool({
    maxId: 12,
    rows: [{
      id: 12,
      process_id: 7,
      event_type: 'RETURNED_TO_COLD',
      created_at: '2026-08-04 10:00:00',
      codigo_material_recibido: 'PASTA-001',
      numero_parte: 'PASTA',
      line_code: 'SA',
    }],
  });

  const feed = await getLocalNotificationFeed(pool, { afterId: '11' });
  assert.equal(feed.cursor, 12);
  assert.equal(feed.events.length, 1);
  assert.equal(feed.events[0].title, 'Pasta regresada al refrigerador');
  assert.match(feed.events[0].body, /reinició su proceso/);
  assert.deepEqual(pool.calls[1].params.slice(0, 2), [11, 12]);
});

test('conserva el cursor del último evento cuando hay otra página', async () => {
  const pool = fakePool({
    maxId: 99,
    rows: [{
      id: 25,
      process_id: 3,
      event_type: 'CONSUMED',
      created_at: '2026-08-04 11:00:00',
      codigo_material_recibido: 'PASTA-025',
      numero_parte: 'PASTA',
      line_code: null,
    }],
  });

  const feed = await getLocalNotificationFeed(pool, { afterId: 20, limit: 1 });
  assert.equal(feed.hasMore, true);
  assert.equal(feed.cursor, 25);
});

test('construye el texto de asignación con el nombre de la línea', () => {
  const notification = buildNotification({
    id: 4,
    process_id: 2,
    event_type: 'ASSIGNED_TO_LINE',
    codigo_material_recibido: 'PASTA-004',
    line_code: 'SB',
  });
  assert.match(notification.body, /SMT B/);
});
