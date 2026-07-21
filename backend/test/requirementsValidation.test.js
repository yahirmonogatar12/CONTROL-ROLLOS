'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const {
  validateRequirementPayload,
  validateRequirementItems,
  normalizeRequirementItemQuantity,
  canAppendRequirementItems,
  canCancelRequirement,
} = require('../utils/requirementsValidation');

const validPayload = () => ({
  area_destino: 'SMD',
  fecha_requerida: '2026-07-22',
  creado_por: 'Operador',
  items: [
    {
      numero_parte: 'EBR12345678',
      cantidad_requerida: 2,
    },
  ],
});

test('acepta un requerimiento con materiales válidos', () => {
  assert.deepEqual(validateRequirementPayload(validPayload()), []);
});

test('conserva compatibilidad con encabezados sin items de PC', () => {
  const payload = validPayload();
  delete payload.items;
  assert.deepEqual(validateRequirementPayload(payload), []);
});

test('rechaza campos requeridos vacíos', () => {
  const errors = validateRequirementPayload({});
  assert.equal(errors.length, 3);
  assert.match(errors[0], /area_destino/);
});

test('rechaza materiales sin parte o con cantidades inválidas', () => {
  const payload = validPayload();
  payload.items = [
    { numero_parte: '', cantidad_requerida: 1 },
    { numero_parte: 'A', cantidad_requerida: 0 },
    { numero_parte: 'B', cantidad_requerida: 1.5 },
  ];
  const errors = validateRequirementPayload(payload);
  assert.equal(errors.length, 3);
});

test('valida materiales agregados a un requerimiento existente', () => {
  assert.deepEqual(validateRequirementItems([
    { numero_parte: 'CAP123', cantidad_requerida: 3 },
  ]), []);
  assert.equal(validateRequirementItems([
    { numero_parte: '', cantidad_requerida: 0 },
  ]).length, 2);
});

test('calcula la cantidad requerida por empaque y unidades', () => {
  const normalized = normalizeRequirementItemQuantity({
    cantidad_requerida: 1,
    cantidad_estandarizada: 250,
    cantidad_unidades: 4,
    unidad_empaque: '250',
    ubicacion_destino: 'Línea 3',
  });

  assert.deepEqual(normalized, {
    cantidadRequerida: 1000,
    cantidadEstandarizada: 250,
    cantidadUnidades: 4,
    unidadEmpaque: '250',
    ubicacionDestino: 'Línea 3',
  });
});

test('rechaza empaque sin unidades y valores fraccionarios', () => {
  const missingUnits = validateRequirementItems([{
    numero_parte: 'CAP123',
    cantidad_requerida: 250,
    cantidad_estandarizada: 250,
  }]);
  assert.match(missingUnits[0], /cantidad_unidades/);

  const fractional = validateRequirementItems([{
    numero_parte: 'CAP123',
    cantidad_requerida: 1,
    cantidad_estandarizada: 2.5,
    cantidad_unidades: 2,
  }]);
  assert.match(fractional[0], /enteras/);
});

test('sólo permite agregar materiales cuando el requerimiento está Pendiente', () => {
  assert.equal(canAppendRequirementItems('Pendiente'), true);
  assert.equal(canAppendRequirementItems('En Preparación'), false);
  assert.equal(canAppendRequirementItems('Listo'), false);
  assert.equal(canAppendRequirementItems('Cancelado'), false);
});

test('permite cancelar estados activos, pero no estados terminales', () => {
  assert.equal(canCancelRequirement('Pendiente'), true);
  assert.equal(canCancelRequirement('En Preparación'), true);
  assert.equal(canCancelRequirement('Listo'), true);
  assert.equal(canCancelRequirement('Entregado'), false);
  assert.equal(canCancelRequirement('Cancelado'), false);
});
