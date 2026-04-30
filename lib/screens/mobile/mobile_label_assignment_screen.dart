import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:material_warehousing_flutter/core/localization/app_translations.dart';
import 'package:material_warehousing_flutter/core/services/api_service.dart';
import 'package:material_warehousing_flutter/core/services/auth_service.dart';
import 'package:material_warehousing_flutter/core/services/mobile_printer_service.dart';
import 'package:material_warehousing_flutter/core/services/printer_service.dart';
import 'package:material_warehousing_flutter/core/services/scanner_config_service.dart';
import 'package:material_warehousing_flutter/core/theme/app_colors.dart';
import 'package:material_warehousing_flutter/core/widgets/mobile_printer_settings_dialog.dart';

/// Estado de una etiqueta en el proceso de asignación
enum LabelStatus { pending, printed, assigned, error }

/// Modelo de etiqueta con su estado
class LabelEntry {
  final String code;
  final int quantity;
  String? supplierLot;
  LabelStatus status;
  String? errorMessage;

  LabelEntry({
    required this.code,
    required this.quantity,
    this.supplierLot,
    this.status = LabelStatus.pending,
    this.errorMessage,
  });
}

/// Pantalla de asignación de etiquetas para móvil
/// Flujo: Generar códigos → Imprimir → Escanear para asignar lote proveedor → Guardar
/// Si assignInternalLot=true: Solo imprimir y guardar (lote interno automático)
class MobileLabelAssignmentScreen extends StatefulWidget {
  final LanguageProvider languageProvider;
  final Map<String, dynamic> materialInfo;
  final Map<String, dynamic> catalogMaterial;
  final int cantidad;
  final int cantidadEtiquetas;
  final bool assignInternalLot;
  final String cliente;

  const MobileLabelAssignmentScreen({
    super.key,
    required this.languageProvider,
    required this.materialInfo,
    required this.catalogMaterial,
    required this.cantidad,
    required this.cantidadEtiquetas,
    this.assignInternalLot = false,
    this.cliente = 'REFRIS',
  });

  @override
  State<MobileLabelAssignmentScreen> createState() => _MobileLabelAssignmentScreenState();
}

class _MobileLabelAssignmentScreenState extends State<MobileLabelAssignmentScreen> {
  MobileScannerController? _scannerController;
  
  // Para modo lector/PDA
  final TextEditingController _readerInputController = TextEditingController();
  final FocusNode _readerFocusNode = FocusNode();
  
  List<LabelEntry> _labels = [];
  bool _isLoading = true;
  bool _isPrinting = false;
  bool _isScanning = false;
  bool _isSaving = false;
  
  // Para el flujo de escaneo rápido
  // Paso 1: Escanear etiqueta impresa → Paso 2: Escanear lote proveedor
  int? _currentAssigningIndex;
  bool _waitingForSupplierLot = false;  // true = esperando lote proveedor
  
  // Para el modo de captura manual
  String? _detectedCode;  // Código detectado pero no confirmado
  bool _codeReady = false;  // true cuando hay código listo para capturar
  
  // Modo Multi-Lote: escanear varios QRs y asignar UN lote a todos
  bool _multiLotMode = false;
  final Set<int> _selectedForMultiLot = {};  // Índices de etiquetas seleccionadas
  final TextEditingController _multiLotController = TextEditingController();
  
  // Modo selección manual (sin escaneo)
  bool _manualSelectMode = false;
  
  String tr(String key) => widget.languageProvider.tr(key);

  @override
  void initState() {
    super.initState();
    _generateLabels();
  }

  @override
  void dispose() {
    _scannerController?.dispose();
    _multiLotController.dispose();
    _readerInputController.dispose();
    _readerFocusNode.dispose();
    super.dispose();
  }

  /// Generar los códigos de etiqueta
  Future<void> _generateLabels() async {
    setState(() => _isLoading = true);

    try {
      final partNumber = widget.catalogMaterial['numero_parte']?.toString() ?? 
                         widget.materialInfo['numero_parte']?.toString() ?? '';
      
      if (partNumber.isEmpty) {
        _showError('No se encontró el número de parte');
        return;
      }

      final now = DateTime.now();
      final dateStr = '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
      
      // Obtener la siguiente secuencia del servidor
      final result = await ApiService.getNextSequence(partNumber, dateStr);
      int nextSeq = result['nextSequence'] as int? ?? 1;

      // Generar las etiquetas
      final labels = <LabelEntry>[];
      final qtyPerLabel = widget.cantidad;
      
      for (int i = 0; i < widget.cantidadEtiquetas; i++) {
        final seq = (nextSeq + i).toString().padLeft(4, '0');
        final code = '$partNumber-$dateStr$seq';
        labels.add(LabelEntry(
          code: code,
          quantity: qtyPerLabel,
        ));
      }

      setState(() {
        _labels = labels;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      _showError('Error generando etiquetas: $e');
    }
  }

  /// Imprimir todas las etiquetas
  Future<void> _printAllLabels() async {
    if (!MobilePrinterService.isConfigured) {
      _showPrinterConfigDialog();
      return;
    }

    setState(() => _isPrinting = true);

    final now = DateTime.now();
    final fecha = '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year}';
    final especificacion = widget.catalogMaterial['especificacion_material']?.toString() ??
                           widget.materialInfo['especificacion']?.toString() ?? '';

    int successCount = 0;
    int errorCount = 0;

    for (int i = 0; i < _labels.length; i++) {
      final label = _labels[i];
      
      // Generar ZPL - usar el mismo que PC
      final zpl = PrinterService.generateLabelZPL(
        codigo: label.code,
        fecha: fecha,
        especificacion: especificacion,
        cantidadActual: label.quantity.toString(),
      );

      // Imprimir
      final result = await MobilePrinterService.printLabel(zpl);
      
      // MSL Mirror Label: Si el material tiene nivel_msl >= 1, imprimir copia
      if (result.success) {
        final nivelMsl = int.tryParse(widget.catalogMaterial['nivel_msl']?.toString() ?? '') ?? 0;
        if (nivelMsl >= 1) {
          await Future.delayed(const Duration(milliseconds: 300));
          await MobilePrinterService.printLabel(zpl); // Copia MSL
        }
      }

      setState(() {
        if (result.success) {
          _labels[i].status = LabelStatus.printed;
          successCount++;
        } else {
          _labels[i].status = LabelStatus.error;
          _labels[i].errorMessage = result.error;
          errorCount++;
        }
      });

      // Pequeña pausa entre impresiones
      if (i < _labels.length - 1) {
        await Future.delayed(const Duration(milliseconds: 300));
      }
    }

    setState(() => _isPrinting = false);

    if (errorCount > 0) {
      _showMessage('$successCount impresas, $errorCount con error', isError: true);
    } else {
      _showMessage('✓ $successCount etiquetas impresas', isError: false);
      
      // Si tiene lote interno asignado, generar automáticamente
      if (widget.assignInternalLot && successCount > 0) {
        await _autoAssignInternalLot();
      }
    }
  }

  /// Generar y asignar lote interno automáticamente (cuando assignInternalLot=true)
  Future<void> _autoAssignInternalLot() async {
    setState(() => _isSaving = true);
    
    try {
      // Obtener siguiente secuencia de lote interno
      final result = await ApiService.getNextInternalLotSequence();
      final nextSeq = result['nextSequence'] as int? ?? 1;
      
      // Formato: DD/MM/YYYY/00001
      final now = DateTime.now();
      final dateStr = '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year}';
      final internalLot = '$dateStr/${nextSeq.toString().padLeft(5, '0')}';
      
      // Asignar el mismo lote interno a todas las etiquetas impresas
      for (int i = 0; i < _labels.length; i++) {
        if (_labels[i].status == LabelStatus.printed) {
          setState(() {
            _labels[i].supplierLot = internalLot;
            _labels[i].status = LabelStatus.assigned;
          });
        }
      }
      
      _showMessage('✓ Lote interno asignado: $internalLot', isError: false);
    } catch (e) {
      _showMessage('Error generando lote interno: $e', isError: true);
    } finally {
      setState(() => _isSaving = false);
    }
  }

  /// Reintentar impresión de una etiqueta específica
  Future<void> _retryPrint(int index) async {
    final label = _labels[index];
    
    final now = DateTime.now();
    final fecha = '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year}';
    final especificacion = widget.catalogMaterial['especificacion_material']?.toString() ??
                           widget.materialInfo['especificacion']?.toString() ?? '';

    setState(() {
      _labels[index].status = LabelStatus.pending;
      _labels[index].errorMessage = null;
    });

    // Generar ZPL - usar el mismo que PC
    final zpl = PrinterService.generateLabelZPL(
      codigo: label.code,
      fecha: fecha,
      especificacion: especificacion,
      cantidadActual: label.quantity.toString(),
    );

    final result = await MobilePrinterService.printLabel(zpl);
    
    // MSL Mirror Label: Si el material tiene nivel_msl >= 1, imprimir copia
    if (result.success) {
      final nivelMsl = int.tryParse(widget.catalogMaterial['nivel_msl']?.toString() ?? '') ?? 0;
      if (nivelMsl >= 1) {
        await Future.delayed(const Duration(milliseconds: 300));
        await MobilePrinterService.printLabel(zpl); // Copia MSL
      }
    }

    setState(() {
      if (result.success) {
        _labels[index].status = LabelStatus.printed;
        _showMessage('✓ Etiqueta impresa', isError: false);
      } else {
        _labels[index].status = LabelStatus.error;
        _labels[index].errorMessage = result.error;
        _showMessage('Error: ${result.error}', isError: true);
      }
    });
  }

  /// Iniciar escaneo para asignar lote (flujo rápido)
  /// Si no hay índice, espera escanear etiqueta primero, luego lote proveedor
  void _startAssignmentScan([int? labelIndex]) {
    setState(() {
      _isScanning = true;
      _currentAssigningIndex = labelIndex;
      _waitingForSupplierLot = labelIndex != null;
      _detectedCode = null;
      _codeReady = false;
    });
    
    // Modo lector/PDA - enfocar campo de texto
    if (ScannerConfigService.isReaderMode) {
      Future.delayed(const Duration(milliseconds: 100), () {
        if (mounted) _readerFocusNode.requestFocus();
      });
      return;
    }
    
    // Modo cámara - crear controlador
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
      _currentAssigningIndex = null;
      _waitingForSupplierLot = false;
      _detectedCode = null;
      _codeReady = false;
      // NO limpiar selección multi-lote al cerrar escáner
      // para que pueda seguir editando sin escanear
    });
  }
  
  /// Procesar input del lector/PDA
  void _onReaderInput(String value) {
    if (value.isEmpty) return;
    final code = value.trim();
    _readerInputController.clear();
    
    // Simular detección de código
    setState(() {
      _detectedCode = code;
      _codeReady = true;
    });
    
    // Auto-confirmar para flujo rápido
    _confirmScan();
    
    // Mantener foco para siguiente escaneo
    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted && _isScanning) _readerFocusNode.requestFocus();
    });
  }
  
  /// Desasignar lote de una etiqueta
  void _unassignLot(int index) {
    setState(() {
      _labels[index].supplierLot = null;
      _labels[index].status = LabelStatus.printed;
    });
    _showMessage('Lote desasignado. Puede asignar uno nuevo.', isError: false);
  }
  
  /// Toggle selección manual de una etiqueta (sin escaneo)
  void _toggleManualSelect(int index) {
    if (_labels[index].status != LabelStatus.printed) return;
    
    setState(() {
      if (_selectedForMultiLot.contains(index)) {
        _selectedForMultiLot.remove(index);
      } else {
        _selectedForMultiLot.add(index);
      }
    });
  }
  
  /// Seleccionar/deseleccionar todas las etiquetas impresas
  void _toggleSelectAll() {
    final printedIndices = <int>[];
    for (int i = 0; i < _labels.length; i++) {
      if (_labels[i].status == LabelStatus.printed) {
        printedIndices.add(i);
      }
    }
    
    setState(() {
      if (_selectedForMultiLot.length == printedIndices.length) {
        // Deseleccionar todas
        _selectedForMultiLot.clear();
      } else {
        // Seleccionar todas las impresas
        _selectedForMultiLot.clear();
        _selectedForMultiLot.addAll(printedIndices);
      }
    });
  }
  
  /// Toggle modo multi-lote
  void _toggleMultiLotMode(bool value) {
    setState(() {
      _multiLotMode = value;
      _selectedForMultiLot.clear();
      _multiLotController.clear();
      // Si activamos multi-lote, no esperamos lote proveedor individual
      if (_multiLotMode) {
        _waitingForSupplierLot = false;
        _currentAssigningIndex = null;
      }
    });
  }
  
  /// Asignar el lote del campo de texto a todas las etiquetas seleccionadas
  void _applyMultiLot() {
    final lot = _multiLotController.text.trim();
    if (lot.isEmpty) {
      _showError('Ingrese un número de lote');
      return;
    }
    
    if (_selectedForMultiLot.isEmpty) {
      _showError('No hay etiquetas seleccionadas');
      return;
    }
    
    final count = _selectedForMultiLot.length;
    
    setState(() {
      for (final index in _selectedForMultiLot) {
        _labels[index].supplierLot = lot;
        _labels[index].status = LabelStatus.assigned;
      }
      _selectedForMultiLot.clear();
      _multiLotController.clear();
    });
    
    _showMessage('✓ Lote "$lot" asignado a $count etiquetas', isError: false);
    
    // Verificar si todas fueron asignadas
    final pendingPrinted = _labels.where((l) => l.status == LabelStatus.printed).length;
    if (pendingPrinted == 0) {
      // Desactivar modo selección manual si estaba activo
      setState(() {
        _manualSelectMode = false;
      });
      if (_isScanning) {
        _stopScanner();
      }
      _showMessage('✓ ¡Todas las etiquetas asignadas! Puede guardar.', isError: false);
    }
  }

  // Detecta el código pero NO lo procesa - solo lo muestra
  void _onBarcodeDetected(BarcodeCapture capture) {
    if (capture.barcodes.isEmpty) return;
    
    final barcode = capture.barcodes.first;
    if (barcode.rawValue == null) return;

    final scannedCode = barcode.rawValue!;
    
    // Solo actualizar el código detectado, no procesar
    if (_detectedCode != scannedCode) {
      setState(() {
        _detectedCode = scannedCode;
        _codeReady = true;
      });
    }
  }

  // Confirmar y procesar el código detectado
  void _confirmScan() {
    if (_detectedCode == null || !_codeReady) {
      _showMessage('Apunte al código y espere a que se detecte', isError: true);
      return;
    }

    final scannedCode = _detectedCode!;
    
    // MODO MULTI-LOTE: Solo agregar etiquetas a la lista de selección
    if (_multiLotMode) {
      final matchingIndex = _labels.indexWhere(
        (l) => l.code == scannedCode && l.status == LabelStatus.printed
      );
      
      if (matchingIndex >= 0) {
        if (_selectedForMultiLot.contains(matchingIndex)) {
          // Ya está seleccionada, quitarla
          setState(() {
            _selectedForMultiLot.remove(matchingIndex);
            _detectedCode = null;
            _codeReady = false;
          });
          _showMessage('Etiqueta removida. Seleccionadas: ${_selectedForMultiLot.length}', isError: false);
        } else {
          // Agregar a selección
          setState(() {
            _selectedForMultiLot.add(matchingIndex);
            _detectedCode = null;
            _codeReady = false;
          });
          _showMessage('✓ Etiqueta agregada. Seleccionadas: ${_selectedForMultiLot.length}', isError: false);
        }
      } else {
        // Ya fue asignada o no existe
        final alreadyAssigned = _labels.indexWhere(
          (l) => l.code == scannedCode && l.status == LabelStatus.assigned
        );
        if (alreadyAssigned >= 0) {
          _showMessage('Esta etiqueta ya tiene lote asignado', isError: true);
        } else {
          _showMessage('Código no reconocido', isError: true);
        }
        setState(() {
          _detectedCode = null;
          _codeReady = false;
        });
      }
      return;
    }
    
    // FLUJO NORMAL:
    // Paso 1: Si no estamos esperando lote, buscar si es una etiqueta impresa
    if (!_waitingForSupplierLot) {
      final matchingIndex = _labels.indexWhere(
        (l) => l.code == scannedCode && l.status == LabelStatus.printed
      );
      
      if (matchingIndex >= 0) {
        // Encontró etiqueta impresa, ahora esperar lote proveedor
        setState(() {
          _currentAssigningIndex = matchingIndex;
          _waitingForSupplierLot = true;
          _detectedCode = null;
          _codeReady = false;
        });
        _showMessage('✓ Etiqueta confirmada. Ahora escanee el LOTE DEL PROVEEDOR', isError: false);
      } else {
        // No es una etiqueta nuestra
        setState(() {
          _detectedCode = null;
          _codeReady = false;
        });
        _showMessage('Código no reconocido. Escanee una etiqueta impresa.', isError: true);
      }
    } else {
      // Paso 2: Estamos esperando el lote del proveedor
      if (_currentAssigningIndex != null) {
        // Verificar que no sea la misma etiqueta
        if (scannedCode == _labels[_currentAssigningIndex!].code) {
          setState(() {
            _detectedCode = null;
            _codeReady = false;
          });
          _showMessage('Ese es el código de la etiqueta. Escanee el LOTE DEL PROVEEDOR.', isError: true);
          return;
        }
        
        // Asignar el lote
        _assignSupplierLot(_currentAssigningIndex!, scannedCode);
      }
    }
  }

  void _assignSupplierLot(int index, String lot) {
    setState(() {
      _labels[index].supplierLot = lot;
      _labels[index].status = LabelStatus.assigned;
      _currentAssigningIndex = null;
      _waitingForSupplierLot = false;
      _detectedCode = null;
      _codeReady = false;
    });

    _showMessage('✓ Asignado: ${_labels[index].code} → Lote: $lot', isError: false);
    
    // Verificar si hay más etiquetas por asignar
    final pendingPrinted = _labels.where((l) => l.status == LabelStatus.printed).length;
    if (pendingPrinted > 0) {
      _showMessage('✓ Lote asignado. Quedan $pendingPrinted por asignar.', isError: false);
    } else {
      // Todas asignadas, detener scanner
      _stopScanner();
      _showMessage('✓ ¡Todas las etiquetas asignadas! Puede guardar.', isError: false);
    }
  }

  /// Guardar todas las entradas en inventario
  Future<void> _saveToInventory({bool partial = false}) async {
    final assignedLabels = _labels.where((l) => l.status == LabelStatus.assigned).toList();
    
    if (assignedLabels.isEmpty) {
      _showError('No hay etiquetas asignadas para guardar');
      return;
    }

    if (!partial && assignedLabels.length < _labels.length) {
      // Mostrar confirmación para guardado parcial
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: const Color(0xFF252A3C),
          title: const Text('Etiquetas sin asignar', style: TextStyle(color: Colors.white)),
          content: Text(
            'Hay ${_labels.length - assignedLabels.length} etiquetas sin lote asignado. ¿Desea guardar solo las asignadas?',
            style: const TextStyle(color: Colors.white70),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
              child: const Text('Guardar Parcial'),
            ),
          ],
        ),
      );

      if (confirmed != true) return;
    }

    setState(() => _isSaving = true);

    int savedCount = 0;
    int errorCount = 0;
    final now = DateTime.now();

    for (final label in assignedLabels) {
      final data = {
        'forma_material': 'OriginCode',
        'cliente': 'LGEMN',
        'codigo_material_original': widget.materialInfo['codigo_material_original'] ?? '',
        'codigo_material': widget.catalogMaterial['codigo_material'] ?? 
                           widget.materialInfo['codigo_material'] ?? '',
        'material_importacion_local': 'Local',
        'fecha_recibo': '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')} ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}',
        'fecha_fabricacion': '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}',
        'cantidad_actual': label.quantity,
        'numero_lote_material': label.supplierLot,
        'codigo_material_recibido': label.code,
        'numero_parte': widget.catalogMaterial['numero_parte'] ?? 
                        widget.materialInfo['numero_parte'] ?? '',
        'cantidad_estandarizada': widget.catalogMaterial['unidad_empaque']?.toString() ?? 
                                  widget.materialInfo['cantidad_estandarizada']?.toString() ?? '',
        'codigo_material_final': widget.catalogMaterial['codigo_material'] ?? 
                                 widget.materialInfo['codigo_material'] ?? '',
        'propiedad_material': 'Customer Supply',
        'especificacion': widget.catalogMaterial['especificacion_material'] ?? 
                          widget.materialInfo['especificacion'] ?? '',
        'material_importacion_local_final': 'Local',
        'estado_desecho': 0,
        'ubicacion_salida': widget.materialInfo['ubicacion_salida'] ?? 
                            widget.catalogMaterial['ubicacion_material'] ?? '',
        'vendedor': widget.materialInfo['vendedor'] ?? 
                    widget.catalogMaterial['vendedor'] ?? '',
        'usuario_registro': AuthService.currentUser?.nombreCompleto ?? 'Móvil',
        'unidad_medida': widget.catalogMaterial['unidad_medida'] ?? 
                         widget.materialInfo['unidad_medida'] ?? 'EA',
      };

      final result = await ApiService.createWarehousing(data);
      if (result['success'] == true) {
        savedCount++;
      } else {
        errorCount++;
      }
    }

    setState(() => _isSaving = false);
    if (errorCount > 0) {
      _showMessage('$savedCount guardados, $errorCount con error', isError: true);
    } else {
      _showMessage('✓ $savedCount registros guardados', isError: false);
      // Regresar a la pantalla anterior
      if (mounted) {
        Navigator.pop(context, true);
      }
    }
  }

  void _showPrinterConfigDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF252A3C),
        title: Row(
          children: [
            const Icon(Icons.print_disabled, color: Colors.orange),
            const SizedBox(width: 12),
            Text(tr('printer_not_configured'), style: const TextStyle(color: Colors.white)),
          ],
        ),
        content: Text(
          tr('configure_printer_continue'),
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(tr('cancel')),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              MobilePrinterSettingsDialog.show(context, widget.languageProvider);
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.headerTab),
            child: Text(tr('configure_printer')),
          ),
        ],
      ),
    );
  }

  void _showMessage(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showError(String message) {
    _showMessage(message, isError: true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A1E2C),
      appBar: AppBar(
        backgroundColor: const Color(0xFF252A3C),
        title: Text(tr('assign_labels'), style: const TextStyle(color: Colors.white)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: Icon(
              Icons.print,
              color: MobilePrinterService.isConfigured ? Colors.green : Colors.orange,
            ),
            onPressed: () => MobilePrinterSettingsDialog.show(context, widget.languageProvider),
            tooltip: tr('configure_printer'),
          ),
        ],
      ),
      body: _isScanning 
          ? _buildScanner()
          : _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _buildContent(),
    );
  }

  Widget _buildScanner() {
    final pendingCount = _labels.where((l) => l.status == LabelStatus.printed).length;
    final assignedCount = _labels.where((l) => l.status == LabelStatus.assigned).length;
    
    // Modo lector/PDA - mostrar campo de texto
    if (ScannerConfigService.isReaderMode) {
      return _buildReaderModeScanner(pendingCount, assignedCount);
    }
    
    // Modo cámara
    return Stack(
      children: [
        MobileScanner(
          controller: _scannerController!,
          onDetect: _onBarcodeDetected,
        ),
        // Overlay - cambia de color según estado
        Center(
          child: Container(
            width: 280,
            height: 180,
            decoration: BoxDecoration(
              border: Border.all(
                color: _codeReady 
                    ? Colors.green 
                    : (_waitingForSupplierLot ? Colors.orange : AppColors.headerTab), 
                width: _codeReady ? 4 : 3,
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: _codeReady 
                ? Center(
                    child: Icon(
                      Icons.check_circle,
                      color: Colors.green.withOpacity(0.8),
                      size: 48,
                    ),
                  )
                : null,
          ),
        ),
        // Instrucción y estado (arriba)
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
                // Toggle Multi-Lote (compacto para cámara)
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.layers,
                      color: _multiLotMode ? Colors.purple : Colors.white54,
                      size: 16,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Multi-Lote',
                      style: TextStyle(
                        color: _multiLotMode ? Colors.purple : Colors.white70,
                        fontSize: 11,
                      ),
                    ),
                    Switch(
                      value: _multiLotMode,
                      onChanged: _toggleMultiLotMode,
                      activeColor: Colors.purple,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                
                // Contenido según modo
                if (_multiLotMode) ...[
                  // Modo Multi-Lote
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.purple,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${_selectedForMultiLot.length} seleccionadas',
                      style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Escanea etiquetas para seleccionar',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                  ),
                ] else ...[
                  // Modo Normal - Paso actual
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: _waitingForSupplierLot ? Colors.orange : AppColors.headerTab,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          _waitingForSupplierLot ? tr('step_2') : tr('step_1'),
                          style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // Instrucción principal
                  Text(
                    _waitingForSupplierLot
                        ? tr('point_to_supplier_lot')
                        : tr('point_to_printed_label'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  // Etiqueta actual si está en paso 2
                  if (_waitingForSupplierLot && _currentAssigningIndex != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      '${tr('for_label')}: ${_labels[_currentAssigningIndex!].code}',
                      style: const TextStyle(color: Colors.orange, fontSize: 11),
                    ),
                  ],
                ],
                const SizedBox(height: 8),
                // Código detectado
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: _codeReady ? Colors.green.withOpacity(0.2) : Colors.white.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: _codeReady ? Colors.green : Colors.white24,
                    ),
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
                          _codeReady 
                              ? _detectedCode!
                              : tr('waiting_for_code'),
                          style: TextStyle(
                            color: _codeReady ? Colors.green : Colors.white54,
                            fontSize: 13,
                            fontWeight: _codeReady ? FontWeight.bold : FontWeight.normal,
                            fontFamily: 'monospace',
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                // Contador
                Text(
                  '${tr('assigned_status')}: $assignedCount / ${_labels.length} | ${tr('pending')}: $pendingCount',
                  style: const TextStyle(color: Colors.white70, fontSize: 11),
                ),
              ],
            ),
          ),
        ),
        // BOTÓN GRANDE DE CAPTURAR (centro-abajo)
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
                  color: _codeReady 
                      ? Colors.green 
                      : Colors.white.withOpacity(0.3),
                  border: Border.all(
                    color: _codeReady ? Colors.green.shade300 : Colors.white54,
                    width: 4,
                  ),
                  boxShadow: _codeReady ? [
                    BoxShadow(
                      color: Colors.green.withOpacity(0.5),
                      blurRadius: 20,
                      spreadRadius: 2,
                    ),
                  ] : null,
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
            _codeReady ? '¡Presione para confirmar!' : 'Apunte al código',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: _codeReady ? Colors.green : Colors.white70,
              fontSize: 13,
              fontWeight: _codeReady ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
        // Botones inferiores (flash, cerrar, cámara)
        Positioned(
          bottom: 16,
          left: 0,
          right: 0,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              // Flash
              IconButton(
                onPressed: () => _scannerController?.toggleTorch(),
                icon: const Icon(Icons.flash_auto, color: Colors.white, size: 28),
              ),
              // Botón cancelar/cerrar
              TextButton.icon(
                onPressed: _stopScanner,
                icon: Icon(
                  assignedCount == _labels.length ? Icons.check : Icons.close,
                  size: 20,
                ),
                label: Text(assignedCount == _labels.length ? 'Listo' : 'Cerrar'),
                style: TextButton.styleFrom(
                  foregroundColor: assignedCount == _labels.length 
                      ? Colors.green 
                      : Colors.white70,
                ),
              ),
              // Cambiar cámara
              IconButton(
                onPressed: () => _scannerController?.switchCamera(),
                icon: const Icon(Icons.cameraswitch, color: Colors.white, size: 28),
              ),
            ],
          ),
        ),
        
        // Panel flotante para aplicar multi-lote (solo visible cuando hay seleccionadas)
        if (_multiLotMode && _selectedForMultiLot.isNotEmpty)
          Positioned(
            bottom: 70,
            left: 16,
            right: 16,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.9),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.purple, width: 2),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${_selectedForMultiLot.length} etiquetas seleccionadas',
                    style: const TextStyle(color: Colors.purple, fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _multiLotController,
                          style: const TextStyle(color: Colors.white, fontSize: 14),
                          decoration: InputDecoration(
                            hintText: 'Escribir lote o escanear ↑',
                            hintStyle: const TextStyle(color: Colors.white38, fontSize: 12),
                            prefixIcon: const Icon(Icons.inventory_2, color: Colors.purple, size: 20),
                            filled: true,
                            fillColor: const Color(0xFF1A1E2C),
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide.none,
                            ),
                          ),
                          onSubmitted: (_) => _applyMultiLot(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Botón para usar código escaneado como lote
                      if (_codeReady && _detectedCode != null)
                        IconButton(
                          onPressed: () {
                            setState(() {
                              _multiLotController.text = _detectedCode!;
                              _detectedCode = null;
                              _codeReady = false;
                            });
                          },
                          icon: const Icon(Icons.qr_code_scanner, color: Colors.green),
                          tooltip: 'Usar código escaneado',
                        ),
                      ElevatedButton(
                        onPressed: _applyMultiLot,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.purple,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        ),
                        child: const Text('Aplicar'),
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

  /// UI para modo lector/PDA (sin cámara)
  Widget _buildReaderModeScanner(int pendingCount, int assignedCount) {
    return Container(
      color: AppColors.panelBackground,
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          // Header con icono y estado
          Icon(
            Icons.barcode_reader,
            size: 64,
            color: Colors.white.withOpacity(0.5),
          ),
          const SizedBox(height: 16),
          
          // Toggle Multi-Lote
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.layers,
                color: _multiLotMode ? Colors.purple : Colors.white54,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                'Multi-Lote',
                style: TextStyle(
                  color: _multiLotMode ? Colors.purple : Colors.white70,
                  fontSize: 14,
                ),
              ),
              Switch(
                value: _multiLotMode,
                onChanged: _toggleMultiLotMode,
                activeColor: Colors.purple,
              ),
            ],
          ),
          const SizedBox(height: 16),
          
          // Instrucción según modo
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: _waitingForSupplierLot ? Colors.orange.withOpacity(0.2) : AppColors.headerTab.withOpacity(0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              children: [
                Text(
                  _multiLotMode
                      ? 'Escanee etiquetas para seleccionar'
                      : _waitingForSupplierLot
                          ? 'Paso 2: Escanee el LOTE DEL PROVEEDOR'
                          : 'Paso 1: Escanee la etiqueta impresa',
                  style: TextStyle(
                    color: _waitingForSupplierLot ? Colors.orange : Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                if (_waitingForSupplierLot && _currentAssigningIndex != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Para: ${_labels[_currentAssigningIndex!].code}',
                    style: const TextStyle(color: Colors.orange, fontSize: 12),
                  ),
                ],
                if (_multiLotMode && _selectedForMultiLot.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    '${_selectedForMultiLot.length} seleccionadas',
                    style: const TextStyle(color: Colors.purple, fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 24),
          
          // Campo de texto para escaneo
          TextField(
            controller: _readerInputController,
            focusNode: _readerFocusNode,
            autofocus: true,
            style: const TextStyle(color: Colors.white, fontSize: 18),
            decoration: InputDecoration(
              labelText: _waitingForSupplierLot ? 'Lote Proveedor' : 'Código de etiqueta',
              labelStyle: const TextStyle(color: Colors.white70),
              prefixIcon: const Icon(Icons.qr_code_scanner, color: Colors.white54),
              border: const OutlineInputBorder(),
              filled: true,
              fillColor: AppColors.fieldBackground,
              focusedBorder: OutlineInputBorder(
                borderSide: BorderSide(
                  color: _waitingForSupplierLot ? Colors.orange : AppColors.headerTab,
                  width: 2,
                ),
              ),
            ),
            onSubmitted: _onReaderInput,
          ),
          const SizedBox(height: 16),
          
          // Contador de estado
          Text(
            'Asignadas: $assignedCount / ${_labels.length} | Pendientes: $pendingCount',
            style: const TextStyle(color: Colors.white54, fontSize: 13),
          ),
          
          // Panel para aplicar multi-lote (si hay seleccionadas)
          if (_multiLotMode && _selectedForMultiLot.isNotEmpty) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.purple.withOpacity(0.15),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.purple),
              ),
              child: Column(
                children: [
                  Text(
                    '${_selectedForMultiLot.length} etiquetas listas para asignar',
                    style: const TextStyle(color: Colors.purple, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _multiLotController,
                          style: const TextStyle(color: Colors.white, fontSize: 14),
                          decoration: InputDecoration(
                            hintText: 'Escribir o escanear lote',
                            hintStyle: const TextStyle(color: Colors.white38),
                            filled: true,
                            fillColor: const Color(0xFF1A1E2C),
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide.none,
                            ),
                          ),
                          onSubmitted: (_) => _applyMultiLot(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: _applyMultiLot,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.purple,
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        ),
                        child: const Text('Aplicar'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
          
          const Spacer(),
          
          // Botón de cerrar
          ElevatedButton.icon(
            onPressed: _stopScanner,
            icon: Icon(assignedCount == _labels.length ? Icons.check : Icons.close),
            label: Text(assignedCount == _labels.length ? 'Listo' : 'Cerrar'),
            style: ElevatedButton.styleFrom(
              backgroundColor: assignedCount == _labels.length ? Colors.green : const Color(0xFF3A3F4B),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    final printedCount = _labels.where((l) => l.status == LabelStatus.printed).length;
    final assignedCount = _labels.where((l) => l.status == LabelStatus.assigned).length;
    final errorCount = _labels.where((l) => l.status == LabelStatus.error).length;

    return Column(
      children: [
        // Info del material
        Container(
          padding: const EdgeInsets.all(16),
          color: const Color(0xFF252A3C),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.catalogMaterial['numero_parte']?.toString() ?? 
                widget.materialInfo['numero_parte']?.toString() ?? '-',
                style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Text(
                widget.catalogMaterial['especificacion_material']?.toString() ?? 
                widget.materialInfo['especificacion']?.toString() ?? '-',
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  _buildStatChip('Total', _labels.length.toString(), Colors.blue),
                  const SizedBox(width: 8),
                  _buildStatChip('Impresas', printedCount.toString(), Colors.orange),
                  const SizedBox(width: 8),
                  _buildStatChip('Asignadas', assignedCount.toString(), Colors.green),
                  if (errorCount > 0) ...[
                    const SizedBox(width: 8),
                    _buildStatChip('Error', errorCount.toString(), Colors.red),
                  ],
                ],
              ),
            ],
          ),
        ),

        // Lista de etiquetas
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: _labels.length,
            itemBuilder: (context, index) => _buildLabelTile(index),
          ),
        ),

        // Botones de acción
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF252A3C),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.2),
                blurRadius: 8,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: Column(
            children: [
              // Botón imprimir (si hay pendientes de impresión)
              if (_labels.any((l) => l.status == LabelStatus.pending || l.status == LabelStatus.error))
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _isPrinting ? null : _printAllLabels,
                    icon: _isPrinting
                        ? const SizedBox(
                            width: 20, height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.print),
                    label: Text(_isPrinting ? 'Imprimiendo...' : 'Imprimir Etiquetas'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
              
              // Botón escanear para asignar (si hay impresas sin asignar y NO es lote interno)
              if (!widget.assignInternalLot && _labels.any((l) => l.status == LabelStatus.printed)) ...[
                const SizedBox(height: 12),
                // Fila con botón escanear y botón selección manual
                Row(
                  children: [
                    // Botón escanear
                    Expanded(
                      child: SizedBox(
                        height: 50,
                        child: ElevatedButton.icon(
                          onPressed: () => _startAssignmentScan(),
                          icon: const Icon(Icons.qr_code_scanner, size: 24),
                          label: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text('Escanear', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                              Text(
                                '${_labels.where((l) => l.status == LabelStatus.printed).length} pendientes',
                                style: const TextStyle(fontSize: 10),
                              ),
                            ],
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Botón selección manual
                    Expanded(
                      child: SizedBox(
                        height: 50,
                        child: ElevatedButton.icon(
                          onPressed: () {
                            setState(() {
                              _manualSelectMode = !_manualSelectMode;
                              if (!_manualSelectMode) {
                                _selectedForMultiLot.clear();
                                _multiLotController.clear();
                              }
                            });
                          },
                          icon: Icon(
                            _manualSelectMode ? Icons.close : Icons.checklist,
                            size: 24,
                          ),
                          label: Text(
                            _manualSelectMode ? 'Cancelar' : 'Seleccionar',
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _manualSelectMode ? Colors.grey : Colors.purple,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              
              // Panel de asignación manual (visible cuando hay seleccionadas)
              if (_manualSelectMode && _labels.any((l) => l.status == LabelStatus.printed)) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.purple.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.purple.withOpacity(0.3)),
                  ),
                  child: Column(
                    children: [
                      // Botón seleccionar todas
                      Row(
                        children: [
                          TextButton.icon(
                            onPressed: _toggleSelectAll,
                            icon: Icon(
                              _selectedForMultiLot.length == _labels.where((l) => l.status == LabelStatus.printed).length
                                  ? Icons.deselect
                                  : Icons.select_all,
                              size: 18,
                            ),
                            label: Text(
                              _selectedForMultiLot.length == _labels.where((l) => l.status == LabelStatus.printed).length
                                  ? 'Deseleccionar Todas'
                                  : 'Seleccionar Todas',
                              style: const TextStyle(fontSize: 12),
                            ),
                            style: TextButton.styleFrom(foregroundColor: Colors.purple),
                          ),
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.purple,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              '${_selectedForMultiLot.length} seleccionadas',
                              style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      // Campo de texto para lote + botón aplicar
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _multiLotController,
                              style: const TextStyle(color: Colors.white, fontSize: 14),
                              decoration: InputDecoration(
                                hintText: 'Escriba o escanee el lote',
                                hintStyle: const TextStyle(color: Colors.white38, fontSize: 12),
                                prefixIcon: const Icon(Icons.inventory_2, color: Colors.purple, size: 20),
                                filled: true,
                                fillColor: const Color(0xFF1A1E2C),
                                isDense: true,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide.none,
                                ),
                              ),
                              onSubmitted: (_) {
                                if (_selectedForMultiLot.isNotEmpty) _applyMultiLot();
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton(
                            onPressed: _selectedForMultiLot.isEmpty || _multiLotController.text.trim().isEmpty
                                ? null
                                : _applyMultiLot,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.purple,
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            ),
                            child: const Text('Asignar'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],

              if (_labels.any((l) => l.status == LabelStatus.pending || l.status == LabelStatus.error) ||
                  _labels.any((l) => l.status == LabelStatus.printed))
                const SizedBox(height: 12),

              // Botón guardar
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _isSaving || assignedCount == 0 ? null : () => _saveToInventory(),
                  icon: _isSaving
                      ? const SizedBox(
                          width: 20, height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.save),
                  label: Text(_isSaving 
                      ? 'Guardando...' 
                      : 'Guardar en Inventario ($assignedCount)'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: assignedCount > 0 ? AppColors.headerTab : Colors.grey,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStatChip(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: TextStyle(color: color, fontSize: 11)),
          const SizedBox(width: 4),
          Text(value, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _buildLabelTile(int index) {
    final label = _labels[index];
    final isSelected = _selectedForMultiLot.contains(index);
    
    IconData icon;
    Color color;
    String statusText;
    
    switch (label.status) {
      case LabelStatus.pending:
        icon = Icons.radio_button_unchecked;
        color = Colors.grey;
        statusText = 'Pendiente de impresión';
        break;
      case LabelStatus.printed:
        icon = Icons.print;
        color = Colors.orange;
        statusText = '✓ Impresa - Lista para asignar lote';
        break;
      case LabelStatus.assigned:
        icon = Icons.check_circle;
        color = Colors.green;
        statusText = '✓ Lote: ${label.supplierLot}';
        break;
      case LabelStatus.error:
        icon = Icons.error;
        color = Colors.red;
        statusText = label.errorMessage ?? 'Error';
        break;
    }

    return GestureDetector(
      onTap: (_manualSelectMode && label.status == LabelStatus.printed)
          ? () => _toggleManualSelect(index)
          : null,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected 
              ? Colors.purple.withOpacity(0.2) 
              : const Color(0xFF252A3C),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? Colors.purple : color.withOpacity(0.3),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            // Checkbox para selección manual (solo si está en modo selección y está impresa)
            if (_manualSelectMode && label.status == LabelStatus.printed) ...[
              Checkbox(
                value: isSelected,
                onChanged: (_) => _toggleManualSelect(index),
                activeColor: Colors.purple,
                checkColor: Colors.white,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ] else ...[
              Icon(icon, color: color, size: 24),
            ],
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label.code,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Cantidad: ${label.quantity}',
                    style: const TextStyle(color: Colors.white54, fontSize: 11),
                  ),
                  Text(
                    statusText,
                    style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ),
            // Botón desasignar (solo para asignadas)
            if (label.status == LabelStatus.assigned)
              IconButton(
                icon: const Icon(Icons.link_off, color: Colors.orange),
                onPressed: () => _unassignLot(index),
                tooltip: 'Desasignar lote',
              ),
            // Botón reintentar (solo para errores)
            if (label.status == LabelStatus.error)
              IconButton(
                icon: const Icon(Icons.refresh, color: Colors.orange),
                onPressed: () => _retryPrint(index),
                tooltip: 'Reintentar',
              ),
          ],
        ),
      ),
    );
  }
}
