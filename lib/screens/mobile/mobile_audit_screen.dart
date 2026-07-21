import 'dart:async';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:intl/intl.dart';
import 'package:material_warehousing_flutter/core/localization/app_translations.dart';
import 'package:material_warehousing_flutter/core/services/api_service.dart';
import 'package:material_warehousing_flutter/core/services/auth_service.dart';
import 'package:material_warehousing_flutter/core/services/feedback_service.dart';
import 'package:material_warehousing_flutter/core/services/scanner_config_service.dart';
import 'package:material_warehousing_flutter/core/theme/app_colors.dart';

/// Pantalla de Auditoría de Inventario para Móvil (Operadores)
/// Flujo:
/// 1. Escanear ubicación (QR de estante/rack)
/// 2. Ver lista de materiales esperados en esa ubicación
/// 3. Escanear cada material para marcarlo como "Found"
/// 4. Marcar faltantes manualmente
/// 5. Completar ubicación y pasar a la siguiente
class MobileAuditScreen extends StatefulWidget {
  final LanguageProvider languageProvider;

  const MobileAuditScreen({
    super.key,
    required this.languageProvider,
  });

  @override
  State<MobileAuditScreen> createState() => _MobileAuditScreenState();
}

class _MobileAuditScreenState extends State<MobileAuditScreen> {
  // Scanner
  MobileScannerController? _scannerController;
  bool _isScannerActive = false;

  // Escáner externo
  final TextEditingController _scannerInputController = TextEditingController();
  final FocusNode _scannerFocusNode = FocusNode();

  // Estados
  Map<String, dynamic>? _activeAudit;
  String? _currentLocation;
  String? _locationStatus;
  List<Map<String, dynamic>> _locationItems = [];

  // Estados para flujo v2 (por parte)
  List<Map<String, dynamic>> _partSummary = [];
  Map<String, dynamic>? _selectedPartForScan;

  // Etiquetas de la parte seleccionada en modo mismatch_scan
  List<Map<String, dynamic>> _partLabels = [];
  bool _isLoadingLabels = false;

  bool _isLoading = false;
  bool _isProcessing = false;
  final List<String> _scanQueue = [];
  bool _isQueueProcessing = false;
  static const int _scanBatchMin = 8;
  static const int _scanBatchMid = 12;
  static const int _scanBatchMax = 20;
  static const int _scanDebounceFastMs = 140;
  static const int _scanDebounceMidMs = 220;
  static const int _scanDebounceSlowMs = 320;
  int _scanBatchSize = _scanBatchMid;
  int _scanDebounceMs = _scanDebounceMidMs;
  double _scanLatencyAvgMs = 0;
  int _scanLatencySamples = 0;
  Timer? _scanQueueDebounce;

  // Control de escaneo
  String? _lastProcessedCode;
  DateTime? _lastScanTime;

  // Modo de escaneo: 'location', 'summary' (v2), 'mismatch_scan' (v2), 'item' (legacy)
  String _scanMode = 'location';

  // Mensajes de estado
  String? _statusMessage;
  bool _statusIsError = false;

  String tr(String key) => widget.languageProvider.tr(key);
  String _formatQty(num value) {
    final locale = widget.languageProvider.currentLocale;
    return NumberFormat.decimalPattern(locale).format(value);
  }

  String _normalizePart(String value) => value.trim().toUpperCase();

  String _labelCode(Map<String, dynamic> label) {
    final code = label['codigo_material_recibido'] ??
        label['warehousing_code'] ??
        label['codigo_material'] ??
        '';
    return code.toString();
  }

  List<dynamic> _splitLabelCode(String code) {
    final matches = RegExp(r'(\d+|\D+)').allMatches(code);
    return matches.map((match) {
      final chunk = match.group(0)!;
      final number = int.tryParse(chunk);
      return number ?? chunk.toUpperCase();
    }).toList();
  }

  int _compareLabelCodes(String a, String b) {
    final aParts = _splitLabelCode(a);
    final bParts = _splitLabelCode(b);
    final len = aParts.length < bParts.length ? aParts.length : bParts.length;

    for (var i = 0; i < len; i++) {
      final aPart = aParts[i];
      final bPart = bParts[i];
      if (aPart is int && bPart is int) {
        if (aPart != bPart) return aPart.compareTo(bPart);
      } else {
        final cmp = aPart.toString().compareTo(bPart.toString());
        if (cmp != 0) return cmp;
      }
    }
    return aParts.length.compareTo(bParts.length);
  }

  bool _loadingDialogVisible = false;

  void _showLoadingDialog(String message) {
    if (_loadingDialogVisible || !mounted) return;
    _loadingDialogVisible = true;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.panelBackground,
        content: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _hideLoadingDialog() {
    if (!_loadingDialogVisible || !mounted) return;
    _loadingDialogVisible = false;
    Navigator.of(context, rootNavigator: true).pop();
  }

  void _enqueueScan(String code) {
    if (code.isEmpty) return;
    if (_scanQueue.contains(code)) {
      // Código duplicado en cola - dar feedback pero no agregar
      FeedbackService.playDuplicate();
      return;
    }
    setState(() {
      _scanQueue.add(code);
    });
    // Feedback inmediato de que se agregó a la cola
    FeedbackService.playSuccess();
    _showStatus('+ $code (${tr('pending')}: ${_scanQueue.length})',
        isError: false);
  }

  void _scheduleQueuedScanProcessing() {
    if (_scanQueue.isEmpty) return;
    if (_scanQueue.length >= _scanBatchSize) {
      _scanQueueDebounce?.cancel();
      _processQueuedScans();
      return;
    }

    _scanQueueDebounce?.cancel();
    _scanQueueDebounce = Timer(Duration(milliseconds: _scanDebounceMs), () {
      _processQueuedScans();
    });
  }

  void _recordScanLatency({
    required int elapsedMs,
    required bool batchOk,
  }) {
    if (elapsedMs <= 0) return;

    if (_scanLatencySamples == 0) {
      _scanLatencyAvgMs = elapsedMs.toDouble();
      _scanLatencySamples = 1;
    } else {
      const double alpha = 0.3;
      _scanLatencyAvgMs =
          (_scanLatencyAvgMs * (1 - alpha)) + (elapsedMs * alpha);
      _scanLatencySamples++;
    }

    if (!batchOk || _scanLatencyAvgMs >= 1400) {
      _scanBatchSize = _scanBatchMax;
      _scanDebounceMs = _scanDebounceSlowMs;
      return;
    }

    if (_scanLatencyAvgMs >= 700) {
      _scanBatchSize = _scanBatchMid;
      _scanDebounceMs = _scanDebounceMidMs;
      return;
    }

    _scanBatchSize = _scanBatchMin;
    _scanDebounceMs = _scanDebounceFastMs;
  }

  Future<void> _processQueuedScans() async {
    if (_isQueueProcessing || _scanQueue.isEmpty) return;
    _scanQueueDebounce?.cancel();
    _isQueueProcessing = true;
    try {
      while (_scanQueue.isNotEmpty) {
        if (!mounted || _scanMode != 'mismatch_scan') {
          _scanQueue.clear();
          break;
        }

        final count = _scanQueue.length > _scanBatchSize
            ? _scanBatchSize
            : _scanQueue.length;
        final codes = _scanQueue.sublist(0, count);
        _scanQueue.removeRange(0, count);
        if (mounted) setState(() {});

        await _scanPartItemsFast(codes);
      }
    } finally {
      _isQueueProcessing = false;
      if (_scanQueue.isNotEmpty) {
        _scheduleQueuedScanProcessing();
      }
    }
  }

  // Version rapida en lote para procesar cola sin bloquear
  Future<void> _scanPartItemsFast(List<String> warehousingCodes) async {
    if (_currentLocation == null ||
        _selectedPartForScan == null ||
        warehousingCodes.isEmpty) {
      return;
    }

    final currentUser = AuthService.currentUser;
    if (currentUser == null) return;

    final expectedItems = _toInt(_selectedPartForScan!['expected_items']);
    var scannedItems = _toInt(_selectedPartForScan!['scanned_items']);
    var successCount = 0;
    var errorCount = 0;
    var automaticEntryDetected = false;
    String? firstError;
    final rows = <Map<String, dynamic>>[];

    final stopwatch = Stopwatch()..start();
    final selectedPart = _selectedPartForScan!['numero_parte'].toString();
    for (final code in warehousingCodes) {
      final normalizedCode = code.trim();
      if (normalizedCode.isEmpty) continue;

      final single = await ApiService.scanAuditPartItem(
        location: _currentLocation!,
        numeroParte: selectedPart,
        warehousingCode: normalizedCode,
        userId: currentUser.id,
      );
      if (single['success'] == true) {
        final data = single['data'] as Map<String, dynamic>? ?? {};
        rows.add({'code': normalizedCode, ...data});
      } else {
        rows.add({
          'code': normalizedCode,
          'success': false,
          'error': single['error'] ?? tr('audit_scan_error'),
        });
      }
    }
    stopwatch.stop();

    for (final item in rows) {
      final row = item;
      final rowCode = row['code']?.toString() ?? '';
      if (row['success'] == true) {
        successCount++;
        automaticEntryDetected = automaticEntryDetected ||
            row['automaticEntry'] == true ||
            row['data']?['automaticEntry'] == true;
        final progress = (row['progress'] ?? row['data']?['progress'])
            as Map<String, dynamic>?;
        scannedItems = _toInt(progress?['scanned'] ?? (scannedItems + 1));
        _markLabelAsScanned(rowCode);
      } else {
        errorCount++;
        firstError ??= row['error']?.toString();
      }
    }

    _recordScanLatency(
      elapsedMs: stopwatch.elapsedMilliseconds,
      batchOk: errorCount == 0,
    );

    if (mounted && successCount > 0) {
      setState(() {
        _selectedPartForScan = {
          ..._selectedPartForScan!,
          'scanned_items': scannedItems,
        };
        final idx = _partSummary.indexWhere(
          (p) => p['numero_parte'] == _selectedPartForScan!['numero_parte'],
        );
        if (idx >= 0) {
          _partSummary[idx] = {
            ..._partSummary[idx],
            'scanned_items': scannedItems,
          };
        }
      });
      FeedbackService.playSuccess();
      if (automaticEntryDetected) {
        await _reloadPartSummary();
        await _loadPartLabels(selectedPart);
      }
      _showStatus(
        automaticEntryDetected
            ? 'OK +$successCount ($scannedItems/$expectedItems) - entrada automática'
            : 'OK +$successCount ($scannedItems/$expectedItems)',
        isError: false,
      );
    }

    if (errorCount > 0) {
      FeedbackService.playError();
      _showStatus(
        'ERR $errorCount: ${firstError ?? tr('audit_scan_error')}',
        isError: true,
      );
    }
  }

  // Marcar una etiqueta como escaneada en la lista local
  void _markLabelAsScanned(String warehousingCode) {
    final normalized = warehousingCode.trim();
    final idx = _partLabels.indexWhere(
      (l) => _labelCode(l).trim() == normalized,
    );
    if (idx >= 0) {
      _partLabels[idx] = {..._partLabels[idx], 'audit_status': 'Found'};
    }
  }

  int _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }

  double _toDouble(dynamic value) {
    if (value is double) return value;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0.0;
    return 0.0;
  }

  @override
  void initState() {
    super.initState();
    FeedbackService.init();
    _loadActiveAudit();
  }

  @override
  void dispose() {
    _scanQueueDebounce?.cancel();
    _scannerController?.dispose();
    _scannerInputController.dispose();
    _scannerFocusNode.dispose();
    super.dispose();
  }

  Future<void> _loadActiveAudit() async {
    setState(() => _isLoading = true);

    final result = await ApiService.getActiveAudit();

    if (mounted) {
      setState(() {
        _isLoading = false;
        if (result['success'] == true && result['data'] != null) {
          _activeAudit = result['data'];
        } else {
          _activeAudit = null;
        }
      });
    }
  }

  void _startCameraScanner() {
    _scannerController?.dispose();
    _scannerController = MobileScannerController(
      detectionSpeed: DetectionSpeed.normal,
      facing: CameraFacing.back,
      torchEnabled: false,
    );
    setState(() {
      _isScannerActive = true;
      _lastProcessedCode = null;
    });
  }

  void _stopCameraScanner() {
    _scannerController?.stop();
    _scannerInputController.clear();
    setState(() {
      _isScannerActive = false;
    });
  }

  void _onBarcodeDetected(BarcodeCapture capture) {
    if (capture.barcodes.isEmpty) return;

    final barcode = capture.barcodes.first;
    if (barcode.rawValue == null) return;

    final code = barcode.rawValue!.trim();

    // En modo mismatch_scan: siempre encolar para escaneo rápido
    if (_scanMode == 'mismatch_scan') {
      _enqueueAndProcess(code);
      return;
    }

    if (_isProcessing) return;
    _processScannedCode(code);
  }

  void _restoreScannerFocus() {
    if (!mounted || !ScannerConfigService.isReaderMode) return;
    if (_scanMode != 'location' &&
        _scanMode != 'summary' &&
        _scanMode != 'mismatch_scan') {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scannerFocusNode.canRequestFocus) return;
      _scannerFocusNode.requestFocus();
    });
  }

  Future<void> _onExternalScannerInput(String value) async {
    final code = value.trim();
    _scannerInputController.clear();
    try {
      if (code.isEmpty) return;

      // En modo mismatch_scan: siempre encolar para escaneo rápido
      if (_scanMode == 'mismatch_scan') {
        _enqueueAndProcess(code);
        return;
      }

      if (_isProcessing) return;
      await _processScannedCode(code);
    } finally {
      _scannerInputController.clear();
      _restoreScannerFocus();
    }
  }

  // Encolar código y procesar cola en segundo plano (no bloquea)
  void _enqueueAndProcess(String code) {
    // Verificar duplicado reciente (300ms)
    final now = DateTime.now();
    if (_lastProcessedCode == code &&
        _lastScanTime != null &&
        now.difference(_lastScanTime!).inMilliseconds < 300) {
      return;
    }
    _lastProcessedCode = code;
    _lastScanTime = now;

    _enqueueScan(code);
    _scheduleQueuedScanProcessing();
  }

  Future<void> _processScannedCode(String code) async {
    // Evitar procesar el mismo código muy rápido (300ms para duplicados)
    final now = DateTime.now();
    if (_lastProcessedCode == code &&
        _lastScanTime != null &&
        now.difference(_lastScanTime!).inMilliseconds < 300) {
      return;
    }

    _lastProcessedCode = code;
    _lastScanTime = now;

    if (_activeAudit == null) {
      FeedbackService.playError();
      _showStatus(tr('audit_no_active'), isError: true);
      return;
    }

    final currentUser = AuthService.currentUser;
    if (currentUser == null) {
      FeedbackService.playError();
      _showStatus(tr('audit_error_no_user'), isError: true);
      return;
    }

    setState(() => _isProcessing = true);

    try {
      if (_scanMode == 'location') {
        // Escanear ubicación
        await _scanLocation(code, currentUser.id);
      } else if (_scanMode == 'mismatch_scan') {
        // Escanear etiqueta de parte en discrepancia (v2)
        await _scanPartItem(code, currentUser.id);
      } else if (_scanMode == 'summary') {
        // Rollo existente en almacén: se registra automático con la cantidad
        // del sistema. Solo abre el diálogo si el material es nuevo.
        await _autoRegisterScannedRoll(code);
      } else {
        // Modo legacy: Escanear material individual
        await _scanItem(code, currentUser.id);
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
      if (_scanMode == 'mismatch_scan') {
        await _processQueuedScans();
      }
    }
  }

  Future<void> _scanLocation(String location, int userId) async {
    _showLoadingDialog(tr('processing_msg'));
    try {
      // Primero registrar escaneo de ubicación en el backend
      final scanResult = await ApiService.auditScanLocation(
        auditId: _activeAudit!['id'],
        location: location,
        scannedBy: userId,
      );

      if (scanResult['success'] != true) {
        FeedbackService.playError();
        _showStatus(scanResult['error'] ?? tr('audit_scan_error'),
            isError: true);
        return;
      }

      final scanData = scanResult['data'] as Map<String, dynamic>? ?? {};
      final normalizedLocation =
          (scanData['location'] ?? location).toString().trim().toUpperCase();

      // Cargar resumen por parte (flujo v2)
      final result =
          await ApiService.getAuditLocationSummary(normalizedLocation);

      if (result['success'] == true) {
        FeedbackService.playSuccess();
        final data = result['data'];

        setState(() {
          _currentLocation = normalizedLocation;
          _locationStatus = data['locationStatus']?.toString();
          _partSummary = List<Map<String, dynamic>>.from(data['parts'] ?? []);
          _locationItems = []; // Limpiar items legacy
          _selectedPartForScan = null;
          _scanQueue.clear();
          _scanMode = 'summary'; // Flujo v2: mostrar resumen por parte
        });

        final progress = data['progress'] ?? {};
        _showStatus(
            'OK $normalizedLocation: ${_partSummary.length} ${tr('audit_parts')} (${progress['confirmed'] ?? 0} ${tr('audit_confirmed')})',
            isError: false);
      } else {
        FeedbackService.playError();
        _showStatus(result['error'] ?? tr('audit_scan_error'), isError: true);
      }
    } finally {
      _hideLoadingDialog();
    }
  }

  // Escaneo ágil: busca el rollo en almacén y registra su cantidad de sistema
  // sin captura manual. Cae al diálogo solo si no existe en almacén.
  Future<void> _autoRegisterScannedRoll(String code) async {
    if (_currentLocation == null) return;
    final currentUser = AuthService.currentUser;
    if (currentUser == null) return;

    _showLoadingDialog(tr('processing_msg'));
    final warehouse = await ApiService.getWarehousingByCode(code);
    final quantity =
        warehouse == null ? 0.0 : _toDouble(warehouse['cantidad_actual']);

    if (warehouse == null ||
        warehouse['codigo_material_recibido'] == null ||
        quantity <= 0) {
      // Material nuevo o sin stock en almacén: alta manual como antes
      _hideLoadingDialog();
      await _showPhysicalItemDialog(initialCode: code);
      return;
    }

    try {
      final result = await ApiService.registerAuditPhysicalItem(
        location: _currentLocation!,
        warehousingCode: code,
        physicalQuantity: quantity,
        userId: currentUser.id,
      );

      if (result['success'] == true) {
        FeedbackService.playSuccess();
        await _reloadPartSummary();
        _showStatus(
          'OK $code: ${_formatQty(quantity)} ${warehouse['numero_parte'] ?? ''}',
          isError: false,
        );
      } else {
        FeedbackService.playError();
        _showStatus(
          result['error'] ?? tr('audit_physical_item_error'),
          isError: true,
        );
      }
    } finally {
      _hideLoadingDialog();
      _restoreScannerFocus();
    }
  }

  Future<void> _showPhysicalItemDialog({String initialCode = ''}) async {
    if (_currentLocation == null) return;

    final codeController = TextEditingController(text: initialCode);
    final partController = TextEditingController();
    final lotController = TextEditingController();
    final quantityController = TextEditingController();
    final specController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final payload = await showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: Text(tr('audit_register_physical_item')),
        content: SizedBox(
          width: 420,
          child: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${tr('location')}: $_currentLocation',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: codeController,
                    autofocus: initialCode.isEmpty,
                    decoration: InputDecoration(
                      labelText: tr('audit_material_code'),
                      prefixIcon: const Icon(Icons.qr_code_scanner),
                      border: const OutlineInputBorder(),
                    ),
                    validator: (value) => value == null || value.trim().isEmpty
                        ? tr('required_field')
                        : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: quantityController,
                    autofocus: initialCode.isNotEmpty,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: tr('audit_physical_quantity'),
                      prefixIcon: const Icon(Icons.scale),
                      border: const OutlineInputBorder(),
                    ),
                    validator: (value) {
                      final quantity = double.tryParse(
                        (value ?? '').trim().replaceAll(',', '.'),
                      );
                      return quantity == null || quantity <= 0
                          ? tr('audit_invalid_physical_quantity')
                          : null;
                    },
                  ),
                  const SizedBox(height: 12),
                  Text(
                    tr('audit_new_material_hint'),
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: partController,
                    decoration: InputDecoration(
                      labelText: tr('part_number'),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: lotController,
                    decoration: InputDecoration(
                      labelText: tr('lot_number'),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: specController,
                    decoration: InputDecoration(
                      labelText: tr('specification'),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(tr('cancel')),
          ),
          ElevatedButton.icon(
            onPressed: () {
              if (formKey.currentState?.validate() != true) return;
              Navigator.pop(dialogContext, {
                'code': codeController.text.trim(),
                'quantity': double.parse(
                  quantityController.text.trim().replaceAll(',', '.'),
                ),
                'part': partController.text.trim(),
                'lot': lotController.text.trim(),
                'spec': specController.text.trim(),
              });
            },
            icon: const Icon(Icons.save),
            label: Text(tr('save')),
          ),
        ],
      ),
    );

    codeController.dispose();
    partController.dispose();
    lotController.dispose();
    quantityController.dispose();
    specController.dispose();

    if (payload == null || !mounted) {
      _restoreScannerFocus();
      return;
    }

    final currentUser = AuthService.currentUser;
    if (currentUser == null) return;

    _showLoadingDialog(tr('processing_msg'));
    try {
      final result = await ApiService.registerAuditPhysicalItem(
        location: _currentLocation!,
        warehousingCode: payload['code'] as String,
        physicalQuantity: payload['quantity'] as double,
        userId: currentUser.id,
        numeroParte: payload['part'] as String,
        numeroLote: payload['lot'] as String,
        especificacion: payload['spec'] as String,
      );

      if (result['success'] == true) {
        FeedbackService.playSuccess();
        final data = result['data'] as Map<String, dynamic>;
        await _reloadPartSummary();
        _showStatus(
          'OK ${data['warehousingCode']}: ${data['message']}',
          isError: false,
        );
      } else {
        FeedbackService.playError();
        _showStatus(
          result['error'] ?? tr('audit_physical_item_error'),
          isError: true,
        );
      }
    } finally {
      _hideLoadingDialog();
      _restoreScannerFocus();
    }
  }

  Future<void> _scanItem(String warehousingCode, int userId) async {
    if (_currentLocation == null) {
      FeedbackService.playDuplicate();
      _showStatus(tr('audit_scan_location_first'), isError: true);
      return;
    }

    final result = await ApiService.auditScanItem(
      auditId: _activeAudit!['id'],
      location: _currentLocation!,
      warehousingCode: warehousingCode,
      scannedBy: userId,
    );

    if (result['success'] == true) {
      FeedbackService.playSuccess();

      // Actualizar estado del item en la lista local usando codigo_material_recibido
      final data = result['data'];
      final scannedCode = data['warehousingCode'] ?? warehousingCode;
      final automaticEntry = data['automaticEntry'] == true;
      setState(() {
        final index = _locationItems.indexWhere(
          (item) => item['codigo_material_recibido'] == scannedCode,
        );
        if (index >= 0) {
          _locationItems[index]['audit_status'] = 'Found';
          _locationItems[index]['scanned_by_name'] =
              AuthService.currentUser?.nombreCompleto ?? '';
        }
      });

      if (automaticEntry) {
        await _reloadPartSummary();
      }
      _showStatus(
        automaticEntry
            ? 'OK $scannedCode - ${data['message']}'
            : 'OK $scannedCode',
        isError: false,
      );
    } else {
      FeedbackService.playError();
      _showStatus(result['error'] ?? tr('audit_scan_error'), isError: true);
    }
  }

  Future<void> _markMissing(Map<String, dynamic> item) async {
    final currentUser = AuthService.currentUser;
    if (currentUser == null) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr('audit_mark_missing')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(tr('audit_mark_missing_confirm')),
            const SizedBox(height: 8),
            Text(
              item['warehousing_code'] ??
                  item['codigo_material_recibido'] ??
                  '',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            Text(item['numero_parte'] ?? ''),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(tr('cancel')),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: Text(tr('audit_mark_missing')),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isProcessing = true);

    final result = await ApiService.auditMarkMissing(
      auditId: _activeAudit!['id'],
      warehousingId: item['warehousing_id'],
      location: _currentLocation!,
      markedBy: currentUser.id,
    );

    if (mounted) {
      setState(() => _isProcessing = false);

      if (result['success'] == true) {
        FeedbackService.playDuplicate();

        // Actualizar estado local usando codigo_material_recibido
        final code = item['codigo_material_recibido'];
        final index = _locationItems.indexWhere(
          (i) => i['codigo_material_recibido'] == code,
        );
        if (index >= 0) {
          setState(() {
            _locationItems[index]['audit_status'] = 'Missing';
          });
        }

        _showStatus(tr('audit_marked_missing'), isError: false);
      } else {
        FeedbackService.playError();
        _showStatus(result['error'] ?? tr('audit_mark_error'), isError: true);
      }
    }
  }

  Future<void> _completeLocation() async {
    if (_currentLocation == null) return;

    final currentUser = AuthService.currentUser;
    if (currentUser == null) return;

    // Verificar si hay items pendientes
    final pendingItems = _locationItems
        .where((i) => (i['audit_status'] ?? 'Pending') == 'Pending')
        .toList();

    if (pendingItems.isNotEmpty) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(tr('audit_complete_location')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(tr('audit_pending_items_warning')),
              const SizedBox(height: 8),
              Text(
                '${pendingItems.length} ${tr('audit_items_pending')}',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.orange,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                tr('audit_pending_will_be_missing'),
                style: const TextStyle(fontSize: 12, color: Colors.red),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(tr('cancel')),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
              child: Text(tr('audit_complete_anyway')),
            ),
          ],
        ),
      );

      if (confirm != true) return;
    }

    setState(() => _isProcessing = true);

    final result = await ApiService.auditCompleteLocation(
      auditId: _activeAudit!['id'],
      location: _currentLocation!,
      completedBy: currentUser.id,
    );

    if (mounted) {
      setState(() => _isProcessing = false);

      if (result['success'] == true) {
        FeedbackService.playSuccess();
        _showStatus(tr('audit_location_completed'), isError: false);

        // Volver a modo escaneo de ubicación
        setState(() {
          _currentLocation = null;
          _locationStatus = null;
          _locationItems = [];
          _partSummary = [];
          _selectedPartForScan = null;
          _partLabels = [];
          _scanQueue.clear();
          _scanMode = 'location';
        });
      } else {
        FeedbackService.playError();
        _showStatus(result['error'] ?? tr('audit_complete_error'),
            isError: true);
      }
    }
  }

  void _cancelLocation() {
    setState(() {
      _currentLocation = null;
      _locationStatus = null;
      _locationItems = [];
      _partSummary = [];
      _selectedPartForScan = null;
      _partLabels = [];
      _scanQueue.clear();
      _scanMode = 'location';
    });
    _restoreScannerFocus();
  }

  // ============================================
  // MÉTODOS FLUJO V2 - Por número de parte
  // ============================================

  // Confirmar parte como OK sin escaneo
  Future<void> _confirmPart(Map<String, dynamic> part) async {
    final currentUser = AuthService.currentUser;
    if (currentUser == null || _currentLocation == null) return;

    setState(() => _isProcessing = true);

    final result = await ApiService.confirmAuditPart(
      location: _currentLocation!,
      numeroParte: part['numero_parte'],
      userId: currentUser.id,
    );

    if (mounted) {
      setState(() => _isProcessing = false);

      if (result['success'] == true) {
        FeedbackService.playSuccess();
        _showStatus('OK ${tr('audit_part_confirmed')}: ${part['numero_parte']}',
            isError: false);
        await _reloadPartSummary();
      } else {
        FeedbackService.playError();
        _showStatus(result['error'] ?? tr('general_error'), isError: true);
      }
    }
  }

  // Marcar parte como discrepancia
  Future<void> _flagMismatch(Map<String, dynamic> part) async {
    final currentUser = AuthService.currentUser;
    if (currentUser == null || _currentLocation == null) return;

    setState(() => _isProcessing = true);

    final result = await ApiService.flagAuditMismatch(
      location: _currentLocation!,
      numeroParte: part['numero_parte'],
      userId: currentUser.id,
    );

    if (mounted) {
      setState(() => _isProcessing = false);

      if (result['success'] == true) {
        FeedbackService.playSuccess();
        _showStatus(
            '⚠ ${tr('audit_mismatch_flagged')}: ${part['numero_parte']}',
            isError: false);

        // Cambiar a modo escaneo de etiquetas de esta parte
        setState(() {
          _selectedPartForScan = part;
          _scanQueue.clear();
          _partLabels = [];
          _scanMode = 'mismatch_scan';
        });

        // Cargar etiquetas de esta parte
        await _loadPartLabels(part['numero_parte'].toString());
        await _reloadPartSummary();
        _restoreScannerFocus();
      } else {
        FeedbackService.playError();
        _showStatus(result['error'] ?? tr('general_error'), isError: true);
      }
    }
  }

  // Escanear etiqueta individual de una parte en Mismatch
  // OPTIMIZADO: Actualización optimista sin esperar recarga completa
  Future<void> _scanPartItem(String warehousingCode, int userId) async {
    if (_currentLocation == null || _selectedPartForScan == null) {
      FeedbackService.playError();
      _showStatus(tr('audit_select_part_first'), isError: true);
      return;
    }

    // Actualización optimista: incrementar contador localmente antes de API
    final currentScanned = _toInt(_selectedPartForScan!['scanned_items']);
    final expectedItems = _toInt(_selectedPartForScan!['expected_items']);

    // Llamar API en background
    final result = await ApiService.scanAuditPartItem(
      location: _currentLocation!,
      numeroParte: _selectedPartForScan!['numero_parte'].toString(),
      warehousingCode: warehousingCode,
      userId: userId,
    );

    if (result['success'] == true) {
      FeedbackService.playSuccess();
      final data = result['data'];
      final automaticEntry = data['automaticEntry'] == true;
      final progress = data['progress'] as Map<String, dynamic>?;
      final newScanned = progress?['scanned'] ?? (currentScanned + 1);

      // Actualizar estado local inmediatamente (sin recargar todo)
      if (mounted) {
        setState(() {
          _selectedPartForScan = {
            ..._selectedPartForScan!,
            'scanned_items': newScanned,
          };
          // Actualizar también en _partSummary
          final idx = _partSummary.indexWhere((p) =>
              p['numero_parte'] == _selectedPartForScan!['numero_parte']);
          if (idx >= 0) {
            _partSummary[idx] = {
              ..._partSummary[idx],
              'scanned_items': newScanned
            };
          }
          // Marcar etiqueta como escaneada en la lista visual
          _markLabelAsScanned(warehousingCode);
        });
      }

      _showStatus(
        automaticEntry
            ? '✓ $warehousingCode: $newScanned/$expectedItems - ${data['message']}'
            : '✓ $warehousingCode: $newScanned/$expectedItems',
        isError: false,
      );

      if (automaticEntry) {
        await _reloadPartSummary();
        await _loadPartLabels(
          _selectedPartForScan!['numero_parte'].toString(),
        );
      }

      // NO recargar summary después de cada escaneo - solo actualizar localmente
      // await _reloadPartSummary();  // <-- Removido para velocidad
    } else {
      FeedbackService.playError();
      _showStatus(result['error'] ?? tr('audit_scan_error'), isError: true);
    }
  }

  // Deshacer mismatch y confirmar como OK
  Future<void> _undoMismatchAndConfirmOk() async {
    if (_selectedPartForScan == null || _currentLocation == null) return;

    final currentUser = AuthService.currentUser;
    if (currentUser == null) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.panelBackground,
        title: Text(tr('audit_undo_mismatch'),
            style: const TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${tr('audit_confirm_ok_question')}: ${_selectedPartForScan!['numero_parte']}',
              style: const TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 8),
            Text(
              tr('audit_undo_mismatch_desc'),
              style: const TextStyle(fontSize: 12, color: Colors.green),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(tr('cancel')),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            child: Text(tr('audit_confirm_ok')),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isProcessing = true);

    final result = await ApiService.undoAuditMismatch(
      location: _currentLocation!,
      numeroParte: _selectedPartForScan!['numero_parte'],
      userId: currentUser.id,
      confirmOk: true,
    );

    if (mounted) {
      setState(() => _isProcessing = false);

      if (result['success'] == true) {
        FeedbackService.playSuccess();
        _showStatus(
            '✓ ${tr('audit_part_confirmed')}: ${_selectedPartForScan!['numero_parte']}',
            isError: false);

        // Volver a modo resumen
        setState(() {
          _selectedPartForScan = null;
          _scanQueue.clear();
          _partLabels = [];
          _scanMode = 'summary';
        });

        await _reloadPartSummary();
      } else {
        FeedbackService.playError();
        _showStatus(result['error'] ?? tr('general_error'), isError: true);
      }
    }
  }

  // Confirmar faltantes de una parte en Mismatch
  Future<void> _confirmMissing() async {
    if (_selectedPartForScan == null || _currentLocation == null) return;

    final currentUser = AuthService.currentUser;
    if (currentUser == null) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr('audit_confirm_missing')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
                '${tr('audit_confirm_missing_part')}: ${_selectedPartForScan!['numero_parte']}'),
            const SizedBox(height: 8),
            Text(
              tr('audit_unscanned_will_be_missing'),
              style: const TextStyle(fontSize: 12, color: Colors.orange),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(tr('cancel')),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            child: Text(tr('confirm')),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isProcessing = true);

    final result = await ApiService.confirmAuditMissing(
      location: _currentLocation!,
      numeroParte: _selectedPartForScan!['numero_parte'],
      userId: currentUser.id,
    );

    if (mounted) {
      setState(() => _isProcessing = false);

      if (result['success'] == true) {
        FeedbackService.playSuccess();
        final data = result['data'];
        final missingItems = data?['missingItems'] ?? 0;
        final partNumber = _selectedPartForScan?['numero_parte'];
        _showStatus(
          '${tr('audit_missing_confirmed')}: $missingItems ${tr('audit_items')}',
          isError: false,
        );
        if (missingItems > 0 && partNumber != null) {
          await _showMissingLabelsForPart(partNumber.toString());
        }

        // Volver a modo resumen
        setState(() {
          _selectedPartForScan = null;
          _scanQueue.clear();
          _partLabels = [];
          _scanMode = 'summary';
        });

        await _reloadPartSummary();
      } else {
        FeedbackService.playError();
        _showStatus(result['error'] ?? tr('general_error'), isError: true);
      }
    }
  }

  Future<void> _reopenLocation() async {
    if (_currentLocation == null) return;

    final currentUser = AuthService.currentUser;
    if (currentUser == null) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr('audit_reopen_confirm_title')),
        content: Text(tr('audit_reopen_confirm_body')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(tr('cancel')),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            child: Text(tr('audit_reopen_location')),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isProcessing = true);

    final result = await ApiService.reopenAuditLocation(
      location: _currentLocation!,
      userId: currentUser.id,
    );

    if (mounted) {
      setState(() => _isProcessing = false);

      if (result['success'] == true) {
        FeedbackService.playSuccess();
        _showStatus(tr('audit_location_reopened'), isError: false);
        setState(() {
          _scanQueue.clear();
          _partLabels = [];
          _selectedPartForScan = null;
          _scanMode = 'summary';
        });
        await _reloadPartSummary();
      } else {
        FeedbackService.playError();
        _showStatus(result['error'] ?? tr('general_error'), isError: true);
      }
    }
  }

  Future<void> _reopenPart(Map<String, dynamic> part) async {
    if (_currentLocation == null) return;

    final currentUser = AuthService.currentUser;
    if (currentUser == null) return;

    final numeroParte = part['numero_parte']?.toString() ?? '';
    if (numeroParte.trim().isEmpty) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr('audit_reopen_part_confirm_title')),
        content:
            Text('${tr('audit_reopen_part_confirm_body')}\n\n$numeroParte'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(tr('cancel')),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            child: Text(tr('audit_reopen_part')),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isProcessing = true);

    final result = await ApiService.reopenAuditPart(
      location: _currentLocation!,
      numeroParte: numeroParte,
      userId: currentUser.id,
    );

    if (mounted) {
      setState(() => _isProcessing = false);

      if (result['success'] == true) {
        FeedbackService.playSuccess();
        _showStatus('${tr('audit_part_reopened')}: $numeroParte',
            isError: false);
        setState(() {
          final selectedPart =
              _selectedPartForScan?['numero_parte']?.toString();
          if (selectedPart == numeroParte) {
            _scanQueue.clear();
            _partLabels = [];
            _selectedPartForScan = null;
            _scanMode = 'summary';
          }
        });
        await _reloadPartSummary();
      } else {
        FeedbackService.playError();
        _showStatus(result['error'] ?? tr('general_error'), isError: true);
      }
    }
  }

  Future<void> _showMissingLabelsForPart(String partNumber) async {
    if (_activeAudit == null || _currentLocation == null) return;

    final result = await ApiService.getAuditLocationItems(
      _activeAudit!['id'],
      _currentLocation!,
    );

    if (result['success'] != true) {
      FeedbackService.playError();
      _showStatus(result['error'] ?? tr('general_error'), isError: true);
      return;
    }

    final data = result['data'];
    final rawItems = data is Map<String, dynamic> ? data['items'] : data;
    final items = List<Map<String, dynamic>>.from(rawItems ?? []);
    final normalizedPart = _normalizePart(partNumber);
    final missingItems = items.where((item) {
      final itemPart = _normalizePart(item['numero_parte']?.toString() ?? '');
      final status = item['audit_status'] ?? 'Pending';
      return itemPart == normalizedPart && status == 'Missing';
    }).toList();

    if (!mounted || missingItems.isEmpty) return;

    final labels = missingItems
        .map((item) =>
            (item['warehousing_code'] ?? item['codigo_material_recibido'] ?? '')
                .toString())
        .where((code) => code.isNotEmpty)
        .toList();

    if (labels.isEmpty) return;

    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr('audit_missing_labels')),
        content: SizedBox(
          width: double.maxFinite,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 240),
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: labels.length,
              separatorBuilder: (_, __) => const Divider(height: 8),
              itemBuilder: (context, index) => Text(
                labels[index],
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(tr('ok')),
          ),
        ],
      ),
    );
  }

  // Recargar resumen de partes
  Future<void> _reloadPartSummary() async {
    if (_currentLocation == null) return;

    final result = await ApiService.getAuditLocationSummary(_currentLocation!);

    if (mounted && result['success'] == true) {
      final data = result['data'];
      setState(() {
        _partSummary = List<Map<String, dynamic>>.from(data['parts'] ?? []);
        _locationStatus = data['locationStatus']?.toString();

        // Actualizar _selectedPartForScan si sigue existiendo
        if (_selectedPartForScan != null) {
          final updated = _partSummary.firstWhere(
            (p) => p['numero_parte'] == _selectedPartForScan!['numero_parte'],
            orElse: () => {},
          );
          if (updated.isNotEmpty) {
            _selectedPartForScan = updated;
          }
        }
      });

      // Verificar si todas las partes están completadas
      final progress = data['progress'] as Map<String, dynamic>?;
      if (progress != null &&
          progress['pending'] == 0 &&
          progress['mismatch'] == 0) {
        _showStatus('✓ ${tr('audit_location_completed')}', isError: false);

        // Volver a modo ubicación
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) {
            setState(() {
              _currentLocation = null;
              _locationStatus = null;
              _partSummary = [];
              _selectedPartForScan = null;
              _partLabels = [];
              _scanMode = 'location';
            });
            _restoreScannerFocus();
          }
        });
      }
    }
  }

  // Cargar etiquetas de una parte específica para modo mismatch_scan
  Future<void> _loadPartLabels(String numeroParte) async {
    if (_activeAudit == null || _currentLocation == null) return;

    setState(() => _isLoadingLabels = true);

    final result = await ApiService.getAuditLocationItems(
      _activeAudit!['id'],
      _currentLocation!,
    );

    if (mounted) {
      setState(() => _isLoadingLabels = false);

      if (result['success'] == true) {
        final data = result['data'];
        final rawItems = data is Map<String, dynamic> ? data['items'] : data;
        final items = List<Map<String, dynamic>>.from(rawItems ?? []);
        final normalizedPart = _normalizePart(numeroParte);

        // Filtrar solo las etiquetas de esta parte
        setState(() {
          _partLabels = items.where((item) {
            final itemPart =
                _normalizePart(item['numero_parte']?.toString() ?? '');
            return itemPart == normalizedPart;
          }).toList();
        });
      } else {
        _showStatus(result['error'] ?? tr('general_error'), isError: true);
      }
    }
  }

  void _showStatus(String message, {required bool isError}) {
    setState(() {
      _statusMessage = message;
      _statusIsError = isError;
    });

    // Auto-ocultar después de 3 segundos
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted && _statusMessage == message) {
        setState(() => _statusMessage = null);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.panelBackground,
      appBar: AppBar(
        title: Text(tr('audit_inventory')),
        backgroundColor: AppColors.headerTab,
        foregroundColor: Colors.white,
        actions: [
          // Refrescar
          IconButton(
            onPressed: _loadActiveAudit,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _activeAudit == null
              ? _buildNoActiveAudit()
              : _buildAuditContent(),
    );
  }

  Widget _buildNoActiveAudit() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.inventory_2_outlined,
              size: 80,
              color: Colors.white24,
            ),
            const SizedBox(height: 24),
            Text(
              tr('audit_no_active'),
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              tr('audit_wait_supervisor'),
              style: const TextStyle(color: Colors.white54),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: _loadActiveAudit,
              icon: const Icon(Icons.refresh),
              label: Text(tr('refresh')),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAuditContent() {
    final canScan = _scanMode == 'location' ||
        _scanMode == 'summary' ||
        _scanMode == 'mismatch_scan';
    return Column(
      children: [
        // Status bar
        if (_statusMessage != null)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            color: _statusIsError ? Colors.red : Colors.green,
            child: Text(
              _statusMessage!,
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
          ),

        // Modo actual
        Container(
          padding: const EdgeInsets.all(16),
          color: AppColors.gridBackground,
          child: Row(
            children: [
              Icon(
                _scanMode == 'location'
                    ? Icons.location_on
                    : _scanMode == 'summary'
                        ? Icons.inventory_2
                        : _scanMode == 'mismatch_scan'
                            ? Icons.qr_code_scanner
                            : Icons.inventory,
                color: AppColors.headerTab,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _scanMode == 'location'
                          ? tr('audit_scan_location_mode')
                          : _scanMode == 'summary'
                              ? tr('audit_summary_by_part')
                              : _scanMode == 'mismatch_scan'
                                  ? '${tr('audit_scan_labels')}: ${_selectedPartForScan?['numero_parte'] ?? ''}'
                                  : tr('audit_scan_item_mode'),
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, color: Colors.white),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (_currentLocation != null)
                      Text(
                        '${tr('location')}: $_currentLocation',
                        style: const TextStyle(
                            fontSize: 12, color: Colors.white54),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              if (_currentLocation != null) ...[
                const SizedBox(width: 8),
                Flexible(
                  fit: FlexFit.loose,
                  child: TextButton(
                    onPressed: _cancelLocation,
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 6),
                      minimumSize: const Size(0, 0),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: Text(
                      tr('audit_change_location'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),

        // Input para esc?ner externo/PDA (prioridad sobre c?mara)
        if (canScan && ScannerConfigService.isReaderMode)
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _scannerInputController,
              focusNode: _scannerFocusNode,
              autofocus: true,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: _scanMode == 'location'
                    ? tr('audit_scan_location_label')
                    : tr('audit_scan_item_label'),
                prefixIcon:
                    const Icon(Icons.qr_code_scanner, color: Colors.white54),
                border: const OutlineInputBorder(),
                filled: true,
                fillColor: AppColors.fieldBackground,
              ),
              onSubmitted: _onExternalScannerInput,
            ),
          ),

        // ?rea de escaneo con c?mara
        if (canScan &&
            ScannerConfigService.isCameraMode &&
            !ScannerConfigService.isReaderMode)
          _buildScanArea(),

        // ========== MODO SUMMARY (v2) ==========
        if (_scanMode == 'summary')
          Expanded(
            child: _buildPartSummaryList(),
          ),

        if (_scanMode == 'summary' && _currentLocation != null)
          _buildPhysicalAuditActions(),

        // ========== MODO MISMATCH_SCAN (v2) ==========
        if (_scanMode == 'mismatch_scan')
          Expanded(
            child: _buildMismatchScanView(),
          ),

        // ========== MODO ITEM (legacy) ==========
        if (_scanMode == 'item')
          Expanded(
            child: _buildItemsList(),
          ),

        // Botón completar ubicación (solo modo item legacy)
        if (_scanMode == 'item' && _currentLocation != null)
          Container(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isProcessing ? null : _completeLocation,
                icon: _isProcessing
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check_circle),
                label: Text(tr('audit_complete_location')),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ),
          ),
      ],
    );
  }

  // ========== UI FLUJO V2 ==========

  Widget _buildPhysicalAuditActions() {
    final isEmpty = _partSummary.isEmpty;
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        color: AppColors.gridBackground,
        child: Row(
          children: [
            if (isEmpty) ...[
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _isProcessing ? null : _completeLocation,
                  icon: const Icon(Icons.inbox_outlined),
                  label: Text(tr('audit_confirm_empty_location')),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.green,
                    side: const BorderSide(color: Colors.green),
                    padding: const EdgeInsets.symmetric(vertical: 13),
                  ),
                ),
              ),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: ElevatedButton.icon(
                onPressed:
                    _isProcessing ? null : () => _showPhysicalItemDialog(),
                icon: const Icon(Icons.add_box_outlined),
                label: Text(tr('audit_register_physical_item')),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.headerTab,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPartSummaryList() {
    if (_partSummary.isEmpty) {
      return Center(
        child: Text(tr('audit_no_parts'),
            style: const TextStyle(color: Colors.white54)),
      );
    }

    // Contar estados
    final confirmed = _partSummary
        .where((p) =>
            p['status'] == 'Ok' ||
            p['status'] == 'VerifiedByScan' ||
            p['status'] == 'MissingConfirmed')
        .length;
    final mismatch =
        _partSummary.where((p) => p['status'] == 'Mismatch').length;
    final pending = _partSummary.where((p) => p['status'] == 'Pending').length;

    return Column(
      children: [
        if (_locationStatus == 'Verified' || _locationStatus == 'Discrepancy')
          Container(
            margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.gridBackground,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.green.withValues(alpha: 0.4)),
            ),
            child: Row(
              children: [
                const Icon(Icons.verified, color: Colors.green, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    tr('audit_location_verified'),
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ),
                TextButton(
                  onPressed: _isProcessing ? null : _reopenLocation,
                  child: Text(tr('audit_reopen_location')),
                ),
              ],
            ),
          ),
        // Resumen
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: AppColors.gridBackground,
          child: Wrap(
            alignment: WrapAlignment.spaceAround,
            spacing: 12,
            runSpacing: 8,
            children: [
              _buildCountBadge(tr('audit_confirmed'), confirmed, Colors.green),
              _buildCountBadge(tr('audit_mismatch'), mismatch, Colors.orange),
              _buildCountBadge(tr('audit_pending'), pending, Colors.grey),
            ],
          ),
        ),

        // Lista de partes
        Expanded(
          child: ListView.builder(
            itemCount: _partSummary.length,
            itemBuilder: (context, index) {
              final part = _partSummary[index];
              return _buildPartCard(part);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildPartCard(Map<String, dynamic> part) {
    final status = part['status'] as String? ?? 'Pending';
    final numeroParte = part['numero_parte'] ?? '';
    final expectedItems = _toInt(part['expected_items']);
    final scannedItems = _toInt(part['scanned_items']);
    final expectedQty = _toDouble(part['expected_qty']);
    final scannedQty = _toDouble(part['scanned_qty']);
    final physicalItems = _toInt(part['physical_items']);
    final physicalQty = _toDouble(part['physical_qty']);
    final quantityDifference = _toDouble(part['quantity_difference']);
    final newItems = _toInt(part['new_items']);
    final lotes = part['lotes'] as List<dynamic>? ?? [];

    // Determinar si mostrar formato "encontradas/esperadas" o solo "esperadas"
    final bool showScannedFormat = status != 'Pending';

    Color statusColor;
    IconData statusIcon;
    bool canConfirm = status == 'Pending';
    final bool canReopen = status != 'Pending';

    switch (status) {
      case 'Ok':
      case 'VerifiedByScan':
        statusColor = Colors.green;
        statusIcon = Icons.check_circle;
        break;
      case 'Mismatch':
        statusColor = Colors.orange;
        statusIcon = Icons.warning;
        break;
      case 'MissingConfirmed':
        statusColor = Colors.red;
        statusIcon = Icons.cancel;
        break;
      default:
        statusColor = Colors.grey;
        statusIcon = Icons.radio_button_unchecked;
    }

    final statusLabel = (status == 'Ok' || status == 'VerifiedByScan')
        ? tr('audit_confirmed').toUpperCase()
        : status == 'Mismatch'
            ? tr('audit_mismatch')
            : status == 'MissingConfirmed'
                ? tr('audit_missing_confirmed')
                : status;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      color: AppColors.gridBackground,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header: Número de parte + Status
            Row(
              children: [
                Icon(statusIcon, color: statusColor, size: 24),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    numeroParte,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: Colors.white,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    statusLabel,
                    style: TextStyle(
                        fontSize: 10,
                        color: statusColor,
                        fontWeight: FontWeight.bold),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 8),

            // Info: Etiquetas y cantidad
            Wrap(
              spacing: 12,
              runSpacing: 6,
              children: [
                _buildInfoChip(
                  context,
                  Icons.label,
                  showScannedFormat
                      ? '${tr('audit_found_labels')}: $scannedItems/$expectedItems'
                      : '${tr('audit_expected_labels')}: $expectedItems',
                ),
                _buildInfoChip(
                  context,
                  Icons.scale,
                  showScannedFormat
                      ? '${tr('audit_found_qty')}: ${_formatQty(scannedQty)}/${_formatQty(expectedQty)}'
                      : '${tr('audit_expected_qty')}: ${_formatQty(expectedQty)}',
                ),
                if (physicalItems > 0)
                  _buildInfoChip(
                    context,
                    Icons.fact_check_outlined,
                    '${tr('audit_physical_quantity')}: ${_formatQty(physicalQty)}',
                  ),
                if (quantityDifference.abs() >= 0.0001)
                  _buildInfoChip(
                    context,
                    quantityDifference > 0
                        ? Icons.trending_up
                        : Icons.trending_down,
                    '${tr('audit_quantity_difference')}: ${quantityDifference > 0 ? '+' : ''}${_formatQty(quantityDifference)}',
                  ),
                if (newItems > 0)
                  _buildInfoChip(
                    context,
                    Icons.add_circle_outline,
                    '${tr('audit_new_items')}: $newItems',
                  ),
                // Cantidad de lotes con stock
                if (lotes.isNotEmpty)
                  _buildInfoChip(
                    context,
                    Icons.inventory_2,
                    'Lotes: ${lotes.length}',
                  ),
              ],
            ),

            // Detalle de lotes de inventario_lotes (lo que el sistema cree que hay)
            if (lotes.isNotEmpty) ...[
              const SizedBox(height: 6),
              ...lotes.map<Widget>((lote) {
                final loteName = lote['numero_lote'] ?? '';
                final loteStock = lote['stock_actual'] ?? 0;
                return Padding(
                  padding: const EdgeInsets.only(left: 8, top: 2),
                  child: Row(
                    children: [
                      Icon(Icons.circle,
                          size: 6, color: Colors.white.withValues(alpha: 0.4)),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Lote: $loteName',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.7),
                            fontSize: 11,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        '${_formatQty(loteStock is num ? loteStock : 0)} pzas',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.7),
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ],

            // Botones de acción (solo si Pending)
            if (canConfirm) ...[
              const SizedBox(height: 12),
              LayoutBuilder(
                builder: (context, constraints) {
                  final isNarrow = constraints.maxWidth < 340;
                  final confirmButton = ElevatedButton.icon(
                    onPressed: _isProcessing ? null : () => _confirmPart(part),
                    icon: const Icon(Icons.check, size: 18),
                    label: Text(
                      tr('audit_confirm_ok'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                  );
                  final mismatchButton = OutlinedButton.icon(
                    onPressed: _isProcessing ? null : () => _flagMismatch(part),
                    icon: const Icon(Icons.close, size: 18),
                    label: Text(
                      tr('audit_flag_mismatch'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.orange,
                      side: const BorderSide(color: Colors.orange),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                  );

                  if (isNarrow) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        confirmButton,
                        const SizedBox(height: 8),
                        mismatchButton,
                      ],
                    );
                  }

                  return Row(
                    children: [
                      Expanded(child: confirmButton),
                      const SizedBox(width: 12),
                      Expanded(child: mismatchButton),
                    ],
                  );
                },
              ),
            ],

            // Si está en Mismatch, mostrar botón para escanear
            if (status == 'Mismatch') ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _isProcessing
                      ? null
                      : () async {
                          setState(() {
                            _selectedPartForScan = part;
                            _scanQueue.clear();
                            _partLabels = [];
                            _scanMode = 'mismatch_scan';
                          });
                          // Cargar etiquetas de esta parte
                          await _loadPartLabels(
                              part['numero_parte'].toString());
                          _restoreScannerFocus();
                        },
                  icon: const Icon(Icons.qr_code_scanner, size: 18),
                  label: Text(
                      '${tr('audit_scan_labels')} ($scannedItems/$expectedItems)'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
            ],
            if (canReopen) ...[
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _isProcessing ? null : () => _reopenPart(part),
                  icon: const Icon(Icons.restart_alt, size: 18),
                  label: Text(
                    tr('audit_reopen_part'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.orange,
                    side: const BorderSide(color: Colors.orange),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildMismatchScanView() {
    if (_selectedPartForScan == null) {
      return Center(
        child: Text(tr('audit_select_part_first'),
            style: const TextStyle(color: Colors.white54)),
      );
    }

    final part = _selectedPartForScan!;
    final expectedItems = _toInt(part['expected_items']);
    final scannedItems = _toInt(part['scanned_items']);
    final isKeyboardOpen = MediaQuery.of(context).viewInsets.bottom > 0;

    // Separar etiquetas por estado y ordenar por secuencia de codigo
    final pendingLabels = _partLabels
        .where((l) => (l['audit_status'] ?? 'Pending') == 'Pending')
        .toList()
      ..sort((a, b) => _compareLabelCodes(_labelCode(a), _labelCode(b)));
    final scannedLabels = _partLabels
        .where((l) => (l['audit_status'] ?? 'Pending') == 'Found')
        .toList()
      ..sort((a, b) => _compareLabelCodes(_labelCode(a), _labelCode(b)));

    Widget buildLabels({required bool scrollable}) {
      if (_isLoadingLabels) {
        return const Padding(
          padding: EdgeInsets.symmetric(vertical: 24),
          child: Center(child: CircularProgressIndicator()),
        );
      }

      if (_partLabels.isEmpty) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.qr_code_scanner,
                    size: 60, color: Colors.white.withValues(alpha: 0.3)),
                const SizedBox(height: 12),
                Text(
                  tr('audit_scan_all_or_confirm'),
                  style: const TextStyle(color: Colors.white54, fontSize: 14),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        );
      }

      final list = ListView(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        shrinkWrap: scrollable,
        physics: scrollable
            ? const NeverScrollableScrollPhysics()
            : const AlwaysScrollableScrollPhysics(),
        children: [
          if (pendingLabels.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text(
                '${tr('audit_pending')} (${pendingLabels.length})',
                style: const TextStyle(
                    color: Colors.orange,
                    fontWeight: FontWeight.bold,
                    fontSize: 12),
              ),
            ),
            ...pendingLabels
                .map((label) => _buildLabelTile(label, isPending: true)),
          ],
          if (scannedLabels.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 6),
              child: Text(
                '${tr('audit_scanned')} (${scannedLabels.length})',
                style: const TextStyle(
                    color: Colors.green,
                    fontWeight: FontWeight.bold,
                    fontSize: 12),
              ),
            ),
            ...scannedLabels
                .map((label) => _buildLabelTile(label, isPending: false)),
          ],
        ],
      );

      return scrollable ? list : Expanded(child: list);
    }

    Widget buildContent({required bool scrollable}) {
      return Column(
        children: [
          // Info de la parte
          Container(
            padding: const EdgeInsets.all(12),
            color: Colors.orange.withValues(alpha: 0.15),
            child: Row(
              children: [
                const Icon(Icons.warning, color: Colors.orange, size: 28),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        part['numero_parte'] ?? '',
                        style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            color: Colors.white),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        '${tr('audit_scanned_of')}: $scannedItems / $expectedItems',
                        style:
                            const TextStyle(fontSize: 13, color: Colors.orange),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Barra de progreso
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(
              children: [
                LinearProgressIndicator(
                  value: expectedItems > 0 ? scannedItems / expectedItems : 0,
                  backgroundColor: Colors.grey[800],
                  valueColor:
                      const AlwaysStoppedAnimation<Color>(Colors.orange),
                ),
                const SizedBox(height: 4),
                Text(
                  '${(expectedItems > 0 ? (scannedItems / expectedItems * 100) : 0).toStringAsFixed(0)}% ${tr('audit_scanned')}',
                  style: const TextStyle(color: Colors.white54, fontSize: 11),
                ),
              ],
            ),
          ),

          // Lista de etiquetas
          buildLabels(scrollable: scrollable),

          if (_scanQueue.isNotEmpty)
            Container(
              margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.gridBackground,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tr('audit_pending_scans'),
                    style: const TextStyle(
                        color: Colors.white70,
                        fontWeight: FontWeight.w600,
                        fontSize: 11),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: _scanQueue.map((code) {
                      return Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.fieldBackground,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          code,
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 10),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),

          SafeArea(
            top: false,
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed:
                          _isProcessing ? null : _undoMismatchAndConfirmOk,
                      icon: const Icon(Icons.check_circle, size: 18),
                      label: Text(tr('audit_confirm_ok'),
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () {
                            setState(() {
                              _selectedPartForScan = null;
                              _scanQueue.clear();
                              _partLabels = [];
                              _scanMode = 'summary';
                            });
                          },
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white54,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          child: Text(tr('back'),
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        flex: 2,
                        child: ElevatedButton.icon(
                          onPressed: _isProcessing ? null : _confirmMissing,
                          icon: _isProcessing
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.report_problem, size: 16),
                          label: Text(tr('audit_confirm_missing'),
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final shouldScroll = isKeyboardOpen || constraints.maxHeight < 520;
        if (!shouldScroll) {
          return buildContent(scrollable: false);
        }
        return SingleChildScrollView(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom + 16,
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: buildContent(scrollable: true),
          ),
        );
      },
    );
  }

  // Widget para cada etiqueta en la lista
  Widget _buildLabelTile(Map<String, dynamic> label,
      {required bool isPending}) {
    final code = _labelCode(label);
    final lot = label['numero_lote_material'] ?? '';
    final qty = label['cantidad_actual'] ?? 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: isPending
            ? Colors.red.withValues(alpha: 0.15)
            : Colors.green.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: isPending
              ? Colors.red.withValues(alpha: 0.3)
              : Colors.green.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          Icon(
            isPending ? Icons.radio_button_unchecked : Icons.check_circle,
            color: isPending ? Colors.red : Colors.green,
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  code.isEmpty ? '-' : code,
                  style: TextStyle(
                    color: isPending ? Colors.white : Colors.white70,
                    fontSize: 12,
                    fontWeight: isPending ? FontWeight.w500 : FontWeight.normal,
                    decoration: isPending ? null : TextDecoration.lineThrough,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (lot.toString().trim().isNotEmpty)
                  Text(
                    '${tr('lot_no')}: $lot',
                    style: TextStyle(
                      color: isPending ? Colors.white54 : Colors.white38,
                      fontSize: 10,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          Text(
            '${tr('quantity')}: ${_formatQty(qty is num ? qty : 0)}',
            style: TextStyle(
              color: isPending ? Colors.white54 : Colors.white38,
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScanArea() {
    return Container(
      height: 200,
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Stack(
        children: [
          if (_isScannerActive && _scannerController != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: MobileScanner(
                controller: _scannerController!,
                onDetect: _onBarcodeDetected,
              ),
            )
          else
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.qr_code_scanner,
                    size: 60,
                    color: Colors.white.withValues(alpha: 0.5),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: _startCameraScanner,
                    icon: const Icon(Icons.camera_alt),
                    label: Text(tr('audit_start_scan')),
                  ),
                ],
              ),
            ),

          // Botón para detener cámara
          if (_isScannerActive)
            Positioned(
              top: 8,
              right: 8,
              child: IconButton(
                onPressed: _stopCameraScanner,
                icon: const Icon(Icons.close, color: Colors.white),
                style: IconButton.styleFrom(
                  backgroundColor: Colors.black54,
                ),
              ),
            ),

          // Indicador de procesamiento
          if (_isProcessing)
            Container(
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Center(
                child: CircularProgressIndicator(),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildItemsList() {
    if (_locationItems.isEmpty) {
      return Center(
        child: Text(tr('audit_no_items')),
      );
    }

    // Contar estados
    final found =
        _locationItems.where((i) => i['audit_status'] == 'Found').length;
    final missing =
        _locationItems.where((i) => i['audit_status'] == 'Missing').length;
    final pending = _locationItems
        .where((i) => (i['audit_status'] ?? 'Pending') == 'Pending')
        .length;

    return Column(
      children: [
        // Resumen
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: AppColors.gridBackground,
          child: Wrap(
            alignment: WrapAlignment.spaceAround,
            spacing: 12,
            runSpacing: 8,
            children: [
              _buildCountBadge(tr('audit_found'), found, Colors.green),
              _buildCountBadge(tr('audit_missing'), missing, Colors.red),
              _buildCountBadge(tr('audit_pending'), pending, Colors.orange),
            ],
          ),
        ),

        // Lista
        Expanded(
          child: ListView.builder(
            itemCount: _locationItems.length,
            itemBuilder: (context, index) {
              final item = _locationItems[index];
              final status = item['audit_status'] as String? ?? 'Pending';

              Color statusColor;
              IconData statusIcon;
              switch (status) {
                case 'Found':
                  statusColor = Colors.green;
                  statusIcon = Icons.check_circle;
                  break;
                case 'Missing':
                  statusColor = Colors.red;
                  statusIcon = Icons.cancel;
                  break;
                default:
                  statusColor = Colors.orange;
                  statusIcon = Icons.radio_button_unchecked;
              }

              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: ListTile(
                  leading: Icon(statusIcon, color: statusColor, size: 32),
                  title: Text(
                    item['warehousing_code'] ??
                        item['codigo_material_recibido'] ??
                        '',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item['numero_parte'] ?? '',
                          style: const TextStyle(
                              fontSize: 12, color: Colors.white70)),
                      Text(
                        '${tr('quantity')}: ${item['cantidad_actual'] ?? '-'}',
                        style: const TextStyle(
                            fontSize: 11, color: Colors.white54),
                      ),
                    ],
                  ),
                  trailing: status == 'Pending'
                      ? IconButton(
                          onPressed: () => _markMissing(item),
                          icon: const Icon(Icons.report_problem,
                              color: Colors.orange),
                          tooltip: tr('audit_mark_missing'),
                        )
                      : Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: statusColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            status,
                            style: TextStyle(
                              fontSize: 11,
                              color: statusColor,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildCountBadge(String label, int count, Color color) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color),
          ),
          child: Text(
            '$count',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(fontSize: 10, color: Colors.white54),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }

  Widget _buildInfoChip(BuildContext context, IconData icon, String text,
      {Color? color}) {
    final iconColor = color ?? Colors.white54;
    final textColor = color ?? Colors.white70;
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 14, color: iconColor),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            text,
            style: TextStyle(fontSize: 11, color: textColor),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
