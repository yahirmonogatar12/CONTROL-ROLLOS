'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const {
  applyReturnedWarehouseQuantity,
} = require('../controllers/return.controller');

test('un retorno parcial neutraliza la salida antes de reducir la cantidad física', async () => {
  const state = {
    totalEntrada: 4000,
    totalSalida: 3900,
    warehouseQty: 4000,
    tieneSalida: 1,
  };
  const operations = [];
  const connection = {
    async query(sql, params) {
      const normalized = sql.replace(/\s+/g, ' ').trim();
      operations.push(normalized);

      if (normalized.includes('SET total_salida = 0')) {
        state.totalSalida = 0;
      } else if (normalized.includes('UPDATE control_material_almacen_smd')) {
        const previousQty = state.warehouseQty;
        state.warehouseQty = params[0];
        state.tieneSalida = 0;

        // Comportamiento relevante de trg_almacen_au_smd.
        state.totalEntrada += state.warehouseQty - previousQty;
        if (state.totalSalida > state.totalEntrada) {
          throw new Error('NEGATIVE_STOCK_NOT_ALLOWED_SMD');
        }
      } else if (normalized.includes('SET total_entrada = ?, total_salida = ?')) {
        state.totalEntrada = params[0];
        state.totalSalida = params[1];
      }

      return [{ affectedRows: 1 }];
    },
  };

  await applyReturnedWarehouseQuantity(connection, {
    inventoryLotId: 57251,
    originalTotalEntrada: 4000,
    expectedTotalSalida: 3900,
    warehousingId: 31644,
    newQty: 100,
  });

  assert.match(operations[0], /SET total_salida = 0/);
  assert.match(operations[1], /UPDATE control_material_almacen_smd/);
  assert.match(operations[2], /SET total_entrada = \?, total_salida = \?/);
  assert.deepEqual(state, {
    totalEntrada: 4000,
    totalSalida: 3900,
    warehouseQty: 100,
    tieneSalida: 0,
  });
  assert.equal(state.totalEntrada - state.totalSalida, 100);
});
