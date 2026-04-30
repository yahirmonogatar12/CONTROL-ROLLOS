import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:material_warehousing_flutter/core/theme/app_colors.dart';

/// Mixin para agregar funcionalidad de columnas redimensionables a cualquier grid
/// 
/// Uso:
/// 1. Añadir `with ResizableColumnsMixin` al State del widget
/// 2. Llamar `initColumnFlex(columnCount, storageKey)` en initState
/// 3. Usar `buildResizableHeader(headers, ...)` para el header
/// 4. Usar `getColumnFlex(index)` para obtener el flex de cada columna de datos
mixin ResizableColumnsMixin<T extends StatefulWidget> on State<T> {
  List<double> _columnFlexFactors = [];
  String _storageKey = '';
  int? _resizingColumn;
  double _resizeStartX = 0;
  double _resizeStartFlex = 0;

  /// Inicializa los flex factors para las columnas
  /// [columnCount] - número de columnas
  /// [storageKey] - clave única para guardar/cargar configuración
  /// [defaultFlexValues] - valores flex por defecto (opcional)
  Future<void> initColumnFlex(int columnCount, String storageKey, {List<double>? defaultFlexValues}) async {
    _storageKey = storageKey;
    
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getString('grid_flex_$storageKey');
      if (stored != null) {
        final List<dynamic> decoded = jsonDecode(stored);
        if (decoded.length == columnCount) {
          if (mounted) {
            setState(() {
              _columnFlexFactors = decoded.map((e) => (e as num).toDouble()).toList();
            });
          }
          return;
        }
      }
    } catch (e) {
      debugPrint('Error loading column flex: $e');
    }
    
    // Valores por defecto
    if (mounted) {
      setState(() {
        _columnFlexFactors = defaultFlexValues ?? List.filled(columnCount, 2.0);
      });
    }
  }

  /// Guarda los flex factors actuales
  Future<void> _saveColumnFlex() async {
    if (_storageKey.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('grid_flex_$_storageKey', jsonEncode(_columnFlexFactors));
    } catch (e) {
      debugPrint('Error saving column flex: $e');
    }
  }

  /// Inicia el redimensionamiento de una columna
  void onResizeStart(int index, DragStartDetails details) {
    setState(() {
      _resizingColumn = index;
      _resizeStartX = details.globalPosition.dx;
      final flex = _columnFlexFactors.isEmpty || index >= _columnFlexFactors.length
          ? 2.0
          : _columnFlexFactors[index];
      _resizeStartFlex = flex;
    });
  }

  /// Actualiza el redimensionamiento
  void onResizeUpdate(int index, DragUpdateDetails details) {
    if (_resizingColumn == index && _columnFlexFactors.isNotEmpty) {
      final delta = details.globalPosition.dx - _resizeStartX;
      final newFlex = (_resizeStartFlex + delta / 100).clamp(0.1, 20.0);
      setState(() {
        _columnFlexFactors[index] = newFlex;
      });
    }
  }

  /// Finaliza el redimensionamiento
  void onResizeEnd(int index, DragEndDetails details) {
    setState(() {
      _resizingColumn = null;
    });
    _saveColumnFlex();
  }
  
  /// Helper para construir el handle de resize
  Widget buildResizeHandle(int index) {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      child: GestureDetector(
        onHorizontalDragStart: (details) => onResizeStart(index, details),
        onHorizontalDragUpdate: (details) => onResizeUpdate(index, details),
        onHorizontalDragEnd: (details) => onResizeEnd(index, details),
        child: Container(
          width: 8,
          height: 32,
          color: _resizingColumn == index ? Colors.blue.withOpacity(0.5) : Colors.transparent,
          child: Center(
            child: Container(
              width: 2,
              height: 20,
              decoration: BoxDecoration(
                color: const Color(0xFF666666),
                borderRadius: BorderRadius.circular(1),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Obtiene el flex factor para una columna (para usar en las filas de datos)
  int getColumnFlex(int index) {
    if (_columnFlexFactors.isEmpty || index >= _columnFlexFactors.length) {
      return 200; // Default flex * 100
    }
    return (_columnFlexFactors[index] * 100).round();
  }

  /// Construye el header con columnas redimensionables
  /// 
  /// [headers] - Lista de textos para cada header
  /// [onSort] - Callback cuando se ordena (field, ascending)
  /// [onFilter] - Callback cuando se filtra (field)
  /// [sortColumn] - Columna actualmente ordenada
  /// [sortAscending] - Si el orden es ascendente
  /// [columnFilters] - Map de filtros activos
  /// [fieldMapping] - Lista de nombres de campo para cada columna
  /// [showCheckbox] - Si mostrar checkbox de seleccionar todo
  /// [selectAllValue] - Valor del checkbox de seleccionar todo
  /// [onSelectAll] - Callback cuando se selecciona todo
  Widget buildResizableHeader({
    required List<String> headers,
    List<String>? fieldMapping,
    Function(String field, bool ascending)? onSort,
    Function(String field)? onFilter,
    String? sortColumn,
    bool sortAscending = true,
    Map<String, String?>? columnFilters,
    bool showCheckbox = true,
    bool? selectAllValue,
    Function(bool?)? onSelectAll,
  }) {
    return Container(
      height: 32,
      decoration: const BoxDecoration(
        color: AppColors.gridHeader,
        border: Border(bottom: BorderSide(color: AppColors.border, width: 1)),
      ),
      child: Row(
        children: [
          // Checkbox column
          if (showCheckbox)
            SizedBox(
              width: 30,
              child: Checkbox(
                value: selectAllValue,
                tristate: true,
                onChanged: onSelectAll,
                side: const BorderSide(color: AppColors.border),
                activeColor: Colors.blue,
              ),
            ),
          // Headers con resize
          ...List.generate(headers.length, (i) {
            final header = headers[i];
            final field = fieldMapping != null && i < fieldMapping.length ? fieldMapping[i] : '';
            final isSorted = sortColumn == field;
            final hasFilter = columnFilters?.containsKey(field) ?? false;
            
            final flex = _columnFlexFactors.isEmpty || i >= _columnFlexFactors.length
                ? 2.0
                : _columnFlexFactors[i];
            
            return Expanded(
              flex: (flex * 100).round(),
              child: Row(
                children: [
                  // Header content
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        if (onSort != null && field.isNotEmpty) {
                          onSort(field, !(isSorted && sortAscending));
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        alignment: Alignment.centerLeft,
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                header,
                                style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (isSorted)
                              Icon(
                                sortAscending ? Icons.arrow_upward : Icons.arrow_downward,
                                size: 10,
                                color: Colors.blue,
                              ),
                            if (onFilter != null && field.isNotEmpty)
                              GestureDetector(
                                onTap: () => onFilter(field),
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
                    ),
                  ),
                  // Resize handle
                  MouseRegion(
                    cursor: SystemMouseCursors.resizeColumn,
                    child: GestureDetector(
                      onHorizontalDragStart: (details) {
                        setState(() {
                          _resizingColumn = i;
                          _resizeStartX = details.globalPosition.dx;
                          _resizeStartFlex = flex;
                        });
                      },
                      onHorizontalDragUpdate: (details) {
                        if (_resizingColumn == i && _columnFlexFactors.isNotEmpty) {
                          final delta = details.globalPosition.dx - _resizeStartX;
                          final newFlex = (_resizeStartFlex + delta / 100).clamp(0.1, 20.0);
                          setState(() {
                            _columnFlexFactors[i] = newFlex;
                          });
                        }
                      },
                      onHorizontalDragEnd: (details) {
                        setState(() {
                          _resizingColumn = null;
                        });
                        _saveColumnFlex();
                      },
                      child: Container(
                        width: 8,
                        height: 32,
                        color: _resizingColumn == i ? Colors.blue.withOpacity(0.5) : Colors.transparent,
                        child: Center(
                          child: Container(
                            width: 2,
                            height: 20,
                            decoration: BoxDecoration(
                              color: const Color(0xFF666666),
                              borderRadius: BorderRadius.circular(1),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}
