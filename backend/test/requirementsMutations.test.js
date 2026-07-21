'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { pool } = require('../config/database');
const requirementsController = require('../controllers/requirements.controller');

function createResponseRecorder() {
  return {
    statusCode: 200,
    body: null,
    status(code) {
      this.statusCode = code;
      return this;
    },
    json(body) {
      this.body = body;
      return this;
    },
  };
}

function installConnection(t, connection) {
  const originalGetConnection = pool.getConnection;
  pool.getConnection = async () => connection;
  t.after(() => {
    pool.getConnection = originalGetConnection;
  });
}

function transactionConnection(queryHandler, events) {
  return {
    async beginTransaction() {
      events.push('begin');
    },
    query: queryHandler,
    async commit() {
      events.push('commit');
    },
    async rollback() {
      events.push('rollback');
    },
    release() {
      events.push('release');
    },
  };
}

const validItems = [{
  numero_parte: 'CAP123',
  descripcion: 'Capacitor',
  cantidad_requerida: 2,
}];

const unitItems = [{
  numero_parte: 'CAP123',
  descripcion: 'Capacitor',
  cantidad_requerida: 1,
  cantidad_estandarizada: 250,
  cantidad_unidades: 4,
  unidad_empaque: '250',
  ubicacion_destino: 'Línea 3',
}];

test('agrega materiales atómicamente a un requerimiento Pendiente', async (t) => {
  const events = [];
  let insertedParams;
  const connection = transactionConnection(async (sql, params) => {
    if (sql.includes('SELECT status')) return [[{ status: 'Pendiente' }]];
    if (sql.includes('INSERT INTO material_requirement_items')) {
      events.push('item');
      insertedParams = params;
      return [{ affectedRows: 1 }];
    }
    throw new Error(`Consulta inesperada: ${sql}`);
  }, events);
  installConnection(t, connection);

  const response = createResponseRecorder();
  let nextError;
  await requirementsController.addItems(
    { params: { id: 12 }, body: { items: unitItems } },
    response,
    (error) => { nextError = error; },
  );

  assert.equal(nextError, undefined);
  assert.equal(response.body.success, true);
  assert.deepEqual(insertedParams.slice(3, 8), [1000, 250, 4, '250', 'Línea 3']);
  assert.deepEqual(events, ['begin', 'item', 'commit', 'release']);
});

test('rechaza agregar materiales si el requerimiento está En Preparación', async (t) => {
  const events = [];
  const connection = transactionConnection(async (sql) => {
    if (sql.includes('SELECT status')) {
      return [[{ status: 'En Preparación' }]];
    }
    throw new Error(`No debía ejecutar: ${sql}`);
  }, events);
  installConnection(t, connection);

  const response = createResponseRecorder();
  await requirementsController.addItems(
    { params: { id: 12 }, body: { items: validItems } },
    response,
    assert.fail,
  );

  assert.equal(response.statusCode, 409);
  assert.equal(response.body.status, 'En Preparación');
  assert.deepEqual(events, ['begin', 'rollback', 'release']);
});

test('revierte todos los materiales si una inserción falla', async (t) => {
  const events = [];
  const connection = transactionConnection(async (sql) => {
    if (sql.includes('SELECT status')) return [[{ status: 'Pendiente' }]];
    if (sql.includes('INSERT INTO material_requirement_items')) {
      events.push('item-error');
      throw new Error('Fallo simulado');
    }
    throw new Error(`Consulta inesperada: ${sql}`);
  }, events);
  installConnection(t, connection);

  const response = createResponseRecorder();
  let nextError;
  await requirementsController.addItems(
    { params: { id: 12 }, body: { items: validItems } },
    response,
    (error) => { nextError = error; },
  );

  assert.match(nextError.message, /Fallo simulado/);
  assert.deepEqual(events, ['begin', 'item-error', 'rollback', 'release']);
});

test('cancela un requerimiento activo dentro de una transacción', async (t) => {
  const events = [];
  const connection = transactionConnection(async (sql) => {
    if (sql.includes('SELECT status')) return [[{ status: 'Pendiente' }]];
    if (sql.includes("SET status = 'Cancelado'")) {
      events.push('cancel');
      return [{ affectedRows: 1 }];
    }
    throw new Error(`Consulta inesperada: ${sql}`);
  }, events);
  installConnection(t, connection);

  const response = createResponseRecorder();
  await requirementsController.cancel(
    { params: { id: 12 }, body: { actualizado_por: 'Operador' } },
    response,
    assert.fail,
  );

  assert.equal(response.body.success, true);
  assert.deepEqual(events, ['begin', 'cancel', 'commit', 'release']);
});

test('no permite cancelar un requerimiento ya entregado', async (t) => {
  const events = [];
  const connection = transactionConnection(async (sql) => {
    if (sql.includes('SELECT status')) return [[{ status: 'Entregado' }]];
    throw new Error(`No debía ejecutar: ${sql}`);
  }, events);
  installConnection(t, connection);

  const response = createResponseRecorder();
  await requirementsController.cancel(
    { params: { id: 12 }, body: { actualizado_por: 'Operador' } },
    response,
    assert.fail,
  );

  assert.equal(response.statusCode, 409);
  assert.deepEqual(events, ['begin', 'rollback', 'release']);
});
