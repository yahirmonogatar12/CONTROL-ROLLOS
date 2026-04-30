# Backend Conventions

> **Última actualización:** Enero 2026

## Arquitectura Modular

El backend está organizado en módulos siguiendo el patrón MVC.

### Estructura de Módulos
```
backend/
├── server.js              # Punto de entrada (~280 líneas), registro de rutas
├── config/
│   ├── database.js        # Pool de conexión MySQL
│   └── permissions.js     # Permisos por departamento
├── controllers/           # Lógica de negocio (15 módulos)
│   └── [modulo].controller.js
├── routes/                # Definición de endpoints (17 módulos)
│   └── [modulo].routes.js
├── middleware/
│   ├── errorHandler.js    # Manejo de errores
│   └── rateLimiter.js     # Rate limiting para múltiples dispositivos
└── utils/
    ├── dbMigrations.js    # Migraciones de BD
    └── udpDiscovery.js    # Servicio UDP para descubrimiento de servidor
```

### Módulos Disponibles (16 rutas, 14 controllers)

| Módulo | Controller | Routes | Prefijo API | Descripción |
|--------|------------|--------|-------------|-------------|
| Warehousing | warehousing.controller.js | warehousing.routes.js | `/api/warehousing` | Entradas de material |
| Outgoing | outgoing.controller.js | outgoing.routes.js | `/api/outgoing` | Salidas de material |
| Return | return.controller.js | return.routes.js | `/api/return` | Devoluciones de material |
| Plan + BOM | plan.controller.js | plan.routes.js | `/api/plan`, `/api/bom` | Plan de producción y BOM |
| Auth + Users | auth.controller.js | auth.routes.js | `/api/auth`, `/api/users`, `/api/departments`, `/api/cargos`, `/api/permissions` | Autenticación y usuarios |
| Materials | materials.controller.js | materials.routes.js | `/api/materiales`, `/api/materials` | Catálogo de materiales |
| IQC | iqc.controller.js | iqc.routes.js | `/api/iqc` | Inspección de calidad |
| Quality Specs | quality-specs.controller.js | quality-specs.routes.js | `/api/quality-specs` | Especificaciones de calidad |
| Quarantine | quarantine.controller.js | quarantine.routes.js | `/api/quarantine` | Cuarentena |
| Inventory | inventory.controller.js | inventory.routes.js | `/api/inventory` | Inventario de lotes |
| Customers | customers.controller.js | customers.routes.js | `/api/customers` | Catálogo de clientes |
| Cancellation | cancellation.controller.js | cancellation.routes.js | `/api/cancellation` | Solicitudes de cancelación |
| Print | - | print.routes.js | `/api/print` | Impresión remota para móviles |
| Audit | audit.controller.js | audit.routes.js | `/api/audit` | Auditoría de inventario físico |
| Blacklist | blacklist.controller.js | blacklist.routes.js | `/api/blacklist` | Lista negra de lotes |

---

## Express Route Structure

### Route Organization
Cada módulo tiene su propio archivo de rutas en `routes/`:
- Controllers en `controllers/` con la lógica de negocio
- Routes en `routes/` definen los endpoints
- `server.js` registra todas las rutas con `app.use('/api/[modulo]', routes)`

### Route Naming Convention
```
GET    /api/feature           - List all
GET    /api/feature/search    - Search with query params
GET    /api/feature/:id       - Get by ID
POST   /api/feature           - Create new
PUT    /api/feature/:id       - Update by ID
DELETE /api/feature/:id       - Delete by ID
```

---

## Cómo Agregar un Nuevo Módulo

### 1. Crear Controller
En `controllers/[modulo].controller.js`:
```javascript
const { pool } = require('../config/database');

exports.getAll = async (req, res, next) => {
  try {
    const [rows] = await pool.query('SELECT * FROM tabla ORDER BY id DESC');
    res.json(rows);
  } catch (err) {
    next(err);
  }
};

exports.create = async (req, res, next) => {
  try {
    const { campo1, campo2 } = req.body;
    const [result] = await pool.query(
      'INSERT INTO tabla (campo1, campo2) VALUES (?, ?)',
      [campo1, campo2]
    );
    res.status(201).json({ id: result.insertId, message: 'Created' });
  } catch (err) {
    next(err);
  }
};
```

### 2. Crear Routes
En `routes/[modulo].routes.js`:
```javascript
const router = require('express').Router();
const ctrl = require('../controllers/[modulo].controller');

router.get('/', ctrl.getAll);
router.get('/:id', ctrl.getById);
router.post('/', ctrl.create);
router.put('/:id', ctrl.update);
router.delete('/:id', ctrl.delete);

module.exports = router;
```

### 3. Registrar en server.js
```javascript
// Importar
const moduloRoutes = require('./routes/[modulo].routes');

// Registrar
app.use('/api/[modulo]', moduloRoutes);
```

---

## Response Patterns

### Success Responses
```javascript
// Success list
res.json(rows);

// Success single
res.json(rows[0]);

// Success create
res.status(201).json({ id: result.insertId, message: 'Created' });

// Success update
res.json({ success: true, message: 'Updated' });

// Success delete
res.json({ success: true, message: 'Deleted' });
```

### Error Responses
```javascript
// Not found
res.status(404).json({ error: 'Registro no encontrado' });

// Validation error
res.status(400).json({ error: 'Validation message', code: 'ERROR_CODE' });

// Business rule error
res.status(409).json({ error: 'Conflict message' });
```

### Error Handling
```javascript
app.get('/api/endpoint', async (req, res, next) => {
  try {
    // ... logic
  } catch (err) {
    next(err);  // Pass to error middleware
  }
});
```

---

## Middleware

### Rate Limiter
Protección contra sobrecarga con múltiples dispositivos móviles:
```javascript
// General rate limit
app.use(rateLimiter);

// Stricter limit for write operations
app.post('*', writeRateLimiter);
app.put('*', writeRateLimiter);
app.delete('*', writeRateLimiter);
```

### Error Handler
Manejo centralizado de errores en `middleware/errorHandler.js`:
```javascript
module.exports = (err, req, res, next) => {
  console.error('Error:', err.message);
  res.status(500).json({ 
    error: 'Error interno del servidor',
    details: process.env.NODE_ENV === 'development' ? err.message : undefined
  });
};
```

---

## Database Patterns

### Query Style
- Use parameterized queries with `?` placeholders
- Use `pool.query()` for all database operations
- Destructure results: `const [rows] = await pool.query(...)`

### Column Naming
- snake_case for all columns: `fecha_registro`, `numero_parte`
- Boolean flags as TINYINT: `cancelado`, `tiene_salida`, `iqc_required`
- Timestamps: `created_at`, `updated_at`, `closed_at`

### Schema Migrations
- Add columns with `ALTER TABLE ... ADD COLUMN IF NOT EXISTS`
- Run migrations at server startup via `utils/dbMigrations.js`
- Check column existence before adding:
```javascript
const [rows] = await pool.query(`
  SELECT COLUMN_NAME FROM INFORMATION_SCHEMA.COLUMNS 
  WHERE TABLE_SCHEMA = DATABASE() 
  AND TABLE_NAME = ? AND COLUMN_NAME = ?
`, [tableName, columnName]);
```

---

## Key Tables

### control_material_almacen
Main warehousing table - material receiving records
- `codigo_material_recibido` - Unique label code (primary identifier)
- `receiving_lot_code` - First 20 chars of label (groups labels)
- `iqc_status` - 'NotRequired', 'Pending', 'InProgress', 'Released', 'Rejected'

### materiales
Material master data with IQC configuration
- `numero_parte` - Part number (primary key)
- `iqc_required` - Whether material needs IQC
- `*_enabled`, `*_sampling_level`, `*_aql_level` - Per-test IQC config

### iqc_inspection_lot
IQC inspection records
- `receiving_lot_code` - Links to warehousing records
- `disposition` - 'Pending', 'Release', 'Return', 'Scrap', 'Hold', 'Rework'
- `status` - 'Pending', 'InProgress', 'Closed'

### inventory_audit
Physical inventory audit records
- `audit_id` - Unique audit session identifier
- `status` - 'InProgress', 'Completed', 'Cancelled'
- Real-time sync via WebSocket

### material_returns
Material return to supplier records
- `return_id` - Unique return identifier
- `reason` - Return reason code
- `status` - 'Pending', 'Approved', 'Completed'

---

## Environment Configuration

### .env File (backend/.env)
```
DB_HOST=localhost
DB_PORT=3306
DB_USER=root
DB_PASSWORD=
DB_NAME=meslocal
```

### Loading .env
The server auto-detects .env location for both development and packaged modes:
1. Same directory as .exe (production)
2. `backend/` folder (development)
3. Current working directory (fallback)

---

## UDP Discovery Service

Para que los dispositivos móviles encuentren automáticamente el servidor:

```javascript
// Se inicia en server.js
const { startDiscoveryService } = require('./utils/udpDiscovery');
startDiscoveryService(PORT);
```

- Escucha en puerto UDP 3001
- Responde con la IP y puerto del servidor
- Los móviles usan `ServerDiscoveryService` para encontrar el servidor

---

## Health Check Endpoint

```
GET /api/health
```

Respuesta:
```json
{
  "status": "OK",
  "database": "Connected",
  "pool": { "active": 2, "idle": 8 },
  "rateLimiting": { "activeClients": 5 },
  "server": { "uptime": 3600 }
}
```
