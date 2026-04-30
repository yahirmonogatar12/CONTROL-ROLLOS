import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_warehousing_flutter/core/localization/app_translations.dart';
import 'package:material_warehousing_flutter/core/theme/app_colors.dart';
import 'package:material_warehousing_flutter/core/widgets/grid_footer.dart';
import 'package:material_warehousing_flutter/core/services/api_service.dart';
import 'package:material_warehousing_flutter/core/widgets/resizable_grid_header.dart';

// ============================================
// Quarantine History Grid - Historial de Cuarentena
// ============================================
class QuarantineHistoryGrid extends StatefulWidget {
  final LanguageProvider languageProvider;

  const QuarantineHistoryGrid({
    super.key,
    required this.languageProvider,
  });

  @override
  State<QuarantineHistoryGrid> createState() => QuarantineHistoryGridState();
}

class QuarantineHistoryGridState extends State<QuarantineHistoryGrid> with ResizableColumnsMixin {
  List<Map<String, dynamic>> _data = [];
  List<Map<String, dynamic>> _filteredData = [];
  bool _isLoading = true;
  int _selectedIndex = -1;
  
  // Filtro de fechas
  DateTime _startDate = DateTime.now().subtract(const Duration(days: 30));
  DateTime _endDate = DateTime.now();
  
  // Búsqueda
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  bool _showSearchBar = false;
  String _searchText = '';

  // Campos del grid
  final List<String> _fields = [
    'codigo_material_recibido', 'part_number', 'cantidad', 
    'reason', 'status', 'created_by_name', 'created_at', 
    'closed_by_name', 'closed_at'
  ];

  String tr(String key) => widget.languageProvider.tr(key);

  List<String> get _headers => [
    tr('material_code'),
    tr('part_number'),
    tr('quantity'),
    tr('reason'),
    tr('status'),
    tr('created_by'),
    tr('created_at'),
    tr('closed_by'),
    tr('closed_at'),
  ];

  @override
  void initState() {
    super.initState();
    initColumnFlex(9, 'quarantine_history', defaultFlexValues: [2.0, 2.0, 1.0, 3.0, 1.5, 2.0, 2.0, 2.0, 2.0]);
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
      final startStr = '${_startDate.year}-${_startDate.month.toString().padLeft(2, '0')}-${_startDate.day.toString().padLeft(2, '0')}';
      final endStr = '${_endDate.year}-${_endDate.month.toString().padLeft(2, '0')}-${_endDate.day.toString().padLeft(2, '0')}';
      
      final data = await ApiService.getQuarantineHistory(
        fechaInicio: startStr,
        fechaFin: endStr,
      );
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

  Future<void> _selectStartDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() => _startDate = picked);
    }
  }

  Future<void> _selectEndDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _endDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked != null) {
      setState(() => _endDate = picked);
    }
  }

  // Mostrar historial detallado del item
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

  Color _getStatusColor(String? status) {
    switch (status) {
      case 'Released':
        return Colors.green;
      case 'Scrapped':
        return Colors.red;
      case 'Returned':
        return Colors.orange;
      default:
        return Colors.grey;
    }
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
            // Barra de filtros de fecha
            _buildDateFilterBar(),
            
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
                  Text(formatDate(_startDate), style: const TextStyle(color: Colors.white, fontSize: 12)),
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
                  Text(formatDate(_endDate), style: const TextStyle(color: Colors.white, fontSize: 12)),
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
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              minimumSize: const Size(0, 28),
            ),
          ),
          
          const Spacer(),
          
          // Hint Ctrl+F
          Text(
            'Ctrl+F',
            style: TextStyle(fontSize: 10, color: Colors.white.withOpacity(0.3)),
          ),
          const SizedBox(width: 8),
        ],
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
            width: 50,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: const Center(
              child: Icon(Icons.history, size: 14, color: Colors.white54),
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
                      style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.white),
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
          onDoubleTap: () => _showItemHistory(row),
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
                  width: 50,
                  child: IconButton(
                    onPressed: () => _showItemHistory(row),
                    icon: const Icon(Icons.history, size: 14, color: Colors.cyan),
                    tooltip: tr('view_history'),
                    padding: EdgeInsets.zero,
                  ),
                ),
                // Columnas de datos
                ...List.generate(_fields.length, (i) {
                  final field = _fields[i];
                  var value = row[field]?.toString() ?? '';
                  
                  // Formatear fechas
                  if ((field == 'created_at' || field == 'closed_at') && value.isNotEmpty) {
                    try {
                      final date = DateTime.parse(value);
                      value = '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
                    } catch (_) {}
                  }
                  
                  // Widget especial para status
                  Widget cellContent;
                  if (field == 'status') {
                    cellContent = Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: _getStatusColor(value).withOpacity(0.2),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        value,
                        style: TextStyle(
                          fontSize: 9,
                          color: _getStatusColor(value),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    );
                  } else {
                    cellContent = Text(
                      value,
                      style: const TextStyle(fontSize: 9, color: Colors.white),
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                    );
                  }
                  
                  return Expanded(
                    flex: getColumnFlex(i),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      decoration: const BoxDecoration(
                        border: Border(left: BorderSide(color: AppColors.border, width: 0.5)),
                      ),
                      child: Center(child: cellContent),
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
}
