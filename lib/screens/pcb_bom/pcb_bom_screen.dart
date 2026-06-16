import 'package:flutter/material.dart';
import 'package:material_warehousing_flutter/core/localization/app_translations.dart';
import 'package:material_warehousing_flutter/core/services/api_service.dart';
import 'package:material_warehousing_flutter/core/services/excel_export_service.dart';
import 'package:material_warehousing_flutter/core/theme/app_colors.dart';
import 'package:material_warehousing_flutter/core/widgets/field_decoration.dart';
import 'package:material_warehousing_flutter/core/widgets/resizable_grid_header.dart';

class PcbBomScreen extends StatefulWidget {
  final LanguageProvider languageProvider;

  const PcbBomScreen({super.key, required this.languageProvider});

  @override
  State<PcbBomScreen> createState() => _PcbBomScreenState();
}

class _PcbBomScreenState extends State<PcbBomScreen>
    with ResizableColumnsMixin {
  final TextEditingController _queryController = TextEditingController();
  final TextEditingController _modelController = TextEditingController();

  List<Map<String, dynamic>> _rows = [];
  List<Map<String, dynamic>> _filteredRows = [];
  Map<String, String?> _columnFilters = {};
  String? _sortColumn;
  bool _sortAscending = true;
  int _selectedIndex = -1;
  bool _isLoading = false;
  bool _hasSearched = false;

  String _selectedSide = 'ALL';
  String _selectedTipo = 'ALL';
  String _selectedClass = 'ALL';

  static const _fields = [
    'modelo',
    'numero_parte',
    'side',
    'tipo_material',
    'classification',
    'especificacion_material',
    'cantidad_total',
    'ubicacion',
  ];

  String tr(String key) => widget.languageProvider.tr(key);

  List<String> get _headers => [
        tr('pcb_bom_model'),
        tr('pcb_bom_component'),
        tr('pcb_bom_side'),
        tr('pcb_bom_type'),
        tr('pcb_bom_class'),
        tr('pcb_bom_spec'),
        tr('pcb_bom_qty'),
        tr('pcb_bom_location'),
      ];

  List<String> get _tipoOptions {
    final values = _rows
        .map((row) => (row['tipo_material'] ?? '').toString())
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    return ['ALL', ...values];
  }

  List<String> get _classOptions {
    final values = _rows
        .map((row) => (row['classification'] ?? '').toString())
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    return ['ALL', ...values];
  }

  Map<String, dynamic>? get _selectedRow {
    if (_selectedIndex < 0 || _selectedIndex >= _filteredRows.length) {
      return null;
    }
    return _filteredRows[_selectedIndex];
  }

  @override
  void initState() {
    super.initState();
    initColumnFlex(
      _fields.length,
      'pcb_bom_consulta',
      defaultFlexValues: [
        1.5,
        1.6,
        0.8,
        1.1,
        1.4,
        3.0,
        0.8,
        1.6,
      ],
    );
  }

  @override
  void dispose() {
    _queryController.dispose();
    _modelController.dispose();
    super.dispose();
  }

  String _extractPcbPartNo(String value) {
    final match = RegExp(r'EBR\d{8}', caseSensitive: false).firstMatch(value);
    return match?.group(0)?.toUpperCase() ?? value.trim().toUpperCase();
  }

  void _normalizeModelScan() {
    final normalized = _extractPcbPartNo(_modelController.text);
    if (normalized != _modelController.text && normalized.isNotEmpty) {
      _modelController.text = normalized;
      _modelController.selection = TextSelection.collapsed(
        offset: _modelController.text.length,
      );
    }
  }

  Future<void> _search() async {
    if (_isLoading) return;
    _normalizeModelScan();

    setState(() {
      _isLoading = true;
      _hasSearched = true;
      _selectedIndex = -1;
    });

    final result = await ApiService.searchBomComponents(
      query: _queryController.text,
      modelo: _modelController.text,
      side: _selectedSide,
      tipoMaterial: _selectedTipo,
      classification: _selectedClass,
      limit: 1000,
    );

    if (!mounted) return;
    final data = (result['data'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    setState(() {
      _rows = data;
      _filteredRows = List.from(data);
      _columnFilters.clear();
      _sortColumn = null;
      _sortAscending = true;
      _isLoading = false;
      if (!_tipoOptions.contains(_selectedTipo)) _selectedTipo = 'ALL';
      if (!_classOptions.contains(_selectedClass)) _selectedClass = 'ALL';
    });
  }

  void _clear() {
    setState(() {
      _queryController.clear();
      _modelController.clear();
      _selectedSide = 'ALL';
      _selectedTipo = 'ALL';
      _selectedClass = 'ALL';
      _rows = [];
      _filteredRows = [];
      _columnFilters.clear();
      _sortColumn = null;
      _sortAscending = true;
      _selectedIndex = -1;
      _hasSearched = false;
    });
  }

  void _applyGridFilters() {
    var data = List<Map<String, dynamic>>.from(_rows);
    for (final entry in _columnFilters.entries) {
      final filterValue = entry.value;
      if (filterValue == null || filterValue.isEmpty) continue;
      data = data
          .where((row) => (row[entry.key] ?? '').toString() == filterValue)
          .toList();
    }

    if (_sortColumn != null) {
      data.sort((a, b) {
        final va = a[_sortColumn];
        final vb = b[_sortColumn];
        final na = double.tryParse((va ?? '').toString());
        final nb = double.tryParse((vb ?? '').toString());
        if (na != null && nb != null) {
          return _sortAscending ? na.compareTo(nb) : nb.compareTo(na);
        }
        final sa = (va ?? '').toString();
        final sb = (vb ?? '').toString();
        return _sortAscending ? sa.compareTo(sb) : sb.compareTo(sa);
      });
    }

    _filteredRows = data;
    if (_selectedIndex >= _filteredRows.length) _selectedIndex = -1;
  }

  void _onSort(String field, bool ascending) {
    setState(() {
      _sortColumn = field;
      _sortAscending = ascending;
      _applyGridFilters();
    });
  }

  void _onFilter(String field) {
    final values = _rows
        .map((row) => (row[field] ?? '').toString())
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList()
      ..sort();

    final currentFilter = _columnFilters[field];
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.panelBackground,
        title: Text(
          '${tr('filter_by')}: $field',
          style: const TextStyle(color: Colors.white, fontSize: 14),
        ),
        content: SizedBox(
          width: 280,
          height: 320,
          child: ListView(
            children: [
              ListTile(
                dense: true,
                title: Text(
                  tr('all'),
                  style: TextStyle(
                    color: currentFilter == null ? Colors.blue : Colors.white70,
                    fontSize: 13,
                    fontWeight: currentFilter == null
                        ? FontWeight.bold
                        : FontWeight.normal,
                  ),
                ),
                onTap: () {
                  setState(() {
                    _columnFilters.remove(field);
                    _applyGridFilters();
                  });
                  Navigator.pop(ctx);
                },
              ),
              const Divider(color: AppColors.border),
              ...values.map(
                (value) => ListTile(
                  dense: true,
                  title: Text(
                    value,
                    style: TextStyle(
                      color:
                          currentFilter == value ? Colors.blue : Colors.white70,
                      fontSize: 13,
                      fontWeight: currentFilter == value
                          ? FontWeight.bold
                          : FontWeight.normal,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onTap: () {
                    setState(() {
                      _columnFilters[field] = value;
                      _applyGridFilters();
                    });
                    Navigator.pop(ctx);
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _exportExcel() async {
    await ExcelExportService.exportToExcel(
      data: _filteredRows,
      headers: _headers,
      fieldMapping: _fields,
      fileName: 'PCB_BOM_Consulta',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildSearchPanel(),
        _buildMetrics(),
        Expanded(child: _buildGrid()),
        _buildDetailPanel(),
      ],
    );
  }

  Widget _buildSearchPanel() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
      decoration: const BoxDecoration(
        color: AppColors.subPanelBackground,
        border: Border(bottom: BorderSide(color: AppColors.border, width: 1)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 1040;
          final quickSearch = _labeledField(
            label: tr('pcb_bom_quick_search'),
            width: compact ? 280 : double.infinity,
            child: TextFormField(
              controller: _queryController,
              decoration: fieldDecoration(hintText: tr('pcb_bom_search_hint')),
              style: const TextStyle(color: Colors.white, fontSize: 13),
              onFieldSubmitted: (_) => _search(),
            ),
          );

          final modelField = _labeledField(
            label: tr('pcb_bom_model'),
            width: 170,
            child: TextFormField(
              controller: _modelController,
              decoration: fieldDecoration(hintText: tr('pcb_bom_model_hint')),
              style: const TextStyle(color: Colors.white, fontSize: 13),
              onFieldSubmitted: (_) {
                _normalizeModelScan();
                _search();
              },
            ),
          );

          final controls = <Widget>[
            _dropdown(
              label: tr('pcb_bom_side'),
              width: 110,
              value: _selectedSide,
              items: const ['ALL', 'MASTER', 'SMD', 'IMD', 'OTHER'],
              onChanged: (value) => setState(() => _selectedSide = value),
            ),
            _dropdown(
              label: tr('pcb_bom_type'),
              width: 130,
              value: _selectedTipo,
              items: _tipoOptions,
              onChanged: (value) => setState(() => _selectedTipo = value),
            ),
            _dropdown(
              label: tr('pcb_bom_class'),
              width: 190,
              value: _selectedClass,
              items: _classOptions,
              onChanged: (value) => setState(() => _selectedClass = value),
            ),
            _searchButton(),
            _clearButton(),
            _exportButton(),
          ];

          if (compact) {
            return Wrap(
              spacing: 12,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [modelField, quickSearch, ...controls],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              modelField,
              const SizedBox(width: 12),
              Expanded(child: quickSearch),
              const SizedBox(width: 12),
              for (var i = 0; i < controls.length; i++) ...[
                controls[i],
                if (i < controls.length - 1) const SizedBox(width: 12),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _searchButton() {
    return SizedBox(
      height: 34,
      child: ElevatedButton.icon(
        onPressed: _isLoading ? null : _search,
        icon: _isLoading
            ? const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const Icon(Icons.search, size: 16),
        label: Text(tr('search'), style: const TextStyle(fontSize: 12)),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.buttonSearch,
          foregroundColor: Colors.white,
        ),
      ),
    );
  }

  Widget _clearButton() {
    return SizedBox(
      height: 34,
      child: ElevatedButton.icon(
        onPressed: _clear,
        icon: const Icon(Icons.cleaning_services, size: 16),
        label: Text(tr('clean'), style: const TextStyle(fontSize: 12)),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.buttonGray,
          foregroundColor: Colors.white,
        ),
      ),
    );
  }

  Widget _exportButton() {
    return SizedBox(
      height: 34,
      child: ElevatedButton.icon(
        onPressed: _filteredRows.isEmpty ? null : _exportExcel,
        icon: const Icon(Icons.file_download, size: 16),
        label: Text(
          tr('pcb_export_excel'),
          style: const TextStyle(fontSize: 12),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.buttonExcel,
          foregroundColor: Colors.white,
        ),
      ),
    );
  }

  Widget _labeledField({
    required String label,
    required double width,
    required Widget child,
  }) {
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label,
            style: const TextStyle(color: Colors.white70, fontSize: 11)),
        const SizedBox(height: 4),
        child,
      ],
    );

    if (width == double.infinity) return content;

    return SizedBox(
      width: width,
      child: content,
    );
  }

  Widget _dropdown({
    required String label,
    required double width,
    required String value,
    required List<String> items,
    required ValueChanged<String> onChanged,
  }) {
    final safeItems = items.contains(value) ? items : ['ALL', ...items];
    return _labeledField(
      label: label,
      width: width,
      child: DropdownButtonFormField<String>(
        initialValue: value,
        isExpanded: true,
        decoration: fieldDecoration(),
        dropdownColor: AppColors.fieldBackground,
        style: const TextStyle(color: Colors.white, fontSize: 12),
        items: safeItems
            .toSet()
            .map(
              (item) => DropdownMenuItem(
                value: item,
                child: Text(item, overflow: TextOverflow.ellipsis),
              ),
            )
            .toList(),
        onChanged: (value) {
          if (value != null) onChanged(value);
        },
      ),
    );
  }

  Widget _buildMetrics() {
    final models = _filteredRows
        .map((row) => (row['modelo'] ?? '').toString())
        .where((value) => value.isNotEmpty)
        .toSet()
        .length;
    final components = _filteredRows
        .map((row) => (row['numero_parte'] ?? '').toString())
        .where((value) => value.isNotEmpty)
        .toSet()
        .length;
    final selected = _selectedRow;

    return Container(
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
      color: AppColors.panelBackground,
      child: Row(
        children: [
          _metric(tr('total_rows'), '${_filteredRows.length}', Colors.cyan),
          const SizedBox(width: 8),
          _metric(tr('pcb_bom_models'), '$models', Colors.orange),
          const SizedBox(width: 8),
          _metric(tr('pcb_bom_components'), '$components', Colors.green),
          const Spacer(),
          if (selected != null)
            Text(
              '${selected['modelo'] ?? ''} | ${selected['numero_parte'] ?? ''}',
              style: const TextStyle(color: Colors.white70, fontSize: 12),
              overflow: TextOverflow.ellipsis,
            ),
        ],
      ),
    );
  }

  Widget _metric(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        border: Border.all(color: color.withValues(alpha: 0.35)),
        borderRadius: BorderRadius.circular(4),
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

  Widget _buildGrid() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }

    if (!_hasSearched) {
      return Center(
        child: Text(
          tr('pcb_bom_initial_message'),
          style: const TextStyle(color: Colors.white38, fontSize: 14),
        ),
      );
    }

    if (_filteredRows.isEmpty) {
      return Center(
        child: Text(
          tr('no_data'),
          style: const TextStyle(color: Colors.white38, fontSize: 14),
        ),
      );
    }

    return Container(
      color: AppColors.gridBackground,
      child: Column(
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
            child: ListView.builder(
              itemCount: _filteredRows.length,
              itemBuilder: (context, index) {
                final row = _filteredRows[index];
                final selected = index == _selectedIndex;
                return GestureDetector(
                  onTap: () => setState(() => _selectedIndex = index),
                  onDoubleTap: () {
                    _modelController.text = (row['modelo'] ?? '').toString();
                    _queryController.clear();
                    _search();
                  },
                  child: Container(
                    height: 32,
                    color: selected
                        ? AppColors.gridSelectedRow
                        : index.isEven
                            ? AppColors.gridRowEven
                            : AppColors.gridRowOdd,
                    child: Row(
                      children: List.generate(_fields.length, (col) {
                        final field = _fields[col];
                        final value = _formatCell(field, row[field]);
                        return Expanded(
                          flex: getColumnFlex(col),
                          child: Container(
                            alignment: Alignment.centerLeft,
                            padding: const EdgeInsets.symmetric(horizontal: 5),
                            decoration: const BoxDecoration(
                              border: Border(
                                right: BorderSide(
                                  color: Color(0x223C8DBC),
                                  width: 1,
                                ),
                              ),
                            ),
                            child: Text(
                              value,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                              ),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
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
      ),
    );
  }

  String _formatCell(String field, dynamic value) {
    if (value == null) return '';
    if (field == 'cantidad_total') {
      final parsed = double.tryParse(value.toString());
      if (parsed == null) return value.toString();
      return parsed == parsed.roundToDouble()
          ? parsed.toInt().toString()
          : parsed.toStringAsFixed(2);
    }
    return value.toString();
  }

  Widget _buildDetailPanel() {
    final row = _selectedRow;
    return Container(
      height: 118,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      decoration: const BoxDecoration(
        color: AppColors.panelBackground,
        border: Border(top: BorderSide(color: AppColors.border, width: 1)),
      ),
      child: row == null
          ? Align(
              alignment: Alignment.centerLeft,
              child: Text(
                tr('pcb_bom_select_row'),
                style: const TextStyle(color: Colors.white38, fontSize: 12),
              ),
            )
          : Row(
              children: [
                Expanded(
                  flex: 4,
                  child: _detailBlock(
                    tr('pcb_bom_spec'),
                    (row['especificacion_material'] ?? '').toString(),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 3,
                  child: _detailBlock(
                    tr('pcb_bom_location'),
                    (row['ubicacion'] ?? '').toString(),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 3,
                  child: _detailBlock(
                    tr('pcb_bom_substitute'),
                    [
                      row['material_sustituto'],
                      row['material_original'],
                    ]
                        .where((value) => (value ?? '').toString().isNotEmpty)
                        .join(' / '),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _detailBlock(String title, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(color: Colors.white54, fontSize: 11),
        ),
        const SizedBox(height: 5),
        Expanded(
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.gridBackground,
              border:
                  Border.all(color: AppColors.border.withValues(alpha: 0.35)),
              borderRadius: BorderRadius.circular(4),
            ),
            child: SingleChildScrollView(
              child: Text(
                value.isEmpty ? '-' : value,
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
