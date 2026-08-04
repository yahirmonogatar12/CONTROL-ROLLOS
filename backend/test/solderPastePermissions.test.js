'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const authController = require('../controllers/auth.controller');

test('publica el permiso especial para autorizar retorno de scrap de pasta', async () => {
  let payload = null;
  await authController.getAvailablePermissions(
    {},
    { json: (value) => { payload = value; } },
    (error) => { throw error; },
  );

  const permission = payload.find(
    (item) => item.key === 'authorize_solder_paste_scrap_return',
  );
  assert.ok(permission);
  assert.equal(permission.category, 'SMT');
  assert.match(permission.description, /nunca llegó a línea/i);
});
