import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:material_warehousing_flutter/core/localization/app_translations.dart';
import 'package:material_warehousing_flutter/core/services/api_service.dart';
import 'package:material_warehousing_flutter/core/services/auth_service.dart';
import 'package:material_warehousing_flutter/core/services/feedback_service.dart';
import 'package:material_warehousing_flutter/core/services/scan_batcher.dart';
import 'package:material_warehousing_flutter/core/services/scanner_config_service.dart';
import 'package:material_warehousing_flutter/core/theme/app_colors.dart';

/// Pantalla de salidas de material para móvil con escaneo en lote
/// Soporta cámara y escáner externo (Bluetooth/USB)
class MobileOutgoingScreen extends StatefulWidget {
  final LanguageProvider languageProvider;

  const MobileOutgoingScreen({
    super.key,
    required this.languageProvider,
  });

  @override
  State<MobileOutgoingScreen> createState() => _MobileOutgoingScreenState();
}

class _MobileOutgoingScreenState extends State<MobileOutgoingScreen> {
  // Scanner
  MobileScannerController? _scannerController;
  bool _isScannerActive = false;
  
  // Escáner externo
  final TextEditingController _scannerInputController = TextEditingController();
  final FocusNode _scannerFocusNode = FocusNode();
  
  // Lista de materiales escaneados (máximo 100)
  final List<Map<String, dynamic>> _scannedMaterials = [];
  static const int _maxMaterials = 100;
  ScanBatcher<Map<String, dynamic>>? _validationBatcher;
  
  // Control de escaneo continuo
  String? _lastProcessedCode;
  DateTime? _lastScanTime;
  
  // Sistema de cola para escaneo rápido
  final Set<String> _processingCodes = {};  // Códigos en proceso (evita duplicados)
  int _pendingCount = 0;  // Contador de procesamientos pendientes
  static const int _maxConcurrent = 50;  // Máximo procesamientos concurrentes
  
  // Estado de carga (solo para submit final)
  bool _isSubmitting = false;
  
  // Mensajes de estado
  String? _statusMessage;
  bool _statusIsError = false;

  String tr(String key) => widget.languageProvider.tr(key);

  @override
  void initState() {
    super.initState();
    FeedbackService.init();
    if (ApiService.isSlowLinkAndroid) {
      _validationBatcher = ScanBatcher<Map<String, dynamic>>(
        loader: (codes) async {
          final results = await ApiService.validateMaterialsForBatch(codes);
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
  }

  @override
  void dispose() {
    _validationBatcher?.dispose();
    _scannerController?.dispose();
    _scannerInputController.dispose();
    _scannerFocusNode.dispose();
    super.dispose();
  }

  void _startCameraScanner() {
    if (ScannerConfigService.isReaderMode) {
      // Modo lector/PDA - mostrar campo de texto
      setState(() {
        _isScannerActive = true;
        _lastProcessedCode = null;
      });
      Future.delayed(const Duration(milliseconds: 100), () {
        _scannerFocusNode.requestFocus();
      });
      return;
    }
    
    // Modo cámara
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
    
    // Evitar procesar el mismo código muy rápido (reducido a 300ms)
    final now = DateTime.now();
    if (_lastProcessedCode == code && 
        _lastScanTime != null && 
        now.difference(_lastScanTime!).inMilliseconds < 300) {
      return;
    }
    
    _lastProcessedCode = code;
    _lastScanTime = now;
    
    _processScannedCode(code);
  }

  void _onExternalScannerInput(String code) {
    final trimmedCode = code.trim();
    if (trimmedCode.isEmpty) return;
    
    _scannerInputController.clear();
    _processScannedCode(trimmedCode);
    
    // Mantener el foco para el siguiente escaneo (sin delay)
    _scannerFocusNode.requestFocus();
  }

  Future<void> _processScannedCode(String code) async {
    // Verificar límite de materiales
    if (_scannedMaterials.length >= _maxMaterials) {
      await FeedbackService.vibrateError();
      _showStatus(tr('batch_limit_reached'), isError: true);
      return;
    }
    
    // Verificar límite de procesamientos concurrentes
    if (_pendingCount >= _maxConcurrent) {
      // No bloquear, solo ignorar silenciosamente
      return;
    }
    
    // Verificar si ya está en la lista o en proceso
    final isDuplicate = _scannedMaterials.any(
      (m) => m['codigo_material_recibido'] == code
    );
    if (isDuplicate || _processingCodes.contains(code)) {
      // Ignorar silenciosamente
      return;
    }
    
    // Marcar como en proceso
    _processingCodes.add(code);
    _pendingCount++;
    
    try {
      // Validar con el backend (no bloquea nuevos escaneos)
      final result = await _validateMaterial(code);
      
      if (result['valid'] == true) {
        final material = result['material'] as Map<String, dynamic>;
        
        if (mounted) {
          setState(() {
            _scannedMaterials.insert(0, {
              'codigo_material_recibido': code,
              'numero_parte': material['numero_parte'] ?? '',
              'cantidad': material['cantidad'] ?? 0,
              'ubicacion': material['ubicacion'] ?? '',
              'standard_pack': material['standard_pack'] ?? 0,
            });
          });
        }
        
        await FeedbackService.vibrateSuccess();
        _showStatus('✓ $code', isError: false);
        
      } else {
        await FeedbackService.vibrateError();
        final errorMsg = result['error'] ?? tr('validation_error');
        _showStatus('✗ $code: $errorMsg', isError: true);
      }
      
    } catch (e) {
      await FeedbackService.vibrateError();
      _showStatus('Error: $e', isError: true);
    } finally {
      _processingCodes.remove(code);
      _pendingCount--;
    }
  }

  Future<Map<String, dynamic>> _validateMaterial(String code) async {
    if (!ApiService.isSlowLinkAndroid || _validationBatcher == null) {
      return ApiService.validateMaterialForBatch(code);
    }

    final result = await _validationBatcher!.enqueue(code);
    if (result != null) {
      return result;
    }

    return {
      'valid': false,
      'error': tr('validation_error'),
      'code': 'BATCH_LOOKUP_EMPTY',
    };
  }

  void _removeMaterial(int index) {
    setState(() {
      _scannedMaterials.removeAt(index);
    });
  }

  void _clearAllMaterials() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF252A3C),
        title: Text(tr('clear_list'), style: const TextStyle(color: Colors.white)),
        content: Text(
          tr('clear_list_confirm'),
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(tr('cancel')),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              Navigator.pop(context);
              setState(() {
                _scannedMaterials.clear();
              });
            },
            child: Text(tr('clear')),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmBatchOutgoing() async {
    if (_scannedMaterials.isEmpty) {
      _showStatus(tr('no_materials_to_process'), isError: true);
      return;
    }
    
    // Confirmar
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF252A3C),
        title: Text(tr('confirm_batch_outgoing'), style: const TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${tr('materials_to_process')}: ${_scannedMaterials.length}',
              style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Text(
              tr('batch_outgoing_warning'),
              style: TextStyle(color: Colors.orange.shade300, fontSize: 14),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(tr('cancel')),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            onPressed: () => Navigator.pop(context, true),
            child: Text(tr('confirm_btn')),
          ),
        ],
      ),
    );
    
    if (confirmed != true) return;
    
    setState(() {
      _isSubmitting = true;
    });
    
    try {
      final user = AuthService.currentUser;
      
      final result = await ApiService.createOutgoingBatch(
        _scannedMaterials,
        user?.nombreCompleto ?? 'Mobile User',
      );
      
      setState(() {
        _isSubmitting = false;
      });
      
      if (result['success'] == true) {
        final processed = result['processed'] ?? 0;
        final failed = result['failed'] ?? 0;
        
        await FeedbackService.vibrateSuccess();
        
        // Mostrar resumen
        await showDialog(
          context: context,
          builder: (context) => AlertDialog(
            backgroundColor: const Color(0xFF252A3C),
            title: Row(
              children: [
                Icon(
                  failed == 0 ? Icons.check_circle : Icons.warning,
                  color: failed == 0 ? Colors.green : Colors.orange,
                ),
                const SizedBox(width: 8),
                Text(tr('batch_result'), style: const TextStyle(color: Colors.white)),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildResultRow(tr('processed_ok'), processed.toString(), Colors.green),
                if (failed > 0)
                  _buildResultRow(tr('processed_failed'), failed.toString(), Colors.red),
                _buildResultRow(tr('total'), '${processed + failed}', Colors.white),
              ],
            ),
            actions: [
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.headerTab),
                onPressed: () => Navigator.pop(context),
                child: Text(tr('ok')),
              ),
            ],
          ),
        );
        
        // Limpiar lista procesada
        setState(() {
          _scannedMaterials.clear();
        });
        
      } else {
        await FeedbackService.vibrateError();
        _showStatus(result['error'] ?? tr('batch_error'), isError: true);
      }
      
    } catch (e) {
      setState(() {
        _isSubmitting = false;
      });
      await FeedbackService.vibrateError();
      _showStatus('Error: $e', isError: true);
    }
  }

  Widget _buildResultRow(String label, String value, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.white70)),
          Text(
            value,
            style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 18),
          ),
        ],
      ),
    );
  }

  void _showStatus(String message, {bool isError = false}) {
    setState(() {
      _statusMessage = message;
      _statusIsError = isError;
    });
    
    // Auto-ocultar después de 3 segundos
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted && _statusMessage == message) {
        setState(() {
          _statusMessage = null;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!AuthService.canWriteOutgoing) {
      return _buildNoPermissionScreen();
    }

    return Column(
      children: [
        // Área de escaneo (según modo configurado)
        Expanded(
          flex: 2,
          child: ScannerConfigService.isCameraMode ? _buildCameraScanner() : _buildExternalScanner(),
        ),
        
        // Mensaje de estado
        if (_statusMessage != null) _buildStatusMessage(),
        
        // Lista de materiales escaneados
        Expanded(
          flex: 3,
          child: _buildScannedList(),
        ),
        
        // Botón de confirmar
        _buildConfirmButton(),
      ],
    );
  }

  Widget _buildNoPermissionScreen() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.lock, size: 64, color: Colors.white.withValues(alpha: 0.3)),
          const SizedBox(height: 16),
          Text(
            tr('no_permission_mobile'),
            style: const TextStyle(color: Colors.white54, fontSize: 16),
          ),
        ],
      ),
    );
  }

  Widget _buildCameraScanner() {
    if (!_isScannerActive) {
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF252A3C),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.camera_alt, size: 48, color: Colors.white.withOpacity(0.3)),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _startCameraScanner,
                icon: const Icon(Icons.play_arrow),
                label: Text(tr('start_camera')),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.headerTab,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      clipBehavior: Clip.hardEdge,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Stack(
        children: [
          MobileScanner(
            controller: _scannerController!,
            onDetect: _onBarcodeDetected,
          ),
          // Overlay
          Center(
            child: Container(
              width: 250,
              height: 120,
              decoration: BoxDecoration(
                border: Border.all(
                  color: _pendingCount > 0 ? Colors.orange : Colors.green,
                  width: 3,
                ),
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
          // Indicador de procesando (contador)
          if (_pendingCount > 0)
            Positioned(
              top: 16,
              right: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.orange,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  'Procesando: $_pendingCount',
                  style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          // Botones de control
          Positioned(
            bottom: 8,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                IconButton(
                  onPressed: () => _scannerController?.toggleTorch(),
                  icon: const Icon(Icons.flash_auto, color: Colors.white),
                ),
                IconButton(
                  onPressed: _stopCameraScanner,
                  icon: const Icon(Icons.stop_circle, color: Colors.red),
                ),
                IconButton(
                  onPressed: () => _scannerController?.switchCamera(),
                  icon: const Icon(Icons.cameraswitch, color: Colors.white),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExternalScanner() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF252A3C),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.qr_code_scanner,
            size: 48,
            color: _scannerFocusNode.hasFocus ? AppColors.headerTab : Colors.white38,
          ),
          const SizedBox(height: 16),
          Text(
            tr('external_scanner_instruction'),
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70, fontSize: 14),
          ),
          const SizedBox(height: 16),
          // Campo de entrada oculto para capturar input del escáner
          TextField(
            controller: _scannerInputController,
            focusNode: _scannerFocusNode,
            autofocus: ScannerConfigService.isReaderMode,
            style: const TextStyle(color: Colors.white, fontSize: 16),
            decoration: InputDecoration(
              hintText: tr('scan_or_type_code'),
              hintStyle: const TextStyle(color: Colors.white38),
              prefixIcon: Icon(
                Icons.keyboard,
                color: _scannerFocusNode.hasFocus ? AppColors.headerTab : Colors.white38,
              ),
              filled: true,
              fillColor: const Color(0xFF1A1E2C),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: AppColors.headerTab, width: 2),
              ),
            ),
            textInputAction: TextInputAction.done,
            onSubmitted: _onExternalScannerInput,
            // Capturar Enter del escáner
            onChanged: (value) {
              // Algunos escáneres envían el código completo de una vez
              if (value.contains('\n') || value.contains('\r')) {
                final cleanCode = value.replaceAll('\n', '').replaceAll('\r', '').trim();
                if (cleanCode.isNotEmpty) {
                  _onExternalScannerInput(cleanCode);
                }
              }
            },
          ),
          const SizedBox(height: 8),
          Text(
            _scannerFocusNode.hasFocus 
                ? '✓ ${tr('scanner_ready')}'
                : tr('tap_to_focus'),
            style: TextStyle(
              color: _scannerFocusNode.hasFocus ? Colors.green : Colors.orange,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusMessage() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: _statusIsError 
            ? Colors.red.withOpacity(0.2)
            : Colors.green.withOpacity(0.2),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: _statusIsError ? Colors.red : Colors.green,
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Icon(
            _statusIsError ? Icons.error : Icons.check_circle,
            color: _statusIsError ? Colors.red : Colors.green,
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _statusMessage!,
              style: TextStyle(
                color: _statusIsError ? Colors.red.shade200 : Colors.green.shade200,
                fontSize: 13,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScannedList() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF252A3C),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Colors.white12)),
            ),
            child: Row(
              children: [
                const Icon(Icons.list_alt, color: Colors.orange, size: 20),
                const SizedBox(width: 8),
                Text(
                  '${tr('scanned_materials')}: ${_scannedMaterials.length}/$_maxMaterials',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                if (_scannedMaterials.isNotEmpty)
                  IconButton(
                    onPressed: _clearAllMaterials,
                    icon: const Icon(Icons.delete_sweep, color: Colors.red, size: 20),
                    tooltip: tr('clear_all'),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
              ],
            ),
          ),
          // Lista
          Expanded(
            child: _scannedMaterials.isEmpty
                ? Center(
                    child: Text(
                      tr('no_scanned_materials'),
                      style: const TextStyle(color: Colors.white38),
                    ),
                  )
                : ListView.builder(
                    itemCount: _scannedMaterials.length,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemBuilder: (context, index) {
                      final material = _scannedMaterials[index];
                      return Dismissible(
                        key: Key(material['codigo_material_recibido']),
                        direction: DismissDirection.endToStart,
                        background: Container(
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 16),
                          color: Colors.red,
                          child: const Icon(Icons.delete, color: Colors.white),
                        ),
                        onDismissed: (_) => _removeMaterial(index),
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1A1E2C),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 28,
                                height: 28,
                                decoration: BoxDecoration(
                                  color: Colors.green.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: Center(
                                  child: Text(
                                    '${index + 1}',
                                    style: const TextStyle(
                                      color: Colors.green,
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      material['codigo_material_recibido'] ?? '',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 13,
                                        fontFamily: 'monospace',
                                      ),
                                    ),
                                    Text(
                                      '${material['numero_parte'] ?? ''} • ${material['cantidad'] ?? 0}',
                                      style: const TextStyle(
                                        color: Colors.white54,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                onPressed: () => _removeMaterial(index),
                                icon: const Icon(Icons.close, color: Colors.red, size: 18),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                              ),
                            ],
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

  Widget _buildConfirmButton() {
    final hasItems = _scannedMaterials.isNotEmpty;
    
    return Container(
      padding: const EdgeInsets.all(12),
      child: SizedBox(
        width: double.infinity,
        height: 56,
        child: ElevatedButton.icon(
          onPressed: hasItems && !_isSubmitting ? _confirmBatchOutgoing : null,
          icon: _isSubmitting
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Icon(Icons.check_circle, size: 24),
          label: Text(
            _isSubmitting 
                ? tr('processing_msg')
                : '${tr('confirm_outgoing')} (${_scannedMaterials.length})',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: hasItems ? Colors.green : Colors.grey,
            foregroundColor: Colors.white,
            disabledBackgroundColor: Colors.grey.shade700,
            disabledForegroundColor: Colors.white54,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      ),
    );
  }
}
