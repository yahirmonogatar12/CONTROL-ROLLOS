import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:material_warehousing_flutter/core/localization/app_translations.dart';
import 'package:material_warehousing_flutter/core/theme/app_colors.dart';
import 'package:material_warehousing_flutter/core/services/api_service.dart';
import 'package:material_warehousing_flutter/core/services/auth_service.dart';

class WarehousingGridPanel extends StatefulWidget {
  final LanguageProvider languageProvider;
  final Function(Map<String, dynamic>)? onRowDoubleClick; // Callback para doble click
  
  const WarehousingGridPanel({
    super.key, 
    required this.languageProvider,
    this.onRowDoubleClick,
  });

  @override
  State<WarehousingGridPanel> createState() => WarehousingGridPanelState();
}

class WarehousingGridPanelState extends State<WarehousingGridPanel> with AutomaticKeepAliveClientMixin {
  List<Map<String, dynamic>> _data = [];
  List<Map<String, dynamic>> _originalData = []; // Datos sin ordenar
  bool _isLoading = true;
  bool _showSearchBar = false;
  String _searchText = '';
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final FocusNode _keyboardFocusNode = FocusNode();
  final ScrollController _horizontalScrollController = ScrollController();
  
  // Índices de filas seleccionadas (multi-selección)
  Set<int> _selectedIndices = {};
  int? _lastSelectedIndex; // Para selección con Shift
  
  // Ordenamiento
  String? _sortColumn;
  bool _sortAscending = true;
  
  // Filtros activos por columna
  Map<String, String?> _columnFilters = {};
  
  // Proporciones de columna redimensionables (flex factors)
  List<double> _columnFlexFactors = [];
  static const String _columnWidthsKey = 'warehousing_grid_flex';
  int? _resizingColumn;
  double _resizeStartX = 0;
  double _resizeStartFlex = 0;
  
  // Para mantener el estado al cambiar de pestaña
  @override
  bool get wantKeepAlive => true;
  
  String tr(String key) => widget.languageProvider.tr(key);

  @override
  void initState() {
    super.initState();
    _loadColumnWidths();
    _loadTodayData(); // Cargar solo datos del día al iniciar
  }
  
  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    _keyboardFocusNode.dispose();
    _horizontalScrollController.dispose();
    super.dispose();
  }
  
  // Cargar proporciones de columna guardadas
  Future<void> _loadColumnWidths() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getString(_columnWidthsKey);
      if (stored != null) {
        final List<dynamic> decoded = jsonDecode(stored);
        if (decoded.length == 12) { // Número actual de columnas
          setState(() {
            _columnFlexFactors = decoded.map((e) => (e as num).toDouble()).toList();
          });
          return;
        }
      }
    } catch (e) {
      debugPrint('Error loading column flex factors: $e');
    }
    // Valores por defecto (proporciones flex)
    setState(() {
      _columnFlexFactors = [
        3.0, // Part Number
        4.0, // Material Spec
        4.0, // Warehousing Code
        3.0, // Supplier Lot
        2.0, // Current Qty
        2.0, // Packaging Unit
        2.0, // Location
        2.5, // Warehousing Date
        1.5, // Hora
        3.0, // Vendor
        2.0, // Cancelled
        2.0, // Registered By
      ];
    });
  }
  
  // Guardar proporciones de columna
  Future<void> _saveColumnWidths() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_columnWidthsKey, jsonEncode(_columnFlexFactors));
    } catch (e) {
      debugPrint('Error saving column flex factors: $e');
    }
  }

  // Cargar solo datos del día actual (al iniciar)
  Future<void> _loadTodayData({bool preserveFilters = false}) async {
    setState(() => _isLoading = true);
    final now = DateTime.now();
    final today = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final data = await ApiService.searchWarehousing(
      fechaInicio: today,
      fechaFin: today,
    );
    if (mounted) {
      setState(() {
        _originalData = List.from(data);
        _data = data;
        if (!preserveFilters) {
          _sortColumn = null;
        }
        _isLoading = false;
        // Re-aplicar filtros si existen
        if (_columnFilters.isNotEmpty) {
          _applyAllFilters();
        }
      });
    }
  }
  
  // Método público para recargar datos del día (después de una nueva entrada)
  Future<void> reloadData({bool preserveFilters = true}) async {
    _selectedIndices.clear(); // Limpiar selección al recargar
    await _loadTodayData(preserveFilters: preserveFilters);
  }
  
  // Método público para obtener datos de la fila seleccionada (primera seleccionada)
  Map<String, dynamic>? getSelectedRowData() {
    if (_selectedIndices.isNotEmpty) {
      final firstIndex = _selectedIndices.first;
      if (firstIndex >= 0 && firstIndex < _data.length) {
        return _data[firstIndex];
      }
    }
    return null;
  }
  
  // Método público para verificar si hay fila seleccionada
  bool hasSelectedRow() => _selectedIndices.isNotEmpty;
  
  // Método público para obtener todas las filas seleccionadas (multi-selección)
  List<Map<String, dynamic>> getSelectedItems() {
    return _selectedIndices
        .where((i) => i >= 0 && i < _data.length)
        .map((i) => _data[i])
        .toList();
  }
  
  // Limpiar selección
  void clearSelection() {
    setState(() => _selectedIndices.clear());
  }
  
  // Seleccionar/deseleccionar todos
  void toggleSelectAll() {
    setState(() {
      if (_selectedIndices.length == _data.length) {
        _selectedIndices.clear();
      } else {
        _selectedIndices = Set<int>.from(List.generate(_data.length, (i) => i));
      }
    });
  }
  
  // Método público para obtener datos para exportar a Excel
  List<Map<String, dynamic>> getDataForExport() => _data;
  
  // Ordenar datos por columna
  void _sortByColumn(String field, bool ascending) {
    setState(() {
      _sortColumn = field;
      _sortAscending = ascending;
      _data.sort((a, b) {
        var aValue = a[field]?.toString() ?? '';
        var bValue = b[field]?.toString() ?? '';
        
        // Intentar comparar como números si es posible
        final aNum = num.tryParse(aValue);
        final bNum = num.tryParse(bValue);
        
        int result;
        if (aNum != null && bNum != null) {
          result = aNum.compareTo(bNum);
        } else {
          result = aValue.toLowerCase().compareTo(bValue.toLowerCase());
        }
        
        return ascending ? result : -result;
      });
    });
  }
  
  // Limpiar ordenamiento
  void _clearSorting() {
    setState(() {
      _sortColumn = null;
      _sortAscending = true;
      _data = List.from(_originalData);
    });
  }
  
  // Mostrar menú contextual de columna
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
              Text('Sort Ascending', 
                style: TextStyle(fontSize: 12, 
                  color: _sortColumn == field && _sortAscending ? Colors.blue : Colors.white)),
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
              Text('Sort Descending',
                style: TextStyle(fontSize: 12,
                  color: _sortColumn == field && !_sortAscending ? Colors.blue : Colors.white)),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'clear_sort',
          enabled: _sortColumn != null,
          height: 32,
          child: Row(
            children: [
              Icon(Icons.clear, size: 16, color: _sortColumn != null ? Colors.white70 : Colors.white30),
              const SizedBox(width: 8),
              Text('Clear Sorting', 
                style: TextStyle(fontSize: 12, color: _sortColumn != null ? Colors.white : Colors.white30)),
            ],
          ),
        ),
        const PopupMenuDivider(height: 8),
        PopupMenuItem(
          value: 'best_fit',
          height: 32,
          child: const Row(
            children: [
              Icon(Icons.fit_screen, size: 16, color: Colors.white70),
              SizedBox(width: 8),
              Text('Best Fit', style: TextStyle(fontSize: 12, color: Colors.white)),
            ],
          ),
        ),
        const PopupMenuDivider(height: 8),
        PopupMenuItem(
          value: 'filter',
          height: 32,
          child: const Row(
            children: [
              Icon(Icons.filter_list, size: 16, color: Colors.white70),
              SizedBox(width: 8),
              Text('Filter Editor...', style: TextStyle(fontSize: 12, color: Colors.white)),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'search',
          height: 32,
          child: const Row(
            children: [
              Icon(Icons.search, size: 16, color: Colors.white70),
              SizedBox(width: 8),
              Text('Show Search Panel', style: TextStyle(fontSize: 12, color: Colors.white)),
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
        case 'search':
          _toggleSearchBar();
          break;
      }
    });
  }
  
  // Mostrar diálogo de filtro
  void _showFilterDialog(BuildContext context, String field, String header) {
    final filterController = TextEditingController();
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2D2D30),
        title: Text('Filter: $header', style: const TextStyle(color: Colors.white, fontSize: 14)),
        content: SizedBox(
          width: 300,
          child: TextField(
            controller: filterController,
            autofocus: true,
            style: const TextStyle(color: Colors.white, fontSize: 12),
            decoration: InputDecoration(
              hintText: 'Enter filter value...',
              hintStyle: const TextStyle(color: Colors.white54, fontSize: 12),
              filled: true,
              fillColor: AppColors.fieldBackground,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(4),
                borderSide: const BorderSide(color: AppColors.border),
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _applyFilter(field, filterController.text);
            },
            child: const Text('Apply'),
          ),
        ],
      ),
    );
  }
  
  // Aplicar filtro a columna
  void _applyFilter(String field, String? filterValue) {
    setState(() {
      if (filterValue == null || filterValue.isEmpty) {
        _columnFilters.remove(field);
      } else {
        _columnFilters[field] = filterValue;
      }
      _applyAllFilters();
    });
  }
  
  // Aplicar todos los filtros activos
  void _applyAllFilters() {
    if (_columnFilters.isEmpty) {
      _data = List.from(_originalData);
    } else {
      _data = _originalData.where((row) {
        for (var entry in _columnFilters.entries) {
          final field = entry.key;
          final filterValue = entry.value;
          if (filterValue == null) continue;
          
          // Obtener valor - manejar campos virtuales
          String value;
          if (field == 'fecha_recibo_hora') {
            // Campo virtual: extraer hora de fecha_recibo
            final rawValue = row['fecha_recibo']?.toString() ?? '';
            if (rawValue.isNotEmpty) {
              try {
                final isoValue = rawValue.contains('T') ? rawValue : rawValue.replaceFirst(' ', 'T');
                final date = DateTime.parse(isoValue);
                value = '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
              } catch (_) {
                value = '';
              }
            } else {
              value = '';
            }
          } else if (field == 'fecha_recibo') {
            // Formatear fecha sin hora para el filtro
            final rawValue = row[field]?.toString() ?? '';
            if (rawValue.isNotEmpty) {
              try {
                final isoValue = rawValue.contains('T') ? rawValue : rawValue.replaceFirst(' ', 'T');
                final date = DateTime.parse(isoValue);
                value = '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
              } catch (_) {
                value = rawValue;
              }
            } else {
              value = '';
            }
          } else {
            value = row[field]?.toString() ?? '';
          }
          
          // Filtro especial para blanks/non-blanks
          if (filterValue == '__BLANKS__') {
            if (value.isNotEmpty) return false;
          } else if (filterValue == '__NON_BLANKS__') {
            if (value.isEmpty) return false;
          } else {
            if (value != filterValue) return false;
          }
        }
        return true;
      }).toList();
    }
  }
  
  // Mostrar dropdown de filtro con valores únicos
  void _showFilterDropdown(BuildContext context, GlobalKey key, String field, String header) {
    final RenderBox? renderBox = key.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;
    
    final position = renderBox.localToGlobal(Offset.zero);
    final size = renderBox.size;
    
    // Obtener valores únicos de la columna
    final Set<String> uniqueValues = {};
    bool hasBlanks = false;
    
    for (var row in _originalData) {
      // Manejar campos virtuales
      String value;
      if (field == 'fecha_recibo_hora') {
        // Campo virtual: extraer hora de fecha_recibo
        final rawValue = row['fecha_recibo']?.toString() ?? '';
        if (rawValue.isNotEmpty) {
          try {
            // Manejar ambos formatos: "2026-01-20 00:01:10" o "2026-01-20T00:01:10"
            final isoValue = rawValue.contains('T') ? rawValue : rawValue.replaceFirst(' ', 'T');
            final date = DateTime.parse(isoValue);
            value = '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
          } catch (_) {
            value = '';
          }
        } else {
          value = '';
        }
      } else if (field == 'fecha_recibo') {
        // Formatear fecha sin hora para el filtro
        final rawValue = row[field]?.toString() ?? '';
        if (rawValue.isNotEmpty) {
          try {
            final isoValue = rawValue.contains('T') ? rawValue : rawValue.replaceFirst(' ', 'T');
            final date = DateTime.parse(isoValue);
            value = '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
          } catch (_) {
            value = rawValue;
          }
        } else {
          value = '';
        }
      } else {
        value = row[field]?.toString() ?? '';
      }
      
      if (value.isEmpty) {
        hasBlanks = true;
      } else {
        uniqueValues.add(value);
      }
    }
    
    // Ordenar valores
    final sortedValues = uniqueValues.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    
    final currentFilter = _columnFilters[field];
    
    showDialog(
      context: context,
      barrierColor: Colors.transparent,
      builder: (context) {
        String searchText = '';
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final filteredValues = sortedValues
                .where((v) => v.toLowerCase().contains(searchText.toLowerCase()))
                .toList();
            
            return Stack(
              children: [
                Positioned(
                  left: position.dx,
                  top: position.dy + size.height,
                  child: Material(
                    elevation: 8,
                    color: const Color(0xFF252526),
                    borderRadius: BorderRadius.circular(4),
                    child: Container(
                      width: 200,
                      constraints: const BoxConstraints(maxHeight: 300),
                      decoration: BoxDecoration(
                        border: Border.all(color: const Color(0xFF3C3C3C)),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Barra de búsqueda
                          Container(
                            padding: const EdgeInsets.all(8),
                            child: TextField(
                              autofocus: true,
                              style: const TextStyle(color: Colors.white, fontSize: 12),
                              decoration: InputDecoration(
                                isDense: true,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                hintText: 'Search...',
                                hintStyle: const TextStyle(color: Colors.white38, fontSize: 11),
                                prefixIcon: const Icon(Icons.search, size: 16, color: Colors.white38),
                                prefixIconConstraints: const BoxConstraints(minWidth: 30),
                                filled: true,
                                fillColor: const Color(0xFF3C3C3C),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(4),
                                  borderSide: BorderSide.none,
                                ),
                              ),
                              onChanged: (value) {
                                setDialogState(() => searchText = value);
                              },
                            ),
                          ),
                          const Divider(height: 1, color: Color(0xFF3C3C3C)),
                          // Lista de opciones
                          Flexible(
                            child: SingleChildScrollView(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Opción para limpiar filtro
                                  if (currentFilter != null)
                                    _buildFilterOption(
                                      context, 
                                      '(Clear Filter)', 
                                      currentFilter == null,
                                      Icons.clear,
                                      Colors.orange,
                                      () {
                                        Navigator.pop(context);
                                        _applyFilter(field, null);
                                      },
                                    ),
                                  // Blanks
                                  if (hasBlanks)
                                    _buildFilterOption(
                                      context,
                                      '(Blanks)',
                                      currentFilter == '__BLANKS__',
                                      Icons.check_box_outline_blank,
                                      Colors.white70,
                                      () {
                                        Navigator.pop(context);
                                        _applyFilter(field, '__BLANKS__');
                                      },
                                    ),
                                  // Non-blanks
                                  _buildFilterOption(
                                    context,
                                    '(Non blanks)',
                                    currentFilter == '__NON_BLANKS__',
                                    Icons.check_box,
                                    Colors.white70,
                                    () {
                                      Navigator.pop(context);
                                      _applyFilter(field, '__NON_BLANKS__');
                                    },
                                  ),
                                  const Divider(height: 1, color: Color(0xFF3C3C3C)),
                                  // Valores únicos
                                  ...filteredValues.map((value) => _buildFilterOption(
                                    context,
                                    value,
                                    currentFilter == value,
                                    null,
                                    null,
                                    () {
                                      Navigator.pop(context);
                                      _applyFilter(field, value);
                                    },
                                  )),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
  
  Widget _buildFilterOption(BuildContext context, String text, bool isSelected, IconData? icon, Color? iconColor, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        color: isSelected ? Colors.blue.withOpacity(0.3) : null,
        child: Row(
          children: [
            if (icon != null) ...[
              Icon(icon, size: 14, color: iconColor),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: Text(
                text,
                style: TextStyle(
                  fontSize: 11,
                  color: isSelected ? Colors.blue : Colors.white,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (isSelected)
              const Icon(Icons.check, size: 14, color: Colors.blue),
          ],
        ),
      ),
    );
  }

  // Cargar todos los datos (cuando se quita el filtro de fecha)
  Future<void> _loadAllData() async {
    setState(() => _isLoading = true);
    final data = await ApiService.getWarehousing();
    if (mounted) {
      setState(() {
        _originalData = List.from(data);
        _data = data;
        _sortColumn = null;
        _isLoading = false;
      });
    }
  }
  
  // Método público para buscar por fecha
  Future<void> searchByDate(DateTime? fechaInicio, DateTime? fechaFin, {bool preserveFilters = false, String? texto}) async {
    setState(() => _isLoading = true);
    
    List<Map<String, dynamic>> data;
    if (fechaInicio != null && fechaFin != null) {
      final inicio = '${fechaInicio.year}-${fechaInicio.month.toString().padLeft(2, '0')}-${fechaInicio.day.toString().padLeft(2, '0')}';
      final fin = '${fechaFin.year}-${fechaFin.month.toString().padLeft(2, '0')}-${fechaFin.day.toString().padLeft(2, '0')}';
      data = await ApiService.searchWarehousing(
        fechaInicio: inicio, 
        fechaFin: fin,
        texto: texto ?? (_searchText.isNotEmpty ? _searchText : null),
      );
    } else {
      // Si no hay fechas, buscar sin filtro de fecha pero con texto
      data = await ApiService.searchWarehousing(
        texto: texto ?? (_searchText.isNotEmpty ? _searchText : null),
      );
    }
    
    if (mounted) {
      setState(() {
        _originalData = List.from(data);
        _data = data;
        if (!preserveFilters) {
          _sortColumn = null;
        }
        _isLoading = false;
        // Re-aplicar filtros si existen
        if (_columnFilters.isNotEmpty) {
          _applyAllFilters();
        }
      });
    }
  }
  
  void _toggleSearchBar() {
    setState(() {
      _showSearchBar = !_showSearchBar;
      if (_showSearchBar) {
        Future.delayed(const Duration(milliseconds: 100), () {
          _searchFocusNode.requestFocus();
        });
      } else {
        _searchController.clear();
        _searchText = '';
        _loadTodayData(); // Volver a cargar solo del día
      }
    });
  }
  
  Future<void> _onSearchTextChanged(String text) async {
    setState(() => _searchText = text);
    
    if (text.isEmpty) {
      _loadTodayData();
    } else {
      setState(() => _isLoading = true);
      // Buscar en los datos del día actual por defecto
      final now = DateTime.now();
      final today = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      final data = await ApiService.searchWarehousing(
        fechaInicio: today,
        fechaFin: today,
        texto: text,
      );
      if (mounted) {
        setState(() {
          _data = data;
          _isLoading = false;
        });
      }
    }
  }
  
  // Widget para resaltar texto encontrado
  Widget _highlightText(String text, String searchText) {
    if (searchText.isEmpty) {
      return Text(
        text,
        style: const TextStyle(fontSize: 11, color: Colors.white),
        overflow: TextOverflow.ellipsis,
      );
    }
    
    final lowerText = text.toLowerCase();
    final lowerSearch = searchText.toLowerCase();
    final index = lowerText.indexOf(lowerSearch);
    
    if (index < 0) {
      return Text(
        text,
        style: const TextStyle(fontSize: 11, color: Colors.white),
        overflow: TextOverflow.ellipsis,
      );
    }
    
    return RichText(
      overflow: TextOverflow.ellipsis,
      text: TextSpan(
        children: [
          TextSpan(
            text: text.substring(0, index),
            style: const TextStyle(fontSize: 11, color: Colors.white),
          ),
          TextSpan(
            text: text.substring(index, index + searchText.length),
            style: const TextStyle(
              fontSize: 11, 
              color: Colors.black,
              backgroundColor: Colors.yellow,
              fontWeight: FontWeight.bold,
            ),
          ),
          TextSpan(
            text: text.substring(index + searchText.length),
            style: const TextStyle(fontSize: 11, color: Colors.white),
          ),
        ],
      ),
    );
  }
  
  @override
  Widget build(BuildContext context) {
    super.build(context); // Necesario para AutomaticKeepAliveClientMixin
    
    final headers = [
      tr('part_number'),
      tr('material_spec'),
      tr('material_warehousing_code'),
      tr('material_lot_no'),
      tr('current_qty'),
      tr('packaging_unit'),
      tr('location'),
      tr('warehousing_date'),
      'Hora',
      tr('vendor'),
      tr('cancelled'),
      tr('registered_by'),
    ];

    // Mapeo de campos de BD a columnas del grid
    final fieldMapping = [
      'numero_parte',                 // Part Number
      'especificacion',               // Material Spec
      'codigo_material_recibido',     // Material Warehousing Code
      'numero_lote_material',         // Material Lot No (Supplier Lot)
      'cantidad_actual',              // Current Qty
      'cantidad_estandarizada',       // Packaging Unit
      'location',                     // Location
      'fecha_recibo',                 // Warehousing Date
      'fecha_recibo_hora',            // Hora
      'vendedor',                     // Vendor
      'cancelado',                    // Cancelled
      'usuario_registro',             // Registered By
    ];

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
        onTap: () => _keyboardFocusNode.requestFocus(),
        child: Container(
        color: AppColors.gridBackground,
        child: Column(
          children: [
            // Search Bar (Ctrl+F)
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
                        onChanged: _onSearchTextChanged,
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
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(4),
                            borderSide: const BorderSide(color: AppColors.border),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(4),
                            borderSide: const BorderSide(color: Colors.blue),
                          ),
                          suffixIcon: _searchController.text.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear, size: 16, color: Colors.white70),
                                  onPressed: () {
                                    _searchController.clear();
                                    _onSearchTextChanged('');
                                  },
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                )
                              : null,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      height: 28,
                      child: ElevatedButton(
                        onPressed: _toggleSearchBar,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.grey[700],
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                        ),
                        child: const Text('Close', style: TextStyle(fontSize: 11)),
                      ),
                    ),
                  ],
                ),
              ),
            // Header con scroll horizontal sincronizado
            Container(
              height: 32,
              decoration: const BoxDecoration(
                color: AppColors.gridHeader,
                border: Border(bottom: BorderSide(color: AppColors.border, width: 1)),
              ),
              child: Row(
                children: [
                  // Checkbox column header - Select All (fijo)
                  SizedBox(
                    width: 30,
                    child: Checkbox(
                      value: _data.isNotEmpty && _selectedIndices.length == _data.length,
                      tristate: true,
                      onChanged: (value) {
                        toggleSelectAll();
                      },
                      side: const BorderSide(color: AppColors.border),
                      activeColor: Colors.blue,
                    ),
                  ),
                  // Headers con Expanded proporcional + resize handles
                  ...List.generate(headers.length, (i) {
                    final header = headers[i];
                    final field = fieldMapping[i];
                    final isSorted = _sortColumn == field;
                    final hasFilter = _columnFilters.containsKey(field);
                    final filterKey = GlobalKey();
                    
                    // Usar flex factor dinámico (redimensionable)
                    final flex = _columnFlexFactors.isEmpty || i >= _columnFlexFactors.length
                        ? 2.0
                        : _columnFlexFactors[i];
                    
                    return Expanded(
                      flex: (flex * 100).round(), // Convertir a int para Expanded
                      child: Row(
                        children: [
                          // Contenido del header
                          Expanded(
                            child: GestureDetector(
                              onTap: () => _sortByColumn(field, isSorted ? !_sortAscending : true),
                              onSecondaryTapDown: (details) {
                                _showColumnContextMenu(context, details.globalPosition, field, header);
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
                                        _sortAscending ? Icons.arrow_upward : Icons.arrow_downward,
                                        size: 10,
                                        color: Colors.blue,
                                      ),
                                    GestureDetector(
                                      key: filterKey,
                                      onTap: () => _showFilterDropdown(context, filterKey, field, header),
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
                          // Resize handle (área más grande para facilitar arrastre)
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
                                  // Ajustar flex: +30px = +1 flex (más sensible)
                                  final newFlex = (_resizeStartFlex + delta / 30).clamp(0.5, 15.0);
                                  setState(() {
                                    _columnFlexFactors[i] = newFlex;
                                  });
                                }
                              },
                              onHorizontalDragEnd: (details) {
                                setState(() {
                                  _resizingColumn = null;
                                });
                                _saveColumnWidths();
                              },
                              child: Container(
                                width: 8, // Área más grande para arrastrar
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
            ),
          // Data rows
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: Colors.white70),
                  )
                : _data.isEmpty
                    ? const Center(
                        child: Text(
                          'No data',
                          style: TextStyle(fontSize: 11, color: Colors.white70),
                        ),
                      )
                    : SelectionArea(
                      child: NotificationListener<ScrollNotification>(
                        onNotification: (notification) {
                          // Sincronizar scroll horizontal
                          return false;
                        },
                        child: ListView.builder(
                          itemCount: _data.length,
                          itemBuilder: (context, index) {
                            final row = _data[index];
                            final isSelected = _selectedIndices.contains(index);
                            final isEven = index % 2 == 0;
                            return GestureDetector(
                              onTap: () {
                                final isShiftPressed = HardwareKeyboard.instance.isShiftPressed;
                                setState(() {
                                  if (isShiftPressed && _lastSelectedIndex != null) {
                                    // Selección en rango con Shift
                                    final start = _lastSelectedIndex! < index ? _lastSelectedIndex! : index;
                                    final end = _lastSelectedIndex! > index ? _lastSelectedIndex! : index;
                                    for (int i = start; i <= end; i++) {
                                      _selectedIndices.add(i);
                                    }
                                    _lastSelectedIndex = index;
                                  } else {
                                    // Selección individual normal
                                    if (isSelected) {
                                      _selectedIndices.remove(index);
                                    } else {
                                      _selectedIndices.add(index);
                                    }
                                    _lastSelectedIndex = index;
                                  }
                                });
                              },
                              onDoubleTap: () {
                                widget.onRowDoubleClick?.call(row);
                              },
                              child: Container(
                                height: 28,
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? Colors.blue.withOpacity(0.3)
                                      : isEven 
                                          ? AppColors.gridBackground 
                                          : AppColors.gridBackground.withOpacity(0.7),
                                  border: Border(
                                    bottom: const BorderSide(color: AppColors.border, width: 0.5),
                                    left: isSelected ? const BorderSide(color: Colors.blue, width: 3) : BorderSide.none,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    // Checkbox fijo
                                    SizedBox(
                                      width: 30,
                                      child: Checkbox(
                                        value: isSelected,
                                        onChanged: (value) {
                                          final isShiftPressed = HardwareKeyboard.instance.isShiftPressed;
                                          setState(() {
                                            if (isShiftPressed && _lastSelectedIndex != null) {
                                              // Selección en rango con Shift
                                              final start = _lastSelectedIndex! < index ? _lastSelectedIndex! : index;
                                              final end = _lastSelectedIndex! > index ? _lastSelectedIndex! : index;
                                              for (int i = start; i <= end; i++) {
                                                _selectedIndices.add(i);
                                              }
                                              _lastSelectedIndex = index;
                                            } else {
                                              if (value == true) {
                                                _selectedIndices.add(index);
                                              } else {
                                                _selectedIndices.remove(index);
                                              }
                                              _lastSelectedIndex = index;
                                            }
                                          });
                                        },
                                        side: const BorderSide(color: AppColors.border),
                                        activeColor: Colors.blue,
                                      ),
                                    ),
                                    // Data cells con Expanded proporcional (sincronizado con header)
                                    ...fieldMapping.asMap().entries.map((entry) {
                                      final colIndex = entry.key;
                                      final field = entry.value;
                                      var value = row[field]?.toString() ?? '';
                                      
                                      // Usar flex factor dinámico (sincronizado con header)
                                      final flex = _columnFlexFactors.isEmpty || colIndex >= _columnFlexFactors.length
                                          ? 2.0
                                          : _columnFlexFactors[colIndex];
                                      final columnFlex = (flex * 100).round();
                                      
                                      // Formatear fecha (solo fecha)
                                      if (field == 'fecha_recibo' && value.isNotEmpty) {
                                        try {
                                          final isoValue = value.contains('T') ? value : value.replaceFirst(' ', 'T');
                                          final date = DateTime.parse(isoValue);
                                          value = '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
                                        } catch (_) {}
                                      }
                                      // Formatear hora (columna separada)
                                      if (field == 'fecha_recibo_hora') {
                                        final rawValue = row['fecha_recibo']?.toString() ?? '';
                                        if (rawValue.isNotEmpty) {
                                          try {
                                            final isoValue = rawValue.contains('T') ? rawValue : rawValue.replaceFirst(' ', 'T');
                                            final date = DateTime.parse(isoValue);
                                            value = '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
                                          } catch (_) {
                                            value = '';
                                          }
                                        }
                                      }
                                      // Formatear estado_desecho
                                      if (field == 'estado_desecho') {
                                        value = value == '1' ? tr('yes') : tr('no');
                                      }
                                      // Formatear cancelado con color rojo
                                      if (field == 'cancelado') {
                                        final isCancelled = value == '1';
                                        return Expanded(
                                          flex: columnFlex,
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 4),
                                            alignment: Alignment.centerLeft,
                                            child: Text(
                                              isCancelled ? tr('yes') : tr('no'),
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: isCancelled ? Colors.red : Colors.white,
                                                fontWeight: isCancelled ? FontWeight.bold : FontWeight.normal,
                                              ),
                                            ),
                                          ),
                                        );
                                      }
                                      return Expanded(
                                        flex: columnFlex,
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 4),
                                          alignment: Alignment.centerLeft,
                                          child: _highlightText(value, _searchText),
                                        ),
                                      );
                                    }),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
          ),
          // Footer
          Container(
            height: 24,
            color: AppColors.gridHeader,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            alignment: Alignment.centerLeft,
            child: Text(
              _selectedIndices.isEmpty 
                  ? '${tr('total_rows')} : ${_data.length}'
                  : '${tr('selected')}: ${_selectedIndices.length} / ${tr('total_rows')} : ${_data.length}',
              style: const TextStyle(fontSize: 11, color: Colors.white70),
            ),
          ),
        ],
      ),
    ),
    ),
    );
  }
}
