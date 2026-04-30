import 'dart:async';
import 'package:flutter/material.dart';
import 'package:material_warehousing_flutter/core/services/api_service.dart';
import 'package:material_warehousing_flutter/core/services/fcm_service.dart';
import 'package:material_warehousing_flutter/core/services/feedback_service.dart';
import 'package:material_warehousing_flutter/core/services/auth_service.dart';
import 'package:material_warehousing_flutter/core/localization/app_translations.dart';

/// Pantalla de solicitudes de material SMT
/// Muestra solicitudes pendientes desde las líneas SMT para que almacén las surta
class MobileSMTRequestsScreen extends StatefulWidget {
  final LanguageProvider languageProvider;

  const MobileSMTRequestsScreen({
    super.key,
    required this.languageProvider,
  });

  @override
  State<MobileSMTRequestsScreen> createState() =>
      _MobileSMTRequestsScreenState();
}

class _MobileSMTRequestsScreenState extends State<MobileSMTRequestsScreen> {
  List<Map<String, dynamic>> _requests = [];
  bool _isLoading = true;
  String? _selectedLine;
  String _filterStatus = 'pending';
  Timer? _refreshTimer;
  int _lastPendingCount = 0;
  void Function(Map<String, dynamic> data)? _previousMaterialRequestHandler;

  static const List<String> _smtLines = ['SA', 'SB', 'SC', 'SD', 'SE'];

  static const Map<String, String> _lineLabels = {
    'SA': 'SMT A',
    'SB': 'SMT B',
    'SC': 'SMT C',
    'SD': 'SMT D',
    'SE': 'SMT E',
  };

  String tr(String key) => widget.languageProvider.tr(key);

  String _formatLineLabel(String? lineId) {
    if (lineId == null || lineId.isEmpty) {
      return '';
    }
    return _lineLabels[lineId] ?? lineId;
  }

  String _extractPartNumber(String? reelCode) {
    final normalized = (reelCode ?? '').trim();
    if (normalized.isEmpty) {
      return '';
    }
    return normalized.split('-').first.trim();
  }

  @override
  void initState() {
    super.initState();
    _loadRequests(showLoading: true, refreshPendingCount: true);
    _previousMaterialRequestHandler = FCMService.instance.onMaterialRequest;
    FCMService.instance.onMaterialRequest = (data) {
      _previousMaterialRequestHandler?.call(data);
      if (mounted) {
        _loadRequests(refreshPendingCount: true);
      }
    };
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _pollPendingCount(),
    );
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    if (FCMService.instance.onMaterialRequest != _previousMaterialRequestHandler) {
      FCMService.instance.onMaterialRequest = _previousMaterialRequestHandler;
    }
    super.dispose();
  }

  Future<void> _loadRequests({
    bool showLoading = false,
    bool refreshPendingCount = false,
  }) async {
    if (showLoading && mounted) {
      setState(() => _isLoading = true);
    }

    try {
      final requests = await ApiService.getSMTRequests(
        status: _filterStatus == 'all' ? null : _filterStatus,
        lineId: _selectedLine,
        limit: 100,
        compact: ApiService.isSlowLinkAndroid,
      );
      final pendingCount = refreshPendingCount
          ? await ApiService.getSMTRequestsPendingCount(lineId: _selectedLine)
          : _lastPendingCount;
      if (mounted) {
        setState(() {
          _requests = requests;
          _isLoading = false;
          if (refreshPendingCount) {
            _lastPendingCount = pendingCount;
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _pollPendingCount() async {
    final count = await ApiService.getSMTRequestsPendingCount(lineId: _selectedLine);
    if (!mounted) return;
    if (count != _lastPendingCount) {
      await _loadRequests(refreshPendingCount: true);
    }
  }

  Future<void> _fulfillRequest(int id) async {
    final userName = AuthService.currentUser?.nombreCompleto ?? 'almacen';
    final success = await ApiService.fulfillSMTRequest(id, fulfilledBy: userName);

    if (success) {
      await FeedbackService.playSuccess();
      _loadRequests(refreshPendingCount: true);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Material marcado como surtido'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } else {
      await FeedbackService.playError();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Error al marcar como surtido'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Filtros
        _buildFilters(),

        // Lista de solicitudes
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _requests.isEmpty
                  ? _buildEmptyState()
                  : RefreshIndicator(
                      onRefresh: () => _loadRequests(refreshPendingCount: true),
                      child: ListView.builder(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        itemCount: _requests.length,
                        itemBuilder: (context, index) =>
                            _buildRequestCard(_requests[index]),
                      ),
                    ),
        ),
      ],
    );
  }

  Widget _buildFilters() {
    return Container(
      padding: const EdgeInsets.all(12),
      color: const Color(0xFF252A3C),
      child: Row(
        children: [
          // Filtro por línea
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1E2C),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white24),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String?>(
                  value: _selectedLine,
                  hint: const Text(
                    'Todas las lineas',
                    style: TextStyle(color: Colors.white54, fontSize: 14),
                  ),
                  dropdownColor: const Color(0xFF252A3C),
                  isExpanded: true,
                  icon: const Icon(Icons.arrow_drop_down, color: Colors.white54),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text(
                        'Todas las lineas',
                        style: TextStyle(color: Colors.white, fontSize: 14),
                      ),
                    ),
                    ..._smtLines.map((line) => DropdownMenuItem<String?>(
                          value: line,
                          child: Text(
                            _formatLineLabel(line),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                            ),
                          ),
                        )),
                  ],
                  onChanged: (value) {
                    setState(() => _selectedLine = value);
                    _loadRequests(showLoading: true, refreshPendingCount: true);
                  },
                ),
              ),
            ),
          ),

          const SizedBox(width: 8),

          // Filtro por status
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1E2C),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white24),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _filterStatus,
                dropdownColor: const Color(0xFF252A3C),
                icon: const Icon(Icons.arrow_drop_down, color: Colors.white54),
                items: const [
                  DropdownMenuItem(
                    value: 'pending',
                    child: Text('Pendientes',
                        style: TextStyle(color: Colors.amber, fontSize: 14)),
                  ),
                  DropdownMenuItem(
                    value: 'fulfilled',
                    child: Text('Surtidos',
                        style: TextStyle(color: Colors.green, fontSize: 14)),
                  ),
                  DropdownMenuItem(
                    value: 'all',
                    child: Text('Todos',
                        style: TextStyle(color: Colors.white, fontSize: 14)),
                  ),
                ],
                onChanged: (value) {
                  setState(() => _filterStatus = value ?? 'pending');
                  _loadRequests(showLoading: true, refreshPendingCount: true);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            _filterStatus == 'pending'
                ? Icons.check_circle_outline
                : Icons.inbox_outlined,
            size: 64,
            color: Colors.white24,
          ),
          const SizedBox(height: 16),
          Text(
            _filterStatus == 'pending'
                ? 'No hay solicitudes pendientes'
                : 'No hay solicitudes',
            style: const TextStyle(
              color: Colors.white38,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: () => _loadRequests(showLoading: true, refreshPendingCount: true),
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('Actualizar'),
          ),
        ],
      ),
    );
  }

  Widget _buildRequestCard(Map<String, dynamic> request) {
    final status = request['status'] ?? 'pending';
    final isPending = status == 'pending';
    final isFulfilled = status == 'fulfilled';
    final lineId = request['line_id'] ?? '';
    final lineLabel = _formatLineLabel(lineId.toString());
    final reelCode = request['reel_code']?.toString() ?? '';
    final partNumber =
        request['numero_parte']?.toString().trim().isNotEmpty == true
            ? request['numero_parte'].toString().trim()
            : _extractPartNumber(reelCode);
    final location = request['ubicacion_rollos']?.toString().trim() ?? '';
    final requestedAt = request['requested_at'] ?? '';
    final fulfilledBy = request['fulfilled_by'] ?? '';
    final fulfilledAt = request['fulfilled_at'] ?? '';
    final id = request['id'];

    // Parse time
    String timeStr = '';
    if (requestedAt.toString().length >= 16) {
      timeStr = requestedAt.toString().substring(11, 16);
    }

    String fulfilledTimeStr = '';
    if (fulfilledAt.toString().length >= 16) {
      fulfilledTimeStr = fulfilledAt.toString().substring(11, 16);
    }

    return Card(
      color: const Color(0xFF252A3C),
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
          color: isPending
              ? Colors.amber.withAlpha(100)
              : isFulfilled
                  ? Colors.green.withAlpha(60)
                  : Colors.white12,
          width: isPending ? 2 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header: Line + Status + Time
            Row(
              children: [
                // Line badge
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.amber.withAlpha(30),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    lineLabel,
                    style: const TextStyle(
                      color: Colors.amber,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ),

                const SizedBox(width: 8),

                // Status badge
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: isPending
                        ? Colors.amber.withAlpha(20)
                        : isFulfilled
                            ? Colors.green.withAlpha(20)
                            : Colors.grey.withAlpha(20),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    isPending
                        ? 'PENDIENTE'
                        : isFulfilled
                            ? 'SURTIDO'
                            : status.toUpperCase(),
                    style: TextStyle(
                      color: isPending
                          ? Colors.amber
                          : isFulfilled
                              ? Colors.green
                              : Colors.grey,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),

                const Spacer(),

                // Time
                Icon(
                  Icons.access_time,
                  size: 14,
                  color: Colors.white.withAlpha(80),
                ),
                const SizedBox(width: 4),
                Text(
                  timeStr,
                  style: TextStyle(
                    color: Colors.white.withAlpha(120),
                    fontSize: 13,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 10),

            // Reel code
            Row(
              children: [
                const Icon(Icons.qr_code, size: 18, color: Colors.white54),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    partNumber,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 8),

            Row(
              children: [
                const Icon(
                  Icons.location_on_outlined,
                  size: 18,
                  color: Colors.white54,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    location.isNotEmpty
                        ? location
                        : 'Ubicacion de rollos no configurada',
                    style: TextStyle(
                      color: location.isNotEmpty
                          ? Colors.white70
                          : Colors.orangeAccent.withAlpha(180),
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),

            // Fulfilled info
            if (isFulfilled && fulfilledBy.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                'Surtido por $fulfilledBy a las $fulfilledTimeStr',
                style: TextStyle(
                  color: Colors.green.withAlpha(150),
                  fontSize: 12,
                ),
              ),
            ],

            // Action button for pending
            if (isPending) ...[
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => _fulfillRequest(id),
                  icon: const Icon(Icons.check, size: 20),
                  label: const Text(
                    'MARCAR COMO SURTIDO',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
