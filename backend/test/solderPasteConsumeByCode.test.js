'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const service = require('../services/solderPasteLifecycleService');

const { STATUS, consumeByCode, resolvePasteLine } = service;

test('consumeByCode esta expuesto y el ciclo tiene los estados que usa', () => {
  assert.equal(typeof consumeByCode, 'function');
  assert.equal(STATUS.IN_LINE, 'IN_LINE');
  assert.equal(STATUS.CONSUMED, 'CONSUMED');
});

test('rechaza un codigo vacio antes de tocar la base', async () => {
  // Si llegara a consultar MySQL, el error seria de conexion y no MISSING_CODE.
  for (const code of [undefined, null, '', '   ']) {
    await assert.rejects(
      () => consumeByCode({ code, usuario: 'test' }),
      (error) => {
        assert.equal(error.code, 'MISSING_CODE');
        assert.equal(error.statusCode, 400);
        return true;
      },
    );
  }
});

test('normalizeCode deja el codigo escaneado listo para buscar', () => {
  // El lector puede mandar espacios o minusculas; la busqueda es por igualdad.
  assert.equal(service.normalizeCode('  49111007000-202608050067 '), '49111007000-202608050067');
  assert.equal(service.normalizeCode('abc-001'), 'ABC-001');
});

test('resolvePasteLine traduce la linea del escaneo a la de control de pasta', () => {
  // El piso escanea SA..SE; control de pasta guarda 'SMT A'..'SMT E'.
  assert.equal(resolvePasteLine('SA'), 'SMT A');
  assert.equal(resolvePasteLine('se'), 'SMT E');
  assert.equal(resolvePasteLine('SMT C'), 'SMT C');
  assert.equal(resolvePasteLine('SMT-B'), 'SMT B');
  assert.equal(resolvePasteLine('  sd  '), 'SMT D');
});

test('resolvePasteLine no adivina lineas que no existen', () => {
  // Antes que asignar el bote a la linea equivocada, se rechaza el escaneo.
  for (const value of ['M2', 'SF', 'SMT F', '', null, undefined, 'S', 'SAA']) {
    assert.equal(resolvePasteLine(value), null, `no debe resolver ${value}`);
  }
});
