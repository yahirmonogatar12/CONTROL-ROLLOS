import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_warehousing_flutter/core/localization/app_translations.dart';
import 'package:material_warehousing_flutter/core/theme/app_colors.dart';
import 'package:material_warehousing_flutter/core/services/api_service.dart';
import 'package:material_warehousing_flutter/core/services/printer_service.dart';
import 'package:material_warehousing_flutter/core/widgets/resizable_grid_header.dart';
import 'package:intl/intl.dart';
import 'package:excel/excel.dart' as excel_lib;
import 'package:file_picker/file_picker.dart';

class ReturnGridPanel extends StatefulWidget {
  final LanguageProvider languageProvider;
  
  const ReturnGridPanel({
    super.key,
    required this.languageProvider,
  });

  @override
  State<ReturnGridPanel> createState() => ReturnGridPanelState();
}

class ReturnGridPanelState extends State<ReturnGridPanel> with ResizableColumnsMixin {
  List<Map<String, dynamic>> _originalData = [];
  List<Map<String, dynamic>> _data = [];
  bool _isLoading = true;
  int? _selectedRowIndex;
  final ScrollController _verticalController = ScrollController();
  
  // Filtros por columna y ordenamiento
  Map<String, String?> _columnFilters = {};
  String? _sortColumn;
  bool _sortAscending = true;
  
  // Búsqueda Ctrl+F
  bool _showSearchBar = false;
  String _searchText = '';
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final FocusNode _keyboardFocusNode = FocusNode();
  
  // GlobalKeys para filtros
  final Map<String, GlobalKey> _filterKeys = {};
  
  // Campos
  final List<String> _fields = [
    'return_datetime',
    'material_warehousing_code',
    'material_code',
    'part_number',
    'material_lot_no',
    'packaging_unit',
    'return_qty',
    'material_spec',
    'remarks',
  ];

  String tr(String key) => widget.languageProvider.tr(key);
  
  List<String> get _headers => [
    tr('return_datetime'),
    tr('material_warehousing_code'),
    tr('material_code'),
    tr('part_number'),
    tr('material_lot_no'),
    tr('packaging_unit'),
    tr('return_qty'),
    tr('material_spec'),
    tr('reason'),
  ];

  @override
  void initState() {
    super.initState();
    for (var field in _fields) {
      _filterKeys[field] = GlobalKey();
    }
    initColumnFlex(9, 'return_grid', defaultFlexValues: [3.0, 3.0, 2.0, 3.0, 2.0, 2.0, 2.0, 4.0, 3.0]);
    reloadData();
  }

  @override
  void dispose() {
    _verticalController.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    _keyboardFocusNode.dispose();
    super.dispose();
  }

  Future<void> reloadData() async {
    setState(() => _isLoading = true);
    
    try {
      final data = await ApiService.getReturns();
      if (mounted) {
        setState(() {
          _originalData = List.from(data);
          _data = data;
          _isLoading = false;
          _selectedRowIndex = null;
          _applyFiltersAndSort();
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading data: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> searchByDate(DateTime? startDate, DateTime? endDate, {String? texto}) async {
    setState(() => _isLoading = true);
    
    try {
      final data = await ApiService.searchReturns(fechaInicio: startDate, fechaFin: endDate, texto: texto);
      if (mounted) {
        setState(() {
          _originalData = List.from(data);
          _data = data;
          _isLoading = false;
          _selectedRowIndex = null;
          _applyFiltersAndSort();
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error searching: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }
  
  // ==================== FILTROS Y ORDENAMIENTO ====================
  
  void _toggleSearchBar() {
    setState(() {
      _showSearchBar = !_showSearchBar;
      if (_showSearchBar) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _searchFocusNode.requestFocus();
        });
      } else {
        _searchText = '';
        _searchController.clear();
      }
    });
  }

  void _onSearchTextChanged(String text) {
    setState(() => _searchText = text);
  }

  void _applyFiltersAndSort() {
    List<Map<String, dynamic>> result = List.from(_originalData);
    
    // Aplicar filtros de columna
    _columnFilters.forEach((field, value) {
      if (value != null && value.isNotEmpty) {
        result = result.where((row) {
          final fieldValue = _getFieldValue(row, field);
          if (value == '__BLANKS__') {
            return fieldValue.isEmpty;
          } else if (value == '__NON_BLANKS__') {
            return fieldValue.isNotEmpty;
          }
          return fieldValue.toLowerCase() == value.toLowerCase();
        }).toList();
      }
    });
    
    // Aplicar ordenamiento
    if (_sortColumn != null) {
      result.sort((a, b) {
        final aVal = _getFieldValue(a, _sortColumn!);
        final bVal = _getFieldValue(b, _sortColumn!);
        
        // Para campos numéricos
        if (_sortColumn == 'cantidad_devuelta') {
          final aNum = int.tryParse(aVal) ?? 0;
          final bNum = int.tryParse(bVal) ?? 0;
          return _sortAscending ? aNum.compareTo(bNum) : bNum.compareTo(aNum);
        }
        
        return _sortAscending ? aVal.compareTo(bVal) : bVal.compareTo(aVal);
      });
    }
    
    _data = result;
  }

  String _getFieldValue(Map<String, dynamic> row, String field) {
    if (field == 'return_datetime' && row['return_datetime'] != null) {
      return _formatDateTime(row['return_datetime']);
    }
    return row[field]?.toString() ?? '';
  }

  void _sortByColumn(String field, bool ascending) {
    setState(() {
      _sortColumn = field;
      _sortAscending = ascending;
      _applyFiltersAndSort();
    });
  }

  void _clearSorting() {
    setState(() {
      _sortColumn = null;
      _sortAscending = true;
      _applyFiltersAndSort();
    });
  }

  void _applyFilter(String field, String? value) {
    setState(() {
      if (value == null || value.isEmpty) {
        _columnFilters.remove(field);
      } else {
        _columnFilters[field] = value;
      }
      _applyFiltersAndSort();
    });
  }

  void _showColumnContextMenu(BuildContext context, String field, int fieldIndex) {
    final RenderBox? renderBox = _filterKeys[field]?.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;
    final position = renderBox.localToGlobal(Offset.zero);
    final size = renderBox.size;
    
    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(position.dx, position.dy + size.height, position.dx + 150, position.dy + size.height + 200),
      items: [
        PopupMenuItem(value: 'sort_asc', child: Row(children: [const Icon(Icons.arrow_upward, size: 16), const SizedBox(width: 8), Text(tr('sort_ascending'))])),
        PopupMenuItem(value: 'sort_desc', child: Row(children: [const Icon(Icons.arrow_downward, size: 16), const SizedBox(width: 8), Text(tr('sort_descending'))])),
        PopupMenuItem(value: 'clear_sort', child: Row(children: [const Icon(Icons.clear, size: 16), const SizedBox(width: 8), Text(tr('clear_sorting'))])),
        const PopupMenuDivider(),
        PopupMenuItem(value: 'filter', child: Row(children: [const Icon(Icons.filter_list, size: 16), const SizedBox(width: 8), Text(tr('filter_by_column'))])),
        PopupMenuItem(value: 'clear_filter', child: Row(children: [const Icon(Icons.filter_list_off, size: 16), const SizedBox(width: 8), Text(tr('clear_filter'))])),
        const PopupMenuDivider(),
        PopupMenuItem(value: 'search', child: Row(children: [const Icon(Icons.search, size: 16), const SizedBox(width: 8), Text(tr('search'))])),
      ],
    ).then((value) {
      if (value == 'sort_asc') _sortByColumn(field, true);
      else if (value == 'sort_desc') _sortByColumn(field, false);
      else if (value == 'clear_sort') _clearSorting();
      else if (value == 'filter') _showFilterDropdown(context, field);
      else if (value == 'clear_filter') _applyFilter(field, null);
      else if (value == 'search') _toggleSearchBar();
    });
  }

  void _showFilterDropdown(BuildContext context, String field) {
    final RenderBox? renderBox = _filterKeys[field]?.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;
    final position = renderBox.localToGlobal(Offset.zero);
    final size = renderBox.size;
    
    final fieldIndex = _fields.indexOf(field);
    final header = fieldIndex >= 0 ? _headers[fieldIndex] : field;
    
    // Obtener valores únicos
    final Set<String> uniqueValues = {};
    bool hasBlanks = false;
    
    for (var row in _originalData) {
      final value = _getFieldValue(row, field);
      if (value.isEmpty) {
        hasBlanks = true;
      } else {
        uniqueValues.add(value);
      }
    }
    
    final sortedValues = uniqueValues.toList()..sort();
    
    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(position.dx, position.dy + size.height, position.dx + 250, position.dy + size.height + 300),
      items: [
        PopupMenuItem(
          enabled: false,
          child: Text('${tr('filter_by')}: $header', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(value: '', child: Text('(${tr('all')})', style: const TextStyle(fontStyle: FontStyle.italic))),
        if (hasBlanks) PopupMenuItem(value: '__BLANKS__', child: Text('(${tr('blanks')})')),
        PopupMenuItem(value: '__NON_BLANKS__', child: Text('(${tr('non_blanks')})')),
        const PopupMenuDivider(),
        ...sortedValues.take(50).map((val) => PopupMenuItem(value: val, child: Text(val, overflow: TextOverflow.ellipsis))),
        if (sortedValues.length > 50) const PopupMenuItem(enabled: false, child: Text('... and more', style: TextStyle(fontStyle: FontStyle.italic))),
      ],
    ).then((selectedValue) {
      if (selectedValue != null) {
        _applyFilter(field, selectedValue.isEmpty ? null : selectedValue);
      }
    });
  }

  Widget _highlightText(String text, String search) {
    if (search.isEmpty) {
      return Text(
        text,
        style: const TextStyle(fontSize: 11, color: Colors.white70),
        overflow: TextOverflow.ellipsis,
      );
    }
    
    final lowerText = text.toLowerCase();
    final lowerSearch = search.toLowerCase();
    
    if (!lowerText.contains(lowerSearch)) {
      return Text(
        text,
        style: const TextStyle(fontSize: 11, color: Colors.white70),
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
        style: const TextStyle(fontSize: 11, color: Colors.white70),
        children: spans,
      ),
      overflow: TextOverflow.ellipsis,
    );
  }

  Map<String, dynamic>? getSelectedRowData() {
    if (_selectedRowIndex == null || _selectedRowIndex! >= _data.length) {
      return null;
    }
    return _data[_selectedRowIndex!];
  }

  void clearSelection() {
    setState(() => _selectedRowIndex = null);
  }

  Future<void> exportToExcel() async {
    if (_data.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr('no_data_to_export')), backgroundColor: Colors.orange),
      );
      return;
    }

    try {
      final excel = excel_lib.Excel.createExcel();
      final sheet = excel['Material Returns'];
      
      // Headers
      final headers = [
        tr('return_datetime'),
        tr('material_warehousing_code'),
        tr('material_code'),
        tr('part_number'),
        tr('material_lot_no'),
        tr('packaging_unit'),
        tr('return_qty'),
        tr('material_spec'),
        tr('reason'),
      ];
      
      for (var i = 0; i < headers.length; i++) {
        sheet.cell(excel_lib.CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0)).value = 
            excel_lib.TextCellValue(headers[i]);
      }
      
      // Data rows
      for (var rowIndex = 0; rowIndex < _data.length; rowIndex++) {
        final row = _data[rowIndex];
        final dataRow = rowIndex + 1;
        
        sheet.cell(excel_lib.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: dataRow)).value = 
            excel_lib.TextCellValue(_formatDateTime(row['return_datetime']));
        sheet.cell(excel_lib.CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: dataRow)).value = 
            excel_lib.TextCellValue(row['material_warehousing_code']?.toString() ?? '');
        sheet.cell(excel_lib.CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: dataRow)).value = 
            excel_lib.TextCellValue(row['material_code']?.toString() ?? '');
        sheet.cell(excel_lib.CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: dataRow)).value = 
            excel_lib.TextCellValue(row['part_number']?.toString() ?? '');
        sheet.cell(excel_lib.CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: dataRow)).value = 
            excel_lib.TextCellValue(row['material_lot_no']?.toString() ?? '');
        sheet.cell(excel_lib.CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: dataRow)).value = 
            excel_lib.TextCellValue(row['packaging_unit']?.toString() ?? '');
        sheet.cell(excel_lib.CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: dataRow)).value = 
            excel_lib.IntCellValue(row['return_qty'] ?? 0);
        sheet.cell(excel_lib.CellIndex.indexByColumnRow(columnIndex: 7, rowIndex: dataRow)).value = 
            excel_lib.TextCellValue(row['material_spec']?.toString() ?? '');
        sheet.cell(excel_lib.CellIndex.indexByColumnRow(columnIndex: 8, rowIndex: dataRow)).value = 
            excel_lib.TextCellValue(row['remarks']?.toString() ?? '');
      }
      
      excel.delete('Sheet1');
      
      final fileName = 'Material_Returns_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.xlsx';
      
      final result = await FilePicker.platform.saveFile(
        dialogTitle: tr('save_excel_file'),
        fileName: fileName,
        type: FileType.custom,
        allowedExtensions: ['xlsx'],
      );
      
      if (result != null) {
        final fileBytes = excel.save();
        if (fileBytes != null) {
          final file = File(result);
          await file.writeAsBytes(fileBytes);
          
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('✓ ${tr('export_success')}'),
                backgroundColor: Colors.green,
              ),
            );
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${tr('export_error')}: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> reprintSelected() async {
    final selectedData = getSelectedRowData();
    if (selectedData == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr('select_row_first')), backgroundColor: Colors.orange),
      );
      return;
    }

    if (!PrinterService.hasPrinterConfigured) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr('configure_printer_first')), backgroundColor: Colors.orange),
      );
      return;
    }

    final success = await PrinterService.printLabel(
      codigo: selectedData['warehousing_code']?.toString() ?? '',
      fecha: _formatDateTime(selectedData['fecha_creacion']),
      especificacion: selectedData['material_spec']?.toString() ?? '',
      cantidadActual: selectedData['cantidad_devuelta']?.toString() ?? '',
    );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success ? '✓ ${tr('print_success')}' : '✗ ${tr('print_error')}'),
          backgroundColor: success ? Colors.green : Colors.red,
        ),
      );
    }
  }

  String _formatDateTime(dynamic dateTime) {
    if (dateTime == null) return '';
    try {
      final date = DateTime.parse(dateTime.toString());
      return DateFormat('dd/MM/yyyy HH:mm').format(date);
    } catch (_) {
      return dateTime.toString();
    }
  }

  @override
  Widget build(BuildContext context) {
    final headers = _headers;
    final fieldMapping = _fields;
    
    // Filtrar por búsqueda Ctrl+F
    final displayData = _searchText.isEmpty
        ? _data
        : _data.where((row) {
            return fieldMapping.any((field) {
              final value = _getFieldValue(row, field).toLowerCase();
              return value.contains(_searchText.toLowerCase());
            });
          }).toList();

    return Focus(
      focusNode: _keyboardFocusNode,
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent) {
          // Ctrl+F para buscar
          if (event.logicalKey == LogicalKeyboardKey.keyF && 
              HardwareKeyboard.instance.isControlPressed) {
            _toggleSearchBar();
            return KeyEventResult.handled;
          }
          // Escape para cerrar búsqueda
          if (event.logicalKey == LogicalKeyboardKey.escape && _showSearchBar) {
            _toggleSearchBar();
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: () => _keyboardFocusNode.requestFocus(),
        child: Container(
          color: AppColors.gridBackground,
          child: Column(
            children: [
              // Barra de búsqueda Ctrl+F
              if (_showSearchBar)
                Container(
                  height: 36,
                  color: AppColors.panelBackground,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    children: [
                      const Icon(Icons.search, color: Colors.white54, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _searchController,
                          focusNode: _searchFocusNode,
                          style: const TextStyle(color: Colors.white, fontSize: 13),
                          decoration: InputDecoration(
                            hintText: '${tr('search')}... (Ctrl+F)',
                            hintStyle: const TextStyle(color: Colors.white38, fontSize: 13),
                            border: InputBorder.none,
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(vertical: 8),
                          ),
                          onChanged: _onSearchTextChanged,
                          onSubmitted: (_) => _keyboardFocusNode.requestFocus(),
                        ),
                      ),
                      if (_searchText.isNotEmpty)
                        Text(
                          '${displayData.length} ${tr('results')}',
                          style: const TextStyle(color: Colors.white54, fontSize: 11),
                        ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        color: Colors.white54,
                        onPressed: _toggleSearchBar,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                      ),
                    ],
                  ),
                ),
              // Header Row con columnas redimensionables y menú contextual
              _buildHeaderRow(headers, fieldMapping),
              // Data rows
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator(color: Colors.white70))
                    : displayData.isEmpty
                        ? Center(
                            child: Text(tr('no_data'),
                                style: const TextStyle(color: Colors.white54, fontSize: 14)),
                          )
                        : SelectionArea(
                          child: ListView.builder(
                            controller: _verticalController,
                            itemCount: displayData.length,
                            itemBuilder: (context, index) {
                              final row = displayData[index];
                              final isSelected = _selectedRowIndex == index;
                              final isEven = index % 2 == 0;
                              
                              return InkWell(
                                onTap: () {
                                  setState(() {
                                    _selectedRowIndex = isSelected ? null : index;
                                  });
                                },
                                child: Container(
                                  height: 30,
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? AppColors.gridSelectedRow
                                        : isEven
                                            ? AppColors.gridRowEven
                                            : AppColors.gridRowOdd,
                                    border: const Border(
                                      bottom: BorderSide(color: AppColors.border, width: 0.5),
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      // Checkbox
                                      SizedBox(
                                        width: 30,
                                        child: Checkbox(
                                          value: isSelected,
                                          onChanged: (value) {
                                            setState(() {
                                              _selectedRowIndex = value == true ? index : null;
                                            });
                                          },
                                          side: const BorderSide(color: AppColors.border),
                                          activeColor: AppColors.headerTab,
                                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                        ),
                                      ),
                                      // Data cells con flex sincronizado
                                      ...List.generate(fieldMapping.length, (i) {
                                        final field = fieldMapping[i];
                                        String value = '';
                                        TextStyle baseStyle = const TextStyle(fontSize: 11, color: Colors.white70);
                                        
                                        if (field == 'return_datetime') {
                                          value = _formatDateTime(row[field]);
                                        } else if (field == 'return_qty') {
                                          value = row[field]?.toString() ?? '0';
                                          baseStyle = const TextStyle(fontSize: 11, color: Colors.orange, fontWeight: FontWeight.bold);
                                        } else if (field == 'material_warehousing_code') {
                                          value = row[field]?.toString() ?? '';
                                          baseStyle = const TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.w500);
                                        } else {
                                          value = row[field]?.toString() ?? '';
                                        }
                                        
                                        return Expanded(
                                          flex: getColumnFlex(i),
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 4),
                                            alignment: Alignment.centerLeft,
                                            child: _searchText.isNotEmpty
                                                ? _highlightText(value, _searchText)
                                                : Text(
                                                    value,
                                                    style: baseStyle,
                                                    overflow: TextOverflow.ellipsis,
                                                  ),
                                          ),
                                        );
                                      }),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
              ),
              // Footer con información de filtros
              Container(
                height: 28,
                color: AppColors.panelBackground,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Text('${tr('total_rows')}: ${displayData.length}${displayData.length != _originalData.length ? ' / ${_originalData.length}' : ''}',
                        style: const TextStyle(color: Colors.white70, fontSize: 11)),
                    const Spacer(),
                    if (_columnFilters.isNotEmpty || _sortColumn != null)
                      Row(
                        children: [
                          if (_columnFilters.isNotEmpty)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              margin: const EdgeInsets.only(right: 8),
                              decoration: BoxDecoration(
                                color: Colors.blue.withValues(alpha: 0.3),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.filter_list, size: 12, color: Colors.blue),
                                  const SizedBox(width: 4),
                                  Text('${_columnFilters.length} ${tr('filter_by_column').split(' ').first.toLowerCase()}',
                                      style: const TextStyle(color: Colors.blue, fontSize: 10)),
                                ],
                              ),
                            ),
                          if (_sortColumn != null)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.green.withValues(alpha: 0.3),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(_sortAscending ? Icons.arrow_upward : Icons.arrow_downward, size: 12, color: Colors.green),
                                  const SizedBox(width: 4),
                                  Text(_sortColumn!, style: const TextStyle(color: Colors.green, fontSize: 10)),
                                ],
                              ),
                            ),
                        ],
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
  
  Widget _buildHeaderRow(List<String> headers, List<String> fieldMapping) {
    return Container(
      height: 32,
      decoration: const BoxDecoration(
        color: AppColors.gridHeader,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          // Checkbox header
          const SizedBox(
            width: 30,
            child: Center(
              child: Icon(Icons.check_box_outline_blank, size: 16, color: Colors.white54),
            ),
          ),
          // Column headers con menú contextual
          ...List.generate(headers.length, (i) {
            final field = fieldMapping[i];
            final hasFilter = _columnFilters.containsKey(field);
            final isSorted = _sortColumn == field;
            
            return Expanded(
              flex: getColumnFlex(i),
              child: GestureDetector(
                key: _filterKeys[field],
                onTap: () => _sortByColumn(field, isSorted ? !_sortAscending : true),
                onSecondaryTap: () => _showColumnContextMenu(context, field, i),
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            headers[i],
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: hasFilter || isSorted ? Colors.yellow : Colors.white,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (isSorted)
                          Icon(
                            _sortAscending ? Icons.arrow_upward : Icons.arrow_downward,
                            size: 12,
                            color: Colors.blue,
                          ),
                        if (hasFilter)
                          GestureDetector(
                            onTap: () => _showColumnContextMenu(context, field, i),
                            child: const Padding(
                              padding: EdgeInsets.only(left: 2),
                              child: Icon(Icons.filter_list, size: 12, color: Colors.blue),
                            ),
                          ),
                        GestureDetector(
                          onTap: () => _showColumnContextMenu(context, field, i),
                          child: const Icon(Icons.arrow_drop_down, size: 14, color: Colors.white54),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}
