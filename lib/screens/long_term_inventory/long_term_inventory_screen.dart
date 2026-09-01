import 'package:flutter/material.dart';
import '../../core/widgets/column_filter.dart';
import 'package:flutter/services.dart';
import 'package:material_warehousing_flutter/core/localization/app_translations.dart';
import 'package:material_warehousing_flutter/core/theme/app_colors.dart';
import 'package:material_warehousing_flutter/core/services/api_service.dart';
import 'package:material_warehousing_flutter/core/services/auth_service.dart';
import 'package:material_warehousing_flutter/core/services/excel_export_service.dart';
import 'package:material_warehousing_flutter/core/widgets/grid_footer.dart';
import 'package:material_warehousing_flutter/core/widgets/resizable_grid_header.dart';

class LongTermInventoryScreen extends StatefulWidget {
  final LanguageProvider languageProvider;
  
  const LongTermInventoryScreen({super.key, required this.languageProvider});

  @override
  State<LongTermInventoryScreen> createState() => LongTermInventoryScreenState();
}
class LongTermInventoryScreenState extends State<LongTermInventoryScreen> with SingleTickerProviderStateMixin, ResizableColumnsMixin {
  late TabController _tabController;
  
  // Datos
  List<Map<String, dynamic>> _summaryData = [];
  List<Map<String, dynamic>> _detailData = [];
  List<Map<String, dynamic>> _originalSummaryData = [];
  List<Map<String, dynamic>> _originalDetailData = [];
  bool _isLoading = false;
  
  // Controladores de búsqueda
  final TextEditingController _searchPartController = TextEditingController();
  final TextEditingController _searchLabelController = TextEditingController();
  
  // Selección
  int _selectedSummaryIndex = -1;
  Set<int> _selectedDetailIndices = {}; // Multi-selección para Details
  
  // Ordenamiento
  String? _summarySortColumn;
  bool _summarySortAscending = true;
  String? _detailSortColumn;
  bool _detailSortAscending = true;
  
  // Filtros por columna
  final Map<String, Set<String>> _summaryFilters = {};
  final Map<String, Set<String>> _detailFilters = {};
  
  // Búsqueda con Ctrl+F
  bool _showSearchBar = false;
  String _searchText = '';
  final TextEditingController _gridSearchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final FocusNode _keyboardFocusNode = FocusNode();
  
  // Filtros de fecha e incluir salidas
  bool _includeZeroStock = false;
  bool _useDateRange = false;
  DateTime? _startDate;
  DateTime? _endDate;
  
  String tr(String key) => widget.languageProvider.tr(key);

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(_onTabChanged);
    // Summary: 7 columns in Current mode, 9 in Date Range mode
    initColumnFlex(7, 'inv_summary', defaultFlexValues: [2.0, 2.0, 1.5, 1.0, 1.5, 1.5, 1.5]);
    _loadSummaryData();
  }
  
  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    _searchPartController.dispose();
    _searchLabelController.dispose();
    _gridSearchController.dispose();
    _searchFocusNode.dispose();
    _keyboardFocusNode.dispose();
    super.dispose();
  }
  
  void _onTabChanged() {
    setState(() {}); // Para actualizar los tabs visuales
    
    if (!_tabController.indexIsChanging) {
      if (_tabController.index == 0) {
        // Summary: 7 columns in Current mode, 9 in Date Range mode
        final cols = _useDateRange ? 9 : 7;
        initColumnFlex(cols, 'inv_summary', defaultFlexValues: _useDateRange 
            ? [2.0, 2.0, 1.5, 1.0, 1.5, 1.5, 1.5, 1.5, 1.5]
            : [2.0, 2.0, 1.5, 1.0, 1.5, 1.5, 1.5]);
        _loadSummaryData();
      } else {
        // Detail: 11 columns in Current mode, 13 in Date Range mode
        final cols = _useDateRange ? 13 : 11;
        initColumnFlex(cols, 'inv_detail', defaultFlexValues: _useDateRange 
            ? [2.0, 2.0, 2.0, 2.0, 1.5, 1.0, 1.0, 1.5, 1.5, 1.5, 1.5, 1.5, 1.5]
            : [2.0, 2.0, 2.0, 2.0, 1.5, 1.0, 1.5, 1.5, 1.5, 1.5, 1.5]);
        _loadDetailData();
      }
    }
  }
  
  Future<void> _loadSummaryData() async {
    setState(() => _isLoading = true);
    final data = await ApiService.getInventorySummary(
      numeroParte: _searchPartController.text.isNotEmpty ? _searchPartController.text : null,
      includeZeroStock: _includeZeroStock,
      fechaInicio: _useDateRange && _startDate != null ? _startDate!.toIso8601String().split('T')[0] : null,
      fechaFin: _useDateRange && _endDate != null ? _endDate!.toIso8601String().split('T')[0] : null,
    );
    if (mounted) {
      setState(() {
        _originalSummaryData = List.from(data);
        _summaryData = data;
        _selectedSummaryIndex = -1;
        _summaryFilters.clear();
        _isLoading = false;
      });
    }
  }
  
  Future<void> _loadDetailData() async {
    setState(() => _isLoading = true);
    final data = await ApiService.getInventoryLots(
      numeroParte: _searchPartController.text.isNotEmpty ? _searchPartController.text : null,
      codigoMaterialRecibido: _searchLabelController.text.isNotEmpty ? _searchLabelController.text : null,
      includeZeroStock: _includeZeroStock,
      fechaInicio: _useDateRange && _startDate != null ? _startDate!.toIso8601String().split('T')[0] : null,
      fechaFin: _useDateRange && _endDate != null ? _endDate!.toIso8601String().split('T')[0] : null,
    );
    if (mounted) {
      setState(() {
        _originalDetailData = List.from(data);
        _detailData = data;
        _selectedDetailIndices.clear();
        _detailFilters.clear();
        _isLoading = false;
      });
    }
  }
  
  void _search() {
    if (_tabController.index == 0) {
      _loadSummaryData();
    } else {
      _loadDetailData();
    }
  }

  /// Recarga los datos del inventario desde el servidor
  Future<void> reloadData() async {
    if (_tabController.index == 0) {
      await _loadSummaryData();
    } else {
      await _loadDetailData();
    }
  }
  

  void _showSnackBar(String message, {Color? backgroundColor}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: backgroundColor,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  double _readQuantity(dynamic value) =>
      double.tryParse(value?.toString() ?? '') ?? 0;

  String _formatQuantity(dynamic value) {
    final quantity = _readQuantity(value);
    if ((quantity - quantity.roundToDouble()).abs() < 0.001) {
      return quantity.toStringAsFixed(0);
    }
    final fixed = quantity.toStringAsFixed(2);
    return fixed.endsWith('0')
        ? fixed.substring(0, fixed.length - 1)
        : fixed;
  }

  String _currentUsername() {
    final user = AuthService.currentUser;
    if (user == null) return 'Sistema';
    final fullName = user.nombreCompleto.trim();
    return fullName.isNotEmpty ? fullName : user.username;
  }

  List<Map<String, String>> _buildDetailHeaders() {
    final baseHeaders = [
      {'label': tr('part_number'), 'field': 'numero_parte'},
      {'label': tr('lot_number'), 'field': 'numero_lote'},
      {'label': tr('material_warehousing_code'), 'field': 'codigo_material_recibido'},
      {'label': tr('material_spec'), 'field': 'especificacion'},
      {'label': tr('location'), 'field': 'ubicacion'},
      {'label': tr('unit'), 'field': 'unidad_medida'},
    ];
    final movementHeaders = [
      {'label': tr('total_in'), 'field': 'total_entrada'},
      {'label': tr('total_out'), 'field': 'total_salida'},
    ];
    final finalHeaders = [
      {'label': tr('current_stock'), 'field': 'stock_actual'},
      {'label': tr('entry_date'), 'field': 'fecha_recibo'},
      {'label': tr('exit_date'), 'field': 'fecha_salida'},
      {'label': tr('entry_user'), 'field': 'usuario_entrada'},
      {'label': tr('exit_user'), 'field': 'usuario_salida'},
    ];
    return _useDateRange
        ? [...baseHeaders, ...movementHeaders, ...finalHeaders]
        : [...baseHeaders, ...finalHeaders];
  }

  List<Map<String, dynamic>> _getDisplayedDetailData(
      [List<Map<String, String>>? headers]) {
    final effectiveHeaders = headers ?? _buildDetailHeaders();
    if (_searchText.isEmpty) {
      return List<Map<String, dynamic>>.from(_detailData);
    }
    return _detailData.where((row) {
      return effectiveHeaders.any((header) {
        final field = header['field']!;
        final value = row[field]?.toString().toLowerCase() ?? '';
        return value.contains(_searchText);
      });
    }).toList();
  }

  List<Map<String, dynamic>> _getSelectedDetailRows() {
    final displayed = _getDisplayedDetailData();
    final indices = _selectedDetailIndices.toList()..sort();
    return indices
        .where((index) => index >= 0 && index < displayed.length)
        .map((index) => displayed[index])
        .toList();
  }

  Future<void> _openAdjustInventoryDialog() async {
    if (!AuthService.canWriteInventoryAdjustment) {
      _showSnackBar(tr('no_permission'), backgroundColor: Colors.red);
      return;
    }
    if (_tabController.index != 1 || _useDateRange) {
      _showSnackBar(tr('adjust_current_mode_only'),
          backgroundColor: Colors.orange);
      return;
    }

    final selectedRows = _getSelectedDetailRows();
    if (selectedRows.length != 1) {
      _showSnackBar(tr('select_single_row'), backgroundColor: Colors.orange);
      return;
    }

    final row = selectedRows.first;
    final currentStock = _readQuantity(row['stock_actual']);
    final unit = row['unidad_medida']?.toString() ?? 'EA';
    final targetController =
        TextEditingController(text: _formatQuantity(currentStock));
    final reasonController = TextEditingController();

    final payload = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) {
        String? validationError;
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final target = int.tryParse(targetController.text.trim());
            final delta = target == null ? null : target - currentStock;
            return AlertDialog(
              backgroundColor: const Color(0xFF2D2D30),
              title: Text(tr('adjust_stock'),
                  style: const TextStyle(color: Colors.white, fontSize: 15)),
              content: SizedBox(
                width: 420,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${tr('material_warehousing_code')}: ${row['codigo_material_recibido'] ?? ''}',
                        style: const TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${tr('part_number')}: ${row['numero_parte'] ?? ''}',
                        style: const TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${tr('lot_number')}: ${row['numero_lote'] ?? ''}',
                        style: const TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        '${tr('current_stock')}: ${_formatQuantity(currentStock)} $unit',
                        style: const TextStyle(color: Colors.white, fontSize: 12),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: targetController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: false),
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        style: const TextStyle(color: Colors.white, fontSize: 12),
                        decoration: InputDecoration(
                          labelText: tr('target_stock'),
                          labelStyle: const TextStyle(color: Colors.white70, fontSize: 12),
                          filled: true,
                          fillColor: AppColors.fieldBackground,
                          border: const OutlineInputBorder(),
                        ),
                        onChanged: (_) =>
                            setDialogState(() => validationError = null),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: reasonController,
                        maxLines: 2,
                        maxLength: 255,
                        style: const TextStyle(color: Colors.white, fontSize: 12),
                        decoration: InputDecoration(
                          labelText: tr('reason'),
                          labelStyle: const TextStyle(color: Colors.white70, fontSize: 12),
                          filled: true,
                          fillColor: AppColors.fieldBackground,
                          border: const OutlineInputBorder(),
                        ),
                        onChanged: (_) =>
                            setDialogState(() => validationError = null),
                      ),
                      if (delta != null && delta != 0)
                        Text(
                          '${delta > 0 ? tr('entries') : tr('exits')}: '
                          '${_formatQuantity(delta.abs())} $unit',
                          style: TextStyle(
                            color: delta > 0
                                ? Colors.greenAccent
                                : Colors.orangeAccent,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      if (validationError != null) ...[
                        const SizedBox(height: 8),
                        Text(validationError!,
                            style: const TextStyle(color: Colors.red, fontSize: 12)),
                      ],
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: Text(tr('cancel')),
                ),
                TextButton(
                  onPressed: () {
                    final target = int.tryParse(targetController.text.trim());
                    final reason = reasonController.text.trim();
                    if (target == null || target < 0) {
                      setDialogState(() =>
                          validationError = tr('invalid_target_stock'));
                    } else if ((target - currentStock).abs() < 0.0001) {
                      setDialogState(() =>
                          validationError = tr('no_inventory_change'));
                    } else if (reason.isEmpty) {
                      setDialogState(() => validationError =
                          tr('adjustment_reason_required'));
                    } else {
                      Navigator.pop(dialogContext, {
                        'target_stock': target,
                        'reason': reason,
                      });
                    }
                  },
                  child: Text(tr('save')),
                ),
              ],
            );
          },
        );
      },
    );

    targetController.dispose();
    reasonController.dispose();
    if (payload == null) return;

    final warehousingId = int.tryParse('${row['warehousing_id'] ?? ''}');
    if (warehousingId == null) {
      _showSnackBar(tr('invalid_target_stock'), backgroundColor: Colors.red);
      return;
    }

    final user = AuthService.currentUser;
    final response = await ApiService.adjustInventoryLot(
      warehousingId: warehousingId,
      codigoMaterialRecibido:
          row['codigo_material_recibido']?.toString() ?? '',
      targetStock: payload['target_stock'] as num,
      reason: payload['reason'] as String,
      usuarioRegistro: _currentUsername(),
      usuarioRegistroId: user?.id,
    );
    if (!mounted) return;

    if (response['success'] == true) {
      await _loadSummaryData();
      await _loadDetailData();
      _showSnackBar(tr('adjustment_saved'), backgroundColor: Colors.green);
    } else {
      _showSnackBar(
        response['error']?.toString() ?? tr('outgoing_error'),
        backgroundColor: Colors.red,
      );
    }
  }

  void _clearSearch() {
    _searchPartController.clear();
    _searchLabelController.clear();
    setState(() {
      // No resetear _includeZeroStock - mantener el estado del checkbox "Include Exits"
      _useDateRange = false;
      _startDate = null;
      _endDate = null;
    });
    // Volver a la pestaña Summary
    _tabController.animateTo(0);
  }
  
  // Funciones de búsqueda Ctrl+F
  void _toggleSearchBar() {
    setState(() {
      _showSearchBar = !_showSearchBar;
      if (_showSearchBar) {
        Future.delayed(const Duration(milliseconds: 100), () {
          _searchFocusNode.requestFocus();
        });
      } else {
        _searchText = '';
        _gridSearchController.clear();
      }
    });
  }
  
  void _onSearchTextChanged(String value) {
    setState(() {
      _searchText = value.toLowerCase();
    });
  }
  
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
  
  Future<void> _exportToExcel() async {
    List<String> headers;
    List<String> fieldMapping;
    List<Map<String, dynamic>> data;
    String fileName;
    
    if (_tabController.index == 0) {
      // Exportar Summary
      if (_useDateRange) {
        headers = [
          tr('part_number'),
          tr('material_spec'),
          tr('unit'),
          tr('entries'),
          tr('exits'),
          tr('stock_total'),
          tr('distinct_lots'),
          tr('lots_with_stock'),
        ];
        fieldMapping = [
          'numero_parte',
          'especificacion',
          'unidad_medida',
          'total_entrada',
          'total_salida',
          'stock_total',
          'lotes_distintos',
          'lotes_con_stock',
        ];
      } else {
        headers = [
          tr('part_number'),
          tr('material_spec'),
          tr('unit'),
          tr('stock_total'),
          tr('distinct_lots'),
          tr('lots_with_stock'),
        ];
        fieldMapping = [
          'numero_parte',
          'especificacion',
          'unidad_medida',
          'stock_total',
          'lotes_distintos',
          'lotes_con_stock',
        ];
      }
      data = _summaryData;
      fileName = 'Inventory_Summary';
    } else {
      // Exportar Detail
      if (_useDateRange) {
        headers = [
          tr('part_number'),
          tr('lot_number'),
          tr('material_warehousing_code'),
          tr('unit'),
          tr('total_in'),
          tr('total_out'),
          tr('current_stock'),
        ];
        fieldMapping = [
          'numero_parte',
          'numero_lote',
          'codigo_material_recibido',
          'unidad_medida',
          'total_entrada',
          'total_salida',
          'stock_actual',
        ];
      } else {
        headers = [
          tr('part_number'),
          tr('lot_number'),
          tr('material_warehousing_code'),
          tr('unit'),
          tr('current_stock'),
        ];
        fieldMapping = [
          'numero_parte',
          'numero_lote',
          'codigo_material_recibido',
          'unidad_medida',
          'stock_actual',
        ];
      }
      data = _detailData;
      fileName = 'Inventory_Detail';
    }
    
    final success = await ExcelExportService.exportToExcel(
      data: data,
      headers: headers,
      fieldMapping: fieldMapping,
      fileName: fileName,
    );
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success ? 'Excel exported successfully' : 'Export cancelled'),
          backgroundColor: success ? Colors.green : Colors.orange,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }
  
  void _sortData(String field, bool ascending, bool isSummary) {
    setState(() {
      if (isSummary) {
        _summarySortColumn = field;
        _summarySortAscending = ascending;
      } else {
        _detailSortColumn = field;
        _detailSortAscending = ascending;
      }

      final dataList = isSummary ? _summaryData : _detailData;
      _sortRows(dataList, field, ascending);
    });
  }

  void _sortRows(
    List<Map<String, dynamic>> rows,
    String field,
    bool ascending,
  ) {
    rows.sort((a, b) {
      final aValue = a[field];
      final bValue = b[field];
      final comparison = _compareValues(aValue, bValue);
      return ascending ? comparison : -comparison;
    });
  }

  int _compareValues(dynamic aValue, dynamic bValue) {
    if (aValue == null && bValue == null) return 0;
    if (aValue == null) return -1;
    if (bValue == null) return 1;
    if (aValue is num && bValue is num) return aValue.compareTo(bValue);

    final aText = aValue.toString().trim();
    final bText = bValue.toString().trim();
    final aNumber = num.tryParse(aText);
    final bNumber = num.tryParse(bText);
    if (aNumber != null && bNumber != null) {
      return aNumber.compareTo(bNumber);
    }
    return aText.toLowerCase().compareTo(bText.toLowerCase());
  }

  String _columnFilterValue(dynamic value) => value?.toString().trim() ?? '';

  List<Map<String, dynamic>> _rowsMatchingOtherFilters(
    String excludedField,
    bool isSummary,
  ) {
    final filters = isSummary ? _summaryFilters : _detailFilters;
    final originalData =
        isSummary ? _originalSummaryData : _originalDetailData;
    return originalData.where((row) {
      for (final entry in filters.entries) {
        if (entry.key == excludedField) continue;
        final cellValue = _columnFilterValue(row[entry.key]);
        if (!entry.value.contains(cellValue)) return false;
      }
      return true;
    }).toList();
  }

  Future<void> _showExcelColumnFilter(
    BuildContext context,
    String field,
    String header,
    bool isSummary,
    Offset position,
  ) async {
    final filters = isSummary ? _summaryFilters : _detailFilters;
    final rows = _rowsMatchingOtherFilters(field, isSummary);
    final values = rows.map((row) => _columnFilterValue(row[field])).toList();

    // Los filtros de esta pantalla se guardan como conjunto; el desplegable
    // devuelve un valor. (Blanks)/(Non blanks) se expanden al conjunto que les
    // corresponde para no tocar la logica de _applyFilters.
    final current = filters[field];
    final result = await ColumnFilter.show(
      context: context,
      anchorOffset: position,
      values: values,
      currentFilter:
          current != null && current.length == 1 ? current.first : null,
    );
    if (!mounted || !result.changed) return;

    if (result.filter == null) {
      _clearColumnFilter(field, isSummary);
      return;
    }
    final disponibles = values.toSet();
    final Set<String> elegidos;
    if (result.filter == ColumnFilter.blanks) {
      elegidos = disponibles.where((v) => v.isEmpty).toSet();
    } else if (result.filter == ColumnFilter.nonBlanks) {
      elegidos = disponibles.where((v) => v.isNotEmpty).toSet();
    } else {
      elegidos = {result.filter!};
    }
    _applyColumnFilter(field, elegidos, disponibles.toList(), isSummary);
  }

  void _applyColumnFilter(
    String field,
    Set<String> selectedValues,
    List<String> availableValues,
    bool isSummary,
  ) {
    setState(() {
      final filters = isSummary ? _summaryFilters : _detailFilters;
      final allSelected = selectedValues.length == availableValues.length &&
          selectedValues.containsAll(availableValues);
      if (allSelected) {
        filters.remove(field);
      } else {
        filters[field] = Set<String>.from(selectedValues);
      }
      _applyFilters(isSummary);
    });
  }
  
  void _clearColumnFilter(String field, bool isSummary) {
    setState(() {
      final filters = isSummary ? _summaryFilters : _detailFilters;
      filters.remove(field);
      _applyFilters(isSummary);
    });
  }
  
  void _applyFilters(bool isSummary) {
    final filters = isSummary ? _summaryFilters : _detailFilters;
    final originalData =
        isSummary ? _originalSummaryData : _originalDetailData;
    final filtered = originalData.where((row) {
      for (final entry in filters.entries) {
        final cellValue = _columnFilterValue(row[entry.key]);
        if (!entry.value.contains(cellValue)) return false;
      }
      return true;
    }).toList();

    final sortColumn =
        isSummary ? _summarySortColumn : _detailSortColumn;
    final sortAscending =
        isSummary ? _summarySortAscending : _detailSortAscending;
    if (sortColumn != null) {
      _sortRows(filtered, sortColumn, sortAscending);
    }

    if (isSummary) {
      _selectedSummaryIndex = -1;
      _summaryData = filtered;
    } else {
      _selectedDetailIndices.clear();
      _detailData = filtered;
    }
  }

  InputDecoration _searchDecoration(String hint) {
    return InputDecoration(
      isDense: true,
      hintText: hint,
      hintStyle: const TextStyle(fontSize: 11, color: Colors.white38),
      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      filled: true,
      fillColor: AppColors.fieldBackground,
      border: const OutlineInputBorder(
        borderSide: BorderSide(color: AppColors.border, width: 1),
      ),
      enabledBorder: const OutlineInputBorder(
        borderSide: BorderSide(color: AppColors.border, width: 1),
      ),
      focusedBorder: const OutlineInputBorder(
        borderSide: BorderSide(color: AppColors.headerTab, width: 1),
      ),
    );
  }

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
        onTap: () => _keyboardFocusNode.requestFocus(),
        child: Column(
      children: [
        // Barra superior con tabs y búsqueda
        Container(
          color: AppColors.panelBackground,
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
          child: Row(
            children: [
              // Tabs con sombra y tamaño uniforme
              Container(
                width: 180,
                height: 32,
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1A2E),
                  borderRadius: BorderRadius.circular(6),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.4),
                      blurRadius: 6,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () => _tabController.animateTo(0),
                        child: Container(
                          decoration: BoxDecoration(
                            color: _tabController.index == 0 ? AppColors.headerTab : Colors.transparent,
                            borderRadius: BorderRadius.circular(6),
                            boxShadow: _tabController.index == 0 ? [
                              BoxShadow(
                                color:
                                    AppColors.headerTab.withValues(alpha: 0.5),
                                blurRadius: 4,
                                offset: const Offset(0, 2),
                              ),
                            ] : null,
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            tr('summary_view'),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: _tabController.index == 0 ? FontWeight.w600 : FontWeight.normal,
                              color: _tabController.index == 0 ? Colors.white : Colors.white54,
                            ),
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: GestureDetector(
                        onTap: () => _tabController.animateTo(1),
                        child: Container(
                          decoration: BoxDecoration(
                            color: _tabController.index == 1 ? AppColors.headerTab : Colors.transparent,
                            borderRadius: BorderRadius.circular(6),
                            boxShadow: _tabController.index == 1 ? [
                              BoxShadow(
                                color:
                                    AppColors.headerTab.withValues(alpha: 0.5),
                                blurRadius: 4,
                                offset: const Offset(0, 2),
                              ),
                            ] : null,
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            tr('detail_view'),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: _tabController.index == 1 ? FontWeight.w600 : FontWeight.normal,
                              color: _tabController.index == 1 ? Colors.white : Colors.white54,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // Campo de búsqueda por Part Number
              Flexible(
                flex: 2,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 200),
                  child: SizedBox(
                    height: 28,
                    child: TextField(
                      controller: _searchPartController,
                      style: const TextStyle(fontSize: 11),
                      decoration: _searchDecoration(tr('search_by_part')),
                      onSubmitted: (_) => _search(),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              // Campo de búsqueda por Label (solo en detalle)
              if (_tabController.index == 1) ...[
                Flexible(
                  flex: 2,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 200),
                    child: SizedBox(
                      height: 28,
                      child: TextField(
                        controller: _searchLabelController,
                        style: const TextStyle(fontSize: 11),
                        decoration: _searchDecoration(tr('search_by_label')),
                        onSubmitted: (_) => _search(),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
              ],
              // Botón de búsqueda
              SizedBox(
                height: 28,
                child: ElevatedButton(
                  onPressed: _search,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    backgroundColor: AppColors.buttonSearch,
                  ),
                  child: Text(tr('search'), style: const TextStyle(fontSize: 11)),
                ),
              ),
              const SizedBox(width: 4),
              // Botón Limpiar
              SizedBox(
                height: 28,
                child: ElevatedButton(
                  onPressed: _clearSearch,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    backgroundColor: AppColors.buttonGray,
                  ),
                  child: Text(tr('clean'), style: const TextStyle(fontSize: 11)),
                ),
              ),
              const SizedBox(width: 8),
              // Checkbox incluir salidas
              SizedBox(
                height: 28,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 20,
                      height: 20,
                      child: Checkbox(
                        value: _includeZeroStock,
                        onChanged: (v) {
                          setState(() => _includeZeroStock = v ?? false);
                          _search();
                        },
                        side: const BorderSide(color: AppColors.border),
                        activeColor: Colors.blue,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(tr('include_exits'), style: const TextStyle(fontSize: 11, color: Colors.white70)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // Toggle Actual / Rango de Fechas
              Container(
                height: 28,
                decoration: BoxDecoration(
                  color: AppColors.fieldBackground,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () {
                        setState(() {
                          _useDateRange = false;
                          _startDate = null;
                          _endDate = null;
                        });
                        // Reinitialize columns for Current mode
                        if (_tabController.index == 0) {
                          initColumnFlex(7, 'inv_summary_current', defaultFlexValues: [2.0, 2.0, 1.5, 1.0, 1.5, 1.5, 1.5]);
                        } else {
                          initColumnFlex(11, 'inv_detail_current', defaultFlexValues: [2.0, 2.0, 2.0, 2.0, 1.5, 1.0, 1.5, 1.5, 1.5, 1.5, 1.5]);
                        }
                        _search();
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        decoration: BoxDecoration(
                          color: !_useDateRange ? AppColors.headerTab : Colors.transparent,
                          borderRadius: BorderRadius.circular(3),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          tr('current_inventory'),
                          style: TextStyle(
                            fontSize: 11,
                            color: !_useDateRange ? Colors.white : Colors.white54,
                          ),
                        ),
                      ),
                    ),
                    GestureDetector(
                      onTap: () {
                        setState(() {
                          _useDateRange = true;
                          // Por defecto: inicio del mes actual hasta hoy
                          final now = DateTime.now();
                          _startDate = DateTime(now.year, now.month, 1);
                          _endDate = now;
                        });
                        // Reinitialize columns for Date Range mode
                        if (_tabController.index == 0) {
                          initColumnFlex(9, 'inv_summary_range', defaultFlexValues: [2.0, 2.0, 1.5, 1.0, 1.5, 1.5, 1.5, 1.5, 1.5]);
                        } else {
                          initColumnFlex(13, 'inv_detail_range', defaultFlexValues: [2.0, 2.0, 2.0, 2.0, 1.5, 1.0, 1.0, 1.5, 1.5, 1.5, 1.5, 1.5, 1.5]);
                        }
                        _search();
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        decoration: BoxDecoration(
                          color: _useDateRange ? AppColors.headerTab : Colors.transparent,
                          borderRadius: BorderRadius.circular(3),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          tr('date_range'),
                          style: TextStyle(
                            fontSize: 11,
                            color: _useDateRange ? Colors.white : Colors.white54,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // Date pickers (solo visibles cuando _useDateRange es true)
              if (_useDateRange) ...[
                const SizedBox(width: 4),
                // Start Date
                SizedBox(
                  height: 28,
                  child: InkWell(
                    onTap: () async {
                      final date = await showDatePicker(
                        context: context,
                        initialDate: _startDate ?? DateTime.now(),
                        firstDate: DateTime(2020),
                        lastDate: DateTime.now(),
                      );
                      if (date != null) {
                        setState(() => _startDate = date);
                        _search();
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      decoration: BoxDecoration(
                        color: AppColors.fieldBackground,
                        border: Border.all(color: AppColors.border),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      alignment: Alignment.center,
                      child: Row(
                        children: [
                          const Icon(Icons.calendar_today, size: 12, color: Colors.white54),
                          const SizedBox(width: 4),
                          Text(
                            _startDate != null 
                              ? '${_startDate!.year}-${_startDate!.month.toString().padLeft(2, '0')}-${_startDate!.day.toString().padLeft(2, '0')}'
                              : tr('start_date'),
                            style: const TextStyle(fontSize: 11, color: Colors.white70),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                const Text('~', style: TextStyle(color: Colors.white54)),
                const SizedBox(width: 4),
                // End Date
                SizedBox(
                  height: 28,
                  child: InkWell(
                    onTap: () async {
                      final date = await showDatePicker(
                        context: context,
                        initialDate: _endDate ?? DateTime.now(),
                        firstDate: DateTime(2020),
                        lastDate: DateTime.now(),
                      );
                      if (date != null) {
                        setState(() => _endDate = date);
                        _search();
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      decoration: BoxDecoration(
                        color: AppColors.fieldBackground,
                        border: Border.all(color: AppColors.border),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      alignment: Alignment.center,
                      child: Row(
                        children: [
                          const Icon(Icons.calendar_today, size: 12, color: Colors.white54),
                          const SizedBox(width: 4),
                          Text(
                            _endDate != null 
                              ? '${_endDate!.year}-${_endDate!.month.toString().padLeft(2, '0')}-${_endDate!.day.toString().padLeft(2, '0')}'
                              : tr('end_date'),
                            style: const TextStyle(fontSize: 11, color: Colors.white70),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
              const Spacer(),
              if (_tabController.index == 1 && !_useDateRange) ...[
                SizedBox(
                  height: 28,
                  child: ElevatedButton(
                    onPressed: _openAdjustInventoryDialog,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      backgroundColor: AuthService.canWriteInventoryAdjustment
                          ? AppColors.buttonSave
                          : AppColors.buttonGray,
                    ),
                    child: Text(tr('adjust_stock'),
                        style: const TextStyle(fontSize: 11)),
                  ),
                ),
                const SizedBox(width: 4),
              ],
              // Botón Excel Export
              SizedBox(
                height: 28,
                child: ElevatedButton(
                  onPressed: _exportToExcel,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    backgroundColor: AppColors.buttonExcel,
                  ),
                  child: Text(tr('excel_export'), style: const TextStyle(fontSize: 11)),
                ),
              ),
            ],
          ),
        ),
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
                    controller: _gridSearchController,
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
                      prefixIcon: const Icon(Icons.search, size: 16, color: Colors.white54),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  _searchText.isNotEmpty 
                    ? 'Highlighting: "$_searchText"'
                    : 'Ctrl+F ${tr('to_close')}: Esc',
                  style: const TextStyle(fontSize: 11, color: Colors.white54),
                ),
                const Spacer(),
                SizedBox(
                  height: 24,
                  child: TextButton(
                    onPressed: _toggleSearchBar,
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                    ),
                    child: const Text('Close', style: TextStyle(fontSize: 11)),
                  ),
                ),
              ],
            ),
          ),
        // Grid
        Expanded(
          child: TabBarView(
            controller: _tabController,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              _buildSummaryGrid(),
              _buildDetailGrid(),
            ],
          ),
        ),
      ],
    ),
    ),
    );
  }
  
  Widget _buildSummaryGrid() {
    // Headers base (sin entries/exits)
    final baseHeaders = [
      {'label': tr('part_number'), 'field': 'numero_parte'},
      {'label': tr('material_spec'), 'field': 'especificacion'},
      {'label': tr('location'), 'field': 'ubicacion'},
      {'label': tr('unit'), 'field': 'unidad_medida'},
    ];
    
    // Headers de entries/exits (solo en Date Range)
    final entryExitHeaders = [
      {'label': tr('entries'), 'field': 'total_entrada'},
      {'label': tr('exits'), 'field': 'total_salida'},
    ];
    
    // Headers finales
    final finalHeaders = [
      {'label': tr('stock_total'), 'field': 'stock_total'},
      {'label': tr('distinct_lots'), 'field': 'lotes_distintos'},
      {'label': tr('lots_with_stock'), 'field': 'lotes_con_stock'},
    ];
    
    // Combinar headers según el modo
    final headers = _useDateRange 
        ? [...baseHeaders, ...entryExitHeaders, ...finalHeaders]
        : [...baseHeaders, ...finalHeaders];
    
    // Filtrar por búsqueda Ctrl+F
    final displayData = _searchText.isEmpty
        ? _summaryData
        : _summaryData.where((row) {
            return headers.any((h) {
              final field = h['field'] as String;
              final value = row[field]?.toString().toLowerCase() ?? '';
              return value.contains(_searchText);
            });
          }).toList();
    
    return Container(
      color: AppColors.gridBackground,
      child: Column(
        children: [
          // Header
          Container(
            height: 28,
            color: AppColors.gridHeader,
            child: Row(
              children: headers.asMap().entries.map((entry) => _buildHeaderCell(
                entry.value['label'] as String, 
                entry.value['field'] as String,
                true,
                entry.key,
              )).toList(),
            ),
          ),
          // Body
          Expanded(
            child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : displayData.isEmpty
                ? Center(child: Text(tr('no_data'), style: const TextStyle(fontSize: 11, color: Colors.white70)))
                : SelectionArea(
                  child: ListView.builder(
                    itemCount: displayData.length,
                    itemBuilder: (context, index) {
                      final row = displayData[index];
                      final isSelected = _selectedSummaryIndex == index;
                      final unit = row['unidad_medida']?.toString() ?? 'EA';
                      final stockTotal = row['stock_total'] ?? 0;
                      final totalEntrada = row['total_entrada'] ?? 0;
                      final totalSalida = row['total_salida'] ?? 0;
                      
                      // Formato con comas para miles
                      String formatNumber(dynamic value) {
                        if (value == null) return '0';
                        final num = double.tryParse(value.toString()) ?? 0;
                        return num.toStringAsFixed(0).replaceAllMapped(
                          RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
                          (Match m) => '${m[1]},',
                        );
                      }
                      
                      return GestureDetector(
                        onTap: () => setState(() => _selectedSummaryIndex = index),
                        onDoubleTap: () {
                          // Al hacer doble click, ir a detalle filtrado por ese part number
                          _searchPartController.text = row['numero_parte']?.toString() ?? '';
                          _tabController.animateTo(1);
                        },
                        child: Container(
                          height: 24,
                          color: isSelected 
                            ? AppColors.gridSelectedRow 
                            : (index.isEven ? AppColors.gridBackground : AppColors.gridRowAlt),
                          child: Row(
                            children: [
                              _buildCell(row['numero_parte']?.toString() ?? '', 0),
                              _buildCell(row['especificacion']?.toString() ?? '', 1),
                              _buildCell(row['ubicacion']?.toString() ?? '', 2),
                              _buildCell(unit, 3),
                              if (_useDateRange) ...[
                                _buildCell('${formatNumber(totalEntrada)} $unit', 4),
                                _buildCell('${formatNumber(totalSalida)} $unit', 5),
                                _buildCell('${formatNumber(stockTotal)} $unit', 6),
                                _buildCell(row['lotes_distintos']?.toString() ?? '0', 7),
                                _buildCell(row['lotes_con_stock']?.toString() ?? '0', 8),
                              ] else ...[
                                _buildCell('${formatNumber(stockTotal)} $unit', 4),
                                _buildCell(row['lotes_distintos']?.toString() ?? '0', 5),
                                _buildCell(row['lotes_con_stock']?.toString() ?? '0', 6),
                              ],
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
          ),
          GridFooter(text: '${tr('total_rows')} : ${displayData.length}${displayData.length != _originalSummaryData.length ? ' / ${_originalSummaryData.length}' : ''}'),
        ],
      ),
    );
  }
  
  Widget _buildDetailGrid() {
    final headers = _buildDetailHeaders();
    final displayData = _getDisplayedDetailData(headers);
    
    return Container(
      color: AppColors.gridBackground,
      child: Column(
        children: [
          // Header con checkbox Select All
          Container(
            height: 28,
            color: AppColors.gridHeader,
            child: Row(
              children: [
                // Checkbox Select All
                SizedBox(
                  width: 30,
                  child: Checkbox(
                    value: displayData.isNotEmpty && _selectedDetailIndices.length == displayData.length,
                    tristate: true,
                    onChanged: (value) {
                      setState(() {
                        if (_selectedDetailIndices.length == displayData.length) {
                          _selectedDetailIndices.clear();
                        } else {
                          _selectedDetailIndices = Set<int>.from(List.generate(displayData.length, (i) => i));
                        }
                      });
                    },
                    side: const BorderSide(color: AppColors.border),
                    activeColor: Colors.blue,
                  ),
                ),
                ...headers.asMap().entries.map((entry) => _buildHeaderCell(
                  entry.value['label'] as String, 
                  entry.value['field'] as String,
                  false,
                  entry.key,
                )),
              ],
            ),
          ),
          // Body
          Expanded(
            child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : displayData.isEmpty
                ? Center(child: Text(tr('no_data'), style: const TextStyle(fontSize: 11, color: Colors.white70)))
                : SelectionArea(
                  child: ListView.builder(
                    itemCount: displayData.length,
                    itemBuilder: (context, index) {
                      final row = displayData[index];
                      final isSelected = _selectedDetailIndices.contains(index);
                      final unit = row['unidad_medida']?.toString() ?? 'EA';
                      
                      return GestureDetector(
                        onTap: () {
                          setState(() {
                            if (isSelected) {
                              _selectedDetailIndices.remove(index);
                            } else {
                              _selectedDetailIndices.add(index);
                            }
                          });
                        },
                        child: Container(
                          height: 24,
                          color: isSelected 
                            ? AppColors.gridSelectedRow 
                            : (index.isEven ? AppColors.gridBackground : AppColors.gridRowAlt),
                          child: Row(
                            children: [
                              // Checkbox individual
                              SizedBox(
                                width: 30,
                                child: Checkbox(
                                  value: isSelected,
                                  onChanged: (value) {
                                    setState(() {
                                      if (value == true) {
                                        _selectedDetailIndices.add(index);
                                      } else {
                                        _selectedDetailIndices.remove(index);
                                      }
                                    });
                                  },
                                  side: const BorderSide(color: AppColors.border),
                                  activeColor: Colors.blue,
                                ),
                              ),
                              _buildCell(row['numero_parte']?.toString() ?? '', 0),
                              _buildCell(row['numero_lote']?.toString() ?? '', 1),
                              _buildCell(row['codigo_material_recibido']?.toString() ?? '', 2),
                              _buildCell(row['especificacion']?.toString() ?? '', 3),
                              _buildCell(row['ubicacion']?.toString() ?? '', 4),
                              _buildCell(unit, 5),
                              if (_useDateRange) ...[
                                _buildCell('${row['total_entrada']?.toString() ?? '0'} $unit', 6),
                                _buildCell('${row['total_salida']?.toString() ?? '0'} $unit', 7),
                                _buildCell('${row['stock_actual']?.toString() ?? '0'} $unit', 8),
                                _buildCell(row['fecha_recibo']?.toString() ?? '', 9),
                                _buildCell(row['fecha_salida']?.toString() ?? '', 10),
                                _buildCell(row['usuario_entrada']?.toString() ?? '', 11),
                                _buildCell(row['usuario_salida']?.toString() ?? '', 12),
                              ] else ...[
                                _buildCell('${row['stock_actual']?.toString() ?? '0'} $unit', 6),
                                _buildCell(row['fecha_recibo']?.toString() ?? '', 7),
                                _buildCell(row['fecha_salida']?.toString() ?? '', 8),
                                _buildCell(row['usuario_entrada']?.toString() ?? '', 9),
                                _buildCell(row['usuario_salida']?.toString() ?? '', 10),
                              ],
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
          ),
          GridFooter(text: '${tr('total_rows')} : ${displayData.length}${displayData.length != _originalDetailData.length ? ' / ${_originalDetailData.length}' : ''}'),
        ],
      ),
    );
  }
  
  Widget _buildHeaderCell(String label, String field, bool isSummary, int index) {
    final sortColumn =
        isSummary ? _summarySortColumn : _detailSortColumn;
    final sortAscending =
        isSummary ? _summarySortAscending : _detailSortAscending;
    final isSorted = sortColumn == field;
    final filters = isSummary ? _summaryFilters : _detailFilters;
    final hasFilter = filters.containsKey(field);
    
    return Expanded(
      flex: getColumnFlex(index),
      child: Stack(
        children: [
          Container(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        decoration: const BoxDecoration(
          border: Border(
            right: BorderSide(color: AppColors.border, width: 0.5),
          ),
        ),
        child: Row(
          children: [
            // Título de columna (clicable para ordenar)
            Expanded(
               child: GestureDetector(
                onTap: () => _sortData(
                  field,
                  isSorted ? !sortAscending : true,
                  isSummary,
                ),
                onSecondaryTapDown: (details) {
                  _showExcelColumnFilter(
                      context, field, label, isSummary, details.globalPosition);
                },
                child: Text(
                  label,
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
                sortAscending ? Icons.arrow_upward : Icons.arrow_downward,
                size: 10,
                color: Colors.blue,
              ),
            // Ícono de filtro (clicable) - mismo estilo que warehousing grid
            GestureDetector(
              onTapDown: (details) => _showExcelColumnFilter(
                  context, field, label, isSummary, details.globalPosition),
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
      Positioned(
          right: 0,
          top: 0,
          bottom: 0,
          child: buildResizeHandle(index),
        ),
        ],
      ),
    );
  }
  
  Widget _buildCell(String value, int index) {
    return Expanded(
      flex: getColumnFlex(index),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: const BoxDecoration(
          border: Border(
            right: BorderSide(color: AppColors.border, width: 0.5),
          ),
        ),
        child: _highlightText(value, _searchText),
      ),
    );
  }
}
