/**
 * Auth Routes - Autenticación y Gestión de Usuarios
 * Pantalla Flutter: lib/screens/login/
 */

const express = require('express');
const authController = require('../controllers/auth.controller');

// Auth router (montado en /api/auth)
const authRouter = express.Router();
authRouter.post('/login', authController.login);
authRouter.post('/logout', authController.logout);
authRouter.get('/verify/:userId', authController.verify);

// Users router (montado en /api/users)
const usersRouter = express.Router();
usersRouter.get('/', authController.getAllUsers);
usersRouter.get('/:id', authController.getUserById);
usersRouter.post('/', authController.createUser);
usersRouter.put('/:id', authController.updateUser);
usersRouter.put('/:id/password', authController.changePassword);
usersRouter.post('/:id/change-password', authController.changeOwnPassword);
usersRouter.put('/:id/toggle-active', authController.toggleActive);
usersRouter.get('/:id/permissions', authController.getUserPermissions);
usersRouter.put('/:id/permissions', authController.updateUserPermissions);

// Departments router (montado en /api/departments)
const departmentsRouter = express.Router();
departmentsRouter.get('/', authController.getDepartments);

// Cargos router (montado en /api/cargos)
const cargosRouter = express.Router();
cargosRouter.get('/', authController.getCargos);

// Permissions router (montado en /api/permissions)
const permissionsRouter = express.Router();
permissionsRouter.get('/available', authController.getAvailablePermissions);

module.exports = {
  authRouter,
  usersRouter,
  departmentsRouter,
  cargosRouter,
  permissionsRouter
};
