'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { pool } = require('../config/database');
const requirementsController = require('../controllers/requirements.controller');

function requestBody() {
  return {
    area_destino: 'SMD',
    fecha_requerida: '2026-07-22',
    prioridad: 'Normal',
    creado_por: 'Operador',
    items: [
      {
        numero_parte: 'EBR12345678',
        descripcion: 'Resistor',
        cantidad_requerida: 2,
      },
    ],
  };
}

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

test('confirma encabezado e items dentro de la misma transacción', async (t) => {
  const events = [];
  const connection = {
    async beginTransaction() {
      events.push('begin');
    },
    async query(sql) {
      if (sql.includes('SELECT codigo_requerimiento')) return [[]];
      if (sql.includes('INSERT INTO material_requirements')) {
        events.push('header');
        return [{ insertId: 42 }];
      }
      if (sql.includes('INSERT INTO material_requirement_items')) {
        events.push('item');
        return [{ affectedRows: 1 }];
      }
      throw new Error(`Consulta inesperada: ${sql}`);
    },
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

  const originalGetConnection = pool.getConnection;
  pool.getConnection = async () => connection;
  t.after(() => {
    pool.getConnection = originalGetConnection;
  });

  const response = createResponseRecorder();
  let nextError;
  await requirementsController.create(
    { body: requestBody() },
    response,
    (error) => {
      nextError = error;
    },
  );

  assert.equal(nextError, undefined);
  assert.equal(response.statusCode, 201);
  assert.equal(response.body.id, 42);
  assert.deepEqual(events, ['begin', 'header', 'item', 'commit', 'release']);
});

test('revierte el encabezado cuando falla la inserción de un item', async (t) => {
  const events = [];
  const connection = {
    async beginTransaction() {
      events.push('begin');
    },
    async query(sql) {
      if (sql.includes('SELECT codigo_requerimiento')) return [[]];
      if (sql.includes('INSERT INTO material_requirements')) {
        events.push('header');
        return [{ insertId: 42 }];
      }
      if (sql.includes('INSERT INTO material_requirement_items')) {
        events.push('item-error');
        throw new Error('Fallo simulado');
      }
      throw new Error(`Consulta inesperada: ${sql}`);
    },
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

  const originalGetConnection = pool.getConnection;
  pool.getConnection = async () => connection;
  t.after(() => {
    pool.getConnection = originalGetConnection;
  });

  const response = createResponseRecorder();
  let nextError;
  await requirementsController.create(
    { body: requestBody() },
    response,
    (error) => {
      nextError = error;
    },
  );

  assert.match(nextError.message, /Fallo simulado/);
  assert.equal(response.body, null);
  assert.deepEqual(events, [
    'begin',
    'header',
    'item-error',
    'rollback',
    'release',
  ]);
});
