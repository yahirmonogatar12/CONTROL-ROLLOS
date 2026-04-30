import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:material_warehousing_flutter/core/localization/app_translations.dart';
import 'package:material_warehousing_flutter/core/services/api_service.dart';
import 'package:material_warehousing_flutter/core/services/auth_service.dart';
import 'package:material_warehousing_flutter/core/theme/app_colors.dart';

class WarehouseOutgoingConfirmPanel extends StatefulWidget {
  final LanguageProvider languageProvider;
  final VoidCallback? onConfirmed;
  final ValueChanged<int>? onCountChanged;

  const WarehouseOutgoingConfirmPanel({
    super.key,
    required this.languageProvider,
    this.onConfirmed,
    this.onCountChanged,
  });

  @override
  State<WarehouseOutgoingConfirmPanel> createState() => WarehouseOutgoingConfirmPanelState();
}

class WarehouseOutgoingConfirmPanelState extends State<WarehouseOutgoingConfirmPanel> {
  List<Map<String, dynamic>> _pending = [];
  List<Map<String, dynamic>> _groups = [];
  List<Map<String, dynamic>> _rejected = [];
  List<Map<String, dynamic>> _rejectedGroups = [];
  bool _isLoading = true;
  bool _isLoadingHistory = false;
  bool _isExpanded = true;
  int _selectedTab = 0; // 0 = pendientes, 1 = historial
  String? _startDate;
  String? _errorMessage;
  String? _historyError;
  final Set<String> _confirmingParts = {};
  final Set<String> _rejectingParts = {};
  final Map<String, Set<int>> _selectedByPart = {};
  final Map<String, TextEditingController> _ubicacionControllers = {};
  final Map<String, int> _lastSelectedIndex = {}; // Para Shift+Click
  final Map<int, String> _assignedLocations = {}; // Ubicaciones asignadas por rowId
  
  // Filtro de fechas - últimos 3 días por defecto
  late DateTime _filterStartDate;
  late DateTime _filterEndDate;
  
  // Buscador de número de parte
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  String tr(String key) => widget.languageProvider.tr(key);

  @override
  void initState() {
    super.initState();
    // Inicializar con rango de últimos 3 días
    final now = DateTime.now();
    _filterEndDate = now;
    _filterStartDate = now.subtract(const Duration(days: 3));
    loadPending();
  }

  @override
  void dispose() {
    _searchController.dispose();
    for (final controller in _ubicacionControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  String _formatDateForApi(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  Future<void> loadPending() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final result = await ApiService.getPendingWarehouseOutgoing(
      fechaInicio: _formatDateForApi(_filterStartDate),
      fechaFin: _formatDateForApi(_filterEndDate),
    );
    if (!mounted) return;

    if (result['success'] == false) {
      setState(() {
        _pending = [];
        _groups = [];
        _selectedByPart.clear();
        _isLoading = false;
        _errorMessage = result['error']?.toString() ?? 'Error';
      });
      widget.onCountChanged?.call(0);
      return;
    }

    final data = (result['data'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    setState(() {
      _pending = data;
      _groups = _buildGroups(data);
      _startDate = result['start_date']?.toString();
      _selectedByPart.clear();
      _isLoading = false;
    });
    widget.onCountChanged?.call(_groups.length);
  }

  Future<void> _loadRejected({bool force = false}) async {
    if (_isLoadingHistory) return;
    if (!force && _rejected.isNotEmpty) return;

    setState(() {
      _isLoadingHistory = true;
      _historyError = null;
    });

    final result = await ApiService.getRejectedWarehouseOutgoing();
    if (!mounted) return;

    if (result['success'] == false) {
      setState(() {
        _rejected = [];
        _rejectedGroups = [];
        _isLoadingHistory = false;
        _historyError = result['error']?.toString() ?? 'Error';
      });
      return;
    }

    final data = (result['data'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    setState(() {
      _rejected = data;
      _rejectedGroups = _buildRejectedGroups(data);
      _isLoadingHistory = false;
    });
  }

  Future<void> refresh() async {
    await loadPending();
  }

  Future<void> _refreshHistory() async {
    await _loadRejected(force: true);
  }

  TextEditingController _getUbicacionController(String partNumber) {
    return _ubicacionControllers.putIfAbsent(partNumber, () => TextEditingController());
  }

  /// Asigna la ubicación del campo de texto a todos los seleccionados
  void _assignLocationToSelected(String partNumber, VoidCallback onUpdated, {List<String> expectedLocations = const []}) {
    final ubicacion = _getUbicacionController(partNumber).text.trim();
    if (ubicacion.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(tr('destination_required')),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // Validar que la ubicación coincida con ALGUNA de las esperadas
    if (expectedLocations.isNotEmpty) {
      final matches = expectedLocations.any(
        (loc) => loc.toUpperCase() == ubicacion.toUpperCase()
      );
      if (!matches) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${tr('location_mismatch')}: ${expectedLocations.join(', ')}'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
    }
    
    final selected = _selectedByPart[partNumber] ?? {};
    if (selected.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(tr('no_items_selected')),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    
    for (final id in selected) {
      _assignedLocations[id] = ubicacion;
    }
    
    // Limpiar selección y campo después de asignar
    _selectedByPart[partNumber]?.clear();
    _getUbicacionController(partNumber).clear();
    
    onUpdated();
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${tr('location_assigned')}: $ubicacion (${selected.length})'),
        backgroundColor: Colors.blue,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  /// Obtiene la ubicación asignada a un rowId
  String? _getAssignedLocation(int rowId) {
    return _assignedLocations[rowId];
  }

  /// Cuenta cuántos items tienen ubicación asignada
  int _countWithLocation(String partNumber) {
    final items = _pending.where((r) => r['numero_parte'] == partNumber).toList();
    int count = 0;
    for (final item in items) {
      final rowId = _rowId(item);
      if (rowId != null && _assignedLocations.containsKey(rowId)) {
        count++;
      }
    }
    return count;
  }

  Future<bool> _confirmSelected(String partNumber) async {
    if (_confirmingParts.contains(partNumber)) return false;
    final ids = _selectedByPart[partNumber]?.toList() ?? [];
    if (ids.isEmpty) return false;

    // Validar que todos los seleccionados tengan ubicación asignada
    final idsWithoutLocation = ids.where((id) => !_assignedLocations.containsKey(id) || _assignedLocations[id]!.isEmpty).toList();
    if (idsWithoutLocation.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${tr('destination_required')} (${idsWithoutLocation.length} ${tr('pending')})'),
          backgroundColor: Colors.red,
        ),
      );
      return false;
    }

    setState(() => _confirmingParts.add(partNumber));

    final currentUser = AuthService.currentUser;
    final usuario = currentUser?.nombreCompleto ?? currentUser?.username ?? 'Unknown';
    
    // Crear mapa de ubicaciones por ID para enviar en un solo batch
    final Map<int, String> ubicacionesPorId = {};
    for (final id in ids) {
      ubicacionesPorId[id] = _assignedLocations[id]!;
    }
    
    // Enviar todo en una sola llamada batch
    final result = await ApiService.confirmWarehouseOutgoingByIds(
      ids: ids,
      usuario: usuario,
      ubicacionesPorId: ubicacionesPorId,
    );
    
    int totalConfirmed = 0;
    int totalSkipped = 0;
    String? lastError;
    
    if (result['success'] == true) {
      totalConfirmed = (result['confirmed'] as int?) ?? ids.length;
      totalSkipped = (result['skipped'] as int?) ?? 0;
      // Limpiar ubicaciones asignadas de los confirmados
      for (final id in ids) {
        _assignedLocations.remove(id);
      }
    } else {
      lastError = result['error']?.toString();
    }

    if (!mounted) return false;
    setState(() => _confirmingParts.remove(partNumber));

    if (totalConfirmed > 0) {
      // Limpiar el controlador después de confirmar exitosamente
      _getUbicacionController(partNumber).clear();
      await loadPending();
      widget.onConfirmed?.call();

      String message = '${tr('warehouse_outgoing_confirmed')} ($totalConfirmed / ${ids.length})';
      if (totalSkipped > 0) {
        message += ' - ${tr('skipped')}: $totalSkipped';
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), backgroundColor: Colors.green),
      );
      return true;
    } else {
      final error = lastError ?? tr('warehouse_outgoing_confirm_error');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error), backgroundColor: Colors.red),
      );
      return false;
    }
  }

  Future<bool> _rejectSelected(String partNumber) async {
    if (_rejectingParts.contains(partNumber)) return false;

    final reasonController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.panelBackground,
        title: Row(
          children: [
            const Icon(Icons.cancel, color: Colors.red, size: 22),
            const SizedBox(width: 8),
            Text(tr('reject'), style: const TextStyle(color: Colors.white)),
          ],
        ),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                tr('rejection_reason_prompt'),
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: reasonController,
                maxLines: 3,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: tr('enter_rejection_reason'),
                  hintStyle: const TextStyle(color: Colors.white38),
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
            onPressed: () => Navigator.pop(context, false),
            child: Text(tr('cancel'), style: const TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () {
              if (reasonController.text.trim().isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(tr('reason_required')), backgroundColor: Colors.orange),
                );
                return;
              }
              Navigator.pop(context, true);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: Text(tr('reject')),
          ),
        ],
      ),
    );

    final motivo = reasonController.text.trim();
    reasonController.dispose();

    if (confirmed != true || motivo.isEmpty) return false;

    final ids = _selectedByPart[partNumber]?.toList() ?? [];
    if (ids.isEmpty) return false;

    setState(() => _rejectingParts.add(partNumber));

    final currentUser = AuthService.currentUser;
    final usuario = currentUser?.nombreCompleto ?? currentUser?.username ?? 'Unknown';
    final result = await ApiService.rejectWarehouseOutgoingByIds(
      ids: ids,
      motivo: motivo,
      usuario: usuario,
    );

    if (!mounted) return false;
    setState(() => _rejectingParts.remove(partNumber));

    if (result['success'] == true) {
      await loadPending();
      await _loadRejected(force: true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr('rejected')), backgroundColor: Colors.red),
      );
      return true;
    } else {
      final error = result['error']?.toString() ?? tr('warehouse_outgoing_confirm_error');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error), backgroundColor: Colors.red),
      );
      return false;
    }
  }

  num _parseQty(dynamic value) {
    if (value == null) return 0;
    if (value is num) return value;
    return num.tryParse(value.toString()) ?? 0;
  }

  int? _rowId(Map<String, dynamic> row) {
    final raw = row['id'];
    if (raw is int) return raw;
    return int.tryParse(raw?.toString() ?? '');
  }

  Set<int> _selectedForPart(String partNumber) {
    return _selectedByPart.putIfAbsent(partNumber, () => <int>{});
  }

  void _toggleSelectRow(String partNumber, int rowId, [VoidCallback? onUpdated]) {
    setState(() {
      final selected = _selectedForPart(partNumber);
      if (selected.contains(rowId)) {
        selected.remove(rowId);
      } else {
        selected.add(rowId);
      }
    });
    onUpdated?.call();
  }

  // Selección con Shift+Click para rango de filas
  void _handleRowClick(String partNumber, int index, int rowId, List<Map<String, dynamic>> items, bool isShiftPressed, [VoidCallback? onUpdated]) {
    setState(() {
      final selected = _selectedForPart(partNumber);
      
      if (isShiftPressed && _lastSelectedIndex.containsKey(partNumber)) {
        // Shift+Click: seleccionar rango
        final lastIndex = _lastSelectedIndex[partNumber]!;
        final startIdx = lastIndex < index ? lastIndex : index;
        final endIdx = lastIndex < index ? index : lastIndex;
        
        for (int i = startIdx; i <= endIdx; i++) {
          final itemRowId = _rowId(items[i]);
          if (itemRowId != null) {
            selected.add(itemRowId);
          }
        }
      } else {
        // Click normal: toggle individual
        if (selected.contains(rowId)) {
          selected.remove(rowId);
        } else {
          selected.add(rowId);
        }
      }
      
      // Guardar el último índice seleccionado
      _lastSelectedIndex[partNumber] = index;
    });
    onUpdated?.call();
  }

  void _toggleSelectAll(String partNumber, List<Map<String, dynamic>> items, [VoidCallback? onUpdated]) {
    setState(() {
      final selected = _selectedForPart(partNumber);
      final ids = items
          .map(_rowId)
          .whereType<int>()
          .toList();
      if (selected.length == ids.length) {
        selected.clear();
      } else {
        selected
          ..clear()
          ..addAll(ids);
      }
    });
    onUpdated?.call();
  }


  List<Map<String, dynamic>> _buildGroups(List<Map<String, dynamic>> rows) {
    final Map<String, Map<String, dynamic>> groups = {};
    for (final row in rows) {
      final partNumber = row['numero_parte']?.toString() ?? '-';
      final qty = _parseQty(row['cantidad_salida']);
      if (!groups.containsKey(partNumber)) {
        groups[partNumber] = {
          'numero_parte': partNumber,
          'total_qty': 0,
          'count': 0,
          'items': <Map<String, dynamic>>[],
          'latest_date': row['fecha_salida']?.toString(),
        };
      }
      final group = groups[partNumber]!;
      group['total_qty'] = (group['total_qty'] as num) + qty;
      group['count'] = (group['count'] as int) + 1;
      (group['items'] as List<Map<String, dynamic>>).add(row);

      final latestDate = group['latest_date']?.toString();
      final currentDate = row['fecha_salida']?.toString();
      if (latestDate == null || (currentDate != null && currentDate.compareTo(latestDate) > 0)) {
        group['latest_date'] = currentDate;
      }
    }
    final list = groups.values.toList();
    list.sort((a, b) => (b['latest_date']?.toString() ?? '').compareTo(a['latest_date']?.toString() ?? ''));
    return list;
  }

  List<Map<String, dynamic>> _buildRejectedGroups(List<Map<String, dynamic>> rows) {
    final Map<String, Map<String, dynamic>> groups = {};
    for (final row in rows) {
      final partNumber = row['numero_parte']?.toString() ?? '-';
      final qty = _parseQty(row['cantidad_salida']);
      if (!groups.containsKey(partNumber)) {
        groups[partNumber] = {
          'numero_parte': partNumber,
          'total_qty': 0,
          'count': 0,
          'latest_rejected_at': row['rechazado_at']?.toString(),
          'rechazado_por': row['rechazado_por']?.toString(),
          'rechazado_motivo': row['rechazado_motivo']?.toString(),
        };
      }
      final group = groups[partNumber]!;
      group['total_qty'] = (group['total_qty'] as num) + qty;
      group['count'] = (group['count'] as int) + 1;

      final latest = group['latest_rejected_at']?.toString();
      final current = row['rechazado_at']?.toString();
      if (latest == null || (current != null && current.compareTo(latest) > 0)) {
        group['latest_rejected_at'] = current;
        group['rechazado_por'] = row['rechazado_por']?.toString();
        group['rechazado_motivo'] = row['rechazado_motivo']?.toString();
      }
    }
    final list = groups.values.toList();
    list.sort((a, b) => (b['latest_rejected_at']?.toString() ?? '').compareTo(a['latest_rejected_at']?.toString() ?? ''));
    return list;
  }

  String _formatDateTime(String? dateStr) {
    if (dateStr == null || dateStr.isEmpty) return '-';
    try {
      final date = DateTime.parse(dateStr);
      return DateFormat('dd/MM/yyyy HH:mm').format(date);
    } catch (_) {
      return dateStr;
    }
  }

  String _formatDate(String? dateStr) {
    if (dateStr == null || dateStr.isEmpty) return '-';
    try {
      final date = DateTime.parse(dateStr);
      return DateFormat('dd/MM/yyyy').format(date);
    } catch (_) {
      return dateStr;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      constraints: const BoxConstraints(maxHeight: 420),
      decoration: BoxDecoration(
        color: AppColors.panelBackground,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.headerTab.withOpacity(0.6)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: () => setState(() => _isExpanded = !_isExpanded),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.gridHeader,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(6),
                  topRight: const Radius.circular(6),
                  bottomLeft: Radius.circular(_isExpanded ? 0 : 6),
                  bottomRight: Radius.circular(_isExpanded ? 0 : 6),
                ),
              ),
                child: Row(
                  children: [
                    const Icon(Icons.local_shipping_outlined, color: Colors.white70, size: 18),
                    const SizedBox(width: 8),
                    Text(
                      tr('warehouse_outgoing_pending'),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                  ),
                  if (_groups.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.headerTab,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${_groups.length}',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11),
                      ),
                    ),
                  ],
                  const Spacer(),
                  Icon(
                    _isExpanded ? Icons.expand_less : Icons.expand_more,
                    color: Colors.white70,
                    size: 20,
                  ),
                ],
              ),
            ),
          ),
          if (_isExpanded) ...[
            // Filtro de fechas
            _buildDateFilter(),
            _buildTabs(),
            Flexible(
              child: _selectedTab == 0 ? _buildPendingList() : _buildHistoryList(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDateFilter() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: const BoxDecoration(
        color: AppColors.panelBackground,
        border: Border(bottom: BorderSide(color: AppColors.border, width: 0.5)),
      ),
      child: Row(
        children: [
          const Icon(Icons.date_range, color: Colors.white54, size: 16),
          const SizedBox(width: 8),
          // Fecha inicio
          InkWell(
            onTap: () => _selectDate(isStart: true),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.fieldBackground,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: AppColors.border),
              ),
              child: Text(
                _formatDateDisplay(_filterStartDate),
                style: const TextStyle(color: Colors.white70, fontSize: 11),
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 6),
            child: Text('~', style: TextStyle(color: Colors.white54)),
          ),
          // Fecha fin
          InkWell(
            onTap: () => _selectDate(isStart: false),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.fieldBackground,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: AppColors.border),
              ),
              child: Text(
                _formatDateDisplay(_filterEndDate),
                style: const TextStyle(color: Colors.white70, fontSize: 11),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Botón buscar
          InkWell(
            onTap: loadPending,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.headerTab.withOpacity(0.3),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.search, color: Colors.white70, size: 14),
                  const SizedBox(width: 4),
                  Text(tr('search'), style: const TextStyle(color: Colors.white70, fontSize: 11)),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Botón refresh
          InkWell(
            onTap: () {
              final now = DateTime.now();
              setState(() {
                _filterEndDate = now;
                _filterStartDate = now.subtract(const Duration(days: 3));
              });
              loadPending();
            },
            child: const Icon(Icons.refresh, color: Colors.white54, size: 16),
          ),
          const Spacer(),
          // Buscador de número de parte
          SizedBox(
            width: 180,
            height: 28,
            child: TextField(
              controller: _searchController,
              style: const TextStyle(color: Colors.white, fontSize: 11),
              decoration: InputDecoration(
                hintText: tr('search_part_number'),
                hintStyle: const TextStyle(color: Colors.white38, fontSize: 10),
                filled: true,
                fillColor: AppColors.fieldBackground,
                contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                prefixIcon: const Icon(Icons.search, color: Colors.white54, size: 14),
                prefixIconConstraints: const BoxConstraints(minWidth: 30),
                suffixIcon: _searchQuery.isNotEmpty
                    ? InkWell(
                        onTap: () {
                          setState(() {
                            _searchController.clear();
                            _searchQuery = '';
                          });
                        },
                        child: const Icon(Icons.clear, color: Colors.white54, size: 14),
                      )
                    : null,
                suffixIconConstraints: const BoxConstraints(minWidth: 30),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(4),
                  borderSide: const BorderSide(color: AppColors.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(4),
                  borderSide: const BorderSide(color: AppColors.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(4),
                  borderSide: const BorderSide(color: Colors.cyan, width: 1),
                ),
              ),
              onChanged: (value) {
                setState(() {
                  _searchQuery = value;
                });
              },
            ),
          ),
        ],
      ),
    );
  }

  String _formatDateDisplay(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }

  Future<void> _selectDate({required bool isStart}) async {
    final initial = isStart ? _filterStartDate : _filterEndDate;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2024),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.dark(
              primary: AppColors.headerTab,
              surface: AppColors.panelBackground,
            ),
          ),
          child: child!,
        );
      },
    );
    
    if (picked != null) {
      setState(() {
        if (isStart) {
          _filterStartDate = picked;
          // Si fecha inicio es mayor que fin, ajustar
          if (_filterStartDate.isAfter(_filterEndDate)) {
            _filterEndDate = _filterStartDate;
          }
        } else {
          _filterEndDate = picked;
          // Si fecha fin es menor que inicio, ajustar
          if (_filterEndDate.isBefore(_filterStartDate)) {
            _filterStartDate = _filterEndDate;
          }
        }
      });
      loadPending();
    }
  }
  Widget _buildTabs() {
    return Container(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          _buildTab(0, tr('pending'), _groups.length),
          _buildTab(1, tr('history'), _rejectedGroups.length),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.refresh, size: 16, color: Colors.white54),
            onPressed: _selectedTab == 0 ? refresh : _refreshHistory,
            padding: const EdgeInsets.all(8),
            constraints: const BoxConstraints(),
            tooltip: tr('refresh'),
          ),
          const SizedBox(width: 6),
        ],
      ),
    );
  }

  Widget _buildTab(int index, String title, int count) {
    final isSelected = _selectedTab == index;
    return InkWell(
      onTap: () {
        setState(() => _selectedTab = index);
        if (index == 1) {
          _loadRejected();
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: isSelected ? AppColors.headerTab : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              style: TextStyle(
                color: isSelected ? AppColors.headerTab : Colors.white54,
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
            if (count > 0) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: isSelected ? AppColors.headerTab : Colors.white24,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 10,
                    color: isSelected ? Colors.white : Colors.white70,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildPendingList() {
    if (_isLoading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    if (_errorMessage != null) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.red),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _errorMessage!,
                style: const TextStyle(color: Colors.red),
              ),
            ),
          ],
        ),
      );
    }

    if (_groups.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.check_circle_outline, color: Colors.green, size: 32),
              const SizedBox(height: 8),
              Text(
                tr('no_pending_warehouse_outgoing'),
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ],
          ),
        ),
      );
    }

    // Filtrar grupos por búsqueda
    final filteredGroups = _searchQuery.isEmpty
        ? _groups
        : _groups.where((g) {
            final partNumber = g['numero_parte']?.toString().toUpperCase() ?? '';
            return partNumber.contains(_searchQuery.toUpperCase());
          }).toList();

    if (filteredGroups.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _searchQuery.isEmpty ? tr('no_pending_warehouse_outgoing') : tr('no_results'),
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 6),
      itemCount: filteredGroups.length,
      separatorBuilder: (_, __) => const SizedBox(height: 6),
      itemBuilder: (context, index) {
        final group = filteredGroups[index];
        return _buildGroupItem(group);
      },
    );
  }

  Widget _buildHistoryList() {
    if (_isLoadingHistory) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    if (_historyError != null) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.red),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _historyError!,
                style: const TextStyle(color: Colors.red),
              ),
            ),
          ],
        ),
      );
    }

    if (_rejectedGroups.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.history, color: Colors.white24, size: 32),
              const SizedBox(height: 8),
              Text(
                tr('no_rejected_warehouse_outgoing'),
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 6),
      itemCount: _rejectedGroups.length,
      separatorBuilder: (_, __) => const SizedBox(height: 6),
      itemBuilder: (context, index) {
        final group = _rejectedGroups[index];
        return _buildRejectedItem(group);
      },
    );
  }

  Widget _buildGroupItem(Map<String, dynamic> group) {
    final partNumber = group['numero_parte']?.toString() ?? '-';
    final totalQty = group['total_qty'] as num? ?? 0;
    final count = group['count'] as int? ?? 0;
    final items = group['items'] as List<Map<String, dynamic>>? ?? [];
    final sample = items.isNotEmpty ? items.first : <String, dynamic>{};
    final spec = sample['especificacion_material']?.toString()
        ?? sample['material_especificacion']?.toString()
        ?? '';
    final expectedLocationStr = sample['ubicacion_rollos']?.toString() ?? '';
    final expectedLocations = expectedLocationStr.isNotEmpty
        ? expectedLocationStr.split(',').map((v) => v.trim()).where((v) => v.isNotEmpty).toList()
        : <String>[];
    return InkWell(
      onDoubleTap: () => _openPartDialog(
        partNumber: partNumber,
        items: items,
        totalQty: totalQty,
        count: count,
        expectedLocations: expectedLocations,
      ),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.gridBackground,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: AppColors.border.withOpacity(0.6)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Row(
                children: [
                  Text(
                    partNumber,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  if (spec.isNotEmpty) ...[
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        spec,
                        style: const TextStyle(color: Colors.white60, fontSize: 12),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            _buildChip('${tr('qty')}: $totalQty', Colors.green),
          ],
        ),
      ),
    );
  }

  Future<void> _openPartDialog({
    required String partNumber,
    required List<Map<String, dynamic>> items,
    required num totalQty,
    required int count,
    List<String> expectedLocations = const [],
  }) async {
    _selectedForPart(partNumber);
    await showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final selected = _selectedByPart[partNumber] ?? <int>{};
            final selectedCount = selected.length;
            final allSelected = items.isNotEmpty && selectedCount == items.length;
            final isConfirming = _confirmingParts.contains(partNumber);
            final isRejecting = _rejectingParts.contains(partNumber);

            return Dialog(
              backgroundColor: AppColors.panelBackground,
              insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
              child: SizedBox(
                width: 980,
                height: 560,
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: const BoxDecoration(
                        color: AppColors.gridHeader,
                        borderRadius: BorderRadius.only(
                          topLeft: Radius.circular(6),
                          topRight: Radius.circular(6),
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              partNumber,
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                            ),
                          ),
                          _buildChip('${tr('qty')}: $totalQty', Colors.green),
                          const SizedBox(width: 6),
                          _buildChip('${tr('records')}: $count', Colors.blueGrey),
                          Builder(builder: (ctx) {
                            final withLoc = _countWithLocation(partNumber);
                            if (withLoc > 0) {
                              return Padding(
                                padding: const EdgeInsets.only(left: 6),
                                child: _buildChip('${tr('assigned')}: $withLoc', Colors.blue),
                              );
                            }
                            return const SizedBox.shrink();
                          }),
                          if (selectedCount > 0) ...[
                            const SizedBox(width: 10),
                            Text(
                              '${tr('selected')}: $selectedCount',
                              style: const TextStyle(color: Colors.white70, fontSize: 11),
                            ),
                          ],
                        ],
                      ),
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: _buildGroupTableDialog(partNumber, items, selected, setModalState),
                      ),
                    ),
                    // Campo de ubicación destino
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      child: Row(
                        children: [
                          Text(
                            tr('destination_location'),
                            style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: SizedBox(
                              height: 38,
                              child: TextField(
                                controller: _getUbicacionController(partNumber),
                                style: const TextStyle(color: Colors.cyan, fontSize: 14),
                                decoration: InputDecoration(
                                  hintText: tr('scan_destination'),
                                  hintStyle: const TextStyle(color: Colors.white38, fontSize: 12),
                                  filled: true,
                                  fillColor: AppColors.fieldBackground,
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                  prefixIcon: const Icon(Icons.qr_code_scanner, color: Colors.cyan, size: 18),
                                  prefixIconConstraints: const BoxConstraints(minWidth: 40),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(4),
                                    borderSide: const BorderSide(color: AppColors.border),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(4),
                                    borderSide: const BorderSide(color: AppColors.border),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(4),
                                    borderSide: const BorderSide(color: Colors.cyan, width: 1.5),
                                  ),
                                ),
                                onChanged: (_) => setModalState(() {}),
                                onSubmitted: (_) => _assignLocationToSelected(partNumber, () => setModalState(() {}), expectedLocations: expectedLocations),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton.icon(
                            onPressed: (selectedCount == 0 || _getUbicacionController(partNumber).text.trim().isEmpty)
                                ? null
                                : () => _assignLocationToSelected(partNumber, () => setModalState(() {}), expectedLocations: expectedLocations),
                            icon: const Icon(Icons.assignment_turned_in, size: 16),
                            label: Text(tr('assign'), style: const TextStyle(fontSize: 12)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue,
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Mostrar ubicaciones esperadas si existen
                    if (expectedLocations.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        child: Row(
                          children: [
                            const Icon(Icons.info_outline, color: Colors.amber, size: 16),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Wrap(
                                spacing: 4,
                                runSpacing: 2,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  Text(
                                    '${tr('expected_location')}:',
                                    style: const TextStyle(color: Colors.amber, fontSize: 12),
                                  ),
                                  ...expectedLocations.map((loc) => Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.amber.withOpacity(0.15),
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border.all(color: Colors.amber.withOpacity(0.4)),
                                    ),
                                    child: Text(
                                      loc,
                                      style: const TextStyle(fontSize: 11, color: Colors.amber, fontWeight: FontWeight.w600),
                                    ),
                                  )),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      child: Row(
                        children: [
                          TextButton.icon(
                            onPressed: items.isEmpty ? null : () => _toggleSelectAll(partNumber, items, () => setModalState(() {})),
                            icon: Icon(allSelected ? Icons.clear_all : Icons.select_all, size: 16),
                            label: Text(allSelected ? tr('clear_selection') : tr('select_all'), style: const TextStyle(fontSize: 12)),
                            style: TextButton.styleFrom(
                              foregroundColor: Colors.white70,
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                            ),
                          ),
                          const Spacer(),
                          TextButton.icon(
                            onPressed: (selectedCount == 0 || isRejecting || isConfirming)
                                ? null
                                : () async {
                                    final ok = await _rejectSelected(partNumber);
                                    if (ok && mounted) Navigator.pop(context);
                                  },
                            icon: isRejecting
                                ? const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : const Icon(Icons.close, size: 16),
                            label: Text(tr('reject_selected'), style: const TextStyle(fontSize: 12)),
                            style: TextButton.styleFrom(
                              foregroundColor: Colors.red,
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Builder(builder: (ctx) {
                            final withLoc = _countWithLocation(partNumber);
                            return ElevatedButton.icon(
                              onPressed: (withLoc == 0 || isConfirming || isRejecting)
                                  ? null
                                  : () async {
                                      // Seleccionar todos los que tienen ubicación asignada para confirmar
                                      _selectedByPart[partNumber] = items
                                          .where((item) {
                                            final rowId = _rowId(item);
                                            return rowId != null && _assignedLocations.containsKey(rowId);
                                          })
                                          .map((item) => _rowId(item)!)
                                          .toSet();
                                      setModalState(() {});
                                      final ok = await _confirmSelected(partNumber);
                                      if (ok && mounted) Navigator.pop(context);
                                    },
                              icon: isConfirming
                                  ? const SizedBox(
                                      width: 14,
                                      height: 14,
                                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                    )
                                  : const Icon(Icons.check, size: 16),
                              label: Text('${tr('confirm_selected')} ($withLoc)', style: const TextStyle(fontSize: 12)),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green,
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              ),
                            );
                          }),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildGroupTableDialog(
    String partNumber,
    List<Map<String, dynamic>> items,
    Set<int> selected,
    void Function(VoidCallback fn) setModalState,
  ) {
    final columns = [
      {'key': 'codigo_material_recibido', 'label': tr('label_code'), 'flex': 3},
      {'key': 'numero_lote', 'label': tr('lot_number'), 'flex': 2},
      {'key': 'cantidad_salida', 'label': tr('qty'), 'flex': 1},
      {'key': 'fecha_salida', 'label': tr('outgoing_date'), 'flex': 2},
      {'key': 'depto_salida', 'label': tr('department'), 'flex': 2},
      {'key': 'proceso_salida', 'label': tr('process'), 'flex': 2},
    ];

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.border.withOpacity(0.6)),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        children: [
          _buildTableHeader(columns),
          Expanded(
            child: items.isEmpty
                ? Center(
                    child: Text(
                      tr('no_pending_warehouse_outgoing'),
                      style: const TextStyle(color: Colors.white54, fontSize: 11),
                    ),
                  )
                : ListView.builder(
                    itemCount: items.length,
                    itemBuilder: (context, index) {
                      final row = items[index];
                      final rowId = _rowId(row);
                      final isSelected = rowId != null && selected.contains(rowId);
                      final isEven = index % 2 == 0;
                        return _buildTableRow(
                          partNumber,
                          row,
                          rowId,
                          index,
                          items,
                          isSelected,
                          isEven,
                          columns,
                          () => setModalState(() {}),
                        );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildTableHeader(List<Map<String, dynamic>> columns) {
    return Container(
      height: 28,
      color: AppColors.gridHeader,
      child: Row(
        children: [
          const SizedBox(width: 30),
          ...columns.map((col) {
            final flex = col['flex'] as int;
            return Expanded(
              flex: flex,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  col['label'] as String,
                  style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            );
          }),
          // Columna de ubicación asignada
          SizedBox(
            width: 90,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                tr('assigned'),
                style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.cyan),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTableRow(
    String partNumber,
    Map<String, dynamic> row,
    int? rowId,
    int index,
    List<Map<String, dynamic>> items,
    bool isSelected,
    bool isEven,
    List<Map<String, dynamic>> columns,
    VoidCallback? onUpdated,
  ) {
    final assignedLocation = rowId != null ? _getAssignedLocation(rowId) : null;
    final hasAssignedLocation = assignedLocation != null && assignedLocation.isNotEmpty;
    
    return GestureDetector(
      onTap: rowId == null ? null : () {
        final isShiftPressed = HardwareKeyboard.instance.isShiftPressed;
        _handleRowClick(partNumber, index, rowId, items, isShiftPressed, onUpdated);
      },
      child: Container(
        height: 28,
        decoration: BoxDecoration(
          color: hasAssignedLocation
              ? Colors.blue.withOpacity(0.15)
              : isSelected
                  ? AppColors.gridSelectedRow.withOpacity(0.4)
                  : isEven
                      ? AppColors.gridRowEven
                      : AppColors.gridRowOdd,
          border: Border(
            bottom: BorderSide(color: AppColors.border.withOpacity(0.4), width: 0.5),
            left: hasAssignedLocation 
                ? const BorderSide(color: Colors.blue, width: 3) 
                : isSelected 
                    ? const BorderSide(color: Colors.orange, width: 3) 
                    : BorderSide.none,
          ),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 30,
              child: hasAssignedLocation
                  ? const Icon(Icons.location_on, color: Colors.blue, size: 16)
                  : Checkbox(
                      value: isSelected,
                      onChanged: rowId == null ? null : (_) {
                        final isShiftPressed = HardwareKeyboard.instance.isShiftPressed;
                        _handleRowClick(partNumber, index, rowId, items, isShiftPressed, onUpdated);
                      },
                      side: const BorderSide(color: AppColors.border),
                      activeColor: Colors.orange,
                    ),
            ),
            ...columns.map((col) {
              final key = col['key'] as String;
              final flex = col['flex'] as int;
              String value = row[key]?.toString() ?? '-';
              if (key == 'fecha_salida') {
                value = _formatDateTime(row['fecha_salida']?.toString());
              }
              if (key == 'cantidad_salida') {
                value = _parseQty(row['cantidad_salida']).toString();
              }
              return Expanded(
                flex: flex,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    value,
                    style: const TextStyle(color: Colors.white70, fontSize: 11),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              );
            }),
            // Mostrar ubicación asignada
            if (hasAssignedLocation)
              Container(
                width: 90,
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        assignedLocation,
                        style: const TextStyle(color: Colors.cyan, fontSize: 10, fontWeight: FontWeight.bold),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    GestureDetector(
                      onTap: () {
                        _assignedLocations.remove(rowId);
                        onUpdated?.call();
                      },
                      child: const Icon(Icons.close, color: Colors.red, size: 14),
                    ),
                  ],
                ),
              )
            else
              const SizedBox(width: 90),
          ],
        ),
      ),
    );
  }

  Widget _buildRejectedItem(Map<String, dynamic> group) {
    final partNumber = group['numero_parte']?.toString() ?? '-';
    final totalQty = group['total_qty'] as num? ?? 0;
    final count = group['count'] as int? ?? 0;
    final rechazadoAt = _formatDateTime(group['latest_rejected_at']?.toString());
    final rechazadoPor = group['rechazado_por']?.toString() ?? '-';
    final motivo = group['rechazado_motivo']?.toString() ?? '-';

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.gridBackground,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.red.withOpacity(0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  partNumber,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                ),
              ),
              _buildChip('${tr('qty')}: $totalQty', Colors.red),
              const SizedBox(width: 6),
              _buildChip('${tr('records')}: $count', Colors.blueGrey),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.access_time, size: 14, color: Colors.white54),
              const SizedBox(width: 4),
              Text(
                rechazadoAt,
                style: const TextStyle(color: Colors.white54, fontSize: 11),
              ),
              const SizedBox(width: 12),
              const Icon(Icons.person_outline, size: 14, color: Colors.white54),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  rechazadoPor,
                  style: const TextStyle(color: Colors.white70, fontSize: 11),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.red.withOpacity(0.08),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: Colors.red.withOpacity(0.4)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tr('reason'),
                  style: const TextStyle(color: Colors.white54, fontSize: 10),
                ),
                const SizedBox(height: 4),
                Text(
                  motivo,
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChip(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.2),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.6)),
      ),
      child: Text(
        text,
        style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold),
      ),
    );
  }
}
