import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_warehousing_flutter/core/localization/app_translations.dart';
import 'package:material_warehousing_flutter/core/theme/app_colors.dart';
import 'package:material_warehousing_flutter/core/widgets/grid_footer.dart';
import 'package:material_warehousing_flutter/core/services/api_service.dart';
import 'package:material_warehousing_flutter/core/services/excel_export_service.dart';
import 'package:material_warehousing_flutter/core/services/printer_service.dart';
import 'package:material_warehousing_flutter/core/widgets/printer_settings_dialog.dart';
import 'package:material_warehousing_flutter/core/widgets/resizable_grid_header.dart';

class OutgoingHistoryView extends StatefulWidget {
  final LanguageProvider languageProvider;
  
  const OutgoingHistoryView({super.key, required this.languageProvider});

  @override
  State<OutgoingHistoryView> createState() => OutgoingHistoryViewState();
}

class OutgoingHistoryViewState extends State<OutgoingHistoryView> with ResizableColumnsMixin {
  // Datos de la búsqueda
  List<Map<String, dynamic>> _outgoingData = [];
  List<Map<String, dynamic>> _filteredData = [];
  bool _isLoading = false;
  
  // Filtros de fecha
  DateTime _startDate = DateTime.now();
  DateTime _endDate = DateTime.now();
  final TextEditingController _lotNoController = TextEditingController();
  bool _useDateFilter = true;
  
  // Filtros de columna y ordenamiento
  Map<String, String?> _columnFilters = {};
  String? _sortColumn;
  bool _sortAscending = true;
  
  // Búsqueda Ctrl+F
  bool _showSearchBar = false;
  String _searchText = '';
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final FocusNode _keyboardFocusNode = FocusNode();
  
  // GlobalKeys para filtros
  final Map<String, GlobalKey> _filterKeys = {};
  
  // Selección múltiple para reimpresión
  Set<int> _selectedIndices = {};
  int? _lastSelectedIndex;
  static const int _maxSelection = 100;
  
  // Campos
  final List<String> _fields = ['fecha_salida', 'fecha_salida_hora', 'proceso_salida', 'linea_proceso', 'codigo_material_recibido', 'numero_parte', 'cantidad_salida', 'numero_lote', 'especificacion_material', 'depto_salida', 'vendedor', 'comparacion_escaneada', 'comparacion_resultado', 'usuario_registro'];

  String tr(String key) => widget.languageProvider.tr(key);
  
  List<String> get _headers => [tr('outgoing_date'), 'Hora', tr('out_process'), tr('production_line'), tr('warehousing_code'), tr('part_number'), tr('qty'), tr('material_lot_no'), tr('material_spec'), tr('outgoing_department'), tr('vendor'), tr('comparison_scan'), 'Resultado', tr('registered_by')];

  @override
  void initState() {
    super.initState();
    for (var field in _fields) {
      _filterKeys[field] = GlobalKey();
    }
    initColumnFlex(14, 'outgoing_history', defaultFlexValues: [2.0, 1.5, 2.0, 2.0, 3.0, 2.0, 1.0, 2.0, 2.0, 2.0, 2.0, 2.0, 1.5, 2.0]);
    _search();
  }

  @override
  void dispose() {
    _lotNoController.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    _keyboardFocusNode.dispose();
    super.dispose();
  }

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }

  String _formatDateForApi(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  Future<void> _selectStartDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      builder: (context, child) {
        return Theme(
          data: ThemeData.dark().copyWith(
            colorScheme: ColorScheme.dark(
              primary: AppColors.headerTab,
              onPrimary: Colors.white,
              surface: AppColors.panelBackground,
              onSurface: Colors.white,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() => _startDate = picked);
    }
  }

  Future<void> _selectEndDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _endDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      builder: (context, child) {
        return Theme(
          data: ThemeData.dark().copyWith(
            colorScheme: ColorScheme.dark(
              primary: AppColors.headerTab,
              onPrimary: Colors.white,
              surface: AppColors.panelBackground,
              onSurface: Colors.white,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() => _endDate = picked);
    }
  }

  /// Método público para agregar un nuevo registro sin recargar todo
  void addOutgoingRecord(Map<String, dynamic> record) {
    if (!mounted) return;
    setState(() {
      // Insertar al inicio de la lista
      _outgoingData.insert(0, record);
      _applyFiltersAndSort();
    });
  }

  /// Método público para refrescar la búsqueda
  Future<void> refresh() async {
    await _search();
  }

  // ============ MÉTODOS DE SELECCIÓN MÚLTIPLE ============
  
  /// Obtener todas las filas seleccionadas
  List<Map<String, dynamic>> getSelectedItems() {
    // Usar displayData para obtener los items filtrados actuales
    final displayData = _getDisplayData();
    return _selectedIndices
        .where((i) => i >= 0 && i < displayData.length)
        .map((i) => displayData[i])
        .toList();
  }

  /// Limpiar selección
  void clearSelection() {
    setState(() {
      _selectedIndices.clear();
      _lastSelectedIndex = null;
    });
  }

  /// Seleccionar/deseleccionar todos (máximo _maxSelection)
  void toggleSelectAll() {
    final displayData = _getDisplayData();
    setState(() {
      if (_selectedIndices.length == displayData.length || _selectedIndices.length >= _maxSelection) {
        _selectedIndices.clear();
      } else {
        // Seleccionar hasta el máximo permitido
        final maxToSelect = displayData.length > _maxSelection ? _maxSelection : displayData.length;
        _selectedIndices = Set<int>.from(List.generate(maxToSelect, (i) => i));
      }
    });
  }

  /// Verificar si hay selección
  bool hasSelectedRow() => _selectedIndices.isNotEmpty;

  /// Toggle selección con soporte para Shift (rango)
  void _toggleSelection(int index, bool isShiftPressed) {
    final displayData = _getDisplayData();
    setState(() {
      if (isShiftPressed && _lastSelectedIndex != null) {
        // Selección en rango con Shift
        final start = _lastSelectedIndex! < index ? _lastSelectedIndex! : index;
        final end = _lastSelectedIndex! > index ? _lastSelectedIndex! : index;
        for (int i = start; i <= end; i++) {
          if (_selectedIndices.length < _maxSelection) {
            _selectedIndices.add(i);
          }
        }
        _lastSelectedIndex = index;
      } else {
        // Selección individual normal
        if (_selectedIndices.contains(index)) {
          _selectedIndices.remove(index);
        } else {
          if (_selectedIndices.length < _maxSelection) {
            _selectedIndices.add(index);
          } else {
            // Mostrar mensaje de límite alcanzado
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('⚠ ${tr('max_selection_reached')} ($_maxSelection)'),
                backgroundColor: Colors.orange,
                duration: const Duration(seconds: 2),
              ),
            );
          }
        }
        _lastSelectedIndex = index;
      }
    });
  }

  /// Obtener datos filtrados para display
  List<Map<String, dynamic>> _getDisplayData() {
    var baseData = _filteredData.isEmpty && _columnFilters.isEmpty && _sortColumn == null 
        ? _outgoingData 
        : _filteredData;
    
    if (_searchText.isEmpty) return baseData;
    
    return baseData.where((row) {
      return _fields.any((field) {
        final value = _getFieldValue(row, field).toLowerCase();
        return value.contains(_searchText.toLowerCase());
      });
    }).toList();
  }

  /// Reimprimir etiquetas seleccionadas
  Future<void> _reprintSelected() async {
    if (_selectedIndices.isEmpty) return;
    
    // Verificar impresora configurada
    if (!PrinterService.hasPrinterConfigured) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('⚠ ${tr('configure_printer_first')}'),
          backgroundColor: Colors.orange,
        ),
      );
      PrinterSettingsDialog.show(context);
      return;
    }
    
    final selectedItems = getSelectedItems();
    final total = selectedItems.length;
    int printed = 0;
    int failed = 0;
    
    // Mostrar progreso
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
            const SizedBox(width: 12),
            Text('${tr('printing')}... 0/$total'),
          ],
        ),
        duration: const Duration(seconds: 30),
      ),
    );
    
    for (final item in selectedItems) {
      final codigo = item['codigo_material_recibido']?.toString() ?? '';
      final fechaRaw = item['fecha_salida']?.toString() ?? '';
      final especificacion = item['especificacion_material']?.toString() ?? '';
      final cantidad = item['cantidad_salida']?.toString() ?? '';
      
      // Formatear fecha
      String fecha = '';
      try {
        final isoValue = fechaRaw.contains('T') ? fechaRaw : fechaRaw.replaceFirst(' ', 'T');
        final date = DateTime.parse(isoValue);
        fecha = '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
      } catch (_) {
        fecha = fechaRaw;
      }
      
      final success = await PrinterService.printLabel(
        codigo: codigo,
        fecha: fecha,
        especificacion: especificacion,
        cantidadActual: cantidad,
      );
      
      if (success) {
        printed++;
      } else {
        failed++;
      }
    }
    
    // Ocultar progreso y mostrar resultado
    if (mounted) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      
      if (failed == 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✓ $printed ${tr('labels_printed')}'),
            backgroundColor: Colors.green,
          ),
        );
        // Limpiar selección después de reimprimir exitosamente
        clearSelection();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('⚠ $printed ${tr('printed')}, $failed ${tr('failed')}'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    }
  }

  // ============ FIN MÉTODOS DE SELECCIÓN ============

  Future<void> _search() async {
    setState(() => _isLoading = true);
    
    final results = await ApiService.searchOutgoing(
      fechaInicio: _useDateFilter ? _formatDateForApi(_startDate) : null,
      fechaFin: _useDateFilter ? _formatDateForApi(_endDate) : null,
      texto: _lotNoController.text.isNotEmpty ? _lotNoController.text : null,
    );
    
    if (mounted) {
      setState(() {
        _outgoingData = results;
        _isLoading = false;
        _applyFiltersAndSort();
      });
    }
  }

  Future<void> _exportToExcel() async {
    if (_filteredData.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr('no_data')), backgroundColor: Colors.orange),
      );
      return;
    }
    
    // Headers y mapeo de campos para Material Outgoing
    final headers = [
      tr('outgoing_date'),
      'Hora',
      tr('out_process'),
      tr('warehousing_code'),
      tr('part_number'),
      tr('qty'),
      tr('material_lot_no'),
      tr('material_spec'),
      tr('outgoing_department'),
      tr('comparison_scan'),
      'Resultado',
      tr('registered_by'),
    ];
    
    final fieldMapping = [
      'fecha_salida',
      'fecha_salida_hora',
      'proceso_salida',
      'codigo_material_recibido',
      'numero_parte',
      'cantidad_salida',
      'numero_lote',
      'especificacion_material',
      'depto_salida',
      'comparacion_escaneada',
      'comparacion_resultado',
      'usuario_registro',
    ];
    
    // Mostrar indicador de carga
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
            const SizedBox(width: 12),
            Text(tr('printing_to').replaceAll('Printing to', 'Exporting to Excel...')),
          ],
        ),
        duration: const Duration(seconds: 2),
      ),
    );
    
    final success = await ExcelExportService.exportToExcel(
      data: _filteredData,
      headers: headers,
      fieldMapping: fieldMapping,
      fileName: 'Material_Outgoing_History',
    );
    
    if (mounted) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success 
            ? '✓ Excel exported successfully' 
            : 'Export cancelled'),
          backgroundColor: success ? Colors.green : Colors.grey,
        ),
      );
    }
  }

  void _toggleSearchBar() {
    setState(() {
      _showSearchBar = !_showSearchBar;
      if (_showSearchBar) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _searchFocusNode.requestFocus();
        });
      } else {
        _searchText = '';
        _searchController.clear();
      }
    });
  }

  void _onSearchTextChanged(String text) {
    setState(() => _searchText = text);
  }

  void _applyFiltersAndSort() {
    List<Map<String, dynamic>> result = List.from(_outgoingData);
    
    // Aplicar filtros de columna
    _columnFilters.forEach((field, value) {
      if (value != null && value.isNotEmpty) {
        result = result.where((row) {
          final fieldValue = _getFieldValue(row, field);
          if (value == '__BLANKS__') {
            return fieldValue.isEmpty;
          } else if (value == '__NON_BLANKS__') {
            return fieldValue.isNotEmpty;
          }
          return fieldValue.toLowerCase() == value.toLowerCase();
        }).toList();
      }
    });
    
    // Aplicar ordenamiento
    if (_sortColumn != null) {
      result.sort((a, b) {
        final aVal = _getFieldValue(a, _sortColumn!);
        final bVal = _getFieldValue(b, _sortColumn!);
        return _sortAscending ? aVal.compareTo(bVal) : bVal.compareTo(aVal);
      });
    }
    
    _filteredData = result;
  }

  String _getFieldValue(Map<String, dynamic> row, String field) {
    if (field == 'fecha_salida' && row['fecha_salida'] != null) {
      try {
        final rawValue = row['fecha_salida'].toString();
        final isoValue = rawValue.contains('T') ? rawValue : rawValue.replaceFirst(' ', 'T');
        final date = DateTime.parse(isoValue);
        return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
      } catch (_) {}
    }
    if (field == 'fecha_salida_hora' && row['fecha_salida'] != null) {
      try {
        final rawValue = row['fecha_salida'].toString();
        final isoValue = rawValue.contains('T') ? rawValue : rawValue.replaceFirst(' ', 'T');
        final date = DateTime.parse(isoValue);
        return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
      } catch (_) {}
    }
    return row[field]?.toString() ?? '';
  }

  void _sortByColumn(String field, bool ascending) {
    setState(() {
      _sortColumn = field;
      _sortAscending = ascending;
      _applyFiltersAndSort();
    });
  }

  void _clearSorting() {
    setState(() {
      _sortColumn = null;
      _sortAscending = true;
      _applyFiltersAndSort();
    });
  }

  void _applyFilter(String field, String? value) {
    setState(() {
      if (value == null || value.isEmpty) {
        _columnFilters.remove(field);
      } else {
        _columnFilters[field] = value;
      }
      _applyFiltersAndSort();
    });
  }

  void _showColumnContextMenu(BuildContext context, String field, int fieldIndex) {
    final RenderBox? renderBox = _filterKeys[field]?.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;
    final position = renderBox.localToGlobal(Offset.zero);
    final size = renderBox.size;
    
    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(position.dx, position.dy + size.height, position.dx + 150, position.dy + size.height + 200),
      items: [
        PopupMenuItem(value: 'sort_asc', child: Row(children: [const Icon(Icons.arrow_upward, size: 16), const SizedBox(width: 8), Text(tr('sort_ascending'))])),
        PopupMenuItem(value: 'sort_desc', child: Row(children: [const Icon(Icons.arrow_downward, size: 16), const SizedBox(width: 8), Text(tr('sort_descending'))])),
        PopupMenuItem(value: 'clear_sort', child: Row(children: [const Icon(Icons.clear, size: 16), const SizedBox(width: 8), Text(tr('clear_sorting'))])),
        const PopupMenuDivider(),
        PopupMenuItem(value: 'filter', child: Row(children: [const Icon(Icons.filter_list, size: 16), const SizedBox(width: 8), Text(tr('filter_by_column'))])),
        PopupMenuItem(value: 'clear_filter', child: Row(children: [const Icon(Icons.filter_list_off, size: 16), const SizedBox(width: 8), Text(tr('clear_filter'))])),
        const PopupMenuDivider(),
        PopupMenuItem(value: 'search', child: Row(children: [const Icon(Icons.search, size: 16), const SizedBox(width: 8), Text(tr('search'))])),
      ],
    ).then((value) {
      if (value == 'sort_asc') _sortByColumn(field, true);
      else if (value == 'sort_desc') _sortByColumn(field, false);
      else if (value == 'clear_sort') _clearSorting();
      else if (value == 'filter') _showFilterDropdown(context, field);
      else if (value == 'clear_filter') _applyFilter(field, null);
      else if (value == 'search') _toggleSearchBar();
    });
  }

  void _showFilterDropdown(BuildContext context, String field) {
    final RenderBox? renderBox = _filterKeys[field]?.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;
    final position = renderBox.localToGlobal(Offset.zero);
    final size = renderBox.size;
    
    final header = _headers[_fields.indexOf(field)];
    
    // Obtener valores únicos
    final Set<String> uniqueValues = {};
    bool hasBlanks = false;
    
    for (var row in _outgoingData) {
      final value = _getFieldValue(row, field);
      if (value.isEmpty) {
        hasBlanks = true;
      } else {
        uniqueValues.add(value);
      }
    }
    
    final sortedValues = uniqueValues.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    final currentFilter = _columnFilters[field];
    
    showDialog(
      context: context,
      barrierColor: Colors.transparent,
      builder: (ctx) {
        String searchText = '';
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            final filteredValues = sortedValues
                .where((v) => v.toLowerCase().contains(searchText.toLowerCase()))
                .toList();
            
            return Stack(
              children: [
                Positioned.fill(child: GestureDetector(onTap: () => Navigator.pop(ctx), child: Container(color: Colors.transparent))),
                Positioned(
                  left: position.dx + (size.width / 2) - 100,
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
                          Padding(
                            padding: const EdgeInsets.all(8),
                            child: Text('Filter: $header', style: const TextStyle(color: Colors.white, fontSize: 12)),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
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
                              onChanged: (value) => setDialogState(() => searchText = value),
                            ),
                          ),
                          const Divider(height: 8, color: Color(0xFF3C3C3C)),
                          Flexible(
                            child: SingleChildScrollView(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (currentFilter != null)
                                    _buildFilterOption(ctx, '(Clear Filter)', false, Icons.clear, Colors.orange, () {
                                      Navigator.pop(ctx);
                                      _applyFilter(field, null);
                                    }),
                                  if (hasBlanks)
                                    _buildFilterOption(ctx, '(Blanks)', currentFilter == '__BLANKS__', null, null, () {
                                      Navigator.pop(ctx);
                                      _applyFilter(field, '__BLANKS__');
                                    }),
                                  _buildFilterOption(ctx, '(Non blanks)', currentFilter == '__NON_BLANKS__', null, null, () {
                                    Navigator.pop(ctx);
                                    _applyFilter(field, '__NON_BLANKS__');
                                  }),
                                  const Divider(height: 1, color: Color(0xFF3C3C3C)),
                                  ...filteredValues.map((value) => _buildFilterOption(
                                    ctx, value, currentFilter == value, null, null, () {
                                      Navigator.pop(ctx);
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

  Widget _highlightText(String text, String searchText) {
    if (searchText.isEmpty) {
      return Text(text, style: const TextStyle(fontSize: 10, color: Colors.white), overflow: TextOverflow.ellipsis, textAlign: TextAlign.center);
    }
    final lowerText = text.toLowerCase();
    final lowerSearch = searchText.toLowerCase();
    final index = lowerText.indexOf(lowerSearch);
    if (index < 0) {
      return Text(text, style: const TextStyle(fontSize: 10, color: Colors.white), overflow: TextOverflow.ellipsis, textAlign: TextAlign.center);
    }
    return RichText(
      overflow: TextOverflow.ellipsis,
      textAlign: TextAlign.center,
      text: TextSpan(
        style: const TextStyle(fontSize: 10, color: Colors.white),
        children: [
          TextSpan(text: text.substring(0, index)),
          TextSpan(text: text.substring(index, index + searchText.length), style: const TextStyle(backgroundColor: Colors.yellow, color: Colors.black)),
          TextSpan(text: text.substring(index + searchText.length)),
        ],
      ),
    );
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

  @override
  Widget build(BuildContext context) {
    // Primero aplicar filtros de columna y ordenamiento
    var baseData = _filteredData.isEmpty && _columnFilters.isEmpty && _sortColumn == null ? _outgoingData : _filteredData;
    
    // Luego filtrar por búsqueda Ctrl+F
    final displayData = _searchText.isEmpty
        ? baseData
        : baseData.where((row) {
            return _fields.any((field) {
              final value = _getFieldValue(row, field).toLowerCase();
              return value.contains(_searchText.toLowerCase());
            });
          }).toList();

    return GestureDetector(
      onTap: () => _keyboardFocusNode.requestFocus(),
      child: Focus(
        focusNode: _keyboardFocusNode,
        autofocus: false,
        onKeyEvent: (node, event) {
          if (event is KeyDownEvent && HardwareKeyboard.instance.isControlPressed && event.logicalKey == LogicalKeyboardKey.keyF) {
            _toggleSearchBar();
            return KeyEventResult.handled;
          }
          if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.escape && _showSearchBar) {
            _toggleSearchBar();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: Column(
          children: [
            // Barra de búsqueda Ctrl+F
            if (_showSearchBar)
              Container(
                color: AppColors.panelBackground,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Row(
                  children: [
                  const Icon(Icons.search, size: 16, color: Colors.white70),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      focusNode: _searchFocusNode,
                      onChanged: _onSearchTextChanged,
                      style: const TextStyle(fontSize: 11, color: Colors.white),
                      decoration: InputDecoration(
                        hintText: '${tr('search')}... (Esc ${tr('to_close')})',
                        hintStyle: const TextStyle(fontSize: 11, color: Colors.white54),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                        border: OutlineInputBorder(borderSide: BorderSide(color: AppColors.border)),
                        enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: AppColors.border)),
                        focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: AppColors.headerTab)),
                        filled: true,
                        fillColor: AppColors.fieldBackground,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 16, color: Colors.white70),
                    onPressed: _toggleSearchBar,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                  ),
                ],
              ),
            ),
          // Barra de filtros
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
                        value: _useDateFilter,
                        onChanged: (v) => setState(() => _useDateFilter = v ?? true),
                        side: const BorderSide(color: AppColors.border),
                      ),
                      const SizedBox(width: 4),
                      Text(tr('outgoing_date'), style: const TextStyle(fontSize: 11)),
                      const SizedBox(width: 4),
                      // Fecha inicio
                      SizedBox(
                        width: 100,
                        child: InkWell(
                          onTap: _selectStartDate,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                          decoration: BoxDecoration(
                            color: AppColors.fieldBackground,
                            border: Border.all(color: AppColors.border),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(_formatDate(_startDate), style: const TextStyle(fontSize: 11)),
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
                        onTap: _selectEndDate,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                          decoration: BoxDecoration(
                            color: AppColors.fieldBackground,
                            border: Border.all(color: AppColors.border),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(_formatDate(_endDate), style: const TextStyle(fontSize: 11)),
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
                        onFieldSubmitted: (_) => _search(),
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              // Botón Reprint (visible cuando hay selección)
              if (_selectedIndices.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: SizedBox(
                    height: 26,
                    child: ElevatedButton.icon(
                      onPressed: _reprintSelected,
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        backgroundColor: Colors.orange,
                      ),
                      icon: const Icon(Icons.print, size: 14),
                      label: Text('${tr('reprint')} (${_selectedIndices.length})', style: const TextStyle(fontSize: 11)),
                    ),
                  ),
                ),
              // Botón Clear Selection
              if (_selectedIndices.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: SizedBox(
                    height: 26,
                    child: ElevatedButton.icon(
                      onPressed: clearSelection,
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        backgroundColor: Colors.grey[700],
                      ),
                      icon: const Icon(Icons.clear, size: 14),
                      label: Text(tr('clear'), style: const TextStyle(fontSize: 11)),
                    ),
                  ),
                ),
              SizedBox(
                height: 26,
                child: ElevatedButton(
                  onPressed: _search,
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
        // Tabla de datos
        Expanded(
          child: Container(
            color: AppColors.gridBackground,
            child: Column(
              children: [
                // Encabezados con filtros y resize
                Container(
                  color: AppColors.gridHeader,
                  child: Row(
                    children: [
                      // Checkbox para seleccionar todos
                      SizedBox(
                        width: 36,
                        height: 32,
                        child: Center(
                          child: Checkbox(
                            value: displayData.isNotEmpty && _selectedIndices.length == displayData.length,
                            tristate: _selectedIndices.isNotEmpty && _selectedIndices.length < displayData.length,
                            onChanged: (value) => toggleSelectAll(),
                            side: const BorderSide(color: AppColors.border),
                            activeColor: Colors.blue,
                          ),
                        ),
                      ),
                      ...List.generate(_headers.length, (i) {
                      final field = _fields[i];
                      final hasFilter = _columnFilters.containsKey(field);
                      final flex = getColumnFlex(i);
                      final isSorted = _sortColumn == field;
                      
                      return Expanded(
                        flex: flex,
                        key: _filterKeys[field],
                        child: Stack(
                          children: [
                            GestureDetector(
                              onTap: () => _sortByColumn(field, isSorted ? !_sortAscending : true),
                              onSecondaryTap: () => _showColumnContextMenu(context, field, i),
                              child: Container(
                                height: 32, // Altura fija para el header
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), // Padding extra para el handle
                                alignment: Alignment.center,
                                decoration: const BoxDecoration(
                                  border: Border(bottom: BorderSide(color: AppColors.border)),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Flexible(
                                      child: Text(
                                        _headers[i],
                                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
                                        textAlign: TextAlign.center,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    const SizedBox(width: 2),
                                    GestureDetector(
                                      onTap: () => _showFilterDropdown(context, field),
                                      child: Icon(
                                        hasFilter ? Icons.filter_alt : Icons.filter_alt_outlined,
                                        size: 12,
                                        color: hasFilter ? AppColors.headerTab : Colors.white54,
                                      ),
                                    ),
                                    if (_sortColumn == field)
                                      Icon(_sortAscending ? Icons.arrow_upward : Icons.arrow_downward, size: 10, color: Colors.blue),
                                  ],
                                ),
                              ),
                            ),
                            // Resize Handle manual
                            Positioned(
                              right: 0,
                              top: 0,
                              bottom: 0,
                              child: buildResizeHandle(i),
                            ),
                          ],
                        ),
                      );
                    }),
                    ],
                  ),
                ),
                // Datos
                Expanded(
                  child: _isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : displayData.isEmpty
                          ? const Center(
                              child: Text('No data', style: TextStyle(fontSize: 11, color: Colors.white70)),
                            )
                          : SelectionArea(
                            child: ListView.builder(
                              itemCount: displayData.length,
                              itemBuilder: (context, index) {
                                final row = displayData[index];
                                final isEven = index % 2 == 0;
                                final isSelected = _selectedIndices.contains(index);
                                
                                return GestureDetector(
                                  onTap: () {
                                    final isShiftPressed = HardwareKeyboard.instance.isShiftPressed;
                                    _toggleSelection(index, isShiftPressed);
                                  },
                                  child: Container(
                                    color: isSelected 
                                        ? Colors.blue.withOpacity(0.3) 
                                        : (isEven ? AppColors.gridRowEven : AppColors.gridRowOdd),
                                    child: Row(
                                      children: [
                                        // Checkbox de selección
                                        SizedBox(
                                          width: 36,
                                          child: Checkbox(
                                            value: isSelected,
                                            onChanged: (value) {
                                              final isShiftPressed = HardwareKeyboard.instance.isShiftPressed;
                                              _toggleSelection(index, isShiftPressed);
                                            },
                                            side: const BorderSide(color: AppColors.border),
                                            activeColor: Colors.blue,
                                          ),
                                        ),
                                        _buildCell(_getFieldValue(row, 'fecha_salida'), 0),
                                        _buildCell(_getFieldValue(row, 'fecha_salida_hora'), 1),
                                        _buildCell(row['proceso_salida']?.toString() ?? '', 2),
                                        _buildCell(row['linea_proceso']?.toString() ?? '', 3),
                                        _buildCell(row['codigo_material_recibido']?.toString() ?? '', 4),
                                        _buildCell(row['numero_parte']?.toString() ?? '', 5),
                                        _buildCell(row['cantidad_salida']?.toString() ?? '', 6),
                                        _buildCell(row['numero_lote']?.toString() ?? '', 7),
                                        _buildCell(row['especificacion_material']?.toString() ?? '', 8),
                                        _buildCell(row['depto_salida']?.toString() ?? '', 9),
                                        _buildCell(row['vendedor']?.toString() ?? '', 10),
                                        _buildCell(row['comparacion_escaneada']?.toString() ?? '', 11),
                                        _buildComparisonResultCell(row['comparacion_resultado']?.toString() ?? '', 12),
                                        _buildCell(row['usuario_registro']?.toString() ?? '', 13),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                ),
                GridFooter(text: '${tr('total_rows')} : ${displayData.length}'),
              ],
            ),
          ),
        ),
        ],
      ),
      ),
    );
  }

  Widget _buildComparisonResultCell(String text, int index) {
    final color = text == 'OK' ? Colors.green : text == 'NG' ? Colors.red : Colors.white70;
    final bgColor = text == 'OK' ? Colors.green.withOpacity(0.2) : text == 'NG' ? Colors.red.withOpacity(0.2) : Colors.transparent;
    
    return Expanded(
      flex: getColumnFlex(index),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        alignment: Alignment.center,
        child: text.isNotEmpty ? Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: color.withOpacity(0.5)),
          ),
          child: Text(
            text,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ) : const SizedBox.shrink(),
      ),
    );
  }

  Widget _buildCell(String text, int index) {
    return Expanded(
      flex: getColumnFlex(index),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        alignment: Alignment.center,
        child: _highlightText(text, _searchText),
      ),
    );
  }
}
