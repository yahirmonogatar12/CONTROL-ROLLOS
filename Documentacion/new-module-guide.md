# Guía para Crear Nuevos Módulos

> **Última actualización:** Enero 2026

## Prompt para Generar un Nuevo Módulo

Usa este prompt como base para solicitar la creación de un nuevo módulo:

```
Crea un nuevo módulo llamado "[NOMBRE_MODULO]" para [DESCRIPCION_FUNCIONALIDAD].

Requisitos:
1. Tabla BD: [nombre_tabla] con columnas: [lista de columnas]
2. Funcionalidades: [CRUD, búsqueda, exportación, etc.]
3. Permisos: [qué departamentos pueden escribir]
4. Mobile: [sí/no - si necesita pantalla móvil]

Sigue la estructura existente del proyecto:
- Screen principal con tabs (Regist/History si aplica)
- Form panel para entrada de datos
- Grid panel para visualización
- Integración con MainTabbedScreen
- Traducciones en los 3 idiomas (en/es/ko)
- Backend modular (controller + routes separados)
```

---

## Checklist de Integración Completo

### 1. Base de Datos

```sql
-- Crear tabla en MySQL
CREATE TABLE IF NOT EXISTS [nombre_tabla] (
  id INT AUTO_INCREMENT PRIMARY KEY,
  -- columnas del módulo
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
);
```

O agregar migración en `backend/utils/dbMigrations.js`:
```javascript
// Agregar tabla
await pool.query(`
  CREATE TABLE IF NOT EXISTS [nombre_tabla] (
    id INT AUTO_INCREMENT PRIMARY KEY,
    campo1 VARCHAR(100),
    campo2 TEXT,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
  )
`);
```

---

### 2. Backend Controller

Crear `backend/controllers/[modulo].controller.js`:

```javascript
const { pool } = require('../config/database');

// GET /api/[modulo] - Lista todos
exports.getAll = async (req, res, next) => {
  try {
    const [rows] = await pool.query('SELECT * FROM [tabla] ORDER BY id DESC');
    res.json(rows);
  } catch (err) {
    next(err);
  }
};

// GET /api/[modulo]/search - Buscar con filtros
exports.search = async (req, res, next) => {
  try {
    const { texto } = req.query;
    const [rows] = await pool.query(
      'SELECT * FROM [tabla] WHERE campo1 LIKE ? ORDER BY id DESC',
      [`%${texto || ''}%`]
    );
    res.json(rows);
  } catch (err) {
    next(err);
  }
};

// GET /api/[modulo]/:id - Obtener por ID
exports.getById = async (req, res, next) => {
  try {
    const { id } = req.params;
    const [rows] = await pool.query('SELECT * FROM [tabla] WHERE id = ?', [id]);
    if (rows.length === 0) {
      return res.status(404).json({ error: 'Registro no encontrado' });
    }
    res.json(rows[0]);
  } catch (err) {
    next(err);
  }
};

// POST /api/[modulo] - Crear nuevo
exports.create = async (req, res, next) => {
  try {
    const { campo1, campo2 } = req.body;
    
    // Validación
    if (!campo1) {
      return res.status(400).json({ error: 'campo1 es requerido' });
    }
    
    const [result] = await pool.query(
      'INSERT INTO [tabla] (campo1, campo2) VALUES (?, ?)',
      [campo1, campo2]
    );
    
    res.status(201).json({ 
      success: true,
      id: result.insertId, 
      message: 'Registro creado' 
    });
  } catch (err) {
    next(err);
  }
};

// PUT /api/[modulo]/:id - Actualizar
exports.update = async (req, res, next) => {
  try {
    const { id } = req.params;
    const { campo1, campo2 } = req.body;
    
    const [result] = await pool.query(
      'UPDATE [tabla] SET campo1 = ?, campo2 = ? WHERE id = ?',
      [campo1, campo2, id]
    );
    
    if (result.affectedRows === 0) {
      return res.status(404).json({ error: 'Registro no encontrado' });
    }
    
    res.json({ success: true, message: 'Registro actualizado' });
  } catch (err) {
    next(err);
  }
};

// DELETE /api/[modulo]/:id - Eliminar
exports.delete = async (req, res, next) => {
  try {
    const { id } = req.params;
    
    const [result] = await pool.query('DELETE FROM [tabla] WHERE id = ?', [id]);
    
    if (result.affectedRows === 0) {
      return res.status(404).json({ error: 'Registro no encontrado' });
    }
    
    res.json({ success: true, message: 'Registro eliminado' });
  } catch (err) {
    next(err);
  }
};
```

---

### 3. Backend Routes

Crear `backend/routes/[modulo].routes.js`:

```javascript
const router = require('express').Router();
const ctrl = require('../controllers/[modulo].controller');

router.get('/', ctrl.getAll);
router.get('/search', ctrl.search);
router.get('/:id', ctrl.getById);
router.post('/', ctrl.create);
router.put('/:id', ctrl.update);
router.delete('/:id', ctrl.delete);

module.exports = router;
```

---

### 4. Registrar Rutas en server.js

```javascript
// IMPORTAR (en la sección de imports)
const [modulo]Routes = require('./routes/[modulo].routes');

// REGISTRAR (en la sección de rutas)
app.use('/api/[modulo]', [modulo]Routes);
```

---

### 5. API Service (Flutter)

Agregar en `lib/core/services/api_service.dart`:

```dart
// ============================================
// [NOMBRE MODULO] ENDPOINTS
// ============================================

static Future<List<Map<String, dynamic>>> get[Modulo]() async {
  try {
    final response = await http.get(Uri.parse('$baseUrl/[modulo]'));
    if (response.statusCode == 200) {
      final List<dynamic> data = json.decode(response.body);
      return data.cast<Map<String, dynamic>>();
    }
    return [];
  } catch (e) {
    print('Error en get[Modulo]: $e');
    return [];
  }
}

static Future<List<Map<String, dynamic>>> search[Modulo](String texto) async {
  try {
    final response = await http.get(
      Uri.parse('$baseUrl/[modulo]/search?texto=${Uri.encodeComponent(texto)}')
    );
    if (response.statusCode == 200) {
      final List<dynamic> data = json.decode(response.body);
      return data.cast<Map<String, dynamic>>();
    }
    return [];
  } catch (e) {
    print('Error en search[Modulo]: $e');
    return [];
  }
}

static Future<Map<String, dynamic>> create[Modulo](Map<String, dynamic> data) async {
  try {
    final response = await http.post(
      Uri.parse('$baseUrl/[modulo]'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode(data),
    );
    return json.decode(response.body);
  } catch (e) {
    print('Error en create[Modulo]: $e');
    return {'success': false, 'error': e.toString()};
  }
}

static Future<Map<String, dynamic>> update[Modulo](int id, Map<String, dynamic> data) async {
  try {
    final response = await http.put(
      Uri.parse('$baseUrl/[modulo]/$id'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode(data),
    );
    return json.decode(response.body);
  } catch (e) {
    print('Error en update[Modulo]: $e');
    return {'success': false, 'error': e.toString()};
  }
}

static Future<Map<String, dynamic>> delete[Modulo](int id) async {
  try {
    final response = await http.delete(Uri.parse('$baseUrl/[modulo]/$id'));
    return json.decode(response.body);
  } catch (e) {
    print('Error en delete[Modulo]: $e');
    return {'success': false, 'error': e.toString()};
  }
}
```

---

### 6. Estructura de Archivos Flutter

Crear carpeta: `lib/screens/[nombre_modulo]/`

```
lib/screens/[nombre_modulo]/
├── [nombre_modulo]_screen.dart      # Screen principal
├── [nombre_modulo]_form_panel.dart  # Formulario de entrada
├── [nombre_modulo]_grid_panel.dart  # Grid de datos
└── [nombre_modulo]_search_bar_panel.dart  # (opcional) Barra de búsqueda
```

---

### 7. Screen Principal Template

```dart
import 'package:flutter/material.dart';
import 'package:material_warehousing_flutter/core/localization/app_translations.dart';
import '[nombre_modulo]_form_panel.dart';
import '[nombre_modulo]_grid_panel.dart';

class [NombreModulo]Screen extends StatefulWidget {
  final LanguageProvider languageProvider;
  
  const [NombreModulo]Screen({super.key, required this.languageProvider});

  @override
  State<[NombreModulo]Screen> createState() => _[NombreModulo]ScreenState();
}

class _[NombreModulo]ScreenState extends State<[NombreModulo]Screen> {
  final GlobalKey<[NombreModulo]GridPanelState> _gridKey = GlobalKey();
  
  String tr(String key) => widget.languageProvider.tr(key);
  
  void _onDataSaved() {
    _gridKey.currentState?.reloadData();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        [NombreModulo]FormPanel(
          languageProvider: widget.languageProvider,
          onDataSaved: _onDataSaved,
        ),
        Expanded(
          child: [NombreModulo]GridPanel(
            key: _gridKey,
            languageProvider: widget.languageProvider,
          ),
        ),
      ],
    );
  }
}
```

---

### 8. Integrar en MainTabbedScreen

Archivo: `lib/screens/main_tabbed_screen.dart`

```dart
// 1. IMPORT
import 'package:material_warehousing_flutter/screens/[nombre_modulo]/[nombre_modulo]_screen.dart';

// 2. TAB (en TopTabBar, agregar tab)
_buildTab(tr('[translation_key]'), [index]),

// 3. SCREEN (en IndexedStack children)
[NombreModulo]Screen(
  key: ValueKey('[modulo]_$currentLocale'),
  languageProvider: widget.languageProvider,
),
```

---

### 9. Traducciones

Agregar en `lib/core/localization/app_translations.dart`:

```dart
// ============================================
// [NOMBRE MODULO] - English
// ============================================
'[modulo]_title': 'Module Title',
'[modulo]_field1': 'Field 1',
'[modulo]_field2': 'Field 2',
'[modulo]_saved': 'Record saved successfully',
'[modulo]_error': 'Error saving record',

// ============================================
// [NOMBRE MODULO] - Español
// ============================================
'[modulo]_title': 'Título del Módulo',
'[modulo]_field1': 'Campo 1',
'[modulo]_field2': 'Campo 2',
'[modulo]_saved': 'Registro guardado exitosamente',
'[modulo]_error': 'Error al guardar registro',

// ============================================
// [NOMBRE MODULO] - 한국어
// ============================================
'[modulo]_title': '모듈 제목',
'[modulo]_field1': '필드 1',
'[modulo]_field2': '필드 2',
'[modulo]_saved': '레코드가 성공적으로 저장되었습니다',
'[modulo]_error': '레코드 저장 오류',
```

---

### 10. Permisos (si aplica)

En `lib/core/services/auth_service.dart`:

```dart
// Lista de departamentos con acceso de escritura
static const List<String> _[modulo]WriteDepartments = [
  'Sistemas', 'Gerencia', 'Administración', '[Departamento]'
];

// Getter de permiso
static bool get canWrite[Modulo] {
  if (_currentUser == null) return false;
  return _[modulo]WriteDepartments.contains(_currentUser!.departamento);
}

static bool get canView[Modulo] => _currentUser != null;
```

---

## Crear Módulo Mobile

### Estructura de Pantalla Mobile

```dart
// lib/screens/mobile/mobile_[modulo]_screen.dart
import 'package:flutter/material.dart';
import 'package:material_warehousing_flutter/core/localization/app_translations.dart';
import 'package:material_warehousing_flutter/core/services/api_service.dart';
import 'package:material_warehousing_flutter/core/services/feedback_service.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class Mobile[Modulo]Screen extends StatefulWidget {
  final LanguageProvider languageProvider;
  
  const Mobile[Modulo]Screen({super.key, required this.languageProvider});

  @override
  State<Mobile[Modulo]Screen> createState() => _Mobile[Modulo]ScreenState();
}

class _Mobile[Modulo]ScreenState extends State<Mobile[Modulo]Screen> {
  final TextEditingController _scanController = TextEditingController();
  bool _isProcessing = false;
  
  String tr(String key) => widget.languageProvider.tr(key);

  Future<void> _onScan(String code) async {
    if (_isProcessing) return;
    
    setState(() => _isProcessing = true);
    
    // Feedback sonoro
    await FeedbackService.playSuccess();
    
    // Procesar código...
    final result = await ApiService.process[Modulo]Scan(code);
    
    if (result['success'] == true) {
      FeedbackService.vibrate();
      // Mostrar resultado...
    } else {
      FeedbackService.playError();
      // Mostrar error...
    }
    
    setState(() => _isProcessing = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('[modulo]_title'))),
      body: Column(
        children: [
          // Campo de escaneo manual
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _scanController,
              decoration: InputDecoration(
                labelText: tr('scan_code'),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.send),
                  onPressed: () => _onScan(_scanController.text),
                ),
              ),
              onSubmitted: _onScan,
            ),
          ),
          // Vista de cámara
          Expanded(
            child: MobileScanner(
              onDetect: (capture) {
                final barcodes = capture.barcodes;
                if (barcodes.isNotEmpty && barcodes.first.rawValue != null) {
                  _onScan(barcodes.first.rawValue!);
                }
              },
            ),
          ),
        ],
      ),
    );
  }
}
```

### Integrar en MobileHomeScaffold

```dart
// En mobile_home_scaffold.dart
// 1. Agregar a la lista de pantallas
// 2. Agregar ícono en bottom navigation
BottomNavigationBarItem(
  icon: Icon(Icons.[icono]),
  label: tr('[modulo]_title'),
),
```

---

## Widgets Reutilizables

```dart
// Decoración estándar para campos
import 'package:material_warehousing_flutter/core/widgets/field_decoration.dart';
TextField(decoration: fieldDecoration(hintText: 'Placeholder...'))

// Campo con etiqueta
import 'package:material_warehousing_flutter/core/widgets/labeled_field.dart';
LabeledField(label: 'Nombre', child: TextField(...))

// Dropdown con tabla de búsqueda
import 'package:material_warehousing_flutter/core/widgets/table_dropdown_field.dart';
TableDropdownField(
  headers: ['Code', 'Name'],
  rows: [['001', 'Item 1'], ['002', 'Item 2']],
  onRowSelected: (index) => print('Selected: $index'),
)

// Footer de grid con totales
import 'package:material_warehousing_flutter/core/widgets/grid_footer.dart';
GridFooter(totalRows: _data.length, languageProvider: widget.languageProvider)
```

---

## Notas Importantes

1. **Orden de implementación**: 
   BD → Controller → Routes → Register in server.js → ApiService → Flutter screens → MainTabbedScreen → Traducciones

2. **Consistencia de nombres**:
   - Tabla BD: `snake_case` plural (`proveedores`)
   - Controller: `kebab-case.controller.js` (`proveedor.controller.js`)
   - Routes: `kebab-case.routes.js` (`proveedor.routes.js`)
   - Endpoint: `/api/kebab-case` (`/api/proveedores`)
   - Clase Dart: `PascalCase` (`SupplierManagementScreen`)
   - Archivo Dart: `snake_case.dart` (`supplier_management_screen.dart`)

3. **GlobalKey para comunicación**:
   ```dart
   final GlobalKey<[Modulo]GridPanelState> _gridKey = GlobalKey();
   ```

4. **Mantener estado con tabs**: Usar `AutomaticKeepAliveClientMixin` en grids.

5. **Mobile**: Usar `FeedbackService` para audio/vibración en operaciones.
