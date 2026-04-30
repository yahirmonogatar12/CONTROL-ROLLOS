import 'dart:async';
import 'package:flutter/material.dart';
import 'package:material_warehousing_flutter/core/localization/app_translations.dart';
import 'package:material_warehousing_flutter/core/theme/app_colors.dart';
import 'package:material_warehousing_flutter/core/services/api_service.dart';
import 'package:material_warehousing_flutter/core/services/auth_service.dart';
import 'package:material_warehousing_flutter/core/services/excel_export_service.dart';

enum _AuditEndMode { closeOnly, processOutgoing }

/// Pantalla de Auditoría de Inventario para PC (Supervisores)
class InventoryAuditScreen extends StatefulWidget {
  final LanguageProvider languageProvider;

  const InventoryAuditScreen({super.key, required this.languageProvider});

  @override
  State<InventoryAuditScreen> createState() => _InventoryAuditScreenState();
}

class _InventoryAuditScreenState extends State<InventoryAuditScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // Auto-refresh timer (cada 10 segundos cuando hay auditoría activa)
  Timer? _refreshTimer;

  // Tab 0: Auditoría Activa
  Map<String, dynamic>? _activeAudit;
  List<Map<String, dynamic>> _locations = [];
  Map<String, dynamic>? _summary;
  bool _isLoading = false;
  bool _isStarting = false;
  bool _isEnding = false;

  // Tab 1: Historial
  List<Map<String, dynamic>> _history = [];
  bool _isLoadingHistory = false;
  Map<String, dynamic>? _selectedHistoryAudit;
  List<Map<String, dynamic>> _selectedHistoryItems = [];
  bool _isLoadingHistoryDetail = false;

  // Tab 2: Comparación
  List<Map<String, dynamic>> _auditsForCompare = [];
  int? _compareAudit1;
  int? _compareAudit2;
  List<Map<String, dynamic>> _comparisonResults = [];
  bool _isComparing = false;
  // Filtros para comparación
  final TextEditingController _compareSearchController =
      TextEditingController();
  DateTime? _compareFilterDateFrom;
  DateTime? _compareFilterDateTo;
  List<Map<String, dynamic>> _filteredAuditsForCompare = [];

  // Detalle de ubicación seleccionada
  String? _selectedLocation;
  List<Map<String, dynamic>> _selectedLocationItems = [];
  bool _isLoadingItems = false;

  String tr(String key) => widget.languageProvider.tr(key);

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(_onTabChanged);
    _loadActiveAudit();
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    _refreshTimer?.cancel();
    _compareSearchController.dispose();
    super.dispose();
  }

  void _onTabChanged() {
    if (_tabController.index == 1) {
      _loadHistory();
    } else if (_tabController.index == 2) {
      _loadAuditsForCompare();
    }
    setState(() {});
  }

  Future<void> _loadActiveAudit() async {
    setState(() => _isLoading = true);
    final result = await ApiService.getActiveAudit();
    if (mounted) {
      setState(() {
        _isLoading = false;
        if (result['success'] == true && result['data'] != null) {
          _activeAudit = result['data'];
          _loadAuditDetails();
          _startAutoRefresh();
        } else {
          _activeAudit = null;
          _locations = [];
          _summary = null;
          _stopAutoRefresh();
        }
      });
    }
  }

  Future<void> _loadAuditDetails() async {
    if (_activeAudit == null) return;
    final auditId = _activeAudit!['id'];
    final results = await Future.wait([
      ApiService.getAuditLocations(auditId),
      ApiService.getAuditSummary(auditId),
    ]);
    if (mounted) {
      setState(() {
        if (results[0]['success'] == true) {
          final data = results[0]['data'];
          // El backend devuelve {locations: [...], auditActive: bool, auditId: string}
          if (data is Map && data['locations'] != null) {
            _locations = List<Map<String, dynamic>>.from(data['locations']);
          } else if (data is List) {
            _locations = List<Map<String, dynamic>>.from(data);
          } else {
            _locations = [];
          }
        }
        if (results[1]['success'] == true) {
          _summary = results[1]['data'];
        }
      });
    }
  }

  void _startAutoRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (_activeAudit != null && _tabController.index == 0) {
        _loadAuditDetails();
        if (_selectedLocation != null) {
          _loadLocationItems(_selectedLocation!);
        }
      }
    });
  }

  void _stopAutoRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = null;
  }

  Future<void> _loadHistory() async {
    setState(() => _isLoadingHistory = true);
    final result = await ApiService.getAuditHistory(limit: 100);
    if (mounted) {
      setState(() {
        _isLoadingHistory = false;
        if (result['success'] == true) {
          _history = List<Map<String, dynamic>>.from(result['data'] ?? []);
        }
      });
    }
  }

  Future<void> _loadAuditsForCompare() async {
    final result = await ApiService.getAuditHistory(limit: 200);
    if (mounted && result['success'] == true) {
      setState(() {
        _auditsForCompare =
            List<Map<String, dynamic>>.from(result['data'] ?? []);
        _applyCompareFilters();
      });
    }
  }

  void _applyCompareFilters() {
    final searchText = _compareSearchController.text.toLowerCase();
    _filteredAuditsForCompare = _auditsForCompare.where((audit) {
      // Filtro por texto (código de auditoría)
      final code = (audit['audit_code'] ?? '').toString().toLowerCase();
      if (searchText.isNotEmpty && !code.contains(searchText)) {
        return false;
      }

      // Filtro por fecha desde
      if (_compareFilterDateFrom != null) {
        final fechaFin = audit['fecha_fin'];
        if (fechaFin != null) {
          try {
            final date = DateTime.parse(fechaFin.toString());
            if (date.isBefore(_compareFilterDateFrom!)) return false;
          } catch (_) {}
        }
      }

      // Filtro por fecha hasta
      if (_compareFilterDateTo != null) {
        final fechaFin = audit['fecha_fin'];
        if (fechaFin != null) {
          try {
            final date = DateTime.parse(fechaFin.toString());
            if (date
                .isAfter(_compareFilterDateTo!.add(const Duration(days: 1))))
              return false;
          } catch (_) {}
        }
      }

      return true;
    }).toList();
  }

  Future<void> _loadLocationItems(String location) async {
    if (_activeAudit == null) return;
    setState(() => _isLoadingItems = true);
    final result =
        await ApiService.getAuditLocationItems(_activeAudit!['id'], location);
    if (mounted) {
      setState(() {
        _isLoadingItems = false;
        if (result['success'] == true) {
          final data = result['data'];
          // El backend devuelve {items: [...], location: string, auditId: int}
          if (data is Map && data['items'] != null) {
            _selectedLocationItems =
                List<Map<String, dynamic>>.from(data['items']);
          } else if (data is List) {
            _selectedLocationItems = List<Map<String, dynamic>>.from(data);
          } else {
            _selectedLocationItems = [];
          }
        }
      });
    }
  }

  Future<void> _startAudit() async {
    final currentUser = AuthService.currentUser;
    if (currentUser == null) {
      _showError(tr('audit_error_no_user'));
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.panelBackground,
        title: Text(tr('audit_start_confirm_title'),
            style: const TextStyle(color: Colors.white)),
        content: Text(tr('audit_start_confirm_message'),
            style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(tr('cancel'))),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            child: Text(tr('audit_start')),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() => _isStarting = true);
    final result = await ApiService.startAudit(currentUser.id);
    if (mounted) {
      setState(() => _isStarting = false);
      if (result['success'] == true) {
        _showSuccess(tr('audit_started_success'));
        await _loadActiveAudit();
      } else {
        _showError(result['error'] ?? tr('audit_start_error'));
      }
    }
  }

  Future<void> _endAudit() async {
    if (_activeAudit == null) return;
    final currentUser = AuthService.currentUser;
    if (currentUser == null) {
      _showError(tr('audit_error_no_user'));
      return;
    }

    final pendingLocs =
        _locations.where((l) => l['status'] != 'Verified').length;
    final endMode = await showDialog<_AuditEndMode>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.panelBackground,
        title: Text(tr('audit_end_confirm_title'),
            style: const TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(tr('audit_end_confirm_message'),
                style: const TextStyle(color: Colors.white70)),
            const SizedBox(height: 12),
            _statRow(tr('audit_total_locations'), '${_locations.length}',
                Colors.blue),
            _statRow(
                tr('audit_verified'),
                '${_locations.where((l) => l['status'] == 'Verified').length}',
                Colors.green),
            _statRow(tr('audit_pending'), '$pendingLocs', Colors.red),
            if (pendingLocs > 0) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8)),
                child: Row(children: [
                  const Icon(Icons.warning, color: Colors.orange, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                      child: Text(tr('audit_pending_warning'),
                          style: const TextStyle(
                              fontSize: 12, color: Colors.orange))),
                ]),
              ),
            ],
            const SizedBox(height: 12),
            Text(
              tr('audit_end_mode_hint'),
              style: const TextStyle(fontSize: 12, color: Colors.white60),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: Text(tr('cancel'))),
          OutlinedButton(
            onPressed: () => Navigator.pop(ctx, _AuditEndMode.closeOnly),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.orange,
              side: const BorderSide(color: Colors.orange),
            ),
            child: Text(tr('audit_end_without_outgoing')),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, _AuditEndMode.processOutgoing),
            style: ElevatedButton.styleFrom(
                backgroundColor:
                    pendingLocs > 0 ? Colors.orange : Colors.green),
            child: Text(tr('audit_end_with_outgoing')),
          ),
        ],
      ),
    );
    if (endMode == null) return;

    setState(() => _isEnding = true);
    final result = await ApiService.endAudit(
      _activeAudit!['id'],
      currentUser.id,
      processDiscrepancies: endMode == _AuditEndMode.processOutgoing,
    );
    if (mounted) {
      setState(() => _isEnding = false);
      if (result['success'] == true) {
        final data = result['data'] as Map<String, dynamic>?;
        final stats = data?['stats'] as Map<String, dynamic>?;
        final processedOut = (stats?['processedOut'] as num?)?.toInt() ?? 0;
        _showSuccess(
          processedOut > 0
              ? tr('audit_ended_with_outgoing')
              : tr('audit_ended_without_outgoing'),
        );
        _stopAutoRefresh();
        await _loadActiveAudit();
      } else {
        _showError(result['error'] ?? tr('audit_end_error'));
      }
    }
  }

  Future<void> _compareAudits() async {
    if (_compareAudit1 == null || _compareAudit2 == null) return;
    setState(() => _isComparing = true);
    final result =
        await ApiService.compareAudits(_compareAudit1!, _compareAudit2!);
    if (mounted) {
      setState(() {
        _isComparing = false;
        if (result['success'] == true) {
          _comparisonResults =
              List<Map<String, dynamic>>.from(result['data'] ?? []);
        }
      });
    }
  }

  // Mostrar detalles de una auditoría del historial (en panel lateral)
  Future<void> _showAuditDetails(Map<String, dynamic> audit) async {
    setState(() {
      _selectedHistoryAudit = audit;
      _isLoadingHistoryDetail = true;
      _selectedHistoryItems = [];
    });

    final auditId = audit['id'];
    final result = await ApiService.getAuditHistoryDetail(auditId);

    if (mounted) {
      setState(() {
        _isLoadingHistoryDetail = false;
        if (result['success'] == true) {
          final details = result['data'];
          _selectedHistoryItems =
              List<Map<String, dynamic>>.from(details['items'] ?? []);
        }
      });
    }
  }

  Widget _statRow(String label, String value, Color color) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child:
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(label, style: const TextStyle(color: Colors.white70)),
          Text(value,
              style: TextStyle(fontWeight: FontWeight.bold, color: color)),
        ]),
      );

  void _showError(String m) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(m), backgroundColor: Colors.red));
  void _showSuccess(String m) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(m), backgroundColor: Colors.green));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.panelBackground,
      body: Column(
        children: [
          Container(
            color: AppColors.gridBackground,
            child: TabBar(
              controller: _tabController,
              labelColor: AppColors.headerTab,
              unselectedLabelColor: Colors.white54,
              indicatorColor: AppColors.headerTab,
              tabs: [
                Tab(
                    icon: const Icon(Icons.fact_check),
                    text: tr('audit_active')),
                Tab(icon: const Icon(Icons.history), text: tr('audit_history')),
                Tab(
                    icon: const Icon(Icons.compare_arrows),
                    text: tr('audit_compare')),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildActiveTab(),
                _buildHistoryTab(),
                _buildCompareTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ============================================
  // TAB 0: AUDITORÍA ACTIVA
  // ============================================
  Widget _buildActiveTab() {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_activeAudit == null) return _buildNoActiveAudit();

    return Column(
      children: [
        _buildAuditHeader(),
        Expanded(
          child: Row(
            children: [
              // Panel izquierdo: Grid de ubicaciones
              Expanded(flex: 2, child: _buildLocationsGrid()),
              // Panel derecho: Detalle de ubicación seleccionada
              if (_selectedLocation != null)
                Expanded(flex: 3, child: _buildLocationDetail()),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildNoActiveAudit() => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.inventory_2_outlined,
                size: 80, color: Colors.white24),
            const SizedBox(height: 24),
            Text(tr('audit_no_active'),
                style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.white)),
            const SizedBox(height: 8),
            Text(tr('audit_no_active_description'),
                style: const TextStyle(color: Colors.white54),
                textAlign: TextAlign.center),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: _isStarting ? null : _startAudit,
              icon: _isStarting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.play_arrow),
              label:
                  Text(_isStarting ? tr('audit_starting') : tr('audit_start')),
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 32, vertical: 16)),
            ),
          ],
        ),
      );

  Widget _buildAuditHeader() => Container(
        padding: const EdgeInsets.all(12),
        color: AppColors.gridBackground,
        child: Row(
          children: [
            // Indicador de auto-refresh
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: Colors.green),
              ),
              child: const Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.autorenew, size: 16, color: Colors.green),
                SizedBox(width: 4),
                Text('Auto 10s',
                    style: TextStyle(fontSize: 11, color: Colors.green)),
              ]),
            ),
            const SizedBox(width: 16),
            // Info de auditoría
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                        '${tr('audit_id')}: ${_activeAudit?['audit_code'] ?? _activeAudit?['id']}',
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, color: Colors.white)),
                    Text(
                        '${tr('audit_started_at')}: ${_activeAudit?['fecha_inicio'] ?? ''}',
                        style: const TextStyle(
                            fontSize: 12, color: Colors.white54)),
                  ]),
            ),
            // Resumen rápido
            _quickStat(Icons.location_on, '${_locations.length}', Colors.blue,
                'Total'),
            const SizedBox(width: 12),
            _quickStat(
                Icons.check_circle,
                '${_locations.where((l) => l['status'] == 'Verified').length}',
                Colors.green,
                tr('audit_verified')),
            const SizedBox(width: 12),
            _quickStat(
                Icons.pending,
                '${_locations.where((l) => l['status'] != 'Verified').length}',
                Colors.red,
                tr('audit_pending')),
            const SizedBox(width: 16),
            // Botones
            IconButton(
                onPressed: _loadAuditDetails,
                icon: const Icon(Icons.refresh, color: Colors.white),
                tooltip: tr('refresh')),
            ElevatedButton.icon(
              onPressed: _isEnding ? null : _endAudit,
              icon: _isEnding
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.stop),
              label: Text(_isEnding ? tr('audit_ending') : tr('audit_end')),
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red, foregroundColor: Colors.white),
            ),
          ],
        ),
      );

  Widget _quickStat(IconData icon, String value, Color color, String label) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color.withValues(alpha: 0.3))),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 6),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(value,
                style: TextStyle(
                    fontSize: 16, fontWeight: FontWeight.bold, color: color)),
            Text(label,
                style: TextStyle(
                    fontSize: 10, color: color.withValues(alpha: 0.8))),
          ]),
        ]),
      );

  Widget _buildLocationsGrid() {
    return Container(
      margin: const EdgeInsets.all(8),
      decoration: BoxDecoration(
          color: AppColors.gridBackground,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.border)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
                color: AppColors.headerTab.withValues(alpha: 0.1),
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(8))),
            child: Row(children: [
              const Icon(Icons.location_on, size: 20, color: Colors.white),
              const SizedBox(width: 8),
              Text('${tr('audit_locations')} (${_locations.length})',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, color: Colors.white)),
            ]),
          ),
          // Grid visual de ubicaciones
          Expanded(
            child: _locations.isEmpty
                ? Center(
                    child: Text(tr('audit_no_locations'),
                        style: const TextStyle(color: Colors.white54)))
                : Padding(
                    padding: const EdgeInsets.all(8),
                    child: GridView.builder(
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 4,
                        childAspectRatio: 1.5,
                        crossAxisSpacing: 8,
                        mainAxisSpacing: 8,
                      ),
                      itemCount: _locations.length,
                      itemBuilder: (context, index) {
                        final loc = _locations[index];
                        final status = loc['status'] as String? ?? 'Pending';
                        final isVerified = status == 'Verified';
                        final isSelected = _selectedLocation == loc['location'];

                        return InkWell(
                          onTap: () {
                            setState(() => _selectedLocation = loc['location']);
                            _loadLocationItems(loc['location']);
                          },
                          child: Container(
                            decoration: BoxDecoration(
                              color: isVerified
                                  ? Colors.green.withValues(alpha: 0.3)
                                  : Colors.red.withValues(alpha: 0.3),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: isSelected
                                    ? Colors.white
                                    : (isVerified ? Colors.green : Colors.red),
                                width: isSelected ? 3 : 2,
                              ),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  isVerified
                                      ? Icons.check_circle
                                      : Icons.radio_button_unchecked,
                                  color: isVerified ? Colors.green : Colors.red,
                                  size: 24,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  loc['location'] ?? '',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                      fontSize: 12),
                                  textAlign: TextAlign.center,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(
                                  '${loc['scanned_items'] ?? 0}/${loc['total_items'] ?? 0}',
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: isVerified
                                          ? Colors.green
                                          : Colors.red),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildLocationDetail() {
    return Container(
      margin: const EdgeInsets.all(8),
      decoration: BoxDecoration(
          color: AppColors.gridBackground,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.border)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
                color: AppColors.headerTab.withValues(alpha: 0.1),
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(8))),
            child: Row(children: [
              const Icon(Icons.inventory_2, size: 20, color: Colors.white),
              const SizedBox(width: 8),
              Expanded(
                  child: Text('${tr('audit_items_in')}: $_selectedLocation',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, color: Colors.white))),
              IconButton(
                  onPressed: () => _loadLocationItems(_selectedLocation!),
                  icon:
                      const Icon(Icons.refresh, size: 20, color: Colors.white)),
              IconButton(
                  onPressed: () => setState(() {
                        _selectedLocation = null;
                        _selectedLocationItems = [];
                      }),
                  icon: const Icon(Icons.close, size: 20, color: Colors.white)),
            ]),
          ),
          Expanded(
            child: _isLoadingItems
                ? const Center(child: CircularProgressIndicator())
                : _selectedLocationItems.isEmpty
                    ? Center(
                        child: Text(tr('audit_no_items'),
                            style: const TextStyle(color: Colors.white54)))
                    : ListView.builder(
                        itemCount: _selectedLocationItems.length,
                        itemBuilder: (context, index) {
                          final item = _selectedLocationItems[index];
                          final status = item['audit_status'] as String? ??
                              item['status'] as String? ??
                              'Pending';
                          final isFound = status == 'Found';
                          final isMissing = status == 'Missing';

                          Color statusColor = Colors.grey;
                          IconData statusIcon = Icons.radio_button_unchecked;
                          if (isFound) {
                            statusColor = Colors.green;
                            statusIcon = Icons.check_circle;
                          } else if (isMissing) {
                            statusColor = Colors.red;
                            statusIcon = Icons.cancel;
                          }

                          return Card(
                            color: AppColors.gridRowOdd,
                            margin: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            child: ListTile(
                              leading: Icon(statusIcon,
                                  color: statusColor, size: 28),
                              title: Text(
                                  item['warehousing_code'] ??
                                      item['codigo_material_recibido'] ??
                                      '',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w500,
                                      fontSize: 13,
                                      color: Colors.white)),
                              subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(item['numero_parte'] ?? '',
                                        style: const TextStyle(
                                            fontSize: 12,
                                            color: Colors.white70)),
                                    Text(
                                        '${tr('quantity')}: ${item['cantidad_actual'] ?? '-'}',
                                        style: const TextStyle(
                                            fontSize: 11,
                                            color: Colors.white54)),
                                  ]),
                              trailing: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                    color: statusColor.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(4)),
                                child: Text(status,
                                    style: TextStyle(
                                        fontSize: 11,
                                        color: statusColor,
                                        fontWeight: FontWeight.bold)),
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  // ============================================
  // TAB 1: HISTORIAL (con panel de detalles a la derecha)
  // ============================================
  Widget _buildHistoryTab() {
    if (_isLoadingHistory)
      return const Center(child: CircularProgressIndicator());
    if (_history.isEmpty) {
      return Center(
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        const Icon(Icons.history, size: 60, color: Colors.white24),
        const SizedBox(height: 16),
        Text(tr('audit_no_history'),
            style: const TextStyle(color: Colors.white54)),
        const SizedBox(height: 16),
        ElevatedButton.icon(
            onPressed: _loadHistory,
            icon: const Icon(Icons.refresh),
            label: Text(tr('refresh'))),
      ]));
    }

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          // Panel izquierdo: Lista de auditorías
          Expanded(
            flex: 2,
            child: Container(
              decoration: BoxDecoration(
                  color: AppColors.gridBackground,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.border)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                        color: AppColors.headerTab.withValues(alpha: 0.1),
                        borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(8))),
                    child: Row(children: [
                      const Icon(Icons.history, size: 20, color: Colors.white),
                      const SizedBox(width: 8),
                      Expanded(
                          child: Text(
                              '${tr('audit_history')} (${_history.length})',
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white))),
                      IconButton(
                        onPressed:
                            _history.isEmpty ? null : _exportHistoryToExcel,
                        icon: const Icon(Icons.file_download,
                            size: 18, color: Colors.white),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        tooltip: tr('export_excel'),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                          onPressed: _loadHistory,
                          icon: const Icon(Icons.refresh,
                              size: 18, color: Colors.white),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints()),
                    ]),
                  ),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        return SingleChildScrollView(
                          child: ConstrainedBox(
                            constraints:
                                BoxConstraints(minWidth: constraints.maxWidth),
                            child: DataTable(
                              headingRowColor:
                                  WidgetStateProperty.all(AppColors.gridHeader),
                              dataRowColor: WidgetStateProperty.resolveWith(
                                  (states) => AppColors.gridRowOdd),
                              columnSpacing: 8,
                              horizontalMargin: 8,
                              columns: [
                                DataColumn(
                                    label: Expanded(
                                        child: Text(tr('audit_code'),
                                            style: const TextStyle(
                                                color: Colors.white,
                                                fontWeight: FontWeight.bold,
                                                fontSize: 11)))),
                                DataColumn(
                                    label: Expanded(
                                        child: Text(tr('audit_ended_at'),
                                            style: const TextStyle(
                                                color: Colors.white,
                                                fontWeight: FontWeight.bold,
                                                fontSize: 11)))),
                                DataColumn(
                                    label: Text(tr('audit_verified'),
                                        style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 11))),
                                DataColumn(
                                    label: Text(tr('audit_with_discrepancy'),
                                        style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 11))),
                              ],
                              rows: _history.map((audit) {
                                final isSelected =
                                    _selectedHistoryAudit?['id'] == audit['id'];
                                return DataRow(
                                  selected: isSelected,
                                  color:
                                      WidgetStateProperty.resolveWith((states) {
                                    if (isSelected)
                                      return AppColors.headerTab
                                          .withValues(alpha: 0.3);
                                    return AppColors.gridRowOdd;
                                  }),
                                  onSelectChanged: (_) =>
                                      _showAuditDetails(audit),
                                  cells: [
                                    DataCell(Text(
                                        audit['audit_code'] ??
                                            '#${audit['id']}',
                                        style: TextStyle(
                                            color: isSelected
                                                ? Colors.white
                                                : Colors.white70,
                                            fontWeight: isSelected
                                                ? FontWeight.bold
                                                : FontWeight.normal,
                                            fontSize: 11))),
                                    DataCell(Text(
                                        _formatDate(audit['fecha_fin']),
                                        style: const TextStyle(
                                            color: Colors.white70,
                                            fontSize: 10))),
                                    DataCell(Text(
                                        '${audit['verified_locations'] ?? 0}',
                                        style: const TextStyle(
                                            color: Colors.green,
                                            fontSize: 11))),
                                    DataCell(Text(
                                        '${audit['discrepancy_locations'] ?? 0}',
                                        style: const TextStyle(
                                            color: Colors.red, fontSize: 11))),
                                  ],
                                );
                              }).toList(),
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
          const SizedBox(width: 12),
          // Panel derecho: Detalle de auditoría seleccionada
          Expanded(
            flex: 3,
            child: _buildHistoryDetailPanel(),
          ),
        ],
      ),
    );
  }

  Future<void> _exportHistoryToExcel() async {
    if (_history.isEmpty) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.panelBackground,
        content: Row(mainAxisSize: MainAxisSize.min, children: [
          const CircularProgressIndicator(),
          const SizedBox(width: 16),
          Text(tr('exporting'), style: const TextStyle(color: Colors.white)),
        ]),
      ),
    );

    final success = await ExcelExportService.exportToExcel(
      data: _history,
      headers: [
        tr('audit_code'),
        tr('audit_started_at'),
        tr('audit_ended_at'),
        tr('audit_total_locations'),
        tr('audit_verified'),
        tr('audit_with_discrepancy'),
        tr('status')
      ],
      fieldMapping: [
        'audit_code',
        'fecha_inicio',
        'fecha_fin',
        'total_locations',
        'verified_locations',
        'discrepancy_locations',
        'status'
      ],
      fileName: 'audit_history',
    );

    if (mounted) Navigator.pop(context);
    if (mounted) {
      if (success) {
        _showSuccess(tr('export_success'));
      } else {
        _showError(tr('export_error'));
      }
    }
  }

  Future<void> _exportDetailToExcel() async {
    if (_selectedHistoryItems.isEmpty || _selectedHistoryAudit == null) return;

    final filteredItems = _selectedHistoryItems
        .where((i) => i['status'] == 'Missing' || i['status'] == 'ProcessedOut')
        .toList();
    if (filteredItems.isEmpty) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.panelBackground,
        content: Row(mainAxisSize: MainAxisSize.min, children: [
          const CircularProgressIndicator(),
          const SizedBox(width: 16),
          Text(tr('exporting'), style: const TextStyle(color: Colors.white)),
        ]),
      ),
    );

    final success = await ExcelExportService.exportToExcel(
      data: filteredItems,
      headers: [
        tr('material_code'),
        tr('part_number'),
        tr('location'),
        tr('quantity'),
        tr('status')
      ],
      fieldMapping: [
        'warehousing_code',
        'numero_parte',
        'location',
        'cantidad_actual',
        'status'
      ],
      fileName:
          'audit_${_selectedHistoryAudit!['audit_code'] ?? _selectedHistoryAudit!['id']}_discrepancies',
    );

    if (mounted) Navigator.pop(context);
    if (mounted) {
      if (success) {
        _showSuccess(tr('export_success'));
      } else {
        _showError(tr('export_error'));
      }
    }
  }

  Widget _buildHistoryDetailPanel() {
    if (_selectedHistoryAudit == null) {
      return Container(
        decoration: BoxDecoration(
            color: AppColors.gridBackground,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.border)),
        child: Center(
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            const Icon(Icons.touch_app, size: 48, color: Colors.white24),
            const SizedBox(height: 12),
            Text(tr('audit_select_to_view'),
                style: const TextStyle(color: Colors.white54)),
          ]),
        ),
      );
    }

    final audit = _selectedHistoryAudit!;

    return Container(
      decoration: BoxDecoration(
          color: AppColors.gridBackground,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.border)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header con info de auditoría
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
                color: AppColors.headerTab.withValues(alpha: 0.1),
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(8))),
            child: Row(children: [
              const Icon(Icons.fact_check,
                  size: 20, color: AppColors.headerTab),
              const SizedBox(width: 8),
              Text(audit['audit_code'] ?? '#${audit['id']}',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, color: Colors.white)),
              const Spacer(),
              IconButton(
                onPressed:
                    _selectedHistoryItems.isEmpty ? null : _exportDetailToExcel,
                icon: Icon(Icons.file_download,
                    size: 18,
                    color: _selectedHistoryItems.isEmpty
                        ? Colors.white24
                        : Colors.white),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                tooltip: tr('export_excel'),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: () => setState(() {
                  _selectedHistoryAudit = null;
                  _selectedHistoryItems = [];
                }),
                icon: const Icon(Icons.close, size: 18, color: Colors.white54),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ]),
          ),
          // Stats rápidas
          Padding(
            padding: const EdgeInsets.all(12),
            child: Wrap(spacing: 12, runSpacing: 8, children: [
              _quickStat(
                  Icons.calendar_today,
                  _formatDate(audit['fecha_inicio']),
                  Colors.blue,
                  tr('audit_started_at')),
              _quickStat(Icons.calendar_today, _formatDate(audit['fecha_fin']),
                  Colors.orange, tr('audit_ended_at')),
              _quickStat(
                  Icons.check_circle,
                  '${audit['found_items'] ?? audit['verified_locations'] ?? 0}',
                  Colors.green,
                  tr('audit_found')),
              _quickStat(
                  Icons.cancel,
                  '${audit['missing_items'] ?? audit['discrepancy_locations'] ?? 0}',
                  Colors.red,
                  tr('audit_missing')),
            ]),
          ),
          const Divider(color: AppColors.border, height: 1),
          // Título de items
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(tr('audit_missing_items'),
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold)),
          ),
          // Lista de items
          Expanded(
            child: _isLoadingHistoryDetail
                ? const Center(child: CircularProgressIndicator())
                : _selectedHistoryItems.isEmpty
                    ? Center(
                        child: Text(tr('no_discrepancies'),
                            style: const TextStyle(color: Colors.white54)))
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        itemCount: _selectedHistoryItems
                            .where((i) =>
                                i['status'] == 'Missing' ||
                                i['status'] == 'ProcessedOut')
                            .length,
                        itemBuilder: (context, index) {
                          final filteredItems = _selectedHistoryItems
                              .where((i) =>
                                  i['status'] == 'Missing' ||
                                  i['status'] == 'ProcessedOut')
                              .toList();
                          final item = filteredItems[index];
                          final status = item['status'] as String? ?? 'Unknown';
                          final statusColor = status == 'ProcessedOut'
                              ? Colors.orange
                              : Colors.red;
                          final statusIcon = status == 'ProcessedOut'
                              ? Icons.exit_to_app
                              : Icons.cancel;

                          return Card(
                            color: AppColors.gridRowOdd,
                            margin: const EdgeInsets.only(bottom: 6),
                            child: ListTile(
                              dense: true,
                              leading: Icon(statusIcon,
                                  color: statusColor, size: 24),
                              title: Text(item['warehousing_code'] ?? '-',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w500,
                                      fontSize: 13,
                                      color: Colors.white)),
                              subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(item['numero_parte'] ?? '-',
                                        style: const TextStyle(
                                            fontSize: 11,
                                            color: Colors.white70)),
                                    Text(
                                        '${tr('location')}: ${item['location'] ?? '-'} | ${tr('quantity')}: ${item['cantidad_actual'] ?? '-'}',
                                        style: const TextStyle(
                                            fontSize: 10,
                                            color: Colors.white54)),
                                  ]),
                              trailing: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                    color: statusColor.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(4)),
                                child: Text(
                                    status == 'ProcessedOut'
                                        ? tr('outgoing_created')
                                        : tr('audit_missing'),
                                    style: TextStyle(
                                        fontSize: 10, color: statusColor)),
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  // ============================================
  // TAB 2: COMPARACIÓN DE AUDITORÍAS
  // ============================================
  Widget _buildCompareTab() {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          // Panel izquierdo: Selección de auditorías con filtros
          Expanded(
            flex: 2,
            child: Container(
              decoration: BoxDecoration(
                  color: AppColors.gridBackground,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.border)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header con título
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                        color: AppColors.headerTab.withValues(alpha: 0.1),
                        borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(8))),
                    child: Row(children: [
                      const Icon(Icons.list_alt, size: 20, color: Colors.white),
                      const SizedBox(width: 8),
                      Text(tr('audit_select_audits'),
                          style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.white)),
                      const Spacer(),
                      IconButton(
                        onPressed: _loadAuditsForCompare,
                        icon: const Icon(Icons.refresh,
                            size: 18, color: Colors.white),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ]),
                  ),
                  // Filtros
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: Column(
                      children: [
                        // Búsqueda por código
                        TextField(
                          controller: _compareSearchController,
                          style: const TextStyle(
                              color: Colors.white, fontSize: 13),
                          decoration: InputDecoration(
                            hintText: tr('search_by_code'),
                            hintStyle: const TextStyle(
                                color: Colors.white38, fontSize: 12),
                            prefixIcon: const Icon(Icons.search,
                                size: 18, color: Colors.white38),
                            filled: true,
                            fillColor: AppColors.fieldBackground,
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: BorderSide.none),
                            suffixIcon: _compareSearchController.text.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.clear,
                                        size: 16, color: Colors.white38),
                                    onPressed: () {
                                      _compareSearchController.clear();
                                      setState(() => _applyCompareFilters());
                                    },
                                  )
                                : null,
                          ),
                          onChanged: (_) =>
                              setState(() => _applyCompareFilters()),
                        ),
                        const SizedBox(height: 8),
                        // Filtro de fechas
                        Row(
                          children: [
                            Expanded(
                              child: InkWell(
                                onTap: () => _selectCompareDate(isFrom: true),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 10),
                                  decoration: BoxDecoration(
                                      color: AppColors.fieldBackground,
                                      borderRadius: BorderRadius.circular(8)),
                                  child: Row(children: [
                                    const Icon(Icons.calendar_today,
                                        size: 14, color: Colors.white54),
                                    const SizedBox(width: 6),
                                    Text(
                                      _compareFilterDateFrom != null
                                          ? '${_compareFilterDateFrom!.day}/${_compareFilterDateFrom!.month}/${_compareFilterDateFrom!.year}'
                                          : tr('from'),
                                      style: TextStyle(
                                          fontSize: 11,
                                          color: _compareFilterDateFrom != null
                                              ? Colors.white
                                              : Colors.white54),
                                    ),
                                  ]),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: InkWell(
                                onTap: () => _selectCompareDate(isFrom: false),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 10),
                                  decoration: BoxDecoration(
                                      color: AppColors.fieldBackground,
                                      borderRadius: BorderRadius.circular(8)),
                                  child: Row(children: [
                                    const Icon(Icons.calendar_today,
                                        size: 14, color: Colors.white54),
                                    const SizedBox(width: 6),
                                    Text(
                                      _compareFilterDateTo != null
                                          ? '${_compareFilterDateTo!.day}/${_compareFilterDateTo!.month}/${_compareFilterDateTo!.year}'
                                          : tr('to'),
                                      style: TextStyle(
                                          fontSize: 11,
                                          color: _compareFilterDateTo != null
                                              ? Colors.white
                                              : Colors.white54),
                                    ),
                                  ]),
                                ),
                              ),
                            ),
                            if (_compareFilterDateFrom != null ||
                                _compareFilterDateTo != null)
                              IconButton(
                                icon: const Icon(Icons.clear,
                                    size: 16, color: Colors.white54),
                                onPressed: () => setState(() {
                                  _compareFilterDateFrom = null;
                                  _compareFilterDateTo = null;
                                  _applyCompareFilters();
                                }),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const Divider(color: AppColors.border, height: 1),
                  // Auditorías seleccionadas
                  Container(
                    padding: const EdgeInsets.all(8),
                    color: AppColors.gridHeader.withValues(alpha: 0.3),
                    child: Row(children: [
                      Expanded(
                        child: Text(
                          '${tr('audit')} 1: ${_compareAudit1 != null ? _auditsForCompare.firstWhere((a) => a['id'] == _compareAudit1, orElse: () => {})['audit_code'] ?? '-' : '-'}',
                          style: TextStyle(
                              fontSize: 11,
                              color: _compareAudit1 != null
                                  ? Colors.green
                                  : Colors.white54),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          '${tr('audit')} 2: ${_compareAudit2 != null ? _auditsForCompare.firstWhere((a) => a['id'] == _compareAudit2, orElse: () => {})['audit_code'] ?? '-' : '-'}',
                          style: TextStyle(
                              fontSize: 11,
                              color: _compareAudit2 != null
                                  ? Colors.orange
                                  : Colors.white54),
                        ),
                      ),
                    ]),
                  ),
                  // Lista de auditorías
                  Expanded(
                    child: _filteredAuditsForCompare.isEmpty
                        ? Center(
                            child: Text(tr('no_data'),
                                style: const TextStyle(color: Colors.white54)))
                        : ListView.builder(
                            itemCount: _filteredAuditsForCompare.length,
                            itemBuilder: (context, index) {
                              final audit = _filteredAuditsForCompare[index];
                              final isSelected1 = _compareAudit1 == audit['id'];
                              final isSelected2 = _compareAudit2 == audit['id'];

                              return Card(
                                color: isSelected1
                                    ? Colors.green.withValues(alpha: 0.2)
                                    : isSelected2
                                        ? Colors.orange.withValues(alpha: 0.2)
                                        : AppColors.gridRowOdd,
                                margin: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 3),
                                child: InkWell(
                                  onTap: () {
                                    setState(() {
                                      if (_compareAudit1 == null) {
                                        _compareAudit1 = audit['id'];
                                      } else if (_compareAudit2 == null &&
                                          audit['id'] != _compareAudit1) {
                                        _compareAudit2 = audit['id'];
                                      } else if (audit['id'] ==
                                          _compareAudit1) {
                                        _compareAudit1 = null;
                                      } else if (audit['id'] ==
                                          _compareAudit2) {
                                        _compareAudit2 = null;
                                      } else {
                                        // Reemplazar el primero
                                        _compareAudit1 = audit['id'];
                                      }
                                    });
                                  },
                                  child: Padding(
                                    padding: const EdgeInsets.all(10),
                                    child: Row(
                                      children: [
                                        Icon(
                                          isSelected1
                                              ? Icons.looks_one
                                              : isSelected2
                                                  ? Icons.looks_two
                                                  : Icons
                                                      .radio_button_unchecked,
                                          color: isSelected1
                                              ? Colors.green
                                              : isSelected2
                                                  ? Colors.orange
                                                  : Colors.white38,
                                          size: 20,
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                audit['audit_code'] ??
                                                    '#${audit['id']}',
                                                style: TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 12,
                                                  color: isSelected1
                                                      ? Colors.green
                                                      : isSelected2
                                                          ? Colors.orange
                                                          : Colors.white,
                                                ),
                                              ),
                                              Text(
                                                _formatDate(audit['fecha_fin']),
                                                style: const TextStyle(
                                                    fontSize: 10,
                                                    color: Colors.white54),
                                              ),
                                            ],
                                          ),
                                        ),
                                        Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.end,
                                          children: [
                                            Text(
                                                '${audit['verified_locations'] ?? 0}',
                                                style: const TextStyle(
                                                    fontSize: 11,
                                                    color: Colors.green)),
                                            Text(
                                                '${audit['discrepancy_locations'] ?? 0}',
                                                style: const TextStyle(
                                                    fontSize: 11,
                                                    color: Colors.red)),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                  // Botón comparar
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: (_compareAudit1 != null &&
                                    _compareAudit2 != null &&
                                    !_isComparing)
                                ? _compareAudits
                                : null,
                            icon: _isComparing
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2, color: Colors.white))
                                : const Icon(Icons.compare, size: 18),
                            label: Text(tr('audit_compare'),
                                style: const TextStyle(fontSize: 12)),
                            style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.headerTab,
                                foregroundColor: Colors.white),
                          ),
                        ),
                        const SizedBox(width: 8),
                        TextButton(
                          onPressed: () => setState(() {
                            _compareAudit1 = null;
                            _compareAudit2 = null;
                            _comparisonResults = [];
                          }),
                          child: Text(tr('clear'),
                              style: const TextStyle(fontSize: 11)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Panel derecho: Resultados
          Expanded(
            flex: 3,
            child: Container(
              decoration: BoxDecoration(
                  color: AppColors.gridBackground,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.border)),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                        color: AppColors.headerTab.withValues(alpha: 0.1),
                        borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(8))),
                    child: Row(children: [
                      const Icon(Icons.compare_arrows,
                          size: 20, color: AppColors.headerTab),
                      const SizedBox(width: 8),
                      Text(tr('audit_compare_results'),
                          style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.white)),
                      const Spacer(),
                      if (_comparisonResults.isNotEmpty)
                        IconButton(
                          onPressed: _exportCompareToExcel,
                          icon: const Icon(Icons.file_download,
                              size: 18, color: Colors.white),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          tooltip: tr('export_excel'),
                        ),
                    ]),
                  ),
                  Expanded(
                    child: _comparisonResults.isEmpty
                        ? Center(
                            child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(Icons.compare_arrows,
                                      size: 48, color: Colors.white24),
                                  const SizedBox(height: 12),
                                  Text(tr('audit_select_to_compare'),
                                      style: const TextStyle(
                                          color: Colors.white54)),
                                ]),
                          )
                        : LayoutBuilder(
                            builder: (context, constraints) {
                              return SingleChildScrollView(
                                child: ConstrainedBox(
                                  constraints: BoxConstraints(
                                      minWidth: constraints.maxWidth),
                                  child: DataTable(
                                    headingRowColor: WidgetStateProperty.all(
                                        AppColors.gridHeader),
                                    columnSpacing: 12,
                                    columns: [
                                      DataColumn(
                                          label: Expanded(
                                              child: Text(tr('part_number'),
                                                  style: const TextStyle(
                                                      color: Colors.white,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      fontSize: 11)))),
                                      DataColumn(
                                          label: Text('Items 1',
                                              style: const TextStyle(
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 11))),
                                      DataColumn(
                                          label: Text('${tr('quantity')} 1',
                                              style: const TextStyle(
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 11))),
                                      DataColumn(
                                          label: Text('Items 2',
                                              style: const TextStyle(
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 11))),
                                      DataColumn(
                                          label: Text('${tr('quantity')} 2',
                                              style: const TextStyle(
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 11))),
                                      DataColumn(
                                          label: Text('Δ Items',
                                              style: const TextStyle(
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 11))),
                                      DataColumn(
                                          label: Text('Δ ${tr('quantity')}',
                                              style: const TextStyle(
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 11))),
                                    ],
                                    rows: _comparisonResults.map((row) {
                                      final qty1 = int.tryParse(
                                              row['qty1']?.toString() ?? '0') ??
                                          0;
                                      final qty2 = int.tryParse(
                                              row['qty2']?.toString() ?? '0') ??
                                          0;
                                      final diff = qty2 - qty1;
                                      final diffColor = diff > 0
                                          ? Colors.green
                                          : (diff < 0
                                              ? Colors.red
                                              : Colors.grey);
                                      final statusText = diff > 0
                                          ? '+$diff'
                                          : (diff < 0 ? '$diff' : '=');

                                      // Cantidades de material
                                      final qtyFound1 = int.tryParse(
                                              row['qty_found1']?.toString() ??
                                                  '0') ??
                                          0;
                                      final qtyFound2 = int.tryParse(
                                              row['qty_found2']?.toString() ??
                                                  '0') ??
                                          0;
                                      final qtyDiff = qtyFound2 - qtyFound1;
                                      final qtyDiffColor = qtyDiff > 0
                                          ? Colors.green
                                          : (qtyDiff < 0
                                              ? Colors.red
                                              : Colors.grey);
                                      final qtyDiffText = qtyDiff > 0
                                          ? '+$qtyDiff'
                                          : (qtyDiff < 0 ? '$qtyDiff' : '=');

                                      return DataRow(cells: [
                                        DataCell(Text(
                                            row['numero_parte'] ?? '-',
                                            style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 11))),
                                        DataCell(Text('$qty1',
                                            style: const TextStyle(
                                                color: Colors.white70,
                                                fontSize: 11))),
                                        DataCell(Text('$qtyFound1',
                                            style: const TextStyle(
                                                color: Colors.cyan,
                                                fontSize: 11))),
                                        DataCell(Text('$qty2',
                                            style: const TextStyle(
                                                color: Colors.white70,
                                                fontSize: 11))),
                                        DataCell(Text('$qtyFound2',
                                            style: const TextStyle(
                                                color: Colors.cyan,
                                                fontSize: 11))),
                                        DataCell(Row(children: [
                                          Icon(
                                              diff > 0
                                                  ? Icons.arrow_upward
                                                  : (diff < 0
                                                      ? Icons.arrow_downward
                                                      : Icons.remove),
                                              color: diffColor,
                                              size: 14),
                                          Text(statusText,
                                              style: TextStyle(
                                                  color: diffColor,
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 11)),
                                        ])),
                                        DataCell(Row(children: [
                                          Icon(
                                              qtyDiff > 0
                                                  ? Icons.arrow_upward
                                                  : (qtyDiff < 0
                                                      ? Icons.arrow_downward
                                                      : Icons.remove),
                                              color: qtyDiffColor,
                                              size: 14),
                                          Text(qtyDiffText,
                                              style: TextStyle(
                                                  color: qtyDiffColor,
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 11)),
                                        ])),
                                      ]);
                                    }).toList(),
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
        ],
      ),
    );
  }

  Future<void> _selectCompareDate({required bool isFrom}) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: isFrom
          ? (_compareFilterDateFrom ?? DateTime.now())
          : (_compareFilterDateTo ?? DateTime.now()),
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.dark(
                primary: AppColors.headerTab,
                surface: AppColors.panelBackground),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() {
        if (isFrom) {
          _compareFilterDateFrom = picked;
        } else {
          _compareFilterDateTo = picked;
        }
        _applyCompareFilters();
      });
    }
  }

  Future<void> _exportCompareToExcel() async {
    if (_comparisonResults.isEmpty) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.panelBackground,
        content: Row(mainAxisSize: MainAxisSize.min, children: [
          const CircularProgressIndicator(),
          const SizedBox(width: 16),
          Text(tr('exporting'), style: const TextStyle(color: Colors.white)),
        ]),
      ),
    );

    // Preparar datos con diferencia calculada
    final dataForExport = _comparisonResults.map((row) {
      final qty1 = int.tryParse(row['qty1']?.toString() ?? '0') ?? 0;
      final qty2 = int.tryParse(row['qty2']?.toString() ?? '0') ?? 0;
      final diff = qty2 - qty1;
      final qtyFound1 = int.tryParse(row['qty_found1']?.toString() ?? '0') ?? 0;
      final qtyFound2 = int.tryParse(row['qty_found2']?.toString() ?? '0') ?? 0;
      final qtyDiff = qtyFound2 - qtyFound1;
      return {
        ...row,
        'qty1_str': qty1.toString(),
        'qty_found1_str': qtyFound1.toString(),
        'qty2_str': qty2.toString(),
        'qty_found2_str': qtyFound2.toString(),
        'diff_str': diff > 0 ? '+$diff' : '$diff',
        'qty_diff_str': qtyDiff > 0 ? '+$qtyDiff' : '$qtyDiff',
      };
    }).toList();

    final success = await ExcelExportService.exportToExcel(
      data: dataForExport,
      headers: [
        tr('part_number'),
        'Items 1',
        '${tr('quantity')} 1',
        'Items 2',
        '${tr('quantity')} 2',
        'Δ Items',
        'Δ ${tr('quantity')}'
      ],
      fieldMapping: [
        'numero_parte',
        'qty1_str',
        'qty_found1_str',
        'qty2_str',
        'qty_found2_str',
        'diff_str',
        'qty_diff_str'
      ],
      fileName: 'audit_comparison',
    );

    if (mounted) Navigator.pop(context);
    if (mounted) {
      if (success) {
        _showSuccess(tr('export_success'));
      } else {
        _showError(tr('export_error'));
      }
    }
  }

  String _formatDate(dynamic d) {
    if (d == null) return '-';
    try {
      final dt = DateTime.parse(d.toString());
      return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return d.toString();
    }
  }
}
