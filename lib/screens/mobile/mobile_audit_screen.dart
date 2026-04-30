import 'dart:async';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
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
  List<Map<String, dynamic>> _locationItems = [];
  
  // Estados para flujo v2 (por parte)
  List<Map<String, dynamic>> _partSummary = [];
  Map<String, dynamic>? _selectedPartForScan;
  
  bool _isLoading = false;
  bool _isProcessing = false;
  
  // Control de escaneo
  String? _lastProcessedCode;
  DateTime? _lastScanTime;
  
  // Modo de escaneo: 'location', 'summary' (v2), 'mismatch_scan' (v2), 'item' (legacy)
  String _scanMode = 'location';
  
  // Mensajes de estado
  String? _statusMessage;
  bool _statusIsError = false;

  String tr(String key) => widget.languageProvider.tr(key);

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
    if (capture.barcodes.isEmpty || _isProcessing) return;
    
    final barcode = capture.barcodes.first;
    if (barcode.rawValue == null) return;
    
    final code = barcode.rawValue!.trim();
    _processScannedCode(code);
  }
  
  void _onExternalScannerInput(String value) {
    if (value.isEmpty || _isProcessing) return;
    
    final code = value.trim();
    _scannerInputController.clear();
    _processScannedCode(code);
  }
  
  Future<void> _processScannedCode(String code) async {
    // Evitar procesar el mismo código muy rápido
    final now = DateTime.now();
    if (_lastProcessedCode == code && 
        _lastScanTime != null && 
        now.difference(_lastScanTime!).inMilliseconds < 1500) {
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
        // En modo summary solo se puede escanear ubicaciones nuevas
        FeedbackService.playDuplicate();
        _showStatus(tr('audit_use_buttons'), isError: true);
      } else {
        // Modo legacy: Escanear material individual
        await _scanItem(code, currentUser.id);
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }
  
  Future<void> _scanLocation(String location, int userId) async {
    // Primero registrar escaneo de ubicación en el backend
    final scanResult = await ApiService.auditScanLocation(
      auditId: _activeAudit!['id'],
      location: location,
      scannedBy: userId,
    );
    
    if (scanResult['success'] != true) {
      FeedbackService.playError();
      _showStatus(scanResult['error'] ?? tr('audit_scan_error'), isError: true);
      return;
    }

    final scanData = scanResult['data'] as Map<String, dynamic>?;
    if (_applyPartSummary(
      scanData,
      location: location,
      nextScanMode: 'summary',
      clearSelection: true,
    )) {
      FeedbackService.playSuccess();
      final progress = scanData?['progress'] ?? {};
      _showStatus(
        '📦 $location: ${_partSummary.length} ${tr('audit_parts')} (${progress['confirmed'] ?? 0} ${tr('audit_confirmed')})', 
        isError: false
      );
      return;
    }

    // Fallback para backends sin respuesta compacta
    final result = await ApiService.getAuditLocationSummary(location);
    if (result['success'] == true &&
        _applyPartSummary(
          result['data'],
          location: location,
          nextScanMode: 'summary',
          clearSelection: true,
        )) {
      FeedbackService.playSuccess();
      final data = result['data'];
      final progress = data['progress'] ?? {};
      _showStatus(
        '📦 $location: ${_partSummary.length} ${tr('audit_parts')} (${progress['confirmed'] ?? 0} ${tr('audit_confirmed')})',
        isError: false,
      );
    } else {
      FeedbackService.playError();
      _showStatus(result['error'] ?? tr('audit_scan_error'), isError: true);
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
      setState(() {
        final index = _locationItems.indexWhere(
          (item) => item['codigo_material_recibido'] == scannedCode,
        );
        if (index >= 0) {
          _locationItems[index]['audit_status'] = 'Found';
          _locationItems[index]['scanned_by_name'] = AuthService.currentUser?.nombreCompleto ?? '';
        }
      });
      
      _showStatus('✓ $scannedCode', isError: false);
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
              item['warehousing_code'] ?? item['codigo_material_recibido'] ?? '',
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
    final pendingItems = _locationItems.where((i) => (i['audit_status'] ?? 'Pending') == 'Pending').toList();
    
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
          _locationItems = [];
          _scanMode = 'location';
        });
      } else {
        FeedbackService.playError();
        _showStatus(result['error'] ?? tr('audit_complete_error'), isError: true);
      }
    }
  }
  
  void _cancelLocation() {
    setState(() {
      _currentLocation = null;
      _locationItems = [];
      _partSummary = [];
      _selectedPartForScan = null;
      _scanMode = 'location';
    });
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
        _showStatus('✓ ${tr('audit_part_confirmed')}: ${part['numero_parte']}', isError: false);
        if (!_applyPartSummary(result['data'])) {
          await _reloadPartSummary();
        }
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
        _showStatus('⚠ ${tr('audit_mismatch_flagged')}: ${part['numero_parte']}', isError: false);
        
        // Cambiar a modo escaneo de etiquetas de esta parte
        setState(() {
          _selectedPartForScan = part;
          _scanMode = 'mismatch_scan';
        });
        
        final data = result['data'] as Map<String, dynamic>?;
        if (_applyPartSummary(data, nextScanMode: 'mismatch_scan')) {
          setState(() {
            _selectedPartForScan =
                _partSummary.cast<Map<String, dynamic>?>().firstWhere(
                      (item) => item?['numero_parte'] == part['numero_parte'],
                      orElse: () => part,
                    );
          });
        } else {
          await _reloadPartSummary();
        }
      } else {
        FeedbackService.playError();
        _showStatus(result['error'] ?? tr('general_error'), isError: true);
      }
    }
  }
  
  // Escanear etiqueta individual de una parte en Mismatch
  Future<void> _scanPartItem(String warehousingCode, int userId) async {
    if (_currentLocation == null || _selectedPartForScan == null) {
      FeedbackService.playError();
      _showStatus(tr('audit_select_part_first'), isError: true);
      return;
    }
    
    final result = await ApiService.scanAuditPartItem(
      location: _currentLocation!,
      warehousingCode: warehousingCode,
      userId: userId,
    );
    
    if (result['success'] == true) {
      FeedbackService.playSuccess();
      final data = result['data'];
      final progress = data['progress'] as Map<String, dynamic>?;
      
      _showStatus(
        '✓ ${data['warehousingCode']}: ${progress?['scanned'] ?? 0}/${progress?['expected'] ?? 0}',
        isError: false,
      );
      
      if (!_applyPartSummary(data, nextScanMode: 'mismatch_scan')) {
        await _reloadPartSummary();
      }
    } else {
      FeedbackService.playError();
      _showStatus(result['error'] ?? tr('audit_scan_error'), isError: true);
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
            Text('${tr('audit_confirm_missing_part')}: ${_selectedPartForScan!['numero_parte']}'),
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
        final processedOut = data?['processedOut'] ?? 0;
        _showStatus(
          '${tr('audit_missing_confirmed')}: ${data?['missingItems'] ?? 0} ${tr('audit_items')} - $processedOut ${tr('audit_outgoing_created')}',
          isError: false,
        );
        
        // Volver a modo resumen
        setState(() {
          _selectedPartForScan = null;
          _scanMode = 'summary';
        });
        
        if (!_applyPartSummary(result['data'])) {
          await _reloadPartSummary();
        }
      } else {
        FeedbackService.playError();
        _showStatus(result['error'] ?? tr('general_error'), isError: true);
      }
    }
  }
  
  bool _applyPartSummary(
    Map<String, dynamic>? data, {
    String? location,
    String? nextScanMode,
    bool clearSelection = false,
  }) {
    if (data == null || data['parts'] is! List) {
      return false;
    }

    final parts = List<Map<String, dynamic>>.from(data['parts'] ?? []);
    final progress = data['progress'] as Map<String, dynamic>?;

    setState(() {
      if (location != null) {
        _currentLocation = location;
      }
      _partSummary = parts;
      _locationItems = [];

      if (clearSelection) {
        _selectedPartForScan = null;
      } else if (_selectedPartForScan != null) {
        final updated = _partSummary.cast<Map<String, dynamic>?>().firstWhere(
              (part) => part?['numero_parte'] == _selectedPartForScan!['numero_parte'],
              orElse: () => null,
            );
        _selectedPartForScan = updated;
      }

      if (nextScanMode != null) {
        _scanMode = nextScanMode;
      }
    });

    if (progress != null && progress['pending'] == 0 && progress['mismatch'] == 0) {
      _showStatus('✓ ${tr('audit_location_completed')}', isError: false);
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) {
          setState(() {
            _currentLocation = null;
            _partSummary = [];
            _selectedPartForScan = null;
            _scanMode = 'location';
          });
        }
      });
    }

    return true;
  }

  // Recargar resumen de partes
  Future<void> _reloadPartSummary() async {
    if (_currentLocation == null) return;

    final result = await ApiService.getAuditLocationSummary(_currentLocation!);
    if (mounted && result['success'] == true) {
      _applyPartSummary(result['data']);
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
    final canScan = _scanMode == 'location' || _scanMode == 'mismatch_scan';
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
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        
        // Modo actual
        Container(
          padding: const EdgeInsets.all(16),
          color: AppColors.gridBackground,
          child: Row(
            children: [
              Icon(
                _scanMode == 'location' ? Icons.location_on 
                  : _scanMode == 'summary' ? Icons.inventory_2
                  : _scanMode == 'mismatch_scan' ? Icons.qr_code_scanner
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
                      style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (_currentLocation != null)
                      Text(
                        '${tr('location')}: $_currentLocation',
                        style: const TextStyle(fontSize: 12, color: Colors.white54),
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
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
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
                prefixIcon: const Icon(Icons.qr_code_scanner, color: Colors.white54),
                border: const OutlineInputBorder(),
                filled: true,
                fillColor: AppColors.fieldBackground,
              ),
              onSubmitted: _onExternalScannerInput,
            ),
          ),

        // ?rea de escaneo con c?mara
        if (canScan && ScannerConfigService.isCameraMode && !ScannerConfigService.isReaderMode)
          _buildScanArea(),

        // ========== MODO SUMMARY (v2) ==========
        if (_scanMode == 'summary')
          Expanded(
            child: _buildPartSummaryList(),
          ),
        
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
  
  Widget _buildPartSummaryList() {
    if (_partSummary.isEmpty) {
      return Center(
        child: Text(tr('audit_no_parts'), style: const TextStyle(color: Colors.white54)),
      );
    }
    
    // Contar estados
    final confirmed = _partSummary.where((p) => 
      p['status'] == 'Ok' || p['status'] == 'VerifiedByScan' || p['status'] == 'MissingConfirmed'
    ).length;
    final mismatch = _partSummary.where((p) => p['status'] == 'Mismatch').length;
    final pending = _partSummary.where((p) => p['status'] == 'Pending').length;
    
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
    
    Color statusColor;
    IconData statusIcon;
    bool canConfirm = status == 'Pending';
    
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

    final statusLabel = status == 'Ok'
        ? 'OK'
        : status == 'VerifiedByScan'
            ? tr('audit_verified')
            : status == 'Mismatch'
                ? tr('audit_mismatch')
                : status == 'MissingConfirmed'
                    ? tr('audit_missing')
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
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    statusLabel,
                    style: TextStyle(fontSize: 10, color: statusColor, fontWeight: FontWeight.bold),
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
                  '${tr('audit_expected_labels')}: $expectedItems',
                ),
                _buildInfoChip(
                  context,
                  Icons.scale,
                  '${tr('audit_expected_qty')}: ${expectedQty.toStringAsFixed(0)}',
                ),
              ],
            ),
            
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
                  onPressed: _isProcessing ? null : () {
                    setState(() {
                      _selectedPartForScan = part;
                      _scanMode = 'mismatch_scan';
                    });
                  },
                  icon: const Icon(Icons.qr_code_scanner, size: 18),
                  label: Text('${tr('audit_scan_labels')} ($scannedItems/$expectedItems)'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    foregroundColor: Colors.white,
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
        child: Text(tr('audit_select_part_first'), style: const TextStyle(color: Colors.white54)),
      );
    }
    
    final part = _selectedPartForScan!;
    final expectedItems = _toInt(part['expected_items']);
    final scannedItems = _toInt(part['scanned_items']);
    
    return Column(
      children: [
        // Info de la parte
        Container(
          padding: const EdgeInsets.all(16),
          color: Colors.orange.withValues(alpha: 0.15),
          child: Row(
            children: [
              const Icon(Icons.warning, color: Colors.orange, size: 32),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      part['numero_parte'] ?? '',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      '${tr('audit_scanned_of')}: $scannedItems / $expectedItems',
                      style: const TextStyle(fontSize: 14, color: Colors.orange),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        
        // Barra de progreso
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              LinearProgressIndicator(
                value: expectedItems > 0 ? scannedItems / expectedItems : 0,
                backgroundColor: Colors.grey[800],
                valueColor: const AlwaysStoppedAnimation<Color>(Colors.orange),
              ),
              const SizedBox(height: 8),
              Text(
                '${(expectedItems > 0 ? (scannedItems / expectedItems * 100) : 0).toStringAsFixed(0)}% ${tr('audit_scanned')}',
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ],
          ),
        ),
        
        // Instrucciones
        Expanded(
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.qr_code_scanner, size: 80, color: Colors.white.withValues(alpha: 0.3)),
                const SizedBox(height: 16),
                Text(
                  tr('audit_scan_all_or_confirm'),
                  style: const TextStyle(color: Colors.white54, fontSize: 16),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
        
        // Botones de acción
        Container(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final isNarrow = constraints.maxWidth < 340;
                    final backButton = OutlinedButton(
                      onPressed: () {
                        setState(() {
                          _selectedPartForScan = null;
                          _scanMode = 'summary';
                        });
                      },
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white54,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: Text(
                        tr('back'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    );
                    final confirmButton = ElevatedButton.icon(
                      onPressed: _isProcessing ? null : _confirmMissing,
                      icon: _isProcessing
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.report_problem),
                      label: Text(
                        tr('audit_confirm_missing'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                    );

                    if (isNarrow) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          backButton,
                          const SizedBox(height: 8),
                          confirmButton,
                        ],
                      );
                    }

                    return Row(
                      children: [
                        Expanded(child: backButton),
                        const SizedBox(width: 12),
                        Expanded(flex: 2, child: confirmButton),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ],
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
    final found = _locationItems.where((i) => i['audit_status'] == 'Found').length;
    final missing = _locationItems.where((i) => i['audit_status'] == 'Missing').length;
    final pending = _locationItems.where((i) => (i['audit_status'] ?? 'Pending') == 'Pending').length;
    
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
                    item['warehousing_code'] ?? item['codigo_material_recibido'] ?? '',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item['numero_parte'] ?? '', style: const TextStyle(fontSize: 12, color: Colors.white70)),
                      Text(
                        '${tr('quantity')}: ${item['cantidad_actual'] ?? '-'}',
                        style: const TextStyle(fontSize: 11, color: Colors.white54),
                      ),
                    ],
                  ),
                  trailing: status == 'Pending'
                    ? IconButton(
                        onPressed: () => _markMissing(item),
                        icon: const Icon(Icons.report_problem, color: Colors.orange),
                        tooltip: tr('audit_mark_missing'),
                      )
                    : Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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

  Widget _buildInfoChip(BuildContext context, IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: Colors.white54),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            text,
            style: const TextStyle(fontSize: 12, color: Colors.white70),
          ),
        ),
      ],
    );
  }
}

