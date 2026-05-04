import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:dropdown_button2/dropdown_button2.dart';
import 'package:excel/excel.dart' as xl;
import 'package:file_picker/file_picker.dart';
import 'package:material_warehousing_flutter/core/localization/app_translations.dart';
import 'package:material_warehousing_flutter/core/theme/app_colors.dart';
import 'package:material_warehousing_flutter/core/services/api_service.dart';
import 'package:material_warehousing_flutter/core/services/auth_service.dart';
import 'package:material_warehousing_flutter/core/services/excel_export_service.dart';
import 'package:material_warehousing_flutter/core/widgets/field_decoration.dart';
import 'package:material_warehousing_flutter/core/widgets/resizable_grid_header.dart';
import 'package:xml/xml.dart';

class PcbInventarioScreen extends StatefulWidget {
  final LanguageProvider languageProvider;

  const PcbInventarioScreen({super.key, required this.languageProvider});

  @override
  State<PcbInventarioScreen> createState() => PcbInventarioScreenState();
}

class PcbInventarioScreenState extends State<PcbInventarioScreen>
    with SingleTickerProviderStateMixin, ResizableColumnsMixin {
  late TabController _tabController; // 0=Summary, 1=Detail

  // Data
  List<Map<String, dynamic>> _summaryData = [];
  List<Map<String, dynamic>> _summaryFiltered = [];
  List<Map<String, dynamic>> _detailData = [];
  List<Map<String, dynamic>> _detailFiltered = [];

  // Mode: current vs date range
  bool _useDateRange = false;
  DateTime _startDate = DateTime.now().subtract(const Duration(days: 30));
  DateTime _endDate = DateTime.now();

  // Search
  final TextEditingController _searchPartCtrl = TextEditingController();
  final TextEditingController _startDateCtrl = TextEditingController();
  final TextEditingController _endDateCtrl = TextEditingController();
  bool _includeZeroStock = false;
  String _selectedArea = 'ALL';
  String _selectedProceso = 'ALL';

  static const List<String> _areaOptions = ['ALL', 'INVENTARIO', 'REPARACION'];
  static const List<String> _procesoOptions = ['ALL', 'SMD', 'IMD', 'ASSY'];

  // Sorting
  String? _sortColumn;
  bool _sortAscending = true;
  Map<String, String?> _columnFilters = {};

  // Selection
  int _selectedSummaryIndex = -1;
  int _selectedDetailIndex = -1;

  bool _isLoading = false;

  String tr(String key) => widget.languageProvider.tr(key);

  // Summary columns: 8
  static const _summaryFields = [
    'pcb_part_no',
    'modelo',
    'area',
    'proceso',
    'total_entrada',
    'total_salida',
    'total_scrap',
    'stock_actual',
  ];

  // Detail columns: 12
  static const _detailFields = [
    'tipo_movimiento',
    'scanned_original',
    'pcb_part_no',
    'modelo',
    'area',
    'defect_type',
    'component_location',
    'qty',
    'array_count',
    'proceso',
    'inventory_date',
    'hora',
    'comentarios',
    'scanned_by',
  ];

  List<String> get _summaryHeaders => [
        tr('pcb_part_no'),
        tr('pcb_modelo'),
        tr('pcb_area'),
        tr('pcb_proceso'),
        tr('pcb_total_entrada'),
        tr('pcb_total_salida'),
        tr('pcb_total_scrap'),
        tr('pcb_stock_actual'),
      ];

  List<String> get _detailHeaders => [
        tr('pcb_tipo_movimiento'),
        tr('pcb_scanned_code'),
        tr('pcb_part_no'),
        tr('pcb_modelo'),
        tr('pcb_area'),
        tr('pcb_defect_type'),
        tr('pcb_component_location'),
        tr('pcb_qty'),
        tr('pcb_array_count'),
        tr('pcb_proceso'),
        tr('pcb_date'),
        tr('pcb_hora'),
        tr('pcb_comentarios'),
        tr('pcb_scanned_by'),
      ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(_onTabChanged);
    _initDates();
    initColumnFlex(8, 'pcb_inv_summary',
        defaultFlexValues: [1.8, 1.8, 1.3, 1.3, 1.0, 1.0, 1.0, 1.2]);
    _loadData();
  }

  void _initDates() {
    _startDateCtrl.text = _fmt(_startDate);
    _endDateCtrl.text = _fmt(_endDate);
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    _searchPartCtrl.dispose();
    _startDateCtrl.dispose();
    _endDateCtrl.dispose();
    super.dispose();
  }

  void _onTabChanged() {
    if (_tabController.indexIsChanging) return;
    setState(() {
      _sortColumn = null;
      _sortAscending = true;
      _columnFilters.clear();
    });
    if (_tabController.index == 0) {
      initColumnFlex(8, 'pcb_inv_summary',
          defaultFlexValues: [1.8, 1.8, 1.3, 1.3, 1.0, 1.0, 1.0, 1.2]);
    } else {
      initColumnFlex(14, 'pcb_inv_detail', defaultFlexValues: [
        1.2,
        2.5,
        1.5,
        1.5,
        1.3,
        1.4,
        1.3,
        0.8,
        1.0,
        1.2,
        1.2,
        1.0,
        1.5,
        1.2
      ]);
    }
  }

  String _fmt(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _pickDate(bool isStart) async {
    final initial = isStart ? _startDate : _endDate;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2024),
      lastDate: DateTime(2030),
    );
    if (picked != null && mounted) {
      setState(() {
        if (isStart) {
          _startDate = picked;
          _startDateCtrl.text = _fmt(picked);
        } else {
          _endDate = picked;
          _endDateCtrl.text = _fmt(picked);
        }
      });
    }
  }

  Future<void> _loadData() async {
    if (_isLoading) return;
    setState(() => _isLoading = true);

    try {
      final partNo = _searchPartCtrl.text.trim().isNotEmpty
          ? _searchPartCtrl.text.trim()
          : null;

      final summaryFuture = ApiService.getPcbStockSummary(
        numeroParte: partNo,
        area: _selectedArea,
        proceso: _selectedProceso,
        includeZeroStock: _includeZeroStock,
        fechaInicio: _useDateRange ? _startDate : null,
        fechaFin: _useDateRange ? _endDate : null,
      );

      final detailFuture = ApiService.getPcbStockDetail(
        numeroParte: partNo,
        area: _selectedArea,
        proceso: _selectedProceso,
        includeZeroStock: _includeZeroStock,
        fechaInicio: _useDateRange ? _startDate : null,
        fechaFin: _useDateRange ? _endDate : null,
      );

      final results = await Future.wait([summaryFuture, detailFuture]);

      if (mounted) {
        setState(() {
          _summaryData =
              (results[0]['data'] as List?)?.cast<Map<String, dynamic>>() ?? [];
          _detailData =
              (results[1]['data'] as List?)?.cast<Map<String, dynamic>>() ?? [];
          _summaryFiltered = List.from(_summaryData);
          _detailFiltered = List.from(_detailData);
          _selectedSummaryIndex = -1;
          _selectedDetailIndex = -1;
        });
      }
    } catch (_) {}

    if (mounted) setState(() => _isLoading = false);
  }

  void _applyFiltersSummary() {
    var data = List<Map<String, dynamic>>.from(_summaryData);
    for (final entry in _columnFilters.entries) {
      if (entry.value != null && entry.value!.isNotEmpty) {
        data = data
            .where((r) => (r[entry.key] ?? '').toString() == entry.value)
            .toList();
      }
    }
    if (_sortColumn != null) {
      data.sort((a, b) {
        final va = a[_sortColumn];
        final vb = b[_sortColumn];
        if (va is num && vb is num) {
          return _sortAscending ? va.compareTo(vb) : vb.compareTo(va);
        }
        final sa = (va ?? '').toString();
        final sb = (vb ?? '').toString();
        return _sortAscending ? sa.compareTo(sb) : sb.compareTo(sa);
      });
    }
    _summaryFiltered = data;
  }

  void _applyFiltersDetail() {
    var data = List<Map<String, dynamic>>.from(_detailData);
    for (final entry in _columnFilters.entries) {
      if (entry.value != null && entry.value!.isNotEmpty) {
        data = data
            .where((r) => (r[entry.key] ?? '').toString() == entry.value)
            .toList();
      }
    }
    if (_sortColumn != null) {
      data.sort((a, b) {
        final sa = (a[_sortColumn] ?? '').toString();
        final sb = (b[_sortColumn] ?? '').toString();
        return _sortAscending ? sa.compareTo(sb) : sb.compareTo(sa);
      });
    }
    _detailFiltered = data;
  }

  void _onSort(String field, bool ascending) {
    setState(() {
      _sortColumn = field;
      _sortAscending = ascending;
      if (_tabController.index == 0) {
        _applyFiltersSummary();
      } else {
        _applyFiltersDetail();
      }
    });
  }

  void _onFilter(String field) {
    final source = _tabController.index == 0 ? _summaryData : _detailData;
    final values = source
        .map((r) => (r[field] ?? '').toString())
        .where((v) => v.isNotEmpty)
        .toSet()
        .toList()
      ..sort();

    final currentFilter = _columnFilters[field];

    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: AppColors.panelBackground,
          title: Text('${tr('pcb_filter')}: $field',
              style: const TextStyle(color: Colors.white, fontSize: 14)),
          content: SizedBox(
            width: 250,
            height: 300,
            child: ListView(
              children: [
                ListTile(
                  dense: true,
                  title: Text(tr('pcb_all'),
                      style: TextStyle(
                        color: currentFilter == null
                            ? Colors.blue
                            : Colors.white70,
                        fontSize: 13,
                        fontWeight: currentFilter == null
                            ? FontWeight.bold
                            : FontWeight.normal,
                      )),
                  onTap: () {
                    setState(() {
                      _columnFilters.remove(field);
                      if (_tabController.index == 0)
                        _applyFiltersSummary();
                      else
                        _applyFiltersDetail();
                    });
                    Navigator.pop(ctx);
                  },
                ),
                const Divider(color: AppColors.border),
                ...values.map((v) => ListTile(
                      dense: true,
                      title: Text(v,
                          style: TextStyle(
                            color: currentFilter == v
                                ? Colors.blue
                                : Colors.white70,
                            fontSize: 13,
                            fontWeight: currentFilter == v
                                ? FontWeight.bold
                                : FontWeight.normal,
                          )),
                      onTap: () {
                        setState(() {
                          _columnFilters[field] = v;
                          if (_tabController.index == 0)
                            _applyFiltersSummary();
                          else
                            _applyFiltersDetail();
                        });
                        Navigator.pop(ctx);
                      },
                    )),
              ],
            ),
          ),
        );
      },
    );
  }

  void _onSummaryDoubleClick(int index) {
    if (index < 0 || index >= _summaryFiltered.length) return;
    final row = _summaryFiltered[index];
    final partNo = row['pcb_part_no']?.toString() ?? '';
    if (partNo.isNotEmpty) {
      _searchPartCtrl.text = partNo;
      _tabController.animateTo(1);
      _loadData();
    }
  }

  Future<void> _exportExcel() async {
    if (_tabController.index == 0) {
      await ExcelExportService.exportToExcel(
        data: _summaryFiltered,
        headers: _summaryHeaders,
        fieldMapping: _summaryFields,
        fileName: 'PCB_Inventario_Resumen',
      );
    } else {
      await ExcelExportService.exportToExcel(
        data: _detailFiltered,
        headers: _detailHeaders,
        fieldMapping: _detailFields,
        fileName: 'PCB_Inventario_Detalle',
      );
    }
  }

  Future<void> _showInitialStockImportDialog() async {
    final successMessage = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _InitialStockImportDialog(
        tr: tr,
      ),
    );
    if (successMessage != null && mounted) {
      await _loadData();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(successMessage),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildSearchBar(),
        _buildTabBar(),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildSummaryGrid(),
              _buildDetailGrid(),
            ],
          ),
        ),
        _buildFooter(),
      ],
    );
  }

  Widget _buildSearchBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        color: AppColors.subPanelBackground,
        border: Border(bottom: BorderSide(color: AppColors.border, width: 1)),
      ),
      child: Row(
        children: [
          // Part number
          Text(tr('pcb_search_part'),
              style: const TextStyle(fontSize: 14, color: Colors.white)),
          const SizedBox(width: 10),
          SizedBox(
            width: 200,
            child: TextFormField(
              controller: _searchPartCtrl,
              decoration: fieldDecoration(),
              style: const TextStyle(fontSize: 14),
              onFieldSubmitted: (_) => _loadData(),
            ),
          ),
          const SizedBox(width: 16),
          // Area
          Text(tr('pcb_area'),
              style: const TextStyle(fontSize: 14, color: Colors.white)),
          const SizedBox(width: 8),
          SizedBox(
            width: 150,
            child: DropdownButtonFormField2<String>(
              decoration: fieldDecoration(),
              value: _selectedArea,
              isExpanded: true,
              style: const TextStyle(fontSize: 14, color: Colors.white),
              items: _areaOptions
                  .map((a) => DropdownMenuItem(
                        value: a,
                        child: Text(a, style: const TextStyle(fontSize: 14)),
                      ))
                  .toList(),
              onChanged: (val) {
                if (val != null) setState(() => _selectedArea = val);
              },
              iconStyleData: const IconStyleData(
                icon: Icon(Icons.arrow_drop_down,
                    color: Colors.white70, size: 20),
              ),
              dropdownStyleData: DropdownStyleData(
                maxHeight: 200,
                decoration: BoxDecoration(
                  color: AppColors.fieldBackground,
                  borderRadius: BorderRadius.circular(4),
                ),
                padding: EdgeInsets.zero,
              ),
              menuItemStyleData: const MenuItemStyleData(
                height: 32,
                padding: EdgeInsets.symmetric(horizontal: 10),
              ),
            ),
          ),
          const SizedBox(width: 16),
          // Proceso
          Text(tr('pcb_proceso'),
              style: const TextStyle(fontSize: 14, color: Colors.white)),
          const SizedBox(width: 8),
          SizedBox(
            width: 130,
            child: DropdownButtonFormField2<String>(
              decoration: fieldDecoration(),
              value: _selectedProceso,
              isExpanded: true,
              style: const TextStyle(fontSize: 14, color: Colors.white),
              items: _procesoOptions
                  .map((p) => DropdownMenuItem(
                        value: p,
                        child: Text(p, style: const TextStyle(fontSize: 14)),
                      ))
                  .toList(),
              onChanged: (val) {
                if (val != null) setState(() => _selectedProceso = val);
              },
              iconStyleData: const IconStyleData(
                icon: Icon(Icons.arrow_drop_down,
                    color: Colors.white70, size: 20),
              ),
              dropdownStyleData: DropdownStyleData(
                maxHeight: 200,
                decoration: BoxDecoration(
                  color: AppColors.fieldBackground,
                  borderRadius: BorderRadius.circular(4),
                ),
                padding: EdgeInsets.zero,
              ),
              menuItemStyleData: const MenuItemStyleData(
                height: 32,
                padding: EdgeInsets.symmetric(horizontal: 10),
              ),
            ),
          ),
          const SizedBox(width: 20),
          // Date range
          Checkbox(
            value: _useDateRange,
            onChanged: (v) => setState(() => _useDateRange = v ?? false),
            side: const BorderSide(color: AppColors.border),
            activeColor: Colors.blue,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          const SizedBox(width: 6),
          Text(tr('pcb_date_range'),
              style: const TextStyle(fontSize: 14, color: Colors.white)),
          const SizedBox(width: 10),
          SizedBox(
            width: 130,
            child: TextFormField(
              controller: _startDateCtrl,
              readOnly: true,
              enabled: _useDateRange,
              onTap: () => _pickDate(true),
              decoration: fieldDecoration().copyWith(
                suffixIcon: const Icon(Icons.calendar_today,
                    color: Colors.white70, size: 16),
                suffixIconConstraints:
                    const BoxConstraints(minWidth: 28, minHeight: 20),
              ),
              style: const TextStyle(fontSize: 14),
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 6),
            child: Text('~',
                style: TextStyle(color: Colors.white54, fontSize: 14)),
          ),
          SizedBox(
            width: 130,
            child: TextFormField(
              controller: _endDateCtrl,
              readOnly: true,
              enabled: _useDateRange,
              onTap: () => _pickDate(false),
              decoration: fieldDecoration().copyWith(
                suffixIcon: const Icon(Icons.calendar_today,
                    color: Colors.white70, size: 16),
                suffixIconConstraints:
                    const BoxConstraints(minWidth: 28, minHeight: 20),
              ),
              style: const TextStyle(fontSize: 14),
            ),
          ),
          const SizedBox(width: 16),
          // Include zero stock
          Checkbox(
            value: _includeZeroStock,
            onChanged: (v) => setState(() => _includeZeroStock = v ?? false),
            side: const BorderSide(color: AppColors.border),
            activeColor: Colors.blue,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          const SizedBox(width: 6),
          Text(tr('pcb_include_zero_stock'),
              style: const TextStyle(fontSize: 14, color: Colors.white)),
          const Spacer(),
          SizedBox(
            height: 32,
            child: ElevatedButton.icon(
              onPressed: AuthService.canWritePcbInventory
                  ? _showInitialStockImportDialog
                  : null,
              icon: const Icon(Icons.upload_file, size: 15),
              label: Text(tr('pcb_initial_stock_upload'),
                  style: const TextStyle(fontSize: 12)),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                backgroundColor: AppColors.buttonSave,
                foregroundColor: Colors.white,
                disabledBackgroundColor: Colors.grey.shade700,
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Search
          SizedBox(
            height: 32,
            child: ElevatedButton(
              onPressed: _loadData,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                backgroundColor: AppColors.buttonSearch,
                foregroundColor: Colors.white,
              ),
              child:
                  Text(tr('pcb_search'), style: const TextStyle(fontSize: 13)),
            ),
          ),
          const SizedBox(width: 8),
          // Excel export
          SizedBox(
            height: 32,
            child: ElevatedButton(
              onPressed: _exportExcel,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                backgroundColor: AppColors.buttonExcel,
                foregroundColor: Colors.white,
              ),
              child: Text(tr('excel_export'),
                  style: const TextStyle(fontSize: 13)),
            ),
          ),
          if (_isLoading) ...[
            const SizedBox(width: 12),
            const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2)),
          ],
        ],
      ),
    );
  }

  Widget _buildTabBar() {
    return Container(
      height: 32,
      color: AppColors.panelBackground,
      child: TabBar(
        controller: _tabController,
        indicatorColor: Colors.cyan,
        labelColor: Colors.white,
        unselectedLabelColor: Colors.white54,
        labelStyle: const TextStyle(fontSize: 12),
        tabs: [
          Tab(text: '${tr('pcb_summary')} (${_summaryFiltered.length})'),
          Tab(text: '${tr('pcb_detail')} (${_detailFiltered.length})'),
        ],
      ),
    );
  }

  Widget _buildSummaryGrid() {
    return Column(
      children: [
        buildResizableHeader(
          headers: _summaryHeaders,
          fieldMapping: _summaryFields,
          onSort: _onSort,
          onFilter: _onFilter,
          sortColumn: _sortColumn,
          sortAscending: _sortAscending,
          columnFilters: _columnFilters,
          showCheckbox: false,
        ),
        Expanded(
          child: _summaryFiltered.isEmpty
              ? Center(
                  child: Text(tr('pcb_no_data'),
                      style: const TextStyle(color: Colors.white38)))
              : ListView.builder(
                  itemCount: _summaryFiltered.length,
                  itemBuilder: (context, index) {
                    final row = _summaryFiltered[index];
                    final isSelected = index == _selectedSummaryIndex;
                    final stock = (row['stock_actual'] is num)
                        ? (row['stock_actual'] as num).toInt()
                        : 0;
                    return GestureDetector(
                      onTap: () =>
                          setState(() => _selectedSummaryIndex = index),
                      onDoubleTap: () => _onSummaryDoubleClick(index),
                      child: Container(
                        height: 30,
                        decoration: BoxDecoration(
                          color: isSelected
                              ? Colors.cyan.withValues(alpha: 0.20)
                              : (index.isEven
                                  ? AppColors.gridRowEven
                                  : AppColors.gridRowOdd),
                          border: Border(
                              bottom: BorderSide(
                                  color:
                                      AppColors.border.withValues(alpha: 0.3))),
                        ),
                        child: Row(
                          children: List.generate(_summaryFields.length, (ci) {
                            final field = _summaryFields[ci];
                            final val = row[field];
                            final text = '${val ?? ''}';
                            Color textColor = Colors.white70;
                            FontWeight fw = FontWeight.normal;
                            if (field == 'stock_actual') {
                              textColor = stock > 0
                                  ? Colors.green
                                  : stock < 0
                                      ? Colors.red
                                      : Colors.white38;
                              fw = FontWeight.w600;
                            } else if (field == 'total_entrada') {
                              textColor = Colors.green.shade300;
                            } else if (field == 'total_salida') {
                              textColor = Colors.orange.shade300;
                            } else if (field == 'total_scrap') {
                              textColor = Colors.red.shade300;
                            }
                            return Expanded(
                              flex: getColumnFlex(ci),
                              child: Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 6),
                                child: Text(
                                  text,
                                  style: TextStyle(
                                      color: textColor,
                                      fontSize: 12,
                                      fontWeight: fw),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            );
                          }),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildDetailGrid() {
    return Column(
      children: [
        buildResizableHeader(
          headers: _detailHeaders,
          fieldMapping: _detailFields,
          onSort: _onSort,
          onFilter: _onFilter,
          sortColumn: _sortColumn,
          sortAscending: _sortAscending,
          columnFilters: _columnFilters,
          showCheckbox: false,
        ),
        Expanded(
          child: _detailFiltered.isEmpty
              ? Center(
                  child: Text(tr('pcb_no_data'),
                      style: const TextStyle(color: Colors.white38)))
              : ListView.builder(
                  itemCount: _detailFiltered.length,
                  itemBuilder: (context, index) {
                    final row = _detailFiltered[index];
                    final isSelected = index == _selectedDetailIndex;
                    final tipo = (row['tipo_movimiento'] ?? '').toString();
                    Color tipoColor;
                    switch (tipo) {
                      case 'ENTRADA':
                        tipoColor = Colors.green;
                        break;
                      case 'SALIDA':
                        tipoColor = Colors.orange;
                        break;
                      case 'SCRAP':
                        tipoColor = Colors.red;
                        break;
                      default:
                        tipoColor = Colors.white70;
                    }
                    return GestureDetector(
                      onTap: () => setState(() => _selectedDetailIndex = index),
                      child: Container(
                        height: 30,
                        decoration: BoxDecoration(
                          color: isSelected
                              ? Colors.cyan.withValues(alpha: 0.20)
                              : (index.isEven
                                  ? AppColors.gridRowEven
                                  : AppColors.gridRowOdd),
                          border: Border(
                              bottom: BorderSide(
                                  color:
                                      AppColors.border.withValues(alpha: 0.3))),
                        ),
                        child: Row(
                          children: List.generate(_detailFields.length, (ci) {
                            final field = _detailFields[ci];
                            final val = '${row[field] ?? ''}';
                            final color = ci == 0 ? tipoColor : Colors.white70;
                            final fw =
                                ci == 0 ? FontWeight.w600 : FontWeight.normal;
                            return Expanded(
                              flex: getColumnFlex(ci),
                              child: Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 6),
                                child: Text(
                                  val,
                                  style: TextStyle(
                                      color: color,
                                      fontSize: 12,
                                      fontWeight: fw),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            );
                          }),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildFooter() {
    final totalStock = _summaryFiltered.fold<int>(0, (sum, r) {
      final v = r['stock_actual'];
      return sum + (v is num ? v.toInt() : 0);
    });

    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: AppColors.panelBackground,
        border: Border(top: BorderSide(color: AppColors.border, width: 1)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.cyan.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              tr('pcb_inventario_title'),
              style: const TextStyle(
                  color: Colors.cyan,
                  fontSize: 11,
                  fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            '${tr('pcb_stock_actual')}: $totalStock',
            style: TextStyle(
              color: totalStock > 0 ? Colors.green : Colors.white54,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 12),
          Text(
            '${tr('pcb_summary')}: ${_summaryFiltered.length} | ${tr('pcb_detail')}: ${_detailFiltered.length}',
            style: const TextStyle(color: Colors.white38, fontSize: 11),
          ),
          const Spacer(),
          if (_useDateRange)
            Text(
              '${_fmt(_startDate)} ~ ${_fmt(_endDate)}',
              style: const TextStyle(color: Colors.white38, fontSize: 11),
            )
          else
            Text(
              tr('pcb_all_time'),
              style: const TextStyle(color: Colors.white38, fontSize: 11),
            ),
        ],
      ),
    );
  }
}

class _InitialStockImportDialog extends StatefulWidget {
  final String Function(String key) tr;

  const _InitialStockImportDialog({
    required this.tr,
  });

  @override
  State<_InitialStockImportDialog> createState() =>
      _InitialStockImportDialogState();
}

class _InitialStockImportDialogState extends State<_InitialStockImportDialog> {
  final TextEditingController _dateController = TextEditingController();
  final TextEditingController _commentController = TextEditingController();
  DateTime _inventoryDate = DateTime.now();
  String _selectedArea = 'INVENTARIO';
  String _selectedProceso = 'SMD';
  String? _fileName;
  bool _isSubmitting = false;
  int _submittedBatches = 0;
  int _totalBatches = 0;
  List<Map<String, dynamic>> _items = [];
  List<Map<String, dynamic>> _parseErrors = [];

  static const _areas = ['INVENTARIO', 'REPARACION'];
  static const _procesos = ['SMD', 'IMD', 'ASSY'];

  String tr(String key) => widget.tr(key);

  @override
  void initState() {
    super.initState();
    _dateController.text = _fmt(_inventoryDate);
  }

  @override
  void dispose() {
    _dateController.dispose();
    _commentController.dispose();
    super.dispose();
  }

  String _fmt(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _inventoryDate,
      firstDate: DateTime(2024),
      lastDate: DateTime(2030),
    );
    if (picked != null && mounted) {
      setState(() {
        _inventoryDate = picked;
        _dateController.text = _fmt(picked);
      });
    }
  }

  Future<void> _selectFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'xls', 'csv'],
        dialogTitle: tr('pcb_select_initial_stock_file'),
      );
      if (result == null || result.files.isEmpty) return;

      final path = result.files.single.path;
      if (path == null) return;

      final file = File(path);
      final bytes = await file.readAsBytes();
      final extension = result.files.single.extension?.toLowerCase();

      final parsed = extension == 'csv'
          ? _parseCsv(String.fromCharCodes(bytes))
          : _parseExcel(bytes);

      setState(() {
        _fileName = result.files.single.name;
        _items = parsed.items;
        _parseErrors = parsed.errors;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _items = [];
        _parseErrors = [
          {
            'row': '-',
            'message': '${tr('pcb_initial_stock_file_error')}: $e',
          }
        ];
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(tr('pcb_initial_stock_file_error')),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  _ParsedInitialStock _parseCsv(String content) {
    final rows = content
        .split(RegExp(r'\r?\n'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .map((line) => line.split(RegExp(r'\t|,|;')))
        .toList();
    return _parseRows(rows);
  }

  _ParsedInitialStock _parseExcel(List<int> bytes) {
    try {
      final book = xl.Excel.decodeBytes(bytes);
      if (book.tables.isEmpty) {
        return _ParsedInitialStock(items: [], errors: []);
      }
      final sheet = book.tables.values.first;
      final rows = <List<String>>[];
      for (var i = 0; i < sheet.maxRows; i++) {
        final row = sheet.row(i);
        rows.add(row.map((cell) => cell?.value?.toString() ?? '').toList());
      }
      return _parseRows(rows);
    } catch (_) {
      final rows = _parseXlsxWithoutStyles(bytes);
      return _parseRows(rows);
    }
  }

  List<List<String>> _parseXlsxWithoutStyles(List<int> bytes) {
    final archive = ZipDecoder().decodeBytes(bytes);
    final sharedStrings = _readSharedStrings(archive);
    final sheetPath = _findFirstWorksheetPath(archive);
    final sheetFile = archive.files.firstWhere(
      (file) => file.name == sheetPath,
      orElse: () => throw Exception('Worksheet not found'),
    );
    final sheetXml = Utf8Decoder().convert(sheetFile.content as List<int>);
    final document = XmlDocument.parse(sheetXml);
    final rows = <List<String>>[];

    for (final rowNode in document.findAllElements('row')) {
      final cells = <int, String>{};
      var maxColumnIndex = -1;
      for (final cellNode in rowNode.findElements('c')) {
        final ref = cellNode.getAttribute('r') ?? '';
        final columnIndex = _columnIndexFromCellRef(ref);
        if (columnIndex < 0) continue;
        if (columnIndex > maxColumnIndex) maxColumnIndex = columnIndex;
        cells[columnIndex] = _readCellValue(cellNode, sharedStrings);
      }

      if (maxColumnIndex < 0) {
        rows.add(<String>[]);
        continue;
      }

      final row = List<String>.filled(maxColumnIndex + 1, '');
      cells.forEach((index, value) => row[index] = value);
      rows.add(row);
    }

    return rows;
  }

  List<String> _readSharedStrings(Archive archive) {
    final sharedFile = archive.files
        .where((file) => file.name == 'xl/sharedStrings.xml')
        .cast<ArchiveFile?>()
        .firstWhere((file) => file != null, orElse: () => null);
    if (sharedFile == null) return const [];

    final xml = Utf8Decoder().convert(sharedFile.content as List<int>);
    final document = XmlDocument.parse(xml);
    return document
        .findAllElements('si')
        .map((si) => si.findAllElements('t').map((t) => t.innerText).join())
        .toList();
  }

  String _findFirstWorksheetPath(Archive archive) {
    final workbookFile = archive.files.firstWhere(
      (file) => file.name == 'xl/workbook.xml',
      orElse: () => throw Exception('Workbook not found'),
    );
    final relsFile = archive.files.firstWhere(
      (file) => file.name == 'xl/_rels/workbook.xml.rels',
      orElse: () => throw Exception('Workbook relationships not found'),
    );

    final workbookXml =
        Utf8Decoder().convert(workbookFile.content as List<int>);
    final relsXml = Utf8Decoder().convert(relsFile.content as List<int>);
    final workbookDoc = XmlDocument.parse(workbookXml);
    final relsDoc = XmlDocument.parse(relsXml);

    final firstSheet = workbookDoc.findAllElements('sheet').first;
    final relId = firstSheet.getAttribute('id',
        namespace:
            'http://schemas.openxmlformats.org/officeDocument/2006/relationships');
    if (relId == null) {
      throw Exception('Worksheet relationship id not found');
    }

    final relNode = relsDoc.findAllElements('Relationship').firstWhere(
          (node) => node.getAttribute('Id') == relId,
        );
    final target = relNode.getAttribute('Target');
    if (target == null || target.isEmpty) {
      throw Exception('Worksheet target not found');
    }
    return target.startsWith('xl/') ? target : 'xl/$target';
  }

  int _columnIndexFromCellRef(String ref) {
    final match = RegExp(r'([A-Z]+)').firstMatch(ref.toUpperCase());
    if (match == null) return -1;
    final letters = match.group(1)!;
    var result = 0;
    for (final codeUnit in letters.codeUnits) {
      result = result * 26 + (codeUnit - 64);
    }
    return result - 1;
  }

  String _readCellValue(XmlElement cellNode, List<String> sharedStrings) {
    final type = cellNode.getAttribute('t');
    if (type == 'inlineStr') {
      return cellNode.findAllElements('t').map((node) => node.innerText).join();
    }

    final valueText = cellNode.getElement('v')?.innerText ?? '';
    if (type == 's') {
      final index = int.tryParse(valueText);
      if (index == null || index < 0 || index >= sharedStrings.length) {
        return '';
      }
      return sharedStrings[index];
    }
    return valueText;
  }

  _ParsedInitialStock _parseRows(List<List<String>> rows) {
    final items = <Map<String, dynamic>>[];
    final errors = <Map<String, dynamic>>[];
    if (rows.isEmpty) return _ParsedInitialStock(items: items, errors: errors);

    var partIndex = 0;
    var qtyIndex = 1;
    var startRow = 0;
    final first = rows.first.map(_normalizeHeader).toList();
    final headerPartIndex = _findHeaderIndex(first, {
      'nopartepcb',
      'pcbpartnumber',
      'numeroparte',
      'noparte',
      'partno',
      'partnumber',
      'pcbpartno',
    });
    final headerQtyIndex = _findHeaderIndex(first, {
      'cantidad',
      'cant',
      'qty',
      'quantity',
    });
    if (headerPartIndex >= 0 && headerQtyIndex >= 0) {
      partIndex = headerPartIndex;
      qtyIndex = headerQtyIndex;
      startRow = 1;
    }

    for (var i = startRow; i < rows.length; i++) {
      final row = rows[i];
      final rowNumber = i + 1;
      final partNo =
          row.length > partIndex ? row[partIndex].trim().toUpperCase() : '';
      final qtyText = row.length > qtyIndex ? row[qtyIndex].trim() : '';
      if (partNo.isEmpty && qtyText.isEmpty) continue;

      final qty = int.tryParse(qtyText.replaceAll(RegExp(r'\.0$'), ''));
      if (!RegExp(r'^EBR\d{8}$').hasMatch(partNo)) {
        errors.add({
          'row': rowNumber,
          'pcb_part_no': partNo,
          'message': tr('pcb_invalid_part_no'),
        });
        continue;
      }
      if (qty == null || qty <= 0) {
        errors.add({
          'row': rowNumber,
          'pcb_part_no': partNo,
          'message': tr('pcb_invalid_qty'),
        });
        continue;
      }

      items.add({
        'row_number': rowNumber,
        'pcb_part_no': partNo,
        'qty': qty,
      });
    }

    return _ParsedInitialStock(items: items, errors: errors);
  }

  int _findHeaderIndex(List<String> headers, Set<String> aliases) {
    for (var i = 0; i < headers.length; i++) {
      if (aliases.contains(headers[i])) return i;
    }
    return -1;
  }

  String _normalizeHeader(String value) {
    return value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '').trim();
  }

  List<Map<String, dynamic>> get _groupedItems {
    final grouped = <String, int>{};
    for (final item in _items) {
      final partNo = item['pcb_part_no'].toString();
      final qty = item['qty'] as int;
      grouped[partNo] = (grouped[partNo] ?? 0) + qty;
    }
    return grouped.entries
        .map((entry) => {'pcb_part_no': entry.key, 'qty': entry.value})
        .toList()
      ..sort((a, b) =>
          a['pcb_part_no'].toString().compareTo(b['pcb_part_no'].toString()));
  }

  int get _totalQty => _items.fold<int>(
        0,
        (sum, item) => sum + (item['qty'] as int),
      );

  Future<void> _import() async {
    if (_items.isEmpty || _isSubmitting) return;
    final groupedItems = _groupedItems;
    const batchSize = 200;
    final totalBatches = (groupedItems.length / batchSize).ceil();
    setState(() {
      _isSubmitting = true;
      _submittedBatches = 0;
      _totalBatches = totalBatches;
    });

    var inserted = 0;
    var totalQty = 0;
    Map<String, dynamic>? lastError;

    for (var offset = 0; offset < groupedItems.length; offset += batchSize) {
      final batch = groupedItems.skip(offset).take(batchSize).toList();
      final response = await ApiService.bulkAddPcbInitialStock(
        inventoryDate: _fmt(_inventoryDate),
        area: _selectedArea,
        proceso: _selectedProceso,
        items: batch,
        comentarios: _commentController.text.trim().isNotEmpty
            ? _commentController.text.trim()
            : null,
        scannedBy: AuthService.currentUser?.nombreCompleto,
      );

      if (response['success'] != true) {
        lastError = response;
        break;
      }

      inserted += (response['inserted'] as num?)?.toInt() ?? 0;
      totalQty += (response['total_qty'] as num?)?.toInt() ?? 0;
      if (!mounted) return;
      setState(() => _submittedBatches += 1);
    }

    if (!mounted) return;
    setState(() => _isSubmitting = false);

    if (lastError == null) {
      final successMessage =
          '${tr('pcb_initial_stock_imported')}: $inserted ${tr('pcb_grouped_parts')} / $totalQty ${tr('pcb_total_qty')}';
      Navigator.pop(context, successMessage);
    } else {
      final partialPrefix = inserted > 0
          ? '${tr('pcb_initial_stock_partial')}: $inserted ${tr('pcb_grouped_parts')} / $totalQty ${tr('pcb_total_qty')}. '
          : '';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '$partialPrefix${lastError['message']?.toString() ?? tr('pcb_scan_error')}',
          ),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final grouped = _groupedItems;
    return AlertDialog(
      backgroundColor: AppColors.panelBackground,
      title: Text(tr('pcb_initial_stock_upload'),
          style: const TextStyle(color: Colors.white, fontSize: 16)),
      content: SizedBox(
        width: 720,
        height: 520,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                SizedBox(
                  width: 150,
                  child: TextFormField(
                    controller: _dateController,
                    readOnly: true,
                    onTap: _pickDate,
                    decoration: fieldDecoration().copyWith(
                      labelText: tr('pcb_date'),
                      labelStyle:
                          const TextStyle(color: Colors.white70, fontSize: 12),
                      suffixIcon: const Icon(Icons.calendar_today,
                          color: Colors.white70, size: 16),
                    ),
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 160,
                  child: DropdownButtonFormField2<String>(
                    decoration: fieldDecoration(),
                    value: _selectedArea,
                    isExpanded: true,
                    items: _areas
                        .map((area) => DropdownMenuItem(
                              value: area,
                              child: Text(area,
                                  style: const TextStyle(fontSize: 13)),
                            ))
                        .toList(),
                    onChanged: (value) {
                      if (value != null) setState(() => _selectedArea = value);
                    },
                    dropdownStyleData: DropdownStyleData(
                      width: 160,
                      maxHeight: 160,
                      decoration: BoxDecoration(
                        color: AppColors.fieldBackground,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      padding: EdgeInsets.zero,
                    ),
                    menuItemStyleData: const MenuItemStyleData(
                      height: 32,
                      padding: EdgeInsets.symmetric(horizontal: 10),
                    ),
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 130,
                  child: DropdownButtonFormField2<String>(
                    decoration: fieldDecoration(),
                    value: _selectedProceso,
                    isExpanded: true,
                    items: _procesos
                        .map((proceso) => DropdownMenuItem(
                              value: proceso,
                              child: Text(proceso,
                                  style: const TextStyle(fontSize: 13)),
                            ))
                        .toList(),
                    onChanged: (value) {
                      if (value != null) {
                        setState(() => _selectedProceso = value);
                      }
                    },
                    dropdownStyleData: DropdownStyleData(
                      width: 130,
                      maxHeight: 140,
                      decoration: BoxDecoration(
                        color: AppColors.fieldBackground,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      padding: EdgeInsets.zero,
                    ),
                    menuItemStyleData: const MenuItemStyleData(
                      height: 32,
                      padding: EdgeInsets.symmetric(horizontal: 10),
                    ),
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                  ),
                ),
                const Spacer(),
                SizedBox(
                  height: 34,
                  child: ElevatedButton.icon(
                    onPressed: _selectFile,
                    icon: const Icon(Icons.upload_file, size: 16),
                    label: Text(tr('pcb_select_file'),
                        style: const TextStyle(fontSize: 12)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.buttonExcel,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _commentController,
              decoration: fieldDecoration().copyWith(
                labelText: tr('pcb_comentarios'),
                labelStyle:
                    const TextStyle(color: Colors.white70, fontSize: 12),
              ),
              style: const TextStyle(color: Colors.white, fontSize: 13),
            ),
            const SizedBox(height: 10),
            Text(
              _fileName == null
                  ? tr('pcb_initial_stock_template_hint')
                  : '${tr('pcb_selected_file')}: $_fileName',
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                _buildMetric(
                    tr('pcb_rows_valid'), '${_items.length}', Colors.green),
                const SizedBox(width: 8),
                _buildMetric(
                    tr('pcb_grouped_parts'), '${grouped.length}', Colors.cyan),
                const SizedBox(width: 8),
                _buildMetric(tr('pcb_total_qty'), '$_totalQty', Colors.orange),
                const SizedBox(width: 8),
                _buildMetric(tr('pcb_errors'), '${_parseErrors.length}',
                    _parseErrors.isEmpty ? Colors.white54 : Colors.red),
                if (_isSubmitting) ...[
                  const SizedBox(width: 8),
                  _buildMetric(
                    tr('pcb_import_progress'),
                    '$_submittedBatches/$_totalBatches',
                    Colors.blue,
                  ),
                ],
              ],
            ),
            const SizedBox(height: 10),
            Expanded(
              child: Row(
                children: [
                  Expanded(
                    child: _buildPreviewList(
                      title: tr('pcb_preview_grouped'),
                      rows: grouped
                          .take(200)
                          .map((item) =>
                              '${item['pcb_part_no']}  |  ${item['qty']}')
                          .toList(),
                      emptyText: tr('pcb_no_data'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildPreviewList(
                      title: tr('pcb_errors'),
                      rows: _parseErrors
                          .take(200)
                          .map((error) =>
                              '${tr('row')} ${error['row']}: ${error['message']}')
                          .toList(),
                      emptyText: tr('pcb_no_errors'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSubmitting ? null : () => Navigator.pop(context),
          child:
              Text(tr('cancel'), style: const TextStyle(color: Colors.white70)),
        ),
        ElevatedButton(
          onPressed: _items.isEmpty || _isSubmitting ? null : _import,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.buttonSave,
            disabledBackgroundColor: Colors.grey.shade700,
          ),
          child: _isSubmitting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(tr('import'), style: const TextStyle(color: Colors.white)),
        ),
      ],
    );
  }

  Widget _buildMetric(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        '$label: $value',
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildPreviewList({
    required String title,
    required List<String> rows,
    required String emptyText,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.gridBackground,
        border: Border.all(color: AppColors.border.withValues(alpha: 0.5)),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 30,
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            color: AppColors.gridHeader,
            child: Text(title,
                style: const TextStyle(color: Colors.white, fontSize: 12)),
          ),
          Expanded(
            child: rows.isEmpty
                ? Center(
                    child: Text(emptyText,
                        style: const TextStyle(
                            color: Colors.white38, fontSize: 12)),
                  )
                : ListView.builder(
                    itemCount: rows.length,
                    itemBuilder: (context, index) {
                      return Container(
                        height: 26,
                        alignment: Alignment.centerLeft,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        color: index.isEven
                            ? AppColors.gridRowEven
                            : AppColors.gridRowOdd,
                        child: Text(
                          rows[index],
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 12),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _ParsedInitialStock {
  final List<Map<String, dynamic>> items;
  final List<Map<String, dynamic>> errors;

  const _ParsedInitialStock({
    required this.items,
    required this.errors,
  });
}
