import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_warehousing_flutter/core/theme/app_colors.dart';
import 'package:material_warehousing_flutter/core/widgets/field_decoration.dart';

class MultiSelectTableDropdown extends StatefulWidget {
  final List<String> headers;
  final List<List<String>> rows;
  final Set<int> selectedIndices;
  final ValueChanged<Set<int>>? onSelectionChanged;
  final double tableWidth;
  final double tableHeight;
  // Filtro de fecha opcional
  final bool showDateFilter;
  final DateTime? selectedDate;
  final Future<void> Function(DateTime)? onDateChanged;

  const MultiSelectTableDropdown({
    super.key,
    required this.headers,
    this.rows = const [],
    this.selectedIndices = const {},
    this.onSelectionChanged,
    this.tableWidth = 550,
    this.tableHeight = 380,
    this.showDateFilter = false,
    this.selectedDate,
    this.onDateChanged,
  });

  @override
  State<MultiSelectTableDropdown> createState() => _MultiSelectTableDropdownState();
}

class _MultiSelectTableDropdownState extends State<MultiSelectTableDropdown> {
  final TextEditingController _searchController = TextEditingController();
  final LayerLink _layerLink = LayerLink();
  OverlayEntry? _overlayEntry;
  bool _isOpen = false;
  String _searchText = '';
  late DateTime _currentDate;
  late Set<int> _localSelection;
  int? _lastClickedFilteredIndex; // Índice del último clic en la lista filtrada

  @override
  void initState() {
    super.initState();
    _currentDate = widget.selectedDate ?? DateTime.now();
    _localSelection = Set.from(widget.selectedIndices);
  }

  @override
  void didUpdateWidget(covariant MultiSelectTableDropdown oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selectedDate != null && widget.selectedDate != _currentDate) {
      _currentDate = widget.selectedDate!;
    }
    // Si los rows cambiaron, limpiar índices inválidos
    if (widget.rows != oldWidget.rows) {
      _localSelection = _localSelection.where((i) => i >= 0 && i < widget.rows.length).toSet();
    }
    if (widget.selectedIndices != oldWidget.selectedIndices) {
      _localSelection = widget.selectedIndices.where((i) => i >= 0 && i < widget.rows.length).toSet();
    }
  }

  @override
  void dispose() {
    _overlayEntry?.remove();
    _overlayEntry = null;
    _searchController.dispose();
    super.dispose();
  }

  void _toggleOverlay() {
    if (_isOpen) {
      _removeOverlay();
    } else {
      _showOverlay();
    }
  }

  void _showOverlay() {
    _searchController.clear();
    _searchText = '';
    _localSelection = Set.from(widget.selectedIndices);
    _overlayEntry = _createOverlayEntry();
    Overlay.of(context).insert(_overlayEntry!);
    setState(() => _isOpen = true);
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
    if (mounted) {
      setState(() => _isOpen = false);
    }
  }

  void _updateSearch(String value) {
    _searchText = value.toLowerCase();
    _overlayEntry?.markNeedsBuild();
  }

  void _toggleSelection(int originalIndex, {bool isShiftPressed = false, int? filteredIndex, List<List<String>>? filteredRows}) {
    if (isShiftPressed && _lastClickedFilteredIndex != null && filteredIndex != null && filteredRows != null) {
      // Selección en rango con Shift - usar índices filtrados
      final start = _lastClickedFilteredIndex! < filteredIndex ? _lastClickedFilteredIndex! : filteredIndex;
      final end = _lastClickedFilteredIndex! > filteredIndex ? _lastClickedFilteredIndex! : filteredIndex;
      for (int i = start; i <= end; i++) {
        // Convertir índice filtrado a índice original
        final origIdx = widget.rows.indexOf(filteredRows[i]);
        if (origIdx >= 0) {
          _localSelection.add(origIdx);
        }
      }
      _lastClickedFilteredIndex = filteredIndex;
    } else {
      // Selección individual normal
      if (_localSelection.contains(originalIndex)) {
        _localSelection.remove(originalIndex);
      } else {
        _localSelection.add(originalIndex);
      }
      _lastClickedFilteredIndex = filteredIndex;
    }
    _overlayEntry?.markNeedsBuild();
    // Notificar inmediatamente al padre
    widget.onSelectionChanged?.call(Set.from(_localSelection));
  }

  void _selectAll() {
    _localSelection = Set.from(List.generate(widget.rows.length, (i) => i));
    _overlayEntry?.markNeedsBuild();
    widget.onSelectionChanged?.call(Set.from(_localSelection));
  }

  void _clearAll() {
    _localSelection.clear();
    _overlayEntry?.markNeedsBuild();
    widget.onSelectionChanged?.call(Set.from(_localSelection));
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _currentDate,
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
            dialogTheme: DialogThemeData(backgroundColor: AppColors.panelBackground),
            textTheme: const TextTheme(
              headlineMedium: TextStyle(fontSize: 20, fontWeight: FontWeight.w500),
              labelLarge: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
              bodyLarge: TextStyle(fontSize: 13),
            ),
          ),
          child: Transform.scale(
            scale: 0.9,
            child: child!,
          ),
        );
      },
    );
    if (picked != null && picked != _currentDate) {
      _currentDate = picked;
      _removeOverlay();
      if (widget.onDateChanged != null) {
        await widget.onDateChanged!(picked);
      }
      await Future.delayed(const Duration(milliseconds: 50));
      if (mounted) {
        _showOverlay();
      }
    }
  }

  List<List<String>> get _filteredRows {
    if (_searchText.isEmpty) return widget.rows;
    return widget.rows.where((row) {
      return row.any((cell) => cell.toLowerCase().contains(_searchText));
    }).toList();
  }

  String get _displayText {
    // Filtrar índices válidos
    final validSelection = _localSelection.where((i) => i >= 0 && i < widget.rows.length).toSet();
    if (validSelection.isEmpty) {
      return '';
    } else if (validSelection.length == 1) {
      final idx = validSelection.first;
      if (widget.rows[idx].isNotEmpty) {
        return widget.rows[idx][0];
      }
      return '1 seleccionado';
    } else {
      return '${validSelection.length} seleccionados';
    }
  }

  OverlayEntry _createOverlayEntry() {
    final renderBox = context.findRenderObject() as RenderBox;
    final size = renderBox.size;

    return OverlayEntry(
      builder: (context) {
        final filteredRows = _filteredRows;
        return Positioned(
          width: widget.tableWidth,
          child: CompositedTransformFollower(
            link: _layerLink,
            showWhenUnlinked: false,
            offset: Offset(0, size.height + 2),
            child: Material(
              elevation: 4,
              borderRadius: BorderRadius.circular(4),
              child: Container(
                height: widget.tableHeight,
                decoration: BoxDecoration(
                  color: AppColors.fieldBackground,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  children: [
                    // Date filter (optional)
                    if (widget.showDateFilter)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                        decoration: BoxDecoration(
                          color: AppColors.panelBackground,
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.calendar_today, color: Colors.white54, size: 14),
                            const SizedBox(width: 6),
                            Expanded(
                              child: InkWell(
                                onTap: () => _selectDate(context),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: AppColors.fieldBackground,
                                    borderRadius: BorderRadius.circular(3),
                                    border: Border.all(color: AppColors.border, width: 0.5),
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        '${_currentDate.year}-${_currentDate.month.toString().padLeft(2, '0')}-${_currentDate.day.toString().padLeft(2, '0')}',
                                        style: const TextStyle(fontSize: 11, color: Colors.white),
                                      ),
                                      const Icon(Icons.arrow_drop_down, color: Colors.white54, size: 16),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            // Botones Select All / Clear
                            InkWell(
                              onTap: _selectAll,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: AppColors.buttonSearch,
                                  borderRadius: BorderRadius.circular(3),
                                ),
                                child: const Text('All', style: TextStyle(fontSize: 10, color: Colors.white)),
                              ),
                            ),
                            const SizedBox(width: 4),
                            InkWell(
                              onTap: _clearAll,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.grey[700],
                                  borderRadius: BorderRadius.circular(3),
                                ),
                                child: const Text('Clear', style: TextStyle(fontSize: 10, color: Colors.white)),
                              ),
                            ),
                          ],
                        ),
                      ),
                    // Search field
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: widget.showDateFilter ? AppColors.panelBackground.withOpacity(0.8) : AppColors.panelBackground,
                        borderRadius: widget.showDateFilter ? BorderRadius.zero : const BorderRadius.vertical(top: Radius.circular(4)),
                      ),
                      child: TextField(
                        controller: _searchController,
                        onChanged: _updateSearch,
                        style: const TextStyle(fontSize: 12, color: Colors.white),
                        decoration: InputDecoration(
                          hintText: 'Buscar...',
                          hintStyle: const TextStyle(fontSize: 12, color: Colors.white54),
                          prefixIcon: const Icon(Icons.search, color: Colors.white54, size: 18),
                          prefixIconConstraints: const BoxConstraints(minWidth: 30),
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          filled: true,
                          fillColor: AppColors.fieldBackground,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(4),
                            borderSide: BorderSide(color: AppColors.border),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(4),
                            borderSide: BorderSide(color: AppColors.border),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(4),
                            borderSide: BorderSide(color: AppColors.border),
                          ),
                        ),
                      ),
                    ),
                    // Header con checkbox
                    Container(
                      color: AppColors.gridHeader,
                      child: Row(
                        children: [
                          // Checkbox column header
                          Container(
                            width: 40,
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                            child: const Center(
                              child: Icon(Icons.check_box_outline_blank, size: 16, color: Colors.white70),
                            ),
                          ),
                          ...widget.headers.map((header) => Expanded(
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                              child: Text(
                                header,
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          )),
                        ],
                      ),
                    ),
                    // Rows con checkboxes
                    Expanded(
                      child: ListView.builder(
                        padding: EdgeInsets.zero,
                        itemCount: filteredRows.length,
                        itemBuilder: (context, index) {
                          final originalIndex = widget.rows.indexOf(filteredRows[index]);
                          final isSelected = _localSelection.contains(originalIndex);
                          return InkWell(
                            onTap: () {
                              // Detectar si Shift está presionado
                              final isShiftPressed = HardwareKeyboard.instance.isShiftPressed;
                              _toggleSelection(
                                originalIndex, 
                                isShiftPressed: isShiftPressed,
                                filteredIndex: index,
                                filteredRows: filteredRows,
                              );
                            },
                            child: Container(
                              color: isSelected ? AppColors.headerTab.withOpacity(0.3) : null,
                              child: Row(
                                children: [
                                  // Checkbox
                                  Container(
                                    width: 40,
                                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                                    child: Checkbox(
                                      value: isSelected,
                                      onChanged: (_) {
                                        final isShiftPressed = HardwareKeyboard.instance.isShiftPressed;
                                        _toggleSelection(
                                          originalIndex, 
                                          isShiftPressed: isShiftPressed,
                                          filteredIndex: index,
                                          filteredRows: filteredRows,
                                        );
                                      },
                                      side: const BorderSide(color: Colors.white54),
                                      activeColor: AppColors.headerTab,
                                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                      visualDensity: VisualDensity.compact,
                                    ),
                                  ),
                                  ...filteredRows[index].map((cell) => Expanded(
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                      child: Text(
                                        cell,
                                        style: const TextStyle(fontSize: 12, color: Colors.white),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  )),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    // Footer con contador
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppColors.panelBackground,
                        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(4)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '${_localSelection.length} seleccionado(s)',
                            style: const TextStyle(fontSize: 11, color: Colors.white70),
                          ),
                          InkWell(
                            onTap: _removeOverlay,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                              decoration: BoxDecoration(
                                color: AppColors.headerTab,
                                borderRadius: BorderRadius.circular(3),
                              ),
                              child: const Text('OK', style: TextStyle(fontSize: 11, color: Colors.white)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _layerLink,
      child: GestureDetector(
        onTap: _toggleOverlay,
        child: AbsorbPointer(
          child: TextFormField(
            controller: TextEditingController(text: _displayText),
            decoration: fieldDecoration().copyWith(
              suffixIcon: Icon(
                _isOpen ? Icons.arrow_drop_up : Icons.arrow_drop_down,
                color: Colors.white70,
                size: 20,
              ),
              suffixIconConstraints: const BoxConstraints(minWidth: 30, minHeight: 20),
            ),
            style: const TextStyle(fontSize: 14),
          ),
        ),
      ),
    );
  }
}
