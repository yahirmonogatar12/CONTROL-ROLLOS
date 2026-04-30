# Sistema de Permisos y Autenticación

> **Última actualización:** Enero 2026

## Arquitectura de Autenticación

### Flujo de Login
1. Usuario ingresa credenciales en `LoginScreen`
2. `AuthService.login()` envía POST a `/api/auth/login`
3. Backend valida contra tabla `usuarios` en MySQL
4. Si es exitoso, se crea `UserSession` y se guarda en `SharedPreferences`
5. `app.dart` detecta el cambio y muestra `MainTabbedScreen`

### Persistencia de Sesión
- Sesión guardada en `SharedPreferences` con key `user_session`
- Al iniciar la app, `AuthService.restoreSession()` intenta restaurar
- Backend verifica validez con GET `/api/auth/verify/:userId`

---

## Modelo de Usuario (UserSession)

```dart
class UserSession {
  final int id;
  final String username;
  final String email;
  final String nombreCompleto;
  final String departamento;  // Clave para permisos
  final String cargo;
}
```

El campo `departamento` determina los permisos del usuario.

---

## Departamentos y Permisos

### Matriz de Permisos por Módulo

| Departamento          | Warehousing | Outgoing | IQC    | Inventory | Full Access |
|-----------------------|-------------|----------|--------|-----------|-------------|
| Sistemas              | ✅ Write    | ✅ Write | ✅ Write | ✅ View   | ✅ Yes      |
| Gerencia              | ✅ Write    | ✅ Write | ✅ Write | ✅ View   | ✅ Yes      |
| Administración        | ✅ Write    | ✅ Write | ✅ Write | ✅ View   | ✅ Yes      |
| Almacén               | ✅ Write    | ✅ Write | 👁 View | ✅ View   | ❌ No       |
| Almacén Supervisor    | ✅ Write    | ✅ Write | 👁 View | ✅ View   | ❌ No       |
| Calidad               | 👁 View     | 👁 View  | ✅ Write | ✅ View   | ❌ No       |
| Calidad Supervisor    | 👁 View     | 👁 View  | ✅ Write | ✅ View   | ❌ No       |
| Otros                 | 👁 View     | 👁 View  | 👁 View | ✅ View   | ❌ No       |

### Listas de Departamentos en AuthService

```dart
// Acceso total a todo
static const List<String> _fullAccessDepartments = [
  'Sistemas', 
  'Gerencia', 
  'Administración'
];

// Pueden escribir en Warehousing (Entradas)
static const List<String> _warehousingWriteDepartments = [
  'Sistemas', 'Gerencia', 'Administración', 
  'Almacén', 'Almacén Supervisor'
];

// Pueden escribir en Outgoing (Salidas)
static const List<String> _outgoingWriteDepartments = [
  'Sistemas', 'Gerencia', 'Administración', 
  'Almacén', 'Almacén Supervisor'
];

// Pueden escribir en IQC (Inspección)
static const List<String> _iqcWriteDepartments = [
  'Sistemas', 'Gerencia', 'Administración', 
  'Calidad', 'Calidad Supervisor'
];
```

---

## Getters de Permisos Disponibles

```dart
// Usuario actual
AuthService.currentUser        // UserSession? 
AuthService.isLoggedIn         // bool
AuthService.currentDepartment  // String

// Permisos generales
AuthService.hasFullAccess      // bool - Acceso total

// Permisos de escritura por módulo
AuthService.canWriteWarehousing  // bool
AuthService.canWriteOutgoing     // bool
AuthService.canWriteIqc          // bool

// Permisos de lectura (todos los usuarios logueados)
AuthService.canViewWarehousing   // bool
AuthService.canViewOutgoing      // bool
AuthService.canViewIqc           // bool
```

---

## Uso en Widgets

### Ocultar/Mostrar Botones según Permiso

```dart
// En el build() del widget
final canWrite = AuthService.canWriteWarehousing;

// Ocultar botón completamente
if (canWrite)
  ElevatedButton(
    onPressed: _save,
    child: Text(tr('save')),
  ),

// O deshabilitar botón
ElevatedButton(
  onPressed: canWrite ? _save : null,
  child: Text(tr('save')),
),
```

### Mostrar Indicador de Solo Lectura

```dart
if (!AuthService.canWriteIqc)
  Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    decoration: BoxDecoration(
      color: Colors.orange.withOpacity(0.2),
      borderRadius: BorderRadius.circular(4),
    ),
    child: Row(
      children: [
        const Icon(Icons.visibility, color: Colors.orange, size: 16),
        const SizedBox(width: 8),
        Text(tr('read_only_mode'), style: const TextStyle(color: Colors.orange)),
      ],
    ),
  ),
```

### Restringir Tabs por Departamento

En `MainTabbedScreen`, el departamento "Calidad" solo ve IQC e Inventario:

```dart
// Departamentos que solo ven IQC
static const _iqcOnlyDepartments = ['Calidad', 'Calidad Supervisor'];

bool get _isIqcOnlyUser {
  final dept = AuthService.currentUser?.departamento ?? '';
  return _iqcOnlyDepartments.contains(dept);
}

// En build():
if (_isIqcOnlyUser) {
  // Mostrar solo tabs de IQC y Long-Term Inventory
} else {
  // Mostrar todos los tabs
}
```

---

## Agregar Permisos para Nuevo Módulo

### 1. Definir Lista de Departamentos

En `lib/core/services/auth_service.dart`:

```dart
// Agregar después de las otras listas
static const List<String> _[modulo]WriteDepartments = [
  'Sistemas', 'Gerencia', 'Administración', 
  '[DepartamentoEspecifico]'
];
```

### 2. Agregar Getter de Permiso

```dart
/// Verifica si el usuario puede escribir en [Modulo]
static bool get canWrite[Modulo] {
  if (_currentUser == null) return false;
  return _[modulo]WriteDepartments.contains(_currentUser!.departamento);
}

/// Verifica si el usuario puede ver [Modulo]
static bool get canView[Modulo] => _currentUser != null;
```

### 3. Usar en el Widget

```dart
import 'package:material_warehousing_flutter/core/services/auth_service.dart';

// En el widget
final canWrite = AuthService.canWrite[Modulo];

// Condicionar acciones
ElevatedButton(
  onPressed: canWrite ? _save : null,
  child: Text(tr('save')),
),
```

---

## Backend: Endpoints de Autenticación

### POST /api/auth/login
```javascript
// Request
{ "username": "user", "password": "pass" }

// Response exitoso
{
  "success": true,
  "message": "Login exitoso",
  "user": {
    "id": 1,
    "username": "user",
    "email": "user@example.com",
    "nombre_completo": "Usuario Ejemplo",
    "departamento": "Almacén",
    "cargo": "Operador"
  }
}

// Response fallido
{
  "success": false,
  "message": "Credenciales incorrectas",
  "intentosRestantes": 2
}
```

### GET /api/auth/verify/:userId
```javascript
// Response
{ "valid": true }  // o { "valid": false }
```

### POST /api/auth/logout
```javascript
// Request
{ "userId": 1 }

// Response
{ "success": true }
```

---

## Tabla de Usuarios (BD)

```sql
CREATE TABLE usuarios (
  id INT AUTO_INCREMENT PRIMARY KEY,
  username VARCHAR(50) UNIQUE NOT NULL,
  password VARCHAR(255) NOT NULL,  -- Hash
  email VARCHAR(100),
  nombre_completo VARCHAR(150),
  departamento VARCHAR(50),        -- Clave para permisos
  cargo VARCHAR(50),
  activo TINYINT DEFAULT 1,
  intentos_fallidos INT DEFAULT 0,
  ultimo_login DATETIME,
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP
);
```

---

## Traducciones Relacionadas

```dart
// En app_translations.dart
'login_title': 'Login',
'login_username': 'Username',
'login_password': 'Password',
'login_button': 'Sign In',
'login_empty_fields': 'Please enter username and password',
'login_attempts_remaining': 'Attempts remaining',
'logout': 'Logout',
'logout_confirm': 'Are you sure you want to logout?',
'read_only_mode': 'View Only Mode',
```
