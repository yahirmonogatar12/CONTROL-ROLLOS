'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');

const {
  getPendingInvoicesByPartNumbers,
  attachPendingInvoiceData,
} = require('../services/pendingInvoiceService');

test('devuelve cantidad e invoices pendientes por número de parte', async () => {
  const calls = [];
  const executor = {
    async query(sql, params) {
      calls.push({ sql, params });
      if (calls.length === 1) {
        return [[{ table_count: 3, has_manual_close: 1 }]];
      }
      return [[{
        numero_parte_sistema: 'EAX123',
        cantidad_pendiente_entrada: 600,
        invoices_pendientes: 'INV-10, INV-11',
      }]];
    },
  };

  const result = await getPendingInvoicesByPartNumbers(
    [' EAX123 ', 'EAX123'],
    executor,
  );

  assert.deepEqual(result.get('EAX123'), {
    cantidadPendienteEntrada: 600,
    invoicesPendientes: 'INV-10, INV-11',
  });
  assert.deepEqual(calls[1].params, ['EAX123']);
  assert.match(calls[1].sql, /cerrado_manual/);
});

test('no rompe el catálogo cuando el módulo de invoices no está instalado', async () => {
  let queryCount = 0;
  const executor = {
    async query() {
      queryCount += 1;
      return [[{ table_count: 0, has_manual_close: 0 }]];
    },
  };

  const rows = await attachPendingInvoiceData([
    { numero_parte: 'EAX404', cantidad_disponible: 0 },
  ], executor);

  assert.equal(queryCount, 1);
  assert.deepEqual(rows[0], {
    numero_parte: 'EAX404',
    cantidad_disponible: 0,
    cantidad_pendiente_entrada: 0,
    invoices_pendientes: '',
    pendiente_entrada_en: '',
  });
});

test('adjunta el aviso de invoice a cada material sin alterar su inventario', async () => {
  const executor = {
    async query(sql) {
      if (sql.includes('information_schema.tables')) {
        return [[{ table_count: 3, has_manual_close: 0 }]];
      }
      return [[{
        numero_parte_sistema: 'EAX500',
        cantidad_pendiente_entrada: 250,
        invoices_pendientes: 'INV-50',
      }]];
    },
  };

  const rows = await attachPendingInvoiceData([
    { numero_parte: 'EAX500', cantidad_disponible: 0 },
    { numero_parte: 'EAX501', cantidad_disponible: 12 },
  ], executor);

  assert.equal(rows[0].cantidad_disponible, 0);
  assert.equal(rows[0].cantidad_pendiente_entrada, 250);
  assert.equal(rows[0].pendiente_entrada_en, 'INV-50');
  assert.equal(rows[1].cantidad_disponible, 12);
  assert.equal(rows[1].cantidad_pendiente_entrada, 0);
});
