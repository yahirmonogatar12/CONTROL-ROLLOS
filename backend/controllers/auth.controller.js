/**
 * Auth Controller - Autenticación y Gestión de Usuarios
 * Pantalla Flutter: lib/screens/login/
 */

const { pool } = require('../config/database');
const crypto = require('crypto');

// ============================================
// AUTENTICACIÓN
// ============================================

// POST /api/auth/login - Iniciar sesión
exports.login = async (req, res, next) => {
  try {
    const { username, password } = req.body;

    if (!username || !password) {
      return res.status(400).json({ 
        success: false, 
        message: 'Username y password son requeridos' 
      });
    }

    const [users] = await pool.query(`
      SELECT id, username, password_hash, email, nombre_completo, 
             departamento, cargo, activo, intentos_fallidos, bloqueado_hasta
      FROM usuarios_sistema 
      WHERE username = ?
    `, [username]);

    if (users.length === 0) {
      return res.status(401).json({ 
        success: false, 
        message: 'Usuario o contraseña incorrectos' 
      });
    }

    const user = users[0];

    if (!user.activo) {
      return res.status(401).json({ 
        success: false, 
        message: 'Usuario desactivado. Contacte al administrador.' 
      });
    }

    if (user.bloqueado_hasta && new Date(user.bloqueado_hasta) > new Date()) {
      const tiempoRestante = Math.ceil((new Date(user.bloqueado_hasta) - new Date()) / 60000);
      return res.status(401).json({ 
        success: false, 
        message: `Usuario bloqueado. Intente en ${tiempoRestante} minutos.` 
      });
    }

    const hashedPassword = crypto.createHash('sha256').update(password).digest('hex');

    if (hashedPassword !== user.password_hash) {
      const nuevosIntentos = (user.intentos_fallidos || 0) + 1;
      let bloqueadoHasta = null;
      
      if (nuevosIntentos >= 5) {
        bloqueadoHasta = new Date(Date.now() + 15 * 60 * 1000);
      }

      await pool.query(`
        UPDATE usuarios_sistema 
        SET intentos_fallidos = ?, bloqueado_hasta = ?
        WHERE id = ?
      `, [nuevosIntentos, bloqueadoHasta, user.id]);

      return res.status(401).json({ 
        success: false, 
        message: 'Usuario o contraseña incorrectos',
        intentosRestantes: Math.max(0, 5 - nuevosIntentos)
      });
    }

    await pool.query(`
      UPDATE usuarios_sistema 
      SET intentos_fallidos = 0, bloqueado_hasta = NULL, ultimo_acceso = NOW()
      WHERE id = ?
    `, [user.id]);

    res.json({ 
      success: true, 
      message: 'Login exitoso',
      user: {
        id: user.id,
        username: user.username,
        email: user.email,
        nombre_completo: user.nombre_completo,
        departamento: user.departamento,
        cargo: user.cargo
      }
    });

  } catch (err) {
    next(err);
  }
};

// POST /api/auth/logout - Cerrar sesión
exports.logout = async (req, res, next) => {
  try {
    const { userId } = req.body;
    
    if (userId) {
      await pool.query(`
        UPDATE usuarios_sistema 
        SET ultimo_acceso = NOW()
        WHERE id = ?
      `, [userId]);
    }

    res.json({ success: true, message: 'Sesión cerrada' });
  } catch (err) {
    next(err);
  }
};

// GET /api/auth/verify/:userId - Verificar si el usuario existe y está activo
exports.verify = async (req, res, next) => {
  try {
    const { userId } = req.params;

    const [users] = await pool.query(`
      SELECT id, username, nombre_completo, departamento, cargo, activo
      FROM usuarios_sistema 
      WHERE id = ? AND activo = 1
    `, [userId]);

    if (users.length === 0) {
      return res.json({ valid: false });
    }

    res.json({ valid: true, user: users[0] });
  } catch (err) {
    next(err);
  }
};

// ============================================
// GESTIÓN DE USUARIOS
// ============================================

// GET /api/users - Listar todos los usuarios
exports.getAllUsers = async (req, res, next) => {
  try {
    const [users] = await pool.query(`
      SELECT id, username, email, nombre_completo, departamento, cargo, 
             activo, ultimo_acceso, fecha_creacion
      FROM usuarios_sistema 
      ORDER BY nombre_completo
    `);
    res.json(users);
  } catch (err) {
    next(err);
  }
};

// GET /api/users/:id - Obtener usuario por ID
exports.getUserById = async (req, res, next) => {
  try {
    const { id } = req.params;
    const [users] = await pool.query(`
      SELECT id, username, email, nombre_completo, departamento, cargo, 
             activo, ultimo_acceso, fecha_creacion
      FROM usuarios_sistema 
      WHERE id = ?
    `, [id]);
    
    if (users.length === 0) {
      return res.status(404).json({ error: 'Usuario no encontrado' });
    }
    
    res.json(users[0]);
  } catch (err) {
    next(err);
  }
};

// POST /api/users - Crear nuevo usuario
exports.createUser = async (req, res, next) => {
  try {
    const { username, password, email, nombre_completo, departamento, cargo } = req.body;
    
    if (!username || !password || !nombre_completo || !departamento || !cargo) {
      return res.status(400).json({ error: 'Faltan campos requeridos' });
    }
    
    const [existing] = await pool.query(
      'SELECT id FROM usuarios_sistema WHERE username = ?', 
      [username]
    );
    
    if (existing.length > 0) {
      return res.status(400).json({ error: 'El nombre de usuario ya existe' });
    }
    
    const password_hash = crypto.createHash('sha256').update(password).digest('hex');
    
    const [result] = await pool.query(`
      INSERT INTO usuarios_sistema 
      (username, password_hash, email, nombre_completo, departamento, cargo, activo, fecha_creacion)
      VALUES (?, ?, ?, ?, ?, ?, 1, NOW())
    `, [username, password_hash, email || null, nombre_completo, departamento, cargo]);
    
    res.status(201).json({ 
      success: true, 
      message: 'Usuario creado exitosamente',
      id: result.insertId 
    });
  } catch (err) {
    next(err);
  }
};

// PUT /api/users/:id - Actualizar usuario
exports.updateUser = async (req, res, next) => {
  try {
    const { id } = req.params;
    const { email, nombre_completo, departamento, cargo } = req.body;
    
    if (!nombre_completo || !departamento || !cargo) {
      return res.status(400).json({ error: 'Faltan campos requeridos' });
    }
    
    await pool.query(`
      UPDATE usuarios_sistema 
      SET email = ?, nombre_completo = ?, departamento = ?, cargo = ?
      WHERE id = ?
    `, [email || null, nombre_completo, departamento, cargo, id]);
    
    res.json({ success: true, message: 'Usuario actualizado' });
  } catch (err) {
    next(err);
  }
};

// PUT /api/users/:id/password - Cambiar contraseña (admin, sin verificar actual)
exports.changePassword = async (req, res, next) => {
  try {
    const { id } = req.params;
    const { newPassword } = req.body;
    
    if (!newPassword || newPassword.length < 4) {
      return res.status(400).json({ error: 'La contraseña debe tener al menos 4 caracteres' });
    }
    
    const password_hash = crypto.createHash('sha256').update(newPassword).digest('hex');
    
    await pool.query(`
      UPDATE usuarios_sistema 
      SET password_hash = ?, intentos_fallidos = 0, bloqueado_hasta = NULL
      WHERE id = ?
    `, [password_hash, id]);
    
    res.json({ success: true, message: 'Contraseña actualizada' });
  } catch (err) {
    next(err);
  }
};

// POST /api/users/:id/change-password - Cambiar contraseña propia (requiere contraseña actual)
exports.changeOwnPassword = async (req, res, next) => {
  try {
    const { id } = req.params;
    const { currentPassword, newPassword } = req.body;
    
    if (!currentPassword || !newPassword) {
      return res.status(400).json({ error: 'Se requiere contraseña actual y nueva' });
    }
    
    if (newPassword.length < 4) {
      return res.status(400).json({ error: 'La contraseña debe tener al menos 4 caracteres' });
    }
    
    // Verificar contraseña actual
    const [users] = await pool.query(
      'SELECT password_hash FROM usuarios_sistema WHERE id = ?', 
      [id]
    );
    
    if (users.length === 0) {
      return res.status(404).json({ error: 'Usuario no encontrado' });
    }
    
    const currentHash = crypto.createHash('sha256').update(currentPassword).digest('hex');
    
    if (currentHash !== users[0].password_hash) {
      return res.status(401).json({ error: 'La contraseña actual es incorrecta' });
    }
    
    // Actualizar con nueva contraseña
    const newHash = crypto.createHash('sha256').update(newPassword).digest('hex');
    
    await pool.query(`
      UPDATE usuarios_sistema 
      SET password_hash = ?, intentos_fallidos = 0, bloqueado_hasta = NULL
      WHERE id = ?
    `, [newHash, id]);
    
    res.json({ success: true, message: 'Contraseña actualizada exitosamente' });
  } catch (err) {
    next(err);
  }
};

// PUT /api/users/:id/toggle-active - Activar/desactivar usuario
exports.toggleActive = async (req, res, next) => {
  try {
    const { id } = req.params;
    
    const [users] = await pool.query('SELECT activo FROM usuarios_sistema WHERE id = ?', [id]);
    if (users.length === 0) {
      return res.status(404).json({ error: 'Usuario no encontrado' });
    }
    
    const newStatus = users[0].activo ? 0 : 1;
    
    await pool.query('UPDATE usuarios_sistema SET activo = ? WHERE id = ?', [newStatus, id]);
    
    res.json({ 
      success: true, 
      message: newStatus ? 'Usuario activado' : 'Usuario desactivado',
      activo: newStatus 
    });
  } catch (err) {
    next(err);
  }
};

// ============================================
// CATÁLOGOS
// ============================================

// GET /api/departments - Listar departamentos disponibles
exports.getDepartments = async (req, res, next) => {
  try {
    const departments = [
      'Sistemas',
      'Gerencia',
      'Administración',
      'Almacén',
      'Almacén Supervisor',
      'Calidad',
      'Calidad Supervisor',
      'Producción',
      'Producción Supervisor',
      'Mantenimiento',
      'Recursos Humanos',
      'Compras'
    ];
    res.json(departments);
  } catch (err) {
    next(err);
  }
};

// GET /api/cargos - Listar cargos disponibles
exports.getCargos = async (req, res, next) => {
  try {
    const cargos = [
      'Operador',
      'Técnico',
      'Supervisor',
      'Jefe de Área',
      'Gerente',
      'Director',
      'Auxiliar',
      'Analista',
      'Coordinador',
      'Inspector'
    ];
    res.json(cargos);
  } catch (err) {
    next(err);
  }
};

// GET /api/permissions/available - Listar todos los permisos disponibles del sistema
exports.getAvailablePermissions = async (req, res, next) => {
  try {
    const permissions = [
      { key: 'view_warehousing', name: 'Ver Entradas', category: 'Almacén', description: 'Puede ver el módulo de entradas de material' },
      { key: 'write_warehousing', name: 'Editar Entradas', category: 'Almacén', description: 'Puede crear/editar entradas de material' },
      { key: 'multi_edit_warehousing', name: 'Edición Múltiple Entradas', category: 'Almacén', description: 'Puede editar múltiples entradas a la vez' },
      { key: 'view_outgoing', name: 'Ver Salidas', category: 'Almacén', description: 'Puede ver el módulo de salidas de material' },
      { key: 'write_outgoing', name: 'Editar Salidas', category: 'Almacén', description: 'Puede crear/editar salidas de material' },
      { key: 'view_inventory', name: 'Ver Inventario', category: 'Almacén', description: 'Puede ver el inventario' },
      { key: 'view_material_return', name: 'Ver Devoluciones', category: 'Almacén', description: 'Puede ver el módulo de devoluciones de material' },
      { key: 'write_material_return', name: 'Crear Devoluciones', category: 'Almacén', description: 'Puede crear devoluciones de material' },
      { key: 'approve_cancellation', name: 'Aprobar Cancelaciones', category: 'Almacén', description: 'Puede aprobar/rechazar solicitudes de cancelación de entradas' },
      { key: 'view_requirements', name: 'Ver Requerimientos', category: 'Producción', description: 'Puede ver el módulo de requerimientos de material' },
      { key: 'write_requirements', name: 'Crear Requerimientos', category: 'Producción', description: 'Puede crear/editar requerimientos de material' },
      { key: 'approve_requirements', name: 'Aprobar Requerimientos', category: 'Producción', description: 'Puede aprobar/rechazar requerimientos de material' },
      { key: 'view_material_control', name: 'Ver Control Materiales', category: 'Catálogo', description: 'Puede ver el catálogo de materiales' },
      { key: 'write_material_control', name: 'Editar Control Materiales', category: 'Catálogo', description: 'Puede crear/editar materiales en el catálogo' },
      { key: 'delete_material_control', name: 'Eliminar Materiales', category: 'Catálogo', description: 'Puede eliminar materiales del catálogo' },
      { key: 'write_comparacion', name: 'Gestionar Comparaciones', category: 'Catálogo', description: 'Puede crear materiales (solo NParte y Comparación) y editar comparaciones' },
      { key: 'view_audit', name: 'Ver Auditoría Inventario', category: 'Auditoría', description: 'Puede ver el módulo de auditoría de inventario' },
      { key: 'start_audit', name: 'Iniciar Auditoría', category: 'Auditoría', description: 'Puede iniciar y finalizar auditorías de inventario' },
      { key: 'scan_audit', name: 'Escanear en Auditoría', category: 'Auditoría', description: 'Puede escanear materiales durante una auditoría (móvil)' },
      { key: 'view_iqc', name: 'Ver IQC', category: 'Calidad', description: 'Puede ver el módulo de inspección IQC' },
      { key: 'write_iqc', name: 'Editar IQC', category: 'Calidad', description: 'Puede realizar inspecciones IQC' },
      { key: 'view_quarantine', name: 'Ver Cuarentena', category: 'Calidad', description: 'Puede ver materiales en cuarentena' },
      { key: 'send_quarantine', name: 'Enviar a Cuarentena', category: 'Calidad', description: 'Puede enviar material a cuarentena' },
      { key: 'release_quarantine', name: 'Liberar Cuarentena', category: 'Calidad', description: 'Puede liberar material de cuarentena' },
      { key: 'view_blacklist', name: 'Ver Lista Negra', category: 'Calidad', description: 'Puede ver la lista negra de lotes' },
      { key: 'write_blacklist', name: 'Editar Lista Negra', category: 'Calidad', description: 'Puede agregar/eliminar lotes de la lista negra' },
      { key: 'view_reentry', name: 'Ver Reingreso', category: 'Almacén', description: 'Puede ver el módulo de reingreso/reubicación de material' },
      { key: 'write_reentry', name: 'Reubicar Material', category: 'Almacén', description: 'Puede cambiar ubicaciones de material (reubicación)' },
      { key: 'view_location_search', name: 'Búsqueda de Ubicación', category: 'Almacén', description: 'Puede ver el módulo de búsqueda de ubicación por número de parte' },
      { key: 'manage_users', name: 'Gestión de Usuarios', category: 'Sistema', description: 'Puede administrar usuarios y permisos' },
      { key: 'view_reports', name: 'Ver Reportes', category: 'Reportes', description: 'Puede ver reportes del sistema' },
      { key: 'export_data', name: 'Exportar Datos', category: 'Reportes', description: 'Puede exportar datos a Excel' },
      { key: 'write_pcb_inventory', name: 'Escanear PCB Inventario', category: 'Inventario PCB', description: 'Puede registrar escaneos en el inventario de PCBs' },
      { key: 'view_pcb_entrada', name: 'Ver PCB Entrada', category: 'Inventario PCB', description: 'Puede ver el módulo de entrada de PCBs' },
      { key: 'view_pcb_salida', name: 'Ver PCB Salida', category: 'Inventario PCB', description: 'Puede ver el módulo de salida de PCBs' },
      { key: 'view_pcb_inventario', name: 'Ver PCB Inventario', category: 'Inventario PCB', description: 'Puede ver el inventario actual de PCBs' },
      { key: 'view_smt_requests', name: 'Ver Solicitudes SMT', category: 'SMT', description: 'Puede ver y surtir solicitudes de material de las líneas SMT' },
    ];
    res.json(permissions);
  } catch (err) {
    next(err);
  }
};

// GET /api/users/:id/permissions - Obtener permisos de un usuario
exports.getUserPermissions = async (req, res, next) => {
  try {
    const { id } = req.params;
    const [permissions] = await pool.query(
      'SELECT permission_key, enabled FROM user_permissions_materiales WHERE user_id = ?',
      [id]
    );
    res.json(permissions);
  } catch (err) {
    next(err);
  }
};

// PUT /api/users/:id/permissions - Actualizar permisos de un usuario
exports.updateUserPermissions = async (req, res, next) => {
  try {
    const { id } = req.params;
    const { permissions } = req.body;
    
    console.log('Actualizando permisos para usuario:', id);
    console.log('Permisos recibidos:', JSON.stringify(permissions));
    
    if (!permissions || !Array.isArray(permissions)) {
      return res.status(400).json({ error: 'Se requiere un array de permisos' });
    }
    
    await pool.query('DELETE FROM user_permissions_materiales WHERE user_id = ?', [id]);
    
    let insertCount = 0;
    for (const perm of permissions) {
      if (perm.enabled === true) {
        await pool.query(
          'INSERT IGNORE INTO user_permissions_materiales (user_id, permission_key, enabled) VALUES (?, ?, 1)',
          [id, perm.permission_key]
        );
        insertCount++;
      }
    }
    
    console.log('Permisos insertados:', insertCount);
    res.json({ success: true, message: 'Permisos actualizados', count: insertCount });
  } catch (err) {
    console.error('Error actualizando permisos:', err);
    next(err);
  }
};
