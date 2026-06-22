import 'package:flutter/material.dart';
import 'package:material_warehousing_flutter/core/localization/app_translations.dart';
import 'package:material_warehousing_flutter/core/theme/app_colors.dart';
import 'package:material_warehousing_flutter/core/services/api_service.dart';
import 'package:material_warehousing_flutter/core/widgets/resizable_grid_header.dart';
import 'package:material_warehousing_flutter/core/widgets/searchable_column_filter_dialog.dart';

class PcbEntradaGridPanel extends StatefulWidget {
  final LanguageProvider languageProvider;

  const PcbEntradaGridPanel({super.key, required this.languageProvider});

  @override
  State<PcbEntradaGridPanel> createState() => PcbEntradaGridPanelState();
}

class PcbEntradaGridPanelState extends State<PcbEntradaGridPanel>
    with AutomaticKeepAliveClientMixin, ResizableColumnsMixin {
  List<Map<String, dynamic>> _allData = [];
  List<Map<String, dynamic>> _filteredData = [];

  // Sorting
  String? _sortColumn;
  bool _sortAscending = true;

  // Column filters
  Map<String, String?> _columnFilters = {};

  // Selection
  int _selectedIndex = -1;

  bool _isLoading = false;

  // Date filter
  DateTime? _searchStart;
  DateTime? _searchEnd;
  String? _searchPartNumber;

  static const _fields = [
    'scanned_original',
    'area',
    'defect_type',
    'etapa_deteccion',
    'component_location',
    'qty',
    'array_count',
    'pcb_part_no',
    'modelo',
    'proceso',
    'inventory_date',
    'hora',
    'comentarios',
    'scanned_by',
  ];

  String tr(String key) => widget.languageProvider.tr(key);

  List<String> get _headers => [
        tr('pcb_scanned_code'),
        tr('pcb_area'),
        tr('pcb_defect_type'),
        tr('pcb_etapa_deteccion'),
        tr('pcb_component_location'),
        tr('pcb_qty'),
        tr('pcb_array_count'),
        tr('pcb_part_no'),
        tr('pcb_modelo'),
        tr('pcb_proceso'),
        tr('pcb_date'),
        tr('pcb_hora'),
        tr('pcb_comentarios'),
        tr('pcb_scanned_by'),
      ];

  @override
  bool get wantKeepAlive => true;

  static const int _etapaColIdx = 3;

  Color _etapaColor(String? etapa) {
    switch (etapa) {
      case 'LQC':
        return Colors.orange;
      case 'OQC':
        return Colors.purpleAccent;
      case 'AIS':
        return Colors.cyan;
      default:
        return Colors.white38;
    }
  }

  @override
  void initState() {
    super.initState();
    initColumnFlex(14, 'pcb_entrada_grid', defaultFlexValues: [
      2.5,
      1.0,
      1.4,
      0.8,
      1.3,
      0.8,
      1.0,
      1.5,
      1.5,
      1.2,
      1.2,
      1.0,
      1.5,
      1.2
    ]);
    _loadTodayData();
  }

  void _loadTodayData() {
    final now = DateTime.now();
    searchByDate(now, now);
  }

  Future<void> searchByDate(DateTime? start, DateTime? end,
      {String? partNumber}) async {
    final s = start ?? DateTime.now();
    final e = end ?? DateTime.now();
    _searchStart = s;
    _searchEnd = e;
    _searchPartNumber = partNumber;

    setState(() => _isLoading = true);

    try {
      // Load data for each day in the range via the scans endpoint
      List<Map<String, dynamic>> allRows = [];
      DateTime current = s;
      while (!current.isAfter(e)) {
        final dateStr =
            '${current.year}-${current.month.toString().padLeft(2, '0')}-${current.day.toString().padLeft(2, '0')}';
        final result = await ApiService.getPcbInventoryScans(
          inventoryDate: dateStr,
          tipoMovimiento: 'ENTRADA',
          limit: 5000,
        );
        if (result['success'] == true && result['data'] != null) {
          allRows.addAll((result['data'] as List).cast<Map<String, dynamic>>());
        }
        current = current.add(const Duration(days: 1));
      }

      // Filter by part number if provided
      if (partNumber != null && partNumber.isNotEmpty) {
        allRows = allRows.where((r) {
          final pn = (r['pcb_part_no'] ?? '').toString().toUpperCase();
          return pn.contains(partNumber.toUpperCase());
        }).toList();
      }

      if (mounted) {
        setState(() {
          _allData = allRows;
          _applyFiltersAndSort();
          _selectedIndex = -1;
        });
      }
    } catch (_) {}

    if (mounted) setState(() => _isLoading = false);
  }

  void reloadData() {
    searchByDate(_searchStart, _searchEnd, partNumber: _searchPartNumber);
  }

  List<Map<String, dynamic>> getDataForExport() => _filteredData;

  void _applyFiltersAndSort() {
    var data = List<Map<String, dynamic>>.from(_allData);

    // Apply column filters
    for (final entry in _columnFilters.entries) {
      if (entry.value != null && entry.value!.isNotEmpty) {
        data = data.where((r) {
          return matchesColumnFilterValue(r[entry.key], entry.value!);
        }).toList();
      }
    }

    // Apply sorting
    if (_sortColumn != null) {
      data.sort((a, b) {
        final va = (a[_sortColumn] ?? '').toString();
        final vb = (b[_sortColumn] ?? '').toString();
        return _sortAscending ? va.compareTo(vb) : vb.compareTo(va);
      });
    }

    _filteredData = data;
  }

  void _onSort(String field, bool ascending) {
    setState(() {
      _sortColumn = field;
      _sortAscending = ascending;
      _applyFiltersAndSort();
    });
  }

  String _headerForField(String field) {
    final index = _fields.indexOf(field);
    return index >= 0 && index < _headers.length ? _headers[index] : field;
  }

  void _onFilter(String field) {
    final values = _allData
        .map((r) => (r[field] ?? '').toString())
        .where((v) => v.isNotEmpty)
        .toSet()
        .toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    final currentFilter = _columnFilters[field];

    showSearchableColumnFilterDialog(
      context: context,
      title: '${tr('pcb_filter')}: ${_headerForField(field)}',
      values: values,
      allLabel: tr('pcb_all'),
      searchLabel: tr('search'),
      applyLabel: tr('apply'),
      clearFilterLabel: tr('clear_filter'),
      currentFilter: currentFilter,
    ).then((result) {
      if (!mounted || result == null) return;
      setState(() {
        final filterValue = result.filterValue;
        if (filterValue == null || filterValue.isEmpty) {
          _columnFilters.remove(field);
        } else {
          _columnFilters[field] = filterValue;
        }
        _applyFiltersAndSort();
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return Column(
      children: [
        // Header
        buildResizableHeader(
          headers: _headers,
          fieldMapping: _fields,
          onSort: _onSort,
          onFilter: _onFilter,
          sortColumn: _sortColumn,
          sortAscending: _sortAscending,
          columnFilters: _columnFilters,
          showCheckbox: false,
        ),
        // Rows
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _filteredData.isEmpty
                  ? Center(
                      child: Text(tr('pcb_no_data'),
                          style: const TextStyle(color: Colors.white38)))
                  : ListView.builder(
                      itemCount: _filteredData.length,
                      itemBuilder: (context, index) {
                        final row = _filteredData[index];
                        final isSelected = index == _selectedIndex;
                        return GestureDetector(
                          onTap: () => setState(() => _selectedIndex = index),
                          child: Container(
                            height: 30,
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? Colors.green.withValues(alpha: 0.20)
                                  : (index.isEven
                                      ? AppColors.gridRowEven
                                      : AppColors.gridRowOdd),
                              border: Border(
                                  bottom: BorderSide(
                                      color: AppColors.border
                                          .withValues(alpha: 0.3))),
                            ),
                            child: Row(
                              children: List.generate(_fields.length, (ci) {
                                if (ci == _etapaColIdx) {
                                  final etapa =
                                      (row[_fields[ci]] ?? '').toString();
                                  return Expanded(
                                    flex: getColumnFlex(ci),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 6, vertical: 4),
                                      child: etapa.isEmpty
                                          ? const SizedBox()
                                          : Container(
                                              alignment: Alignment.center,
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 6,
                                                      vertical: 2),
                                              decoration: BoxDecoration(
                                                color: _etapaColor(etapa)
                                                    .withValues(alpha: 0.18),
                                                borderRadius:
                                                    BorderRadius.circular(3),
                                                border: Border.all(
                                                    color: _etapaColor(etapa),
                                                    width: 1),
                                              ),
                                              child: Text(
                                                etapa,
                                                style: TextStyle(
                                                  color: _etapaColor(etapa),
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                    ),
                                  );
                                }
                                return Expanded(
                                  flex: getColumnFlex(ci),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6),
                                    child: Text(
                                      '${row[_fields[ci]] ?? ''}',
                                      style: const TextStyle(
                                          color: Colors.white70, fontSize: 12),
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
        // Footer
        Container(
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
                  color: Colors.green.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  tr('pcb_tab_entrada'),
                  style: const TextStyle(
                      color: Colors.green,
                      fontSize: 11,
                      fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '${tr('pcb_total_scans')}: ${_filteredData.length}',
                style: const TextStyle(color: Colors.white54, fontSize: 11),
              ),
              if (_columnFilters.isNotEmpty) ...[
                const SizedBox(width: 12),
                Text(
                  '(${_allData.length} ${tr('pcb_all')})',
                  style: const TextStyle(color: Colors.white38, fontSize: 11),
                ),
              ],
              const Spacer(),
            ],
          ),
        ),
      ],
    );
  }
}
