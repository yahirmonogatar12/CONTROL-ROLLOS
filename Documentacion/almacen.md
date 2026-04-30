---
inclusion: always
---
# Módulo Almacén - Guía de Operaciones

> **Última actualización:** Enero 2026

Este documento describe las reglas de negocio, flujos de trabajo y convenciones específicas del módulo de Almacén (Warehousing).

---

## Flujo de Entrada de Material (Warehousing)

### Proceso de Registro

1. **Escaneo de Código** → El operador escanea el código de barras del material
2. **Búsqueda Automática** → Sistema busca en catálogo `materiales` por `numero_parte`
3. **Autocompletado** → Se llenan automáticamente: Material Code, Spec, Packaging Unit, Location
4. **Validación IQC** → Si `iqc_required = 1` en catálogo, se marca para inspección
5. **Generación de Código** → Se genera `codigo_material_recibido` único
6. **Impresión de Etiqueta** → Se imprime etiqueta ZPL con código de barras

### Formato del Código de Material Recibido

```
EAE66213501-202511270006
├─────────────────────┤├──┤
   receiving_lot_code   seq
      (20 chars)       (4 digits)
```

- `receiving_lot_code`: Agrupa etiquetas del mismo lote de recepción
- `label_seq`: Secuencia incremental (0001, 0002, etc.)

---

## Reglas de Negocio

### Validaciones de Entrada

| Campo | Validación | Mensaje de Error |
|-------|------------|------------------|
| `numero_parte` | Requerido, debe existir en catálogo | "Part number not found" |
| `cantidad_actual` | Requerido, > 0 | "Quantity must be greater than 0" |
| `numero_lote_material` | Requerido | "Supplier lot is required" |
| `fecha_recibo` | Requerido, no futuro | "Invalid date" |

### Estados IQC

| Estado | Descripción | Color Badge | Permite Salida |
|--------|-------------|-------------|----------------|
| `NotRequired` | No requiere inspección | Gris | ✅ Sí |
| `Pending` | Pendiente de inspección | Naranja | ❌ No |
| `InProgress` | Inspección en curso | Azul | ❌ No |
| `Released` | Liberado por calidad | Verde | ✅ Sí |
| `Rejected` | Rechazado | Rojo | ❌ No |
| `Hold` | En espera | Púrpura | ❌ No |
| `Rework` | Requiere retrabajo | Ámbar | ❌ No |
| `Scrap` | Para desecho | Rojo oscuro | ❌ No |
| `Return` | Devolución a proveedor | Naranja oscuro | ❌ No |

### FIFO (First In, First Out)

- Las salidas deben priorizar material más antiguo
- El sistema ordena por `fecha_recibo` ascendente
- Alertas para material con más de 90 días en almacén

---

## Estructura de Pantalla

### Componentes del Módulo Warehousing

```
lib/screens/material_warehousing/
├── warehousing_screen.dart           # Contenedor principal con tabs
├── warehousing_form_panel.dart       # Formulario de entrada
├── warehousing_grid_panel.dart       # Grid de registros
├── warehousing_search_bar_panel.dart # Barra de búsqueda por fecha
└── warehousing_edit_dialog.dart      # Diálogo de edición
```

### Tabs del Módulo

1. **Regist** - Formulario de nueva entrada
2. **History** - Grid con historial de entradas

---

## Grid Panel - Características

### Columnas Estándar

| Columna | Campo BD | Flex | Características |
|---------|----------|------|-----------------|
| Part Number | `numero_parte` | 3.0 | Texto |
| Material Spec | `especificacion` | 4.0 | Texto |
| Warehousing Code | `codigo_material_recibido` | 4.0 | Texto, único |
| Supplier Lot | `numero_lote_material` | 3.0 | Texto |
| IQC Status | `iqc_status` | 2.0 | Badge con color |
| Quarantine | `in_quarantine` | 2.0 | Badge naranja si true |
| Current Qty | `cantidad_actual` | 2.0 | Numérico |
| Packaging Unit | `cantidad_estandarizada` | 2.0 | Texto |
| Location | `location` | 2.0 | Texto |
| Warehousing Date | `fecha_recibo` | 3.0 | Fecha + hora |
| Vendor | `vendedor` | 3.0 | Texto |
| Cancelled | `cancelado` | 2.0 | Sí/No (rojo si Sí) |
| Registered By | `usuario_registro` | 2.0 | Texto |

### Funcionalidades del Grid

- **Multi-selección** con checkboxes
- **Ordenamiento** por cualquier columna (click en header)
- **Filtros** por columna (dropdown con valores únicos)
- **Búsqueda** Ctrl+F con highlight de texto
- **Redimensionar columnas** arrastrando separadores
- **Persistencia** de anchos de columna en SharedPreferences

---

## API Endpoints

### Warehousing

| Método | Endpoint | Descripción |
|--------|----------|-------------|
| GET | `/api/warehousing` | Lista todas las entradas |
| GET | `/api/warehousing/search` | Buscar con filtros |
| GET | `/api/warehousing/by-code/:code` | Buscar por código |
| GET | `/api/warehousing/:id` | Obtener por ID |
| POST | `/api/warehousing` | Crear nueva entrada |
| PUT | `/api/warehousing/:id` | Actualizar entrada |
| DELETE | `/api/warehousing/:id` | Eliminar entrada |

### Parámetros de Búsqueda

```
GET /api/warehousing/search?
  fechaInicio=2026-01-01&
  fechaFin=2026-01-12&
  texto=EAE66213501&
  iqcStatus=Pending
```

---

## Permisos

### Departamentos con Acceso de Escritura

```dart
static const List<String> _warehousingWriteDepartments = [
  'Sistemas',
  'Gerencia', 
  'Administración',
  'Almacén',
  'Almacén Supervisor'
];
```

### Verificación en UI

```dart
final canWrite = AuthService.canWriteWarehousing;

// Deshabilitar botón si no tiene permiso
ElevatedButton(
  onPressed: canWrite ? _save : null,
  child: Text(tr('save')),
),
```

---

## Impresión de Etiquetas

### Formato ZPL

```zpl
^XA
^FO50,50^BY3
^BCN,100,Y,N,N
^FD{codigo_material_recibido}^FS
^FO50,180^A0N,30,30^FD{numero_parte}^FS
^FO50,220^A0N,25,25^FD{especificacion}^FS
^FO50,260^A0N,25,25^FDQTY: {cantidad_actual}^FS
^FO50,300^A0N,25,25^FDLOT: {numero_lote_material}^FS
^XZ
```

### Configuración de Impresora

- Puerto: 9100 (TCP/IP)
- Impresoras Zebra compatibles
- Configuración en `PrinterService`

---

## Traducciones Clave

```dart
// Títulos
'material_warehousing': 'Material Warehousing' / 'Entrada de Material' / '자재 입고',
'warehousing_date': 'Warehousing Date' / 'Fecha de Entrada' / '입고 날짜',

// Campos
'part_number': 'Part Number' / 'Número de Parte' / '부품 번호',
'material_code': 'Material Code' / 'Código de Material' / '자재 코드',
'material_lot_no': 'Material Lot No' / 'Lote del Material' / '자재 로트 번호',
'current_qty': 'Current Qty' / 'Cantidad Actual' / '현재 수량',
'packaging_unit': 'Packaging Unit' / 'Unidad de Empaque' / '포장 단위',

// Estados IQC
'pending': 'Pending' / 'Pendiente' / '대기중',
'released': 'Released' / 'Liberado' / '출고됨',
'rejected': 'Rejected' / 'Rechazado' / '거부됨',

// Acciones
'save': 'Save' / 'Guardar' / '저장',
'print_label': 'Print Label' / 'Imprimir Etiqueta' / '라벨 인쇄',
```

---

## Buenas Prácticas

### Al Crear Nuevas Entradas

1. Siempre validar que el `numero_parte` existe en catálogo
2. Verificar que no exista duplicado de `codigo_material_recibido`
3. Asignar `iqc_status` basado en configuración del material
4. Registrar `usuario_registro` del usuario actual
5. Usar transacción si se crean múltiples etiquetas

### Al Modificar el Grid

1. Usar `AutomaticKeepAliveClientMixin` para mantener estado
2. Implementar `reloadData()` público para refrescar desde parent
3. Guardar preferencias de columnas en `SharedPreferences`
4. Usar `GlobalKey` para comunicación parent-child

### Al Agregar Nuevas Columnas

1. Agregar al array `headers` (traducido)
2. Agregar al array `fieldMapping` (campo BD)
3. Agregar flex factor en `_columnFlexFactors`
4. Actualizar `_columnWidthsKey` si cambia número de columnas
5. Agregar formateo especial si es necesario (fechas, badges)

---

## Integración con Otros Módulos

### → IQC Inspection

- Cuando `iqc_required = 1`, se crea `iqc_inspection_lot` automáticamente
- El `iqc_status` se actualiza desde el módulo IQC
- Material no puede salir hasta que `iqc_status = Released`

### → Material Outgoing

- Valida `iqc_status` antes de permitir salida
- Actualiza `cantidad_actual` al registrar salida
- Marca `tiene_salida = 1` cuando cantidad llega a 0

### → Quarantine

- Material con `in_quarantine = 1` no puede salir
- Se muestra badge naranja en grid
- Requiere liberación desde módulo Quarantine

### → Inventory Audit

- Entradas activas se incluyen en auditorías
- Se verifica `ubicacion_salida` vs ubicación física
- Discrepancias se registran en `inventory_audit_item`
