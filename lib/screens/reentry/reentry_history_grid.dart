import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:material_warehousing_flutter/core/localization/app_translations.dart';
import 'package:material_warehousing_flutter/core/theme/app_colors.dart';
import 'package:material_warehousing_flutter/core/services/api_service.dart';
import 'package:material_warehousing_flutter/core/services/excel_export_service.dart';

/// Grid de historial de reingresos - Estilo igual a WarehousingGridPanel
class ReentryHistoryGrid extends StatefulWidget {
  final LanguageProvider languageProvider;
  
  const ReentryHistoryGrid({
    super.key, 
    required this.languageProvider,
  });

  @override
  State<ReentryHistoryGrid> createState() => ReentryHistoryGridState();
}

class ReentryHistoryGridState extends State<ReentryHistoryGrid> with AutomaticKeepAliveClientMixin {
  List<Map<String, dynamic>> _data = [];
  List<Map<String, dynamic>> _originalData = [];
  bool _isLoading = true;
  bool _showSearchBar = false;
  String _searchText = '';
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final FocusNode _keyboardFocusNode = FocusNode();
  final ScrollController _horizontalScrollController = ScrollController();
  final ScrollController _verticalScrollController = ScrollController();
  
  // Filtro de fechas
  DateTime _fechaInicio = DateTime.now();
  DateTime _fechaFin = DateTime.now();
  bool _filterEnabled = true;
  final TextEditingController _fechaInicioController = TextEditingController();
  final TextEditingController _fechaFinController = TextEditingController();
  final TextEditingController _lotNoController = TextEditingController();
  
  // Índices de filas seleccionadas
  Set<int> _selectedIndices = {};
  int? _lastSelectedIndex;
  
  // Ordenamiento
  String? _sortColumn;
  bool _sortAscending = true;
  
  // Filtros activos por columna
  Map<String, String?> _columnFilters = {};
  
  // Proporciones de columna redimensionables
  List<double> _columnFlexFactors = [];
  static const String _columnWidthsKey = 'reentry_history_grid_flex';
  int? _resizingColumn;
  double _resizeStartX = 0;
  double _resizeStartFlex = 0;
  
  @override
  bool get wantKeepAlive => true;
  
  String tr(String key) => widget.languageProvider.tr(key);

  // Definición de columnas
  List<Map<String, dynamic>> get _columns => [
    {'field': 'codigo_material_recibido', 'header': tr('warehousing_code'), 'flex': 3.5},
    {'field': 'numero_parte', 'header': tr('part_number'), 'flex': 3.0},
    {'field': 'especificacion', 'header': tr('specification'), 'flex': 3.0},
    {'field': 'cantidad_actual', 'header': tr('quantity'), 'flex': 2.0},
    {'field': 'ubicacion_anterior', 'header': tr('previous_location'), 'flex': 2.5},
    {'field': 'ubicacion_salida', 'header': tr('new_location'), 'flex': 2.5},
    {'field': 'fecha_reingreso', 'header': tr('reentry_date'), 'flex': 3.0},
    {'field': 'usuario_reingreso', 'header': tr('user'), 'flex': 2.5},
    {'field': 'cliente', 'header': tr('customer'), 'flex': 2.5},
    {'field': 'numero_lote_material', 'header': tr('lot_number'), 'flex': 2.5},
  ];

  @override
  void initState() {
    super.initState();
    _loadColumnWidths();
    _updateDateControllers();
    _loadData();
  }
  
  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    _keyboardFocusNode.dispose();
    _horizontalScrollController.dispose();
    _verticalScrollController.dispose();
    _fechaInicioController.dispose();
    _fechaFinController.dispose();
    _lotNoController.dispose();
    super.dispose();
  }
  
  void _updateDateControllers() {
    _fechaInicioController.text = _formatDate(_fechaInicio);
    _fechaFinController.text = _formatDate(_fechaFin);
  }
  
  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }
  
  Future<void> _selectFechaInicio() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _fechaInicio,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() {
        _fechaInicio = picked;
        _fechaInicioController.text = _formatDate(picked);
      });
    }
  }
  
  Future<void> _selectFechaFin() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _fechaFin,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() {
        _fechaFin = picked;
        _fechaFinController.text = _formatDate(picked);
      });
    }
  }
  
  void _onSearchPressed() {
    final texto = _lotNoController.text.isNotEmpty ? _lotNoController.text : null;
    if (_filterEnabled) {
      _loadDataWithDateFilter(_fechaInicio, _fechaFin, texto: texto);
    } else {
      _loadDataWithTexto(texto);
    }
  }
  
  Future<void> _exportToExcel() async {
    if (_data.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(tr('no_data_to_export')),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    
    final headers = [
      tr('warehousing_code'),
      tr('part_number'),
      tr('specification'),
      tr('quantity'),
      tr('previous_location'),
      tr('new_location'),
      tr('reentry_date'),
      tr('user'),
      tr('customer'),
      tr('lot_number'),
    ];
    
    final fieldMapping = [
      'codigo_material_recibido',
      'numero_parte',
      'especificacion',
      'cantidad_actual',
      'ubicacion_anterior',
      'ubicacion_salida',
      'fecha_reingreso',
      'usuario_reingreso',
      'cliente',
      'numero_lote_material',
    ];
    
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Row(
          children: [
            SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
            SizedBox(width: 12),
            Text('Exportando a Excel...'),
          ],
        ),
        duration: Duration(seconds: 2),
      ),
    );
    
    final success = await ExcelExportService.exportToExcel(
      data: _data,
      headers: headers,
      fieldMapping: fieldMapping,
      fileName: 'Reentry_History',
    );
    
    if (mounted) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success 
            ? '✓ Excel exportado correctamente' 
            : 'Exportación cancelada'),
          backgroundColor: success ? Colors.green : Colors.grey,
        ),
      );
    }
  }
  
  InputDecoration _dateDecoration() {
    return const InputDecoration(
      isDense: true,
      contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      filled: true,
      fillColor: AppColors.fieldBackground,
      border: OutlineInputBorder(
        borderSide: BorderSide(color: AppColors.border, width: 1),
      ),
      enabledBorder: OutlineInputBorder(
        borderSide: BorderSide(color: AppColors.border, width: 1),
      ),
    );
  }
  
  Future<void> _loadColumnWidths() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getString(_columnWidthsKey);
      if (stored != null) {
        final List<dynamic> decoded = jsonDecode(stored);
        if (decoded.length == _columns.length) {
          setState(() {
            _columnFlexFactors = decoded.map((e) => (e as num).toDouble()).toList();
          });
          return;
        }
      }
    } catch (e) {
      debugPrint('Error loading column flex factors: $e');
    }
    setState(() {
      _columnFlexFactors = _columns.map((c) => (c['flex'] as num).toDouble()).toList();
    });
  }
  
  Future<void> _saveColumnWidths() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_columnWidthsKey, jsonEncode(_columnFlexFactors));
    } catch (e) {
      debugPrint('Error saving column flex factors: $e');
    }
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final data = await ApiService.getReentryHistory(limit: 500);
      if (mounted) {
        setState(() {
          _originalData = List.from(data);
          _data = data;
          _isLoading = false;
          if (_columnFilters.isNotEmpty) {
            _applyAllFilters();
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }
  
  Future<void> _loadDataWithDateFilter(DateTime startDate, DateTime endDate, {String? texto}) async {
    setState(() => _isLoading = true);
    try {
      final data = await ApiService.getReentryHistory(
        limit: 500,
        startDate: startDate,
        endDate: endDate,
        texto: texto,
      );
      if (mounted) {
        setState(() {
          _originalData = List.from(data);
          _data = data;
          _isLoading = false;
          if (_columnFilters.isNotEmpty) {
            _applyAllFilters();
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }
  
  Future<void> _loadDataWithTexto(String? texto) async {
    setState(() => _isLoading = true);
    try {
      final data = await ApiService.getReentryHistory(
        limit: 500,
        texto: texto,
      );
      if (mounted) {
        setState(() {
          _originalData = List.from(data);
          _data = data;
          _isLoading = false;
          if (_columnFilters.isNotEmpty) {
            _applyAllFilters();
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }
  
  Future<void> reloadData() async {
    _selectedIndices.clear();
    await _loadData();
  }

  // Ordenar datos por columna
  void _sortByColumn(String field, bool ascending) {
    setState(() {
      _sortColumn = field;
      _sortAscending = ascending;
      _data.sort((a, b) {
        var aValue = a[field]?.toString() ?? '';
        var bValue = b[field]?.toString() ?? '';
        
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
  
  void _clearSorting() {
    setState(() {
      _sortColumn = null;
      _sortAscending = true;
      _data = List.from(_originalData);
    });
  }
  
  // Aplicar filtro a una columna
  void _applyFilter(String field, String? value) {
    setState(() {
      if (value == null || value.isEmpty) {
        _columnFilters.remove(field);
      } else {
        _columnFilters[field] = value;
      }
      _applyAllFilters();
    });
  }
  
  void _clearFilter(String field) {
    setState(() {
      _columnFilters.remove(field);
      _applyAllFilters();
    });
  }
  
  void _clearAllFilters() {
    setState(() {
      _columnFilters.clear();
      _data = List.from(_originalData);
    });
  }
  
  void _applyAllFilters() {
    var filtered = List<Map<String, dynamic>>.from(_originalData);
    
    for (final entry in _columnFilters.entries) {
      final field = entry.key;
      final filterValue = entry.value;
      if (filterValue != null && filterValue.isNotEmpty) {
        filtered = filtered.where((row) {
          final cellValue = row[field]?.toString() ?? '';
          return cellValue.toLowerCase() == filterValue.toLowerCase();
        }).toList();
      }
    }
    
    // Aplicar búsqueda global
    if (_searchText.isNotEmpty) {
      filtered = filtered.where((row) {
        return row.values.any((value) =>
          value?.toString().toLowerCase().contains(_searchText.toLowerCase()) ?? false
        );
      }).toList();
    }
    
    setState(() {
      _data = filtered;
    });
  }
  
  // Mostrar menú contextual de columna
  void _showColumnContextMenu(BuildContext context, Offset position, String field, String header, int colIndex) {
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
          value: 'filter',
          height: 32,
          child: Row(
            children: [
              Icon(Icons.filter_list, size: 16, 
                color: _columnFilters.containsKey(field) ? Colors.orange : Colors.white70),
              const SizedBox(width: 8),
              Text('Filter...', 
                style: TextStyle(fontSize: 12, 
                  color: _columnFilters.containsKey(field) ? Colors.orange : Colors.white)),
            ],
          ),
        ),
        if (_columnFilters.containsKey(field))
          PopupMenuItem(
            value: 'clear_filter',
            height: 32,
            child: const Row(
              children: [
                Icon(Icons.filter_list_off, size: 16, color: Colors.orange),
                SizedBox(width: 8),
                Text('Clear Filter', style: TextStyle(fontSize: 12, color: Colors.orange)),
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
          _clearFilter(field);
          break;
      }
    });
  }
  
  void _showFilterDialog(BuildContext context, String field, String header) {
    // Obtener valores únicos de la columna
    final values = _originalData
        .map((row) => row[field]?.toString() ?? '')
        .where((v) => v.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    
    final currentFilter = _columnFilters[field];
    
    showDialog(
      context: context,
      builder: (context) {
        String searchFilter = '';
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final filteredValues = values.where((v) => 
              v.toLowerCase().contains(searchFilter.toLowerCase())
            ).toList();
            
            return AlertDialog(
              backgroundColor: const Color(0xFF2D2D30),
              title: Text('Filter: $header', style: const TextStyle(color: Colors.white, fontSize: 14)),
              content: SizedBox(
                width: 300,
                height: 400,
                child: Column(
                  children: [
                    TextField(
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                      decoration: InputDecoration(
                        hintText: 'Search...',
                        hintStyle: const TextStyle(color: Colors.white38),
                        prefixIcon: const Icon(Icons.search, color: Colors.white38, size: 18),
                        filled: true,
                        fillColor: const Color(0xFF3C3C3C),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(4),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                      ),
                      onChanged: (v) => setDialogState(() => searchFilter = v),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: ListView(
                        children: [
                          ListTile(
                            dense: true,
                            title: const Text('(All)', style: TextStyle(color: Colors.white70, fontSize: 12)),
                            selected: currentFilter == null,
                            selectedTileColor: Colors.blue.withOpacity(0.2),
                            onTap: () {
                              Navigator.pop(context);
                              _clearFilter(field);
                            },
                          ),
                          ...filteredValues.map((value) => ListTile(
                            dense: true,
                            title: Text(value, style: const TextStyle(color: Colors.white, fontSize: 12)),
                            selected: currentFilter == value,
                            selectedTileColor: Colors.blue.withOpacity(0.2),
                            onTap: () {
                              Navigator.pop(context);
                              _applyFilter(field, value);
                            },
                          )),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    
    return Focus(
      focusNode: _keyboardFocusNode,
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent) {
          // Ctrl+F para buscar
          if (HardwareKeyboard.instance.isControlPressed && event.logicalKey == LogicalKeyboardKey.keyF) {
            setState(() => _showSearchBar = !_showSearchBar);
            if (_showSearchBar) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                _searchFocusNode.requestFocus();
              });
            }
            return KeyEventResult.handled;
          }
          // Escape para cerrar búsqueda
          if (event.logicalKey == LogicalKeyboardKey.escape && _showSearchBar) {
            setState(() {
              _showSearchBar = false;
              _searchText = '';
              _searchController.clear();
              _applyAllFilters();
            });
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: Column(
        children: [
          // Barra de filtro de fecha y exportar Excel
          Container(
            color: AppColors.panelBackground,
            padding: const EdgeInsets.fromLTRB(4, 4, 4, 4),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  decoration: BoxDecoration(
                    border: Border.all(color: AppColors.border, width: 1),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Checkbox(
                        value: _filterEnabled,
                        onChanged: (v) => setState(() => _filterEnabled = v ?? true),
                        side: const BorderSide(color: AppColors.border),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        tr('reentry_date'),
                        style: const TextStyle(fontSize: 11),
                      ),
                      const SizedBox(width: 4),
                      // Fecha inicio
                      SizedBox(
                        width: 100,
                        child: InkWell(
                          onTap: _selectFechaInicio,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                            decoration: BoxDecoration(
                              color: AppColors.fieldBackground,
                              border: Border.all(color: AppColors.border),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(_formatDate(_fechaInicio), style: const TextStyle(fontSize: 11)),
                                const Icon(Icons.calendar_today, size: 14, color: Colors.white70),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Text('~', style: TextStyle(fontSize: 12)),
                      const SizedBox(width: 4),
                      // Fecha fin
                      SizedBox(
                        width: 100,
                        child: InkWell(
                          onTap: _selectFechaFin,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                            decoration: BoxDecoration(
                              color: AppColors.fieldBackground,
                              border: Border.all(color: AppColors.border),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(_formatDate(_fechaFin), style: const TextStyle(fontSize: 11)),
                                const Icon(Icons.calendar_today, size: 14, color: Colors.white70),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(tr('lot_no'), style: const TextStyle(fontSize: 11)),
                      const SizedBox(width: 4),
                      SizedBox(
                        width: 110,
                        child: TextFormField(
                          controller: _lotNoController,
                          decoration: _dateDecoration(),
                          style: const TextStyle(fontSize: 11),
                          onFieldSubmitted: (_) => _onSearchPressed(),
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                SizedBox(
                  height: 26,
                  child: ElevatedButton(
                    onPressed: _onSearchPressed,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 18),
                      backgroundColor: AppColors.buttonSearch,
                    ),
                    child: Text(tr('search'), style: const TextStyle(fontSize: 11)),
                  ),
                ),
                const SizedBox(width: 6),
                SizedBox(
                  height: 26,
                  child: ElevatedButton(
                    onPressed: _exportToExcel,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 18),
                      backgroundColor: AppColors.buttonExcel,
                    ),
                    child: Text(tr('excel_export'), style: const TextStyle(fontSize: 11)),
                  ),
                ),
              ],
            ),
          ),
          // Barra de búsqueda
          if (_showSearchBar)
            Container(
              height: 36,
              color: const Color(0xFF2D2D30),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                children: [
                  const Icon(Icons.search, color: Colors.white54, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      focusNode: _searchFocusNode,
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                      decoration: const InputDecoration(
                        hintText: 'Search... (Ctrl+F)',
                        hintStyle: TextStyle(color: Colors.white38),
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(vertical: 8),
                      ),
                      onChanged: (value) {
                        setState(() => _searchText = value);
                        _applyAllFilters();
                      },
                    ),
                  ),
                  if (_searchText.isNotEmpty)
                    Text(
                      '${_data.length} results',
                      style: const TextStyle(color: Colors.white54, fontSize: 11),
                    ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white54, size: 18),
                    onPressed: () {
                      setState(() {
                        _showSearchBar = false;
                        _searchText = '';
                        _searchController.clear();
                        _applyAllFilters();
                      });
                    },
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  ),
                ],
              ),
            ),
          // Barra de filtros activos
          if (_columnFilters.isNotEmpty)
            Container(
              height: 28,
              color: Colors.orange.withOpacity(0.1),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  const Icon(Icons.filter_list, color: Colors.orange, size: 14),
                  const SizedBox(width: 8),
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: _columnFilters.entries.map((e) {
                          final colDef = _columns.firstWhere(
                            (c) => c['field'] == e.key,
                            orElse: () => {'header': e.key},
                          );
                          return Container(
                            margin: const EdgeInsets.only(right: 8),
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.orange.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  '${colDef['header']}: ${e.value}',
                                  style: const TextStyle(color: Colors.orange, fontSize: 10),
                                ),
                                const SizedBox(width: 4),
                                InkWell(
                                  onTap: () => _clearFilter(e.key),
                                  child: const Icon(Icons.close, color: Colors.orange, size: 12),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: _clearAllFilters,
                    child: const Text('Clear All', style: TextStyle(fontSize: 10, color: Colors.orange)),
                  ),
                ],
              ),
            ),
          // Grid
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _data.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.history, size: 64, color: Colors.white.withOpacity(0.15)),
                            const SizedBox(height: 12),
                            Text(
                              tr('no_reentry_history'),
                              style: const TextStyle(color: Colors.white38, fontSize: 14),
                            ),
                          ],
                        ),
                      )
                    : _buildGrid(),
          ),
          // Footer con conteo
          Container(
            height: 24,
            color: const Color(0xFF2D2D30),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Text(
                  '${_data.length} records',
                  style: const TextStyle(color: Colors.white54, fontSize: 11),
                ),
                if (_selectedIndices.isNotEmpty) ...[
                  const SizedBox(width: 16),
                  Text(
                    '${_selectedIndices.length} selected',
                    style: const TextStyle(color: Colors.blue, fontSize: 11),
                  ),
                ],
                const Spacer(),
                Text(
                  'Ctrl+F to search',
                  style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 10),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGrid() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final totalFlex = _columnFlexFactors.fold<double>(0, (sum, f) => sum + f);
        final availableWidth = constraints.maxWidth;
        
        // Calcular anchos de columna basados en flex
        final columnWidths = <double>[];
        for (int i = 0; i < _columnFlexFactors.length; i++) {
          columnWidths.add((_columnFlexFactors[i] / totalFlex) * availableWidth.clamp(800, 2000));
        }
        
        final totalWidth = columnWidths.fold<double>(0, (sum, w) => sum + w);
        
        return Scrollbar(
          controller: _horizontalScrollController,
          thumbVisibility: true,
          child: SingleChildScrollView(
            controller: _horizontalScrollController,
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: totalWidth,
              child: Column(
                children: [
                  // Header
                  _buildHeader(columnWidths),
                  // Data rows
                  Expanded(
                    child: Scrollbar(
                      controller: _verticalScrollController,
                      thumbVisibility: true,
                      child: ListView.builder(
                        controller: _verticalScrollController,
                        itemCount: _data.length,
                        itemBuilder: (context, index) => _buildDataRow(index, columnWidths),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildHeader(List<double> columnWidths) {
    return Container(
      height: 32,
      decoration: BoxDecoration(
        color: AppColors.gridHeader,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: List.generate(_columns.length, (index) {
          final col = _columns[index];
          final field = col['field'] as String;
          final header = col['header'] as String;
          final width = columnWidths[index];
          final hasFilter = _columnFilters.containsKey(field);
          final isSorted = _sortColumn == field;
          
          return GestureDetector(
            onTapDown: (details) {
              _showColumnContextMenu(context, details.globalPosition, field, header, index);
            },
            onHorizontalDragStart: (details) {
              _resizingColumn = index;
              _resizeStartX = details.globalPosition.dx;
              _resizeStartFlex = _columnFlexFactors[index];
            },
            onHorizontalDragUpdate: (details) {
              if (_resizingColumn != null) {
                final delta = details.globalPosition.dx - _resizeStartX;
                final newFlex = (_resizeStartFlex + delta / 50).clamp(1.0, 10.0);
                setState(() {
                  _columnFlexFactors[_resizingColumn!] = newFlex;
                });
              }
            },
            onHorizontalDragEnd: (_) {
              _resizingColumn = null;
              _saveColumnWidths();
            },
            child: Container(
              width: width,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                border: Border(right: BorderSide(color: AppColors.border.withOpacity(0.5))),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      header,
                      style: TextStyle(
                        color: hasFilter ? Colors.orange : Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (isSorted)
                    Icon(
                      _sortAscending ? Icons.arrow_upward : Icons.arrow_downward,
                      size: 12,
                      color: Colors.blue,
                    ),
                  if (hasFilter)
                    const Icon(Icons.filter_list, size: 12, color: Colors.orange),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildDataRow(int index, List<double> columnWidths) {
    final row = _data[index];
    final isSelected = _selectedIndices.contains(index);
    final isEven = index % 2 == 0;
    
    return GestureDetector(
      onTap: () {
        setState(() {
          if (HardwareKeyboard.instance.isControlPressed) {
            if (_selectedIndices.contains(index)) {
              _selectedIndices.remove(index);
            } else {
              _selectedIndices.add(index);
            }
          } else if (HardwareKeyboard.instance.isShiftPressed && _lastSelectedIndex != null) {
            final start = _lastSelectedIndex! < index ? _lastSelectedIndex! : index;
            final end = _lastSelectedIndex! > index ? _lastSelectedIndex! : index;
            _selectedIndices.addAll(List.generate(end - start + 1, (i) => start + i));
          } else {
            _selectedIndices.clear();
            _selectedIndices.add(index);
          }
          _lastSelectedIndex = index;
        });
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
            bottom: BorderSide(color: AppColors.border.withOpacity(0.3)),
            left: isSelected ? const BorderSide(color: Colors.blue, width: 3) : BorderSide.none,
          ),
        ),
        child: Row(
          children: List.generate(_columns.length, (colIndex) {
            final col = _columns[colIndex];
            final field = col['field'] as String;
            final value = row[field];
            final width = columnWidths[colIndex];
            
            return Container(
              width: width,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              alignment: Alignment.centerLeft,
              child: Text(
                _formatCellValue(field, value),
                style: TextStyle(
                  color: _getCellColor(field, value),
                  fontSize: 11,
                  fontFamily: field == 'codigo_material_recibido' ? 'monospace' : null,
                  fontWeight: field == 'ubicacion_salida' ? FontWeight.bold : FontWeight.normal,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            );
          }),
        ),
      ),
    );
  }

  String _formatCellValue(String field, dynamic value) {
    if (value == null) return '-';
    
    if (field == 'fecha_reingreso') {
      try {
        final dt = DateTime.parse(value.toString());
        return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year} '
            '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
      } catch (e) {
        return value.toString();
      }
    }
    
    return value.toString();
  }

  Color _getCellColor(String field, dynamic value) {
    switch (field) {
      case 'ubicacion_anterior':
        return Colors.orange;
      case 'ubicacion_salida':
        return Colors.green;
      case 'cantidad_actual':
        return AppColors.headerTab;
      case 'codigo_material_recibido':
        return Colors.white;
      default:
        return Colors.white70;
    }
  }
}
