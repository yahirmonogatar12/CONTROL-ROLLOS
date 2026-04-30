# Plan - Auditoria Inventario v2

## Objetivo

Redisenar la auditoria para que:
- Muestre por ubicacion el resumen por numero_parte.
- Permita confirmar OK sin escanear.
- Si hay discrepancia, obligue a escanear todas las etiquetas de esa parte.
- No genere salidas hasta confirmar faltantes.
- Aplique el mismo flujo en PC y Movil (PC confirma, Movil escanea).

---

## Nuevo flujo funcional

### PC (Supervisor)

1) Iniciar auditoria.
2) Ver por ubicacion: numero_parte + cantidad_total + conteo_etiquetas.
3) Por cada parte:
   - OK -> status Ok.
   - No coincide -> status Mismatch, habilita escaneo en Movil.
4) Tras escaneo movil, si faltan etiquetas, supervisor confirma faltantes.
5) Cerrar auditoria solo si todas las partes estan confirmadas.

### Movil (Operador)

1) Escanear ubicacion.
2) Ver resumen por numero_parte y cantidades esperadas.
3) Si parte esta en Mismatch, escanear todas las etiquetas de esa parte.
4) Se valida presencia por codigo_material_recibido.

---

## Reglas clave

- Cantidad_total = SUM(cantidad_actual).
- Conteo_etiquetas = COUNT(*).
- Salidas solo despues de confirmacion explicita (no automatico al cerrar).

---

## Modelo de datos

### Tabla nueva: inventory_audit_part

Campos sugeridos:
- id (PK)
- audit_id (FK)
- location
- numero_parte
- expected_items (COUNT de etiquetas)
- expected_qty (SUM cantidad_actual)
- status ENUM('Pending','Ok','Mismatch','VerifiedByScan','MissingConfirmed')
- confirmed_by, confirmed_at
- scanned_items, scanned_qty
- missing_items, missing_qty (opcional)

Indices:
- UNIQUE(audit_id, location, numero_parte)
- idx_audit_id, idx_location, idx_status

### Tablas existentes

- inventory_audit (sin cambio)
- inventory_audit_location (status derivado por partes)
- inventory_audit_item (solo escaneo granular; se usa cuando hay mismatch)

---

## Backend: endpoints

### Gestion (PC)

- POST /api/audit/start
  - Genera inventory_audit_part agrupando por ubicacion + numero_parte.
- GET /api/audit/locations
  - Devuelve ubicaciones y estado agregado por partes.
- GET /api/audit/location-summary
  - Devuelve lista de partes por ubicacion con expected_items/qty + status.
- POST /api/audit/confirm-part
  - Marca Ok (sin escaneo).
- POST /api/audit/flag-mismatch
  - Marca Mismatch y habilita escaneo.
- POST /api/audit/confirm-missing
  - Confirma faltantes y genera salidas solo para esa parte.

### Movil

- POST /api/audit/scan-location
  - Devuelve resumen por parte en esa ubicacion.
- POST /api/audit/scan-part-item
  - Escaneo por codigo_material_recibido.
  - Solo permitido si la parte esta en Mismatch.

### Cierre

- POST /api/audit/end
  - Solo permite cerrar si todas las partes estan Ok/VerifiedByScan/MissingConfirmed.
  - No crea salidas automaticamente.

---

## Logica de salidas

- Generadas solo cuando el supervisor confirma faltantes en PC.
- Inserta control_material_salida y marca control_material_almacen con salida/desecho.

---

## Cambios en UI

### PC (inventory_audit_screen.dart)

- Sustituir lista de etiquetas por resumen por parte.
- Acciones: OK / No coincide.
- Ver progreso por parte (expected vs scanned).
- Boton Confirmar faltantes cuando aplique.

### Movil (mobile_audit_screen.dart)

- Al escanear ubicacion, mostrar resumen por parte.
- Al marcar Mismatch, cambiar a modo escaneo por parte.
- Mostrar progreso (scanned vs expected).

---

## Cliente API (api_service.dart)

Nuevos metodos:
- getAuditLocationSummary
- confirmAuditPart
- flagAuditMismatch
- scanAuditPartItem
- confirmAuditMissing

---

## Migracion

- Crear tabla inventory_audit_part en dbMigrations.js.
- Actualizar database-schema.md e inventory-audit.md.
- Actualizar traducciones en app_translations.dart.

---

## Pruebas recomendadas

- Inicio auditoria con multiples ubicaciones/partes.
- Confirmar OK sin escaneo.
- Marcar Mismatch -> escaneo completo -> confirmar faltantes.
- Intentar cerrar con partes Pending/Mismatch (debe fallar).
- Verificar que salidas solo se crean tras confirmacion.
