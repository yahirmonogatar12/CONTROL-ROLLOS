import 'dart:async';
import 'package:flutter/material.dart';
import 'package:material_warehousing_flutter/core/services/api_service.dart';
import 'package:material_warehousing_flutter/core/services/auth_service.dart';
import 'package:material_warehousing_flutter/core/services/feedback_service.dart';
import 'package:material_warehousing_flutter/core/localization/app_translations.dart';

/// Pantalla desktop de solicitudes de material SMT pendientes.
/// Permite al personal de almacén ver y surtir solicitudes de las líneas SMT.
class SMTRequestsScreen extends StatefulWidget {
  final LanguageProvider languageProvider;

  const SMTRequestsScreen({
    super.key,
    required this.languageProvider,
  });

  @override
  State<SMTRequestsScreen> createState() => SMTRequestsScreenState();
}

class SMTRequestsScreenState extends State<SMTRequestsScreen> {
  List<Map<String, dynamic>> _requests = [];
  bool _isLoading = true;
  String? _selectedLine;
  String _filterStatus = 'pending';
  Timer? _refreshTimer;
  int _lastPendingCount = 0;

  static const List<String> _smtLines = ['SA', 'SB', 'SC', 'SD', 'SE'];
  static const Map<String, String> _lineLabels = {
    'SA': 'SMT A',
    'SB': 'SMT B',
    'SC': 'SMT C',
    'SD': 'SMT D',
    'SE': 'SMT E',
  };

  /// Expone el conteo de pendientes para el badge del tab.
  int get pendingCount => _lastPendingCount;

  /// Requerido por el sistema de tabs (compatibilidad con focus de escaneo).
  void requestScanFocus() {}

  @override
  void initState() {
    super.initState();
    _loadRequests(showLoading: true, refreshPendingCount: true);
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _pollPendingCount(),
    );
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadRequests({
    bool showLoading = false,
    bool refreshPendingCount = false,
  }) async {
    if (showLoading && mounted) setState(() => _isLoading = true);

    try {
      final requests = await ApiService.getSMTRequests(
        status: _filterStatus == 'all' ? null : _filterStatus,
        lineId: _selectedLine,
        limit: 100,
      );
      final pendingCount = refreshPendingCount
          ? await ApiService.getSMTRequestsPendingCount(lineId: _selectedLine)
          : _lastPendingCount;

      if (mounted) {
        setState(() {
          _requests = requests;
          _isLoading = false;
          if (refreshPendingCount) _lastPendingCount = pendingCount;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _pollPendingCount() async {
    final count =
        await ApiService.getSMTRequestsPendingCount(lineId: _selectedLine);
    if (!mounted) return;
    if (count != _lastPendingCount) {
      await _loadRequests(refreshPendingCount: true);
    }
  }

  Future<void> _fulfillRequest(int id) async {
    final userName = AuthService.currentUser?.nombreCompleto ?? 'almacen';
    final success =
        await ApiService.fulfillSMTRequest(id, fulfilledBy: userName);

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

  String _formatLineLabel(String? lineId) =>
      lineId == null || lineId.isEmpty ? '' : (_lineLabels[lineId] ?? lineId);

  String _extractPartNumber(String? reelCode) {
    final normalized = (reelCode ?? '').trim();
    if (normalized.isEmpty) return '';
    return normalized.split('-').first.trim();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildToolbar(),
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _requests.isEmpty
                  ? _buildEmptyState()
                  : _buildRequestList(),
        ),
      ],
    );
  }

  Widget _buildToolbar() {
    return Container(
      height: 44,
      color: const Color(0xFF1E2533),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          // Dropdown línea
          SizedBox(
            width: 160,
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String?>(
                value: _selectedLine,
                hint: const Text(
                  'Todas las líneas',
                  style: TextStyle(color: Colors.white54, fontSize: 13),
                ),
                dropdownColor: const Color(0xFF252A3C),
                isExpanded: true,
                icon:
                    const Icon(Icons.arrow_drop_down, color: Colors.white54),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text(
                      'Todas las líneas',
                      style: TextStyle(color: Colors.white, fontSize: 13),
                    ),
                  ),
                  ..._smtLines.map((line) => DropdownMenuItem<String?>(
                        value: line,
                        child: Text(
                          _formatLineLabel(line),
                          style: const TextStyle(
                              color: Colors.white, fontSize: 13),
                        ),
                      )),
                ],
                onChanged: (v) {
                  setState(() => _selectedLine = v);
                  _loadRequests(showLoading: true, refreshPendingCount: true);
                },
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Dropdown estado
          DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _filterStatus,
              dropdownColor: const Color(0xFF252A3C),
              icon:
                  const Icon(Icons.arrow_drop_down, color: Colors.white54),
              items: const [
                DropdownMenuItem(
                  value: 'pending',
                  child: Text('Pendientes',
                      style: TextStyle(color: Colors.amber, fontSize: 13)),
                ),
                DropdownMenuItem(
                  value: 'fulfilled',
                  child: Text('Surtidos',
                      style: TextStyle(color: Colors.green, fontSize: 13)),
                ),
                DropdownMenuItem(
                  value: 'all',
                  child: Text('Todos',
                      style: TextStyle(color: Colors.white, fontSize: 13)),
                ),
              ],
              onChanged: (v) {
                setState(() => _filterStatus = v ?? 'pending');
                _loadRequests(showLoading: true, refreshPendingCount: true);
              },
            ),
          ),
          const Spacer(),
          // Contador pendientes
          if (_lastPendingCount > 0)
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.amber.withOpacity(0.15),
                borderRadius: BorderRadius.circular(12),
                border:
                    Border.all(color: Colors.amber.withOpacity(0.4)),
              ),
              child: Text(
                '$_lastPendingCount pendiente${_lastPendingCount != 1 ? 's' : ''}',
                style: const TextStyle(
                  color: Colors.amber,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ),
          const SizedBox(width: 8),
          // Botón refrescar
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white54, size: 20),
            tooltip: 'Actualizar',
            onPressed: () =>
                _loadRequests(showLoading: true, refreshPendingCount: true),
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
            size: 72,
            color: Colors.white24,
          ),
          const SizedBox(height: 16),
          Text(
            _filterStatus == 'pending'
                ? 'No hay solicitudes pendientes'
                : 'No hay solicitudes',
            style: const TextStyle(color: Colors.white38, fontSize: 16),
          ),
          const SizedBox(height: 12),
          TextButton.icon(
            onPressed: () =>
                _loadRequests(showLoading: true, refreshPendingCount: true),
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('Actualizar'),
          ),
        ],
      ),
    );
  }

  Widget _buildRequestList() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _requests.length,
      itemBuilder: (context, index) => _buildRequestRow(_requests[index]),
    );
  }

  Widget _buildRequestRow(Map<String, dynamic> request) {
    final status = request['status'] ?? 'pending';
    final isPending = status == 'pending';
    final isFulfilled = status == 'fulfilled';
    final lineId = request['line_id']?.toString() ?? '';
    final lineLabel = _formatLineLabel(lineId);
    final reelCode = request['reel_code']?.toString() ?? '';
    final partNumber =
        request['numero_parte']?.toString().trim().isNotEmpty == true
            ? request['numero_parte'].toString().trim()
            : _extractPartNumber(reelCode);
    final location = request['ubicacion_rollos']?.toString().trim() ?? '';
    final requestedAt = request['requested_at']?.toString() ?? '';
    final fulfilledBy = request['fulfilled_by']?.toString() ?? '';
    final fulfilledAt = request['fulfilled_at']?.toString() ?? '';
    final id = request['id'];

    String timeStr = '';
    if (requestedAt.length >= 16) timeStr = requestedAt.substring(11, 16);
    String fulfilledTimeStr = '';
    if (fulfilledAt.length >= 16) {
      fulfilledTimeStr = fulfilledAt.substring(11, 16);
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF252A3C),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isPending
              ? Colors.amber.withOpacity(0.4)
              : isFulfilled
                  ? Colors.green.withOpacity(0.25)
                  : Colors.white12,
          width: isPending ? 1.5 : 1,
        ),
      ),
      child: Padding(
        padding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            // Badge línea
            Container(
              width: 72,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.amber.withOpacity(0.15),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                lineLabel,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.amber,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            ),
            const SizedBox(width: 12),
            // Badge estado
            Container(
              width: 82,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: isPending
                    ? Colors.amber.withOpacity(0.1)
                    : isFulfilled
                        ? Colors.green.withOpacity(0.1)
                        : Colors.grey.withOpacity(0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                isPending
                    ? 'PENDIENTE'
                    : isFulfilled
                        ? 'SURTIDO'
                        : status.toUpperCase(),
                textAlign: TextAlign.center,
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
            const SizedBox(width: 16),
            // Número de parte
            Expanded(
              flex: 3,
              child: Row(
                children: [
                  const Icon(Icons.qr_code, size: 14, color: Colors.white38),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      partNumber,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        fontFamily: 'monospace',
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            // Ubicación
            Expanded(
              flex: 3,
              child: Row(
                children: [
                  const Icon(Icons.location_on_outlined,
                      size: 14, color: Colors.white38),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      location.isNotEmpty ? location : 'Sin ubicación',
                      style: TextStyle(
                        color: location.isNotEmpty
                            ? Colors.white70
                            : Colors.orangeAccent.withOpacity(0.7),
                        fontSize: 13,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            // Hora / quién surtió
            SizedBox(
              width: 160,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (timeStr.isNotEmpty)
                    Text(
                      timeStr,
                      style: const TextStyle(
                          color: Colors.white38, fontSize: 12),
                    ),
                  if (isFulfilled && fulfilledBy.isNotEmpty)
                    Text(
                      'Por $fulfilledBy'
                      '${fulfilledTimeStr.isNotEmpty ? ' $fulfilledTimeStr' : ''}',
                      style: TextStyle(
                          color: Colors.green.withOpacity(0.7),
                          fontSize: 11),
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            // Botón acción
            if (isPending) ...[
              const SizedBox(width: 12),
              ElevatedButton.icon(
                onPressed: () => _fulfillRequest(id),
                icon: const Icon(Icons.check, size: 16),
                label: const Text(
                  'SURTIR',
                  style: TextStyle(
                      fontSize: 12, fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 8),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
              ),
            ] else
              const SizedBox(width: 104),
          ],
        ),
      ),
    );
  }
}
