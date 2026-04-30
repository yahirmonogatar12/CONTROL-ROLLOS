import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_warehousing_flutter/core/localization/app_translations.dart';
import 'package:material_warehousing_flutter/core/theme/app_colors.dart';
import 'package:material_warehousing_flutter/core/services/api_service.dart';
import 'package:material_warehousing_flutter/core/services/excel_export_service.dart';
import 'package:material_warehousing_flutter/core/widgets/grid_footer.dart';
import 'package:material_warehousing_flutter/core/widgets/resizable_grid_header.dart';

class MaterialShortageScreen extends StatefulWidget {
  final LanguageProvider languageProvider;

  const MaterialShortageScreen({super.key, required this.languageProvider});

  @override
  State<MaterialShortageScreen> createState() => MaterialShortageScreenState();
}

class MaterialShortageScreenState extends State<MaterialShortageScreen>
    with ResizableColumnsMixin {
  // Data
  List<Map<String, dynamic>> _shortageData = [];
  List<Map<String, dynamic>> _originalData = [];
  bool _isLoading = false;

  // Filters
  DateTime _selectedDate = DateTime.now();
  String? _selectedLine;
  List<String> _availableLines = [];
  bool _showOnlyShortages = false;

  // Summary
  int _totalComponents = 0;
  List<String> _modelsWithoutData = [];
  List<Map<String, dynamic>> _modelsWithMissingSide = [];

  // Sorting
  String? _sortColumn;
  bool _sortAscending = true;

  // Column filters
  Map<String, String?> _columnFilters = {};

  // Selection for requirement generation
  final Set<String> _selectedParts = {};

  // Ctrl+F search
  bool _showSearchBar = false;
  String _searchText = '';
  final TextEditingController _gridSearchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final FocusNode _keyboardFocusNode = FocusNode();

  String tr(String key) => widget.languageProvider.tr(key);

  @override
  void initState() {
    super.initState();
    // 13 columns: Checkbox, #, Part Number, Spec, Req Qty, Std Pack, Reels, Adj Qty, Equiv Parts, Stock, Shortage, Status, Models
    initColumnFlex(13, 'shortage_grid_v2',
        defaultFlexValues: [0.3, 0.3, 1.5, 2.0, 0.9, 0.7, 0.6, 0.9, 1.8, 0.9, 0.9, 0.7, 2.2]);
    _loadLines();
    _calculate();
  }

  @override
  void dispose() {
    _gridSearchController.dispose();
    _searchFocusNode.dispose();
    _keyboardFocusNode.dispose();
    super.dispose();
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  Future<void> _loadLines() async {
    final lines = await ApiService.getShortageLines(
      date: _formatDate(_selectedDate),
    );
    if (mounted) {
      setState(() {
        _availableLines = lines;
      });
    }
  }

  Future<void> _calculate() async {
    setState(() => _isLoading = true);

    final result = await ApiService.getShortageCalculation(
      date: _formatDate(_selectedDate),
      line: _selectedLine,
    );

    if (mounted) {
      final items = (result['items'] as List<dynamic>?)
              ?.map((e) => Map<String, dynamic>.from(e as Map))
              .toList() ??
          [];

      setState(() {
        _originalData = List.from(items);
        _totalComponents = result['total_components'] ?? 0;
        _modelsWithoutData = (result['models_without_data'] as List<dynamic>?)
            ?.map((e) => e.toString())
            .toList() ?? [];
        _modelsWithMissingSide = (result['models_with_missing_side'] as List<dynamic>?)
            ?.map((e) => Map<String, dynamic>.from(e as Map))
            .toList() ?? [];
        _selectedParts.clear();
        _columnFilters.clear();
        _sortColumn = null;
        _applyDisplayFilter(items);
        _isLoading = false;
      });
    }
  }

  void _applyDisplayFilter(List<Map<String, dynamic>>? sourceData) {
    var data = sourceData ?? _originalData;

    if (_showOnlyShortages) {
      data = data.where((r) => r['status'] == 'SHORTAGE').toList();
    }

    _shortageData = List.from(data);
  }

  Future<void> _pickDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );
    if (date != null) {
      setState(() {
        _selectedDate = date;
        _selectedLine = null;
      });
      _loadLines();
      _calculate();
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
        _searchText = '';
        _gridSearchController.clear();
      }
    });
  }

  void _onSearchTextChanged(String value) {
    setState(() => _searchText = value.toLowerCase());
  }

  Widget _highlightText(String text, String search) {
    if (search.isEmpty) {
      return Text(text,
          style: const TextStyle(fontSize: 11, color: Colors.white),
          overflow: TextOverflow.ellipsis);
    }

    final lowerText = text.toLowerCase();
    if (!lowerText.contains(search)) {
      return Text(text,
          style: const TextStyle(fontSize: 11, color: Colors.white),
          overflow: TextOverflow.ellipsis);
    }

    final List<TextSpan> spans = [];
    int start = 0;
    int index;
    while ((index = lowerText.indexOf(search, start)) != -1) {
      if (index > start) {
        spans.add(TextSpan(text: text.substring(start, index)));
      }
      spans.add(TextSpan(
        text: text.substring(index, index + search.length),
        style:
            const TextStyle(backgroundColor: Colors.yellow, color: Colors.black),
      ));
      start = index + search.length;
    }
    if (start < text.length) {
      spans.add(TextSpan(text: text.substring(start)));
    }
    return RichText(
      text: TextSpan(
          style: const TextStyle(fontSize: 11, color: Colors.white),
          children: spans),
      overflow: TextOverflow.ellipsis,
    );
  }

  String _formatNumber(dynamic value) {
    if (value == null) return '0';
    final num = double.tryParse(value.toString()) ?? 0;
    return num.toStringAsFixed(0).replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (Match m) => '${m[1]},',
    );
  }

  void _sortData(String field, bool ascending) {
    setState(() {
      _sortColumn = field;
      _sortAscending = ascending;
      _shortageData.sort((a, b) {
        var aValue = a[field];
        var bValue = b[field];

        if (aValue is num && bValue is num) {
          return ascending
              ? aValue.compareTo(bValue)
              : bValue.compareTo(aValue);
        }
        if (aValue is List) aValue = aValue.join(', ');
        if (bValue is List) bValue = bValue.join(', ');

        String aStr = aValue?.toString() ?? '';
        String bStr = bValue?.toString() ?? '';
        return ascending
            ? aStr.toLowerCase().compareTo(bStr.toLowerCase())
            : bStr.toLowerCase().compareTo(aStr.toLowerCase());
      });
    });
  }

  void _clearSorting() {
    setState(() {
      _sortColumn = null;
      _sortAscending = true;
      _applyDisplayFilter(null);
      _applyColumnFilters();
    });
  }

  void _showColumnContextMenu(
      BuildContext context, Offset position, String field, String header) {
    final RenderBox overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;

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
          child: Row(children: [
            Icon(Icons.arrow_upward,
                size: 16,
                color: _sortColumn == field && _sortAscending
                    ? Colors.blue
                    : Colors.white70),
            const SizedBox(width: 8),
            Text(tr('sort_ascending'),
                style: TextStyle(
                    fontSize: 12,
                    color: _sortColumn == field && _sortAscending
                        ? Colors.blue
                        : Colors.white)),
          ]),
        ),
        PopupMenuItem(
          value: 'sort_desc',
          height: 32,
          child: Row(children: [
            Icon(Icons.arrow_downward,
                size: 16,
                color: _sortColumn == field && !_sortAscending
                    ? Colors.blue
                    : Colors.white70),
            const SizedBox(width: 8),
            Text(tr('sort_descending'),
                style: TextStyle(
                    fontSize: 12,
                    color: _sortColumn == field && !_sortAscending
                        ? Colors.blue
                        : Colors.white)),
          ]),
        ),
        PopupMenuItem(
          value: 'clear_sort',
          enabled: _sortColumn != null,
          height: 32,
          child: Row(children: [
            Icon(Icons.clear,
                size: 16,
                color: _sortColumn != null ? Colors.white70 : Colors.white30),
            const SizedBox(width: 8),
            Text(tr('clear_sorting'),
                style: TextStyle(
                    fontSize: 12,
                    color:
                        _sortColumn != null ? Colors.white : Colors.white30)),
          ]),
        ),
        const PopupMenuDivider(height: 8),
        PopupMenuItem(
          value: 'filter',
          height: 32,
          child: Row(children: [
            Icon(Icons.filter_list,
                size: 16,
                color: _columnFilters.containsKey(field)
                    ? Colors.blue
                    : Colors.white70),
            const SizedBox(width: 8),
            Text(tr('filter_by_column'),
                style: TextStyle(
                    fontSize: 12,
                    color: _columnFilters.containsKey(field)
                        ? Colors.blue
                        : Colors.white)),
          ]),
        ),
        PopupMenuItem(
          value: 'clear_filter',
          enabled: _columnFilters.containsKey(field),
          height: 32,
          child: Row(children: [
            Icon(Icons.filter_list_off,
                size: 16,
                color: _columnFilters.containsKey(field)
                    ? Colors.white70
                    : Colors.white30),
            const SizedBox(width: 8),
            Text(tr('clear_filter'),
                style: TextStyle(
                    fontSize: 12,
                    color: _columnFilters.containsKey(field)
                        ? Colors.white
                        : Colors.white30)),
          ]),
        ),
      ],
    ).then((value) {
      if (value == null) return;
      switch (value) {
        case 'sort_asc':
          _sortData(field, true);
          break;
        case 'sort_desc':
          _sortData(field, false);
          break;
        case 'clear_sort':
          _clearSorting();
          break;
        case 'filter':
          _showFilterDialog(context, field, header);
          break;
        case 'clear_filter':
          _clearColumnFilter(field);
          break;
      }
    });
  }

  void _showFilterDialog(BuildContext context, String field, String header) {
    final filterController = TextEditingController();
    filterController.text = _columnFilters[field] ?? '';

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2D2D30),
        title: Text('${tr('filter_by')}: $header',
            style: const TextStyle(color: Colors.white, fontSize: 14)),
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
            onSubmitted: (value) {
              Navigator.pop(context);
              _applyColumnFilter(field, value);
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(tr('cancel')),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _applyColumnFilter(field, filterController.text);
            },
            child: Text(tr('save')),
          ),
        ],
      ),
    );
  }

  void _applyColumnFilter(String field, String value) {
    setState(() {
      if (value.isEmpty) {
        _columnFilters.remove(field);
      } else {
        _columnFilters[field] = value;
      }
      _applyDisplayFilter(null);
      _applyColumnFilters();
    });
  }

  void _clearColumnFilter(String field) {
    setState(() {
      _columnFilters.remove(field);
      _applyDisplayFilter(null);
      _applyColumnFilters();
    });
  }

  void _applyColumnFilters() {
    if (_columnFilters.isEmpty) return;
    _shortageData = _shortageData.where((row) {
      for (var entry in _columnFilters.entries) {
        final field = entry.key;
        final filterValue = entry.value?.toLowerCase() ?? '';
        var cellValue = row[field];
        if (cellValue is List) cellValue = cellValue.join(', ');
        final cellStr = cellValue?.toString().toLowerCase() ?? '';
        if (!cellStr.contains(filterValue)) return false;
      }
      return true;
    }).toList();
  }

  Future<void> _exportToExcel() async {
    final headers = [
      '#',
      tr('part_number'),
      tr('specification'),
      tr('required_qty'),
      tr('standard_pack'),
      tr('reels_needed'),
      tr('adjusted_qty'),
      tr('equivalent_parts'),
      tr('available_stock'),
      tr('shortage'),
      tr('status'),
      tr('model'),
    ];
    final fieldMapping = [
      'index',
      'numero_parte',
      'especificacion',
      'required_qty',
      'standard_pack',
      'reels_needed',
      'adjusted_qty',
      'equivalent_parts_str',
      'available_stock',
      'shortage',
      'status',
      'models_str',
    ];

    // Prepare data for export
    final exportData = _shortageData.asMap().entries.map((entry) {
      final row = Map<String, dynamic>.from(entry.value);
      row['index'] = entry.key + 1;
      row['equivalent_parts_str'] =
          (row['equivalent_parts'] as List?)?.join(', ') ?? '';
      row['models_str'] = (row['models'] as List?)?.join(', ') ?? '';
      return row;
    }).toList();

    final success = await ExcelExportService.exportToExcel(
      data: exportData,
      headers: headers,
      fieldMapping: fieldMapping,
      fileName: 'Material_Shortage_${_formatDate(_selectedDate)}',
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

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _keyboardFocusNode,
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.keyF &&
            HardwareKeyboard.instance.isControlPressed) {
          _toggleSearchBar();
          return KeyEventResult.handled;
        }
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
            // Filter bar
            _buildFilterBar(),
            // Warnings
            if (_modelsWithoutData.isNotEmpty) _buildModelsWithoutDataWarning(),
            if (_modelsWithMissingSide.isNotEmpty) _buildMissingSideWarning(),
            // Search bar (Ctrl+F)
            if (_showSearchBar) _buildSearchBar(),
            // Grid
            Expanded(child: _buildGrid()),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterBar() {
    return Container(
      color: AppColors.panelBackground,
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
      child: Row(
        children: [
          // Date picker
          SizedBox(
            height: 28,
            child: InkWell(
              onTap: _pickDate,
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
                    const Icon(Icons.calendar_today,
                        size: 12, color: Colors.white54),
                    const SizedBox(width: 4),
                    Text(
                      _formatDate(_selectedDate),
                      style:
                          const TextStyle(fontSize: 11, color: Colors.white70),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Line dropdown
          SizedBox(
            height: 28,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: AppColors.fieldBackground,
                border: Border.all(color: AppColors.border),
                borderRadius: BorderRadius.circular(4),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _selectedLine,
                  hint: Text(tr('all_lines'),
                      style:
                          const TextStyle(fontSize: 11, color: Colors.white54)),
                  dropdownColor: const Color(0xFF2D333B),
                  style: const TextStyle(fontSize: 11, color: Colors.white70),
                  isDense: true,
                  items: [
                    DropdownMenuItem<String>(
                      value: null,
                      child: Text(tr('all_lines')),
                    ),
                    ..._availableLines.map((line) => DropdownMenuItem(
                          value: line,
                          child: Text(line),
                        )),
                  ],
                  onChanged: (value) {
                    setState(() => _selectedLine = value);
                  },
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Calculate button
          SizedBox(
            height: 28,
            child: ElevatedButton(
              onPressed: _isLoading ? null : _calculate,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                backgroundColor: AppColors.buttonSearch,
              ),
              child: Text(tr('calculate'),
                  style: const TextStyle(fontSize: 11)),
            ),
          ),
          const SizedBox(width: 8),
          // Only shortages toggle
          SizedBox(
            height: 28,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 20,
                  height: 20,
                  child: Checkbox(
                    value: _showOnlyShortages,
                    onChanged: (v) {
                      setState(() {
                        _showOnlyShortages = v ?? false;
                        _applyDisplayFilter(null);
                        _applyColumnFilters();
                      });
                    },
                    side: const BorderSide(color: AppColors.border),
                    activeColor: Colors.orange,
                  ),
                ),
                const SizedBox(width: 4),
                Text(tr('only_shortages'),
                    style:
                        const TextStyle(fontSize: 11, color: Colors.white70)),
              ],
            ),
          ),
          if (_selectedParts.isNotEmpty) ...[
            const SizedBox(width: 8),
            SizedBox(
              height: 28,
              child: ElevatedButton.icon(
                onPressed: _showGenerateRequirementDialog,
                icon: const Icon(Icons.assignment_add, size: 14),
                label: Text('${tr('generate_requirement')} (${_selectedParts.length})',
                    style: const TextStyle(fontSize: 11)),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  backgroundColor: Colors.purple,
                ),
              ),
            ),
          ],
          const Spacer(),
          // Excel export
          SizedBox(
            height: 28,
            child: ElevatedButton(
              onPressed: _shortageData.isEmpty ? null : _exportToExcel,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                backgroundColor: AppColors.buttonExcel,
              ),
              child:
                  Text(tr('excel_export'), style: const TextStyle(fontSize: 11)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModelsWithoutDataWarning() {
    return Container(
      color: AppColors.panelBackground,
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.orange.withOpacity(0.12),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.orange.withOpacity(0.4)),
        ),
        child: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, size: 16, color: Colors.orange),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '${_modelsWithoutData.length} EBR(s) sin datos de BOM ni CONSUMO: ${_modelsWithoutData.join(", ")}',
                style: const TextStyle(fontSize: 11, color: Colors.orange),
                overflow: TextOverflow.ellipsis,
                maxLines: 2,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMissingSideWarning() {
    final details = _modelsWithMissingSide.map((m) {
      final model = m['model'] ?? '';
      final existing = m['existing'] ?? '';
      final missing = m['missing'] ?? '';
      final sideName = missing == 'B' ? 'Bottom' : 'Top';
      return '$model (tiene $existing, falta $missing-$sideName)';
    }).join(', ');

    return Container(
      color: AppColors.panelBackground,
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.yellow.withOpacity(0.10),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.yellow.withOpacity(0.4)),
        ),
        child: Row(
          children: [
            const Icon(Icons.info_outline, size: 16, color: Colors.yellow),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Falta un lado de PCB (no se considera en calculo): $details',
                style: const TextStyle(fontSize: 11, color: Colors.yellow),
                overflow: TextOverflow.ellipsis,
                maxLines: 2,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
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
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                hintText: tr('search_placeholder'),
                hintStyle:
                    const TextStyle(color: Colors.white54, fontSize: 12),
                filled: true,
                fillColor: AppColors.fieldBackground,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(4),
                  borderSide: const BorderSide(color: AppColors.border),
                ),
                prefixIcon:
                    const Icon(Icons.search, size: 16, color: Colors.white54),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            _searchText.isNotEmpty
                ? 'Highlighting: "$_searchText"'
                : 'Ctrl+F | Esc to close',
            style: const TextStyle(fontSize: 11, color: Colors.white54),
          ),
          const Spacer(),
          SizedBox(
            height: 24,
            child: TextButton(
              onPressed: _toggleSearchBar,
              style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 12)),
              child: const Text('Close', style: TextStyle(fontSize: 11)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGrid() {
    final headers = [
      {'label': '', 'field': '_checkbox'},
      {'label': '#', 'field': 'index'},
      {'label': tr('part_number'), 'field': 'numero_parte'},
      {'label': tr('specification'), 'field': 'especificacion'},
      {'label': tr('required_qty'), 'field': 'required_qty'},
      {'label': tr('standard_pack'), 'field': 'standard_pack'},
      {'label': tr('reels_needed'), 'field': 'reels_needed'},
      {'label': tr('adjusted_qty'), 'field': 'adjusted_qty'},
      {'label': tr('equivalent_parts'), 'field': 'equivalent_parts'},
      {'label': tr('available_stock'), 'field': 'available_stock'},
      {'label': tr('shortage'), 'field': 'shortage'},
      {'label': tr('status'), 'field': 'status'},
      {'label': tr('model'), 'field': 'models'},
    ];

    // Ctrl+F filter
    final displayData = _searchText.isEmpty
        ? _shortageData
        : _shortageData.where((row) {
            return row.values.any((v) {
              String str;
              if (v is List) {
                str = v.join(', ').toLowerCase();
              } else {
                str = v?.toString().toLowerCase() ?? '';
              }
              return str.contains(_searchText);
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
              children: headers.asMap().entries.map((entry) {
                if (entry.key == 0) {
                  // Checkbox select-all header
                  return _buildCheckboxHeaderCell(0);
                }
                return _buildHeaderCell(
                  entry.value['label'] as String,
                  entry.value['field'] as String,
                  entry.key,
                );
              }).toList(),
            ),
          ),
          // Body
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : displayData.isEmpty
                    ? Center(
                        child: Text(
                          _totalComponents == 0
                              ? tr('no_plan_found')
                              : tr('no_data'),
                          style: const TextStyle(
                              fontSize: 11, color: Colors.white70),
                        ),
                      )
                    : SelectionArea(
                        child: ListView.builder(
                          itemCount: displayData.length,
                          itemBuilder: (context, index) {
                            final row = displayData[index];
                            return _buildRow(row, index);
                          },
                        ),
                      ),
          ),
          GridFooter(
              text:
                  '${tr('total_rows')} : ${displayData.length}${displayData.length != _shortageData.length ? ' / ${_shortageData.length}' : ''}'),
        ],
      ),
    );
  }

  Widget _buildRow(Map<String, dynamic> row, int index) {
    final shortage = (row['shortage'] as num?)?.toDouble() ?? 0;
    final status = row['status'] ?? 'OK';
    final equivParts = (row['equivalent_parts'] as List?)?.join(', ') ?? '';
    final models = (row['models'] as List?)?.join(', ') ?? '';

    Color rowColor;
    if (shortage > 0) {
      rowColor = Colors.red.withOpacity(0.12);
    } else if (shortage < 0) {
      rowColor = Colors.green.withOpacity(0.06);
    } else {
      rowColor = index.isEven ? AppColors.gridBackground : AppColors.gridRowAlt;
    }

    final spec = row['especificacion']?.toString() ?? '';
    final standardPack = row['standard_pack'];
    final reelsNeeded = row['reels_needed'];
    final adjustedQty = row['adjusted_qty'];

    final partNo = row['numero_parte']?.toString() ?? '';
    final isSelected = _selectedParts.contains(partNo);

    return Container(
      height: 24,
      color: rowColor,
      child: Row(
        children: [
          _buildCheckboxCell(partNo, isSelected, 0),
          _buildCell('${index + 1}', 1),
          _buildCell(partNo, 2),
          _buildCell(spec, 3),
          _buildCell(_formatNumber(row['required_qty']), 4),
          _buildCell(standardPack != null && standardPack != 0 ? _formatNumber(standardPack) : '', 5),
          _buildCell(reelsNeeded != null && reelsNeeded != 0 ? _formatNumber(reelsNeeded) : '', 6),
          _buildCell(adjustedQty != null && adjustedQty != 0 ? _formatNumber(adjustedQty) : _formatNumber(row['required_qty']), 7),
          _buildCell(equivParts, 8),
          _buildCell(_formatNumber(row['available_stock']), 9),
          _buildCellColored(
            _formatNumber(shortage.abs()),
            10,
            shortage > 0
                ? Colors.red
                : shortage < 0
                    ? Colors.green
                    : Colors.white,
            prefix: shortage > 0
                ? '-'
                : shortage < 0
                    ? '+'
                    : '',
          ),
          _buildStatusCell(status, 11),
          _buildCell(models, 12),
        ],
      ),
    );
  }

  Widget _buildCheckboxHeaderCell(int index) {
    // Check if all visible shortage items are selected
    final visibleShortageItems = _shortageData
        .where((r) => r['status'] == 'SHORTAGE')
        .map((r) => r['numero_parte']?.toString() ?? '')
        .where((p) => p.isNotEmpty)
        .toSet();
    final allSelected = visibleShortageItems.isNotEmpty &&
        visibleShortageItems.every((p) => _selectedParts.contains(p));

    return Expanded(
      flex: getColumnFlex(index),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        decoration: const BoxDecoration(
          border: Border(right: BorderSide(color: AppColors.border, width: 0.5)),
        ),
        alignment: Alignment.center,
        child: SizedBox(
          width: 18,
          height: 18,
          child: Checkbox(
            value: allSelected && visibleShortageItems.isNotEmpty,
            onChanged: (v) {
              setState(() {
                if (v == true) {
                  _selectedParts.addAll(visibleShortageItems);
                } else {
                  _selectedParts.clear();
                }
              });
            },
            side: const BorderSide(color: Colors.white54, width: 1.5),
            activeColor: Colors.purple,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ),
      ),
    );
  }

  Widget _buildCheckboxCell(String partNo, bool isSelected, int index) {
    return Expanded(
      flex: getColumnFlex(index),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        decoration: const BoxDecoration(
          border: Border(right: BorderSide(color: AppColors.border, width: 0.5)),
        ),
        alignment: Alignment.center,
        child: SizedBox(
          width: 18,
          height: 18,
          child: Checkbox(
            value: isSelected,
            onChanged: (v) {
              setState(() {
                if (v == true) {
                  _selectedParts.add(partNo);
                } else {
                  _selectedParts.remove(partNo);
                }
              });
            },
            side: const BorderSide(color: Colors.white38, width: 1.5),
            activeColor: Colors.purple,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ),
      ),
    );
  }

  void _showGenerateRequirementDialog() {
    String selectedArea = 'SMD';
    String selectedPriority = 'Normal';
    String notas = '';
    DateTime fechaRequerida = _selectedDate;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            backgroundColor: const Color(0xFF2D2D30),
            title: Text(tr('generate_requirement'),
                style: const TextStyle(color: Colors.white, fontSize: 14)),
            content: SizedBox(
              width: 400,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${_selectedParts.length} items ${tr('selected')}',
                      style: const TextStyle(color: Colors.white70, fontSize: 12)),
                  const SizedBox(height: 12),
                  // Fecha requerida
                  const Text('Fecha requerida:', style: TextStyle(color: Colors.white70, fontSize: 11)),
                  const SizedBox(height: 4),
                  SizedBox(
                    height: 32,
                    child: InkWell(
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: ctx,
                          initialDate: fechaRequerida,
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2030),
                        );
                        if (picked != null) {
                          setDialogState(() => fechaRequerida = picked);
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        decoration: BoxDecoration(
                          color: AppColors.fieldBackground,
                          border: Border.all(color: AppColors.border),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        alignment: Alignment.centerLeft,
                        child: Row(
                          children: [
                            const Icon(Icons.calendar_today, size: 14, color: Colors.white54),
                            const SizedBox(width: 8),
                            Text(
                              _formatDate(fechaRequerida),
                              style: const TextStyle(fontSize: 12, color: Colors.white),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Area
                  const Text('Area:', style: TextStyle(color: Colors.white70, fontSize: 11)),
                  const SizedBox(height: 4),
                  Container(
                    height: 32,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(
                      color: AppColors.fieldBackground,
                      border: Border.all(color: AppColors.border),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: selectedArea,
                        isExpanded: true,
                        dropdownColor: const Color(0xFF2D333B),
                        style: const TextStyle(fontSize: 12, color: Colors.white),
                        items: ['SMD', 'Assy', 'Molding', 'Pre-Assy', 'Empaque', 'Rework',
                                'Mantenimiento', 'Ingeniería', 'Calidad', 'Otro']
                            .map((a) => DropdownMenuItem(value: a, child: Text(a)))
                            .toList(),
                        onChanged: (v) => setDialogState(() => selectedArea = v!),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Priority
                  const Text('Prioridad:', style: TextStyle(color: Colors.white70, fontSize: 11)),
                  const SizedBox(height: 4),
                  Container(
                    height: 32,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(
                      color: AppColors.fieldBackground,
                      border: Border.all(color: AppColors.border),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: selectedPriority,
                        isExpanded: true,
                        dropdownColor: const Color(0xFF2D333B),
                        style: const TextStyle(fontSize: 12, color: Colors.white),
                        items: ['Normal', 'Urgente', 'Crítico']
                            .map((p) => DropdownMenuItem(value: p, child: Text(p)))
                            .toList(),
                        onChanged: (v) => setDialogState(() => selectedPriority = v!),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Notes
                  const Text('Notas:', style: TextStyle(color: Colors.white70, fontSize: 11)),
                  const SizedBox(height: 4),
                  TextField(
                    onChanged: (v) => notas = v,
                    maxLines: 2,
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                    decoration: InputDecoration(
                      isDense: true,
                      contentPadding: const EdgeInsets.all(8),
                      filled: true,
                      fillColor: AppColors.fieldBackground,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(4),
                        borderSide: const BorderSide(color: AppColors.border),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(tr('cancel')),
              ),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  _createRequirement(
                    area: selectedArea,
                    prioridad: selectedPriority,
                    fecha: fechaRequerida,
                    notas: notas,
                  );
                },
                style: ElevatedButton.styleFrom(backgroundColor: Colors.purple),
                child: Text(tr('generate_requirement')),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _createRequirement({
    required String area,
    required String prioridad,
    required DateTime fecha,
    required String notas,
  }) async {
    // Build items from selected parts
    final items = <Map<String, dynamic>>[];
    for (final partNo in _selectedParts) {
      final row = _originalData.firstWhere(
        (r) => r['numero_parte'] == partNo,
        orElse: () => <String, dynamic>{},
      );
      if (row.isEmpty) continue;

      final shortage = (row['shortage'] as num?)?.toDouble() ?? 0;
      final qty = shortage > 0 ? shortage.ceil() : 0;
      if (qty <= 0) continue;

      items.add({
        'numero_parte': partNo,
        'descripcion': row['especificacion']?.toString() ?? '',
        'cantidad_requerida': qty,
      });
    }

    if (items.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No hay items con faltante para generar requerimiento'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }

    final success = await ApiService.createRequirement({
      'area_destino': area,
      'fecha_requerida': _formatDate(fecha),
      'prioridad': prioridad,
      'notas': notas.isNotEmpty ? notas : 'Generado desde Faltante de Material - ${_formatDate(fecha)}',
      'creado_por': 'Sistema',
      'items': items,
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success
              ? 'Requerimiento creado con ${items.length} items'
              : 'Error al crear requerimiento'),
          backgroundColor: success ? Colors.green : Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
      if (success) {
        setState(() => _selectedParts.clear());
      }
    }
  }

  Widget _buildHeaderCell(String label, String field, int index) {
    final isSorted = _sortColumn == field;
    final hasFilter = _columnFilters.containsKey(field);
    final filterKey = GlobalKey();

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
                Expanded(
                  child: GestureDetector(
                    onTap: () =>
                        _sortData(field, isSorted ? !_sortAscending : true),
                    onSecondaryTapDown: (details) {
                      _showColumnContextMenu(
                          context, details.globalPosition, field, label);
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
                if (isSorted)
                  Icon(
                    _sortAscending ? Icons.arrow_upward : Icons.arrow_downward,
                    size: 10,
                    color: Colors.blue,
                  ),
                GestureDetector(
                  key: filterKey,
                  onTap: () {
                    final RenderBox? renderBox =
                        filterKey.currentContext?.findRenderObject()
                            as RenderBox?;
                    if (renderBox != null) {
                      final position =
                          renderBox.localToGlobal(Offset.zero);
                      _showColumnContextMenu(
                          context, position, field, label);
                    }
                  },
                  child: Padding(
                    padding: const EdgeInsets.only(left: 2),
                    child: Icon(
                      hasFilter
                          ? Icons.filter_alt
                          : Icons.filter_alt_outlined,
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

  Widget _buildCellColored(
      String value, int index, Color color,
      {String prefix = ''}) {
    return Expanded(
      flex: getColumnFlex(index),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: const BoxDecoration(
          border: Border(
            right: BorderSide(color: AppColors.border, width: 0.5),
          ),
        ),
        child: Text(
          '$prefix$value',
          style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600),
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }

  Widget _buildStatusCell(String status, int index) {
    final isShortage = status == 'SHORTAGE';
    return Expanded(
      flex: getColumnFlex(index),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        decoration: const BoxDecoration(
          border: Border(
            right: BorderSide(color: AppColors.border, width: 0.5),
          ),
        ),
        alignment: Alignment.center,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: isShortage
                ? Colors.red.withOpacity(0.2)
                : Colors.green.withOpacity(0.2),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: isShortage
                  ? Colors.red.withOpacity(0.5)
                  : Colors.green.withOpacity(0.5),
            ),
          ),
          child: Text(
            isShortage ? tr('shortage').toUpperCase() : 'OK',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: isShortage ? Colors.red : Colors.green,
            ),
          ),
        ),
      ),
    );
  }
}
