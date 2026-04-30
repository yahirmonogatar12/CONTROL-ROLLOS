import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:material_warehousing_flutter/core/localization/app_translations.dart';
import 'package:material_warehousing_flutter/core/services/api_service.dart';
import 'package:material_warehousing_flutter/core/services/auth_service.dart';
import 'package:material_warehousing_flutter/core/services/feedback_service.dart';
import 'package:material_warehousing_flutter/core/services/scanner_config_service.dart';
import 'package:material_warehousing_flutter/core/theme/app_colors.dart';

/// Pantalla de Retorno de Material para movil
/// Permite devolver material de linea de produccion al inventario de almacen
class MobileReturnScreen extends StatefulWidget {
  final LanguageProvider languageProvider;

  const MobileReturnScreen({
    super.key,
    required this.languageProvider,
  });

  @override
  State<MobileReturnScreen> createState() => _MobileReturnScreenState();
}

class _MobileReturnScreenState extends State<MobileReturnScreen> {
  // --- Scanner ---
  MobileScannerController? _scannerController;
  final TextEditingController _readerInputController = TextEditingController();
  final FocusNode _readerFocusNode = FocusNode();
  bool _isScanning = false;
  bool _isLoading = false;
  String? _detectedCode;
  bool _codeReady = false;
  String? _lastScannedCode;

  // --- Material info ---
  Map<String, dynamic>? _scannedMaterial;
  int? _warehousingId;
  String? _materialLotNo;

  // --- Form ---
  final TextEditingController _returnQtyController = TextEditingController();
  final TextEditingController _remarksController = TextEditingController();
  bool _isSubmitting = false;

  // --- Recent returns ---
  List<Map<String, dynamic>> _recentReturns = [];
  bool _isLoadingHistory = false;

  String tr(String key) => widget.languageProvider.tr(key);

  @override
  void initState() {
    super.initState();
    FeedbackService.init();
    _loadRecentReturns();
  }

  @override
  void dispose() {
    _scannerController?.dispose();
    _readerInputController.dispose();
    _readerFocusNode.dispose();
    _returnQtyController.dispose();
    _remarksController.dispose();
    super.dispose();
  }

  // ====================================================================
  // SCANNER
  // ====================================================================

  void _startScanner() {
    setState(() {
      _isScanning = true;
      _lastScannedCode = null;
      _scannedMaterial = null;
      _detectedCode = null;
      _codeReady = false;
      _returnQtyController.clear();
      _remarksController.clear();
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
    _lookupMaterial(code);
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
      _showMessage(tr('point_to_code'), isError: true);
      return;
    }

    setState(() => _lastScannedCode = _detectedCode);
    _stopScanner();
    _lookupMaterial(_lastScannedCode!);
  }

  // ====================================================================
  // MATERIAL LOOKUP
  // ====================================================================

  Future<void> _lookupMaterial(String code) async {
    setState(() {
      _isLoading = true;
      _scannedMaterial = null;
      _warehousingId = null;
      _materialLotNo = null;
      _returnQtyController.clear();
      _remarksController.clear();
    });

    try {
      final data = await ApiService.getWarehousingByCode(code, forReturn: true);

      if (!mounted) return;

      if (data != null) {
        await FeedbackService.vibrateSuccess();
        setState(() {
          _isLoading = false;
          _scannedMaterial = data;
          _warehousingId = data['id'];
          _materialLotNo = data['numero_lote_material']?.toString();
        });
        _showMessage(
          '${tr('part_number')}: ${data['numero_parte'] ?? code}',
          isError: false,
        );
      } else {
        await FeedbackService.vibrateError();
        setState(() => _isLoading = false);
        _showMessage(tr('warehousing_not_found'), isError: true);
      }
    } catch (e) {
      await FeedbackService.vibrateError();
      setState(() => _isLoading = false);
      _showMessage('Error: $e', isError: true);
    }
  }

  // ====================================================================
  // SAVE RETURN
  // ====================================================================

  Future<void> _saveReturn() async {
    if (_warehousingId == null || _scannedMaterial == null) {
      _showMessage(tr('scan_warehousing_code_first'), isError: true);
      return;
    }

    final returnQty = int.tryParse(_returnQtyController.text) ?? 0;
    final remainQty = int.tryParse(
      _scannedMaterial!['cantidad_actual']?.toString() ?? '0',
    ) ?? 0;

    if (returnQty <= 0) {
      _showMessage(tr('enter_valid_return_qty'), isError: true);
      return;
    }

    if (returnQty > remainQty) {
      _showMessage(tr('return_qty_exceeds_remain'), isError: true);
      return;
    }

    final confirm = await _showConfirmDialog(returnQty);
    if (confirm != true) return;

    setState(() => _isSubmitting = true);

    try {
      final data = {
        'warehousing_id': _warehousingId,
        'material_warehousing_code': _lastScannedCode,
        'material_code': _scannedMaterial!['codigo_material']?.toString() ?? '',
        'part_number': _scannedMaterial!['numero_parte']?.toString() ?? '',
        'material_lot_no': _materialLotNo,
        'packaging_unit': _scannedMaterial!['cantidad_estandarizada']?.toString() ?? '',
        'material_spec': _scannedMaterial!['especificacion']?.toString() ?? '',
        'remain_qty': remainQty,
        'return_qty': returnQty,
        'loss_qty': 0,
        'returned_by': AuthService.currentUser?.nombreCompleto ?? 'Unknown',
        'returned_by_id': AuthService.currentUser?.id,
        'remarks': _remarksController.text.trim().isEmpty
            ? null
            : _remarksController.text.trim(),
      };

      final result = await ApiService.createReturn(data);

      if (!mounted) return;

      if (result['success'] == true) {
        await FeedbackService.vibrateSuccess();
        _showMessage(tr('return_saved_successfully'), isError: false);
        _clearForm();
        _loadRecentReturns();
      } else {
        await FeedbackService.vibrateError();
        _showMessage(
          result['error']?.toString() ?? 'Error saving return',
          isError: true,
        );
      }
    } catch (e) {
      await FeedbackService.vibrateError();
      _showMessage('Error: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  void _clearForm() {
    setState(() {
      _scannedMaterial = null;
      _warehousingId = null;
      _materialLotNo = null;
      _lastScannedCode = null;
      _returnQtyController.clear();
      _remarksController.clear();
    });
  }

  // ====================================================================
  // RECENT RETURNS
  // ====================================================================

  Future<void> _loadRecentReturns() async {
    setState(() => _isLoadingHistory = true);
    try {
      final returns = await ApiService.searchReturns(
        fechaInicio: DateTime.now().subtract(const Duration(days: 1)),
        fechaFin: DateTime.now(),
      );
      if (mounted) {
        setState(() {
          _recentReturns = returns.take(20).toList();
          _isLoadingHistory = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingHistory = false);
    }
  }

  // ====================================================================
  // HELPERS
  // ====================================================================

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

  Future<bool?> _showConfirmDialog(int returnQty) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF252A3C),
        title: Text(
          tr('confirm_return'),
          style: const TextStyle(color: Colors.white),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${tr('code')}: ${_lastScannedCode ?? ''}',
              style: const TextStyle(color: Colors.white70),
            ),
            Text(
              '${tr('part_number')}: ${_scannedMaterial?['numero_parte'] ?? ''}',
              style: const TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 8),
            Text(
              '${tr('return_qty')}: $returnQty',
              style: const TextStyle(
                color: Colors.orange,
                fontWeight: FontWeight.bold,
                fontSize: 16,
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
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            onPressed: () => Navigator.pop(context, true),
            child: Text(tr('confirm')),
          ),
        ],
      ),
    );
  }

  String _formatDateTime(dynamic date) {
    if (date == null) return '-';
    try {
      final dt = DateTime.parse(date.toString());
      return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (e) {
      return date.toString();
    }
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
              _lookupMaterial(value);
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
                _lookupMaterial(value);
              }
            },
            child: Text(tr('search')),
          ),
        ],
      ),
    );
  }

  // ====================================================================
  // BUILD
  // ====================================================================

  @override
  Widget build(BuildContext context) {
    if (!AuthService.canWriteMaterialReturn) {
      return _buildNoPermissionScreen();
    }

    if (_isScanning) return _buildScanner();
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_scannedMaterial != null) return _buildReturnForm();
    return _buildMainView();
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

  // ====================================================================
  // MAIN VIEW: Scan prompt + Recent returns
  // ====================================================================

  Widget _buildMainView() {
    return Column(
      children: [
        _buildScanPromptCard(),
        // Recent returns header
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              const Icon(Icons.history, color: Colors.white54, size: 18),
              const SizedBox(width: 8),
              Text(
                tr('recent_returns'),
                style: const TextStyle(color: Colors.white54, fontSize: 14, fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.refresh, color: AppColors.headerTab, size: 20),
                onPressed: _loadRecentReturns,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
            ],
          ),
        ),
        Expanded(
          child: _isLoadingHistory
              ? const Center(child: CircularProgressIndicator())
              : _recentReturns.isEmpty
                  ? _buildEmptyReturns()
                  : RefreshIndicator(
                      onRefresh: _loadRecentReturns,
                      child: ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        itemCount: _recentReturns.length,
                        itemBuilder: (context, index) =>
                            _buildReturnCard(_recentReturns[index]),
                      ),
                    ),
        ),
      ],
    );
  }

  Widget _buildScanPromptCard() {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF252A3C),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.headerTab.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: Colors.orange.withOpacity(0.1),
              borderRadius: BorderRadius.circular(40),
            ),
            child: const Icon(
              Icons.assignment_return,
              size: 44,
              color: Colors.orange,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            tr('material_return'),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            tr('scan_to_return'),
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 13),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              onPressed: _startScanner,
              icon: const Icon(Icons.qr_code_scanner, size: 24),
              label: Text(tr('scan_material'), style: const TextStyle(fontSize: 16)),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.headerTab,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: _showManualCodeDialog,
            icon: const Icon(Icons.keyboard, size: 18),
            label: Text(tr('scan_or_enter_code')),
            style: TextButton.styleFrom(foregroundColor: Colors.white54),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyReturns() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.assignment_return, size: 48, color: Colors.white.withOpacity(0.15)),
          const SizedBox(height: 12),
          Text(
            tr('no_recent_returns'),
            style: const TextStyle(color: Colors.white38, fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildReturnCard(Map<String, dynamic> r) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF252A3C),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const Icon(Icons.assignment_return, color: Colors.orange, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  r['material_warehousing_code']?.toString() ?? '',
                  style: const TextStyle(color: Colors.white, fontSize: 12, fontFamily: 'monospace'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        r['part_number']?.toString() ?? '',
                        style: const TextStyle(color: Colors.white54, fontSize: 11),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Qty: ${r['return_qty'] ?? 0}',
                      style: const TextStyle(color: Colors.orange, fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                Text(
                  '${r['returned_by'] ?? ''} - ${_formatDateTime(r['return_datetime'])}',
                  style: const TextStyle(color: Colors.white38, fontSize: 10),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ====================================================================
  // SCANNER UI
  // ====================================================================

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

    // Modo camara
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
        // Instruccion
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
                  tr('scan_to_return'),
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
        // Boton capturar
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
        // Texto debajo del boton
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

  // ====================================================================
  // RETURN FORM
  // ====================================================================

  Widget _buildReturnForm() {
    final info = _scannedMaterial!;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header con codigo escaneado
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
                    const Icon(Icons.qr_code, color: Colors.orange),
                    const SizedBox(width: 8),
                    Text(tr('scanned_code'), style: const TextStyle(color: Colors.white54, fontSize: 12)),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.refresh, color: Colors.white54),
                      onPressed: _clearForm,
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
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Material info
          _buildInfoCard(tr('part_number'), info['numero_parte']?.toString() ?? '-'),
          _buildInfoCard(tr('description'), info['especificacion']?.toString() ?? '-'),
          _buildInfoCard(tr('material_code'), info['codigo_material']?.toString() ?? '-'),
          _buildInfoCard(tr('packaging_unit'), info['cantidad_estandarizada']?.toString() ?? '-'),
          _buildInfoCard(
            tr('remain_qty'),
            info['cantidad_actual']?.toString() ?? '0',
            valueColor: Colors.cyan,
          ),

          const SizedBox(height: 16),

          // Return qty
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF252A3C),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.orange.withOpacity(0.5)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.swap_vert, color: Colors.orange, size: 18),
                    const SizedBox(width: 8),
                    Text(
                      tr('return_qty'),
                      style: const TextStyle(color: Colors.orange, fontSize: 14, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _returnQtyController,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(color: Colors.orange, fontSize: 20, fontWeight: FontWeight.bold),
                  decoration: InputDecoration(
                    hintText: tr('enter_valid_return_qty'),
                    hintStyle: const TextStyle(color: Colors.white38, fontSize: 14),
                    filled: true,
                    fillColor: Colors.orange.withOpacity(0.1),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // Remarks
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF252A3C),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tr('reason_optional'),
                  style: const TextStyle(color: Colors.white70, fontSize: 14),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _remarksController,
                  maxLines: 2,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: tr('reason_optional'),
                    hintStyle: const TextStyle(color: Colors.white38),
                    filled: true,
                    fillColor: const Color(0xFF1A1E2C),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Confirm button
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton.icon(
              onPressed: _isSubmitting ? null : _saveReturn,
              icon: _isSubmitting
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.check_circle, size: 24),
              label: Text(
                _isSubmitting ? 'Procesando...' : tr('confirm_return'),
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

          // Scan another
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

  Widget _buildInfoCard(String label, String value, {Color? valueColor}) {
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
              style: TextStyle(
                color: valueColor ?? Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.right,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
