'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const toolingController = require('../controllers/tooling.controller');
const toolingCatalog = require('../data/toolingCatalog');

const { isLimitReached, LIFECYCLE_STATUSES, normalizePcbNo } =
  toolingController._test;

test('el limite 0 o nulo significa "sin limite"', () => {
  assert.equal(isLimitReached({ use_count: 999999, use_limit: null }), false);
  assert.equal(isLimitReached({ use_count: 999999, use_limit: 0 }), false);
  assert.equal(isLimitReached({ use_count: 999999 }), false);
});

test('el herramental se bloquea al alcanzar o pasar el limite', () => {
  assert.equal(isLimitReached({ use_count: 119, use_limit: 120 }), false);
  assert.equal(isLimitReached({ use_count: 120, use_limit: 120 }), true);
  assert.equal(isLimitReached({ use_count: 480, use_limit: 120 }), true);
});

test('"USADA" y "RECIENTES" ya no son estados validos', () => {
  // Describian desgaste, no disponibilidad: el edge bloquea todo lo que no
  // sea ACTIVE, asi que dejaban 72 de 77 mascarillas inservibles al escanear.
  assert.equal(LIFECYCLE_STATUSES.includes('USADA'), false);
  assert.equal(LIFECYCLE_STATUSES.includes('RECIENTES'), false);
  assert.equal(LIFECYCLE_STATUSES.includes('ACTIVE'), true);
  assert.equal(LIFECYCLE_STATUSES.includes('SCRAP'), true);
});

test('el catalogo del Excel solo siembra ACTIVE y SCRAP', () => {
  const rows = toolingCatalog.rows();
  const statuses = new Set(rows.map((row) => row.lifecycleStatus));

  assert.deepEqual([...statuses].sort(), ['ACTIVE', 'SCRAP']);
  assert.equal(rows.filter((row) => row.lifecycleStatus === 'SCRAP').length, 5);
  assert.equal(
    rows.filter((row) => row.lifecycleStatus === 'ACTIVE').length,
    rows.length - 5
  );
});

test('normalizePcbNo guarda la parte base, sin la version', () => {
  // El Excel mezcla separadores: guion en unas filas y espacio en otras.
  assert.equal(normalizePcbNo('EAX67860915-1.0'), 'EAX67860915');
  assert.equal(normalizePcbNo('EAX67860917 1.0'), 'EAX67860917');
  assert.equal(normalizePcbNo('EAX66726314-1.1'), 'EAX66726314');
  assert.equal(normalizePcbNo('  eax65868914-1.0  '), 'EAX65868914');
});

test('normalizePcbNo recorta los formatos sucios del Excel', () => {
  // Version por letra, "VER D" y version+lado pegados: todos los trae el Excel
  // real y todos tienen que colapsar a la misma base para casar con el BOM.
  assert.equal(normalizePcbNo('EAX01882201-D'), 'EAX01882201');
  assert.equal(normalizePcbNo('EAX69471803-C'), 'EAX69471803');
  assert.equal(normalizePcbNo('EAX70205601-B'), 'EAX70205601');
  assert.equal(normalizePcbNo('EAX69871901 VER D'), 'EAX69871901');
  assert.equal(normalizePcbNo('EAX67445308-1.0 TOP'), 'EAX67445308');
  assert.equal(normalizePcbNo('EAX67445308-1.0 BOT'), 'EAX67445308');
});

test('el BOM se normaliza igual que la mask, para poder compararlos', () => {
  // En el BOM el mismo PCB viene con version: si no se recorta, nunca casan.
  assert.equal(normalizePcbNo('EAX65150407-1.0'), normalizePcbNo('EAX65150407'));
  assert.equal(normalizePcbNo('EAX66946010-1.2'), normalizePcbNo('EAX66946010-1.3'));
  assert.equal(normalizePcbNo('EAX01882201-D'), normalizePcbNo('EAX01882201'));
});

test('normalizePcbNo no mutila codigos sin version', () => {
  assert.equal(normalizePcbNo('EAX65150407'), 'EAX65150407');
  assert.equal(normalizePcbNo('EAX66946010'), 'EAX66946010');
});

test('normalizePcbNo trata el vacio como sin dato', () => {
  for (const value of ['', '   ', null, undefined]) {
    assert.equal(normalizePcbNo(value), null);
  }
});
