# Inventory Audit (Auditoria de Inventario)

> **Ultima actualizacion:** Enero 2026

Este documento describe el flujo real de auditoria de inventario segun la implementacion en backend (`backend/controllers/audit.controller.js`) y los datos en la base de datos.

---

## Objetivo

Validar fisicamente el inventario por ubicacion y registrar discrepancias. Al finalizar, los materiales no encontrados se procesan como salida por discrepancia.

---

## Flujo General

1. **Supervisor (PC) inicia auditoria**
   - Se crea una nueva auditoria con status `InProgress`.
   - Se generan ubicaciones a auditar a partir de `control_material_almacen`.
2. **Operadores (movil) escanean ubicaciones y materiales**
   - Cada ubicacion pasa de `Pending` a `InProgress`.
   - Cada material escaneado se marca como `Found`.
3. **Operador completa ubicacion**
   - Todo lo pendiente se marca como `Missing`.
   - Ubicacion termina como `Verified` o `Discrepancy`.
4. **Supervisor finaliza auditoria (PC)**
   - Se crean registros `Missing` para cualquier material que quedo sin escanear.
   - Los `Missing` se convierten en salidas reales y quedan `ProcessedOut`.

---

## Seleccion de Materiales para Auditoria

Al iniciar la auditoria se incluyen SOLO materiales activos:
- `cantidad_actual > 0`
- `cancelado = 0 o NULL`
- `estado_desecho = 0 o NULL`
- `tiene_salida = 0 o NULL`
- `ubicacion_salida` no nula y no vacia

Las ubicaciones se agrupan por `ubicacion_salida` y se almacenan en `inventory_audit_location`.

---

## Estados

### Auditoria (`inventory_audit.status`)
- `Pending`
- `InProgress`
- `Completed`
- `Cancelled`

### Ubicacion (`inventory_audit_location.status`)
- `Pending` (no iniciada)
- `InProgress` (escaneando)
- `Verified` (todo encontrado)
- `Discrepancy` (faltantes)

### Item (`inventory_audit_item.status`)
- `Pending` (default)
- `Found` (escaneado)
- `Missing` (no encontrado)
- `ProcessedOut` (salida por discrepancia aplicada)

---

## Endpoints Clave (API)

### Gestion PC
- `GET /api/audit/active` - auditoria activa
- `POST /api/audit/start` - iniciar auditoria
- `POST /api/audit/end` - finalizar auditoria
- `GET /api/audit/summary` - resumen activo
- `GET /api/audit/locations` - ubicaciones y estado
- `GET /api/audit/location-items` - items por ubicacion

### Operaciones Movil
- `POST /api/audit/scan-location` - iniciar ubicacion
- `POST /api/audit/scan-item` - escanear material
- `POST /api/audit/mark-missing` - marcar faltante
- `POST /api/audit/complete-location` - completar ubicacion

### Historial
- `GET /api/audit/history`
- `GET /api/audit/history/:id`
- `GET /api/audit/compare`

---

## Detalle de Operaciones

### 1) Iniciar Auditoria (`/start`)
- Verifica que no exista auditoria activa.
- Genera `audit_code` con timestamp.
- Inserta en `inventory_audit` con `status = InProgress`.
- Inserta todas las ubicaciones en `inventory_audit_location` con `status = Pending`.

### 2) Escanear Ubicacion (`/scan-location`)
- Verifica auditoria activa.
- Verifica que la ubicacion exista en `inventory_audit_location`.
- Cambia ubicacion a `InProgress` (si estaba `Pending`).
- Devuelve la lista de materiales de esa ubicacion.

### 3) Escanear Material (`/scan-item`)
- Verifica auditoria activa.
- Busca material por `codigo_material_recibido`.
- Si se proporciona `location`, valida coincidencia con `ubicacion_salida`.
- Inserta o actualiza `inventory_audit_item` como `Found`.
- Si la ubicacion queda completa, la marca `Verified`.

### 4) Marcar Faltante (`/mark-missing`)
- Inserta o actualiza `inventory_audit_item` como `Missing`.
- Marca la ubicacion como `Discrepancy`.

### 5) Completar Ubicacion (`/complete-location`)
- Marca todo lo pendiente como `Missing`.
- Actualiza ubicacion a `Verified` o `Discrepancy` segun pendientes.

### 6) Finalizar Auditoria (`/end`)
- Verifica auditoria activa.
- Crea registros `Missing` para materiales no escaneados.
- Por cada `Missing`:
  - Inserta salida en `control_material_salida` con:
    - `depto_salida = 'AUDITORIA'`
    - `proceso_salida = 'DISCREPANCIA INVENTARIO'`
  - Marca `control_material_almacen.tiene_salida = 1` y `estado_desecho = 1`.
  - Actualiza `inventory_audit_item.status = 'ProcessedOut'`.
- Finaliza auditoria con `status = Completed` y estadisticas.

---

## Permisos Requeridos

En `auth.controller.js`:
- `view_audit` - ver modulo de auditoria
- `start_audit` - iniciar/finalizar auditoria (PC)
- `scan_audit` - escanear en auditoria (movil)

---

## Consideraciones para Modificar

- **Filtros de auditoria**: cambiar la consulta de ubicaciones en `startAudit`.
- **Reglas de discrepancia**: ajustar `markMissing`, `completeLocation` y `endAudit`.
- **Salida por discrepancia**: revisar insercion en `control_material_salida`.
- **Estados**: cualquier nuevo estado requiere actualizar UI y reportes.

---

## Archivos Relacionados

- `backend/controllers/audit.controller.js`
- `backend/routes/audit.routes.js`
- `lib/core/services/api_service.dart` (metodos audit)
- `Documentacion/database-schema.md` (tablas inventory_audit)
