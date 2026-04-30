import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:material_warehousing_flutter/core/localization/app_translations.dart';
import 'package:material_warehousing_flutter/core/services/api_service.dart';
import 'package:material_warehousing_flutter/core/services/auth_service.dart';
import 'package:material_warehousing_flutter/core/services/feedback_service.dart';
import 'package:material_warehousing_flutter/core/services/scan_batcher.dart';
import 'package:material_warehousing_flutter/core/services/scanner_config_service.dart';
import 'package:material_warehousing_flutter/core/theme/app_colors.dart';

/// Pantalla de Reingreso para móvil
/// Permite reubicar materiales escaneando sus códigos
class MobileReentryScreen extends StatefulWidget {
  final LanguageProvider languageProvider;

  const MobileReentryScreen({
    super.key,
    required this.languageProvider,
  });

  @override
  State<MobileReentryScreen> createState() => _MobileReentryScreenState();
}

class _MobileReentryScreenState extends State<MobileReentryScreen> {
  // Scanner
  MobileScannerController? _scannerController;
  bool _isScannerActive = false;
  
  // Escáner externo
  final TextEditingController _scannerInputController = TextEditingController();
  final FocusNode _scannerFocusNode = FocusNode();
  
  // Nueva ubicación
  final TextEditingController _locationController = TextEditingController();
  
  // Lista de materiales escaneados
  final List<Map<String, dynamic>> _scannedMaterials = [];
  static const int _maxMaterials = 100;
  ScanBatcher<Map<String, dynamic>>? _reentryBatcher;
  
  // Control de escaneo
  String? _lastProcessedCode;
  
  // Estado
  bool _isProcessing = false;
  bool _isSubmitting = false;
  String? _statusMessage;
  bool _statusIsError = false;

  String tr(String key) => widget.languageProvider.tr(key);

  @override
  void initState() {
    super.initState();
    FeedbackService.init();
    if (ApiService.isSlowLinkAndroid) {
      _reentryBatcher = ScanBatcher<Map<String, dynamic>>(
        loader: (codes) async {
          final results = await ApiService.getReentryByCodes(codes);
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
    _reentryBatcher?.dispose();
    _scannerController?.dispose();
    _scannerInputController.dispose();
    _scannerFocusNode.dispose();
    _locationController.dispose();
    super.dispose();
  }

  void _startScanner() {
    if (_locationController.text.trim().isEmpty) {
      _showStatus(tr('enter_new_location_first'), isError: true);
      return;
    }
    
    if (ScannerConfigService.isReaderMode) {
      setState(() {
        _isScannerActive = true;
        _lastProcessedCode = null;
      });
      Future.delayed(const Duration(milliseconds: 100), () {
        _scannerFocusNode.requestFocus();
      });
      return;
    }
    
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

  void _stopScanner() {
    _scannerController?.stop();
    _scannerInputController.clear();
    setState(() {
      _isScannerActive = false;
    });
  }

  void _onBarcodeDetected(BarcodeCapture capture) {
    if (_isProcessing) return;
    if (capture.barcodes.isEmpty) return;
    
    final barcode = capture.barcodes.first;
    if (barcode.rawValue == null) return;
    
    final code = barcode.rawValue!.trim();
    
    // Evitar procesar el mismo código consecutivamente
    if (code == _lastProcessedCode) return;
    
    _processCode(code);
  }
  
  void _onReaderInput(String value) {
    if (value.isEmpty || _isProcessing) return;
    final code = value.trim();
    _scannerInputController.clear();
    _processCode(code);
    
    // Mantener foco
    Future.delayed(const Duration(milliseconds: 100), () {
      _scannerFocusNode.requestFocus();
    });
  }

  Future<void> _processCode(String code) async {
    // Verificar si ya está en la lista
    final exists = _scannedMaterials.any(
      (m) => m['codigo_material_recibido'] == code
    );
    if (exists) {
      // Ignorar duplicados silenciosamente
      return;
    }
    
    if (_scannedMaterials.length >= _maxMaterials) {
      await FeedbackService.vibrateError();
      _showStatus('${tr('max_items_reached')} $_maxMaterials', isError: true);
      return;
    }

    setState(() {
      _isProcessing = true;
      _lastProcessedCode = code;
    });

    try {
      final material = await _lookupReentryMaterial(code);
      
      if (material == null) {
        await FeedbackService.vibrateError();
        _showStatus('${tr('material_not_found')}: $code', isError: true);
      } else {
        await FeedbackService.vibrateSuccess();
        setState(() {
          _scannedMaterials.add(material);
        });
        _showStatus('✓ ${material['numero_parte']} - ${material['ubicacion_salida']}', isError: false);
      }
    } catch (e) {
      await FeedbackService.vibrateError();
      _showStatus('Error: $e', isError: true);
    } finally {
      setState(() {
        _isProcessing = false;
      });
    }
  }

  Future<Map<String, dynamic>?> _lookupReentryMaterial(String code) async {
    if (!ApiService.isSlowLinkAndroid || _reentryBatcher == null) {
      return ApiService.getReentryByCode(code);
    }

    final result = await _reentryBatcher!.enqueue(code);
    if (result == null || result['found'] != true) {
      return null;
    }

    return result['material'] as Map<String, dynamic>?;
  }

  void _removeMaterial(int index) {
    setState(() {
      _scannedMaterials.removeAt(index);
    });
  }

  void _clearAll() {
    setState(() {
      _scannedMaterials.clear();
      _statusMessage = null;
    });
  }

  Future<void> _confirmReentry() async {
    if (_scannedMaterials.isEmpty) {
      _showStatus(tr('no_materials_scanned'), isError: true);
      return;
    }
    
    final newLocation = _locationController.text.trim();
    if (newLocation.isEmpty) {
      _showStatus(tr('enter_new_location_first'), isError: true);
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    try {
      final ids = _scannedMaterials.map((m) => m['id'] as int).toList();
      final user = AuthService.currentUser;
      
      final result = await ApiService.bulkReentry(
        ids,
        newLocation,
        user?.nombreCompleto,
      );

      if (result['success'] == true) {
        await FeedbackService.vibrateSuccess();
        final count = result['successCount'] ?? ids.length;
        _showStatus('✓ $count ${tr('materials_relocated')}', isError: false);
        
        // Limpiar lista
        setState(() {
          _scannedMaterials.clear();
        });
      } else {
        await FeedbackService.vibrateError();
        _showStatus(result['error'] ?? tr('reentry_error'), isError: true);
      }
    } catch (e) {
      await FeedbackService.vibrateError();
      _showStatus('Error: $e', isError: true);
    } finally {
      setState(() {
        _isSubmitting = false;
      });
    }
  }

  void _showStatus(String message, {bool isError = false}) {
    setState(() {
      _statusMessage = message;
      _statusIsError = isError;
    });
    
    // Auto-limpiar después de unos segundos
    Future.delayed(Duration(seconds: isError ? 4 : 3), () {
      if (mounted && _statusMessage == message) {
        setState(() {
          _statusMessage = null;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Campo de nueva ubicación
        _buildLocationField(),
        
        // Mensaje de estado
        if (_statusMessage != null)
          _buildStatusMessage(),
        
        // Scanner o lista de materiales
        Expanded(
          child: _isScannerActive
              ? _buildScanner()
              : _buildMaterialsList(),
        ),
        
        // Botones de acción
        if (!_isScannerActive)
          _buildActionButtons(),
      ],
    );
  }

  Widget _buildLocationField() {
    return Container(
      padding: const EdgeInsets.all(16),
      color: const Color(0xFF252A3C),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.location_on, color: AppColors.headerTab, size: 20),
              const SizedBox(width: 8),
              Text(
                tr('new_location'),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _locationController,
            style: const TextStyle(color: Colors.white, fontSize: 16),
            decoration: InputDecoration(
              hintText: tr('enter_new_location'),
              hintStyle: const TextStyle(color: Colors.white38),
              filled: true,
              fillColor: const Color(0xFF1A1E2C),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              suffixIcon: _locationController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, color: Colors.white54),
                      onPressed: () {
                        _locationController.clear();
                        setState(() {});
                      },
                    )
                  : null,
            ),
            onChanged: (_) => setState(() {}),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusMessage() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: _statusIsError ? Colors.red.withOpacity(0.2) : Colors.green.withOpacity(0.2),
      child: Row(
        children: [
          Icon(
            _statusIsError ? Icons.error_outline : Icons.check_circle_outline,
            color: _statusIsError ? Colors.red : Colors.green,
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _statusMessage!,
              style: TextStyle(
                color: _statusIsError ? Colors.red : Colors.green,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScanner() {
    if (ScannerConfigService.isReaderMode) {
      return Container(
        color: AppColors.panelBackground,
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
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              '${tr('new_location')}: ${_locationController.text}',
              style: const TextStyle(color: AppColors.headerTab, fontSize: 14),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _scannerInputController,
              focusNode: _scannerFocusNode,
              autofocus: true,
              style: const TextStyle(color: Colors.white, fontSize: 18),
              decoration: InputDecoration(
                labelText: tr('scanned_code'),
                prefixIcon: const Icon(Icons.qr_code_scanner, color: Colors.white54),
                border: const OutlineInputBorder(),
                filled: true,
                fillColor: AppColors.fieldBackground,
              ),
              onSubmitted: _onReaderInput,
            ),
            const SizedBox(height: 16),
            Text(
              '${_scannedMaterials.length} ${tr('materials_scanned')}',
              style: const TextStyle(color: Colors.white54),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _stopScanner,
              icon: const Icon(Icons.check),
              label: Text(tr('done_scanning')),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.headerTab,
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
        Center(
          child: Container(
            width: 280,
            height: 180,
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.headerTab, width: 3),
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        // Info de ubicación destino
        Positioned(
          top: 16,
          left: 16,
          right: 16,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.7),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                const Icon(Icons.location_on, color: AppColors.headerTab, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${tr('relocating_to')}: ${_locationController.text}',
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                  ),
                ),
              ],
            ),
          ),
        ),
        // Contador
        Positioned(
          top: 80,
          right: 16,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.7),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              '${_scannedMaterials.length}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
        // Botones
        Positioned(
          bottom: 32,
          left: 0,
          right: 0,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              IconButton(
                onPressed: () => _scannerController?.toggleTorch(),
                icon: const Icon(Icons.flash_auto, color: Colors.white, size: 32),
              ),
              ElevatedButton.icon(
                onPressed: _stopScanner,
                icon: const Icon(Icons.check),
                label: Text(tr('done_scanning')),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.headerTab,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                ),
              ),
              IconButton(
                onPressed: () => _scannerController?.switchCamera(),
                icon: const Icon(Icons.cameraswitch, color: Colors.white, size: 32),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMaterialsList() {
    if (_scannedMaterials.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.move_to_inbox,
              size: 80,
              color: Colors.white.withOpacity(0.2),
            ),
            const SizedBox(height: 16),
            Text(
              tr('no_materials_to_relocate'),
              style: const TextStyle(color: Colors.white54, fontSize: 16),
            ),
            const SizedBox(height: 8),
            Text(
              tr('scan_to_add'),
              style: const TextStyle(color: Colors.white38, fontSize: 14),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        // Header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          color: const Color(0xFF252A3C),
          child: Row(
            children: [
              const Icon(Icons.inventory_2, color: AppColors.headerTab, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${_scannedMaterials.length} ${tr('materials_to_relocate')}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              TextButton.icon(
                onPressed: _clearAll,
                icon: const Icon(Icons.clear_all, size: 18),
                label: Text(tr('clear_all')),
                style: TextButton.styleFrom(
                  foregroundColor: Colors.red,
                ),
              ),
            ],
          ),
        ),
        // Lista
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(8),
            itemCount: _scannedMaterials.length,
            itemBuilder: (context, index) {
              final material = _scannedMaterials[index];
              return Card(
                color: const Color(0xFF252A3C),
                margin: const EdgeInsets.symmetric(vertical: 4),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
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
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${material['numero_parte'] ?? ''} • ${material['cantidad_actual'] ?? 0}',
                              style: const TextStyle(
                                color: Colors.white54,
                                fontSize: 12,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Row(
                              children: [
                                const Icon(Icons.location_on, size: 12, color: Colors.orange),
                                const SizedBox(width: 4),
                                Flexible(
                                  child: Text(
                                    material['ubicacion_salida'] ?? '-',
                                    style: const TextStyle(
                                      color: Colors.orange,
                                      fontSize: 11,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                const Icon(Icons.arrow_forward, size: 12, color: Colors.green),
                                const SizedBox(width: 4),
                                Flexible(
                                  child: Text(
                                    _locationController.text,
                                    style: const TextStyle(
                                      color: Colors.green,
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => _removeMaterial(index),
                        icon: const Icon(Icons.close, color: Colors.red, size: 20),
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
    );
  }

  Widget _buildActionButtons() {
    final hasLocation = _locationController.text.trim().isNotEmpty;
    final hasMaterials = _scannedMaterials.isNotEmpty;

    return Container(
      padding: const EdgeInsets.all(16),
      color: const Color(0xFF252A3C),
      child: Column(
        children: [
          // Botón de escanear
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton.icon(
              onPressed: hasLocation && !_isSubmitting ? _startScanner : null,
              icon: const Icon(Icons.qr_code_scanner),
              label: Text(tr('scan_materials')),
              style: ElevatedButton.styleFrom(
                backgroundColor: hasLocation ? AppColors.headerTab : Colors.grey,
                foregroundColor: Colors.white,
              ),
            ),
          ),
          const SizedBox(height: 12),
          // Botón de confirmar
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton.icon(
              onPressed: hasMaterials && hasLocation && !_isSubmitting
                  ? _confirmReentry
                  : null,
              icon: _isSubmitting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.check_circle),
              label: Text(
                _isSubmitting ? tr('processing') : tr('confirm_reentry'),
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: hasMaterials ? Colors.green : Colors.grey,
                foregroundColor: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
