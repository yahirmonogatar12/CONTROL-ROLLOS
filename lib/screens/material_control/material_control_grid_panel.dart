import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:excel/excel.dart' as xl;
import 'package:file_picker/file_picker.dart';
import 'package:material_warehousing_flutter/core/localization/app_translations.dart';
import 'package:material_warehousing_flutter/core/theme/app_colors.dart';
import 'package:material_warehousing_flutter/core/services/api_service.dart';
import 'package:material_warehousing_flutter/core/services/auth_service.dart';
import 'package:material_warehousing_flutter/core/widgets/grid_footer.dart';
import 'package:material_warehousing_flutter/core/widgets/resizable_grid_header.dart';

// ============================================
// Material Control Grid Panel
// ============================================
class MaterialControlGridPanel extends StatefulWidget {
  final LanguageProvider languageProvider;
  final Function(Map<String, dynamic>?)? onMaterialSelected;
  final VoidCallback? onCreateNew;
  
  const MaterialControlGridPanel({
    super.key,
    required this.languageProvider,
    this.onMaterialSelected,
    this.onCreateNew,
  });

  @override
  State<MaterialControlGridPanel> createState() => MaterialControlGridPanelState();
}

class MaterialControlGridPanelState extends State<MaterialControlGridPanel> with ResizableColumnsMixin {
  List<Map<String, dynamic>> _data = [];
  List<Map<String, dynamic>> _filteredData = [];
  bool _isLoading = true;
  int _selectedIndex = -1;
  
  // Filtros por columna
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
  
  // Campos de la tabla materiales (sin cantidad y sin reparable)
  final List<String> _fields = [
    'numero_parte',
    'codigo_material',
    'comparacion',
    'ubicacion_rollos',
    'propiedad_material',
    'clasificacion',
    'especificacion_material',
    'unidad_empaque',
    'unidad_medida',
    'vendedor',
    'prohibido_sacar',
    'nivel_msl',
    'espesor_msl',
    'fecha_registro',
    'usuario_registro',
    'version',
  ];

  String tr(String key) => widget.languageProvider.tr(key);

  List<String> get _headers => [
    tr('part_number'),
    tr('material_code'),
    tr('comparison'),
    tr('location_rollos'),
    tr('material_property'),
    tr('classification'),
    tr('material_spec'),
    tr('packaging_unit'),
    tr('unit'),
    tr('vendor'),
    tr('prohibited_exit'),
    tr('msl_level'),
    tr('msl_thickness'),
    tr('registration_date'),
    tr('registered_by'),
    tr('version'),
  ];

  // Permisos de edición
  bool get _canEdit {
    final dept = AuthService.currentUser?.departamento ?? '';
    final hasPermission = AuthService.hasPermission('write_material_control');
    return dept == 'Almacén Supervisor' || dept == 'Sistemas' || hasPermission;
  }
  
  // Permiso para editar solo comparaciones
  bool get _canEditComparacion {
    return AuthService.hasPermission('write_comparacion');
  }
  
  // Puede crear (completo o simplificado)
  bool get _canCreate => _canEdit || _canEditComparacion;
  
  // Permiso para eliminar materiales
  bool get _canDelete {
    final dept = AuthService.currentUser?.departamento ?? '';
    final hasPermission = AuthService.hasPermission('delete_material_control');
    return dept == 'Almacén Supervisor' || dept == 'Sistemas' || hasPermission;
  }

  @override
  void initState() {
    super.initState();
    for (var field in _fields) {
      _filterKeys[field] = GlobalKey();
    }
    initColumnFlex(16, 'material_control', defaultFlexValues: List.generate(16, (i) => (i == 0 || i == 1 || i == 2 || i == 3) ? 2.0 : 1.0));
    loadData();
  }
  
  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    _keyboardFocusNode.dispose();
    super.dispose();
  }
  
  Future<void> loadData() async {
    setState(() => _isLoading = true);
    
    try {
      final data = await ApiService.getMateriales();
      print('=== Material Control Grid ===');
      print('Total registros recibidos: ${data.length}');
      if (data.isNotEmpty) {
        print('Primer registro keys: ${data[0].keys.toList()}');
        print('Primer registro values sample:');
        print('  numero_parte: ${data[0]['numero_parte']}');
        print('  codigo_material: ${data[0]['codigo_material']}');
        print('  propiedad_material: ${data[0]['propiedad_material']}');
        print('  especificacion_material: ${data[0]['especificacion_material']}');
      }
      print('\n=== Column Flex Values ===');
      for (var i = 0; i < _fields.length; i++) {
        print('Column $i (${_fields[i]}): flex=${getColumnFlex(i)}');
      }
      setState(() {
        _data = data;
        _applyFilters();
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading data: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }
  
  void _applyFilters() {
    var result = List<Map<String, dynamic>>.from(_data);
    
    // Aplicar filtros de columna
    _columnFilters.forEach((field, filterValue) {
      if (filterValue != null && filterValue.isNotEmpty) {
        result = result.where((row) {
          final value = row[field]?.toString().toLowerCase() ?? '';
          return value.contains(filterValue.toLowerCase());
        }).toList();
      }
    });
    
    // Aplicar búsqueda global
    if (_searchText.isNotEmpty) {
      result = result.where((row) {
        return row.values.any((value) => 
          value?.toString().toLowerCase().contains(_searchText.toLowerCase()) ?? false
        );
      }).toList();
    }
    
    // Aplicar ordenamiento
    if (_sortColumn != null) {
      result.sort((a, b) {
        var aVal = a[_sortColumn]?.toString() ?? '';
        var bVal = b[_sortColumn]?.toString() ?? '';
        return _sortAscending ? aVal.compareTo(bVal) : bVal.compareTo(aVal);
      });
    }
    
    _filteredData = result;
    _selectedIndex = -1;
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
        _searchController.clear();
        _applyFilters();
      }
    });
  }
  
  void _onSearch(String value) {
    setState(() {
      _searchText = value;
      _applyFilters();
    });
  }
  
  void _showFilterMenu(String field, GlobalKey key) {
    final RenderBox? renderBox = key.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;
    
    final position = renderBox.localToGlobal(Offset.zero);
    final size = renderBox.size;
    
    // Obtener valores únicos para el filtro
    final uniqueValues = _data
        .map((row) => row[field]?.toString() ?? '')
        .where((v) => v.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    
    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy + size.height,
        position.dx + size.width,
        position.dy + size.height + 200,
      ),
      items: [
        PopupMenuItem<String>(
          value: '',
          child: Row(
            children: [
              const Icon(Icons.clear, size: 16, color: Colors.grey),
              const SizedBox(width: 8),
              Text(tr('clear_filter'), style: const TextStyle(color: Colors.grey)),
            ],
          ),
        ),
        ...uniqueValues.take(20).map((value) => PopupMenuItem<String>(
          value: value,
          child: Text(
            value.length > 30 ? '${value.substring(0, 30)}...' : value,
            style: const TextStyle(fontSize: 12),
          ),
        )),
      ],
    ).then((value) {
      if (value != null) {
        setState(() {
          if (value.isEmpty) {
            _columnFilters.remove(field);
          } else {
            _columnFilters[field] = value;
          }
          _applyFilters();
        });
      }
    });
  }
  
  void _sort(String field) {
    setState(() {
      if (_sortColumn == field) {
        _sortAscending = !_sortAscending;
      } else {
        _sortColumn = field;
        _sortAscending = true;
      }
      _applyFilters();
    });
  }
  
  Future<void> _exportToExcel() async {
    try {
      final excel = xl.Excel.createExcel();
      final sheet = excel['Materials'];
      
      // Headers
      for (var i = 0; i < _headers.length; i++) {
        sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0)).value = 
          xl.TextCellValue(_headers[i]);
      }
      
      // Data
      for (var rowIdx = 0; rowIdx < _filteredData.length; rowIdx++) {
        final row = _filteredData[rowIdx];
        for (var colIdx = 0; colIdx < _fields.length; colIdx++) {
          var value = row[_fields[colIdx]]?.toString() ?? '';
          if (_fields[colIdx] == 'assign_internal_lot') {
            value = value == '1' ? 'Yes' : 'No';
          }
          sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: colIdx, rowIndex: rowIdx + 1)).value = 
            xl.TextCellValue(value);
        }
      }
      
      // Guardar archivo
      final bytes = excel.encode();
      if (bytes != null) {
        final timestamp = DateTime.now().toString().replaceAll(':', '-').split('.')[0];
        final fileName = 'Materials_$timestamp.xlsx';
        final downloadsDir = Directory('${Platform.environment['USERPROFILE']}\\Downloads');
        final file = File('${downloadsDir.path}\\$fileName');
        await file.writeAsBytes(bytes);
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${tr('exported_to')}: $fileName'),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }
  
  // Importar comparaciones desde archivo Excel/CSV
  Future<void> _importComparisons() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'xls', 'csv'],
        dialogTitle: tr('select_file'),
      );
      
      if (result == null || result.files.isEmpty) return;
      
      final file = File(result.files.single.path!);
      final bytes = await file.readAsBytes();
      
      List<Map<String, dynamic>> items = [];
      
      if (result.files.single.extension?.toLowerCase() == 'csv') {
        // Procesar CSV
        final content = String.fromCharCodes(bytes);
        final lines = content.split('\n');
        
        for (var i = 0; i < lines.length; i++) { // No saltar header, puede no haber
          final line = lines[i].trim();
          if (line.isEmpty) continue;

          final parts = line.split(',');
          if (parts.length >= 2) {
            final np = parts[0].trim().toLowerCase();
            // Ignorar si parece ser header
            if (np == 'numero_parte' || np == 'nparte' || np == 'part_number' || np == 'n parte' || np == 'no. parte') continue;
            // Unir todo desde parts[2] en adelante para permitir comas dentro de ubicacion_rollos
            final ubicacionRollos = parts.length > 2 ? parts.sublist(2).join(',').trim() : '';
            items.add({
              'numero_parte': parts[0].trim(),
              'comparacion': parts[1].trim(),
              'ubicacion_rollos': ubicacionRollos,
            });
          }
        }
      } else {
        // Procesar Excel
        final excel = xl.Excel.decodeBytes(bytes);
        final sheet = excel.tables.values.first;
        
        for (var i = 0; i < sheet.maxRows; i++) {
          final row = sheet.row(i);
          if (row.isEmpty) continue;
          
          final numeroParte = row[0]?.value?.toString().trim() ?? '';
          final npLower = numeroParte.toLowerCase();
          // Ignorar si parece ser header
          if (npLower == 'numero_parte' || npLower == 'nparte' || npLower == 'part_number' || npLower == 'n parte' || npLower == 'no. parte') continue;
          
          final comparacion = row.length > 1 ? (row[1]?.value?.toString().trim() ?? '') : '';
          final ubicacionRollos = row.length > 2 ? (row[2]?.value?.toString().trim() ?? '') : '';
          
          if (numeroParte.isNotEmpty) {
            items.add({
              'numero_parte': numeroParte,
              'comparacion': comparacion,
              'ubicacion_rollos': ubicacionRollos,
            });
          }
        }
      }
      
      if (items.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(tr('no_data_found')),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }
      
      // Validar cuáles números de parte existen en el sistema
      setState(() => _isLoading = true);
      
      final partNumbers = items.map((i) => i['numero_parte'] as String).toList();
      final validation = await ApiService.validatePartNumbers(partNumbers);
      
      setState(() => _isLoading = false);
      
      if (validation['success'] != true) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(validation['error'] ?? 'Error'), backgroundColor: Colors.red),
          );
        }
        return;
      }
      
      // Crear mapa de existencia
      final results = validation['results'] as List;
      final existsMap = <String, bool>{};
      for (var r in results) {
        existsMap[r['numero_parte']] = r['exists'] == true;
      }
      
      // Separar items que existen y no existen
      final itemsToUpdate = items.where((i) => existsMap[i['numero_parte']] == true).toList();
      final itemsNotInSystem = items.where((i) => existsMap[i['numero_parte']] != true).toList();
      
      // Mostrar diálogo de vista previa
      final confirmed = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context) => _ImportPreviewDialog(
          tr: tr,
          itemsToUpdate: itemsToUpdate,
          itemsNotInSystem: itemsNotInSystem,
        ),
      );
      
      if (confirmed != true || itemsToUpdate.isEmpty) return;
      
      // Enviar solo los que existen al servidor
      setState(() => _isLoading = true);
      
      final response = await ApiService.bulkUpdateComparacion(itemsToUpdate);
      
      setState(() => _isLoading = false);
      
      if (mounted) {
        if (response['success'] == true) {
          final updated = response['updated'] ?? 0;
          
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${tr('updated')}: $updated'),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 5),
            ),
          );
          
          // Recargar datos
          await loadData();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(response['error'] ?? 'Error'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }
  
  // Importar ubicación rollos desde archivo Excel/CSV
  Future<void> _importRollos() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'xls', 'csv'],
        dialogTitle: tr('select_file'),
      );
      
      if (result == null || result.files.isEmpty) return;
      
      final file = File(result.files.single.path!);
      final bytes = await file.readAsBytes();
      
      List<Map<String, dynamic>> items = [];
      
      if (result.files.single.extension?.toLowerCase() == 'csv') {
        // Procesar CSV
        final content = String.fromCharCodes(bytes);
        final lines = content.split('\n');
        
        for (var i = 0; i < lines.length; i++) {
          final line = lines[i].trim();
          if (line.isEmpty) continue;

          // Separar solo por la primera coma para permitir comas dentro de ubicacion_rollos
          final firstComma = line.indexOf(',');
          if (firstComma > 0) {
            final np = line.substring(0, firstComma).trim();
            final npLower = np.toLowerCase();
            // Ignorar si parece ser header
            if (npLower == 'numero_parte' || npLower == 'nparte' || npLower == 'part_number' || npLower == 'n parte' || npLower == 'no. parte') continue;
            items.add({
              'numero_parte': np,
              'ubicacion_rollos': line.substring(firstComma + 1).trim(),
            });
          }
        }
      } else {
        // Procesar Excel
        final excel = xl.Excel.decodeBytes(bytes);
        final sheet = excel.tables.values.first;
        
        for (var i = 0; i < sheet.maxRows; i++) {
          final row = sheet.row(i);
          if (row.isEmpty) continue;
          
          final numeroParte = row[0]?.value?.toString().trim() ?? '';
          final npLower = numeroParte.toLowerCase();
          // Ignorar si parece ser header
          if (npLower == 'numero_parte' || npLower == 'nparte' || npLower == 'part_number' || npLower == 'n parte' || npLower == 'no. parte') continue;
          
          // Tomar todas las columnas desde B en adelante y unirlas con coma
          final ubicaciones = <String>[];
          for (var c = 1; c < row.length; c++) {
            final val = row[c]?.value?.toString().trim() ?? '';
            if (val.isNotEmpty) ubicaciones.add(val);
          }
          final ubicacionRollos = ubicaciones.join(', ');

          if (numeroParte.isNotEmpty) {
            items.add({
              'numero_parte': numeroParte,
              'ubicacion_rollos': ubicacionRollos,
            });
          }
        }
      }
      
      if (items.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(tr('no_data_found')),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }
      
      // Validar cuáles números de parte existen en el sistema
      setState(() => _isLoading = true);
      
      final partNumbers = items.map((i) => i['numero_parte'] as String).toList();
      final validation = await ApiService.validatePartNumbers(partNumbers);
      
      setState(() => _isLoading = false);
      
      if (validation['success'] != true) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(validation['error'] ?? 'Error'), backgroundColor: Colors.red),
          );
        }
        return;
      }
      
      // Crear mapa de existencia
      final results = validation['results'] as List;
      final existsMap = <String, bool>{};
      for (var r in results) {
        existsMap[r['numero_parte']] = r['exists'] == true;
      }
      
      // Separar items que existen y no existen
      final itemsToUpdate = items.where((i) => existsMap[i['numero_parte']] == true).toList();
      final itemsNotInSystem = items.where((i) => existsMap[i['numero_parte']] != true).toList();
      
      // Mostrar diálogo de vista previa
      final confirmed = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context) => _ImportRollosPreviewDialog(
          tr: tr,
          itemsToUpdate: itemsToUpdate,
          itemsNotInSystem: itemsNotInSystem,
        ),
      );
      
      if (confirmed != true || itemsToUpdate.isEmpty) return;
      
      // Enviar solo los que existen al servidor
      setState(() => _isLoading = true);
      
      final response = await ApiService.bulkUpdateUbicacionRollos(itemsToUpdate);
      
      setState(() => _isLoading = false);
      
      if (mounted) {
        if (response['success'] == true) {
          final updated = response['updated'] ?? 0;
          
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${tr('updated')}: $updated'),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 5),
            ),
          );
          
          // Recargar datos
          await loadData();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(response['error'] ?? 'Error'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }
  
  Future<void> _confirmDelete() async {
    if (_selectedIndex < 0 || _selectedIndex >= _filteredData.length) return;
    
    final material = _filteredData[_selectedIndex];
    final numeroParte = material['numero_parte']?.toString() ?? '';
    final codigoMaterial = material['codigo_material']?.toString() ?? '';
    
    if (numeroParte.isEmpty) return;
    
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.panelBackground,
        title: Row(
          children: [
            const Icon(Icons.warning_amber, color: Colors.orange, size: 24),
            const SizedBox(width: 8),
            Text(tr('confirm_delete'), style: const TextStyle(color: Colors.white, fontSize: 16)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${tr('delete_material_confirm')}:',
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.withOpacity(0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${tr('part_number')}: $numeroParte',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${tr('material_code')}: $codigoMaterial',
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              tr('delete_warning'),
              style: const TextStyle(color: Colors.orange, fontSize: 11, fontStyle: FontStyle.italic),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(tr('cancel'), style: const TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: Text(tr('delete'), style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    
    if (confirmed == true) {
      await _deleteMaterial(numeroParte);
    }
  }
  
  Future<void> _deleteMaterial(String numeroParte) async {
    try {
      final result = await ApiService.deleteMaterial(numeroParte);
      
      if (result['success'] == true || result['message'] != null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(result['message'] ?? tr('material_deleted')),
              backgroundColor: Colors.green,
            ),
          );
        }
        widget.onMaterialSelected?.call(null);
        await loadData();
      } else {
        throw Exception(result['error'] ?? 'Error desconocido');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
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
              // Barra de herramientas
              _buildToolbar(),
              // Barra de búsqueda (si está visible)
              if (_showSearchBar) _buildSearchBar(),
              // Header
              _buildHeader(),
              // Data rows
              Expanded(child: _buildDataRows()),
              // Footer
              GridFooter(
                text: '${widget.languageProvider.tr('total_rows')}: ${_filteredData.length}${_data.length != _filteredData.length ? ' / ${_data.length}' : ''}',
              ),
            ],
          ),
        ),
      ),
    );
  }
  
  Widget _buildToolbar() {
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: const BoxDecoration(
        color: AppColors.gridHeader,
        border: Border(bottom: BorderSide(color: AppColors.border, width: 1)),
      ),
      child: Row(
        children: [
          // Botón Nuevo (si puede crear completo o solo comparación)
          if (_canCreate)
            _buildToolbarButton(
              icon: Icons.add,
              label: tr('new'),
              color: Colors.green,
              onPressed: widget.onCreateNew,
            ),
          const SizedBox(width: 8),
          // Botón Eliminar (solo si tiene permiso de eliminar y hay selección)
          if (_canDelete)
            _buildToolbarButton(
              icon: Icons.delete,
              label: tr('delete'),
              color: _selectedIndex >= 0 ? Colors.red : Colors.grey,
              onPressed: _selectedIndex >= 0 ? _confirmDelete : null,
            ),
          const SizedBox(width: 8),
          // Botón Refrescar
          _buildToolbarButton(
            icon: Icons.refresh,
            label: tr('refresh'),
            color: Colors.blue,
            onPressed: loadData,
          ),
          const SizedBox(width: 8),
          // Botón Exportar Excel
          _buildToolbarButton(
            icon: Icons.file_download,
            label: tr('export_excel'),
            color: AppColors.buttonExcel,
            onPressed: _exportToExcel,
          ),
          const SizedBox(width: 8),
          // Botón Importar Comparaciones (disponible para editar completo o solo comparaciones)
          if (_canCreate)
            _buildToolbarButton(
              icon: Icons.upload_file,
              label: tr('import_comparisons'),
              color: Colors.orange,
              onPressed: _importComparisons,
            ),
          if (_canCreate)
            const SizedBox(width: 8),
          // Botón Importar Ubicación Rollos
          if (_canCreate)
            _buildToolbarButton(
              icon: Icons.upload_file,
              label: tr('import_rollos'),
              color: Colors.teal,
              onPressed: _importRollos,
            ),
          const Spacer(),
          // Botón Buscar
          _buildToolbarButton(
            icon: Icons.search,
            label: 'Ctrl+F',
            color: AppColors.buttonSearch,
            onPressed: _toggleSearchBar,
          ),
        ],
      ),
    );
  }
  
  Widget _buildToolbarButton({
    required IconData icon,
    required String label,
    required Color color,
    VoidCallback? onPressed,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: color.withOpacity(0.2),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: color.withOpacity(0.5)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 4),
              Text(label, style: TextStyle(fontSize: 11, color: color)),
            ],
          ),
        ),
      ),
    );
  }
  
  Widget _buildSearchBar() {
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: const BoxDecoration(
        color: AppColors.gridHeader,
        border: Border(bottom: BorderSide(color: AppColors.border, width: 1)),
      ),
      child: Row(
        children: [
          const Icon(Icons.search, size: 16, color: Colors.white54),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _searchController,
              focusNode: _searchFocusNode,
              style: const TextStyle(fontSize: 12, color: Colors.white),
              decoration: InputDecoration(
                hintText: tr('search_all_columns'),
                hintStyle: const TextStyle(color: Colors.white38, fontSize: 12),
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
              onChanged: _onSearch,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 14),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            color: Colors.white54,
            onPressed: _toggleSearchBar,
          ),
        ],
      ),
    );
  }
  
  Widget _buildHeader() {
    return Container(
      height: 32,
      decoration: const BoxDecoration(
        color: AppColors.gridHeader,
        border: Border(bottom: BorderSide(color: AppColors.border, width: 1)),
      ),
      child: Row(
        children: _fields.asMap().entries.map((entry) {
          final idx = entry.key;
          final field = entry.value;
          final header = _headers[idx];
          final hasFilter = _columnFilters.containsKey(field);
          final isSorted = _sortColumn == field;
          
          return Expanded(
            flex: getColumnFlex(idx),
            child: Stack(
              children: [
                GestureDetector(
                  onTap: () => _sort(field),
                  child: Container(
                    key: _filterKeys[field],
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    decoration: const BoxDecoration(
                      border: Border(right: BorderSide(color: AppColors.border, width: 0.5)),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            header,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: hasFilter ? Colors.amber : Colors.white,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (isSorted)
                          Icon(
                            _sortAscending ? Icons.arrow_upward : Icons.arrow_downward,
                            size: 10,
                            color: Colors.cyan,
                          ),
                        InkWell(
                          onTap: () => _showFilterMenu(field, _filterKeys[field]!),
                          child: Icon(
                            Icons.filter_list,
                            size: 12,
                            color: hasFilter ? Colors.amber : Colors.white54,
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
                  child: buildResizeHandle(idx),
                ),
              ],
            ),
          );
        }).toList(),
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
            Icon(Icons.inventory_2_outlined, size: 48, color: Colors.white.withOpacity(0.1)),
            const SizedBox(height: 8),
            Text(
              tr('no_data'),
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
          onTap: () {
            setState(() => _selectedIndex = isSelected ? -1 : index);
            widget.onMaterialSelected?.call(isSelected ? null : row);
          },
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
                
                // DEBUG: Ver qué valores tiene cada celda
                if (index == 0 && idx < 5) {
                  print('Row 0, Field $field: "$value" (isNull: ${row[field] == null}, isEmpty: ${value.isEmpty})');
                }
                
                // Formatear fechas
                if (field == 'fecha_registro' && value.isNotEmpty) {
                  try {
                    final date = DateTime.parse(value);
                    value = '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
                  } catch (_) {}
                }
                
                // Formatear standard_pack: mostrar "-" si es 0 o vacío
                if (field == 'standard_pack' && (value.isEmpty || value == '0')) {
                  value = '-';
                }
                
                Widget cellContent;
                if (field == 'assign_internal_lot' || field == 'dividir_lote') {
                  final isActive = value == '1' || value == 'true';
                  cellContent = Icon(
                    isActive ? Icons.check_box : Icons.check_box_outline_blank,
                    size: 16,
                    color: isActive ? Colors.green : Colors.grey,
                  );
                } else {
                  cellContent = Text(
                    value,
                    style: const TextStyle(fontSize: 10, color: Colors.white),
                    overflow: TextOverflow.ellipsis,
                  );
                }
                
                return Expanded(
                  flex: getColumnFlex(idx),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    alignment: (field == 'assign_internal_lot' || field == 'dividir_lote') ? Alignment.center : Alignment.centerLeft,
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
}

// Diálogo de vista previa para importación de comparaciones
class _ImportPreviewDialog extends StatelessWidget {
  final String Function(String) tr;
  final List<Map<String, dynamic>> itemsToUpdate;
  final List<Map<String, dynamic>> itemsNotInSystem;

  const _ImportPreviewDialog({
    required this.tr,
    required this.itemsToUpdate,
    required this.itemsNotInSystem,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.panelBackground,
      child: Container(
        width: 700,
        height: 500,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                const Icon(Icons.preview, color: Colors.orange, size: 24),
                const SizedBox(width: 8),
                Text(
                  tr('preview_import'),
                  style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.grey),
                  onPressed: () => Navigator.pop(context, false),
                ),
              ],
            ),
            const Divider(color: AppColors.border),
            
            // Resumen
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.gridHeader,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      children: [
                        const Icon(Icons.check_circle, color: Colors.green, size: 32),
                        const SizedBox(height: 4),
                        Text(
                          '${itemsToUpdate.length}',
                          style: const TextStyle(color: Colors.green, fontSize: 20, fontWeight: FontWeight.bold),
                        ),
                        Text(tr('will_be_updated'), style: const TextStyle(color: Colors.white70, fontSize: 11)),
                      ],
                    ),
                  ),
                  Container(width: 1, height: 60, color: AppColors.border),
                  Expanded(
                    child: Column(
                      children: [
                        const Icon(Icons.error, color: Colors.red, size: 32),
                        const SizedBox(height: 4),
                        Text(
                          '${itemsNotInSystem.length}',
                          style: const TextStyle(color: Colors.red, fontSize: 20, fontWeight: FontWeight.bold),
                        ),
                        Text(tr('not_in_system'), style: const TextStyle(color: Colors.white70, fontSize: 11)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            
            // Tabla de vista previa
            Expanded(
              child: DefaultTabController(
                length: 2,
                child: Column(
                  children: [
                    TabBar(
                      labelColor: Colors.white,
                      unselectedLabelColor: Colors.grey,
                      indicatorColor: Colors.orange,
                      tabs: [
                        Tab(text: '${tr('will_be_updated')} (${itemsToUpdate.length})'),
                        Tab(text: '${tr('not_in_system')} (${itemsNotInSystem.length})'),
                      ],
                    ),
                    Expanded(
                      child: TabBarView(
                        children: [
                          _buildItemsTable(itemsToUpdate, Colors.green),
                          _buildItemsTable(itemsNotInSystem, Colors.red),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            
            const Divider(color: AppColors.border),
            
            // Botones
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: Text(tr('cancel'), style: const TextStyle(color: Colors.grey)),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  icon: const Icon(Icons.upload, size: 18),
                  label: Text('${tr('import')} (${itemsToUpdate.length})'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: itemsToUpdate.isNotEmpty ? Colors.orange : Colors.grey,
                  ),
                  onPressed: itemsToUpdate.isNotEmpty ? () => Navigator.pop(context, true) : null,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildItemsTable(List<Map<String, dynamic>> items, Color statusColor) {
    if (items.isEmpty) {
      return const Center(
        child: Text('No hay registros', style: TextStyle(color: Colors.grey)),
      );
    }
    
    return Container(
      margin: const EdgeInsets.only(top: 8),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        children: [
          // Header
          Container(
            height: 32,
            decoration: const BoxDecoration(
              color: AppColors.gridHeader,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(4),
                topRight: Radius.circular(4),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  flex: 2,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Text(tr('part_number_col'), style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold)),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Text(tr('comparison_col'), style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold)),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Text(tr('location_rollos'), style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ),
          // Rows
          Expanded(
            child: ListView.builder(
              itemCount: items.length,
              itemBuilder: (context, index) {
                final item = items[index];
                return Container(
                  height: 28,
                  decoration: BoxDecoration(
                    color: index % 2 == 0 ? AppColors.gridRowEven : AppColors.gridRowOdd,
                    border: const Border(bottom: BorderSide(color: AppColors.border, width: 0.5)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Text(
                            item['numero_parte']?.toString() ?? '',
                            style: const TextStyle(color: Colors.white, fontSize: 11),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 2,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Text(
                            item['comparacion']?.toString() ?? '',
                            style: const TextStyle(color: Colors.white, fontSize: 11),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 2,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Text(
                            item['ubicacion_rollos']?.toString() ?? '',
                            style: const TextStyle(color: Colors.white, fontSize: 11),
                            overflow: TextOverflow.ellipsis,
                          ),
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
    );
  }
}

// Diálogo de vista previa para importación de ubicación rollos
class _ImportRollosPreviewDialog extends StatelessWidget {
  final String Function(String) tr;
  final List<Map<String, dynamic>> itemsToUpdate;
  final List<Map<String, dynamic>> itemsNotInSystem;

  const _ImportRollosPreviewDialog({
    required this.tr,
    required this.itemsToUpdate,
    required this.itemsNotInSystem,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.panelBackground,
      child: Container(
        width: 600,
        height: 500,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                const Icon(Icons.view_carousel, color: Colors.teal, size: 24),
                const SizedBox(width: 8),
                Text(
                  tr('preview_import_rollos'),
                  style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.grey),
                  onPressed: () => Navigator.pop(context, false),
                ),
              ],
            ),
            const Divider(color: AppColors.border),
            
            // Resumen
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.gridHeader,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      children: [
                        const Icon(Icons.check_circle, color: Colors.green, size: 32),
                        const SizedBox(height: 4),
                        Text(
                          '${itemsToUpdate.length}',
                          style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                        ),
                        Text(tr('to_update'), style: const TextStyle(color: Colors.white70, fontSize: 11)),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Column(
                      children: [
                        const Icon(Icons.warning, color: Colors.orange, size: 32),
                        const SizedBox(height: 4),
                        Text(
                          '${itemsNotInSystem.length}',
                          style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                        ),
                        Text(tr('not_in_system'), style: const TextStyle(color: Colors.white70, fontSize: 11)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            
            // Tabs
            Expanded(
              child: DefaultTabController(
                length: 2,
                child: Column(
                  children: [
                    TabBar(
                      tabs: [
                        Tab(text: '${tr('to_update')} (${itemsToUpdate.length})'),
                        Tab(text: '${tr('not_in_system')} (${itemsNotInSystem.length})'),
                      ],
                      labelColor: Colors.white,
                      unselectedLabelColor: Colors.grey,
                      indicatorColor: Colors.teal,
                    ),
                    Expanded(
                      child: TabBarView(
                        children: [
                          _buildRollosTable(itemsToUpdate, Colors.green),
                          _buildRollosTable(itemsNotInSystem, Colors.orange),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            
            // Botones
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: Text(tr('cancel'), style: const TextStyle(color: Colors.grey)),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: itemsToUpdate.isEmpty ? null : () => Navigator.pop(context, true),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.teal),
                  child: Text(tr('import'), style: const TextStyle(color: Colors.white)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildRollosTable(List<Map<String, dynamic>> items, Color statusColor) {
    if (items.isEmpty) {
      return const Center(
        child: Text('No hay registros', style: TextStyle(color: Colors.grey)),
      );
    }
    
    return Container(
      margin: const EdgeInsets.only(top: 8),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        children: [
          // Header
          Container(
            height: 32,
            decoration: const BoxDecoration(
              color: AppColors.gridHeader,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(4),
                topRight: Radius.circular(4),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  flex: 2,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Text(tr('part_number_col'), style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold)),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Text(tr('location_rollos'), style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ),
          // Rows
          Expanded(
            child: ListView.builder(
              itemCount: items.length,
              itemBuilder: (context, index) {
                final item = items[index];
                return Container(
                  height: 28,
                  decoration: BoxDecoration(
                    color: index % 2 == 0 ? AppColors.gridRowEven : AppColors.gridRowOdd,
                    border: const Border(bottom: BorderSide(color: AppColors.border, width: 0.5)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Text(
                            item['numero_parte']?.toString() ?? '',
                            style: const TextStyle(color: Colors.white, fontSize: 11),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 2,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Text(
                            item['ubicacion_rollos']?.toString() ?? '',
                            style: const TextStyle(color: Colors.white, fontSize: 11),
                            overflow: TextOverflow.ellipsis,
                          ),
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
    );
  }
}
