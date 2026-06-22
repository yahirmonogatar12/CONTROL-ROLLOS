import 'package:flutter/material.dart';
import 'package:material_warehousing_flutter/core/localization/app_translations.dart';
import 'package:material_warehousing_flutter/core/theme/app_colors.dart';
import 'package:material_warehousing_flutter/core/services/api_service.dart';
import 'package:material_warehousing_flutter/core/widgets/resizable_grid_header.dart';
import 'package:material_warehousing_flutter/core/widgets/searchable_column_filter_dialog.dart';

class PcbSalidaGridPanel extends StatefulWidget {
  final LanguageProvider languageProvider;

  const PcbSalidaGridPanel({super.key, required this.languageProvider});

  @override
  State<PcbSalidaGridPanel> createState() => PcbSalidaGridPanelState();
}

class PcbSalidaGridPanelState extends State<PcbSalidaGridPanel>
    with AutomaticKeepAliveClientMixin, ResizableColumnsMixin {
  List<Map<String, dynamic>> _allData = [];
  List<Map<String, dynamic>> _filteredData = [];

  String? _sortColumn;
  bool _sortAscending = true;
  Map<String, String?> _columnFilters = {};
  int _selectedIndex = -1;
  bool _isLoading = false;

  DateTime? _searchStart;
  DateTime? _searchEnd;
  String? _searchPartNumber;
  String? _searchTipoFilter;

  // 10 columns: tipo_movimiento + the scan fields
  static const _fields = [
    'tipo_movimiento',
    'scanned_original',
    'area',
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
        tr('pcb_tipo_movimiento'),
        tr('pcb_scanned_code'),
        tr('pcb_area'),
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

  @override
  void initState() {
    super.initState();
    initColumnFlex(10, 'pcb_salida_grid',
        defaultFlexValues: [1.2, 2.5, 1.0, 1.5, 1.5, 1.2, 1.2, 1.0, 1.5, 1.2]);
    _loadTodayData();
  }

  void _loadTodayData() {
    final now = DateTime.now();
    searchByDate(now, now);
  }

  Future<void> searchByDate(DateTime? start, DateTime? end,
      {String? partNumber, String? tipoFilter}) async {
    final s = start ?? DateTime.now();
    final e = end ?? DateTime.now();
    _searchStart = s;
    _searchEnd = e;
    _searchPartNumber = partNumber;
    _searchTipoFilter = tipoFilter;

    setState(() => _isLoading = true);

    try {
      List<Map<String, dynamic>> allRows = [];
      // Load both SALIDA and SCRAP for each day
      final tipos = (tipoFilter != null) ? [tipoFilter] : ['SALIDA', 'SCRAP'];

      DateTime current = s;
      while (!current.isAfter(e)) {
        final dateStr =
            '${current.year}-${current.month.toString().padLeft(2, '0')}-${current.day.toString().padLeft(2, '0')}';
        for (final tipo in tipos) {
          final result = await ApiService.getPcbInventoryScans(
            inventoryDate: dateStr,
            tipoMovimiento: tipo,
            limit: 5000,
          );
          if (result['success'] == true && result['data'] != null) {
            allRows
                .addAll((result['data'] as List).cast<Map<String, dynamic>>());
          }
        }
        current = current.add(const Duration(days: 1));
      }

      // Sort by date desc
      allRows.sort((a, b) {
        final ca = a['created_at']?.toString() ?? '';
        final cb = b['created_at']?.toString() ?? '';
        return cb.compareTo(ca);
      });

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
    searchByDate(_searchStart, _searchEnd,
        partNumber: _searchPartNumber, tipoFilter: _searchTipoFilter);
  }

  List<Map<String, dynamic>> getDataForExport() => _filteredData;

  void _applyFiltersAndSort() {
    var data = List<Map<String, dynamic>>.from(_allData);

    for (final entry in _columnFilters.entries) {
      if (entry.value != null && entry.value!.isNotEmpty) {
        data = data.where((r) {
          return matchesColumnFilterValue(r[entry.key], entry.value!);
        }).toList();
      }
    }

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

  Color _tipoColor(String tipo) {
    switch (tipo) {
      case 'SCRAP':
        return Colors.red;
      case 'SALIDA':
        return Colors.orange;
      default:
        return Colors.white70;
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return Column(
      children: [
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
                        final tipo = (row['tipo_movimiento'] ?? '').toString();
                        final tipoC = _tipoColor(tipo);
                        return GestureDetector(
                          onTap: () => setState(() => _selectedIndex = index),
                          child: Container(
                            height: 30,
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? tipoC.withValues(alpha: 0.20)
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
                                final val = '${row[_fields[ci]] ?? ''}';
                                final color = ci == 0 ? tipoC : Colors.white70;
                                final fw = ci == 0
                                    ? FontWeight.w600
                                    : FontWeight.normal;
                                return Expanded(
                                  flex: getColumnFlex(ci),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6),
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
                  color: Colors.orange.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  tr('pcb_tab_salida'),
                  style: const TextStyle(
                      color: Colors.orange,
                      fontSize: 11,
                      fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  tr('pcb_tab_scrap'),
                  style: const TextStyle(
                      color: Colors.red,
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
