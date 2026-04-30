# Guía de Implementación de Tablas/Grids

> **Última actualización:** Enero 2026

## Resumen

Este documento describe cómo crear tablas/grids con el mismo estilo y funcionalidad que las existentes en el proyecto MES Control de Material.

---

## 📁 Estructura de Archivos

```
lib/
├── core/
│   ├── theme/
│   │   └── app_colors.dart          # Colores del tema
│   ├── widgets/
│   │   └── grid_footer.dart         # Widget reutilizable para footer
│   ├── localization/
│   │   └── app_translations.dart    # Traducciones (EN, ES, KO)
│   └── services/
│       └── api_service.dart         # Servicios de API
└── screens/
    └── [modulo]/
        └── [modulo]_grid_panel.dart # Tu nuevo grid
```

---

## 🎨 Colores del Sistema (AppColors)

```dart
import 'package:material_warehousing_flutter/core/theme/app_colors.dart';

class AppColors {
  // Header y tabs
  static const headerTab = Color(0xFF0097A7);      // Cyan - tabs activos
  
  // Fondos
  static const panelBackground = Color(0xFF262C3A);   // Fondo panel oscuro
  static const gridBackground = Color(0xFF343B4F);    // Fondo del grid
  static const gridHeader = Color(0xFF003954);        // Header del grid (azul oscuro)
  static const fieldBackground = Color(0xFF808A8F);   // Campos de texto
  
  // Filas
  static const gridRowAlt = Color(0xFF2A3142);        // Filas alternas
  static const gridSelectedRow = Color(0xFF0D47A1);   // Fila seleccionada (azul)
  
  // Bordes y botones
  static const border = Color(0xFF2079B5);            // Bordes
  static const buttonSearch = Color(0xFF394B63);      // Botón buscar
  static const buttonExcel = Color(0xFF3D8F2A);       // Botón Excel (verde)
  static const buttonSave = Color(0xFFB76A14);        // Botón guardar (naranja)
  static const buttonGray = Color(0xFF626A73);        // Botón gris
}
```

---

## 🔧 Estructura Base de un Grid

### 1. Imports Necesarios

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';  // Para KeyDownEvent, LogicalKeyboardKey
import 'package:material_warehousing_flutter/core/localization/app_translations.dart';
import 'package:material_warehousing_flutter/core/theme/app_colors.dart';
import 'package:material_warehousing_flutter/core/services/api_service.dart';
import 'package:material_warehousing_flutter/core/widgets/grid_footer.dart';
```

### 2. Variables de Estado Esenciales

```dart
class _MiGridState extends State<MiGrid> {
  // Datos
  List<Map<String, dynamic>> _data = [];
  List<Map<String, dynamic>> _originalData = [];  // Para restaurar filtros
  bool _isLoading = true;
  
  // Selección
  int _selectedIndex = -1;
  
  // Ordenamiento
  String? _sortColumn;
  bool _sortAscending = true;
  
  // Filtros por columna
  Map<String, String?> _columnFilters = {};
  
  // Búsqueda Ctrl+F
  bool _showSearchBar = false;
  String _searchText = '';
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final FocusNode _keyboardFocusNode = FocusNode();
  
  // Traducción helper
  String tr(String key) => widget.languageProvider.tr(key);
}
```

---

## 📋 Definición de Columnas

```dart
// Headers visibles (traducidos)
final headers = [
  tr('part_number'),
  tr('material_code'),
  tr('current_qty'),
  // ... más columnas
];

// Mapeo a campos de BD
final fieldMapping = [
  'numero_parte',
  'codigo_material',
  'cantidad_actual',
  // ... campos correspondientes
];
```

---

## ⌨️ Soporte de Teclado (Ctrl+F, Escape)

```dart
@override
Widget build(BuildContext context) {
  return Focus(
    focusNode: _keyboardFocusNode,
    autofocus: true,
    onKeyEvent: (node, event) {
      // Ctrl+F para abrir búsqueda
      if (event is KeyDownEvent &&
          event.logicalKey == LogicalKeyboardKey.keyF &&
          HardwareKeyboard.instance.isControlPressed) {
        _toggleSearchBar();
        return KeyEventResult.handled;
      }
      // Escape para cerrar búsqueda
      if (event is KeyDownEvent &&
          event.logicalKey == LogicalKeyboardKey.escape &&
          _showSearchBar) {
        _toggleSearchBar();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    },
    child: GestureDetector(
      onTap: () => _keyboardFocusNode.requestFocus(),  // Importante para capturar focus
      child: // ... tu contenido
    ),
  );
}
```

---

## 🔍 Barra de Búsqueda (Search Bar)

```dart
if (_showSearchBar)
  Container(
    height: 36,
    color: AppColors.panelBackground,
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    child: Row(
      children: [
        SizedBox(
          width: 200,
          child: TextField(
            controller: _searchController,
            focusNode: _searchFocusNode,
            onChanged: (value) => setState(() => _searchText = value.toLowerCase()),
            style: const TextStyle(fontSize: 12, color: Colors.white),
            decoration: InputDecoration(
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              hintText: tr('search_placeholder'),
              hintStyle: const TextStyle(color: Colors.white54, fontSize: 12),
              filled: true,
              fillColor: AppColors.fieldBackground,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(4),
                borderSide: const BorderSide(color: AppColors.border),
              ),
              prefixIcon: const Icon(Icons.search, size: 16, color: Colors.white54),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          _searchText.isNotEmpty 
            ? 'Highlighting: "$_searchText"'
            : 'Ctrl+F | Esc to close',
          style: const TextStyle(fontSize: 11, color: Colors.white54),
        ),
        const Spacer(),
        TextButton(
          onPressed: _toggleSearchBar,
          child: const Text('Close', style: TextStyle(fontSize: 11)),
        ),
      ],
    ),
  ),
```

---

## 📊 Header de Columnas con Filtros

```dart
Container(
  height: 28,
  color: AppColors.gridHeader,
  child: Row(
    children: List.generate(headers.length, (i) {
      final header = headers[i];
      final field = fieldMapping[i];
      final isSorted = _sortColumn == field;
      final hasFilter = _columnFilters.containsKey(field);
      final filterKey = GlobalKey();  // Para posición del menú
      
      return Expanded(
        flex: i == 0 ? 3 : 2,  // Primera columna más ancha
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          decoration: const BoxDecoration(
            border: Border(right: BorderSide(color: AppColors.border, width: 0.5)),
          ),
          child: Row(
            children: [
              // Título (click para ordenar)
              Expanded(
                child: GestureDetector(
                  onTap: () => _sortByColumn(field, isSorted ? !_sortAscending : true),
                  onSecondaryTapDown: (details) {
                    _showColumnContextMenu(context, details.globalPosition, field, header);
                  },
                  child: Text(
                    header,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              // Ícono de ordenamiento
              if (isSorted)
                Icon(
                  _sortAscending ? Icons.arrow_upward : Icons.arrow_downward,
                  size: 10,
                  color: Colors.blue,
                ),
              // Ícono de filtro (clicable)
              GestureDetector(
                key: filterKey,
                onTap: () {
                  final RenderBox? box = filterKey.currentContext?.findRenderObject() as RenderBox?;
                  if (box != null) {
                    final position = box.localToGlobal(Offset.zero);
                    _showColumnContextMenu(context, position, field, header);
                  }
                },
                child: Padding(
                  padding: const EdgeInsets.only(left: 2),
                  child: Icon(
                    hasFilter ? Icons.filter_alt : Icons.filter_alt_outlined,
                    size: 12,
                    color: hasFilter ? Colors.blue : Colors.white38,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }),
  ),
),
```

---

## 📝 Filas de Datos

```dart
Expanded(
  child: _isLoading
    ? const Center(child: CircularProgressIndicator(color: Colors.white70))
    : _data.isEmpty
      ? Center(child: Text(tr('no_data'), style: const TextStyle(fontSize: 11, color: Colors.white70)))
      : ListView.builder(
          itemCount: _data.length,
          itemBuilder: (context, index) {
            final row = _data[index];
            final isSelected = index == _selectedIndex;
            final isEven = index % 2 == 0;
            
            return GestureDetector(
              onTap: () => setState(() => _selectedIndex = isSelected ? -1 : index),
              onDoubleTap: () => widget.onRowDoubleClick?.call(row),
              child: Container(
                height: 28,
                decoration: BoxDecoration(
                  color: isSelected
                    ? AppColors.gridSelectedRow
                    : isEven 
                      ? AppColors.gridBackground 
                      : AppColors.gridRowAlt,
                  border: Border(
                    bottom: const BorderSide(color: AppColors.border, width: 0.5),
                    left: isSelected 
                      ? const BorderSide(color: Colors.blue, width: 3) 
                      : BorderSide.none,
                  ),
                ),
                child: Row(
                  children: fieldMapping.asMap().entries.map((entry) {
                    final colIndex = entry.key;
                    final field = entry.value;
                    final columnFlex = colIndex == 0 ? 3 : 2;
                    var value = row[field]?.toString() ?? '';
                    
                    // Formatear valores especiales
                    if (field == 'fecha_recibo' && value.isNotEmpty) {
                      try {
                        final date = DateTime.parse(value);
                        value = '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
                      } catch (_) {}
                    }
                    
                    return Expanded(
                      flex: columnFlex,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        alignment: Alignment.centerLeft,
                        child: _highlightText(value, _searchText),
                      ),
                    );
                  }).toList(),
                ),
              ),
            );
          },
        ),
),
```

---

## 🎯 Funciones de Utilidad

### Highlight de Texto

```dart
Widget _highlightText(String text, String search) {
  if (search.isEmpty) {
    return Text(
      text,
      style: const TextStyle(fontSize: 11, color: Colors.white),
      overflow: TextOverflow.ellipsis,
    );
  }
  
  final lowerText = text.toLowerCase();
  final lowerSearch = search.toLowerCase();
  
  if (!lowerText.contains(lowerSearch)) {
    return Text(
      text,
      style: const TextStyle(fontSize: 11, color: Colors.white),
      overflow: TextOverflow.ellipsis,
    );
  }
  
  final List<TextSpan> spans = [];
  int start = 0;
  int index;
  
  while ((index = lowerText.indexOf(lowerSearch, start)) != -1) {
    if (index > start) {
      spans.add(TextSpan(text: text.substring(start, index)));
    }
    spans.add(TextSpan(
      text: text.substring(index, index + search.length),
      style: const TextStyle(backgroundColor: Colors.yellow, color: Colors.black),
    ));
    start = index + search.length;
  }
  
  if (start < text.length) {
    spans.add(TextSpan(text: text.substring(start)));
  }
  
  return RichText(
    text: TextSpan(
      style: const TextStyle(fontSize: 11, color: Colors.white),
      children: spans,
    ),
    overflow: TextOverflow.ellipsis,
  );
}
```

### Toggle Search Bar

```dart
void _toggleSearchBar() {
  setState(() {
    _showSearchBar = !_showSearchBar;
    if (_showSearchBar) {
      Future.delayed(const Duration(milliseconds: 100), () {
        _searchFocusNode.requestFocus();
      });
    } else {
      _searchText = '';
      _searchController.clear();
    }
  });
}
```

### Ordenar por Columna

```dart
void _sortByColumn(String field, bool ascending) {
  setState(() {
    _sortColumn = field;
    _sortAscending = ascending;
    
    _data.sort((a, b) {
      var aValue = a[field];
      var bValue = b[field];
      
      // Manejar números
      if (aValue is num && bValue is num) {
        return ascending ? aValue.compareTo(bValue) : bValue.compareTo(aValue);
      }
      
      String aStr = aValue?.toString() ?? '';
      String bStr = bValue?.toString() ?? '';
      
      return ascending 
        ? aStr.toLowerCase().compareTo(bStr.toLowerCase())
        : bStr.toLowerCase().compareTo(aStr.toLowerCase());
    });
  });
}
```

---

## 🔧 Menú Contextual de Columna

```dart
void _showColumnContextMenu(BuildContext context, Offset position, String field, String header) {
  final RenderBox overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
  
  showMenu<String>(
    context: context,
    position: RelativeRect.fromRect(
      position & const Size(1, 1),
      Offset.zero & overlay.size,
    ),
    color: const Color(0xFF2D2D30),
    items: [
      PopupMenuItem(
        value: 'sort_asc',
        height: 32,
        child: Row(
          children: [
            Icon(Icons.arrow_upward, size: 16, 
              color: _sortColumn == field && _sortAscending ? Colors.blue : Colors.white70),
            const SizedBox(width: 8),
            Text(tr('sort_ascending'), style: const TextStyle(fontSize: 12, color: Colors.white)),
          ],
        ),
      ),
      PopupMenuItem(
        value: 'sort_desc',
        height: 32,
        child: Row(
          children: [
            Icon(Icons.arrow_downward, size: 16,
              color: _sortColumn == field && !_sortAscending ? Colors.blue : Colors.white70),
            const SizedBox(width: 8),
            Text(tr('sort_descending'), style: const TextStyle(fontSize: 12, color: Colors.white)),
          ],
        ),
      ),
      PopupMenuItem(
        value: 'clear_sort',
        enabled: _sortColumn != null,
        height: 32,
        child: Row(
          children: [
            const Icon(Icons.clear, size: 16, color: Colors.white70),
            const SizedBox(width: 8),
            Text(tr('clear_sorting'), style: const TextStyle(fontSize: 12, color: Colors.white)),
          ],
        ),
      ),
      const PopupMenuDivider(height: 8),
      PopupMenuItem(
        value: 'filter',
        height: 32,
        child: Row(
          children: [
            Icon(Icons.filter_list, size: 16, 
              color: _columnFilters.containsKey(field) ? Colors.blue : Colors.white70),
            const SizedBox(width: 8),
            Text(tr('filter_by_column'), style: const TextStyle(fontSize: 12, color: Colors.white)),
          ],
        ),
      ),
      PopupMenuItem(
        value: 'clear_filter',
        enabled: _columnFilters.containsKey(field),
        height: 32,
        child: Row(
          children: [
            const Icon(Icons.filter_list_off, size: 16, color: Colors.white70),
            const SizedBox(width: 8),
            Text(tr('clear_filter'), style: const TextStyle(fontSize: 12, color: Colors.white)),
          ],
        ),
      ),
    ],
  ).then((value) {
    if (value == null) return;
    
    switch (value) {
      case 'sort_asc':
        _sortByColumn(field, true);
        break;
      case 'sort_desc':
        _sortByColumn(field, false);
        break;
      case 'clear_sort':
        _clearSorting();
        break;
      case 'filter':
        _showFilterDialog(context, field, header);
        break;
      case 'clear_filter':
        _clearColumnFilter(field);
        break;
    }
  });
}
```

---

## 🏁 Footer del Grid

Usa el widget reutilizable:

```dart
GridFooter(text: '${tr('total_rows')} : ${_data.length}'),
```

---

## 📚 Traducciones Necesarias

Agregar en `app_translations.dart`:

```dart
// Grid
'sort_ascending': 'Sort Ascending' / 'Ordenar Ascendente' / '오름차순 정렬',
'sort_descending': 'Sort Descending' / 'Ordenar Descendente' / '내림차순 정렬',
'clear_sorting': 'Clear Sorting' / 'Limpiar Orden' / '정렬 해제',
'filter_by_column': 'Filter by Column' / 'Filtrar por Columna' / '열로 필터링',
'clear_filter': 'Clear Filter' / 'Limpiar Filtro' / '필터 해제',
'search_placeholder': 'Search...' / 'Buscar...' / '검색...',
'total_rows': 'Total Rows' / 'Total Filas' / '총 행',
'no_data': 'No data' / 'Sin datos' / '데이터 없음',
'yes': 'Yes' / 'Sí' / '예',
'no': 'No' / 'No' / '아니오',
```

---

## 🎁 Widget Footer Reutilizable

`lib/core/widgets/grid_footer.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:material_warehousing_flutter/core/theme/app_colors.dart';

class GridFooter extends StatelessWidget {
  final String text;
  const GridFooter({super.key, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 24,
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: const BoxDecoration(
        color: AppColors.gridBackground,
        border: Border(top: BorderSide(color: AppColors.border, width: 1)),
      ),
      child: Text(text, style: const TextStyle(fontSize: 11)),
    );
  }
}
```

---

## ✅ Checklist para Nuevo Grid

- [ ] Crear archivo `[modulo]_grid_panel.dart`
- [ ] Agregar imports necesarios
- [ ] Definir `headers` y `fieldMapping`
- [ ] Implementar variables de estado
- [ ] Agregar soporte de teclado (Focus + onKeyEvent)
- [ ] Implementar Search Bar
- [ ] Implementar Header con filtros
- [ ] Implementar filas con selección
- [ ] Agregar Footer con GridFooter
- [ ] Implementar funciones de ordenamiento
- [ ] Implementar menú contextual
- [ ] Agregar traducciones necesarias

---

## 📐 Dimensiones Estándar

| Elemento | Altura | Notas |
|----------|--------|-------|
| Header | 28-32px | Grid header azul oscuro |
| Row | 24-28px | Fila de datos |
| Footer | 24px | Contador de filas |
| Search Bar | 36px | Barra de búsqueda Ctrl+F |
| Button | 28px | Botones de acción |

---

## 🔄 Ejemplo Completo Mínimo

Ver archivos de referencia:
- `lib/screens/material_warehousing/warehousing_grid_panel.dart` (Grid completo)
- `lib/screens/long_term_inventory/long_term_inventory_screen.dart` (Grid con tabs)

---

*Última actualización: Enero 2026*
