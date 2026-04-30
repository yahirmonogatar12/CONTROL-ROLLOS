# Schema de Base de Datos

> **Última actualización:** Enero 2026

Este documento describe todas las tablas utilizadas por el sistema.

---

## Tablas Principales

### control_material_almacen (Entradas de Material)

Tabla principal de recepción de materiales.

| Columna | Tipo | Descripción |
|---------|------|-------------|
| `id` | INT (PK) | ID único |
| `codigo_material_recibido` | TEXT | Código de etiqueta único (ej: EAE66213501-202511270006) |
| `receiving_lot_code` | VARCHAR(25) | Primeros 20 chars del código (agrupa etiquetas) |
| `label_seq` | INT | Secuencia de etiqueta (últimos 4 dígitos) |
| `numero_parte` | TEXT | Número de parte |
| `codigo_material` | TEXT | Código de material |
| `codigo_material_original` | TEXT | Código original del material |
| `numero_lote_material` | TEXT | Lote del proveedor |
| `cantidad_actual` | INT | Cantidad disponible |
| `cantidad_estandarizada` | TEXT | Unidad de empaque |
| `especificacion` | TEXT | Especificación del material |
| `fecha_recibo` | DATETIME | Fecha de recepción |
| `fecha_fabricacion` | DATETIME | Fecha de fabricación |
| `ubicacion_salida` | TEXT | Ubicación en almacén |
| `cliente` | TEXT | Cliente (default: LGEMN) |
| `propiedad_material` | TEXT | Propiedad del material |
| `material_importacion_local` | TEXT | Import/Local |
| `forma_material` | TEXT | Formato de material |
| `estado_desecho` | INT | 0=Activo, 1=Desechado |
| `cancelado` | TINYINT | 0=Activo, 1=Cancelado |
| `tiene_salida` | TINYINT | 0=Sin salida, 1=Con salida |
| `iqc_required` | TINYINT | 0=No requiere IQC, 1=Requiere IQC |
| `iqc_status` | VARCHAR(20) | NotRequired, Pending, InProgress, Released, Rejected, Hold, Rework, Scrap, Return |
| `usuario_registro` | VARCHAR(150) | Usuario que registró |
| `fecha_registro` | DATETIME | Timestamp de registro |

---

### control_material_salida (Salidas de Material)

Registro de salidas de material a producción.

| Columna | Tipo | Descripción |
|---------|------|-------------|
| `id` | INT (PK) | ID único |
| `warehousing_id` | INT (FK) | Referencia a entrada |
| `codigo_material_recibido` | VARCHAR(50) | Código de etiqueta |
| `numero_parte` | TEXT | Número de parte |
| `cantidad_salida` | INT | Cantidad entregada |
| `modelo` | TEXT | Modelo de producción |
| `depto_salida` | TEXT | Departamento destino |
| `proceso_salida` | TEXT | Proceso destino |
| `fecha_salida` | DATETIME | Fecha/hora de salida |
| `usuario_registro` | VARCHAR(150) | Usuario que registró |

---

### materiales (Catálogo de Materiales)

Catálogo maestro de materiales con configuración IQC.

| Columna | Tipo | Descripción |
|---------|------|-------------|
| `numero_parte` | VARCHAR (PK) | Número de parte |
| `codigo_material` | TEXT | Código de material |
| `especificacion_material` | TEXT | Especificación |
| `unidad_empaque` | TEXT | Unidad de empaque |
| `ubicacion_material` | TEXT | Ubicación default |
| `iqc_required` | TINYINT | Requiere inspección IQC |
| `rohs_enabled` | TINYINT | Prueba ROHS habilitada |
| `brightness_enabled` | TINYINT | Prueba de brillo habilitada |
| `brightness_sampling_level` | VARCHAR(10) | Nivel de muestreo (S-1, S-2, etc.) |
| `brightness_aql_level` | VARCHAR(10) | Nivel AQL (0.65, 1.0, 2.5, 4.0) |
| `brightness_target` | DECIMAL(10,4) | Valor objetivo de brillo |
| `brightness_lsl` | DECIMAL(10,4) | Límite inferior |
| `brightness_usl` | DECIMAL(10,4) | Límite superior |
| `dimension_enabled` | TINYINT | Prueba dimensional habilitada |
| `dimension_length` | DECIMAL(10,3) | Largo nominal |
| `dimension_length_tol` | DECIMAL(10,3) | Tolerancia de largo |
| `dimension_width` | DECIMAL(10,3) | Ancho nominal |
| `dimension_width_tol` | DECIMAL(10,3) | Tolerancia de ancho |
| `color_enabled` | TINYINT | Prueba de color habilitada |
| `color_spec` | VARCHAR(255) | Especificación de color |
| `appearance_enabled` | TINYINT | Prueba de apariencia habilitada |
| `assign_internal_lot` | TINYINT | Asignar lote interno automático |
| `version` | VARCHAR(50) | Versión del material |

---

### iqc_inspection_lot (Inspecciones IQC)

Lotes de inspección de calidad entrante.

| Columna | Tipo | Descripción |
|---------|------|-------------|
| `id` | INT (PK) | ID único |
| `receiving_lot_code` | VARCHAR(50) | Código de lote de recepción |
| `lot_sequence` | INT | Secuencia de inspección del lote |
| `sample_label_code` | VARCHAR(50) | Código de etiqueta muestreada |
| `sample_label_id` | INT (FK) | Referencia a entrada muestreada |
| `part_number` | VARCHAR(150) | Número de parte |
| `material_code` | TEXT | Código de material |
| `customer` | VARCHAR(150) | Cliente |
| `supplier` | VARCHAR(150) | Proveedor |
| `arrival_date` | DATE | Fecha de llegada |
| `total_qty_received` | INT | Cantidad total recibida |
| `total_labels` | INT | Total de etiquetas del lote |
| `aql_level` | VARCHAR(20) | Nivel AQL |
| `sample_qty` | INT | Tamaño de muestra |
| `qty_sample_ok` | INT | Muestras OK |
| `qty_sample_ng` | INT | Muestras NG |
| `rohs_result` | VARCHAR(20) | OK, NG, NA, Pending |
| `brightness_result` | VARCHAR(20) | OK, NG, NA, Pending |
| `dimension_result` | VARCHAR(20) | OK, NG, NA, Pending |
| `color_result` | VARCHAR(20) | OK, NG, NA, Pending |
| `appearance_result` | VARCHAR(20) | OK, NG, NA, Pending |
| `disposition` | ENUM | Pending, Release, Return, Scrap, Hold, Rework |
| `status` | ENUM | Pending, InProgress, Closed |
| `inspector` | VARCHAR(100) | Nombre del inspector |
| `inspector_id` | INT | ID del inspector |
| `remarks` | TEXT | Observaciones |
| `created_at` | DATETIME | Fecha de creación |
| `closed_at` | DATETIME | Fecha de cierre |

---

### iqc_inspection_detail (Detalle de Mediciones)

Mediciones individuales por muestra.

| Columna | Tipo | Descripción |
|---------|------|-------------|
| `id` | INT (PK) | ID único |
| `inspection_lot_id` | INT (FK) | Referencia a iqc_inspection_lot |
| `sample_number` | INT | Número de muestra (1, 2, 3...) |
| `characteristic` | VARCHAR(20) | dimension, brightness, color, rohs |
| `test_name` | VARCHAR(100) | Nombre de la prueba |
| `measured_value` | VARCHAR(50) | Valor medido |
| `unit` | VARCHAR(20) | Unidad (mm, %, etc.) |
| `min_spec` | VARCHAR(50) | Especificación mínima |
| `max_spec` | VARCHAR(50) | Especificación máxima |
| `result` | ENUM | OK, NG |
| `measured_by` | VARCHAR(100) | Usuario que midió |
| `measured_at` | DATETIME | Fecha de medición |

---

### quarantine (Material en Cuarentena)

Material apartado por problemas de calidad.

| Columna | Tipo | Descripción |
|---------|------|-------------|
| `id` | INT (PK) | ID único |
| `warehousing_id` | INT (FK) | Referencia a entrada |
| `codigo_material_recibido` | VARCHAR(50) | Código de etiqueta |
| `numero_parte` | VARCHAR(150) | Número de parte |
| `numero_lote` | VARCHAR(100) | Lote del material |
| `cantidad` | INT | Cantidad en cuarentena |
| `reason` | TEXT | Motivo de cuarentena |
| `status` | ENUM | Pending, Released, Scrapped, Returned |
| `disposition` | ENUM | Pending, Release, Scrap, Return |
| `created_by` | VARCHAR(100) | Usuario que creó |
| `closed_by` | VARCHAR(100) | Usuario que cerró |
| `created_at` | DATETIME | Fecha de creación |
| `closed_at` | DATETIME | Fecha de cierre |

---

### inventory_audit (Auditorías de Inventario)

Sesiones de auditoría física.

| Columna | Tipo | Descripción |
|---------|------|-------------|
| `id` | INT (PK) | ID único |
| `audit_code` | VARCHAR(30) | Código único de auditoría |
| `status` | ENUM | Pending, InProgress, Completed, Cancelled |
| `total_locations` | INT | Total de ubicaciones a auditar |
| `total_items` | INT | Total de items esperados |
| `verified_locations` | INT | Ubicaciones verificadas |
| `discrepancy_locations` | INT | Ubicaciones con discrepancia |
| `found_items` | INT | Items encontrados |
| `missing_items` | INT | Items faltantes |
| `usuario_inicio` | VARCHAR(100) | Usuario que inició |
| `usuario_fin` | VARCHAR(100) | Usuario que finalizó |
| `fecha_inicio` | DATETIME | Fecha de inicio |
| `fecha_fin` | DATETIME | Fecha de fin |
| `notas` | TEXT | Observaciones |

---

### inventory_audit_location (Ubicaciones por Auditoría)

Ubicaciones incluidas en cada auditoría.

| Columna | Tipo | Descripción |
|---------|------|-------------|
| `id` | INT (PK) | ID único |
| `audit_id` | INT (FK) | Referencia a inventory_audit |
| `location` | VARCHAR(100) | Código de ubicación |
| `status` | ENUM | Pending, InProgress, Verified, Discrepancy |
| `total_items` | INT | Items esperados en ubicación |
| `total_qty` | INT | Cantidad total esperada |
| `started_by` | VARCHAR(100) | Usuario que inició |
| `completed_by` | VARCHAR(100) | Usuario que completó |

---

### inventory_audit_item (Items por Auditoría)

Items individuales a verificar.

| Columna | Tipo | Descripción |
|---------|------|-------------|
| `id` | INT (PK) | ID único |
| `audit_id` | INT (FK) | Referencia a inventory_audit |
| `warehousing_id` | INT (FK) | Referencia a entrada |
| `warehousing_code` | VARCHAR(50) | Código de etiqueta |
| `location` | VARCHAR(100) | Ubicación esperada |
| `status` | ENUM | Pending, Found, Missing, ProcessedOut |
| `scanned_by` | VARCHAR(100) | Usuario que escaneó |
| `scanned_at` | DATETIME | Fecha de escaneo |

---

### cancellation_requests (Solicitudes de Cancelación)

Solicitudes para cancelar entradas de material.

| Columna | Tipo | Descripción |
|---------|------|-------------|
| `id` | INT (PK) | ID único |
| `warehousing_id` | INT (FK) | Referencia a entrada |
| `warehousing_code` | VARCHAR(50) | Código de etiqueta |
| `status` | ENUM | Pending, Approved, Rejected |
| `requested_by` | VARCHAR(100) | Usuario solicitante |
| `requested_at` | DATETIME | Fecha de solicitud |
| `reason` | TEXT | Motivo de cancelación |
| `reviewed_by` | VARCHAR(100) | Usuario revisor |
| `reviewed_at` | DATETIME | Fecha de revisión |
| `review_notes` | TEXT | Notas de revisión |

---

### material_return (Devoluciones de Material)

Devoluciones de material a proveedor.

| Columna | Tipo | Descripción |
|---------|------|-------------|
| `id` | INT (PK) | ID único |
| `warehousing_id` | INT (FK) | Referencia a entrada |
| `material_warehousing_code` | VARCHAR(50) | Código de entrada original |
| `part_number` | VARCHAR(50) | Número de parte |
| `material_lot_no` | VARCHAR(100) | Lote del material |
| `remain_qty` | INT | Cantidad antes de devolver |
| `return_qty` | INT | Cantidad devuelta |
| `loss_qty` | INT | Cantidad de merma |
| `return_datetime` | DATETIME | Fecha de devolución |
| `returned_by` | VARCHAR(100) | Usuario que devolvió |
| `remarks` | TEXT | Observaciones |

---

### lot_division (División de Lotes)

Historial de divisiones de lotes para salidas parciales.

| Columna | Tipo | Descripción |
|---------|------|-------------|
| `id` | INT (PK) | ID único |
| `original_code` | VARCHAR(50) | Código de etiqueta original |
| `original_qty_before` | INT | Cantidad original antes de división |
| `original_qty_after` | INT | Cantidad restante después |
| `new_code` | VARCHAR(50) | Nuevo código generado |
| `new_qty` | INT | Cantidad del nuevo lote |
| `standard_pack` | INT | Empaque estándar usado |
| `outgoing_id` | INT (FK) | Referencia a salida |
| `divided_by` | VARCHAR(100) | Usuario que dividió |
| `created_at` | DATETIME | Fecha de división |

---

### usuarios (Usuarios del Sistema)

Usuarios con acceso al sistema.

| Columna | Tipo | Descripción |
|---------|------|-------------|
| `id` | INT (PK) | ID único |
| `username` | VARCHAR(50) | Nombre de usuario (único) |
| `password` | VARCHAR(255) | Hash de contraseña |
| `email` | VARCHAR(100) | Correo electrónico |
| `nombre_completo` | VARCHAR(150) | Nombre completo |
| `departamento` | VARCHAR(50) | Departamento (define permisos) |
| `cargo` | VARCHAR(50) | Puesto/cargo |
| `activo` | TINYINT | 0=Inactivo, 1=Activo |
| `intentos_fallidos` | INT | Intentos de login fallidos |
| `ultimo_login` | DATETIME | Último acceso |
| `created_at` | DATETIME | Fecha de creación |

---

## Diagrama de Relaciones

```
control_material_almacen (Entradas)
    │
    ├──► control_material_salida (1:N - Salidas)
    │
    ├──► iqc_inspection_lot (1:N - Inspecciones)
    │       │
    │       └──► iqc_inspection_detail (1:N - Mediciones)
    │
    ├──► quarantine (1:N - Cuarentenas)
    │
    ├──► cancellation_requests (1:N - Solicitudes cancelación)
    │
    ├──► material_return (1:N - Devoluciones)
    │
    ├──► lot_division (1:N - Divisiones)
    │
    └──► inventory_audit_item (1:N - Items auditoría)

inventory_audit (Auditorías)
    │
    ├──► inventory_audit_location (1:N)
    │
    └──► inventory_audit_item (1:N)

materiales (Catálogo)
    └──► Referenciado por numero_parte en múltiples tablas
```

---

## Migraciones

Las migraciones se ejecutan automáticamente al iniciar el servidor mediante `backend/utils/dbMigrations.js`. Este archivo:

1. Agrega columnas nuevas si no existen
2. Crea tablas si no existen
3. No elimina datos existentes
4. Es idempotente (puede ejecutarse múltiples veces)

Para forzar una migración manual:
```javascript
const { runMigrations } = require('./utils/dbMigrations');
await runMigrations();
```
