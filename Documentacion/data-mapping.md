# Mapeo de Datos: Base de Datos ↔ Flutter

> **Última actualización:** Enero 2026

## control_material_almacen (Entradas de Material)

### Mapeo de Columnas a UI

| Campo UI (Flutter)           | Columna BD                      | Tipo BD        | Controller/Variable Flutter        |
|-----------------------------|---------------------------------|----------------|-----------------------------------|
| Material Warehousing Code   | `codigo_material_recibido`      | TEXT           | `_warehousingCodeController`      |
| Material Code               | `codigo_material`               | TEXT           | `_materialCodeController`         |
| Material Original Code      | `codigo_material_original`      | TEXT           | `_materialOriginalCodeController` |
| Part Number                 | `numero_parte`                  | TEXT           | `_partNumberController`           |
| Material Lot No             | `numero_lote_material`          | TEXT           | `_materialLotNoController`        |
| Material Spec               | `especificacion`                | TEXT           | `_materialSpecController`         |
| Current Qty                 | `cantidad_actual`               | INT            | `_currentQtyController`           |
| Packaging Unit              | `cantidad_estandarizada`        | TEXT           | `_packagingUnitController`        |
| Location                    | `ubicacion_salida`              | TEXT           | `_locationController`             |
| Warehousing Date            | `fecha_recibo`                  | DATETIME       | `_warehousingDateController`      |
| Making Date                 | `fecha_fabricacion`             | DATETIME       | `_makingDateController`           |
| Material Format             | `forma_material`                | TEXT           | Hardcoded: `'OriginCode'`         |
| Customer                    | `cliente`                       | TEXT           | Hardcoded: `'LGEMN'`              |
| Material Consigned          | `material_importacion_local`    | TEXT           | `_selectedMaterialConsigned`      |
| Material Property           | `propiedad_material`            | TEXT           | Hardcoded: `'Customer Supply'`    |
| Disposal                    | `estado_desecho`                | INT (0/1)      | Checkbox o default `0`            |
| Cancelled                   | `cancelado`                     | TINYINT (0/1)  | `_isCancelled` bool               |
| IQC Required                | `iqc_required`                  | TINYINT (0/1)  | `_iqcRequired` bool               |
| IQC Status                  | `iqc_status`                    | ENUM           | Badge widget (read-only)          |

### Columnas Calculadas (no editables directamente)

| Columna BD              | Cálculo                                                    |
|------------------------|------------------------------------------------------------|
| `receiving_lot_code`   | Primeros 20 caracteres de `codigo_material_recibido`       |
| `label_seq`            | Últimos 4 dígitos de `codigo_material_recibido` como INT   |
| `fecha_registro`       | `NOW()` al insertar                                        |

### Formato de codigo_material_recibido
```
EAE66213501-202511270006
├─────────────────────┤├──┤
   receiving_lot_code   seq
      (20 chars)       (4 digits)
```

## materiales (Catálogo de Materiales)

| Campo UI                | Columna BD                  | Uso                              |
|------------------------|-----------------------------|----------------------------------|
| Part Number            | `numero_parte`              | PK, búsqueda en dropdown         |
| Material Code          | `codigo_material`           | Autocompletar al escanear        |
| Material Spec          | `especificacion_material`   | Mostrar en formulario            |
| Packaging Unit         | `unidad_empaque`            | Mostrar en formulario            |
| Location               | `ubicacion_material`        | JOIN para mostrar en grid        |
| IQC Required           | `iqc_required`              | Determina si crear inspección    |

## iqc_inspection_lot (Inspecciones IQC)

| Campo UI               | Columna BD              | Tipo                              |
|-----------------------|-------------------------|-----------------------------------|
| Receiving Lot         | `receiving_lot_code`    | VARCHAR(25) - FK a warehousing    |
| Sample Label          | `sample_label_code`     | VARCHAR(30)                       |
| Part Number           | `part_number`           | VARCHAR(50)                       |
| Customer              | `customer`              | VARCHAR(100)                      |
| Arrival Date          | `arrival_date`          | DATE                              |
| Total Qty             | `total_qty_received`    | INT                               |
| Total Labels          | `total_labels`          | INT                               |
| Sample Size           | `sample_qty`            | INT                               |
| ROHS Result           | `rohs_result`           | ENUM (OK/NG/NA/Pending)           |
| Brightness Result     | `brightness_result`     | ENUM                              |
| Dimension Result      | `dimension_result`      | ENUM                              |
| Color Result          | `color_result`          | ENUM                              |
| Disposition           | `disposition`           | ENUM (Pending/Release/Return/etc) |
| Status                | `status`                | ENUM (Pending/InProgress/Closed)  |
| Inspector             | `inspector`             | VARCHAR(100)                      |
| Comments              | `remarks`               | TEXT                              |

## Grid Panel: fieldMapping Array

El grid usa un array `fieldMapping` para mapear columnas BD a posiciones del grid:

```dart
final fieldMapping = [
  'codigo_material_recibido',    // [0] Material Warehousing Code
  'codigo_material',              // [1] Material Code
  'numero_parte',                 // [2] Part Number
  'numero_lote_material',         // [3] Material Lot No
  'iqc_status',                   // [4] IQC Status
  'propiedad_material',           // [5] Material Property
  'cantidad_actual',              // [6] Current Qty
  'cantidad_estandarizada',       // [7] Packaging Unit
  'location',                     // [8] Location (JOIN)
  'fecha_recibo',                 // [9] Warehousing Date
  'especificacion',               // [10] Material Spec
  'material_importacion_local',   // [11] Material Consigned
  'estado_desecho',               // [12] Disposal
  'cancelado',                    // [13] Cancelled
];
```

## Conversiones de Formato

### Fechas
- BD → Flutter: `DateTime.parse(row['fecha_recibo'])` → `dd/MM/yyyy`
- Flutter → BD: `dd/MM/yyyy` → `yyyy-MM-dd` (split y reverse)

### Booleanos
- BD: TINYINT `0` o `1`
- Flutter: `bool` con conversión `value == 1 || value == '1' || value == true`

### IQC Status (Enum)
```dart
// Valores posibles en BD
'NotRequired' | 'Pending' | 'InProgress' | 'Released' | 'Rejected' | 'Hold' | 'Rework' | 'Scrap' | 'Return'

// Colores en UI
NotRequired → Grey
Pending     → Orange
InProgress  → Blue
Released    → Green
Rejected    → Red
Hold        → Purple
Rework      → Amber
Scrap       → Dark Red
Return      → Deep Orange
```
