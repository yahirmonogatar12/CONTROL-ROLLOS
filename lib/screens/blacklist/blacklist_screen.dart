import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_warehousing_flutter/core/localization/app_translations.dart';
import 'package:material_warehousing_flutter/core/theme/app_colors.dart';
import 'package:material_warehousing_flutter/core/services/api_service.dart';
import 'package:material_warehousing_flutter/core/services/auth_service.dart';
import 'package:material_warehousing_flutter/core/services/excel_export_service.dart';
import 'package:material_warehousing_flutter/core/widgets/grid_footer.dart';
import 'package:intl/intl.dart';

/// Pantalla de Lista Negra - Estilo similar a Material Control
class BlacklistScreen extends StatefulWidget {
  final LanguageProvider languageProvider;
  
  const BlacklistScreen({
    super.key,
    required this.languageProvider,
  });

  @override
  State<BlacklistScreen> createState() => _BlacklistScreenState();
}

class _BlacklistScreenState extends State<BlacklistScreen> {
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
  
  // Campos de la tabla blacklisted_lots
  final List<String> _fields = [
    'work_date',
    'production_line',
    'product_name',
    'lot_id',
    'indicated_qty',
    'produced_qty',
    'quantity_ea',
    'ek_data',
    'process',
    'equipment',
    'equipment_entry_date',
    'reason',
    'blocked_by',
    'created_at',
  ];

  String tr(String key) => widget.languageProvider.tr(key);

  List<String> get _headers => [
    tr('work_date'),
    tr('production_line'),
    tr('product_name'),
    tr('lot_id'),
    tr('indicated_qty'),
    tr('produced_qty'),
    tr('quantity_ea'),
    tr('ek_data'),
    tr('process'),
    tr('equipment'),
    tr('equipment_entry_date'),
    tr('reason'),
    tr('created_by'),
    tr('registration_date'),
  ];

  // Permisos
  bool get _canWrite => AuthService.canWriteBlacklist;

  @override
  void initState() {
    super.initState();
    for (var field in _fields) {
      _filterKeys[field] = GlobalKey();
    }
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
      final data = await ApiService.getBlacklist();
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
        return _fields.any((field) {
          final value = row[field]?.toString().toLowerCase() ?? '';
          return value.contains(_searchText.toLowerCase());
        });
      }).toList();
    }
    
    // Aplicar ordenamiento
    if (_sortColumn != null) {
      result.sort((a, b) {
        final aVal = a[_sortColumn]?.toString() ?? '';
        final bVal = b[_sortColumn]?.toString() ?? '';
        return _sortAscending ? aVal.compareTo(bVal) : bVal.compareTo(aVal);
      });
    }
    
    _filteredData = result;
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
  
  void _toggleSearchBar() {
    setState(() {
      _showSearchBar = !_showSearchBar;
      if (_showSearchBar) {
        _searchFocusNode.requestFocus();
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

  Future<void> _exportToExcel() async {
    if (_filteredData.isEmpty) return;

    final headers = ['NO', ..._headers];
    final fieldMapping = ['no', ..._fields];

    final exportData = _filteredData.asMap().entries.map((entry) {
      final i = entry.key;
      final row = Map<String, dynamic>.from(entry.value);
      row['no'] = (i + 1).toString();
      row['work_date'] = _formatDate(row['work_date']);
      row['equipment_entry_date'] = _formatDateTime(row['equipment_entry_date']);
      row['created_at'] = _formatDateTime(row['created_at']);
      row['indicated_qty'] = row['indicated_qty']?.toString() ?? '';
      row['produced_qty'] = row['produced_qty']?.toString() ?? '';
      row['quantity_ea'] = row['quantity_ea']?.toString() ?? '';
      return row;
    }).toList();

    final success = await ExcelExportService.exportToExcel(
      data: exportData,
      headers: headers,
      fieldMapping: fieldMapping,
      fileName: 'Blacklist_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}',
    );

    if (mounted && success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr('export_excel')), backgroundColor: Colors.green),
      );
    }
  }

  String _formatDate(dynamic date) {
    if (date == null) return '';
    try {
      final dt = DateTime.parse(date.toString());
      return DateFormat('yyyy/MM/dd').format(dt);
    } catch (_) {
      return date.toString();
    }
  }

  String _formatDateTime(dynamic date) {
    if (date == null) return '';
    try {
      final dt = DateTime.parse(date.toString());
      return DateFormat('yyyy-MM-dd HH:mm').format(dt);
    } catch (_) {
      return date.toString();
    }
  }

  void _showAddDialog() {
    _showFormDialog(null);
  }

  void _showEditDialog() {
    if (_selectedIndex < 0 || _selectedIndex >= _filteredData.length) return;
    _showFormDialog(_filteredData[_selectedIndex]);
  }

  void _showFormDialog(Map<String, dynamic>? row) {
    final isEdit = row != null;
    final workDateCtrl = TextEditingController(text: row != null ? _formatDate(row['work_date']) : '');
    final productionLineCtrl = TextEditingController(text: row?['production_line'] ?? '');
    final productNameCtrl = TextEditingController(text: row?['product_name'] ?? '');
    final lotIdCtrl = TextEditingController(text: row?['lot_id'] ?? '');
    final indicatedQtyCtrl = TextEditingController(text: row?['indicated_qty']?.toString() ?? '');
    final producedQtyCtrl = TextEditingController(text: row?['produced_qty']?.toString() ?? '');
    final quantityEaCtrl = TextEditingController(text: row?['quantity_ea']?.toString() ?? '');
    final ekDataCtrl = TextEditingController(text: row?['ek_data'] ?? '');
    final processCtrl = TextEditingController(text: row?['process'] ?? '');
    final equipmentCtrl = TextEditingController(text: row?['equipment'] ?? '');
    final equipmentEntryDateCtrl = TextEditingController(text: row != null ? _formatDateTime(row['equipment_entry_date']) : '');
    final reasonCtrl = TextEditingController(text: row?['reason'] ?? '');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.panelBackground,
        title: Row(
          children: [
            Icon(isEdit ? Icons.edit : Icons.add, color: Colors.cyan, size: 20),
            const SizedBox(width: 8),
            Text(isEdit ? tr('edit') : tr('new'), style: const TextStyle(color: Colors.white, fontSize: 16)),
          ],
        ),
        content: SingleChildScrollView(
          child: SizedBox(
            width: 600,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(child: _buildTextField(tr('work_date'), workDateCtrl, hint: 'YYYY/MM/DD')),
                    const SizedBox(width: 8),
                    Expanded(child: _buildTextField(tr('production_line'), productionLineCtrl)),
                    const SizedBox(width: 8),
                    Expanded(child: _buildTextField(tr('product_name'), productNameCtrl)),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(flex: 2, child: _buildTextField('LOT ID *', lotIdCtrl)),
                    const SizedBox(width: 8),
                    Expanded(child: _buildTextField(tr('indicated_qty'), indicatedQtyCtrl, isNumber: true)),
                    const SizedBox(width: 8),
                    Expanded(child: _buildTextField(tr('produced_qty'), producedQtyCtrl, isNumber: true)),
                    const SizedBox(width: 8),
                    Expanded(child: _buildTextField(tr('quantity_ea'), quantityEaCtrl, isNumber: true)),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(child: _buildTextField(tr('ek_data'), ekDataCtrl)),
                    const SizedBox(width: 8),
                    Expanded(child: _buildTextField(tr('process'), processCtrl)),
                    const SizedBox(width: 8),
                    Expanded(child: _buildTextField(tr('equipment'), equipmentCtrl)),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(child: _buildTextField(tr('equipment_entry_date'), equipmentEntryDateCtrl, hint: 'YYYY-MM-DD HH:mm:ss')),
                    const SizedBox(width: 8),
                    Expanded(flex: 2, child: _buildTextField(tr('reason'), reasonCtrl)),
                  ],
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(tr('cancel'), style: const TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () async {
              if (lotIdCtrl.text.trim().isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('LOT ID requerido'), backgroundColor: Colors.orange),
                );
                return;
              }

              final data = {
                'work_date': workDateCtrl.text.isNotEmpty ? workDateCtrl.text.replaceAll('/', '-') : null,
                'production_line': productionLineCtrl.text.isNotEmpty ? productionLineCtrl.text : null,
                'product_name': productNameCtrl.text.isNotEmpty ? productNameCtrl.text : null,
                'lot_id': lotIdCtrl.text.trim(),
                'indicated_qty': int.tryParse(indicatedQtyCtrl.text),
                'produced_qty': int.tryParse(producedQtyCtrl.text),
                'quantity_ea': int.tryParse(quantityEaCtrl.text),
                'ek_data': ekDataCtrl.text.isNotEmpty ? ekDataCtrl.text : null,
                'process': processCtrl.text.isNotEmpty ? processCtrl.text : null,
                'equipment': equipmentCtrl.text.isNotEmpty ? equipmentCtrl.text : null,
                'equipment_entry_date': equipmentEntryDateCtrl.text.isNotEmpty ? equipmentEntryDateCtrl.text : null,
                'reason': reasonCtrl.text.isNotEmpty ? reasonCtrl.text : null,
                'blocked_by': AuthService.currentUser?.nombreCompleto,
              };

              Map<String, dynamic> result;
              if (isEdit) {
                result = await ApiService.updateBlacklist(row['id'], data);
              } else {
                result = await ApiService.addToBlacklist(data);
              }

              if (result['success'] == true) {
                Navigator.pop(ctx);
                _loadData();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(tr('lot_added_blacklist')), backgroundColor: Colors.green),
                );
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(result['error'] ?? 'Error'), backgroundColor: Colors.red),
                );
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.cyan),
            child: Text(tr('save')),
          ),
        ],
      ),
    );
  }

  Widget _buildTextField(String label, TextEditingController controller, {String? hint, bool isNumber = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 10)),
        const SizedBox(height: 2),
        TextField(
          controller: controller,
          keyboardType: isNumber ? TextInputType.number : TextInputType.text,
          inputFormatters: isNumber ? [FilteringTextInputFormatter.digitsOnly] : null,
          style: const TextStyle(fontSize: 12, color: Colors.white),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: Colors.white38, fontSize: 10),
            filled: true,
            fillColor: AppColors.fieldBackground,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(4),
              borderSide: BorderSide.none,
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            isDense: true,
          ),
        ),
      ],
    );
  }

  Future<void> _deleteSelected() async {
    if (_selectedIndex < 0 || _selectedIndex >= _filteredData.length) return;
    
    final row = _filteredData[_selectedIndex];
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.panelBackground,
        title: const Text('Confirmar eliminación', style: TextStyle(color: Colors.white)),
        content: Text('¿Eliminar lote "${row['lot_id']}" de la lista negra?', style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(tr('cancel'), style: const TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: Text(tr('delete')),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final result = await ApiService.removeFromBlacklist(row['id']);
      if (result['success'] == true) {
        _selectedIndex = -1;
        _loadData();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(tr('lot_removed_blacklist')), backgroundColor: Colors.green),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(result['error'] ?? 'Error'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  /// Diálogo de carga masiva (Bulk Import) desde Excel/texto pegado
  void _showBulkImportDialog() {
    final bulkController = TextEditingController();
    
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.panelBackground,
        title: Row(
          children: [
            const Icon(Icons.upload_file, color: Colors.cyan, size: 20),
            const SizedBox(width: 8),
            Text(tr('bulk_import'), style: const TextStyle(color: Colors.white, fontSize: 16)),
          ],
        ),
        content: SizedBox(
          width: 800,
          height: 500,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Instrucciones
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue.withOpacity(0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.info_outline, color: Colors.blue, size: 16),
                        const SizedBox(width: 8),
                        Text(tr('bulk_import_instructions'), style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      '• Copia las filas desde Excel y pégalas abajo\n'
                      '• El orden de columnas debe ser:\n'
                      '  WORK_DATE | LINE | PRODUCT | LOT_ID | IND_QTY | PROD_QTY | QTY_EA | EK | PROCESS | EQUIPMENT | ENTRY_DATE | REASON\n'
                      '• Separado por TAB (como viene de Excel)\n'
                      '• Una fila por línea',
                      style: TextStyle(color: Colors.white70, fontSize: 11),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              // Área de texto para pegar
              Expanded(
                child: TextField(
                  controller: bulkController,
                  maxLines: null,
                  expands: true,
                  style: const TextStyle(fontSize: 11, color: Colors.white, fontFamily: 'monospace'),
                  decoration: InputDecoration(
                    hintText: 'Pega aquí los datos de Excel...\n\nEjemplo:\n2024-12-01\tLINE1\tPRODUCT-A\tLOT001\t100\t98\t9800\tEK001\tPROCESS1\tEQUIP1\t2024-12-01 10:00:00\tDefecto',
                    hintStyle: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 10),
                    filled: true,
                    fillColor: AppColors.fieldBackground,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.all(12),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(tr('cancel'), style: const TextStyle(color: Colors.grey)),
          ),
          ElevatedButton.icon(
            onPressed: () async {
              final text = bulkController.text.trim();
              if (text.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('No hay datos para importar'), backgroundColor: Colors.orange),
                );
                return;
              }

              final lines = text.split('\n').where((l) => l.trim().isNotEmpty).toList();
              int success = 0;
              int failed = 0;
              final errors = <String>[];

              for (int i = 0; i < lines.length; i++) {
                final cols = lines[i].split('\t');
                
                // Mínimo necesitamos el LOT_ID (columna 3, índice 3)
                if (cols.length < 4 || cols[3].trim().isEmpty) {
                  failed++;
                  errors.add('Fila ${i + 1}: LOT_ID vacío o columnas insuficientes');
                  continue;
                }

                final data = {
                  'work_date': cols.length > 0 && cols[0].trim().isNotEmpty ? cols[0].trim() : null,
                  'production_line': cols.length > 1 && cols[1].trim().isNotEmpty ? cols[1].trim() : null,
                  'product_name': cols.length > 2 && cols[2].trim().isNotEmpty ? cols[2].trim() : null,
                  'lot_id': cols[3].trim(),
                  'indicated_qty': cols.length > 4 ? int.tryParse(cols[4].trim()) : null,
                  'produced_qty': cols.length > 5 ? int.tryParse(cols[5].trim()) : null,
                  'quantity_ea': cols.length > 6 ? int.tryParse(cols[6].trim()) : null,
                  'ek_data': cols.length > 7 && cols[7].trim().isNotEmpty ? cols[7].trim() : null,
                  'process': cols.length > 8 && cols[8].trim().isNotEmpty ? cols[8].trim() : null,
                  'equipment': cols.length > 9 && cols[9].trim().isNotEmpty ? cols[9].trim() : null,
                  'equipment_entry_date': cols.length > 10 && cols[10].trim().isNotEmpty ? cols[10].trim() : null,
                  'reason': cols.length > 11 && cols[11].trim().isNotEmpty ? cols[11].trim() : null,
                  'blocked_by': AuthService.currentUser?.nombreCompleto,
                };

                final result = await ApiService.addToBlacklist(data);
                if (result['success'] == true) {
                  success++;
                } else {
                  failed++;
                  errors.add('Fila ${i + 1} (${cols[3]}): ${result['error'] ?? 'Error desconocido'}');
                }
              }

              Navigator.pop(ctx);
              _loadData();

              // Mostrar resultado
              String message = '✅ Importados: $success';
              if (failed > 0) {
                message += '\n❌ Fallidos: $failed';
              }
              
              showDialog(
                context: context,
                builder: (c) => AlertDialog(
                  backgroundColor: AppColors.panelBackground,
                  title: Text(tr('bulk_import'), style: const TextStyle(color: Colors.white)),
                  content: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(message, style: const TextStyle(color: Colors.white)),
                        if (errors.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          const Text('Errores:', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 4),
                          ...errors.take(10).map((e) => Text(e, style: const TextStyle(color: Colors.white70, fontSize: 11))),
                          if (errors.length > 10)
                            Text('... y ${errors.length - 10} más', style: const TextStyle(color: Colors.white54, fontSize: 11)),
                        ],
                      ],
                    ),
                  ),
                  actions: [
                    ElevatedButton(
                      onPressed: () => Navigator.pop(c),
                      child: const Text('OK'),
                    ),
                  ],
                ),
              );
            },
            icon: const Icon(Icons.upload, size: 16),
            label: Text(tr('import')),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
          ),
        ],
      ),
    );
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
              // Header del módulo
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: const BoxDecoration(
                  color: AppColors.gridHeader,
                  border: Border(bottom: BorderSide(color: AppColors.border, width: 1)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.block, color: Colors.red, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      tr('blacklist'),
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                  ],
                ),
              ),
              // Barra de herramientas
              _buildToolbar(),
              // Barra de búsqueda (si está visible)
              if (_showSearchBar) _buildSearchBar(),
              // Header de columnas
              _buildHeader(),
              // Data rows
              Expanded(child: _buildDataRows()),
              // Footer
              GridFooter(
                text: '${tr('total_rows')}: ${_filteredData.length}${_data.length != _filteredData.length ? ' / ${_data.length}' : ''}',
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
          // Botón Nuevo
          if (_canWrite)
            _buildToolbarButton(
              icon: Icons.add,
              label: tr('new'),
              color: Colors.green,
              onPressed: _showAddDialog,
            ),
          const SizedBox(width: 8),
          // Botón Editar
          if (_canWrite)
            _buildToolbarButton(
              icon: Icons.edit,
              label: tr('edit'),
              color: Colors.amber,
              onPressed: _selectedIndex >= 0 ? _showEditDialog : null,
            ),
          const SizedBox(width: 8),
          // Botón Eliminar
          if (_canWrite)
            _buildToolbarButton(
              icon: Icons.delete,
              label: tr('delete'),
              color: Colors.red,
              onPressed: _selectedIndex >= 0 ? _deleteSelected : null,
            ),
          const SizedBox(width: 16),
          // Separador
          Container(width: 1, height: 20, color: AppColors.border),
          const SizedBox(width: 16),
          // Botón Bulk Import
          if (_canWrite)
            _buildToolbarButton(
              icon: Icons.upload_file,
              label: tr('bulk_import'),
              color: Colors.purple,
              onPressed: _showBulkImportDialog,
            ),
          const SizedBox(width: 8),
          // Botón Refrescar
          _buildToolbarButton(
            icon: Icons.refresh,
            label: tr('refresh'),
            color: Colors.blue,
            onPressed: _loadData,
          ),
          const SizedBox(width: 8),
          // Botón Exportar Excel
          _buildToolbarButton(
            icon: Icons.file_download,
            label: tr('export_excel'),
            color: AppColors.buttonExcel,
            onPressed: _filteredData.isNotEmpty ? _exportToExcel : null,
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
    final isEnabled = onPressed != null;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: isEnabled ? color.withOpacity(0.2) : Colors.grey.withOpacity(0.1),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: isEnabled ? color.withOpacity(0.5) : Colors.grey.withOpacity(0.3)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: isEnabled ? color : Colors.grey),
              const SizedBox(width: 4),
              Text(label, style: TextStyle(fontSize: 11, color: isEnabled ? color : Colors.grey)),
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
          
          // Ajustar flex según columna
          int flex = 1;
          if (field == 'lot_id' || field == 'product_name' || field == 'reason') flex = 2;
          if (field == 'equipment_entry_date' || field == 'created_at') flex = 2;
          
          return Expanded(
            flex: flex,
            child: GestureDetector(
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
                          fontSize: 9,
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
            Icon(Icons.block_outlined, size: 48, color: Colors.white.withOpacity(0.1)),
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
          },
          onDoubleTap: _canWrite ? _showEditDialog : null,
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
                  ? const BorderSide(color: Colors.red, width: 3) 
                  : BorderSide.none,
              ),
            ),
            child: Row(
              children: _fields.asMap().entries.map((entry) {
                final idx = entry.key;
                final field = entry.value;
                var value = row[field]?.toString() ?? '';
                
                // Formatear fechas
                if ((field == 'work_date') && value.isNotEmpty) {
                  value = _formatDate(row[field]);
                }
                if ((field == 'equipment_entry_date' || field == 'created_at') && value.isNotEmpty) {
                  value = _formatDateTime(row[field]);
                }
                
                // Ajustar flex
                int flex = 1;
                if (field == 'lot_id' || field == 'product_name' || field == 'reason') flex = 2;
                if (field == 'equipment_entry_date' || field == 'created_at') flex = 2;
                
                return Expanded(
                  flex: flex,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    alignment: Alignment.centerLeft,
                    decoration: const BoxDecoration(
                      border: Border(right: BorderSide(color: AppColors.border, width: 0.5)),
                    ),
                    child: Text(
                      value,
                      style: const TextStyle(fontSize: 10, color: Colors.white),
                      overflow: TextOverflow.ellipsis,
                    ),
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
