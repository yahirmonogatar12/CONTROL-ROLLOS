import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_warehousing_flutter/core/localization/app_translations.dart';
import 'package:material_warehousing_flutter/core/theme/app_colors.dart';
import 'package:material_warehousing_flutter/core/widgets/grid_footer.dart';
import 'outgoing_history_view.dart';

// REGIST: dos grids izquierda/derecha
class OutgoingRegistView extends StatelessWidget {
  final LanguageProvider languageProvider;
  final List<Map<String, dynamic>> bomData;
  final int planCount;
  final List<Map<String, dynamic>> sessionOutgoings;
  final bool isRequirementsMode;
  
  const OutgoingRegistView({
    super.key, 
    required this.languageProvider,
    required this.bomData,
    this.planCount = 0,
    this.sessionOutgoings = const [],
    this.isRequirementsMode = false,
  });
  
  String tr(String key) => languageProvider.tr(key);

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.gridBackground,
        border: Border(
          right: BorderSide(color: AppColors.border, width: 2),
        ),
      ),
      child: Column(
        children: [
          Expanded(
            child: Row(
              children: [
                Expanded(child: BomGridPanel(
                  languageProvider: languageProvider,
                  bomData: bomData,
                  planCount: planCount,
                  isRequirementsMode: isRequirementsMode,
                )),
                Container(width: 2, color: AppColors.border),
                Expanded(child: SessionOutgoingsGrid(
                  languageProvider: languageProvider,
                  outgoings: sessionOutgoings,
                )),
              ],
            ),
          ),
          Container(height: 2, color: AppColors.border),
          const GridFooter(text: ''),
        ],
      ),
    );
  }
}

// ============================================
// BOM Grid Panel con filtros
// ============================================
class BomGridPanel extends StatefulWidget {
  final LanguageProvider languageProvider;
  final List<Map<String, dynamic>> bomData;
  final int planCount;
  final bool isRequirementsMode;

  const BomGridPanel({
    super.key,
    required this.languageProvider,
    required this.bomData,
    this.planCount = 0,
    this.isRequirementsMode = false,
  });

  @override
  State<BomGridPanel> createState() => _BomGridPanelState();
}

class _BomGridPanelState extends State<BomGridPanel> {
  // Filtros y ordenamiento
  Map<String, String?> _columnFilters = {};
  String? _sortColumn;
  bool _sortAscending = true;
  List<Map<String, dynamic>> _filteredData = [];
  
  // Búsqueda Ctrl+F
  bool _showSearchBar = false;
  String _searchText = '';
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final FocusNode _keyboardFocusNode = FocusNode();
  
  // GlobalKeys para posicionar filtros
  final Map<String, GlobalKey> _filterKeys = {};

  // Campos del BOM
  final List<String> _fields = ['side', 'codigo_material', 'numero_parte', 'required_qty', 'outgoing_qty', 'in_line', 'location', 'tipo_material'];

  String tr(String key) => widget.languageProvider.tr(key);

  List<String> get _headers => [
    widget.isRequirementsMode ? tr('target_area') : tr('process'),
    tr('material_code'),
    tr('part_number'),
    widget.isRequirementsMode ? tr('qty_required') : tr('bom_qty'),
    tr('outgoing_qty'),
    widget.isRequirementsMode ? tr('available_inventory') : tr('in_line'),
    tr('location'),
    widget.isRequirementsMode ? tr('material_spec') : tr('material_property'),
  ];

  @override
  void initState() {
    super.initState();
    // Inicializar filter keys
    for (var field in _fields) {
      _filterKeys[field] = GlobalKey();
    }
    _applyFiltersAndSort();
  }
  
  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    _keyboardFocusNode.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant BomGridPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.bomData != oldWidget.bomData) {
      _applyFiltersAndSort();
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
        _applyFiltersAndSort();
      }
    });
  }
  
  void _onSearchTextChanged(String text) {
    setState(() {
      _searchText = text;
      _applyFiltersAndSort();
    });
  }

  void _applyFiltersAndSort() {
    var data = List<Map<String, dynamic>>.from(widget.bomData);
    
    // Aplicar búsqueda global
    if (_searchText.isNotEmpty) {
      data = data.where((row) {
        for (var field in _fields) {
          String value;
          if (field == 'codigo_material') {
            value = row['codigo_material']?.toString() ?? row['material_code']?.toString() ?? '';
          } else if (field == 'tipo_material') {
            value = row['tipo_material']?.toString() ?? row['classification']?.toString() ?? '';
          } else {
            value = row[field]?.toString() ?? '';
          }
          if (value.toLowerCase().contains(_searchText.toLowerCase())) {
            return true;
          }
        }
        return false;
      }).toList();
    }
    
    // Aplicar filtros
    if (_columnFilters.isNotEmpty) {
      data = data.where((row) {
        for (var entry in _columnFilters.entries) {
          final field = entry.key;
          final filterValue = entry.value;
          if (filterValue == null) continue;
          
          String value;
          if (field == 'required_qty') {
            final bomQty = double.tryParse(row['bom_qty']?.toString() ?? row['cantidad_total']?.toString() ?? '0') ?? 0;
            final reqQty = (row['required_qty'] as num?)?.toDouble() ?? (bomQty * widget.planCount);
            value = reqQty.toStringAsFixed(0);
          } else if (field == 'outgoing_qty') {
            value = ((row['outgoing_qty'] as num?)?.toDouble() ?? 0).toStringAsFixed(0);
          } else if (field == 'codigo_material') {
            value = row['codigo_material']?.toString() ?? row['material_code']?.toString() ?? '';
          } else if (field == 'tipo_material') {
            value = row['tipo_material']?.toString() ?? row['classification']?.toString() ?? '';
          } else {
            value = row[field]?.toString() ?? '';
          }
          
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
    
    // Aplicar ordenamiento
    if (_sortColumn != null) {
      data.sort((a, b) {
        String aValue, bValue;
        if (_sortColumn == 'required_qty') {
          final aBomQty = double.tryParse(a['bom_qty']?.toString() ?? a['cantidad_total']?.toString() ?? '0') ?? 0;
          final bBomQty = double.tryParse(b['bom_qty']?.toString() ?? b['cantidad_total']?.toString() ?? '0') ?? 0;
          aValue = ((a['required_qty'] as num?)?.toDouble() ?? (aBomQty * widget.planCount)).toString();
          bValue = ((b['required_qty'] as num?)?.toDouble() ?? (bBomQty * widget.planCount)).toString();
        } else if (_sortColumn == 'outgoing_qty') {
          aValue = ((a['outgoing_qty'] as num?)?.toDouble() ?? 0).toString();
          bValue = ((b['outgoing_qty'] as num?)?.toDouble() ?? 0).toString();
        } else {
          aValue = a[_sortColumn]?.toString() ?? '';
          bValue = b[_sortColumn]?.toString() ?? '';
        }
        
        final aNum = num.tryParse(aValue);
        final bNum = num.tryParse(bValue);
        int result;
        if (aNum != null && bNum != null) {
          result = aNum.compareTo(bNum);
        } else {
          result = aValue.toLowerCase().compareTo(bValue.toLowerCase());
        }
        return _sortAscending ? result : -result;
      });
    }
    
    setState(() => _filteredData = data);
  }

  void _sortByColumn(String field, bool ascending) {
    _sortColumn = field;
    _sortAscending = ascending;
    _applyFiltersAndSort();
  }

  void _clearSorting() {
    _sortColumn = null;
    _sortAscending = true;
    _applyFiltersAndSort();
  }

  void _applyFilter(String field, String? filterValue) {
    if (filterValue == null || filterValue.isEmpty) {
      _columnFilters.remove(field);
    } else {
      _columnFilters[field] = filterValue;
    }
    _applyFiltersAndSort();
  }

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
              Text('Search (Ctrl+F)', style: TextStyle(fontSize: 12, color: Colors.white)),
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
          _showFilterDropdown(context, field, header);
          break;
        case 'search':
          _toggleSearchBar();
          break;
      }
    });
  }

  void _showFilterDropdown(BuildContext context, String field, String header) {
    // Obtener posición del icono de filtro
    final RenderBox? renderBox = _filterKeys[field]?.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;
    
    final position = renderBox.localToGlobal(Offset.zero);
    final size = renderBox.size;
    
    // Obtener valores únicos para BOM
    final Set<String> uniqueValues = {};
    bool hasBlanks = false;
    
    for (var row in widget.bomData) {
      String value;
      if (field == 'required_qty') {
        final bomQty = double.tryParse(row['bom_qty']?.toString() ?? row['cantidad_total']?.toString() ?? '0') ?? 0;
        final reqQty = (row['required_qty'] as num?)?.toDouble() ?? (bomQty * widget.planCount);
        value = reqQty.toStringAsFixed(0);
      } else if (field == 'outgoing_qty') {
        value = ((row['outgoing_qty'] as num?)?.toDouble() ?? 0).toStringAsFixed(0);
      } else if (field == 'codigo_material') {
        value = row['codigo_material']?.toString() ?? row['material_code']?.toString() ?? '';
      } else if (field == 'tipo_material') {
        value = row['tipo_material']?.toString() ?? row['classification']?.toString() ?? '';
      } else {
        value = row[field]?.toString() ?? '';
      }
      
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
      builder: (context) {
        String searchText = '';
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final filteredValues = sortedValues
                .where((v) => v.toLowerCase().contains(searchText.toLowerCase()))
                .toList();
            
            return Stack(
              children: [
                Positioned.fill(
                  child: GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(color: Colors.transparent),
                  ),
                ),
                Positioned(
                  left: position.dx - 180,
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
                                    _buildFilterOption(context, '(Clear Filter)', false, Icons.clear, Colors.orange, () {
                                      Navigator.pop(context);
                                      _applyFilter(field, null);
                                    }),
                                  if (hasBlanks)
                                    _buildFilterOption(context, '(Blanks)', currentFilter == '__BLANKS__', null, null, () {
                                      Navigator.pop(context);
                                      _applyFilter(field, '__BLANKS__');
                                    }),
                                  _buildFilterOption(context, '(Non blanks)', currentFilter == '__NON_BLANKS__', null, null, () {
                                    Navigator.pop(context);
                                    _applyFilter(field, '__NON_BLANKS__');
                                  }),
                                  const Divider(height: 1, color: Color(0xFF3C3C3C)),
                                  ...filteredValues.map((value) => _buildFilterOption(
                                    context, value, currentFilter == value, null, null, () {
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

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _keyboardFocusNode,
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.keyF && HardwareKeyboard.instance.isControlPressed) {
          _toggleSearchBar();
          return KeyEventResult.handled;
        }
        if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.escape && _showSearchBar) {
          _toggleSearchBar();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: () => _keyboardFocusNode.requestFocus(),
        child: Column(
          children: [
            // Barra de búsqueda Ctrl+F
            if (_showSearchBar)
              Container(
                height: 32,
                color: AppColors.panelBackground,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        focusNode: _searchFocusNode,
                        onChanged: _onSearchTextChanged,
                        style: const TextStyle(fontSize: 12, color: Colors.white),
                        decoration: InputDecoration(
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                          hintText: 'Search...',
                          hintStyle: const TextStyle(color: Colors.white54, fontSize: 12),
                          filled: true,
                          fillColor: AppColors.fieldBackground,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: const BorderSide(color: AppColors.border)),
                          suffixIcon: _searchController.text.isNotEmpty
                              ? IconButton(icon: const Icon(Icons.clear, size: 16, color: Colors.white70), onPressed: () { _searchController.clear(); _onSearchTextChanged(''); }, padding: EdgeInsets.zero, constraints: const BoxConstraints())
                              : null,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(height: 24, child: ElevatedButton(onPressed: _toggleSearchBar, style: ElevatedButton.styleFrom(backgroundColor: Colors.grey[700], padding: const EdgeInsets.symmetric(horizontal: 8)), child: const Text('Close', style: TextStyle(fontSize: 10)))),
                  ],
                ),
              ),
            // Encabezados con filtros e iconos
            Container(
              height: 36,
              color: AppColors.gridHeader,
              child: Row(
                children: List.generate(_headers.length, (i) {
                  final field = _fields[i];
                  final header = _headers[i];
                  final hasFilter = _columnFilters.containsKey(field);
                  final isSorted = _sortColumn == field;
                  
                  return Expanded(
                    child: GestureDetector(
                      onSecondaryTapDown: (details) {
                        _showColumnContextMenu(context, details.globalPosition, field, header);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
                        alignment: Alignment.center,
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                header,
                                style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white),
                                textAlign: TextAlign.center,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (isSorted)
                              Icon(_sortAscending ? Icons.arrow_upward : Icons.arrow_downward, size: 10, color: Colors.blue),
                            GestureDetector(
                              key: _filterKeys[field],
                              onTap: () => _showFilterDropdown(context, field, header),
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
                  );
                }),
              ),
            ),
            // Datos
            Expanded(
              child: _filteredData.isEmpty && widget.bomData.isEmpty
                  ? const Center(
                      child: Text(
                        'Select a model to view BOM',
                        style: TextStyle(color: Colors.white54, fontSize: 12),
                      ),
                    )
                  : _filteredData.isEmpty
                      ? const Center(
                          child: Text(
                            'No matching data',
                            style: TextStyle(color: Colors.white54, fontSize: 12),
                          ),
                        )
                      : ListView.builder(
                          itemCount: _filteredData.length,
                          itemBuilder: (context, index) {
                            final row = _filteredData[index];
                            final isEven = index % 2 == 0;
                            final bomQty = double.tryParse(row['bom_qty']?.toString() ?? row['cantidad_total']?.toString() ?? '0') ?? 0;
                            final requiredQty = (row['required_qty'] as num?)?.toDouble() ?? (bomQty * widget.planCount);
                            final outgoingQty = (row['outgoing_qty'] as num?)?.toDouble() ?? 0;
                            final isComplete = outgoingQty >= requiredQty && requiredQty > 0;
                            final inLine = row['in_line']?.toString() ?? '0';
                            final location = row['location']?.toString() ?? '';
                            
                            Color rowColor;
                            if (isComplete) {
                              rowColor = const Color(0xFF1B5E20);
                            } else {
                              rowColor = isEven ? AppColors.gridRowEven : AppColors.gridRowOdd;
                            }
                            
                            return Container(
                              color: rowColor,
                              child: Row(
                                children: [
                                  _buildCellHighlight(row['side']?.toString() ?? ''),
                                  _buildCellHighlight(row['codigo_material']?.toString() ?? row['material_code']?.toString() ?? ''),
                                  _buildCellHighlight(row['numero_parte']?.toString() ?? ''),
                                  _buildCellHighlight(requiredQty.toStringAsFixed(0)),
                                  _buildCellHighlight(outgoingQty.toStringAsFixed(0)),
                                  _buildCellHighlight(inLine),
                                  _buildCellHighlight(location),
                                  _buildCellHighlight(row['tipo_material']?.toString() ?? row['classification']?.toString() ?? ''),
                                ],
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildCellHighlight(String text) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: _highlightText(text),
      ),
    );
  }
  
  Widget _highlightText(String text) {
    if (_searchText.isEmpty) {
      return Text(text, style: const TextStyle(fontSize: 11, color: Colors.white), overflow: TextOverflow.ellipsis);
    }
    final lowerText = text.toLowerCase();
    final lowerSearch = _searchText.toLowerCase();
    final index = lowerText.indexOf(lowerSearch);
    if (index < 0) {
      return Text(text, style: const TextStyle(fontSize: 11, color: Colors.white), overflow: TextOverflow.ellipsis);
    }
    return RichText(
      overflow: TextOverflow.ellipsis,
      text: TextSpan(children: [
        TextSpan(text: text.substring(0, index), style: const TextStyle(fontSize: 11, color: Colors.white)),
        TextSpan(text: text.substring(index, index + _searchText.length), style: const TextStyle(fontSize: 11, color: Colors.black, backgroundColor: Colors.yellow, fontWeight: FontWeight.bold)),
        TextSpan(text: text.substring(index + _searchText.length), style: const TextStyle(fontSize: 11, color: Colors.white)),
      ]),
    );
  }
}

// ============================================
// Session Outgoings Grid con filtros
// ============================================
class SessionOutgoingsGrid extends StatefulWidget {
  final LanguageProvider languageProvider;
  final List<Map<String, dynamic>> outgoings;

  const SessionOutgoingsGrid({
    super.key,
    required this.languageProvider,
    required this.outgoings,
  });

  @override
  State<SessionOutgoingsGrid> createState() => _SessionOutgoingsGridState();
}

class _SessionOutgoingsGridState extends State<SessionOutgoingsGrid> {
  Map<String, String?> _columnFilters = {};
  String? _sortColumn;
  bool _sortAscending = true;
  List<Map<String, dynamic>> _filteredData = [];
  
  // Búsqueda Ctrl+F
  bool _showSearchBar = false;
  String _searchText = '';
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final FocusNode _keyboardFocusNode = FocusNode();
  
  // GlobalKeys para posicionar filtros
  final Map<String, GlobalKey> _filterKeys = {};

  final List<String> _fields = ['codigo_material_recibido', 'material_code', 'numero_parte', 'cantidad_salida', 'modelo', 'numero_lote', 'material_property', 'msl_level', 'especificacion_material'];

  String tr(String key) => widget.languageProvider.tr(key);

  List<String> get _headers => [
    tr('warehousing_code'),
    tr('material_code'),
    tr('part_number'),
    tr('qty'),
    tr('model'),
    tr('material_lot_no'),
    tr('material_property'),
    tr('msl_level'),
    tr('material_spec'),
  ];

  @override
  void initState() {
    super.initState();
    for (var field in _fields) {
      _filterKeys[field] = GlobalKey();
    }
    // Inicializar _filteredData con los datos actuales
    _filteredData = List<Map<String, dynamic>>.from(widget.outgoings);
  }
  
  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    _keyboardFocusNode.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant SessionOutgoingsGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Siempre actualizar cuando cambia la lista de outgoings
    _applyFiltersAndSort();
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
        _applyFiltersAndSort();
      }
    });
  }
  
  void _onSearchTextChanged(String text) {
    setState(() {
      _searchText = text;
      _applyFiltersAndSort();
    });
  }

  void _applyFiltersAndSort() {
    var data = List<Map<String, dynamic>>.from(widget.outgoings);
    
    // Búsqueda global
    if (_searchText.isNotEmpty) {
      data = data.where((row) {
        for (var field in _fields) {
          final value = row[field]?.toString() ?? '';
          if (value.toLowerCase().contains(_searchText.toLowerCase())) {
            return true;
          }
        }
        return false;
      }).toList();
    }
    
    if (_columnFilters.isNotEmpty) {
      data = data.where((row) {
        for (var entry in _columnFilters.entries) {
          final field = entry.key;
          final filterValue = entry.value;
          if (filterValue == null) continue;
          
          final value = row[field]?.toString() ?? '';
          
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
    
    if (_sortColumn != null) {
      data.sort((a, b) {
        final aValue = a[_sortColumn]?.toString() ?? '';
        final bValue = b[_sortColumn]?.toString() ?? '';
        final aNum = num.tryParse(aValue);
        final bNum = num.tryParse(bValue);
        int result;
        if (aNum != null && bNum != null) {
          result = aNum.compareTo(bNum);
        } else {
          result = aValue.toLowerCase().compareTo(bValue.toLowerCase());
        }
        return _sortAscending ? result : -result;
      });
    }
    
    setState(() => _filteredData = data);
  }

  void _sortByColumn(String field, bool ascending) {
    _sortColumn = field;
    _sortAscending = ascending;
    _applyFiltersAndSort();
  }

  void _clearSorting() {
    _sortColumn = null;
    _sortAscending = true;
    _applyFiltersAndSort();
  }

  void _applyFilter(String field, String? filterValue) {
    if (filterValue == null || filterValue.isEmpty) {
      _columnFilters.remove(field);
    } else {
      _columnFilters[field] = filterValue;
    }
    _applyFiltersAndSort();
  }

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
              Text('Search (Ctrl+F)', style: TextStyle(fontSize: 12, color: Colors.white)),
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
          _showFilterDropdown(context, field, header);
          break;
        case 'search':
          _toggleSearchBar();
          break;
      }
    });
  }

  void _showFilterDropdown(BuildContext context, String field, String header) {
    // Obtener posición del icono de filtro
    final RenderBox? renderBox = _filterKeys[field]?.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;
    
    final position = renderBox.localToGlobal(Offset.zero);
    final size = renderBox.size;
    
    final Set<String> uniqueValues = {};
    bool hasBlanks = false;
    
    for (var row in widget.outgoings) {
      final value = row[field]?.toString() ?? '';
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
      builder: (context) {
        String searchText = '';
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final filteredValues = sortedValues
                .where((v) => v.toLowerCase().contains(searchText.toLowerCase()))
                .toList();
            
            return Stack(
              children: [
                Positioned.fill(
                  child: GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(color: Colors.transparent),
                  ),
                ),
                Positioned(
                  left: position.dx - 180,
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
                                    _buildFilterOption(context, '(Clear Filter)', false, Icons.clear, Colors.orange, () {
                                      Navigator.pop(context);
                                      _applyFilter(field, null);
                                    }),
                                  if (hasBlanks)
                                    _buildFilterOption(context, '(Blanks)', currentFilter == '__BLANKS__', null, null, () {
                                      Navigator.pop(context);
                                      _applyFilter(field, '__BLANKS__');
                                    }),
                                  _buildFilterOption(context, '(Non blanks)', currentFilter == '__NON_BLANKS__', null, null, () {
                                    Navigator.pop(context);
                                    _applyFilter(field, '__NON_BLANKS__');
                                  }),
                                  const Divider(height: 1, color: Color(0xFF3C3C3C)),
                                  ...filteredValues.map((value) => _buildFilterOption(
                                    context, value, currentFilter == value, null, null, () {
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

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _keyboardFocusNode,
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.keyF && HardwareKeyboard.instance.isControlPressed) {
          _toggleSearchBar();
          return KeyEventResult.handled;
        }
        if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.escape && _showSearchBar) {
          _toggleSearchBar();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: () => _keyboardFocusNode.requestFocus(),
        child: Column(
          children: [
            // Barra de búsqueda Ctrl+F
            if (_showSearchBar)
              Container(
                height: 32,
                color: AppColors.panelBackground,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        focusNode: _searchFocusNode,
                        onChanged: _onSearchTextChanged,
                        style: const TextStyle(fontSize: 12, color: Colors.white),
                        decoration: InputDecoration(
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                          hintText: 'Search...',
                          hintStyle: const TextStyle(color: Colors.white54, fontSize: 12),
                          filled: true,
                          fillColor: AppColors.fieldBackground,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: const BorderSide(color: AppColors.border)),
                          suffixIcon: _searchController.text.isNotEmpty
                              ? IconButton(icon: const Icon(Icons.clear, size: 16, color: Colors.white70), onPressed: () { _searchController.clear(); _onSearchTextChanged(''); }, padding: EdgeInsets.zero, constraints: const BoxConstraints())
                              : null,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(height: 24, child: ElevatedButton(onPressed: _toggleSearchBar, style: ElevatedButton.styleFrom(backgroundColor: Colors.grey[700], padding: const EdgeInsets.symmetric(horizontal: 8)), child: const Text('Close', style: TextStyle(fontSize: 10)))),
                  ],
                ),
              ),
            // Encabezados con filtros e iconos
            Container(
              height: 36,
              color: AppColors.gridHeader,
              child: Row(
                children: List.generate(_headers.length, (i) {
                  final field = _fields[i];
                  final header = _headers[i];
                  final hasFilter = _columnFilters.containsKey(field);
                  final isSorted = _sortColumn == field;
                  
                  return Expanded(
                    child: GestureDetector(
                      onSecondaryTapDown: (details) {
                        _showColumnContextMenu(context, details.globalPosition, field, header);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
                        alignment: Alignment.center,
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                header,
                                style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white),
                                textAlign: TextAlign.center,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (isSorted)
                              Icon(_sortAscending ? Icons.arrow_upward : Icons.arrow_downward, size: 10, color: Colors.blue),
                            GestureDetector(
                              key: _filterKeys[field],
                              onTap: () => _showFilterDropdown(context, field, header),
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
                  );
                }),
              ),
            ),
            // Datos
            Expanded(
              child: _filteredData.isEmpty && widget.outgoings.isEmpty
                  ? const Center(
                      child: Text(
                        'No data',
                        style: TextStyle(color: Colors.white54, fontSize: 12),
                      ),
                    )
                  : _filteredData.isEmpty
                      ? const Center(
                          child: Text(
                            'No matching data',
                            style: TextStyle(color: Colors.white54, fontSize: 12),
                          ),
                        )
                      : ListView.builder(
                          itemCount: _filteredData.length,
                          itemBuilder: (context, index) {
                            final row = _filteredData[index];
                            final isEven = index % 2 == 0;
                            return Container(
                              color: isEven ? AppColors.gridRowEven : AppColors.gridRowOdd,
                              child: Row(
                                children: [
                                  _buildCellHighlight(row['codigo_material_recibido']?.toString() ?? ''),
                                  _buildCellHighlight(row['material_code']?.toString() ?? ''),
                                  _buildCellHighlight(row['numero_parte']?.toString() ?? ''),
                                  _buildCellHighlight(row['cantidad_salida']?.toString() ?? ''),
                                  _buildCellHighlight(row['modelo']?.toString() ?? ''),
                                  _buildCellHighlight(row['numero_lote']?.toString() ?? ''),
                                  _buildCellHighlight(row['material_property']?.toString() ?? ''),
                                  _buildCellHighlight(row['msl_level']?.toString() ?? ''),
                                  _buildCellHighlight(row['especificacion_material']?.toString() ?? ''),
                                ],
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildCellHighlight(String text) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: _highlightText(text),
      ),
    );
  }
  
  Widget _highlightText(String text) {
    if (_searchText.isEmpty) {
      return Text(text, style: const TextStyle(fontSize: 11, color: Colors.white), overflow: TextOverflow.ellipsis);
    }
    final lowerText = text.toLowerCase();
    final lowerSearch = _searchText.toLowerCase();
    final index = lowerText.indexOf(lowerSearch);
    if (index < 0) {
      return Text(text, style: const TextStyle(fontSize: 11, color: Colors.white), overflow: TextOverflow.ellipsis);
    }
    return RichText(
      overflow: TextOverflow.ellipsis,
      text: TextSpan(children: [
        TextSpan(text: text.substring(0, index), style: const TextStyle(fontSize: 11, color: Colors.white)),
        TextSpan(text: text.substring(index, index + _searchText.length), style: const TextStyle(fontSize: 11, color: Colors.black, backgroundColor: Colors.yellow, fontWeight: FontWeight.bold)),
        TextSpan(text: text.substring(index + _searchText.length), style: const TextStyle(fontSize: 11, color: Colors.white)),
      ]),
    );
  }
}

// ============================================
// Regist / History tabs
// ============================================
class OutgoingTabSection extends StatefulWidget {
  final LanguageProvider languageProvider;
  final List<Map<String, dynamic>> bomData;
  final int planCount;
  final List<Map<String, dynamic>> sessionOutgoings;
  final bool isRequirementsMode;
  
  const OutgoingTabSection({
    super.key, 
    required this.languageProvider,
    this.bomData = const [],
    this.planCount = 0,
    this.sessionOutgoings = const [],
    this.isRequirementsMode = false,
  });

  @override
  State<OutgoingTabSection> createState() => OutgoingTabSectionState();
}

class OutgoingTabSectionState extends State<OutgoingTabSection> {
  final GlobalKey<OutgoingHistoryViewState> _historyKey = GlobalKey();

  /// Método público para agregar registros al historial
  void addOutgoingToHistory(Map<String, dynamic> record) {
    _historyKey.currentState?.addOutgoingRecord(record);
  }

  /// Método público para refrescar el historial
  Future<void> refreshHistory() async {
    await _historyKey.currentState?.refresh();
  }

  @override
  Widget build(BuildContext context) {
    final tr = widget.languageProvider.tr;
    return DefaultTabController(
      length: 2,
      animationDuration: const Duration(milliseconds: 700),
      child: Container(
        color: AppColors.panelBackground,
        child: Column(
          children: [
            Container(
              color: AppColors.gridHeader,
              child: Row(
                children: [
                  SizedBox(
                    width: 140,
                    child: TabBar(
                      labelStyle: const TextStyle(fontSize: 12),
                      unselectedLabelColor: Colors.white70,
                      labelColor: Colors.white,
                      indicatorColor: Colors.white,
                      labelPadding: const EdgeInsets.symmetric(horizontal: 8),
                      tabs: [
                        Tab(text: tr('regist'), height: 32),
                        Tab(text: tr('history'), height: 32),
                      ],
                    ),
                  ),
                  const Spacer(),
                ],
              ),
            ),
            Expanded(
              child: TabBarView(
                children: [
                  OutgoingRegistView(
                    languageProvider: widget.languageProvider,
                    bomData: widget.bomData,
                    planCount: widget.planCount,
                    sessionOutgoings: widget.sessionOutgoings,
                    isRequirementsMode: widget.isRequirementsMode,
                  ),
                  OutgoingHistoryView(
                    key: _historyKey,
                    languageProvider: widget.languageProvider,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
