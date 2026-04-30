import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:material_warehousing_flutter/core/localization/app_translations.dart';
import 'package:material_warehousing_flutter/core/services/api_service.dart';
import 'package:material_warehousing_flutter/core/services/auth_service.dart';
import 'package:material_warehousing_flutter/core/services/scan_batcher.dart';
import 'package:material_warehousing_flutter/core/services/scanner_config_service.dart';
import 'package:material_warehousing_flutter/core/theme/app_colors.dart';

/// Pantalla de entrada de material para móvil
/// Dos modos:
///   1. Pendientes de Almacén - Confirmar salidas de almacén (sin impresión)
///   2. Escaneo Manual - Escanear código y confirmar entrada (sin impresión)
class MobileEntryScreen extends StatefulWidget {
  final LanguageProvider languageProvider;

  const MobileEntryScreen({
    super.key,
    required this.languageProvider,
  });

  @override
  State<MobileEntryScreen> createState() => _MobileEntryScreenState();
}

class _MobileEntryScreenState extends State<MobileEntryScreen> {
  // --- Modo de operación ---
  bool _useManualScan = false; // false = Pendientes, true = Escaneo Manual

  // --- Estado: Modo Pendientes ---
  List<Map<String, dynamic>> _pending = [];
  List<Map<String, dynamic>> _groups = [];
  final Map<String, Set<int>> _selectedByPart = {};
  final Map<int, String> _assignedLocations = {};
  bool _isLoadingPending = false;
  final Set<String> _confirmingParts = {};
  DateTime _filterStartDate = DateTime.now().subtract(const Duration(days: 7));
  DateTime _filterEndDate = DateTime.now();
  String _searchFilter = '';
  String? _expandedPart; // Parte expandida actualmente

  // --- Estado: Modo Escaneo Manual ---
  MobileScannerController? _scannerController;
  final TextEditingController _readerInputController = TextEditingController();
  final FocusNode _readerFocusNode = FocusNode();
  bool _isScanning = false;
  bool _isLoading = false;
  String? _lastScannedCode;
  Map<String, dynamic>? _scannedMaterialInfo;
  String? _detectedCode;
  bool _codeReady = false;
  final TextEditingController _ubicacionDestinoController = TextEditingController();
  bool _isConfirming = false;
  List<String> _expectedLocations = [];
  ScanBatcher<Map<String, dynamic>>? _materialLookupBatcher;
  String? _activeLookupCode;

  String tr(String key) => widget.languageProvider.tr(key);

  @override
  void initState() {
    super.initState();
    if (ApiService.isSlowLinkAndroid) {
      _materialLookupBatcher = ScanBatcher<Map<String, dynamic>>(
        loader: (codes) async {
          final results = await ApiService.searchWarehouseMaterials(codes);
          final mapped = <String, Map<String, dynamic>>{};
          for (final result in results) {
            final inputCode = result['inputCode']?.toString();
            if (inputCode != null && inputCode.isNotEmpty) {
              mapped[inputCode] = result;
            }
          }
          return mapped;
        },
      );
    }
    _loadPendingOutgoing();
  }

  @override
  void dispose() {
    _materialLookupBatcher?.dispose();
    _scannerController?.dispose();
    _readerInputController.dispose();
    _readerFocusNode.dispose();
    _ubicacionDestinoController.dispose();
    super.dispose();
  }

  // ====================================================================
  // MODO 1: PENDIENTES DE ALMACÉN
  // ====================================================================

  String? _pendingError; // Mensaje de error para mostrar en UI

  Future<void> _loadPendingOutgoing() async {
    setState(() {
      _isLoadingPending = true;
      _pendingError = null;
    });
    try {
      final fechaInicio = _formatDateForApi(_filterStartDate);
      final fechaFin = _formatDateForApi(_filterEndDate);
      debugPrint('[MobileEntry] Cargando pendientes: $fechaInicio → $fechaFin');

      final result = await ApiService.getPendingWarehouseOutgoing(
        fechaInicio: fechaInicio,
        fechaFin: fechaFin,
        compact: ApiService.isSlowLinkAndroid,
        groupedByPart: ApiService.isSlowLinkAndroid,
      );

      debugPrint('[MobileEntry] Respuesta: success=${result['success']}, data_length=${(result['data'] as List?)?.length ?? 'null'}');

      // El backend responde {data: [...], count: N} sin campo 'success'
      // Aceptar si 'data' existe (success puede ser null o true)
      if (result.containsKey('data') && result['success'] != false) {
        final data = _normalizeMapList(result['data']);
        final groups = _normalizePendingGroups(result['groups']);
        setState(() {
          _pending = data;
          _groups = groups.isNotEmpty ? groups : _buildGroups(data);
          _isLoadingPending = false;
        });
      } else {
        final errorMsg = result['error']?.toString() ?? 'Error desconocido del servidor';
        debugPrint('[MobileEntry] Error en respuesta: $errorMsg');
        setState(() {
          _pending = [];
          _groups = [];
          _isLoadingPending = false;
          _pendingError = errorMsg;
        });
        _showMessage('Error: $errorMsg', isError: true);
      }
    } catch (e) {
      debugPrint('[MobileEntry] Excepcion: $e');
      setState(() {
        _pending = [];
        _groups = [];
        _isLoadingPending = false;
        _pendingError = e.toString();
      });
      _showMessage('Error cargando pendientes: $e', isError: true);
    }
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
          'ubicacion_rollos': row['ubicacion_rollos']?.toString() ?? '',
        };
      }

      final group = groups[partNumber]!;
      group['total_qty'] = (group['total_qty'] as num) + qty;
      group['count'] = (group['count'] as int) + 1;
      (group['items'] as List<Map<String, dynamic>>).add(row);
    }

    final list = groups.values.toList();
    list.sort((a, b) => (b['latest_date']?.toString() ?? '')
        .compareTo(a['latest_date']?.toString() ?? ''));
    return list;
  }

  List<Map<String, dynamic>> _normalizeMapList(dynamic value) {
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  List<Map<String, dynamic>> _normalizePendingGroups(dynamic value) {
    return _normalizeMapList(value).map((group) {
      final items = _normalizeMapList(group['items']);
      final rawCount = group['count'];

      return {
        ...group,
        'numero_parte': group['numero_parte']?.toString() ?? '-',
        'count': rawCount is num
            ? rawCount.toInt()
            : int.tryParse(rawCount?.toString() ?? '') ?? items.length,
        'total_qty': _parseQty(group['total_qty']),
        'latest_date': group['latest_date']?.toString(),
        'ubicacion_rollos': group['ubicacion_rollos']?.toString() ?? '',
        'items': items,
      };
    }).toList();
  }

  num _parseQty(dynamic value) {
    if (value == null) return 0;
    if (value is num) return value;
    return num.tryParse(value.toString()) ?? 0;
  }

  int? _rowId(Map<String, dynamic> row) {
    final id = row['id'];
    if (id is int) return id;
    if (id is String) return int.tryParse(id);
    return null;
  }

  Set<int> _selectedForPart(String partNumber) {
    return _selectedByPart.putIfAbsent(partNumber, () => <int>{});
  }

  void _toggleSelectRow(String partNumber, int rowId) {
    setState(() {
      final selected = _selectedForPart(partNumber);
      if (selected.contains(rowId)) {
        selected.remove(rowId);
      } else {
        selected.add(rowId);
      }
    });
  }

  void _toggleSelectAll(String partNumber, List<Map<String, dynamic>> items) {
    final selected = _selectedForPart(partNumber);
    final ids = items.map(_rowId).whereType<int>().toList();

    setState(() {
      if (selected.length == ids.length) {
        selected.clear();
      } else {
        selected.clear();
        selected.addAll(ids);
      }
    });
  }

  void _assignLocationToSelected(String partNumber, String ubicacion) {
    final selected = _selectedByPart[partNumber] ?? {};
    if (selected.isEmpty || ubicacion.trim().isEmpty) return;

    setState(() {
      for (final id in selected) {
        _assignedLocations[id] = ubicacion.trim();
      }
    });
    _showMessage('Ubicacion asignada a ${selected.length} items', isError: false);
  }

  Future<void> _confirmSelected(String partNumber) async {
    final ids = _selectedByPart[partNumber]?.toList() ?? [];
    if (ids.isEmpty) {
      _showMessage('Seleccione items para confirmar', isError: true);
      return;
    }

    // Verificar que todos tengan ubicación asignada
    final idsWithoutLocation = ids.where((id) =>
        !_assignedLocations.containsKey(id) || _assignedLocations[id]!.isEmpty
    ).toList();

    if (idsWithoutLocation.isNotEmpty) {
      _showMessage('${idsWithoutLocation.length} items sin ubicacion asignada', isError: true);
      return;
    }

    setState(() => _confirmingParts.add(partNumber));

    final currentUser = AuthService.currentUser;
    final usuario = currentUser?.nombreCompleto ?? currentUser?.username ?? 'Unknown';

    final Map<int, String> ubicacionesPorId = {};
    for (final id in ids) {
      ubicacionesPorId[id] = _assignedLocations[id]!;
    }

    try {
      final result = await ApiService.confirmWarehouseOutgoingByIds(
        ids: ids,
        usuario: usuario,
        ubicacionesPorId: ubicacionesPorId,
      );

      if (result['success'] == true) {
        final confirmed = (result['confirmed'] as int?) ?? ids.length;
        final skipped = (result['skipped'] as int?) ?? 0;

        // Limpiar ubicaciones confirmadas
        for (final id in ids) {
          _assignedLocations.remove(id);
        }
        _selectedByPart[partNumber]?.clear();

        String msg = '${tr('entry_confirmed')} ($confirmed/${ids.length})';
        if (skipped > 0) msg += ' - Omitidos: $skipped';
        _showMessage(msg, isError: false);

        await _loadPendingOutgoing();
      } else {
        _showMessage(result['error']?.toString() ?? 'Error confirmando', isError: true);
      }
    } catch (e) {
      _showMessage('Error: $e', isError: true);
    }

    setState(() => _confirmingParts.remove(partNumber));
  }

  Future<void> _rejectSelected(String partNumber) async {
    final ids = _selectedByPart[partNumber]?.toList() ?? [];
    if (ids.isEmpty) {
      _showMessage('Seleccione items para rechazar', isError: true);
      return;
    }

    // Pedir motivo de rechazo
    final reasonController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF252A3C),
        title: Text(tr('reject'), style: const TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${ids.length} items seleccionados',
              style: const TextStyle(color: Colors.white70),
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
                fillColor: const Color(0xFF1A1E2C),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(tr('cancel')),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              if (reasonController.text.trim().isEmpty) {
                _showMessage('Ingrese un motivo de rechazo', isError: true);
                return;
              }
              Navigator.pop(context, true);
            },
            child: Text(tr('reject')),
          ),
        ],
      ),
    );

    final motivo = reasonController.text.trim();
    reasonController.dispose();
    if (confirmed != true || motivo.isEmpty) return;

    final currentUser = AuthService.currentUser;
    final usuario = currentUser?.nombreCompleto ?? currentUser?.username ?? 'Unknown';

    try {
      final result = await ApiService.rejectWarehouseOutgoingByIds(
        ids: ids,
        motivo: motivo,
        usuario: usuario,
      );

      if (result['success'] == true) {
        _selectedByPart[partNumber]?.clear();
        _showMessage('${ids.length} items rechazados', isError: false);
        await _loadPendingOutgoing();
      } else {
        _showMessage(result['error']?.toString() ?? 'Error rechazando', isError: true);
      }
    } catch (e) {
      _showMessage('Error: $e', isError: true);
    }
  }

  // ====================================================================
  // MODO 2: ESCANEO MANUAL
  // ====================================================================

  void _startScanner() {
    setState(() {
      _isScanning = true;
      _lastScannedCode = null;
      _scannedMaterialInfo = null;
      _detectedCode = null;
      _codeReady = false;
      _expectedLocations = [];
      _ubicacionDestinoController.clear();
    });

    if (ScannerConfigService.isReaderMode) {
      Future.delayed(const Duration(milliseconds: 100), () {
        if (mounted) _readerFocusNode.requestFocus();
      });
      return;
    }

    _scannerController?.dispose();
    _scannerController = MobileScannerController(
      detectionSpeed: DetectionSpeed.normal,
      facing: CameraFacing.back,
      torchEnabled: false,
    );
  }

  void _stopScanner() {
    _scannerController?.stop();
    _readerInputController.clear();
    setState(() {
      _isScanning = false;
      _detectedCode = null;
      _codeReady = false;
    });
  }

  void _onReaderInput(String value) {
    if (value.isEmpty) return;
    final code = value.trim();
    _readerInputController.clear();

    setState(() {
      _detectedCode = code;
      _codeReady = true;
      _lastScannedCode = code;
    });

    _stopScanner();
    _searchWarehouseMaterial(code);
  }

  void _onBarcodeDetected(BarcodeCapture capture) {
    if (capture.barcodes.isEmpty) return;
    final barcode = capture.barcodes.first;
    if (barcode.rawValue == null) return;

    final scannedCode = barcode.rawValue!;
    if (_detectedCode != scannedCode) {
      setState(() {
        _detectedCode = scannedCode;
        _codeReady = true;
      });
    }
  }

  void _confirmScan() {
    if (_detectedCode == null || !_codeReady) {
      _showMessage('Apunte al codigo y espere a que se detecte', isError: true);
      return;
    }

    setState(() => _lastScannedCode = _detectedCode);
    _stopScanner();
    _searchWarehouseMaterial(_lastScannedCode!);
  }

  /// Buscar material en almacén para confirmar entrada
  Future<void> _searchWarehouseMaterial(String code) async {
    final normalizedCode = code.trim();
    _activeLookupCode = normalizedCode;
    setState(() {
      _isLoading = true;
      _scannedMaterialInfo = null;
      _expectedLocations = [];
      _ubicacionDestinoController.clear();
    });

    try {
      final result = await _lookupWarehouseMaterial(normalizedCode);

      if (!mounted || _activeLookupCode != normalizedCode) return;

      if (result['success'] == true) {
        final data = result['data'] as Map<String, dynamic>;

        // Extraer ubicaciones esperadas
        final ubicacionRollosStr = data['ubicacion_rollos']?.toString() ?? '';
        final locations = ubicacionRollosStr.isNotEmpty
            ? ubicacionRollosStr.split(',').map((v) => v.trim()).where((v) => v.isNotEmpty).toList()
            : <String>[];

        setState(() {
          _isLoading = false;
          _scannedMaterialInfo = data;
          _expectedLocations = locations;
          if (locations.isNotEmpty) {
            _ubicacionDestinoController.text = locations.first;
          }
        });
        _showMessage('Material encontrado: ${data['numero_parte'] ?? normalizedCode}', isError: false);
      } else {
        setState(() => _isLoading = false);
        final error = result['error']?.toString() ?? 'unknown';
        String message;
        switch (error) {
          case 'no_warehouse_exit':
            message = tr('no_warehouse_exit');
            break;
          case 'material_not_found':
            message = tr('material_not_found');
            break;
          case 'cancelled':
            message = tr('material_cancelled');
            break;
          case 'already_in_smd':
            message = 'Este material ya existe en el almacen SMD';
            break;
          default:
            message = result['message']?.toString() ?? 'Error buscando material';
        }
        _showMessage(message, isError: true);
      }
    } catch (e) {
      setState(() => _isLoading = false);
      _showMessage('Error: $e', isError: true);
    }
  }

  Future<Map<String, dynamic>> _lookupWarehouseMaterial(String code) async {
    if (!ApiService.isSlowLinkAndroid || _materialLookupBatcher == null) {
      return ApiService.searchWarehouseMaterial(code);
    }

    final result = await _materialLookupBatcher!.enqueue(code);
    if (result != null) {
      return result;
    }

    return {
      'success': false,
      'error': 'material_not_found',
      'message': 'Material no encontrado en almacén',
    };
  }

  /// Confirmar entrada individual (modo escaneo manual)
  Future<void> _confirmManualEntry() async {
    if (_scannedMaterialInfo == null) {
      _showMessage('Escanee un material primero', isError: true);
      return;
    }

    final codigo = _scannedMaterialInfo!['codigo_material_recibido']?.toString() ?? '';
    if (codigo.isEmpty) {
      _showMessage('Codigo de material no disponible', isError: true);
      return;
    }

    final ubicacionDestino = _ubicacionDestinoController.text.trim();
    if (ubicacionDestino.isEmpty) {
      _showMessage(tr('destination_required'), isError: true);
      return;
    }

    // Validar ubicacion contra las esperadas
    if (_expectedLocations.isNotEmpty) {
      final matches = _expectedLocations.any(
        (loc) => loc.toUpperCase() == ubicacionDestino.toUpperCase()
      );
      if (!matches) {
        _showMessage('Ubicacion no coincide. Esperadas: ${_expectedLocations.join(', ')}', isError: true);
        return;
      }
    }

    setState(() => _isConfirming = true);

    final currentUser = AuthService.currentUser;
    final usuario = currentUser?.nombreCompleto ?? currentUser?.username ?? 'Unknown';

    try {
      final result = await ApiService.confirmWarehouseOutgoing(
        codigoMaterialRecibido: codigo,
        usuario: usuario,
        ubicacionDestino: ubicacionDestino,
      );

      if (!mounted) return;

      if (result['success'] == true) {
        final insertedAlmacen = result['inserted_almacen'];
        if (insertedAlmacen == false) {
          _showMessage('Material ya existe en almacen SMD: $codigo', isError: false);
        } else {
          _showMessage('${tr('entry_confirmed')}: $codigo', isError: false);
        }

        // Limpiar para siguiente escaneo
        setState(() {
          _scannedMaterialInfo = null;
          _lastScannedCode = null;
          _ubicacionDestinoController.clear();
          _expectedLocations = [];
          _isConfirming = false;
        });
      } else if (result['already_confirmed'] == true) {
        _showMessage(tr('already_confirmed'), isError: true);
        setState(() => _isConfirming = false);
      } else {
        _showMessage(result['error']?.toString() ?? 'Error confirmando', isError: true);
        setState(() => _isConfirming = false);
      }
    } catch (e) {
      _showMessage('Error: $e', isError: true);
      setState(() => _isConfirming = false);
    }
  }

  // ====================================================================
  // HELPERS
  // ====================================================================

  String _formatDateForApi(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  String _formatDate(dynamic date) {
    if (date == null) return '-';
    try {
      final dt = DateTime.parse(date.toString());
      return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
    } catch (e) {
      return date.toString();
    }
  }

  void _showMessage(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: isError ? 3 : 2),
      ),
    );
  }

  // ====================================================================
  // BUILD
  // ====================================================================

  @override
  Widget build(BuildContext context) {
    if (!AuthService.canWriteWarehousing) {
      return _buildNoPermissionScreen();
    }

    return Column(
      children: [
        // Selector de modo
        _buildModeSelector(),
        // Contenido según modo
        Expanded(
          child: _useManualScan ? _buildManualScanMode() : _buildPendingMode(),
        ),
      ],
    );
  }

  Widget _buildNoPermissionScreen() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.lock, size: 64, color: Colors.white.withOpacity(0.3)),
          const SizedBox(height: 16),
          Text(
            tr('no_permission_mobile'),
            style: const TextStyle(color: Colors.white54, fontSize: 16),
          ),
        ],
      ),
    );
  }

  Widget _buildModeSelector() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: const Color(0xFF252A3C),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _useManualScan = false),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: !_useManualScan ? AppColors.headerTab : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.pending_actions,
                      color: !_useManualScan ? Colors.white : Colors.white54,
                      size: 18,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      tr('pending_entries'),
                      style: TextStyle(
                        color: !_useManualScan ? Colors.white : Colors.white54,
                        fontWeight: !_useManualScan ? FontWeight.bold : FontWeight.normal,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _useManualScan = true),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: _useManualScan ? AppColors.headerTab : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.qr_code_scanner,
                      color: _useManualScan ? Colors.white : Colors.white54,
                      size: 18,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      tr('manual_scan'),
                      style: TextStyle(
                        color: _useManualScan ? Colors.white : Colors.white54,
                        fontWeight: _useManualScan ? FontWeight.bold : FontWeight.normal,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ====================================================================
  // MODO 1: PENDIENTES UI
  // ====================================================================

  Widget _buildPendingMode() {
    return Column(
      children: [
        // Filtro de fechas y búsqueda
        _buildPendingFilters(),
        // Lista de grupos
        Expanded(
          child: _isLoadingPending
              ? const Center(child: CircularProgressIndicator())
              : _groups.isEmpty
                  ? _buildEmptyPending()
                  : RefreshIndicator(
                      onRefresh: _loadPendingOutgoing,
                      child: ListView.builder(
                        padding: const EdgeInsets.all(12),
                        itemCount: _filteredGroups.length,
                        itemBuilder: (context, index) =>
                            _buildGroupCard(_filteredGroups[index]),
                      ),
                    ),
        ),
      ],
    );
  }

  List<Map<String, dynamic>> get _filteredGroups {
    if (_searchFilter.isEmpty) return _groups;
    final query = _searchFilter.toUpperCase();
    return _groups.where((g) {
      final partNumber = g['numero_parte']?.toString().toUpperCase() ?? '';
      return partNumber.contains(query);
    }).toList();
  }

  Widget _buildPendingFilters() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: const Color(0xFF1A1E2C),
      child: Column(
        children: [
          // Fila de fechas
          Row(
            children: [
              // Fecha inicio
              Expanded(
                child: GestureDetector(
                  onTap: () async {
                    final date = await showDatePicker(
                      context: context,
                      initialDate: _filterStartDate,
                      firstDate: DateTime(2024),
                      lastDate: DateTime.now(),
                    );
                    if (date != null) {
                      setState(() => _filterStartDate = date);
                      _loadPendingOutgoing();
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF252A3C),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.calendar_today, color: Colors.white54, size: 14),
                        const SizedBox(width: 6),
                        Text(
                          _formatDate(_filterStartDate.toIso8601String()),
                          style: const TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 6),
                child: Text('-', style: TextStyle(color: Colors.white54)),
              ),
              // Fecha fin
              Expanded(
                child: GestureDetector(
                  onTap: () async {
                    final date = await showDatePicker(
                      context: context,
                      initialDate: _filterEndDate,
                      firstDate: DateTime(2024),
                      lastDate: DateTime.now().add(const Duration(days: 1)),
                    );
                    if (date != null) {
                      setState(() => _filterEndDate = date);
                      _loadPendingOutgoing();
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF252A3C),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.calendar_today, color: Colors.white54, size: 14),
                        const SizedBox(width: 6),
                        Text(
                          _formatDate(_filterEndDate.toIso8601String()),
                          style: const TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Refresh
              IconButton(
                icon: const Icon(Icons.refresh, color: AppColors.headerTab, size: 22),
                onPressed: _loadPendingOutgoing,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Búsqueda por parte
          TextField(
            style: const TextStyle(color: Colors.white, fontSize: 13),
            decoration: InputDecoration(
              hintText: tr('search_by_part_number'),
              hintStyle: const TextStyle(color: Colors.white38, fontSize: 12),
              prefixIcon: const Icon(Icons.search, color: Colors.white54, size: 18),
              filled: true,
              fillColor: const Color(0xFF252A3C),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: BorderSide.none,
              ),
            ),
            onChanged: (value) => setState(() => _searchFilter = value),
          ),
          // Contador
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(
              children: [
                Text(
                  '${_filteredGroups.length} ${tr('groups')} | ${_pending.length} items',
                  style: const TextStyle(color: Colors.white38, fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyPending() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            _pendingError != null ? Icons.cloud_off : Icons.inbox,
            size: 64,
            color: Colors.white.withOpacity(0.2),
          ),
          const SizedBox(height: 16),
          Text(
            _pendingError != null ? 'Error de conexion' : tr('no_pending_entries'),
            style: const TextStyle(color: Colors.white54, fontSize: 16),
          ),
          const SizedBox(height: 8),
          Text(
            _pendingError ?? tr('no_pending_entries_hint'),
            style: TextStyle(
              color: _pendingError != null ? Colors.red.shade300 : Colors.white38,
              fontSize: 13,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _loadPendingOutgoing,
            icon: const Icon(Icons.refresh),
            label: Text(tr('refresh')),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.headerTab,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGroupCard(Map<String, dynamic> group) {
    final partNumber = group['numero_parte']?.toString() ?? '-';
    final count = (group['count'] as num?)?.toInt() ?? 0;
    final totalQty = _parseQty(group['total_qty']);
    final items = _normalizeMapList(group['items']);
    final isExpanded = _expandedPart == partNumber;
    final selected = _selectedByPart[partNumber] ?? {};
    final isConfirming = _confirmingParts.contains(partNumber);

    // Ubicaciones esperadas del grupo
    final ubicacionStr = group['ubicacion_rollos']?.toString() ?? '';
    final expectedLocs = ubicacionStr.isNotEmpty
        ? ubicacionStr.split(',').map((v) => v.trim()).where((v) => v.isNotEmpty).toList()
        : <String>[];

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF252A3C),
        borderRadius: BorderRadius.circular(10),
        border: selected.isNotEmpty
            ? Border.all(color: AppColors.headerTab, width: 1.5)
            : null,
      ),
      child: Column(
        children: [
          // Header del grupo (tap para expandir)
          InkWell(
            onTap: () {
              setState(() {
                _expandedPart = isExpanded ? null : partNumber;
              });
            },
            borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  // Part number
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          partNumber,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'monospace',
                          ),
                        ),
                        const SizedBox(height: 4),
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: [
                            _buildChip('$count items', Colors.blue),
                            _buildChip('Qty: $totalQty', Colors.orange),
                            if (selected.isNotEmpty)
                              _buildChip('${selected.length} sel.', Colors.green),
                          ],
                        ),
                        if (expectedLocs.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              const Icon(Icons.location_on, size: 14, color: Colors.amber),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  expectedLocs.join(', '),
                                  style: const TextStyle(
                                    color: Colors.amber,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  Icon(
                    isExpanded ? Icons.expand_less : Icons.expand_more,
                    color: Colors.white54,
                  ),
                ],
              ),
            ),
          ),

          // Contenido expandido
          if (isExpanded) ...[
            const Divider(color: Colors.white12, height: 1),

            // Botón Seleccionar Todos
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Row(
                children: [
                  TextButton.icon(
                    onPressed: () => _toggleSelectAll(partNumber, items),
                    icon: Icon(
                      selected.length == items.length ? Icons.deselect : Icons.select_all,
                      size: 16,
                    ),
                    label: Text(
                      selected.length == items.length ? 'Deseleccionar' : 'Seleccionar Todo',
                      style: const TextStyle(fontSize: 12),
                    ),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.headerTab,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                  ),
                ],
              ),
            ),

            // Lista de items
            ...items.map((item) {
              final rowId = _rowId(item);
              final isSelected = rowId != null && selected.contains(rowId);
              final assignedLoc = rowId != null ? _assignedLocations[rowId] : null;

              return InkWell(
                onTap: rowId != null ? () => _toggleSelectRow(partNumber, rowId) : null,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? AppColors.headerTab.withOpacity(0.1)
                        : Colors.transparent,
                    border: const Border(
                      bottom: BorderSide(color: Colors.white12, width: 0.5),
                    ),
                  ),
                  child: Row(
                    children: [
                      // Checkbox
                      SizedBox(
                        width: 32,
                        child: Checkbox(
                          value: isSelected,
                          onChanged: rowId != null
                              ? (_) => _toggleSelectRow(partNumber, rowId)
                              : null,
                          activeColor: AppColors.headerTab,
                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Info del item
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item['codigo_material_recibido']?.toString() ?? '-',
                              style: const TextStyle(color: Colors.white, fontSize: 12, fontFamily: 'monospace'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Row(
                              children: [
                                Text(
                                  'Qty: ${_parseQty(item['cantidad_salida'])}',
                                  style: const TextStyle(color: Colors.white54, fontSize: 11),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  _formatDate(item['fecha_salida']),
                                  style: const TextStyle(color: Colors.white38, fontSize: 10),
                                ),
                              ],
                            ),
                            if (assignedLoc != null)
                              Row(
                                children: [
                                  const Icon(Icons.location_on, color: Colors.green, size: 12),
                                  const SizedBox(width: 4),
                                  Text(
                                    assignedLoc,
                                    style: const TextStyle(color: Colors.green, fontSize: 11, fontWeight: FontWeight.bold),
                                  ),
                                ],
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),

            // Panel de asignación de ubicación y acciones
            if (selected.isNotEmpty)
              _buildAssignmentPanel(partNumber, items, expectedLocs, isConfirming),
          ],
        ],
      ),
    );
  }

  Widget _buildAssignmentPanel(
    String partNumber,
    List<Map<String, dynamic>> items,
    List<String> expectedLocs,
    bool isConfirming,
  ) {
    final ubicController = TextEditingController(
      text: expectedLocs.isNotEmpty ? expectedLocs.first : '',
    );
    final selected = _selectedByPart[partNumber] ?? {};

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.headerTab.withOpacity(0.05),
        border: const Border(top: BorderSide(color: Colors.white24, width: 0.5)),
      ),
      child: Column(
        children: [
          // Campo de ubicación + botón asignar
          Row(
            children: [
              Expanded(
                child: expectedLocs.length > 1
                    ? DropdownButtonFormField<String>(
                        value: expectedLocs.first,
                        dropdownColor: const Color(0xFF1A1E2C),
                        style: const TextStyle(color: Colors.white, fontSize: 13),
                        decoration: InputDecoration(
                          labelText: tr('destination_location'),
                          labelStyle: const TextStyle(color: Colors.white54, fontSize: 11),
                          prefixIcon: const Icon(Icons.location_on, color: Colors.cyan, size: 16),
                          filled: true,
                          fillColor: const Color(0xFF1A1E2C),
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(6),
                            borderSide: BorderSide.none,
                          ),
                        ),
                        items: expectedLocs.map((loc) => DropdownMenuItem(
                          value: loc,
                          child: Text(loc, style: const TextStyle(fontSize: 13)),
                        )).toList(),
                        onChanged: (value) {
                          ubicController.text = value ?? '';
                        },
                      )
                    : TextField(
                        controller: ubicController,
                        style: const TextStyle(color: Colors.white, fontSize: 13),
                        decoration: InputDecoration(
                          labelText: tr('destination_location'),
                          labelStyle: const TextStyle(color: Colors.white54, fontSize: 11),
                          hintText: expectedLocs.isNotEmpty ? expectedLocs.first : tr('enter_location'),
                          hintStyle: const TextStyle(color: Colors.white38, fontSize: 11),
                          prefixIcon: const Icon(Icons.location_on, color: Colors.cyan, size: 16),
                          filled: true,
                          fillColor: const Color(0xFF1A1E2C),
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(6),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: () {
                  _assignLocationToSelected(partNumber, ubicController.text);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.cyan,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
                child: const Text('Asignar', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
          if (expectedLocs.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, size: 12, color: Colors.amber),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      '${tr('expected_location')}: ${expectedLocs.join(', ')}',
                      style: const TextStyle(fontSize: 10, color: Colors.amber),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 10),
          // Botones Confirmar / Rechazar
          Row(
            children: [
              // Rechazar
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: isConfirming ? null : () => _rejectSelected(partNumber),
                  icon: const Icon(Icons.close, size: 16),
                  label: Text(tr('reject'), style: const TextStyle(fontSize: 12)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red,
                    side: const BorderSide(color: Colors.red),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Confirmar
              Expanded(
                flex: 2,
                child: ElevatedButton.icon(
                  onPressed: isConfirming ? null : () => _confirmSelected(partNumber),
                  icon: isConfirming
                      ? const SizedBox(
                          width: 16, height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.check, size: 18),
                  label: Text(
                    isConfirming ? 'Confirmando...' : '${tr('confirm')} (${selected.length})',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.2),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold),
      ),
    );
  }

  // ====================================================================
  // MODO 2: ESCANEO MANUAL UI
  // ====================================================================

  Widget _buildManualScanMode() {
    if (_isScanning) return _buildScanner();
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_scannedMaterialInfo != null) return _buildMaterialConfirmForm();
    return _buildScanPrompt();
  }

  Widget _buildScanPrompt() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                color: AppColors.headerTab.withOpacity(0.1),
                borderRadius: BorderRadius.circular(60),
              ),
              child: const Icon(
                Icons.qr_code_scanner,
                size: 64,
                color: AppColors.headerTab,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              tr('scan_material'),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              tr('scan_material_instruction'),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withOpacity(0.6),
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton.icon(
                onPressed: _startScanner,
                icon: const Icon(Icons.camera_alt, size: 28),
                label: Text(tr('search'), style: const TextStyle(fontSize: 18)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.headerTab,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            TextButton.icon(
              onPressed: _showManualCodeDialog,
              icon: const Icon(Icons.keyboard, size: 20),
              label: Text(tr('scan_or_enter_code')),
              style: TextButton.styleFrom(foregroundColor: Colors.white54),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildScanner() {
    // Modo lector/PDA
    if (ScannerConfigService.isReaderMode) {
      return Container(
        color: const Color(0xFF1A1E2C),
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.barcode_reader,
              size: 80,
              color: Colors.white.withOpacity(0.5),
            ),
            const SizedBox(height: 24),
            Text(
              tr('scan_with_reader'),
              style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              tr('reader_mode_hint'),
              style: const TextStyle(color: Colors.white54, fontSize: 14),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _readerInputController,
              focusNode: _readerFocusNode,
              autofocus: true,
              style: const TextStyle(color: Colors.white, fontSize: 18),
              decoration: InputDecoration(
                labelText: tr('scanned_code'),
                prefixIcon: const Icon(Icons.qr_code_scanner, color: Colors.white54),
                border: const OutlineInputBorder(),
                filled: true,
                fillColor: const Color(0xFF252A3C),
              ),
              onSubmitted: _onReaderInput,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _stopScanner,
              icon: const Icon(Icons.close),
              label: Text(tr('cancel')),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red.withOpacity(0.8),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
            ),
          ],
        ),
      );
    }

    // Modo cámara
    return Stack(
      children: [
        MobileScanner(
          controller: _scannerController!,
          onDetect: _onBarcodeDetected,
        ),
        // Overlay
        Center(
          child: Container(
            width: 280,
            height: 180,
            decoration: BoxDecoration(
              border: Border.all(
                color: _codeReady ? Colors.green : AppColors.headerTab,
                width: _codeReady ? 4 : 3,
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: _codeReady
                ? Center(
                    child: Icon(Icons.check_circle, color: Colors.green.withOpacity(0.8), size: 48),
                  )
                : null,
          ),
        ),
        // Instrucción (arriba)
        Positioned(
          top: 32,
          left: 0,
          right: 0,
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 24),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.85),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              children: [
                Text(
                  tr('scan_material_instruction'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: _codeReady ? Colors.green.withOpacity(0.2) : Colors.white.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: _codeReady ? Colors.green : Colors.white24),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        _codeReady ? Icons.qr_code : Icons.qr_code_scanner,
                        color: _codeReady ? Colors.green : Colors.white54,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          _codeReady ? _detectedCode! : tr('waiting_for_code'),
                          style: TextStyle(
                            color: _codeReady ? Colors.green : Colors.white54,
                            fontSize: 12,
                            fontWeight: _codeReady ? FontWeight.bold : FontWeight.normal,
                            fontFamily: 'monospace',
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        // Botón capturar
        Positioned(
          bottom: 100,
          left: 0,
          right: 0,
          child: Center(
            child: GestureDetector(
              onTap: _codeReady ? _confirmScan : null,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: _codeReady ? 90 : 80,
                height: _codeReady ? 90 : 80,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _codeReady ? Colors.green : Colors.white.withOpacity(0.3),
                  border: Border.all(
                    color: _codeReady ? Colors.green.shade300 : Colors.white54,
                    width: 4,
                  ),
                  boxShadow: _codeReady
                      ? [BoxShadow(color: Colors.green.withOpacity(0.5), blurRadius: 20, spreadRadius: 2)]
                      : null,
                ),
                child: Icon(
                  _codeReady ? Icons.check : Icons.center_focus_weak,
                  color: Colors.white,
                  size: _codeReady ? 48 : 40,
                ),
              ),
            ),
          ),
        ),
        // Texto debajo del botón
        Positioned(
          bottom: 70,
          left: 0,
          right: 0,
          child: Text(
            _codeReady ? tr('press_to_confirm') : tr('point_to_code'),
            textAlign: TextAlign.center,
            style: TextStyle(
              color: _codeReady ? Colors.green : Colors.white70,
              fontSize: 13,
              fontWeight: _codeReady ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
        // Botones inferiores
        Positioned(
          bottom: 16,
          left: 0,
          right: 0,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              IconButton(
                onPressed: () => _scannerController?.toggleTorch(),
                icon: const Icon(Icons.flash_auto, color: Colors.white, size: 28),
              ),
              TextButton.icon(
                onPressed: _stopScanner,
                icon: const Icon(Icons.close, size: 20),
                label: Text(tr('cancel')),
                style: TextButton.styleFrom(foregroundColor: Colors.white70),
              ),
              IconButton(
                onPressed: () => _scannerController?.switchCamera(),
                icon: const Icon(Icons.cameraswitch, color: Colors.white, size: 28),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMaterialConfirmForm() {
    final info = _scannedMaterialInfo!;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header con código escaneado
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF252A3C),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.qr_code, color: AppColors.headerTab),
                    const SizedBox(width: 8),
                    Text(tr('scanned_code'), style: const TextStyle(color: Colors.white54, fontSize: 12)),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.refresh, color: Colors.white54),
                      onPressed: () {
                        setState(() {
                          _scannedMaterialInfo = null;
                          _lastScannedCode = null;
                          _ubicacionDestinoController.clear();
                          _expectedLocations = [];
                        });
                      },
                      tooltip: tr('scan_another'),
                    ),
                  ],
                ),
                Text(
                  _lastScannedCode ?? '',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Info del material
          _buildInfoCard(tr('part_number'), info['numero_parte']?.toString() ?? '-'),
          _buildInfoCard(tr('description'), info['especificacion']?.toString() ?? '-'),
          _buildInfoCard(tr('material_code'), info['codigo_material_recibido']?.toString() ?? '-'),
          _buildInfoCard(tr('quantity'), '${_parseQty(info['cantidad_actual'] ?? info['cantidad_salida'])}'),
          _buildInfoCard(tr('location'), info['ubicacion']?.toString() ?? '-'),

          const SizedBox(height: 16),

          // Campo de ubicación destino
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF252A3C),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.cyan.withOpacity(0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.location_on, color: Colors.cyan, size: 18),
                    const SizedBox(width: 8),
                    Text(
                      tr('destination_location'),
                      style: const TextStyle(color: Colors.cyan, fontSize: 14, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (_expectedLocations.length > 1)
                  DropdownButtonFormField<String>(
                    value: _ubicacionDestinoController.text.isNotEmpty
                        ? _ubicacionDestinoController.text
                        : _expectedLocations.first,
                    dropdownColor: const Color(0xFF1A1E2C),
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: const Color(0xFF1A1E2C),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    items: _expectedLocations.map((loc) => DropdownMenuItem(
                      value: loc,
                      child: Text(loc),
                    )).toList(),
                    onChanged: (value) {
                      _ubicacionDestinoController.text = value ?? '';
                    },
                  )
                else
                  TextField(
                    controller: _ubicacionDestinoController,
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                    decoration: InputDecoration(
                      hintText: _expectedLocations.isNotEmpty
                          ? _expectedLocations.first
                          : tr('enter_location'),
                      hintStyle: const TextStyle(color: Colors.white38),
                      filled: true,
                      fillColor: const Color(0xFF1A1E2C),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    ),
                  ),
                if (_expectedLocations.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Row(
                      children: [
                        const Icon(Icons.info_outline, size: 12, color: Colors.amber),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            '${tr('expected_location')}: ${_expectedLocations.join(', ')}',
                            style: const TextStyle(fontSize: 10, color: Colors.amber),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Botón confirmar entrada
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton.icon(
              onPressed: _isConfirming ? null : _confirmManualEntry,
              icon: _isConfirming
                  ? const SizedBox(
                      width: 24, height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.check_circle, size: 24),
              label: Text(
                _isConfirming ? 'Confirmando...' : tr('confirm_entry'),
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),

          const SizedBox(height: 12),

          // Botón escanear otro
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _startScanner,
              icon: const Icon(Icons.qr_code_scanner),
              label: Text(tr('scan_another')),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white70,
                side: const BorderSide(color: Colors.white24),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard(String label, String value) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF252A3C),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.white54, fontSize: 14)),
          Flexible(
            child: Text(
              value,
              style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500),
              textAlign: TextAlign.right,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  void _showManualCodeDialog() {
    final controller = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF252A3C),
        title: Text(tr('scan_or_enter_code'), style: const TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            labelText: tr('material_code'),
            labelStyle: const TextStyle(color: Colors.white70),
            hintText: 'Ej: PART-2025010001',
            hintStyle: const TextStyle(color: Colors.white38),
            enabledBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
            focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: AppColors.headerTab)),
          ),
          onSubmitted: (value) {
            if (value.isNotEmpty) {
              Navigator.pop(context);
              setState(() => _lastScannedCode = value);
              _searchWarehouseMaterial(value);
            }
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(tr('cancel')),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.headerTab),
            onPressed: () {
              final value = controller.text.trim();
              if (value.isNotEmpty) {
                Navigator.pop(context);
                setState(() => _lastScannedCode = value);
                _searchWarehouseMaterial(value);
              }
            },
            child: Text(tr('search')),
          ),
        ],
      ),
    );
  }
}
