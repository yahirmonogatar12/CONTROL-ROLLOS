import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:excel/excel.dart' as xl;
import 'package:material_warehousing_flutter/core/localization/app_translations.dart';
import 'package:material_warehousing_flutter/core/theme/app_colors.dart';
import 'package:material_warehousing_flutter/core/services/api_service.dart';
import 'package:material_warehousing_flutter/core/widgets/grid_footer.dart';
import 'package:material_warehousing_flutter/core/widgets/resizable_grid_header.dart';

// ============================================
// IQC History Grid - Grid con filtros tipo GUIA_TABLAS_GRID
// ============================================
class IqcHistoryGrid extends StatefulWidget {
  final LanguageProvider languageProvider;
  
  const IqcHistoryGrid({
    super.key,
    required this.languageProvider,
  });

  @override
  State<IqcHistoryGrid> createState() => IqcHistoryGridState();
}

class IqcHistoryGridState extends State<IqcHistoryGrid> with ResizableColumnsMixin {
  List<Map<String, dynamic>> _data = [];
  List<Map<String, dynamic>> _filteredData = [];
  bool _isLoading = true;
  int _selectedIndex = -1;
  
  // Filtros por columna
  Map<String, String?> _columnFilters = {};
  String? _sortColumn;
  bool _sortAscending = true;
  
  // Filtros de fecha - Por defecto últimos 7 días
  DateTime _startDate = DateTime.now().subtract(const Duration(days: 7));
  DateTime _endDate = DateTime.now();
  
  // Búsqueda Ctrl+F
  bool _showSearchBar = false;
  String _searchText = '';
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final FocusNode _keyboardFocusNode = FocusNode();
  
  // GlobalKeys para filtros
  final Map<String, GlobalKey> _filterKeys = {};
  
  // Campos del historial - INCLUYE TODOS LOS DATOS DE VERIFICACIÓN
  final List<String> _fields = [
    'receiving_lot_code', 'lot_sequence', 'part_number', 'customer',
    'total_qty_received',
    'rohs_result', 'brightness_result', 'dimension_result', 'color_result', 'appearance_result',
    'disposition', 'inspector', 'closed_at'
  ];

  String tr(String key) => widget.languageProvider.tr(key);

  List<String> get _headers => [
    tr('receiving_lot'),
    tr('lot_sequence'),
    tr('part_number'),
    tr('customer'),
    tr('total_qty'),
    'RoHS',
    tr('brightness'),
    tr('dimension'),
    tr('color'),
    tr('appearance'),
    tr('disposition'),
    tr('inspector'),
    tr('closed_at'),
  ];

  @override
  void initState() {
    super.initState();
    for (var field in _fields) {
      _filterKeys[field] = GlobalKey();
    }
    initColumnFlex(13, 'iqc_history', defaultFlexValues: [3.0, 1.0, 2.0, 2.0, 2.0, 2.0, 2.0, 2.0, 2.0, 2.0, 2.0, 2.0, 2.0]);
    _loadData();
  }
  
  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    _keyboardFocusNode.dispose();
    super.dispose();
  }
  
  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    
    try {
      final startStr = '${_startDate.year}-${_startDate.month.toString().padLeft(2, '0')}-${_startDate.day.toString().padLeft(2, '0')}';
      final endStr = '${_endDate.year}-${_endDate.month.toString().padLeft(2, '0')}-${_endDate.day.toString().padLeft(2, '0')}';
      
      final data = await ApiService.getIqcHistory(
        fechaInicio: startStr,
        fechaFin: endStr,
      );
      
      setState(() {
        _data = data;
        _applyFiltersAndSort();
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }
  
  void reloadData() => _loadData();
  
  void _applyFiltersAndSort() {
    List<Map<String, dynamic>> result = List.from(_data);
    
    // Aplicar filtros por columna
    _columnFilters.forEach((field, filterValue) {
      if (filterValue != null && filterValue.isNotEmpty) {
        result = result.where((row) {
          final value = row[field]?.toString().toLowerCase() ?? '';
          if (filterValue == '__BLANKS__') {
            return value.isEmpty;
          } else if (filterValue == '__NON_BLANKS__') {
            return value.isNotEmpty;
          }
          return value == filterValue.toLowerCase();
        }).toList();
      }
    });
    
    // Aplicar búsqueda global
    if (_searchText.isNotEmpty) {
      result = result.where((row) {
        return _fields.any((field) {
          final value = row[field]?.toString().toLowerCase() ?? '';
          return value.contains(_searchText.toLowerCase());
        });
      }).toList();
    }
    
    // Aplicar ordenamiento
    if (_sortColumn != null) {
      result.sort((a, b) {
        var aValue = a[_sortColumn];
        var bValue = b[_sortColumn];
        
        if (aValue is num && bValue is num) {
          return _sortAscending ? aValue.compareTo(bValue) : bValue.compareTo(aValue);
        }
        
        String aStr = aValue?.toString() ?? '';
        String bStr = bValue?.toString() ?? '';
        
        return _sortAscending 
          ? aStr.toLowerCase().compareTo(bStr.toLowerCase())
          : bStr.toLowerCase().compareTo(aStr.toLowerCase());
      });
    }
    
    _filteredData = result;
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
  
  void _applyFilter(String field, String? filterValue) {
    setState(() {
      if (filterValue == null || filterValue.isEmpty) {
        _columnFilters.remove(field);
      } else {
        _columnFilters[field] = filterValue;
      }
      _applyFiltersAndSort();
    });
  }

  Future<void> _selectStartDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate,
      firstDate: DateTime(2024),
      lastDate: DateTime.now(),
      builder: (context, child) => Theme(
        data: ThemeData.dark().copyWith(colorScheme: const ColorScheme.dark(primary: Colors.cyan)),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() => _startDate = picked);
      _loadData();
    }
  }

  Future<void> _selectEndDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _endDate,
      firstDate: DateTime(2024),
      lastDate: DateTime.now(),
      builder: (context, child) => Theme(
        data: ThemeData.dark().copyWith(colorScheme: const ColorScheme.dark(primary: Colors.cyan)),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() => _endDate = picked);
      _loadData();
    }
  }

  // ============================================
  // EXPORTAR A EXCEL
  // ============================================
  Future<void> _exportToExcel() async {
    try {
      final excel = xl.Excel.createExcel();
      final sheet = excel['IQC History'];
      
      // Eliminar la hoja por defecto 'Sheet1'
      excel.delete('Sheet1');
      
      // Encabezados
      for (var i = 0; i < _headers.length; i++) {
        final cell = sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0));
        cell.value = xl.TextCellValue(_headers[i]);
        cell.cellStyle = xl.CellStyle(
          bold: true,
          backgroundColorHex: xl.ExcelColor.fromHexString('#1E90FF'),
          fontColorHex: xl.ExcelColor.fromHexString('#FFFFFF'),
          horizontalAlign: xl.HorizontalAlign.Center,
        );
      }
      
      // Datos
      for (var rowIndex = 0; rowIndex < _filteredData.length; rowIndex++) {
        final row = _filteredData[rowIndex];
        for (var colIndex = 0; colIndex < _fields.length; colIndex++) {
          final field = _fields[colIndex];
          var value = row[field]?.toString() ?? '';
          
          // Formatear fechas
          if (field == 'closed_at' && value.isNotEmpty) {
            try {
              final date = DateTime.parse(value);
              value = '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
            } catch (_) {}
          }
          
          // Convertir Pending a N/A para resultados
          final isResultField = field == 'rohs_result' || field == 'brightness_result' || 
              field == 'dimension_result' || field == 'color_result' || field == 'appearance_result';
          if (isResultField && value == 'Pending') {
            value = 'N/A';
          }
          
          final cell = sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: colIndex, rowIndex: rowIndex + 1));
          cell.value = xl.TextCellValue(value);
          
          // Colorear celdas según resultado
          if (isResultField) {
            if (value == 'OK' || value == 'Pass') {
              cell.cellStyle = xl.CellStyle(fontColorHex: xl.ExcelColor.fromHexString('#008000'));
            } else if (value == 'NG' || value == 'Fail') {
              cell.cellStyle = xl.CellStyle(fontColorHex: xl.ExcelColor.fromHexString('#FF0000'));
            }
          } else if (field == 'disposition') {
            if (value == 'Release') {
              cell.cellStyle = xl.CellStyle(fontColorHex: xl.ExcelColor.fromHexString('#008000'));
            } else if (value == 'Return' || value == 'Scrap') {
              cell.cellStyle = xl.CellStyle(fontColorHex: xl.ExcelColor.fromHexString('#FF0000'));
            }
          }
        }
      }
      
      // Guardar archivo en Documentos
      final documentsPath = Platform.environment['USERPROFILE'] ?? 'C:\\Users\\Public';
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final filePath = '$documentsPath\\Documents\\IQC_History_$timestamp.xlsx';
      
      final fileBytes = excel.encode();
      if (fileBytes != null) {
        final file = File(filePath);
        await file.writeAsBytes(fileBytes);
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.check_circle, color: Colors.white),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${tr('export_success')} (${_filteredData.length} ${tr('rows')})'),
                        Text(filePath, style: const TextStyle(fontSize: 10)),
                      ],
                    ),
                  ),
                ],
              ),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 5),
              action: SnackBarAction(
                label: tr('open'),
                textColor: Colors.white,
                onPressed: () async {
                  // Abrir la carpeta del archivo
                  await Process.run('explorer.exe', ['/select,', filePath]);
                },
              ),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Color _getDispositionColor(String? disposition) {
    switch (disposition) {
      case 'Release': return Colors.green;
      case 'Return': return Colors.orange;
      case 'Scrap': return Colors.red;
      case 'Hold': return Colors.amber;
      case 'Rework': return Colors.purple;
      default: return Colors.grey;
    }
  }

  Color _getResultColor(String? result) {
    switch (result) {
      case 'OK':
      case 'Pass': return Colors.green;
      case 'NG':
      case 'Fail': return Colors.red;
      case 'NA':
      case 'N/A': return Colors.grey;
      default: return Colors.amber;
    }
  }

  // ============================================
  // TABLA AQL - Cálculo de Sample Size
  // ============================================
  static const Map<int, Map<String, int>> _lotSizeToCodeLetter = {
    2: {'S-1': 0, 'S-2': 0, 'S-3': 0, 'S-4': 0, 'I': 0, 'II': 0, 'III': 1},
    8: {'S-1': 0, 'S-2': 0, 'S-3': 0, 'S-4': 0, 'I': 0, 'II': 1, 'III': 2},
    15: {'S-1': 0, 'S-2': 0, 'S-3': 0, 'S-4': 1, 'I': 0, 'II': 2, 'III': 3},
    25: {'S-1': 0, 'S-2': 0, 'S-3': 1, 'S-4': 2, 'I': 1, 'II': 3, 'III': 4},
    50: {'S-1': 0, 'S-2': 1, 'S-3': 2, 'S-4': 3, 'I': 2, 'II': 4, 'III': 5},
    90: {'S-1': 1, 'S-2': 1, 'S-3': 2, 'S-4': 3, 'I': 2, 'II': 5, 'III': 6},
    150: {'S-1': 1, 'S-2': 2, 'S-3': 3, 'S-4': 4, 'I': 3, 'II': 6, 'III': 7},
    280: {'S-1': 1, 'S-2': 2, 'S-3': 3, 'S-4': 5, 'I': 3, 'II': 7, 'III': 8},
    500: {'S-1': 1, 'S-2': 2, 'S-3': 4, 'S-4': 5, 'I': 4, 'II': 8, 'III': 9},
    1200: {'S-1': 2, 'S-2': 3, 'S-3': 4, 'S-4': 6, 'I': 5, 'II': 9, 'III': 10},
    3200: {'S-1': 2, 'S-2': 3, 'S-3': 5, 'S-4': 7, 'I': 6, 'II': 10, 'III': 11},
    10000: {'S-1': 2, 'S-2': 4, 'S-3': 6, 'S-4': 8, 'I': 7, 'II': 11, 'III': 12},
    35000: {'S-1': 3, 'S-2': 4, 'S-3': 6, 'S-4': 8, 'I': 7, 'II': 12, 'III': 13},
    150000: {'S-1': 3, 'S-2': 4, 'S-3': 7, 'S-4': 9, 'I': 8, 'II': 13, 'III': 14},
    500000: {'S-1': 3, 'S-2': 5, 'S-3': 7, 'S-4': 10, 'I': 9, 'II': 14, 'III': 15},
    999999999: {'S-1': 3, 'S-2': 5, 'S-3': 8, 'S-4': 10, 'I': 9, 'II': 15, 'III': 15},
  };

  static const List<int> _codeLetterToSampleSize = [
    2, 3, 5, 8, 13, 20, 32, 50, 80, 125, 200, 315, 500, 800, 1250, 2000
  ];

  int _calculateSampleSizeForLevel(int lotSize, String samplingLevel) {
    if (lotSize <= 0) return 2;
    
    String level = samplingLevel.toUpperCase().trim();
    if (level.contains('LEVEL')) {
      level = level.replaceAll('LEVEL', '').trim();
    }
    
    int? codeLetterIndex;
    for (final entry in _lotSizeToCodeLetter.entries) {
      if (lotSize <= entry.key) {
        codeLetterIndex = entry.value[level] ?? entry.value['II'];
        break;
      }
    }
    
    if (codeLetterIndex == null || codeLetterIndex >= _codeLetterToSampleSize.length) {
      return 2;
    }
    
    return _codeLetterToSampleSize[codeLetterIndex];
  }

  String _buildDimensionSpecString(Map<String, dynamic> config) {
    final parts = <String>[];
    final length = config['dimension_length'];
    final lengthTol = config['dimension_length_tol'];
    final width = config['dimension_width'];
    final widthTol = config['dimension_width_tol'];
    final height = config['dimension_height'];
    final heightTol = config['dimension_height_tol'];
    
    if (length != null) parts.add('L:$length${lengthTol != null ? "±$lengthTol" : ""}');
    if (width != null) parts.add('W:$width${widthTol != null ? "±$widthTol" : ""}');
    if (height != null) parts.add('H:$height${heightTol != null ? "±$heightTol" : ""}');
    return parts.join(' ');
  }

  // Mostrar diálogo para editar resultado Pending - Ahora con inspección completa AQL
  Future<void> _showEditResultDialog(Map<String, dynamic> row, String field, String fieldLabel) async {
    final currentValue = row[field]?.toString() ?? 'Pending';
    final inspectionId = row['id'];
    final partNumber = row['part_number']?.toString() ?? '';
    final totalQty = int.tryParse(row['total_qty_received']?.toString() ?? '0') ?? 0;
    
    // Cargar configuración IQC del material
    final config = await ApiService.getMaterialIqcConfig(partNumber);
    if (config == null) {
      await _showFallbackResultDialog(row, field, fieldLabel, currentValue);
      return;
    }
    
    String inspectionType;
    String samplingLevelKey;
    String aqlLevelKey;
    Color themeColor;
    IconData themeIcon;
    bool hasValueField = false;
    String? spec;
    double? target, lsl, usl;
    
    switch (field) {
      case 'rohs_result':
        await _showFallbackResultDialog(row, field, fieldLabel, currentValue);
        return;
      case 'brightness_result':
        inspectionType = 'brightness';
        samplingLevelKey = 'brightness_sampling_level';
        aqlLevelKey = 'brightness_aql_level';
        themeColor = Colors.amber;
        themeIcon = Icons.light_mode;
        hasValueField = true;
        target = double.tryParse(config['brightness_target']?.toString() ?? '');
        lsl = double.tryParse(config['brightness_lsl']?.toString() ?? '');
        usl = double.tryParse(config['brightness_usl']?.toString() ?? '');
        break;
      case 'dimension_result':
        inspectionType = 'dimension';
        samplingLevelKey = 'dimension_sampling_level';
        aqlLevelKey = 'dimension_aql_level';
        themeColor = Colors.blue;
        themeIcon = Icons.straighten;
        hasValueField = true;
        spec = _buildDimensionSpecString(config);
        break;
      case 'color_result':
        inspectionType = 'color';
        samplingLevelKey = 'color_sampling_level';
        aqlLevelKey = 'color_aql_level';
        themeColor = Colors.purple;
        themeIcon = Icons.palette;
        spec = config['color_spec']?.toString() ?? '';
        break;
      case 'appearance_result':
        inspectionType = 'appearance';
        samplingLevelKey = 'appearance_sampling_level';
        aqlLevelKey = 'appearance_aql_level';
        themeColor = Colors.cyan;
        themeIcon = Icons.visibility;
        spec = config['appearance_spec']?.toString() ?? '';
        break;
      default:
        await _showFallbackResultDialog(row, field, fieldLabel, currentValue);
        return;
    }
    
    final samplingLevel = config[samplingLevelKey]?.toString() ?? 'S-1';
    final aqlLevel = config[aqlLevelKey]?.toString() ?? '2.5';
    final sampleSize = _calculateSampleSizeForLevel(totalQty, samplingLevel);
    
    if (sampleSize == 0) {
      await _showFallbackResultDialog(row, field, fieldLabel, currentValue);
      return;
    }
    
    // Cargar mediciones existentes
    final existingData = await ApiService.getIqcMeasurements(inspectionId);
    final existingMeasurements = (existingData[inspectionType] as List?) ?? [];
    
    final measurements = List.generate(sampleSize, (i) {
      final existing = existingMeasurements.cast<Map<String, dynamic>>().firstWhere(
        (m) => m['sampleNum'] == (i + 1),
        orElse: () => {},
      );
      return {
        'sampleNum': i + 1,
        'result': existing['result'] ?? 'Pending',
        'value': existing['value'] ?? '',
      };
    });
    
    await _showFullInspectionModal(
      row: row,
      field: field,
      inspectionType: inspectionType,
      title: fieldLabel,
      color: themeColor,
      icon: themeIcon,
      sampleSize: sampleSize,
      samplingLevel: samplingLevel,
      aqlLevel: aqlLevel,
      measurements: measurements,
      hasValueField: hasValueField,
      spec: spec,
      target: target,
      lsl: lsl,
      usl: usl,
    );
  }

  /// Modal de inspección completa con todas las muestras AQL
  Future<void> _showFullInspectionModal({
    required Map<String, dynamic> row,
    required String field,
    required String inspectionType,
    required String title,
    required Color color,
    required IconData icon,
    required int sampleSize,
    required String samplingLevel,
    required String aqlLevel,
    required List<Map<String, dynamic>> measurements,
    required bool hasValueField,
    String? spec,
    double? target,
    double? lsl,
    double? usl,
  }) async {
    final inspectionId = row['id'];
    final localMeasurements = measurements.map((m) => Map<String, dynamic>.from(m)).toList();
    
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final completed = localMeasurements.where((m) => m['result'] != 'Pending').length;
          final hasFail = localMeasurements.any((m) => m['result'] == 'Fail');
          final allPass = localMeasurements.every((m) => m['result'] == 'Pass');
          final resultPreview = completed == 0 ? 'Pending' : (hasFail ? 'Fail' : (allPass ? 'Pass' : 'Pending'));
          
          return AlertDialog(
            backgroundColor: const Color(0xFF1E1E2E),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            title: Row(
              children: [
                Icon(icon, color: color, size: 24),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('$title (n=$sampleSize)', style: TextStyle(color: color, fontSize: 16, fontWeight: FontWeight.bold)),
                      Text('Lot: ${row['receiving_lot_code']}', style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 11)),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            margin: const EdgeInsets.only(top: 4, right: 8),
                            decoration: BoxDecoration(color: color.withOpacity(0.2), borderRadius: BorderRadius.circular(4)),
                            child: Text('$samplingLevel / AQL $aqlLevel', style: TextStyle(color: color, fontSize: 10)),
                          ),
                          if (spec != null && spec.isNotEmpty)
                            Expanded(child: Text('Spec: $spec', style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 10), overflow: TextOverflow.ellipsis)),
                          if (target != null)
                            Text('Target: $target (${lsl ?? "-"} ~ ${usl ?? "-"})', style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 10)),
                        ],
                      ),
                    ],
                  ),
                ),
                IconButton(icon: const Icon(Icons.close, color: Colors.white54), onPressed: () => Navigator.pop(ctx)),
              ],
            ),
            content: SizedBox(
              width: 550,
              height: 450,
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                    decoration: BoxDecoration(color: color.withOpacity(0.2), borderRadius: BorderRadius.circular(6)),
                    child: Row(
                      children: [
                        const SizedBox(width: 50, child: Text('#', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontSize: 12))),
                        if (hasValueField) const Expanded(child: Text('Value', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontSize: 12))),
                        const SizedBox(width: 160, child: Center(child: Text('Result', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontSize: 12)))),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: ListView.builder(
                      itemCount: sampleSize,
                      itemBuilder: (ctx, index) {
                        final sample = localMeasurements[index];
                        final isPass = sample['result'] == 'Pass';
                        final isFail = sample['result'] == 'Fail';
                        
                        return Container(
                          margin: const EdgeInsets.only(bottom: 6),
                          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
                          decoration: BoxDecoration(
                            color: isPass ? Colors.green.withOpacity(0.1) : isFail ? Colors.red.withOpacity(0.1) : Colors.white.withOpacity(0.05),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: isPass ? Colors.green.withOpacity(0.3) : isFail ? Colors.red.withOpacity(0.3) : Colors.white.withOpacity(0.1)),
                          ),
                          child: Row(
                            children: [
                              SizedBox(width: 50, child: Text('#${index + 1}', style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 12, fontWeight: FontWeight.w500))),
                              if (hasValueField) ...[
                                Expanded(
                                  child: SizedBox(
                                    height: 32,
                                    child: TextField(
                                      style: const TextStyle(color: Colors.white, fontSize: 12),
                                      decoration: InputDecoration(
                                        hintText: 'Enter value...',
                                        hintStyle: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 11),
                                        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                        isDense: true,
                                        filled: true,
                                        fillColor: Colors.white.withOpacity(0.05),
                                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: BorderSide.none),
                                      ),
                                      keyboardType: TextInputType.number,
                                      controller: TextEditingController(text: sample['value'] ?? ''),
                                      onChanged: (v) => localMeasurements[index]['value'] = v,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                              ],
                              SizedBox(
                                width: 160,
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    InkWell(
                                      onTap: () => setDialogState(() => localMeasurements[index]['result'] = 'Pass'),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                                        decoration: BoxDecoration(
                                          color: isPass ? Colors.green : Colors.green.withOpacity(0.1),
                                          borderRadius: BorderRadius.circular(4),
                                          border: Border.all(color: Colors.green, width: isPass ? 2 : 1),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            if (isPass) const Icon(Icons.check, color: Colors.white, size: 14),
                                            if (isPass) const SizedBox(width: 4),
                                            Text('Pass', style: TextStyle(color: isPass ? Colors.white : Colors.green, fontSize: 11, fontWeight: FontWeight.bold)),
                                          ],
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    InkWell(
                                      onTap: () => setDialogState(() => localMeasurements[index]['result'] = 'Fail'),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                                        decoration: BoxDecoration(
                                          color: isFail ? Colors.red : Colors.red.withOpacity(0.1),
                                          borderRadius: BorderRadius.circular(4),
                                          border: Border.all(color: Colors.red, width: isFail ? 2 : 1),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            if (isFail) const Icon(Icons.close, color: Colors.white, size: 14),
                                            if (isFail) const SizedBox(width: 4),
                                            Text('Fail', style: TextStyle(color: isFail ? Colors.white : Colors.red, fontSize: 11, fontWeight: FontWeight.bold)),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(6)),
                child: Row(
                  children: [
                    Text('Completed: $completed/$sampleSize', style: const TextStyle(color: Colors.white70, fontSize: 12)),
                    const SizedBox(width: 16),
                    Text('Result: $resultPreview', style: TextStyle(color: resultPreview == 'Pass' ? Colors.green : resultPreview == 'Fail' ? Colors.red : Colors.white70, fontWeight: FontWeight.bold, fontSize: 12)),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('cancel'), style: const TextStyle(color: Colors.white54))),
              ElevatedButton(
                onPressed: () async {
                  final allMeasurements = localMeasurements.map((m) => {'type': inspectionType, 'sampleNum': m['sampleNum'], 'result': m['result'], 'value': m['value']}).toList();
                  await ApiService.saveIqcMeasurements(inspectionId, allMeasurements);
                  await _updateResult(inspectionId, field, resultPreview);
                  if (mounted) Navigator.pop(ctx);
                },
                style: ElevatedButton.styleFrom(backgroundColor: color),
                child: Text(tr('save'), style: const TextStyle(color: Colors.white)),
              ),
            ],
          );
        },
      ),
    );
  }
  
  // Diálogo simple de fallback para RoHS o cuando no hay configuración
  Future<void> _showFallbackResultDialog(Map<String, dynamic> row, String field, String fieldLabel, String currentValue) async {
    String? selectedValue = currentValue;
    final isMeasurementField = field == 'brightness_result' || field == 'dimension_result';
    
    if (isMeasurementField) {
      await _showSimpleMeasurementDialog(row, field, fieldLabel, currentValue);
      return;
    }
    
    final result = await showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: AppColors.panelBackground,
          title: Text('${tr('edit')} $fieldLabel', style: const TextStyle(color: Colors.white, fontSize: 16)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Lot: ${row['receiving_lot_code']}', style: const TextStyle(color: Colors.white70, fontSize: 12)),
              const SizedBox(height: 16),
              ...['Pass', 'Fail', 'NA'].map((option) => RadioListTile<String>(
                title: Row(
                  children: [
                    Icon(option == 'Pass' ? Icons.check_circle : option == 'Fail' ? Icons.cancel : Icons.remove_circle_outline, color: option == 'Pass' ? Colors.green : option == 'Fail' ? Colors.red : Colors.grey, size: 20),
                    const SizedBox(width: 8),
                    Text(option == 'NA' ? 'N/A' : option, style: TextStyle(color: option == 'Pass' ? Colors.green : option == 'Fail' ? Colors.red : Colors.grey)),
                  ],
                ),
                value: option,
                groupValue: selectedValue,
                activeColor: Colors.blue,
                onChanged: (value) => setDialogState(() => selectedValue = value),
              )),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('cancel'), style: const TextStyle(color: Colors.grey))),
            ElevatedButton(onPressed: () => Navigator.pop(context, selectedValue), style: ElevatedButton.styleFrom(backgroundColor: Colors.blue), child: Text(tr('save'))),
          ],
        ),
      ),
    );
    
    if (result != null && result != currentValue) {
      await _updateResult(row['id'], field, result);
    }
  }
  
  // Diálogo simple para campos de medición (fallback)
  Future<void> _showSimpleMeasurementDialog(Map<String, dynamic> row, String field, String fieldLabel, String currentValue) async {
    final textController = TextEditingController();
    String selectedOption = 'measure';
    
    if (currentValue != 'Pending' && currentValue != 'Pass' && currentValue != 'Fail' && currentValue != 'NA' && currentValue != 'N/A') {
      textController.text = currentValue;
      selectedOption = 'measure';
    } else if (currentValue == 'Pass') {
      selectedOption = 'pass';
    } else if (currentValue == 'Fail') {
      selectedOption = 'fail';
    } else if (currentValue == 'NA' || currentValue == 'N/A') {
      selectedOption = 'na';
    }
    
    final result = await showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: AppColors.panelBackground,
          title: Text('${tr('edit')} $fieldLabel', style: const TextStyle(color: Colors.white, fontSize: 16)),
          content: SizedBox(
            width: 300,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Lot: ${row['receiving_lot_code']}', style: const TextStyle(color: Colors.white70, fontSize: 12)),
                const SizedBox(height: 16),
                RadioListTile<String>(
                  title: Row(children: [
                    const Icon(Icons.straighten, color: Colors.blue, size: 20),
                    const SizedBox(width: 8),
                    Text(field == 'brightness_result' ? 'Enter measurement (cd/m²)' : 'Enter measurement (mm)', style: const TextStyle(color: Colors.blue)),
                  ]),
                  value: 'measure',
                  groupValue: selectedOption,
                  activeColor: Colors.blue,
                  onChanged: (value) => setDialogState(() => selectedOption = value!),
                ),
                if (selectedOption == 'measure')
                  Padding(
                    padding: const EdgeInsets.only(left: 40, right: 16, bottom: 8),
                    child: TextField(
                      controller: textController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: field == 'brightness_result' ? 'e.g. 250.5' : 'e.g. 10.25',
                        hintStyle: const TextStyle(color: Colors.white38),
                        filled: true,
                        fillColor: AppColors.gridBackground,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: BorderSide(color: AppColors.border)),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: BorderSide(color: AppColors.border)),
                        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: const BorderSide(color: Colors.blue)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        suffixText: field == 'brightness_result' ? 'cd/m²' : 'mm',
                        suffixStyle: const TextStyle(color: Colors.white54),
                      ),
                      autofocus: true,
                    ),
                  ),
                const Divider(color: Colors.white24),
                RadioListTile<String>(
                  title: const Row(children: [Icon(Icons.check_circle, color: Colors.green, size: 20), SizedBox(width: 8), Text('Pass', style: TextStyle(color: Colors.green))]),
                  value: 'pass', groupValue: selectedOption, activeColor: Colors.green,
                  onChanged: (value) => setDialogState(() => selectedOption = value!),
                ),
                RadioListTile<String>(
                  title: const Row(children: [Icon(Icons.cancel, color: Colors.red, size: 20), SizedBox(width: 8), Text('Fail', style: TextStyle(color: Colors.red))]),
                  value: 'fail', groupValue: selectedOption, activeColor: Colors.red,
                  onChanged: (value) => setDialogState(() => selectedOption = value!),
                ),
                RadioListTile<String>(
                  title: const Row(children: [Icon(Icons.remove_circle_outline, color: Colors.grey, size: 20), SizedBox(width: 8), Text('N/A', style: TextStyle(color: Colors.grey))]),
                  value: 'na', groupValue: selectedOption, activeColor: Colors.grey,
                  onChanged: (value) => setDialogState(() => selectedOption = value!),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('cancel'), style: const TextStyle(color: Colors.grey))),
            ElevatedButton(
              onPressed: () {
                String finalValue;
                if (selectedOption == 'measure') {
                  finalValue = textController.text.trim();
                  if (finalValue.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter a measurement value'), backgroundColor: Colors.orange));
                    return;
                  }
                } else if (selectedOption == 'pass') {
                  finalValue = 'Pass';
                } else if (selectedOption == 'fail') {
                  finalValue = 'Fail';
                } else {
                  finalValue = 'NA';
                }
                Navigator.pop(context, finalValue);
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
              child: Text(tr('save')),
            ),
          ],
        ),
      ),
    );
    
    textController.dispose();
    
    if (result != null && result != currentValue) {
      await _updateResult(row['id'], field, result);
    }
  }
  
  // Actualizar resultado en el servidor
  Future<void> _updateResult(int id, String field, String value) async {
    try {
      await ApiService.updateIqcInspection(id, {field: value});
      await _loadData(); // Recargar datos
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(tr('updated_successfully')),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
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
        child: Container(
          color: AppColors.gridBackground,
          child: Column(
            children: [
              // Barra de filtros de fecha
              _buildDateFilterBar(),
              
              // Barra de búsqueda Ctrl+F
              if (_showSearchBar) _buildSearchBar(),
              
              // Header de columnas
              _buildColumnHeader(),
              
              // Datos
              Expanded(child: _buildDataRows()),
              
              // Footer
              GridFooter(text: '${tr('total_rows')} : ${_filteredData.length}'),
            ],
          ),
        ),
      ),
    );
  }
  
  Widget _buildDateFilterBar() {
    String formatDate(DateTime d) => '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
    
    return Container(
      height: 36,
      color: AppColors.panelBackground,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          const Icon(Icons.date_range, size: 16, color: Colors.white54),
          const SizedBox(width: 8),
          
          // Fecha inicio
          InkWell(
            onTap: _selectStartDate,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.gridBackground,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                children: [
                  Text(
                    formatDate(_startDate),
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.calendar_today, size: 12, color: Colors.white54),
                ],
              ),
            ),
          ),
          
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8),
            child: Text('~', style: TextStyle(color: Colors.white54)),
          ),
          
          // Fecha fin
          InkWell(
            onTap: _selectEndDate,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.gridBackground,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                children: [
                  Text(
                    formatDate(_endDate),
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.calendar_today, size: 12, color: Colors.white54),
                ],
              ),
            ),
          ),
          
          const SizedBox(width: 8),
          
          // Botón buscar
          ElevatedButton.icon(
            onPressed: _loadData,
            icon: const Icon(Icons.search, size: 14),
            label: Text(tr('search'), style: const TextStyle(fontSize: 11)),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.cyan,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              minimumSize: const Size(0, 28),
            ),
          ),
          
          const Spacer(),
          
          // Indicador de filtros activos
          if (_columnFilters.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.cyan.withOpacity(0.2),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                children: [
                  const Icon(Icons.filter_alt, size: 14, color: Colors.cyan),
                  const SizedBox(width: 4),
                  Text(
                    '${_columnFilters.length} ${tr('filters')}',
                    style: const TextStyle(color: Colors.cyan, fontSize: 11),
                  ),
                  const SizedBox(width: 4),
                  InkWell(
                    onTap: () {
                      setState(() {
                        _columnFilters.clear();
                        _applyFiltersAndSort();
                      });
                    },
                    child: const Icon(Icons.close, size: 14, color: Colors.cyan),
                  ),
                ],
              ),
            ),
          
          const SizedBox(width: 8),
          
          // Botón Exportar Excel
          ElevatedButton.icon(
            onPressed: _filteredData.isNotEmpty ? _exportToExcel : null,
            icon: const Icon(Icons.file_download, size: 14),
            label: const Text('Excel', style: TextStyle(fontSize: 11)),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
              disabledBackgroundColor: Colors.grey[700],
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              minimumSize: const Size(0, 28),
            ),
          ),
          
          const SizedBox(width: 8),
          
          // Refrescar
          IconButton(
            onPressed: _loadData,
            icon: const Icon(Icons.refresh, size: 18, color: Colors.white54),
            tooltip: tr('refresh'),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
          
          // Hint Ctrl+F
          Text(
            'Ctrl+F',
            style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 10),
          ),
        ],
      ),
    );
  }
  
  Widget _buildSearchBar() {
    return Container(
      height: 32,
      color: AppColors.panelBackground,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _searchController,
              focusNode: _searchFocusNode,
              onChanged: (value) {
                setState(() {
                  _searchText = value;
                  _applyFiltersAndSort();
                });
              },
              style: const TextStyle(fontSize: 12, color: Colors.white),
              decoration: InputDecoration(
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                hintText: tr('search_placeholder'),
                hintStyle: const TextStyle(color: Colors.white54, fontSize: 12),
                filled: true,
                fillColor: AppColors.fieldBackground,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(4),
                  borderSide: const BorderSide(color: AppColors.border),
                ),
                prefixIcon: const Icon(Icons.search, size: 16, color: Colors.white54),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 16, color: Colors.white70),
                        onPressed: () {
                          _searchController.clear();
                          setState(() {
                            _searchText = '';
                            _applyFiltersAndSort();
                          });
                        },
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      )
                    : null,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            _searchText.isNotEmpty 
              ? 'Highlighting: "$_searchText"'
              : 'Esc to close',
            style: const TextStyle(fontSize: 11, color: Colors.white54),
          ),
          const SizedBox(width: 8),
          SizedBox(
            height: 24,
            child: ElevatedButton(
              onPressed: _toggleSearchBar,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.grey[700],
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
              child: const Text('Close', style: TextStyle(fontSize: 10)),
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildColumnHeader() {
    return Container(
      height: 36,
      color: AppColors.gridHeader,
      child: Row(
        children: List.generate(_headers.length, (i) {
          final header = _headers[i];
          final field = _fields[i];
          final isSorted = _sortColumn == field;
          final hasFilter = _columnFilters.containsKey(field);
          
          return Expanded(
            flex: getColumnFlex(i),
            child: Stack(
              children: [
                GestureDetector(
                onSecondaryTapDown: (details) {
                  _showColumnContextMenu(context, details.globalPosition, field, header);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: const BoxDecoration(
                    border: Border(right: BorderSide(color: AppColors.border, width: 0.5)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          header,
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (isSorted)
                        Icon(
                          _sortAscending ? Icons.arrow_upward : Icons.arrow_downward,
                          size: 10,
                          color: Colors.cyan,
                        ),
                      GestureDetector(
                        key: _filterKeys[field],
                        onTap: () => _showFilterDropdown(context, field, header),
                        child: Padding(
                          padding: const EdgeInsets.only(left: 2),
                          child: Icon(
                            hasFilter ? Icons.filter_alt : Icons.filter_alt_outlined,
                            size: 12,
                            color: hasFilter ? Colors.cyan : Colors.white38,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
                Positioned(
                  right: 0,
                  top: 0,
                  bottom: 0,
                  child: buildResizeHandle(i),
                ),
              ],
            ),
          );
        }),
      ),
    );
  }
  
  Widget _buildDataRows() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: Colors.cyan));
    }
    
    if (_filteredData.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.history, size: 48, color: Colors.white.withOpacity(0.1)),
            const SizedBox(height: 8),
            Text(
              tr('no_history'),
              style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 12),
            ),
          ],
        ),
      );
    }
    
    return ListView.builder(
      itemCount: _filteredData.length,
      itemBuilder: (context, index) {
        final row = _filteredData[index];
        final isSelected = index == _selectedIndex;
        final isEven = index % 2 == 0;
        
        return GestureDetector(
          onTap: () => setState(() => _selectedIndex = isSelected ? -1 : index),
          onDoubleTap: () => _showMeasurementsDetails(row),
          child: Container(
            height: 28,
            decoration: BoxDecoration(
              color: isSelected
                ? AppColors.gridSelectedRow
                : isEven 
                  ? AppColors.gridBackground 
                  : AppColors.gridRowAlt,
              border: Border(
                bottom: const BorderSide(color: AppColors.border, width: 0.5),
                left: isSelected 
                  ? const BorderSide(color: Colors.cyan, width: 3) 
                  : BorderSide.none,
              ),
            ),
            child: Row(
              children: _fields.asMap().entries.map((entry) {
                final idx = entry.key;
                final field = entry.value;
                
                var value = row[field]?.toString() ?? '';
                
                // Formatear fechas
                if (field == 'closed_at' && value.isNotEmpty) {
                  try {
                    final date = DateTime.parse(value);
                    value = '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
                  } catch (_) {}
                }
                
                // Detectar si es campo de resultado y guardar valor original
                final isResultField = field == 'rohs_result' || field == 'brightness_result' || 
                           field == 'dimension_result' || field == 'color_result' || 
                           field == 'appearance_result';
                final originalValue = row[field]?.toString() ?? '';
                
                // Mostrar el valor apropiado:
                // - Pass/Fail/OK/NG → mostrar tal cual
                // - Pending → mostrar Pending (amarillo, pendiente de verificar)
                // - NA/vacío → mostrar N/A (gris, no aplica)
                var displayValue = originalValue;
                if (isResultField) {
                  if (originalValue.isEmpty || originalValue == 'NA') {
                    displayValue = 'N/A';  // Solo vacío o NA se convierte a N/A
                  }
                  // Pending, Pass, Fail, OK, NG - mantener el valor original
                }
                
                // Widget especial para disposition y resultados
                Widget cellContent;
                if (field == 'disposition') {
                  cellContent = Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: _getDispositionColor(value).withOpacity(0.2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      value,
                      style: TextStyle(
                        fontSize: 10,
                        color: _getDispositionColor(value),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  );
                } else if (isResultField) {
                  // Detectar si es un valor numérico (medida)
                  final isMeasurementField = field == 'brightness_result' || field == 'dimension_result';
                  final isNumericValue = isMeasurementField && 
                      displayValue != 'Pending' && 
                      displayValue != 'Pass' && 
                      displayValue != 'Fail' && 
                      displayValue != 'NA' && 
                      displayValue != 'N/A' &&
                      double.tryParse(displayValue) != null;
                  
                  // Mostrar icono + texto para todos los resultados de verificación
                  final isPending = displayValue == 'Pending';
                  
                  IconData iconData;
                  Color iconColor;
                  
                  if (isNumericValue) {
                    iconData = Icons.straighten;
                    iconColor = Colors.cyan;
                  } else if (displayValue == 'OK' || displayValue == 'Pass') {
                    iconData = Icons.check_circle;
                    iconColor = Colors.green;
                  } else if (displayValue == 'NG' || displayValue == 'Fail') {
                    iconData = Icons.cancel;
                    iconColor = Colors.red;
                  } else if (isPending) {
                    iconData = Icons.pending;
                    iconColor = Colors.amber;
                  } else {
                    iconData = Icons.remove_circle_outline;
                    iconColor = Colors.grey;
                  }
                  
                  final resultWidget = Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(iconData, size: 12, color: iconColor),
                      const SizedBox(width: 2),
                      Flexible(
                        child: Text(
                          isNumericValue 
                              ? '$displayValue ${field == 'brightness_result' ? 'cd/m²' : 'mm'}'
                              : displayValue,
                          style: TextStyle(
                            fontSize: 10, 
                            color: isNumericValue ? Colors.cyan : (isPending ? Colors.amber : _getResultColor(displayValue)),
                            decoration: isPending ? TextDecoration.underline : null,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (isPending) ...[
                        const SizedBox(width: 2),
                        Icon(Icons.edit, size: 10, color: Colors.amber.withOpacity(0.7)),
                      ],
                    ],
                  );
                  
                  // Si es Pending, hacer clickeable para editar
                  if (isPending) {
                    // Obtener el label del campo para el diálogo
                    final fieldLabel = field == 'rohs_result' ? 'RoHS' :
                                       field == 'brightness_result' ? tr('brightness') :
                                       field == 'dimension_result' ? tr('dimension') :
                                       field == 'color_result' ? tr('color') :
                                       field == 'appearance_result' ? tr('appearance') : field;
                    cellContent = MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: GestureDetector(
                        onTap: () => _showEditResultDialog(row, field, fieldLabel),
                        child: resultWidget,
                      ),
                    );
                  } else {
                    cellContent = resultWidget;
                  }
                } else {
                  cellContent = _highlightText(value, _searchText);
                }
                
                return Expanded(
                  flex: getColumnFlex(idx),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    alignment: Alignment.centerLeft,
                    decoration: const BoxDecoration(
                      border: Border(right: BorderSide(color: AppColors.border, width: 0.5)),
                    ),
                    child: cellContent,
                  ),
                );
              }).toList(),
            ),
          ),
        );
      },
    );
  }
  
  Widget _highlightText(String text, String search) {
    if (search.isEmpty) {
      return Text(
        text,
        style: const TextStyle(fontSize: 11, color: Colors.white),
        overflow: TextOverflow.ellipsis,
      );
    }
    
    final lowerText = text.toLowerCase();
    final lowerSearch = search.toLowerCase();
    
    if (!lowerText.contains(lowerSearch)) {
      return Text(
        text,
        style: const TextStyle(fontSize: 11, color: Colors.white),
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
        style: const TextStyle(backgroundColor: Colors.yellow, color: Colors.black, fontWeight: FontWeight.bold),
      ));
      start = index + search.length;
    }
    
    if (start < text.length) {
      spans.add(TextSpan(text: text.substring(start)));
    }
    
    return RichText(
      text: TextSpan(
        style: const TextStyle(fontSize: 11, color: Colors.white),
        children: spans,
      ),
      overflow: TextOverflow.ellipsis,
    );
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
                color: _sortColumn == field && _sortAscending ? Colors.cyan : Colors.white70),
              const SizedBox(width: 8),
              Text('Sort Ascending', 
                style: TextStyle(fontSize: 12, 
                  color: _sortColumn == field && _sortAscending ? Colors.cyan : Colors.white)),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'sort_desc',
          height: 32,
          child: Row(
            children: [
              Icon(Icons.arrow_downward, size: 16,
                color: _sortColumn == field && !_sortAscending ? Colors.cyan : Colors.white70),
              const SizedBox(width: 8),
              Text('Sort Descending',
                style: TextStyle(fontSize: 12,
                  color: _sortColumn == field && !_sortAscending ? Colors.cyan : Colors.white)),
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
          child: Row(
            children: [
              Icon(Icons.filter_list, size: 16, 
                color: _columnFilters.containsKey(field) ? Colors.cyan : Colors.white70),
              const SizedBox(width: 8),
              const Text('Filter Editor...', style: TextStyle(fontSize: 12, color: Colors.white)),
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
    final RenderBox? renderBox = _filterKeys[field]?.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;
    
    final position = renderBox.localToGlobal(Offset.zero);
    final size = renderBox.size;
    
    // Obtener valores únicos
    final Set<String> uniqueValues = {};
    bool hasBlanks = false;
    
    for (var row in _data) {
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
        color: isSelected ? Colors.cyan.withOpacity(0.3) : null,
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
                  color: isSelected ? Colors.cyan : Colors.white,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (isSelected)
              const Icon(Icons.check, size: 14, color: Colors.cyan),
          ],
        ),
      ),
    );
  }
  
  /// Muestra el modal con los detalles de las mediciones de una inspección
  Future<void> _showMeasurementsDetails(Map<String, dynamic> row) async {
    final inspectionId = row['id'];
    if (inspectionId == null) return;
    
    // Cargar las mediciones
    final data = await ApiService.getIqcMeasurements(inspectionId);
    
    if (!mounted) return;
    
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Row(
          children: [
            const Icon(Icons.fact_check, color: Colors.cyan, size: 24),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(tr('inspection_details'), style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                  Text(row['receiving_lot_code']?.toString() ?? '', style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 11)),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close, color: Colors.white54),
              onPressed: () => Navigator.pop(ctx),
            ),
          ],
        ),
        content: SizedBox(
          width: 600,
          height: 400,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Brightness
                if (data['brightness'] != null && (data['brightness'] as List).isNotEmpty)
                  _buildMeasurementSection(
                    tr('brightness'),
                    Colors.amber,
                    Icons.light_mode,
                    data['brightness'] as List,
                    hasValue: true,
                  ),
                
                // Dimension
                if (data['dimension'] != null && (data['dimension'] as List).isNotEmpty)
                  _buildMeasurementSection(
                    tr('dimension'),
                    Colors.blue,
                    Icons.straighten,
                    data['dimension'] as List,
                    hasValue: true,
                  ),
                
                // Color
                if (data['color'] != null && (data['color'] as List).isNotEmpty)
                  _buildMeasurementSection(
                    tr('color'),
                    Colors.purple,
                    Icons.palette,
                    data['color'] as List,
                  ),
                
                // Appearance
                if (data['appearance'] != null && (data['appearance'] as List).isNotEmpty)
                  _buildMeasurementSection(
                    tr('appearance'),
                    Colors.cyan,
                    Icons.visibility,
                    data['appearance'] as List,
                  ),
                
                // Si no hay datos
                if ((data['brightness'] == null || (data['brightness'] as List).isEmpty) &&
                    (data['dimension'] == null || (data['dimension'] as List).isEmpty) &&
                    (data['color'] == null || (data['color'] as List).isEmpty) &&
                    (data['appearance'] == null || (data['appearance'] as List).isEmpty))
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.all(40),
                      child: Column(
                        children: [
                          Icon(Icons.info_outline, size: 48, color: Colors.white.withOpacity(0.2)),
                          const SizedBox(height: 16),
                          Text(
                            'No hay mediciones detalladas registradas',
                            style: TextStyle(color: Colors.white.withOpacity(0.5)),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cerrar', style: TextStyle(color: Colors.cyan)),
          ),
        ],
      ),
    );
  }
  
  Widget _buildMeasurementSection(String title, Color color, IconData icon, List measurements, {bool hasValue = false}) {
    final passCount = measurements.where((m) => m['result'] == 'Pass').length;
    final failCount = measurements.where((m) => m['result'] == 'Fail').length;
    final total = measurements.length;
    
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withOpacity(0.2),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(7),
                topRight: Radius.circular(7),
              ),
            ),
            child: Row(
              children: [
                Icon(icon, color: color, size: 18),
                const SizedBox(width: 8),
                Text(title, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 13)),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text('Pass: $passCount', style: const TextStyle(color: Colors.green, fontSize: 10, fontWeight: FontWeight.bold)),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text('Fail: $failCount', style: const TextStyle(color: Colors.red, fontSize: 10, fontWeight: FontWeight.bold)),
                ),
                const SizedBox(width: 8),
                Text('Total: $total', style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 10)),
              ],
            ),
          ),
          // Measurements grid
          Padding(
            padding: const EdgeInsets.all(12),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: measurements.map<Widget>((m) {
                final isPass = m['result'] == 'Pass';
                final isFail = m['result'] == 'Fail';
                final value = m['value']?.toString() ?? '';
                
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: isPass 
                        ? Colors.green.withOpacity(0.2)
                        : isFail 
                            ? Colors.red.withOpacity(0.2)
                            : Colors.grey.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: isPass ? Colors.green : isFail ? Colors.red : Colors.grey,
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '#${m['sampleNum']}',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.8),
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (hasValue && value.isNotEmpty) ...[
                        const SizedBox(width: 6),
                        Text(
                          value,
                          style: const TextStyle(color: Colors.white, fontSize: 10),
                        ),
                      ],
                      const SizedBox(width: 6),
                      Icon(
                        isPass ? Icons.check_circle : isFail ? Icons.cancel : Icons.pending,
                        size: 14,
                        color: isPass ? Colors.green : isFail ? Colors.red : Colors.grey,
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}
