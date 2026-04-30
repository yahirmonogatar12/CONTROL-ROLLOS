# Plan de Implementación: Mejora del Modo de Auditoría en Android

## Objetivo

Modificar el flujo de auditoría para que en Android:
1. Se pueda ver ubicaciones escaneando o escribiendo (como ya existe)
2. En lugar de escanear todos los materiales, aparezcan las **cantidades por número de parte**
3. Los operadores **confirmen** las cantidades
4. Si **no hay coincidencia**, entonces sí escanear todos los materiales para verificar cuál falta

---

## User Review Required

> [!IMPORTANT]
> Este cambio modifica el flujo de auditoría existente. Las auditorías activas deberán completarse con el flujo anterior antes de activar este cambio.

---

## Propuestos Cambios

### Base de Datos

#### [NEW] Tabla `inventory_audit_part`

- [x] Implementado en `backend/utils/dbMigrations.js`

Campos:
| Campo | Tipo | Descripción |
|-------|------|-------------|
| [id](file:///c:/Users/yahir/OneDrive/Escritorio/MES/Control_de_material_de_almacen/lib/core/services/api_service.dart#616-630) | INT PK | Identificador único |
| `audit_id` | INT FK | Referencia a `inventory_audit` |
| `location` | VARCHAR(100) | Ubicación del rack |
| `numero_parte` | VARCHAR(100) | Número de parte |
| `expected_items` | INT | Cantidad de etiquetas esperadas |
| `expected_qty` | DECIMAL | Suma de cantidad_actual |
| `status` | ENUM | `'Pending', 'Ok', 'Mismatch', 'VerifiedByScan', 'MissingConfirmed'` |
| `confirmed_by` | VARCHAR | Usuario que confirmó |
| `confirmed_at` | DATETIME | Fecha de confirmación |
| `scanned_items` | INT | Etiquetas escaneadas (solo si Mismatch) |
| `scanned_qty` | DECIMAL | Cantidad escaneada |

---

### Backend

#### [MODIFY] [audit.controller.js](file:///c:/Users/yahir/OneDrive/Escritorio/MES/Control_de_material_de_almacen/backend/controllers/audit.controller.js)

1. [x] **Modificar [startAudit](file:///c:/Users/yahir/OneDrive/Escritorio/MES/Control_de_material_de_almacen/lib/core/services/api_service.dart#2172-2193)**: Además de crear `inventory_audit_location`, generar registros en `inventory_audit_part` agrupando por `ubicacion_salida + numero_parte`:
   ```sql
   SELECT ubicacion_salida, numero_parte, COUNT(*) as expected_items, SUM(cantidad_actual) as expected_qty
   FROM control_material_almacen
   WHERE cantidad_actual > 0 AND ...
   GROUP BY ubicacion_salida, numero_parte
   ```

2. [x] **Nuevo endpoint `getLocationSummary`**: Devuelve resumen por parte para una ubicación:
   ```javascript
   // GET /api/audit/location-summary?location=RACK-A1
   // Retorna: [{numero_parte, expected_items, expected_qty, status, scanned_items}]
   ```

3. [x] **Nuevo endpoint `confirmPart`**: Marcar una parte como OK sin escaneo:
   ```javascript
   // POST /api/audit/confirm-part
   // Body: {audit_id, location, numero_parte, confirmed_by}
   // Acción: status = 'Ok', confirmed_at = NOW()
   ```

4. [x] **Nuevo endpoint `flagMismatch`**: Marcar discrepancia y habilitar escaneo:
   ```javascript
   // POST /api/audit/flag-mismatch
   // Body: {audit_id, location, numero_parte, flagged_by}
   // Acción: status = 'Mismatch'
   ```

5. [x] **Nuevo endpoint `scanPartItem`**: Escanear etiqueta individual (solo si parte en Mismatch):
   ```javascript
   // POST /api/audit/scan-part-item
   // Body: {audit_id, location, numero_parte, warehousing_code, scanned_by}
   // Valida: parte debe estar en Mismatch
   // Acción: crear inventory_audit_item + incrementar scanned_items en inventory_audit_part
   ```

6. [x] **Nuevo endpoint `confirmMissing`**: Confirmar faltantes y generar salidas:
   ```javascript
   // POST /api/audit/confirm-missing
   // Body: {audit_id, location, numero_parte, confirmed_by}
   // Acción: items Pending -> Missing, status -> 'MissingConfirmed'
   ```

---

#### [MODIFY] [audit.routes.js](file:///c:/Users/yahir/OneDrive/Escritorio/MES/Control_de_material_de_almacen/backend/routes/audit.routes.js)

Agregar nuevas rutas:
- [x] Rutas agregadas en `backend/routes/audit.routes.js`.
```javascript
// Nuevos endpoints para flujo por parte
router.get('/location-summary', controller.getLocationSummary);
router.post('/confirm-part', controller.confirmPart);
router.post('/flag-mismatch', controller.flagMismatch);
router.post('/scan-part-item', controller.scanPartItem);
router.post('/confirm-missing', controller.confirmMissing);
```

---

### Frontend (Flutter)

#### [MODIFY] [api_service.dart](file:///c:/Users/yahir/OneDrive/Escritorio/MES/Control_de_material_de_almacen/lib/core/services/api_service.dart)

Agregar métodos:
- [x] Métodos agregados en `api_service.dart`.
```dart
static Future<Map<String, dynamic>> getAuditLocationSummary(String location) async {...}
static Future<Map<String, dynamic>> confirmAuditPart({...}) async {...}
static Future<Map<String, dynamic>> flagAuditMismatch({...}) async {...}
static Future<Map<String, dynamic>> scanAuditPartItem({...}) async {...}
static Future<Map<String, dynamic>> confirmAuditMissing({...}) async {...}
```

---

#### [MODIFY] [mobile_audit_screen.dart](file:///c:/Users/yahir/OneDrive/Escritorio/MES/Control_de_material_de_almacen/lib/screens/mobile/mobile_audit_screen.dart)

**Nuevo flujo de pantalla:**

```
┌─────────────────────────────────────────────┐
│  📍 Escanear Ubicación                       │
│  ┌───────────────────────────────────────┐  │
│  │ [Input: Escanear o escribir ubicación]│  │
│  └───────────────────────────────────────┘  │
└─────────────────────────────────────────────┘
                    ▼
┌─────────────────────────────────────────────┐
│  📦 Resumen por Número de Parte              │
│  ┌───────────────────────────────────────┐  │
│  │ P/N: ABC-123-XY                       │  │
│  │ Etiquetas: 5    Cantidad: 500 pzs     │  │
│  │ [✓ CONFIRMAR OK]  [✗ NO COINCIDE]     │  │
│  └───────────────────────────────────────┘  │
│  ┌───────────────────────────────────────┐  │
│  │ P/N: DEF-456-ZZ                       │  │
│  │ Etiquetas: 3    Cantidad: 300 pzs     │  │
│  │ [✓ CONFIRMAR OK]  [✗ NO COINCIDE]     │  │
│  └───────────────────────────────────────┘  │
└─────────────────────────────────────────────┘
                    ▼ (si hay mismatch)
┌─────────────────────────────────────────────┐
│  🔍 Escanear Etiquetas de: ABC-123-XY        │
│  Progreso: 3/5 escaneadas                    │
│  ┌───────────────────────────────────────┐  │
│  │ [Input: Escanear etiqueta]            │  │
│  └───────────────────────────────────────┘  │
│  ┌───────────────────────────────────────┐  │
│  │ ✓ WHI-2024-001 | 100 pzs              │  │
│  │ ✓ WHI-2024-002 | 100 pzs              │  │
│  │ ✓ WHI-2024-003 | 100 pzs              │  │
│  │ ○ WHI-2024-004 | 100 pzs (pendiente)  │  │
│  │ ○ WHI-2024-005 | 100 pzs (pendiente)  │  │
│  └───────────────────────────────────────┘  │
│  [CONFIRMAR FALTANTES] (si hay pendientes)  │
└─────────────────────────────────────────────┘
```

**Cambios en el código:**

1. [x] Nuevo estado `_scanMode`:
   - `'location'`: Escanear ubicación
   - `'summary'`: Ver resumen por parte (NUEVO)
   - `'mismatch_scan'`: Escanear etiquetas de parte específica (NUEVO)

2. [x] Nueva variable `_partSummary`: Lista de partes con sus cantidades

3. [x] Nueva variable `_selectedPartForScan`: Parte seleccionada para escaneo detallado

4. [x] Métodos nuevos:
   - `_loadLocationSummary()`: Cargar resumen por parte
   - `_confirmPart(partNumber)`: Confirmar OK
   - `_flagMismatch(partNumber)`: Marcar discrepancia
   - `_scanPartItem(code)`: Escanear etiqueta individual
   - `_confirmMissing()`: Confirmar faltantes

---

#### [MODIFY] [app_translations.dart](file:///c:/Users/yahir/OneDrive/Escritorio/MES/Control_de_material_de_almacen/lib/core/localization/app_translations.dart)

Agregar traducciones:
- [x] Traducciones agregadas (en/es/ko).
```dart
'audit_summary_by_part': 'Resumen por Número de Parte',
'audit_expected_labels': 'Etiquetas esperadas',
'audit_expected_qty': 'Cantidad esperada',
'audit_confirm_ok': 'Confirmar OK',
'audit_flag_mismatch': 'No Coincide',
'audit_scan_labels': 'Escanear etiquetas de',
'audit_scanned_of': 'escaneadas de',
'audit_confirm_missing': 'Confirmar Faltantes',
'audit_part_confirmed': 'Parte confirmada',
'audit_mismatch_flagged': 'Discrepancia marcada - Escanee las etiquetas',
'audit_scan_all_or_confirm': 'Escanee todas las etiquetas o confirme faltantes',
```

---

## Verificación

### Pruebas Manuales

1. [ ] **Flujo feliz**: 
   - Escanear ubicación → Ver resumen → Confirmar OK en todas las partes → Ubicación completada

2. [ ] **Flujo con discrepancia**:
   - Escanear ubicación → Ver resumen → Marcar "No coincide" en una parte → Escanear etiquetas individualmente → Confirmar faltantes

3. [ ] **Validaciones**:
   - Solo se puede escanear etiquetas si la parte está en Mismatch
   - No se puede cerrar ubicación con partes Pending

### Migración de Datos

- [ ] Crear tabla `inventory_audit_part` sin afectar auditorías existentes
- [ ] Las auditorías nuevas usarán el nuevo flujo automáticamente



