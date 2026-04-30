import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_warehousing_flutter/core/localization/app_translations.dart';
import 'package:material_warehousing_flutter/core/theme/app_colors.dart';
import 'package:material_warehousing_flutter/core/widgets/grid_footer.dart';
import 'package:material_warehousing_flutter/core/services/api_service.dart';
import 'package:material_warehousing_flutter/core/services/auth_service.dart';
import 'package:material_warehousing_flutter/core/widgets/resizable_grid_header.dart';

// ============================================
// Quarantine Pending Grid - Materiales en Cuarentena
// ============================================
class QuarantinePendingGrid extends StatefulWidget {
  final LanguageProvider languageProvider;

  const QuarantinePendingGrid({
    super.key,
    required this.languageProvider,
  });

  @override
  State<QuarantinePendingGrid> createState() => QuarantinePendingGridState();
}

class QuarantinePendingGridState extends State<QuarantinePendingGrid> with ResizableColumnsMixin {
  List<Map<String, dynamic>> _data = [];
  List<Map<String, dynamic>> _filteredData = [];
  bool _isLoading = true;
  int _selectedIndex = -1;
  
  // Búsqueda
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  bool _showSearchBar = false;
  String _searchText = '';

  // Campos del grid
  final List<String> _fields = [
    'codigo_material_recibido', 'part_number', 'cantidad', 
    'reason', 'created_by_name', 'created_at'
  ];

  String tr(String key) => widget.languageProvider.tr(key);

  List<String> get _headers => [
    tr('material_code'),
    tr('part_number'),
    tr('quantity'),
    tr('reason'),
    tr('created_by'),
    tr('created_at'),
  ];

  @override
  void initState() {
    super.initState();
    initColumnFlex(6, 'quarantine_pending', defaultFlexValues: [2.0, 2.0, 1.0, 3.0, 2.0, 2.0]);
    _loadData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    
    try {
      final data = await ApiService.getQuarantine(status: 'InQuarantine');
      setState(() {
        _data = data;
        _applySearch();
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  void reloadData() => _loadData();

  void _applySearch() {
    if (_searchText.isEmpty) {
      _filteredData = List.from(_data);
    } else {
      _filteredData = _data.where((row) {
        return _fields.any((field) {
          final value = row[field]?.toString().toLowerCase() ?? '';
          return value.contains(_searchText.toLowerCase());
        });
      }).toList();
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
        _applySearch();
      }
    });
  }

  // Mostrar modal de disposición
  Future<void> _showDispositionDialog(Map<String, dynamic> row) async {
    if (!AuthService.canWriteQuarantine) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(tr('no_permission')),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    
    String? selectedAction;
    final commentController = TextEditingController();
    
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: AppColors.panelBackground,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          title: Row(
            children: [
              const Icon(Icons.shield, color: Colors.orange, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(tr('quarantine_action'), style: const TextStyle(color: Colors.white, fontSize: 14)),
                    Text(
                      row['codigo_material_recibido'] ?? '',
                      style: const TextStyle(color: Colors.white54, fontSize: 10),
                    ),
                  ],
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Información del material
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.gridBackground,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Column(
                    children: [
                      _buildInfoRow(tr('part_number'), row['part_number'] ?? ''),
                      _buildInfoRow(tr('quantity'), row['cantidad']?.toString() ?? '0'),
                      _buildInfoRow(tr('reason'), row['reason'] ?? ''),
                    ],
                  ),
                ),
                
                const SizedBox(height: 16),
                Text(tr('select_action'), style: const TextStyle(color: Colors.white70, fontSize: 12)),
                const SizedBox(height: 8),
                
                // Opciones de acción
                ...['Released', 'Scrapped', 'Returned'].map((action) {
                  IconData icon;
                  Color color;
                  String label;
                  
                  switch (action) {
                    case 'Released':
                      icon = Icons.check_circle;
                      color = Colors.green;
                      label = tr('release');
                      break;
                    case 'Scrapped':
                      icon = Icons.delete_forever;
                      color = Colors.red;
                      label = tr('scrap');
                      break;
                    case 'Returned':
                      icon = Icons.undo;
                      color = Colors.orange;
                      label = tr('return_supplier');
                      break;
                    default:
                      icon = Icons.help;
                      color = Colors.grey;
                      label = action;
                  }
                  
                  return RadioListTile<String>(
                    title: Row(
                      children: [
                        Icon(icon, color: color, size: 18),
                        const SizedBox(width: 8),
                        Text(label, style: TextStyle(color: color, fontSize: 12)),
                      ],
                    ),
                    value: action,
                    groupValue: selectedAction,
                    activeColor: color,
                    onChanged: (val) => setDialogState(() => selectedAction = val),
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                  );
                }),
                
                const SizedBox(height: 16),
                Text('${tr('comments')} *', style: const TextStyle(color: Colors.amber, fontSize: 11)),
                const SizedBox(height: 4),
                TextField(
                  controller: commentController,
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                  maxLines: 3,
                  onChanged: (_) => setDialogState(() {}),
                  decoration: InputDecoration(
                    hintText: tr('enter_comments'),
                    hintStyle: const TextStyle(color: Colors.white38, fontSize: 11),
                    filled: true,
                    fillColor: AppColors.gridBackground,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(4),
                      borderSide: const BorderSide(color: AppColors.border),
                    ),
                    contentPadding: const EdgeInsets.all(8),
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
            ElevatedButton(
              onPressed: selectedAction != null && commentController.text.trim().isNotEmpty
                  ? () => Navigator.pop(ctx, {'action': selectedAction, 'comments': commentController.text.trim()})
                  : null,
              style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
              child: Text(tr('confirm')),
            ),
          ],
        ),
      ),
    );
    
    commentController.dispose();
    
    if (result != null) {
      final updateResult = await ApiService.updateQuarantineStatus(
        id: row['id'],
        status: result['action'],
        comments: result['comments'],
        userId: AuthService.currentUser?.id ?? 0,
        userName: AuthService.currentUser?.nombreCompleto ?? '',
      );
      
      if (updateResult['success'] == true && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(tr('updated_successfully')),
            backgroundColor: Colors.green,
          ),
        );
        _loadData();
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${updateResult['error']}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // Mostrar historial del item
  Future<void> _showItemHistory(Map<String, dynamic> row) async {
    final history = await ApiService.getQuarantineItemHistory(row['id']);
    
    if (!mounted) return;
    
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.panelBackground,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        title: Row(
          children: [
            const Icon(Icons.history, color: Colors.cyan, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(tr('history'), style: const TextStyle(color: Colors.white, fontSize: 14)),
                  Text(
                    row['codigo_material_recibido'] ?? '',
                    style: const TextStyle(color: Colors.white54, fontSize: 10),
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: () => Navigator.pop(ctx),
              icon: const Icon(Icons.close, color: Colors.white54, size: 18),
            ),
          ],
        ),
        content: SizedBox(
          width: 500,
          height: 400,
          child: history.isEmpty
              ? Center(
                  child: Text(tr('no_history'), style: const TextStyle(color: Colors.white38)),
                )
              : ListView.builder(
                  itemCount: history.length,
                  itemBuilder: (ctx, index) {
                    final item = history[index];
                    return _buildHistoryItem(item);
                  },
                ),
        ),
      ),
    );
  }

  Widget _buildHistoryItem(Map<String, dynamic> item) {
    IconData icon;
    Color color;
    
    switch (item['action']) {
      case 'Created':
        icon = Icons.add_circle;
        color = Colors.blue;
        break;
      case 'Released':
        icon = Icons.check_circle;
        color = Colors.green;
        break;
      case 'Scrapped':
        icon = Icons.delete_forever;
        color = Colors.red;
        break;
      case 'Returned':
        icon = Icons.undo;
        color = Colors.orange;
        break;
      case 'CommentAdded':
        icon = Icons.comment;
        color = Colors.cyan;
        break;
      default:
        icon = Icons.info;
        color = Colors.grey;
    }
    
    String dateStr = '';
    if (item['action_at'] != null) {
      try {
        final date = DateTime.parse(item['action_at']);
        dateStr = '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
      } catch (_) {}
    }
    
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      item['action'] ?? '',
                      style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600),
                    ),
                    const Spacer(),
                    Text(dateStr, style: const TextStyle(color: Colors.white38, fontSize: 9)),
                  ],
                ),
                if (item['comments'] != null && item['comments'].toString().isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    item['comments'],
                    style: const TextStyle(color: Colors.white70, fontSize: 10),
                  ),
                ],
                const SizedBox(height: 2),
                Text(
                  item['action_by_name'] ?? '',
                  style: const TextStyle(color: Colors.white38, fontSize: 9),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Agregar comentario
  Future<void> _addComment(Map<String, dynamic> row) async {
    if (!AuthService.canSendToQuarantine) return;
    
    final commentController = TextEditingController();
    
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.panelBackground,
        title: Text(tr('add_comment'), style: const TextStyle(color: Colors.white, fontSize: 14)),
        content: TextField(
          controller: commentController,
          style: const TextStyle(color: Colors.white, fontSize: 12),
          maxLines: 3,
          autofocus: true,
          decoration: InputDecoration(
            hintText: tr('enter_comments'),
            hintStyle: const TextStyle(color: Colors.white38),
            filled: true,
            fillColor: AppColors.gridBackground,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(4)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(tr('cancel'), style: const TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () {
              if (commentController.text.trim().isNotEmpty) {
                Navigator.pop(ctx, commentController.text.trim());
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.cyan),
            child: Text(tr('save')),
          ),
        ],
      ),
    );
    
    commentController.dispose();
    
    if (result != null && mounted) {
      final addResult = await ApiService.addQuarantineComment(
        id: row['id'],
        comments: result,
        userId: AuthService.currentUser?.id ?? 0,
        userName: AuthService.currentUser?.nombreCompleto ?? '',
      );
      
      if (addResult['success'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr('comment_added')), backgroundColor: Colors.green),
        );
      }
    }
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(label, style: const TextStyle(color: Colors.white54, fontSize: 10)),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(color: Colors.white, fontSize: 10)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.keyF &&
            HardwareKeyboard.instance.isControlPressed) {
          _toggleSearchBar();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Container(
        color: AppColors.gridBackground,
        child: Column(
          children: [
            // Barra de búsqueda
            if (_showSearchBar)
              Container(
                height: 36,
                color: AppColors.panelBackground,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  children: [
                    const Icon(Icons.search, size: 16, color: Colors.white54),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        focusNode: _searchFocusNode,
                        style: const TextStyle(color: Colors.white, fontSize: 12),
                        decoration: InputDecoration(
                          hintText: '${tr('search')}... (Ctrl+F)',
                          hintStyle: const TextStyle(color: Colors.white38, fontSize: 11),
                          border: InputBorder.none,
                        ),
                        onChanged: (value) {
                          setState(() {
                            _searchText = value;
                            _applySearch();
                          });
                        },
                      ),
                    ),
                    IconButton(
                      onPressed: _toggleSearchBar,
                      icon: const Icon(Icons.close, size: 16, color: Colors.white54),
                    ),
                  ],
                ),
              ),
            
            // Header
            _buildHeader(),
            
            // Data rows
            Expanded(child: _buildDataRows()),
            
            // Footer
            GridFooter(text: '${tr('total_rows')}: ${_filteredData.length}'),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      height: 32,
      color: AppColors.gridHeader,
      child: Row(
        children: [
          // Columna de acciones
          Container(
            width: 80,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: const Center(
              child: Text(
                'Actions',
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white),
              ),
            ),
          ),
          // Columnas de datos con resize
          ...List.generate(_headers.length, (i) {
            return Expanded(
              flex: getColumnFlex(i),
              child: Stack(
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    decoration: const BoxDecoration(
                      border: Border(left: BorderSide(color: AppColors.border, width: 0.5)),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      _headers[i],
                      style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white),
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
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
        ],
      ),
    );
  }

  Widget _buildDataRows() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: Colors.orange));
    }

    if (_filteredData.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.shield_outlined, size: 48, color: Colors.white.withOpacity(0.1)),
            const SizedBox(height: 8),
            Text(
              tr('no_items_in_quarantine'),
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
          onDoubleTap: () => _showDispositionDialog(row),
          child: Container(
            height: 28,
            decoration: BoxDecoration(
              color: isSelected
                  ? Colors.orange.withOpacity(0.2)
                  : isEven
                      ? AppColors.gridBackground
                      : AppColors.gridRowAlt,
              border: Border(
                bottom: const BorderSide(color: AppColors.border, width: 0.5),
                left: isSelected
                    ? const BorderSide(color: Colors.orange, width: 3)
                    : BorderSide.none,
              ),
            ),
            child: Row(
              children: [
                // Columna de acciones
                SizedBox(
                  width: 80,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Solo Calidad Supervisor puede procesar/liberar
                      if (AuthService.canWriteQuarantine)
                        _buildActionIcon(Icons.edit, Colors.green, () => _showDispositionDialog(row), tr('process')),
                      // Solo Calidad puede agregar comentarios
                      if (AuthService.canSendToQuarantine)
                        _buildActionIcon(Icons.comment, Colors.cyan, () => _addComment(row), tr('comment')),
                      // Todos pueden ver historial
                      _buildActionIcon(Icons.history, Colors.blue, () => _showItemHistory(row), tr('history')),
                    ],
                  ),
                ),
                // Columnas de datos
                ...List.generate(_fields.length, (i) {
                  final field = _fields[i];
                  var value = row[field]?.toString() ?? '';
                  
                  // Formatear fecha
                  if (field == 'created_at' && value.isNotEmpty) {
                    try {
                      final date = DateTime.parse(value);
                      value = '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
                    } catch (_) {}
                  }
                  
                  return Expanded(
                    flex: getColumnFlex(i),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      decoration: const BoxDecoration(
                        border: Border(left: BorderSide(color: AppColors.border, width: 0.5)),
                      ),
                      child: Text(
                        value,
                        style: const TextStyle(fontSize: 10, color: Colors.white),
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildActionIcon(IconData icon, Color color, VoidCallback onTap, String tooltip) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(icon, size: 14, color: color),
        ),
      ),
    );
  }
}
