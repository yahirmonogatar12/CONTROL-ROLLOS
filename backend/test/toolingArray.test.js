'use strict';

const assert = require('assert');
const { impresionesDePlan, repartirEntreSqueegees, normalizeArraySize } =
  require('../controllers/tooling.controller')._test;
const { PCB_ARRAY } = require('../data/toolingCatalog');

// El plan viene en piezas; la mask se desgasta por impresion.
assert.strictEqual(impresionesDePlan(100, 4), 25);
assert.strictEqual(impresionesDePlan(100, 2), 50);
assert.strictEqual(impresionesDePlan(100, 1), 100);
assert.strictEqual(impresionesDePlan(100, null), 100, 'sin array configurado cuenta piezas');
// Una impresion parcial igual imprimio: 101 piezas en array 4 son 26 pasadas.
assert.strictEqual(impresionesDePlan(101, 4), 26);
assert.strictEqual(impresionesDePlan(0, 4), 0);

// Los dos squeegees se reparten las impresiones de la mask, no las duplican.
assert.deepStrictEqual(repartirEntreSqueegees(25, 2), [13, 12]);
assert.deepStrictEqual(repartirEntreSqueegees(50, 2), [25, 25]);
assert.deepStrictEqual(repartirEntreSqueegees(25, 1), [25], 'un solo squeegee carga todo');
assert.strictEqual(repartirEntreSqueegees(25, 2).reduce((a, b) => a + b, 0), 25,
  'el reparto no puede perder ni inventar impresiones');

// TOP y BOT se escanean por separado: cada mask carga sus impresiones completas,
// que es lo que hace assignPlan al recibir un metal_mask_code por evento.
const impresiones = impresionesDePlan(100, PCB_ARRAY.EAX69577801);
assert.strictEqual(impresiones, 25);
assert.deepStrictEqual([impresiones, impresiones], [25, 25], 'TOP y BOT cargan 25 cada una');

assert.strictEqual(normalizeArraySize('4'), 4);
assert.strictEqual(normalizeArraySize(0), null, 'array 0 es invalido');
assert.strictEqual(normalizeArraySize(-2), null);
assert.strictEqual(normalizeArraySize('abc'), null);

console.log('OK toolingArray: array, impresiones y reparto de squeegees');

// El edge resuelve el reparto al escanear y el central lo aplica tal cual: si
// aqui se recalculara, un cambio de array entre el escaneo y la subida dejaria
// numeros distintos a los dos lados.
// ESCANEO_INPUT vive en otro repo: si no esta al lado, se salta la paridad en
// vez de romper el test de este proyecto.
let edgeStore = null;
try {
  edgeStore = require('../../../ESCANEO_INPUT/backend/src/edge/sqlite-store');
} catch (_) { /* ponytail: sin el edge presente no hay nada que comparar */ }

if (edgeStore) {
  assert.strictEqual(edgeStore.impresionesDePlan(100, 4), impresionesDePlan(100, 4),
    'edge y control deben calcular las mismas impresiones');
  assert.deepStrictEqual(edgeStore.repartirEntreSqueegees(25, 2), repartirEntreSqueegees(25, 2),
    'edge y control deben repartir igual entre squeegees');
  assert.deepStrictEqual(edgeStore.repartirEntreSqueegees(31, 2), [16, 15]);
  console.log('OK toolingArray: el edge y el control coinciden en el calculo');
} else {
  console.log('-- paridad con el edge omitida: ESCANEO_INPUT no esta presente');
}
