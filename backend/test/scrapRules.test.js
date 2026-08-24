'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const scrapController = require('../controllers/scrap.controller');

const { resolveScrapRegistrationDate, isComponentCapture } =
  scrapController._test;

test('acepta una fecha real anterior y conserva esa fecha en el registro', () => {
  const result = resolveScrapRegistrationDate('2024-02-29');

  assert.equal(result.date, '2024-02-29');
  assert.match(result.dateTime, /^2024-02-29 \d{2}:\d{2}:\d{2}$/);
});

test('rechaza fechas inexistentes o futuras', () => {
  assert.equal(resolveScrapRegistrationDate('2025-02-29'), null);
  assert.equal(resolveScrapRegistrationDate('2999-01-01'), null);
  assert.equal(resolveScrapRegistrationDate('10/08/2026'), null);
});

test('clientes anteriores sin fecha continúan registrando con la fecha actual', () => {
  const result = resolveScrapRegistrationDate(null);

  assert.match(result.date, /^\d{4}-\d{2}-\d{2}$/);
  assert.match(result.dateTime, /^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$/);
});

test('identifica componentes por área o por proceso', () => {
  assert.equal(isComponentCapture('COMPONENTE', 'SMT'), true);
  assert.equal(isComponentCapture('IPM', 'SMT'), true);
  assert.equal(isComponentCapture('M1', 'COMPONENTE'), true);
  assert.equal(isComponentCapture('M1', 'SMT'), false);
});
