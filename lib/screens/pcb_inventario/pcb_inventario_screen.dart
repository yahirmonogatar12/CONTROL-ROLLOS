import 'package:flutter/material.dart';
import 'package:dropdown_button2/dropdown_button2.dart';
import 'package:material_warehousing_flutter/core/localization/app_translations.dart';
import 'package:material_warehousing_flutter/core/theme/app_colors.dart';
import 'package:material_warehousing_flutter/core/services/api_service.dart';
import 'package:material_warehousing_flutter/core/services/excel_export_service.dart';
import 'package:material_warehousing_flutter/core/widgets/field_decoration.dart';
import 'package:material_warehousing_flutter/core/widgets/resizable_grid_header.dart';

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
      initColumnFlex(12, 'pcb_inv_detail', defaultFlexValues: [
        1.2,
        2.5,
        1.5,
        1.5,
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
        color: AppColors.panelBackground,
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
                              ? Colors.cyan.withOpacity(0.20)
                              : (index.isEven
                                  ? AppColors.gridRowEven
                                  : AppColors.gridRowOdd),
                          border: Border(
                              bottom: BorderSide(
                                  color: AppColors.border.withOpacity(0.3))),
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
                              ? Colors.cyan.withOpacity(0.20)
                              : (index.isEven
                                  ? AppColors.gridRowEven
                                  : AppColors.gridRowOdd),
                          border: Border(
                              bottom: BorderSide(
                                  color: AppColors.border.withOpacity(0.3))),
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
              color: Colors.cyan.withOpacity(0.15),
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
