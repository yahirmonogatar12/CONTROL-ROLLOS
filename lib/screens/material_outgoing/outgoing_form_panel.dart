import 'package:flutter/material.dart';
import 'package:dropdown_button2/dropdown_button2.dart';
import 'package:material_warehousing_flutter/core/localization/app_translations.dart';
import 'package:material_warehousing_flutter/core/theme/app_colors.dart';
import 'package:material_warehousing_flutter/core/widgets/field_decoration.dart';
import 'package:material_warehousing_flutter/core/widgets/multi_select_table_dropdown.dart';
import 'package:material_warehousing_flutter/core/services/api_service.dart';
import 'package:material_warehousing_flutter/core/services/auth_service.dart';
import 'package:material_warehousing_flutter/core/services/printer_service.dart';
import 'package:material_warehousing_flutter/screens/material_outgoing/widgets/split_lot_dialog.dart';
import 'package:material_warehousing_flutter/screens/material_outgoing/widgets/requirements_loader_dialog.dart';

class OutgoingFormPanel extends StatefulWidget {
  final LanguageProvider languageProvider;
  final Function(String modelo, List<Map<String, dynamic>> bomData, int planCount)? onModelSelected;
  final Function(Map<String, dynamic> outgoingData)? onOutgoingSaved;
  final List<Map<String, dynamic>> currentBomData;
  /// Callback to notify when requirements mode is activated/deactivated
  final Function(bool isRequirementsMode, RequirementsLoaderResult? requirement)? onRequirementsModeChanged;
  
  const OutgoingFormPanel({
    super.key, 
    required this.languageProvider,
    this.onModelSelected,
    this.onOutgoingSaved,
    this.currentBomData = const [],
    this.onRequirementsModeChanged,
  });

  @override
  State<OutgoingFormPanel> createState() => OutgoingFormPanelState();
}

class OutgoingFormPanelState extends State<OutgoingFormPanel> {
  // Lista de planes del día
  List<Map<String, dynamic>> _todayPlans = [];
  Set<int> _selectedPlanIndices = {}; // Multi-selección
  
  // Fecha seleccionada para filtrar planes
  DateTime _selectedDate = DateTime.now();
  
  // Controlador para Lot No (escaneo)
  final TextEditingController _lotNoController = TextEditingController();
  final FocusNode _lotNoFocusNode = FocusNode();
  
  // Controladores para los campos del panel morado
  final TextEditingController _materialCodeController = TextEditingController();
  final TextEditingController _materialSpecController = TextEditingController();
  final TextEditingController _partNumberController = TextEditingController();
  final TextEditingController _currentQtyController = TextEditingController();
  final TextEditingController _materialLotNoController = TextEditingController();
  
  // Controlador para comparación escaneada
  final TextEditingController _comparacionController = TextEditingController();
  final FocusNode _comparacionFocusNode = FocusNode();
  
  // Valores de los dropdowns
  String _outDepartment = 'Almacen';
  String _outProcess = 'SMD';
  
  // Línea de proceso - PERSISTENTE (no se resetea al limpiar)
  String _lineaProceso = 'LINEA A';
  
  // Resultado de validación de comparación
  String? _comparacionResultado; // 'OK', 'NG', null
  String? _comparacionCatalogo; // Comparación registrada en el catálogo
  
  // Datos del material escaneado
  Map<String, dynamic>? _scannedMaterial;
  
  // Validaciones (habilitadas por defecto)
  bool _bomValidation = true;
  bool _fifoValidation = true;
  
  // Dividir lote - se activa según configuración del material
  bool _dividirLote = false;
  bool _salidaAutomatica = false; // Si está activo, divide automáticamente sin modal
  int? _standardPack;

  // Requirements mode
  bool _isRequirementsMode = false;
  RequirementsLoaderResult? _loadedRequirement;
  
  // Pending requirements count for badge notification
  int _pendingRequirementsCount = 0;

  // Cola de escaneos para escaneo rápido
  final List<String> _scanQueue = [];
  bool _isProcessingQueue = false;

  @override
  void initState() {
    super.initState();
    _loadTodayPlans();
    _loadPendingRequirementsCount();
    
    // Auto-focus inicial en el campo de escaneo
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _lotNoFocusNode.requestFocus();
    });
  }

  /// Load pending requirements count for badge notification
  Future<void> _loadPendingRequirementsCount() async {
    try {
      final count = await ApiService.getRequirementsPendingCount();
      if (mounted) {
        setState(() => _pendingRequirementsCount = count);
      }
    } catch (e) {
      // Ignore errors silently
    }
  }

  @override
  void dispose() {
    _lotNoController.dispose();
    _lotNoFocusNode.dispose();
    _materialCodeController.dispose();
    _materialSpecController.dispose();
    _partNumberController.dispose();
    _currentQtyController.dispose();
    _materialLotNoController.dispose();
    _comparacionController.dispose();
    _comparacionFocusNode.dispose();
    super.dispose();
  }

  /// Método público para recuperar el focus en el campo de escaneo
  /// Se llama de forma no invasiva - solo si ningún otro campo tiene focus activo
  void requestScanFocus() {
    final currentFocus = FocusManager.instance.primaryFocus;
    final isTextFieldFocused = currentFocus?.context?.widget is EditableText;
    
    if (!isTextFieldFocused) {
      _lotNoFocusNode.requestFocus();
    }
  }
  
  /// Forzar focus en el campo de escaneo (después de operaciones importantes)
  void forceScanFocus() {
    _lotNoFocusNode.requestFocus();
  }

  /// Open dialog to load requirements
  Future<void> _openRequirementsLoader() async {
    final result = await showDialog<RequirementsLoaderResult>(
      context: context,
      builder: (context) => RequirementsLoaderDialog(
        languageProvider: widget.languageProvider,
        preselectedArea: null, // Default to All Areas
      ),
    );

    // Refresh pending count after dialog closes
    _loadPendingRequirementsCount();

    if (result != null && mounted) {
      setState(() {
        _isRequirementsMode = true;
        _loadedRequirement = result;
        // Clear plan selection when switching to requirements mode
        _selectedPlanIndices = {};
      });
      
      // Notify parent about requirements mode and load items into BOM grid
      widget.onRequirementsModeChanged?.call(true, result);
      
      // Convert requirement items to BOM format for the grid
      final bomData = result.items.map((item) => {
        'side': result.areaDestino, // Process = area destino del requerimiento
        'material_code': item['numero_parte'] ?? '',
        'codigo_material': item['numero_parte'] ?? '',
        'numero_parte': item['numero_parte'] ?? '',
        'descripcion': item['descripcion'] ?? '',
        'tipo_material': item['especificacion_material'] ?? item['descripcion'] ?? '', // Material Property = spec
        'required_qty': item['cantidad_requerida'] ?? 0,
        'cantidad_requerida': item['cantidad_requerida'] ?? 0,
        'outgoing_qty': item['cantidad_entregada'] ?? 0, // Lo que ya se ha entregado
        'cantidad_entregada': item['cantidad_entregada'] ?? 0,
        'in_line': item['cantidad_disponible'] ?? 0, // Inventario disponible
        'location': item['ubicaciones_disponibles'] ?? item['ubicacion_material'] ?? '',
        'requirement_item_id': item['id'],
      }).toList();
      
      widget.onModelSelected?.call(
        result.codigoRequerimiento,
        bomData,
        1,
      );
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${widget.languageProvider.tr('requirement_loaded')}: ${result.codigoRequerimiento}'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  /// Clear requirements mode
  void _clearRequirementsMode() {
    setState(() {
      _isRequirementsMode = false;
      _loadedRequirement = null;
    });
    widget.onRequirementsModeChanged?.call(false, null);
    widget.onModelSelected?.call('', [], 0);
  }

  Future<void> _loadTodayPlans() async {
    final dateStr = '${_selectedDate.year}-${_selectedDate.month.toString().padLeft(2, '0')}-${_selectedDate.day.toString().padLeft(2, '0')}';
    final plans = await ApiService.getTodayPlans(date: dateStr);
    if (mounted) {
      setState(() {
        _todayPlans = plans;
        _selectedPlanIndices = {}; // Limpiar selección al cambiar fecha
      });
    }
  }

  // ========================================
  // SISTEMA DE COLA DE ESCANEOS
  // ========================================
  
  /// Agregar código a la cola de escaneos
  void _addToScanQueue(String code) {
    if (code.isEmpty) return;
    _scanQueue.add(code);
    if (!_isProcessingQueue) {
      _processNextInQueue();
    }
  }

  /// Procesar el siguiente código en la cola
  Future<void> _processNextInQueue() async {
    if (_scanQueue.isEmpty) {
      _isProcessingQueue = false;
      return;
    }

    _isProcessingQueue = true;
    final code = _scanQueue.removeAt(0);
    
    try {
      // Buscar material
      await _onLotNoScanned(code);
      
      if (_scannedMaterial != null) {
        // Si tiene dividir_lote activo, detener cola y mostrar diálogo
        if (_dividirLote && _standardPack != null && _standardPack! > 0) {
          // Poner el código en el campo para que lo procese el flujo normal con diálogo
          _lotNoController.text = code;
          _isProcessingQueue = false;
          
          // Mostrar notificación indicando que requiere dividir lote
          _showLargeNotification(
            '📦 DIVIDIR LOTE',
            '$code - Presione SAVE para dividir',
            Colors.purple,
          );
          
          // No continuar procesando la cola, esperar a que el usuario complete
          return;
        }
        
        // Guardar salida directamente sin dividir lote en modo rápido
        await _saveOutgoingDirect(code);
      } else {
        // Material no encontrado
        _showLargeNotification(
          '✗ $code',
          widget.languageProvider.tr('material_not_found'),
          Colors.red,
        );
      }
    } catch (e) {
      _showLargeNotification(
        '✗ $code',
        'Error: $e',
        Colors.red,
      );
    }
    
    // Procesar siguiente en cola
    if (_scanQueue.isNotEmpty) {
      await _processNextInQueue();
    } else {
      _isProcessingQueue = false;
    }
  }

  /// Guardar salida directamente (sin dividir lote) para escaneo rápido
  Future<void> _saveOutgoingDirect(String code) async {
    final tr = widget.languageProvider.tr;
    
    // Validar que el material no tenga ya una salida
    final checkResult = await ApiService.checkMaterialHasOutgoing(code);
    if (checkResult['has_outgoing'] == true) {
      _showLargeNotification(
        '⚠ $code',
        tr('material_already_has_outgoing'),
        Colors.orange,
      );
      return;
    }
    
    // Validación BOM
    if (_bomValidation && widget.currentBomData.isNotEmpty) {
      final materialCode = _scannedMaterial!['codigo_material']?.toString() ?? '';
      final partNumber = _scannedMaterial!['numero_parte']?.toString() ?? '';
      
      final isInBom = widget.currentBomData.any((bomItem) {
        final bomMaterialCode = (bomItem['codigo_material']?.toString() ?? bomItem['material_code']?.toString() ?? '').toUpperCase();
        final bomPartNumber = (bomItem['numero_parte']?.toString() ?? '').toUpperCase();
        return bomMaterialCode == materialCode.toUpperCase() || bomPartNumber == partNumber.toUpperCase();
      });
      
      if (!isInBom) {
        _showLargeNotification(
          '⚠ $code',
          '${tr('bom_validation_error')}: $materialCode',
          Colors.orange,
        );
        return;
      }
    }
    
    // Validación FIFO
    if (_fifoValidation) {
      final materialCode = _scannedMaterial!['codigo_material']?.toString() ?? '';
      final currentDate = _scannedMaterial!['fecha_recibo']?.toString() ?? '';
      
      final olderMaterial = await ApiService.checkFifoValidation(materialCode, currentDate);
      if (olderMaterial != null && olderMaterial['has_older'] == true) {
        final olderCode = olderMaterial['older_code'] ?? '';
        final olderDate = olderMaterial['older_date'] ?? '';
        _showLargeNotification(
          '⚠ $code',
          '${tr('fifo_validation_error')} ($olderCode - $olderDate)',
          Colors.orange,
        );
        return;
      }
    }
    
    // Obtener los modelos seleccionados
    final modelos = _selectedPlanIndices
        .map((i) => _todayPlans[i]['lot_no']?.toString() ?? '')
        .where((s) => s.isNotEmpty)
        .toList();
    final modelo = modelos.join(', ');
    
    // Si la comparación es NG, no deducir cantidad (solo registrar como malo)
    final cantidadSalida = _comparacionResultado == 'NG' 
      ? 0.0 
      : double.tryParse(_scannedMaterial!['cantidad_actual']?.toString() ?? '0') ?? 0;
    
    // No enviar fecha_salida - el backend usa NOW() de MySQL
    final outgoingData = {
      'codigo_material_recibido': code,
      'numero_parte': _scannedMaterial!['numero_parte']?.toString() ?? '',
      'numero_lote': _scannedMaterial!['numero_lote_material']?.toString() ?? '',
      'modelo': modelo,
      'depto_salida': _outDepartment,
      'proceso_salida': _outProcess,
      'linea_proceso': _lineaProceso,
      'comparacion_escaneada': _comparacionController.text.isNotEmpty ? _comparacionController.text : null,
      'comparacion_resultado': _comparacionResultado,
      'cantidad_salida': cantidadSalida,
      'especificacion_material': _scannedMaterial!['especificacion']?.toString() ?? '',
      'material_code': _scannedMaterial!['codigo_material']?.toString() ?? '',
      'material_property': _scannedMaterial!['propiedad_material']?.toString() ?? '',
      'msl_level': _scannedMaterial!['nivel_msl']?.toString() ?? '',
      'vendedor': _scannedMaterial!['vendedor']?.toString() ?? '',
      'usuario_registro': AuthService.currentUser?.nombreCompleto ?? 'Desconocido',
    };
    
    final result = await ApiService.createOutgoingWithResponse(outgoingData);
    
    if (result['success'] == true && mounted) {
      widget.onOutgoingSaved?.call(outgoingData);
      
      // Link to requirement if in requirements mode
      if (_isRequirementsMode && _loadedRequirement != null) {
        final cantidad = int.tryParse(_scannedMaterial!['cantidad_actual']?.toString() ?? '0') ?? 0;
        await ApiService.linkOutgoingToRequirement(
          numeroParte: _scannedMaterial!['numero_parte']?.toString() ?? '',
          areaDestino: _loadedRequirement!.areaDestino,
          cantidad: cantidad,
          codigoSalida: code,
        );
      }
      
      // Mostrar mensaje diferente según el resultado de comparación
      if (_comparacionResultado == 'NG') {
        _showLargeNotification(
          '✗ COMPARACIÓN NG',
          '$code - Registrado pero NO enviado',
          Colors.red,
        );
      } else {
        _showLargeNotification(
          '✓ SALIDA EXITOSA',
          '$code - ${_scannedMaterial!['numero_parte'] ?? ''}',
          Colors.green,
        );
      }
    } else {
      final errorCode = result['code'];
      if (errorCode == 'ALREADY_HAS_OUTGOING') {
        _showLargeNotification(
          '⚠ $code',
          tr('material_already_has_outgoing'),
          Colors.orange,
        );
      } else {
        _showLargeNotification(
          '✗ $code',
          tr('outgoing_error'),
          Colors.red,
        );
      }
    }
    
    // Limpiar campos del panel morado
    _clearFormFields();
  }
  
  /// Limpiar solo los campos de material, preservar checkboxes de división y línea de proceso
  void _clearFormFields() {
    setState(() {
      _scannedMaterial = null;
      _materialCodeController.clear();
      _materialSpecController.clear();
      _partNumberController.clear();
      _currentQtyController.clear();
      _materialLotNoController.clear();
      _comparacionController.clear();
      _comparacionResultado = null;
      _comparacionCatalogo = null;
      // NO resetear _dividirLote, _salidaAutomatica, _lineaProceso - el usuario los controla
      // Solo limpiar _standardPack ya que depende del material escaneado
      _standardPack = null;
    });
  }

  /// Mostrar notificación grande en la parte superior
  void _showLargeNotification(String title, String message, Color color) {
    if (!mounted) return;
    
    // Quitar snackbar anterior si existe
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              Icon(
                color == Colors.green ? Icons.check_circle : 
                color == Colors.orange ? Icons.warning :
                Icons.error,
                color: Colors.white,
                size: 32,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      message,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
              // Mostrar indicador de cola si hay más items
              if (_scanQueue.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'Cola: ${_scanQueue.length}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
            ],
          ),
        ),
        backgroundColor: color,
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.only(bottom: 20, left: 20, right: 20),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  // Buscar material por código escaneado
  Future<void> _onLotNoScanned(String code) async {
    if (code.isEmpty) return;
    
    // Normalizar a mayúsculas para búsqueda case-insensitive
    code = code.trim().toUpperCase();
    
    final material = await ApiService.getWarehousingByCode(code);
    if (material != null && mounted) {
      // Obtener configuración de dividir_lote del catálogo de materiales
      // Buscar PRIMERO por numero_parte (que es donde está configurado)
      final partNumber = material['numero_parte']?.toString() ?? '';
      final materialCode = material['codigo_material']?.toString() ?? '';
      bool materialDividirLote = false;
      int? materialStandardPack;
      String? comparacionCatalogo; // Comparación registrada en catálogo
      
      // Primero intentar buscar por numero_parte
      if (partNumber.isNotEmpty) {
        final materialConfig = await ApiService.getMaterialByPartNumber(partNumber);
        if (materialConfig != null) {
          materialDividirLote = materialConfig['dividir_lote'] == 1 || materialConfig['dividir_lote'] == true;
          materialStandardPack = int.tryParse(materialConfig['standard_pack']?.toString() ?? '');
          comparacionCatalogo = materialConfig['comparacion']?.toString();
          print('>>> Encontrado por numero_parte: $partNumber, dividir_lote=$materialDividirLote, standard_pack=$materialStandardPack, comparacion=$comparacionCatalogo');
        }
      }
      
      // Si no se encontró por numero_parte, buscar por codigo_material
      if (!materialDividirLote && materialCode.isNotEmpty) {
        final materialConfig = await ApiService.getMaterialByCode(materialCode);
        if (materialConfig != null) {
          materialDividirLote = materialConfig['dividir_lote'] == 1 || materialConfig['dividir_lote'] == true;
          materialStandardPack = int.tryParse(materialConfig['standard_pack']?.toString() ?? '');
          comparacionCatalogo ??= materialConfig['comparacion']?.toString();
          print('>>> Encontrado por codigo_material: $materialCode, dividir_lote=$materialDividirLote, standard_pack=$materialStandardPack, comparacion=$comparacionCatalogo');
        }
      }
      
      // Preservar estado de checkboxes si ya estaban activados por el usuario
      final keepDividirLote = _dividirLote;
      final keepSalidaAutomatica = _salidaAutomatica;
      
      setState(() {
        _scannedMaterial = material;
        _materialCodeController.text = material['codigo_material']?.toString() ?? '';
        _materialSpecController.text = material['especificacion']?.toString() ?? '';
        _partNumberController.text = material['numero_parte']?.toString() ?? '';
        _currentQtyController.text = material['cantidad_actual']?.toString() ?? '';
        _materialLotNoController.text = material['numero_lote_material']?.toString() ?? '';
        // Preservar checkboxes si ya estaban activados, solo actualizar standard_pack
        _dividirLote = keepDividirLote;
        _salidaAutomatica = keepSalidaAutomatica;
        _standardPack = materialStandardPack;
        // Guardar comparación del catálogo para validación posterior
        _comparacionCatalogo = comparacionCatalogo;
        _comparacionResultado = null; // Reset validation result
        _comparacionController.clear(); // Clear previous scan
        
        print('>>> setState: _dividirLote=$_dividirLote, _salidaAutomatica=$_salidaAutomatica, _standardPack=$_standardPack, _comparacionCatalogo=$_comparacionCatalogo');
      });
      
      // Si hay comparación en catálogo, mover focus al campo de comparación
      if (comparacionCatalogo != null && comparacionCatalogo.isNotEmpty) {
        _comparacionFocusNode.requestFocus();
      }
    } else {
      // Limpiar si no se encuentra
      setState(() {
        _scannedMaterial = null;
        _materialCodeController.clear();
        _materialSpecController.clear();
        _partNumberController.clear();
        _currentQtyController.clear();
        _materialLotNoController.clear();
        _comparacionController.clear();
        _comparacionCatalogo = null;
        _comparacionResultado = null;
        _dividirLote = false;
        _salidaAutomatica = false;
        _standardPack = null;
      });
      if (mounted) {
        _showLargeNotification(
          '✗ MATERIAL NO ENCONTRADO EN INVENTARIO',
          'El código $code no existe o no tiene cantidad disponible',
          Colors.red,
        );
      }
    }
  }

  // Guardar registro de salida
  Future<void> _saveOutgoing() async {
    final tr = widget.languageProvider.tr;
    
    // Validar que haya un material escaneado
    if (_scannedMaterial == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(tr('must_scan_material')),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Validar que el material no tenga ya una salida
    final lotNo = _lotNoController.text;
    if (lotNo.isNotEmpty) {
      final checkResult = await ApiService.checkMaterialHasOutgoing(lotNo);
      if (checkResult['has_outgoing'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('⚠ ${tr('material_already_has_outgoing')}: $lotNo'),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 3),
          ),
        );
        return;
      }
    }
    
    // Validación BOM: verificar que el material esté en el BOM cargado
    if (_bomValidation && widget.currentBomData.isNotEmpty) {
      final materialCode = _materialCodeController.text;
      final partNumber = _partNumberController.text;
      
      final isInBom = widget.currentBomData.any((bomItem) {
        final bomMaterialCode = (bomItem['codigo_material']?.toString() ?? bomItem['material_code']?.toString() ?? '').toUpperCase();
        final bomPartNumber = (bomItem['numero_parte']?.toString() ?? '').toUpperCase();
        return bomMaterialCode == materialCode.toUpperCase() || bomPartNumber == partNumber.toUpperCase();
      });
      
      if (!isInBom) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${tr('bom_validation_error')}: $materialCode'),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 3),
          ),
        );
        return;
      }
    }

    // Validación FIFO: verificar que sea el material más antiguo
    if (_fifoValidation) {
      final materialCode = _materialCodeController.text;
      final currentDate = _scannedMaterial?['fecha_recibo']?.toString() ?? '';
      
      // Buscar si hay materiales más antiguos con el mismo código
      final olderMaterial = await ApiService.checkFifoValidation(materialCode, currentDate);
      
      if (olderMaterial != null && olderMaterial['has_older'] == true) {
        final olderCode = olderMaterial['older_code'] ?? '';
        final olderDate = olderMaterial['older_date'] ?? '';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${tr('fifo_validation_error')} ($olderCode - $olderDate)'),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 3),
          ),
        );
        return;
      }
    }

    // Obtener los modelos seleccionados (concatenados)
    final modelos = _selectedPlanIndices
        .map((i) => _todayPlans[i]['lot_no']?.toString() ?? '')
        .where((s) => s.isNotEmpty)
        .toList();
    final modelo = modelos.join(', ');

    // ========================================
    // FLUJO DE DIVISIÓN DE LOTE
    // ========================================
    if (_dividirLote) {
      final currentQty = int.tryParse(_currentQtyController.text) ?? 0;
      
      print('>>> DIVIDIR LOTE ACTIVADO - currentQty: $currentQty, standardPack: $_standardPack, autoSplit: $_salidaAutomatica');
      
      List<int>? quantities; // Para Auto Split con residuos
      SplitLotResult? splitResult; // Para modal manual
      
      // Si salida automática está activa
      if (_salidaAutomatica) {
        // Verificar que tenga standard_pack configurado
        if (_standardPack == null || _standardPack! <= 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(tr('standard_pack_required')),
              backgroundColor: Colors.orange,
            ),
          );
          _lotNoFocusNode.requestFocus();
          return;
        }
        
        // Calcular packs completos + residuo
        final fullPacks = currentQty ~/ _standardPack!;
        final remainder = currentQty % _standardPack!;
        
        // Crear lista de cantidades
        quantities = [];
        for (int i = 0; i < fullPacks; i++) {
          quantities.add(_standardPack!);
        }
        // Agregar residuo si existe
        if (remainder > 0) {
          quantities.add(remainder);
        }
        
        if (quantities.isEmpty) {
          // No hay suficiente cantidad para dividir
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${tr('insufficient_qty_for_split')}: $currentQty < $_standardPack'),
              backgroundColor: Colors.orange,
            ),
          );
          _lotNoFocusNode.requestFocus();
          return;
        }
        
        print('>>> Auto Split quantities: $quantities (total: ${quantities.reduce((a, b) => a + b)})');
      } else {
        // Mostrar diálogo de división manual (para cajas parciales)
        splitResult = await showDialog<SplitLotResult>(
          context: context,
          barrierDismissible: false,
          builder: (context) => SplitLotDialog(
            languageProvider: widget.languageProvider,
            defaultStandardPack: _standardPack ?? 0,
            currentQty: currentQty,
            materialCode: _materialCodeController.text,
            partNumber: _partNumberController.text,
          ),
        );
        
        // Si el usuario canceló
        if (splitResult == null) {
          _lotNoFocusNode.requestFocus();
          return;
        }
        
        print('>>> Modal manual result: ${splitResult.packsCount} x ${splitResult.standardPack}');
      }

      // Calcular información para el modal de carga
      final int totalPacks = quantities?.length ?? splitResult!.packsCount;
      final String packInfo = quantities != null 
          ? '${quantities.length} packs (${quantities.join(", ")})'
          : '${splitResult!.packsCount} × ${splitResult!.standardPack}';

      // Mostrar modal de carga mientras se divide el lote
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => WillPopScope(
          onWillPop: () async => false,
          child: AlertDialog(
            backgroundColor: const Color(0xFF252A3C),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 60,
                  height: 60,
                  child: CircularProgressIndicator(
                    strokeWidth: 4,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.purple),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  tr('splitting_lot'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  packInfo,
                  style: const TextStyle(color: Colors.white70, fontSize: 14),
                ),
              ],
            ),
          ),
        ),
      );

      // Ejecutar división de lote
      late Map<String, dynamic> splitResponse;
      
      if (quantities != null) {
        // Auto Split: usar array de cantidades (incluye residuo)
        print('>>> Calling splitLotOutgoing with quantities: $quantities');
        splitResponse = await ApiService.splitLotOutgoing(
          originalCode: _lotNoController.text,
          quantities: quantities,
          modelo: modelo,
          deptoSalida: _outDepartment,
          procesoSalida: _outProcess,
          lineaProceso: _lineaProceso,
          comparacionEscaneada: _comparacionController.text.isNotEmpty ? _comparacionController.text : null,
          comparacionResultado: _comparacionResultado,
          usuarioRegistro: AuthService.currentUser?.nombreCompleto ?? 'Desconocido',
        );
      } else {
        // Modal manual: usar standardPack y packsCount
        print('>>> Calling splitLotOutgoing with standard_pack: ${splitResult!.standardPack}, packs_count: ${splitResult.packsCount}');
        splitResponse = await ApiService.splitLotOutgoing(
          originalCode: _lotNoController.text,
          standardPack: splitResult.standardPack,
          packsCount: splitResult.packsCount,
          modelo: modelo,
          deptoSalida: _outDepartment,
          procesoSalida: _outProcess,
          lineaProceso: _lineaProceso,
          comparacionEscaneada: _comparacionController.text.isNotEmpty ? _comparacionController.text : null,
          comparacionResultado: _comparacionResultado,
          usuarioRegistro: AuthService.currentUser?.nombreCompleto ?? 'Desconocido',
        );
      }

      // Cerrar modal de carga
      if (mounted) Navigator.of(context).pop();

      print('>>> splitResponse: $splitResponse');

      if (splitResponse['success'] == true && mounted) {
        final newLabels = splitResponse['new_labels'] as List<dynamic>? ?? [];
        final totalExtracted = splitResponse['total_extracted'] ?? 0;
        
        print('>>> newLabels count: ${newLabels.length}');
        print('>>> hasPrinterConfigured: ${PrinterService.hasPrinterConfigured}');
        print('>>> hasNetworkConfig: ${PrinterService.hasNetworkConfig}');
        
        // Notificar al padre para actualizar tabla de sesión e historial
        final now = DateTime.now();
        final fechaSalida = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')} ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';
        
        for (final label in newLabels) {
          widget.onOutgoingSaved?.call({
            'codigo_material_recibido': label['code'],
            'numero_parte': label['part_number'],
            'cantidad_salida': label['qty'],
            'modelo': modelo,
            'fecha_salida': fechaSalida,
            'proceso_salida': _outProcess,
            'depto_salida': _outDepartment,
            'numero_lote': label['lot_no'] ?? _materialLotNoController.text,
            'especificacion_material': label['spec'] ?? _scannedMaterial?['especificacion']?.toString() ?? '',
            'material_code': _scannedMaterial?['codigo_material']?.toString() ?? '',
            'usuario_registro': AuthService.currentUser?.nombreCompleto ?? 'Sistema',
          });
        }
        
        // Mostrar mensaje de éxito
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${tr('split_success')}: $totalPacks packs = $totalExtracted ${tr('units')}',
                  ),
                ),
              ],
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 4),
          ),
        );
        
        // Imprimir etiquetas de los nuevos packs
        final canPrint = PrinterService.hasPrinterConfigured || PrinterService.hasNetworkConfig;
        print('>>> canPrint: $canPrint (hasPrinterConfigured: ${PrinterService.hasPrinterConfigured}, hasNetworkConfig: ${PrinterService.hasNetworkConfig})');
        print('>>> newLabels.isNotEmpty: ${newLabels.isNotEmpty}');
        
        if (newLabels.isNotEmpty && canPrint) {
          final now = DateTime.now();
          final fecha = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
          
          print('>>> Imprimiendo ${newLabels.length} etiquetas de sublotes...');
          
          // Imprimir cada etiqueta con su cantidad específica
          for (final label in newLabels) {
            final labelCode = label['code']?.toString() ?? '';
            final labelQty = label['qty']?.toString() ?? '';
            final labelSpec = label['spec']?.toString() ?? _scannedMaterial?['especificacion']?.toString() ?? '';
            
            print('>>> Imprimiendo sublote: $labelCode - Qty: $labelQty - Spec: $labelSpec');
            
            final printResult = await PrinterService.printLabel(
              codigo: labelCode,
              fecha: fecha,
              especificacion: labelSpec,
              cantidadActual: labelQty,
            );
            
            print('>>> Resultado impresión: $printResult');
          }
          
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('${newLabels.length} ${tr('labels_to_print')}'),
                backgroundColor: Colors.blue,
                duration: const Duration(seconds: 2),
              ),
            );
          }
          
          // Imprimir etiqueta actualizada del lote original (con cantidad restante)
          final originalCode = splitResponse['original']?['code']?.toString() ?? '';
          final remainingQty = splitResponse['original']?['qty_after'];
          
          if (remainingQty != null && remainingQty > 0 && originalCode.isNotEmpty) {
            final fechaOriginal = _scannedMaterial?['fecha_recibo']?.toString() ?? 
                                  _scannedMaterial?['fecha_recibido']?.toString() ?? fecha;
            
            await PrinterService.printLabel(
              codigo: originalCode,
              fecha: fechaOriginal,
              especificacion: _scannedMaterial?['especificacion']?.toString() ?? '',
              cantidadActual: remainingQty.toString(),
            );
            
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('${tr('updated_label_printed')}: $remainingQty'),
                  backgroundColor: Colors.green.shade700,
                  duration: const Duration(seconds: 2),
                ),
              );
            }
          }
        } else if (!canPrint && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(tr('configure_printer_first')),
              backgroundColor: Colors.orange,
              duration: const Duration(seconds: 3),
            ),
          );
        }
        
        // Limpiar formulario
        _clearForm();
        
        // Continuar procesando cola si hay más items
        if (_scanQueue.isNotEmpty) {
          _processNextInQueue();
        }
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${tr('split_error')}: ${splitResponse['error'] ?? 'Error desconocido'}'),
            backgroundColor: Colors.red,
          ),
        );
      }
      
      _lotNoFocusNode.requestFocus();
      return;
    }

    // ========================================
    // FLUJO NORMAL (sin división)
    // ========================================
    
    // Si la comparación es NG, no deducir cantidad (solo registrar como malo)
    final cantidadSalida = _comparacionResultado == 'NG'
      ? 0.0
      : double.tryParse(_currentQtyController.text) ?? 0;
    
    // No enviar fecha_salida - el backend usa NOW() de MySQL
    final outgoingData = {
      'codigo_material_recibido': _lotNoController.text,
      'numero_parte': _partNumberController.text,
      'numero_lote': _materialLotNoController.text,
      'modelo': modelo,
      'depto_salida': _outDepartment,
      'proceso_salida': _outProcess,
      'linea_proceso': _lineaProceso,
      'comparacion_escaneada': _comparacionController.text.isNotEmpty ? _comparacionController.text : null,
      'comparacion_resultado': _comparacionResultado,
      'cantidad_salida': cantidadSalida,
      'especificacion_material': _materialSpecController.text,
      'material_code': _materialCodeController.text,
      'material_property': _scannedMaterial?['propiedad_material']?.toString() ?? '',
      'msl_level': _scannedMaterial?['nivel_msl']?.toString() ?? '',
      'vendedor': _scannedMaterial?['vendedor']?.toString() ?? '',
      'usuario_registro': AuthService.currentUser?.nombreCompleto ?? 'Desconocido',
    };

    final result = await ApiService.createOutgoingWithResponse(outgoingData);

    if (result['success'] == true && mounted) {
      // Notificar al padre para mostrar en la tabla
      widget.onOutgoingSaved?.call(outgoingData);
      
      // ========================================
      // LINK TO REQUIREMENT IF IN REQUIREMENTS MODE
      // ========================================
      if (_isRequirementsMode && _loadedRequirement != null) {
        final cantidad = int.tryParse(_currentQtyController.text) ?? 0;
        final linkResult = await ApiService.linkOutgoingToRequirement(
          numeroParte: _partNumberController.text,
          areaDestino: _loadedRequirement!.areaDestino,
          cantidad: cantidad,
          codigoSalida: _lotNoController.text,
        );
        
        // Mostrar mensaje diferente según el resultado de comparación
        if (_comparacionResultado == 'NG') {
          _showLargeNotification(
            '✗ COMPARACIÓN NG',
            '${_lotNoController.text} - Registrado pero NO enviado',
            Colors.red,
          );
        } else if (linkResult['linked'] == true) {
          _showLargeNotification(
            '✓ SALIDA EXITOSA',
            '${_lotNoController.text} - ${tr('requirement_updated')}',
            Colors.green,
          );
        } else {
          _showLargeNotification(
            '✓ SALIDA EXITOSA',
            '${_lotNoController.text} - ${_partNumberController.text}',
            Colors.green,
          );
        }
      } else {
        // Mostrar mensaje diferente según el resultado de comparación
        if (_comparacionResultado == 'NG') {
          _showLargeNotification(
            '✗ COMPARACIÓN NG',
            '${_lotNoController.text} - Registrado pero NO enviado',
            Colors.red,
          );
        } else {
          _showLargeNotification(
            '✓ SALIDA EXITOSA',
            '${_lotNoController.text} - ${_partNumberController.text}',
            Colors.green,
          );
        }
      }
      // Limpiar formulario
      _clearForm();
      
      // Continuar procesando cola si hay más items
      if (_scanQueue.isNotEmpty) {
        _processNextInQueue();
      }
    } else if (mounted) {
      // Mostrar mensaje de error específico si ya tiene salida
      final errorCode = result['code'];
      if (errorCode == 'ALREADY_HAS_OUTGOING') {
        _showLargeNotification(
          '⚠ ${_lotNoController.text}',
          tr('material_already_has_outgoing'),
          Colors.orange,
        );
      } else {
        _showLargeNotification(
          '✗ ERROR',
          tr('outgoing_error'),
          Colors.red,
        );
      }
    }
  }

  /// Normalizar texto para comparación inteligente
  /// Elimina caracteres especiales: - _ / \ . , y espacios
  String _normalizeForComparison(String text) {
    return text
        .replaceAll(RegExp(r'[-_/\\.,\s]'), '')
        .toUpperCase();
  }

  /// Validar comparación escaneada vs catálogo
  void _validateComparacion(String scannedValue) {
    if (scannedValue.isEmpty) {
      setState(() => _comparacionResultado = null);
      return;
    }

    if (_comparacionCatalogo == null || _comparacionCatalogo!.isEmpty) {
      // No hay comparación en catálogo - mostrar diálogo para registrar
      _showRegisterComparisonDialog();
      return;
    }

    final normalizedScanned = _normalizeForComparison(scannedValue);
    final normalizedCatalog = _normalizeForComparison(_comparacionCatalogo!);

    final isMatch = normalizedScanned == normalizedCatalog;
    
    setState(() {
      _comparacionResultado = isMatch ? 'OK' : 'NG';
    });

    if (!isMatch) {
      _showLargeNotification(
        '✗ COMPARACIÓN NO COINCIDE',
        'Escaneado: $scannedValue\nRegistrado: $_comparacionCatalogo',
        Colors.red,
      );
    } else {
      _showLargeNotification(
        '✓ COMPARACIÓN OK',
        scannedValue,
        Colors.green,
      );
    }
  }

  /// Mostrar diálogo para registrar comparación en catálogo
  Future<void> _showRegisterComparisonDialog() async {
    final tr = widget.languageProvider.tr;
    final partNumber = _partNumberController.text;
    
    if (partNumber.isEmpty) return;

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.panelBackground,
        title: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 28),
            const SizedBox(width: 12),
            Text(tr('comparison_not_registered'), style: const TextStyle(color: Colors.white)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${tr('part_number')}: $partNumber',
              style: const TextStyle(color: Colors.white70, fontSize: 14),
            ),
            const SizedBox(height: 12),
            Text(
              tr('comparison_register_prompt'),
              style: const TextStyle(color: Colors.white),
            ),
            const SizedBox(height: 8),
            Text(
              '${tr('comparison_to_register')}: ${_comparacionController.text}',
              style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(tr('cancel'), style: const TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.buttonSave),
            child: Text(tr('register')),
          ),
        ],
      ),
    );

    if (result == true && mounted) {
      // Registrar comparación en catálogo
      try {
        final response = await ApiService.updateMaterialComparacion(
          partNumber,
          _comparacionController.text,
        );
        
        if (response['success'] == true) {
          setState(() {
            _comparacionCatalogo = _comparacionController.text;
            _comparacionResultado = 'OK';
          });
          _showLargeNotification(
            '✓ COMPARACIÓN REGISTRADA',
            _comparacionController.text,
            Colors.green,
          );
        } else {
          _showLargeNotification(
            '✗ ERROR',
            response['error'] ?? tr('comparison_register_error'),
            Colors.red,
          );
        }
      } catch (e) {
        _showLargeNotification(
          '✗ ERROR',
          e.toString(),
          Colors.red,
        );
      }
    }
  }

  // Limpiar formulario
  // NOTA: _lineaProceso NO se resetea - es persistente
  void _clearForm() {
    setState(() {
      _scannedMaterial = null;
      _lotNoController.clear();
      _materialCodeController.clear();
      _materialSpecController.clear();
      _partNumberController.clear();
      _currentQtyController.clear();
      _materialLotNoController.clear();
      _comparacionController.clear();
      _comparacionResultado = null;
      _comparacionCatalogo = null;
      _dividirLote = false;
      _salidaAutomatica = false;
      _standardPack = null;
    });
  }

  // Convertir planes a formato de filas para MultiSelectTableDropdown
  List<List<String>> get _plansRows {
    return _todayPlans.map((p) => [
      p['lot_no']?.toString() ?? '',
      p['part_no']?.toString() ?? '',
      p['plan_count']?.toString() ?? '0',
    ]).toList();
  }

  // Manejar multi-selección y unificar BOMs
  Future<void> _onSelectionChanged(Set<int> selectedIndices) async {
    setState(() {
      _selectedPlanIndices = selectedIndices;
    });
    
    if (selectedIndices.isEmpty) {
      widget.onModelSelected?.call('', [], 0);
      return;
    }
    
    // Unificar BOMs de todos los planes seleccionados
    Map<String, Map<String, dynamic>> unifiedBom = {};
    int totalPlanCount = 0;
    List<String> partNumbers = [];
    
    for (final index in selectedIndices) {
      if (index < 0 || index >= _todayPlans.length) continue;
      
      final plan = _todayPlans[index];
      final partNo = plan['part_no']?.toString() ?? '';
      final planCount = int.tryParse(plan['plan_count']?.toString() ?? '0') ?? 0;
      totalPlanCount += planCount;
      if (partNo.isNotEmpty) partNumbers.add(partNo);
      
      // Cargar BOM de este plan
      final bomData = await ApiService.getPlanBom(partNo, planCount);
      
      // Unificar: sumar cantidades por material_code
      for (final item in bomData) {
        final materialCode = item['material_code']?.toString() ?? '';
        if (materialCode.isEmpty) continue;
        
        if (unifiedBom.containsKey(materialCode)) {
          // Sumar cantidad
          final existingQty = unifiedBom[materialCode]!['required_qty'] as num? ?? 0;
          final newQty = item['required_qty'] as num? ?? 0;
          unifiedBom[materialCode]!['required_qty'] = existingQty + newQty;
        } else {
          // Agregar nuevo item
          unifiedBom[materialCode] = Map<String, dynamic>.from(item);
        }
      }
    }
    
    // Convertir a lista
    final unifiedBomList = unifiedBom.values.toList();
    final modelDisplay = partNumbers.join(', ');
    
    // Notificar al padre con el BOM unificado
    widget.onModelSelected?.call(modelDisplay, unifiedBomList, totalPlanCount);
  }

  @override
  Widget build(BuildContext context) {
    final tr = widget.languageProvider.tr;
    return Container(
      color: AppColors.panelBackground,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Panel superior
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Fila 1: Código de Almacén + Escanear Comparación + FIFO Validation
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Código de Almacén
                    SizedBox(
                      width: 130,
                      child: Text(tr('warehousing_code'), style: const TextStyle(fontSize: 14, color: Colors.white)),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: TextFormField(
                        controller: _lotNoController,
                        focusNode: _lotNoFocusNode,
                        decoration: fieldDecoration(hintText: tr('scan_code')),
                        style: const TextStyle(fontSize: 14),
                        autofocus: true,
                        onFieldSubmitted: (code) async {
                          if (code.trim().isEmpty) return;
                          // Buscar material
                          await _onLotNoScanned(code.trim());
                          // Mover focus a comparación
                          if (_scannedMaterial != null) {
                            _comparacionFocusNode.requestFocus();
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 20),
                    // Escanear Comparación
                    SizedBox(
                      width: 120,
                      child: Text(tr('comparison_scan'), style: const TextStyle(fontSize: 14, color: Colors.white)),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: TextFormField(
                        controller: _comparacionController,
                        focusNode: _comparacionFocusNode,
                        decoration: fieldDecoration(hintText: tr('scan_comparison')),
                        style: const TextStyle(fontSize: 14),
                        onFieldSubmitted: (value) async {
                          if (value.trim().isEmpty) return;
                          // Validar comparación
                          _validateComparacion(value.trim());
                          // Guardar automáticamente si hay material escaneado (OK o NG)
                          if (_scannedMaterial != null && _comparacionResultado != null) {
                            await Future.delayed(const Duration(milliseconds: 500));
                            await _saveOutgoing();
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 20),
                    // FIFO Validation
                    Row(
                      children: [
                        Checkbox(
                          value: _fifoValidation,
                          onChanged: (v) => setState(() => _fifoValidation = v ?? false),
                          side: const BorderSide(color: AppColors.border),
                          activeColor: AppColors.headerTab,
                        ),
                        Text(tr('fifo_validation'), style: const TextStyle(fontSize: 14, color: Colors.white)),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                // Fila 2: Línea de Proceso
                Row(
                  children: [
                    // Línea de Proceso
                    SizedBox(
                      width: 100,
                      child: Text(tr('production_line'), style: const TextStyle(fontSize: 14, color: Colors.white)),
                    ),
                    const SizedBox(width: 10),
                    SizedBox(
                      width: 150,
                      child: DropdownButtonFormField2<String>(
                        decoration: fieldDecoration(),
                        value: _lineaProceso,
                        isExpanded: true,
                        items: const [
                          DropdownMenuItem(
                            value: 'LINEA A',
                            child: Text('LINEA A', style: TextStyle(fontSize: 14)),
                          ),
                          DropdownMenuItem(
                            value: 'LINEA B',
                            child: Text('LINEA B', style: TextStyle(fontSize: 14)),
                          ),
                          DropdownMenuItem(
                            value: 'LINEA C',
                            child: Text('LINEA C', style: TextStyle(fontSize: 14)),
                          ),
                          DropdownMenuItem(
                            value: 'LINEA D',
                            child: Text('LINEA D', style: TextStyle(fontSize: 14)),
                          ),
                          DropdownMenuItem(
                            value: 'LINEA E',
                            child: Text('LINEA E', style: TextStyle(fontSize: 14)),
                          ),
                        ],
                        onChanged: (value) {
                          if (value != null) {
                            setState(() => _lineaProceso = value);
                          }
                        },
                        iconStyleData: const IconStyleData(
                          icon: Icon(Icons.arrow_drop_down, color: Colors.white70, size: 20),
                        ),
                        dropdownStyleData: DropdownStyleData(
                          maxHeight: 200,
                          decoration: BoxDecoration(
                            color: AppColors.fieldBackground,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          padding: EdgeInsets.zero,
                        ),
                        menuItemStyleData: const MenuItemStyleData(
                          height: 32,
                          padding: EdgeInsets.symmetric(horizontal: 10),
                        ),
                      ),
                    ),
                    const Spacer(),
                    SizedBox(
                      width: 100,
                      height: 36,
                      child: ElevatedButton(
                        onPressed: _clearForm,
                        style: ElevatedButton.styleFrom(
                          padding: EdgeInsets.zero,
                          backgroundColor: AppColors.buttonGray,
                        ),
                        child: Text(tr('clean'), style: const TextStyle(fontSize: 14)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 100,
                      height: 36,
                      child: Tooltip(
                        message: AuthService.canWriteOutgoing ? '' : 'No tienes permiso para crear salidas',
                        child: ElevatedButton(
                          onPressed: AuthService.canWriteOutgoing ? _saveOutgoing : null,
                          style: ElevatedButton.styleFrom(
                            padding: EdgeInsets.zero,
                            backgroundColor: AuthService.canWriteOutgoing 
                                ? AppColors.buttonSave 
                                : Colors.grey,
                            disabledBackgroundColor: Colors.grey.shade700,
                          ),
                          child: Text(tr('save'), style: const TextStyle(fontSize: 14)),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Panel inferior (subpanel morado)
          Container(
            color: AppColors.subPanelBackground,
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
            child: Column(
              children: [
                // Fila 1: Material Code + Material Spec
                Row(
                  children: [
                    SizedBox(
                      width: 130,
                      child: Text(tr('material_code'), style: const TextStyle(fontSize: 14, color: Colors.white)),
                    ),
                    const SizedBox(width: 50),
                    SizedBox(
                      width: 350,
                      child: TextFormField(
                        controller: _materialCodeController,
                        decoration: readOnlyFieldDecoration(),
                        style: const TextStyle(fontSize: 14, color: Colors.white54),
                        readOnly: true,
                      ),
                    ),
                    const SizedBox(width: 20),
                    SizedBox(
                      width: 130,
                      child: Text(tr('material_spec'), style: const TextStyle(fontSize: 14, color: Colors.white)),
                    ),
                    Expanded(
                      child: TextFormField(
                        controller: _materialSpecController,
                        decoration: readOnlyFieldDecoration(),
                        style: const TextStyle(fontSize: 14, color: Colors.white54),
                        readOnly: true,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                // Fila 2: Part Number + Current Qty + Material Lot No
                Row(
                  children: [
                    SizedBox(
                      width: 130,
                      child: Text(tr('part_number'), style: const TextStyle(fontSize: 14, color: Colors.white)),
                    ),
                    const SizedBox(width: 50),
                    SizedBox(
                      width: 350,
                      child: TextFormField(
                        controller: _partNumberController,
                        decoration: readOnlyFieldDecoration(),
                        style: const TextStyle(fontSize: 14, color: Colors.white54),
                        readOnly: true,
                      ),
                    ),
                    const SizedBox(width: 20),
                    SizedBox(
                      width: 130,
                      child: Text(tr('current_qty'), style: const TextStyle(fontSize: 14, color: Colors.white)),
                    ),
                    SizedBox(
                      width: 350,
                      child: TextFormField(
                        controller: _currentQtyController,
                        decoration: readOnlyFieldDecoration(),
                        style: const TextStyle(fontSize: 14, color: Colors.white54),
                        readOnly: true,
                      ),
                    ),
                    const SizedBox(width: 20),
                    SizedBox(
                      width: 130,
                      child: Text(tr('material_lot_no'), style: const TextStyle(fontSize: 14, color: Colors.white)),
                    ),
                    Expanded(
                      child: TextFormField(
                        controller: _materialLotNoController,
                        decoration: fieldDecoration(),
                        style: const TextStyle(fontSize: 14),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
