import 'package:flutter/material.dart';
import 'package:material_warehousing_flutter/core/theme/app_colors.dart';
import 'package:material_warehousing_flutter/core/widgets/field_decoration.dart';

class TableDropdownField extends StatefulWidget {
  final String? value;
  final List<String> headers;
  final List<List<String>> rows;
  final ValueChanged<int>? onRowSelected;
  final double tableWidth;
  final double tableHeight;
  // Nuevo: Filtro de fecha opcional
  final bool showDateFilter;
  final DateTime? selectedDate;
  final Future<void> Function(DateTime)? onDateChanged;

  const TableDropdownField({
    super.key,
    this.value,
    required this.headers,
    this.rows = const [],
    this.onRowSelected,
    this.tableWidth = 450,
    this.tableHeight = 300,
    this.showDateFilter = false,
    this.selectedDate,
    this.onDateChanged,
  });

  @override
  State<TableDropdownField> createState() => _TableDropdownFieldState();
}

class _TableDropdownFieldState extends State<TableDropdownField> {
  final TextEditingController _controller = TextEditingController();
  final TextEditingController _searchController = TextEditingController();
  final LayerLink _layerLink = LayerLink();
  OverlayEntry? _overlayEntry;
  bool _isOpen = false;
  int? _selectedIndex;
  String _searchText = '';
  late DateTime _currentDate;

  @override
  void initState() {
    super.initState();
    _controller.text = widget.value ?? '';
    _currentDate = widget.selectedDate ?? DateTime.now();
  }

  @override
  void didUpdateWidget(covariant TableDropdownField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selectedDate != null && widget.selectedDate != _currentDate) {
      _currentDate = widget.selectedDate!;
    }
    if (widget.value != oldWidget.value) {
      _controller.text = widget.value ?? '';
    }
  }

  @override
  void dispose() {
    _overlayEntry?.remove();
    _overlayEntry = null;
    _controller.dispose();
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
      // Cerrar el overlay primero
      _removeOverlay();
      // Notificar al padre para que cargue los nuevos datos
      if (widget.onDateChanged != null) {
        await widget.onDateChanged!(picked);
      }
      // Esperar al siguiente frame para que los datos estén actualizados
      await Future.delayed(const Duration(milliseconds: 50));
      // Volver a abrir el overlay con los datos actualizados
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
                    // Header
                    Container(
                      color: AppColors.gridHeader,
                      child: Row(
                        children: widget.headers.map((header) => Expanded(
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
                        )).toList(),
                      ),
                    ),
                    // Rows
                    Expanded(
                      child: ListView.builder(
                        padding: EdgeInsets.zero,
                        itemCount: filteredRows.length,
                        itemBuilder: (context, index) {
                          final originalIndex = widget.rows.indexOf(filteredRows[index]);
                          final isSelected = _selectedIndex == originalIndex;
                          return InkWell(
                            onTap: () {
                              setState(() => _selectedIndex = originalIndex);
                              if (filteredRows[index].isNotEmpty) {
                                _controller.text = filteredRows[index][0];
                              }
                              widget.onRowSelected?.call(originalIndex);
                              _removeOverlay();
                            },
                            child: Container(
                              color: isSelected ? AppColors.border.withOpacity(0.5) : null,
                              child: Row(
                                children: filteredRows[index].map((cell) => Expanded(
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                    child: Text(
                                      cell,
                                      style: const TextStyle(fontSize: 12, color: Colors.white),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                )).toList(),
                              ),
                            ),
                          );
                        },
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
            controller: _controller,
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
