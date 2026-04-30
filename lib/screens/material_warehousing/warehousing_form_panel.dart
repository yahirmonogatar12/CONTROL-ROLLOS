import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:dropdown_button2/dropdown_button2.dart';
import 'package:material_warehousing_flutter/core/localization/app_translations.dart';
import 'package:material_warehousing_flutter/core/theme/app_colors.dart';
import 'package:material_warehousing_flutter/core/widgets/field_decoration.dart';
import 'package:material_warehousing_flutter/core/widgets/table_dropdown_field.dart';
import 'package:material_warehousing_flutter/core/widgets/printer_settings_dialog.dart';
import 'package:material_warehousing_flutter/core/services/api_service.dart';
import 'package:material_warehousing_flutter/core/services/printer_service.dart';
import 'package:material_warehousing_flutter/core/services/auth_service.dart';
import 'warehousing_grid_panel.dart';

class WarehousingFormPanel extends StatefulWidget {
  final LanguageProvider languageProvider;
  final VoidCallback? onDataSaved; // Callback cuando se guardan datos
  final GlobalKey<WarehousingGridPanelState>? gridKey; // Referencia al grid para reimprimir
  
  const WarehousingFormPanel({
    super.key, 
    required this.languageProvider,
    this.onDataSaved,
    this.gridKey,
  });

  @override
  State<WarehousingFormPanel> createState() => WarehousingFormPanelState();
}

class WarehousingFormPanelState extends State<WarehousingFormPanel> {
  // Lista de materiales desde la tabla materiales
  List<Map<String, dynamic>> _materiales = [];
  
  // Controladores para campos que se rellenan al seleccionar material
  final TextEditingController _materialSpecController = TextEditingController();
  final TextEditingController _partNumberController = TextEditingController();
  final TextEditingController _packagingUnitController = TextEditingController();
  final TextEditingController _currentQtyController = TextEditingController();
  final TextEditingController _warehousingCodeController = TextEditingController();
  final TextEditingController _materialCodeController = TextEditingController();
  final TextEditingController _warehousingDateController = TextEditingController();
  final TextEditingController _makingDateController = TextEditingController();
  final TextEditingController _materialOriginalCodeController = TextEditingController();
  final TextEditingController _locationController = TextEditingController();
  final TextEditingController _pcbVersionController = TextEditingController();
  final TextEditingController _ubicacionDestinoController = TextEditingController();
  
  // FocusNode para el campo de escaneo principal
  final FocusNode _scanFocusNode = FocusNode();
  final FocusNode _ubicacionDestinoFocusNode = FocusNode();
  
  // Para generar secuencia
  Map<String, int> _secuencias = {};
  String? _currentPartNumber;
  
  // Para evitar búsquedas excesivas al escribir
  Timer? _debounceTimer;
  int? _lastSelectedMaterialIndex; // Índice del último material seleccionado
  String _lastScannedCode = ''; // Último código que disparó selección
  
  // Etiquetas generadas durante impresión para reutilizar en asignación
  // Esto evita consultar la secuencia múltiples veces y que se salten lotes
  List<String> _printedLabels = [];
  
  // Checkbox para asignar lote interno automáticamente
  bool _assignInternalLot = false;
  
  // Cliente seleccionado (REFRIS, OVEN, OTROS)
  String _selectedCliente = 'REFRIS';
  
  // Modo entrada automática
  bool _autoEntry = false;
  
  // Cola de escaneo para procesamiento rápido
  final List<String> _scanQueue = [];
  bool _processingQueue = false;
  int _queueProcessed = 0;
  int _queueErrors = 0;
  
  // Para versión de PCB (cuando Part Number empieza con EAX)
  bool _requiresPcbVersion = false;
  List<String> _availablePcbVersions = []; // Versiones disponibles del material
  String? _selectedPcbVersion; // Versión seleccionada
  
  // Para ubicaciones configurables del material
  List<String> _availableLocations = []; // Ubicaciones disponibles del material
  String? _selectedLocation; // Ubicación seleccionada
  
  // Para vendedores configurables del material
  List<String> _availableVendors = []; // Vendedores disponibles del material
  String? _selectedVendor; // Vendedor seleccionado
  
  // Ubicaciones rollos esperadas (para validación de entrada)
  List<String> _expectedRollosLocations = [];
  
  // Unidad de medida del material seleccionado
  String _unidadMedida = 'EA';

  // Modo entrada directa (sin salida de almacén)
  bool _directEntryMode = false;
  final TextEditingController _manualUserController = TextEditingController();

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }

  // Toggle entrada directa con contraseña
  Future<void> _toggleDirectEntry() async {
    if (_directEntryMode) {
      // Desactivar
      setState(() {
        _directEntryMode = false;
        _manualUserController.clear();
      });
      return;
    }

    // Pedir contraseña para activar
    final passwordController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        title: const Text('Entrada Directa', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Ingresa la contraseña para activar el modo entrada directa (sin salida de almacén)',
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: passwordController,
              obscureText: true,
              autofocus: true,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'Contraseña',
                labelStyle: TextStyle(color: Colors.white54),
                enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.cyan)),
              ),
              onSubmitted: (_) => Navigator.of(ctx).pop(true),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.cyan),
            child: const Text('Activar'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    final password = passwordController.text.trim();
    if (password.isEmpty) return;

    final valid = await ApiService.verifyDirectEntryPassword(password);
    if (!mounted) return;

    if (valid) {
      setState(() => _directEntryMode = true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Modo entrada directa ACTIVADO'),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 2),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Contraseña incorrecta'),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  void initState() {
    super.initState();
    // Inicializar fechas con fecha actual
    final now = DateTime.now();
    _warehousingDateController.text = _formatDate(now);
    _makingDateController.text = _formatDate(now);
    _loadMateriales();
    
    // Listener para buscar material cuando se escanea
    _materialOriginalCodeController.addListener(_onOriginalCodeChanged);
    
    // Auto-focus inicial en el campo de escaneo
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scanFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _materialOriginalCodeController.removeListener(_onOriginalCodeChanged);
    _materialSpecController.dispose();
    _partNumberController.dispose();
    _packagingUnitController.dispose();
    _currentQtyController.dispose();
    _warehousingCodeController.dispose();
    _materialCodeController.dispose();
    _warehousingDateController.dispose();
    _makingDateController.dispose();
    _materialOriginalCodeController.dispose();
    _locationController.dispose();
    _pcbVersionController.dispose();
    _ubicacionDestinoController.dispose();
    _scanFocusNode.dispose();
    _ubicacionDestinoFocusNode.dispose();
    _manualUserController.dispose();
    super.dispose();
  }

  /// Método público para recuperar el focus en el campo de escaneo
  /// Se llama de forma no invasiva - solo si ningún otro campo tiene focus activo
  void requestScanFocus() {
    // Verificar si algún TextField editable tiene focus activo
    final currentFocus = FocusManager.instance.primaryFocus;
    final isTextFieldFocused = currentFocus?.context?.widget is EditableText;
    
    // Solo tomar el focus si no hay ningún campo de texto activo
    if (!isTextFieldFocused) {
      _scanFocusNode.requestFocus();
    }
  }
  
  /// Forzar focus en el campo de escaneo (después de operaciones importantes)
  void forceScanFocus() {
    _scanFocusNode.requestFocus();
  }

  /// Limpia un código removiendo caracteres especiales y comillas
  String _cleanCode(String code) {
    // Remover comillas, espacios y caracteres especiales comunes en códigos escaneados
    return code
        .replaceAll('"', '')
        .replaceAll("'", '')
        .replaceAll(' ', '')
        .replaceAll('-', '')
        .replaceAll('_', '')
        .toUpperCase();
  }

  /// Extrae posibles códigos de material de un texto escaneado
  /// Los códigos suelen estar entre comillas o después de ciertos prefijos
  List<String> _extractPossibleCodes(String scannedText) {
    final codes = <String>[];
    
    // Agregar el texto completo limpio
    codes.add(_cleanCode(scannedText));
    
    // Extraer texto entre comillas dobles
    final doubleQuoteRegex = RegExp(r'"([^"]+)"');
    for (final match in doubleQuoteRegex.allMatches(scannedText)) {
      if (match.group(1) != null && match.group(1)!.length >= 5) {
        codes.add(_cleanCode(match.group(1)!));
      }
    }
    
    // Extraer texto entre comillas simples
    final singleQuoteRegex = RegExp(r"'([^']+)'");
    for (final match in singleQuoteRegex.allMatches(scannedText)) {
      if (match.group(1) != null && match.group(1)!.length >= 5) {
        codes.add(_cleanCode(match.group(1)!));
      }
    }
    
    // Dividir por separadores comunes y agregar cada parte
    final separatorRegex = RegExp(r'''["'\s,;|]+''');
    final parts = scannedText.split(separatorRegex);
    for (final part in parts) {
      if (part.length >= 5) {
        codes.add(_cleanCode(part));
      }
    }
    
    return codes.toSet().toList(); // Eliminar duplicados
  }

  // Buscar material en almacén basado en el código escaneado
  // Usa debounce para evitar búsquedas excesivas mientras se escribe
  void _onOriginalCodeChanged() {
    // Cancelar timer anterior si existe
    _debounceTimer?.cancel();
    
    // Crear nuevo timer con debounce de 400ms
    _debounceTimer = Timer(const Duration(milliseconds: 400), () {
      _performWarehouseMaterialSearch();
    });
  }
  
  // Forzar búsqueda inmediata (cuando presiona Enter)
  void _forceSearch() {
    _debounceTimer?.cancel();
    final scannedCode = _materialOriginalCodeController.text.trim();
    
    // Si está en modo automático, agregar a la cola
    if (_autoEntry && scannedCode.isNotEmpty) {
      _addToQueue(scannedCode);
      _materialOriginalCodeController.clear();
      _scanFocusNode.requestFocus();
      return;
    }
    
    _lastScannedCode = ''; // Resetear para forzar búsqueda
    _performWarehouseMaterialSearch();
  }
  
  // Agregar código a la cola de procesamiento
  void _addToQueue(String code) {
    if (code.isEmpty || _scanQueue.contains(code)) return;
    
    // Validar que destination esté lleno antes de agregar a la cola
    final ubicacionDestino = _ubicacionDestinoController.text.trim();
    if (ubicacionDestino.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(widget.languageProvider.tr('destination_required')),
          backgroundColor: Colors.orange,
        ),
      );
      _ubicacionDestinoFocusNode.requestFocus();
      return;
    }
    
    // Validar que la ubicación destino coincida con ALGUNA de las ubicaciones_rollos configuradas
    if (_expectedRollosLocations.isNotEmpty) {
      final matches = _expectedRollosLocations.any(
        (loc) => loc.toUpperCase() == ubicacionDestino.toUpperCase()
      );
      if (!matches) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${widget.languageProvider.tr('location_mismatch')}: ${_expectedRollosLocations.join(', ')}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
        _ubicacionDestinoFocusNode.requestFocus();
        return;
      }
    }

    setState(() {
      _scanQueue.add(code);
    });
    
    // Iniciar procesamiento si no está corriendo
    if (!_processingQueue) {
      _processQueue();
    }
  }
  
  // Procesar la cola de escaneos
  Future<void> _processQueue() async {
    if (_processingQueue || _scanQueue.isEmpty) return;
    
    _processingQueue = true;
    
    while (_scanQueue.isNotEmpty && mounted) {
      final code = _scanQueue.first;
      
      try {
        // Buscar material
        final searchResult = await ApiService.searchWarehouseMaterial(code, directEntry: _directEntryMode);
        
        if (!mounted) break;
        
        if (searchResult['success'] == true) {
          final data = searchResult['data'] as Map<String, dynamic>;
          final ubicacionDestino = _ubicacionDestinoController.text.trim();
          
          // Obtener ubicacion_rollos del material para validar (multi-valor)
          final ubicacionRollosStr = data['ubicacion_rollos']?.toString() ?? '';
          final rollosLocations = ubicacionRollosStr.isNotEmpty
              ? ubicacionRollosStr.split(',').map((v) => v.trim()).where((v) => v.isNotEmpty).toList()
              : <String>[];

          // Validar que la ubicación destino coincida con ALGUNA de las ubicaciones_rollos configuradas
          if (rollosLocations.isNotEmpty) {
            final matches = rollosLocations.any(
              (loc) => loc.toUpperCase() == ubicacionDestino.toUpperCase()
            );
            if (!matches) {
              _queueErrors++;
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('$code: ${widget.languageProvider.tr('location_mismatch')}: ${rollosLocations.join(', ')}'),
                    backgroundColor: Colors.red,
                    duration: const Duration(seconds: 3),
                  ),
                );
              }
              // Remover de la cola y continuar con el siguiente
              if (mounted) {
                setState(() {
                  _scanQueue.removeAt(0);
                });
              }
              continue;
            }
          }
          
          // Confirmar entrada directamente
          final usuario = _directEntryMode && _manualUserController.text.trim().isNotEmpty
              ? _manualUserController.text.trim()
              : AuthService.currentUser?.username;
          final confirmResult = await ApiService.confirmWarehouseOutgoing(
            codigoMaterialRecibido: data['codigo_material_recibido']?.toString() ?? code,
            usuario: usuario,
            ubicacionDestino: ubicacionDestino.isNotEmpty ? ubicacionDestino : null,
            directEntry: _directEntryMode,
          );
          
          if (!mounted) break;
          
          if (confirmResult['success'] == true) {
            _queueProcessed++;
            widget.onDataSaved?.call();
          } else if (confirmResult['already_confirmed'] == true) {
            _queueProcessed++; // Contar como procesado
          } else {
            _queueErrors++;
          }
        } else {
          _queueErrors++;
        }
      } catch (e) {
        _queueErrors++;
      }
      
      // Remover de la cola
      if (mounted) {
        setState(() {
          _scanQueue.removeAt(0);
        });
      }
    }
    
    _processingQueue = false;
    
    // Mostrar resumen si hubo procesamiento
    if (mounted && (_queueProcessed > 0 || _queueErrors > 0)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✅ $_queueProcessed procesados${_queueErrors > 0 ? ', ❌ $_queueErrors errores' : ''}'),
          backgroundColor: _queueErrors > 0 ? Colors.orange : Colors.green,
          duration: const Duration(seconds: 2),
        ),
      );
      _queueProcessed = 0;
      _queueErrors = 0;
    }
  }
  
  // Ejecuta la búsqueda de material en control_material_almacen
  Future<void> _performWarehouseMaterialSearch() async {
    final scannedCode = _materialOriginalCodeController.text.trim();
    if (scannedCode.isEmpty) return;
    
    // Si el código no ha cambiado, no buscar
    if (scannedCode == _lastScannedCode) return;
    _lastScannedCode = scannedCode;
    
    // Buscar en el API
    final result = await ApiService.searchWarehouseMaterial(scannedCode, directEntry: _directEntryMode);
    
    if (!mounted) return;
    
    if (result['success'] == true) {
      final data = result['data'] as Map<String, dynamic>;
      _fillFormFromWarehouseData(data);
    } else {
      // Mostrar mensaje de error según el tipo
      final error = result['error']?.toString() ?? 'unknown';
      String message;
      
      switch (error) {
        case 'no_warehouse_exit':
          message = widget.languageProvider.tr('no_warehouse_exit');
          break;
        case 'material_not_found':
          message = widget.languageProvider.tr('material_not_found');
          break;
        case 'cancelled':
          message = widget.languageProvider.tr('material_cancelled');
          break;
        case 'already_in_smd':
          message = 'Este material ya existe en el almacén SMD';
          break;
        default:
          message = result['message']?.toString() ?? widget.languageProvider.tr('error');
      }
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }
  
  // Rellena el formulario con datos del material de almacén
  void _fillFormFromWarehouseData(Map<String, dynamic> data) {
    setState(() {
      _partNumberController.text = data['numero_parte']?.toString() ?? '';
      _materialCodeController.text = data['codigo_material']?.toString() ?? '';
      _materialSpecController.text = data['especificacion']?.toString() ?? '';
      _packagingUnitController.text = data['cantidad_estandarizada']?.toString() ?? '';
      _currentQtyController.text = data['cantidad_actual']?.toString() ?? '';
      _warehousingCodeController.text = data['codigo_material_recibido']?.toString() ?? '';
      _locationController.text = data['ubicacion']?.toString() ?? '';
      _unidadMedida = data['unidad_medida']?.toString() ?? 'EA';
      _currentPartNumber = data['numero_parte']?.toString();
      
      // Guardar ubicaciones rollos esperadas para validación (multi-valor)
      final ubicacionRollosStr = data['ubicacion_rollos']?.toString() ?? '';
      _expectedRollosLocations = ubicacionRollosStr.isNotEmpty
          ? ubicacionRollosStr.split(',').map((v) => v.trim()).where((v) => v.isNotEmpty).toList()
          : [];
      
      // Rellenar customer (cliente)
      final cliente = data['cliente']?.toString();
      if (cliente != null && cliente.isNotEmpty) {
        // Verificar si el cliente está en la lista de opciones
        if (['REFRIS', 'OVEN', 'OTROS'].contains(cliente.toUpperCase())) {
          _selectedCliente = cliente.toUpperCase();
        }
      }
      
      // Rellenar vendor (vendedor)
      final vendedor = data['vendedor']?.toString();
      if (vendedor != null && vendedor.isNotEmpty) {
        // Agregar vendedor a la lista si no existe
        if (!_availableVendors.contains(vendedor)) {
          _availableVendors = [vendedor];
        }
        _selectedVendor = vendedor;
      }
      
      // Estos campos no aplican para entrada desde almacén
      _assignInternalLot = false;
      _requiresPcbVersion = false;
      _availablePcbVersions = [];
      _selectedPcbVersion = null;
    });
    
    // Si está en modo entrada automática, confirmar automáticamente
    if (_autoEntry) {
      // Pequeño delay para que se actualice la UI
      Future.delayed(const Duration(milliseconds: 100), () {
        if (mounted) _confirmWarehouseEntry();
      });
    } else if (_ubicacionDestinoController.text.isEmpty) {
      // Solo mover focus a ubicación destino si está vacío y no es auto entry
      _ubicacionDestinoFocusNode.requestFocus();
    }
  }

  // Confirmar entrada de material desde almacén
  Future<void> _confirmWarehouseEntry() async {
    final codigo = _warehousingCodeController.text.trim();
    if (codigo.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(widget.languageProvider.tr('scan_material_first')),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    
    final ubicacionDestino = _ubicacionDestinoController.text.trim();
    
    // Validar que destination esté lleno
    if (ubicacionDestino.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(widget.languageProvider.tr('destination_required')),
          backgroundColor: Colors.orange,
        ),
      );
      _ubicacionDestinoFocusNode.requestFocus();
      return;
    }
    
    // Validar que la ubicación destino coincida con ALGUNA de las ubicaciones_rollos configuradas
    if (_expectedRollosLocations.isNotEmpty) {
      final matches = _expectedRollosLocations.any(
        (loc) => loc.toUpperCase() == ubicacionDestino.toUpperCase()
      );
      if (!matches) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${widget.languageProvider.tr('location_mismatch')}: ${_expectedRollosLocations.join(', ')}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
        _ubicacionDestinoFocusNode.requestFocus();
        return;
      }
    }

    // Llamar al API para confirmar la entrada
    final usuario = _directEntryMode && _manualUserController.text.trim().isNotEmpty
        ? _manualUserController.text.trim()
        : AuthService.currentUser?.username;

    // En modo Entrada Directa: crear registro directamente en control_material_almacen_smd
    // (el código de almacén puede ser generado y no existir en control_material_almacen)
    if (_directEntryMode) {
      // En entrada directa, usar el código original escaneado como código de almacén
      final codigoOriginal = _materialOriginalCodeController.text.trim();
      final codigoAlmacen = codigoOriginal.isNotEmpty ? codigoOriginal : codigo;
      final now = DateTime.now();
      final data = {
        'forma_material': 'DirectEntry',
        'cliente': _selectedCliente ?? '',
        'codigo_material_original': codigoOriginal,
        'codigo_material': _materialCodeController.text,
        'material_importacion_local': 'Local',
        'fecha_recibo': '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')} ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}',
        'fecha_fabricacion': _makingDateController.text.isNotEmpty
            ? _makingDateController.text.split('/').reversed.join('-')
            : null,
        'cantidad_actual': int.tryParse(_currentQtyController.text) ?? 0,
        'numero_lote_material': 'N/A',
        'codigo_material_recibido': codigoAlmacen,
        'numero_parte': _partNumberController.text,
        'cantidad_estandarizada': _packagingUnitController.text,
        'codigo_material_final': _materialCodeController.text,
        'propiedad_material': 'SMD',
        'especificacion': _materialSpecController.text,
        'material_importacion_local_final': 'Local',
        'estado_desecho': 0,
        'ubicacion_destino': ubicacionDestino,
        'vendedor': _selectedVendor ?? '',
        'usuario_registro': usuario ?? 'Sistema',
        'unidad_medida': _unidadMedida,
      };

      final result = await ApiService.createWarehousing(data);

      if (!mounted) return;

      if (result['success'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${widget.languageProvider.tr('entry_confirmed')}: $codigoAlmacen'),
            backgroundColor: Colors.green,
          ),
        );
        _clearForm();
        widget.onDataSaved?.call();
        _scanFocusNode.requestFocus();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result['error']?.toString() ?? widget.languageProvider.tr('error')),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    // Flujo normal: confirmar entrada desde control_material_almacen
    final result = await ApiService.confirmWarehouseOutgoing(
      codigoMaterialRecibido: codigo,
      usuario: usuario,
      ubicacionDestino: ubicacionDestino.isNotEmpty ? ubicacionDestino : null,
      directEntry: _directEntryMode,
    );
    
    if (!mounted) return;
    
    if (result['success'] == true) {
      // Verificar si realmente se insertó el registro en almacen_smd
      final insertedAlmacen = result['inserted_almacen'];
      if (insertedAlmacen == false) {
        // El material ya existía en control_material_almacen_smd, no se insertó nuevo
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Este material ya existe en el almacén SMD: $codigo'),
            backgroundColor: Colors.orange,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${widget.languageProvider.tr('entry_confirmed')}: $codigo'),
            backgroundColor: Colors.green,
          ),
        );
      }
      
      // Limpiar formulario
      _clearForm();
      
      // Notificar que se guardaron datos
      widget.onDataSaved?.call();
      
      // Volver al campo de escaneo
      _scanFocusNode.requestFocus();
    } else if (result['already_confirmed'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(widget.languageProvider.tr('already_confirmed')),
          backgroundColor: Colors.orange,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result['error']?.toString() ?? widget.languageProvider.tr('error')),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // Imprimir etiqueta - desde filas seleccionadas del grid O desde formulario
  Future<void> _printLabel() async {
    print('>>> BOTÓN PRINT PRESIONADO <<<');
    
    // Verificar si hay filas seleccionadas en el grid
    final gridState = widget.gridKey?.currentState;
    final selectedItems = gridState?.getSelectedItems() ?? [];
    
    if (selectedItems.isNotEmpty) {
      // Imprimir múltiples etiquetas desde el grid
      await _printMultipleLabels(selectedItems);
      return;
    }
    
    // Si no hay selección en el grid, imprimir desde el formulario
    final codigo = _warehousingCodeController.text;
    final fecha = _warehousingDateController.text;
    final especificacion = _materialSpecController.text;
    final cantidadActual = _currentQtyController.text;
    
    print('warehousingCode: "$codigo"');
    print('hasPrinterConfigured: ${PrinterService.hasPrinterConfigured}');
    
    // Validar que haya datos para imprimir
    if (codigo.isEmpty) {
      print('ERROR: Código de almacenamiento vacío');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No hay código de almacenamiento para imprimir. Seleccione filas del grid o ingrese datos en el formulario'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Validar que haya impresora configurada
    if (!PrinterService.hasPrinterConfigured) {
      print('ERROR: No hay impresora configurada');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Configure una impresora primero'),
          backgroundColor: Colors.orange,
        ),
      );
      PrinterSettingsDialog.show(context);
      return;
    }

    // Mostrar indicador de impresión
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
            const SizedBox(width: 12),
            Text('${widget.languageProvider.tr('printing_to')}: ${PrinterService.selectedPrinterName}...'),
          ],
        ),
        duration: const Duration(seconds: 2),
      ),
    );

    // Imprimir la etiqueta
    final success = await PrinterService.printLabel(
      codigo: codigo,
      fecha: fecha,
      especificacion: especificacion,
      cantidadActual: cantidadActual,
    );
    
    // MSL Mirror Label: Si el material tiene nivel_msl >= 1, imprimir copia
    bool mslCopyPrinted = false;
    if (success) {
      // Buscar el material por numero_parte del formulario
      final numeroParte = _partNumberController.text;
      if (numeroParte.isNotEmpty) {
        final materialIndex = _materiales.indexWhere(
          (m) => m['numero_parte']?.toString() == numeroParte
        );
        if (materialIndex >= 0) {
          final material = _materiales[materialIndex];
          final nivelMsl = int.tryParse(material['nivel_msl']?.toString() ?? '') ?? 0;
          print('>>> MSL Check: numero_parte=$numeroParte, nivel_msl=$nivelMsl');
          if (nivelMsl >= 1) {
            await Future.delayed(const Duration(milliseconds: 300)); // Pausa entre etiquetas
            mslCopyPrinted = await PrinterService.printLabel(
              codigo: codigo,
              fecha: fecha,
              especificacion: especificacion,
              cantidadActual: cantidadActual,
            );
            print('>>> MSL Copy printed: $mslCopyPrinted');
          }
        }
      }
    }

    if (mounted) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      String message = success 
        ? '✓ Etiqueta impresa correctamente' 
        : '✗ Error al imprimir - Revise la configuración de red/impresora';
      if (success && mslCopyPrinted) {
        message = '✓ Etiqueta + copia MSL impresas correctamente';
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: success ? Colors.green : Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }
  
  // Imprimir múltiples etiquetas desde filas seleccionadas del grid
  Future<void> _printMultipleLabels(List<Map<String, dynamic>> selectedItems) async {
    print('>>> IMPRIMIENDO ${selectedItems.length} ETIQUETAS DESDE GRID <<<');
    
    // Validar que haya impresora configurada
    if (!PrinterService.hasPrinterConfigured) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Configure una impresora primero'),
          backgroundColor: Colors.orange,
        ),
      );
      PrinterSettingsDialog.show(context);
      return;
    }
    
    int successCount = 0;
    int errorCount = 0;
    final total = selectedItems.length;
    
    // Mostrar indicador de progreso
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
            const SizedBox(width: 12),
            Text('Imprimiendo $total etiquetas...'),
          ],
        ),
        duration: Duration(seconds: total * 2 + 2),
      ),
    );
    
    for (int i = 0; i < selectedItems.length; i++) {
      final row = selectedItems[i];
      
      final codigo = row['codigo_material_recibido']?.toString() ?? '';
      if (codigo.isEmpty) {
        errorCount++;
        continue;
      }
      
      // Formatear fecha
      final fechaRaw = row['fecha_recibo']?.toString() ?? '';
      String fecha = '';
      if (fechaRaw.isNotEmpty) {
        try {
          final date = DateTime.parse(fechaRaw);
          fecha = '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
        } catch (_) {
          fecha = fechaRaw;
        }
      }
      
      final especificacion = row['especificacion']?.toString() ?? '';
      final cantidadActual = row['cantidad_actual']?.toString() ?? '';
      
      print('Imprimiendo ${i + 1}/$total: $codigo');
      
      final success = await PrinterService.printLabel(
        codigo: codigo,
        fecha: fecha,
        especificacion: especificacion,
        cantidadActual: cantidadActual,
      );
      
      if (success) {
        successCount++;
        
        // MSL Mirror Label: Buscar nivel_msl del material por numero_parte
        final numeroParte = row['numero_parte']?.toString() ?? '';
        if (numeroParte.isNotEmpty) {
          final materialIndex = _materiales.indexWhere(
            (m) => m['numero_parte']?.toString() == numeroParte
          );
          if (materialIndex >= 0) {
            final nivelMsl = int.tryParse(_materiales[materialIndex]['nivel_msl']?.toString() ?? '') ?? 0;
            if (nivelMsl >= 1) {
              await Future.delayed(const Duration(milliseconds: 300));
              await PrinterService.printLabel(
                codigo: codigo,
                fecha: fecha,
                especificacion: especificacion,
                cantidadActual: cantidadActual,
              );
              // No contamos la copia MSL en successCount, solo es espejo
            }
          }
        }
      } else {
        errorCount++;
      }
      
      // Pequeña pausa entre impresiones para no saturar la impresora
      if (i < selectedItems.length - 1) {
        await Future.delayed(const Duration(milliseconds: 300));
      }
    }
    
    if (mounted) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      
      final message = errorCount == 0
          ? '✓ $successCount etiquetas impresas correctamente'
          : '⚠ $successCount impresas, $errorCount errores';
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: errorCount == 0 ? Colors.green : Colors.orange,
          duration: const Duration(seconds: 3),
        ),
      );
      
      // Limpiar selección del grid después de imprimir
      widget.gridKey?.currentState?.clearSelection();
    }
  }

  // Helper para obtener Part Number completo (incluyendo versión PCB si aplica)
  String _getFullPartNumber() {
    final base = _partNumberController.text;
    final version = _pcbVersionController.text.trim();
    return version.isNotEmpty ? '$base$version' : base;
  }

  // Validar si la versión PCB es requerida
  bool _validatePcbVersion() {
    if (_requiresPcbVersion && _pcbVersionController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(widget.languageProvider.tr('pcb_version_required')),
          backgroundColor: Colors.red,
        ),
      );
      return false;
    }
    return true;
  }

  // Validar que la ubicación destino sea obligatoria y coincida con ubicacion_rollos
  bool _validateLocation() {
    final ubicacionDestino = _ubicacionDestinoController.text.trim();
    
    if (ubicacionDestino.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(widget.languageProvider.tr('destination_required')),
          backgroundColor: Colors.red,
        ),
      );
      return false;
    }
    
    // Validar que coincida con ALGUNA de las ubicaciones_rollos configuradas
    if (_expectedRollosLocations.isNotEmpty) {
      final matches = _expectedRollosLocations.any(
        (loc) => loc.toUpperCase() == ubicacionDestino.toUpperCase()
      );
      if (!matches) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${widget.languageProvider.tr('location_mismatch')}: ${_expectedRollosLocations.join(', ')}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
        _ubicacionDestinoFocusNode.requestFocus();
        return false;
      }
    }
    
    return true;
  }

  // Guardar con lote interno generado automáticamente (pregunta cantidad)
  Future<void> _saveWithInternalLot() async {
    if (_partNumberController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(widget.languageProvider.tr('select_material_first')), backgroundColor: Colors.red),
      );
      return;
    }

    // Validar versión PCB si es requerida
    if (!_validatePcbVersion()) return;
    
    // Validar ubicación obligatoria
    if (!_validateLocation()) return;

    // Mostrar modal para preguntar cantidad y lote opcional
    final quantityController = TextEditingController();
    final customLotController = TextEditingController();
    
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.panelBackground,
        title: Text(widget.languageProvider.tr('label_quantity'), style: const TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Part Number: ${_getFullPartNumber()}',
              style: const TextStyle(color: Colors.white70, fontSize: 14),
            ),
            const SizedBox(height: 8),
            Text(
              widget.languageProvider.tr('assign_internal_lot'),
              style: const TextStyle(color: AppColors.headerTab, fontSize: 12, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: quantityController,
              keyboardType: TextInputType.number,
              autofocus: true,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: widget.languageProvider.tr('unit_quantity'),
                labelStyle: const TextStyle(color: Colors.white70),
                enabledBorder: const OutlineInputBorder(
                  borderSide: BorderSide(color: AppColors.border),
                ),
                focusedBorder: const OutlineInputBorder(
                  borderSide: BorderSide(color: AppColors.headerTab),
                ),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: customLotController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: widget.languageProvider.tr('custom_lot_optional'),
                hintText: widget.languageProvider.tr('leave_empty_auto'),
                hintStyle: const TextStyle(color: Colors.white30, fontSize: 11),
                labelStyle: const TextStyle(color: Colors.white70),
                enabledBorder: const OutlineInputBorder(
                  borderSide: BorderSide(color: AppColors.border),
                ),
                focusedBorder: const OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.orange),
                ),
                prefixIcon: const Icon(Icons.edit_note, color: Colors.orange, size: 20),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(null),
            child: Text(widget.languageProvider.tr('cancel'), style: const TextStyle(color: Colors.white70)),
          ),
          ElevatedButton(
            onPressed: () {
              final qty = int.tryParse(quantityController.text);
              if (qty != null && qty > 0) {
                Navigator.of(context).pop({
                  'quantity': qty,
                  'customLot': customLotController.text.trim(),
                });
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(widget.languageProvider.tr('enter_valid_quantity')), backgroundColor: Colors.red),
                );
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.buttonSave),
            child: Text(widget.languageProvider.tr('save')),
          ),
        ],
      ),
    );
    
    if (result == null) return;
    final quantity = result['quantity'] as int;
    final customLot = result['customLot'] as String;

    // Verificar impresora
    if (!PrinterService.hasPrinterConfigured) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('⚠ ${widget.languageProvider.tr('configure_printer_first')}'),
          backgroundColor: Colors.orange,
        ),
      );
      PrinterSettingsDialog.show(context);
      return;
    }

    // Obtener la siguiente secuencia del lote interno desde la BD
    final now = DateTime.now();
    final dateStr = '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year}';
    
    try {
      // Recargar la secuencia de la DB antes de generar etiquetas
      final partNumber = _getFullPartNumber();
      final nowDate = DateTime.now();
      final dateStrCode = '${nowDate.year}${nowDate.month.toString().padLeft(2, '0')}${nowDate.day.toString().padLeft(2, '0')}';
      
      if (partNumber.isNotEmpty) {
        try {
          final seqResult = await ApiService.getNextSequence(partNumber, dateStrCode);
          final nextSeq = seqResult['nextSequence'] as int? ?? 1;
          _secuencias['$partNumber-$dateStrCode'] = nextSeq - 1;
        } catch (e) {
          // Continuar con la secuencia en memoria
        }
      }
      
      // Generar las etiquetas según la cantidad ingresada
      final labels = _generateLabels(quantity);
      
      // Asignar lote interno a cada etiqueta
      final assignedLabels = <String, String>{};
      
      if (customLot.isNotEmpty) {
        // Usar el lote personalizado para TODAS las etiquetas
        for (var label in labels) {
          assignedLabels[label] = customLot;
        }
      } else {
        // Generar lotes automáticos secuenciales
        final apiResult = await ApiService.getNextInternalLotSequence();
        int nextSeq = apiResult['nextSequence'] as int? ?? 1;
        
        for (var label in labels) {
          final internalLot = '$dateStr/${nextSeq.toString().padLeft(5, '0')}';
          assignedLabels[label] = internalLot;
          nextSeq++; // Incrementar para la siguiente etiqueta
        }
      }
      
      // Imprimir etiquetas antes de guardar
      if (!mounted) return;
      
      // Obtener nivel MSL del material actual
      final numeroParte = _partNumberController.text;
      int nivelMsl = 0;
      if (numeroParte.isNotEmpty) {
        final materialIndex = _materiales.indexWhere(
          (m) => m['numero_parte']?.toString() == numeroParte
        );
        if (materialIndex >= 0) {
          nivelMsl = int.tryParse(_materiales[materialIndex]['nivel_msl']?.toString() ?? '') ?? 0;
        }
      }
      
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => _PrintingProgressDialog(
          labels: labels,
          fecha: _warehousingDateController.text,
          especificacion: _materialSpecController.text,
          cantidad: _currentQtyController.text,
          languageProvider: widget.languageProvider,
          nivelMsl: nivelMsl,
          onComplete: (printedCount, errorCount) async {
            // Después de imprimir, guardar en inventario
            await _saveToInventory(assignedLabels);
          },
        ),
      );
      
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error generating internal lot: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  // Mostrar modal para ingresar cantidad de etiquetas
  void _showQuantityModal() {
    if (_partNumberController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(widget.languageProvider.tr('select_material_first')), backgroundColor: Colors.red),
      );
      return;
    }

    // Validar versión PCB si es requerida
    if (!_validatePcbVersion()) return;
    
    // Validar ubicación obligatoria
    if (!_validateLocation()) return;

    final quantityController = TextEditingController();
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.panelBackground,
        title: Text(widget.languageProvider.tr('label_quantity'), style: const TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Part Number: ${_getFullPartNumber()}',
              style: const TextStyle(color: Colors.white70, fontSize: 14),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: quantityController,
              keyboardType: TextInputType.number,
              autofocus: true,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: widget.languageProvider.tr('unit_quantity'),
                labelStyle: const TextStyle(color: Colors.white70),
                filled: true,
                fillColor: AppColors.fieldBackground,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(4)),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(4),
                  borderSide: BorderSide(color: AppColors.border),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(widget.languageProvider.tr('cancel'), style: const TextStyle(color: Colors.white70)),
          ),
          ElevatedButton(
            onPressed: () {
              final qty = int.tryParse(quantityController.text) ?? 0;
              if (qty <= 0) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(widget.languageProvider.tr('enter_valid_quantity')), backgroundColor: Colors.red),
                );
                return;
              }
              Navigator.pop(context);
              // Imprimir etiquetas inmediatamente y luego mostrar asignación
              _printAndShowLabelAssignment(qty);
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.buttonSave),
            child: Text(widget.languageProvider.tr('continue')),
          ),
        ],
      ),
    );
  }

  // NUEVO: Imprimir etiquetas inmediatamente y luego mostrar asignación
  Future<void> _printAndShowLabelAssignment(int quantity) async {
    // Verificar impresora
    if (!PrinterService.hasPrinterConfigured) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('⚠ ${widget.languageProvider.tr('configure_printer_first')}'),
          backgroundColor: Colors.orange,
        ),
      );
      PrinterSettingsDialog.show(context);
      return;
    }

    // Recargar la secuencia de la DB antes de generar etiquetas
    // IMPORTANTE: Usar getNextSequence (que SÍ actualiza el cache) porque vamos a imprimir
    final partNumber = _getFullPartNumber(); // Usar Part Number completo con versión PCB
    final now = DateTime.now();
    final dateStr = '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
    
    if (partNumber.isNotEmpty) {
      try {
        final result = await ApiService.getNextSequence(partNumber, dateStr);
        final nextSeq = result['nextSequence'] as int? ?? 1;
        _secuencias['$partNumber-$dateStr'] = nextSeq - 1;
      } catch (e) {
        // Continuar con la secuencia en memoria
      }
    }

    // Generar las etiquetas y GUARDARLAS para reutilizar en el modal de asignación
    final labels = _generateLabels(quantity);
    _printedLabels = List.from(labels); // Guardar copia para el modal de asignación

    // Mostrar diálogo de progreso de impresión
    if (!mounted) return;
    
    // Obtener nivel MSL del material actual
    final numeroParte = _partNumberController.text;
    int nivelMsl = 0;
    if (numeroParte.isNotEmpty) {
      final materialIndex = _materiales.indexWhere(
        (m) => m['numero_parte']?.toString() == numeroParte
      );
      if (materialIndex >= 0) {
        nivelMsl = int.tryParse(_materiales[materialIndex]['nivel_msl']?.toString() ?? '') ?? 0;
      }
    }
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => _PrintingProgressDialog(
        labels: labels,
        fecha: _warehousingDateController.text,
        especificacion: _materialSpecController.text,
        cantidad: _currentQtyController.text,
        languageProvider: widget.languageProvider,
        nivelMsl: nivelMsl,
        onComplete: (printedCount, errorCount) {
          // Después de imprimir, mostrar modal de asignación usando las MISMAS etiquetas
          _showLabelAssignmentModal(quantity);
        },
      ),
    );
  }

  // Generar lista de etiquetas secuenciales (usa la secuencia cargada de la DB)
  List<String> _generateLabels(int quantity) {
    final partNumber = _getFullPartNumber(); // Usar Part Number completo con versión PCB
    final now = DateTime.now();
    final dateStr = '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
    
    // Obtener la secuencia inicial para este part number y fecha
    // _secuencias[key] ya contiene la última secuencia usada (de la DB)
    final key = '$partNumber-$dateStr';
    final startSeq = (_secuencias[key] ?? 0);
    
    List<String> labels = [];
    for (int i = 0; i < quantity; i++) {
      final seq = (startSeq + i + 1).toString().padLeft(4, '0');
      labels.add('$partNumber-$dateStr$seq');
    }
    
    return labels;
  }

  // Mostrar modal de asignación de etiquetas
  // IMPORTANTE: Reutiliza las etiquetas guardadas en _printedLabels para evitar doble consulta
  void _showLabelAssignmentModal(int quantity) async {
    // Usar las etiquetas que ya se generaron e imprimieron (NO regenerar)
    // Esto evita que se salten lotes por doble consulta a la secuencia
    List<String> labels;
    if (_printedLabels.isNotEmpty) {
      // Usar las etiquetas ya impresas (caso normal: viene de _printAndShowLabelAssignment)
      labels = List.from(_printedLabels);
    } else {
      // Fallback: generar etiquetas si no hay impresas (caso directo sin imprimir)
      final partNumber = _getFullPartNumber();
      if (partNumber.isNotEmpty) {
        final now = DateTime.now();
        final dateStr = '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
        try {
          final result = await ApiService.getNextSequence(partNumber, dateStr);
          final nextSeq = result['nextSequence'] as int? ?? 1;
          _secuencias['$partNumber-$dateStr'] = nextSeq - 1;
        } catch (e) {
          // Continuar con la secuencia en memoria
        }
      }
      labels = _generateLabels(quantity);
    }
    
    final Map<String, String> labelLotMap = {}; // Mapa de etiqueta -> lote proveedor
    
    if (!mounted) return;
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => _LabelAssignmentDialog(
        labels: labels,
        labelLotMap: labelLotMap,
        partNumber: _getFullPartNumber(), // Usar Part Number completo con versión PCB
        languageProvider: widget.languageProvider,
        onComplete: (assignedLabels, unassignedLabels) {
          if (unassignedLabels.isNotEmpty) {
            _showUnassignedWarning(assignedLabels, unassignedLabels);
          } else {
            _saveToInventory(assignedLabels);
          }
        },
      ),
    );
  }

  // Mostrar advertencia de etiquetas no asignadas
  void _showUnassignedWarning(Map<String, String> assignedLabels, List<String> unassignedLabels) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.panelBackground,
        title: Row(
          children: [
            const Icon(Icons.warning, color: Colors.orange, size: 28),
            const SizedBox(width: 8),
            Text(widget.languageProvider.tr('unassigned_labels'), style: const TextStyle(color: Colors.white)),
          ],
        ),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.languageProvider.tr('labels_no_inventory'),
                style: const TextStyle(color: Colors.white70, fontSize: 14),
              ),
              const SizedBox(height: 12),
              Container(
                constraints: const BoxConstraints(maxHeight: 200),
                decoration: BoxDecoration(
                  color: AppColors.fieldBackground,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: unassignedLabels.length,
                  itemBuilder: (context, index) => Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    child: Text(
                      unassignedLabels[index],
                      style: const TextStyle(color: Colors.red, fontSize: 13),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                '${widget.languageProvider.tr('assigned_count')}: ${assignedLabels.length} | ${widget.languageProvider.tr('unassigned_count')}: ${unassignedLabels.length}',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(widget.languageProvider.tr('back_to_assign'), style: const TextStyle(color: Colors.white70)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _saveToInventory(assignedLabels);
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.buttonSave),
            child: Text(widget.languageProvider.tr('finish_anyway')),
          ),
        ],
      ),
    );
  }

  // Guardar en inventario (las etiquetas ya fueron impresas antes)
  Future<void> _saveToInventory(Map<String, String> assignedLabels) async {
    // Actualizar la secuencia
    final partNumber = _getFullPartNumber(); // Usar Part Number completo con versión PCB
    final now = DateTime.now();
    final dateStr = '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
    final key = '$partNumber-$dateStr';
    _secuencias[key] = (_secuencias[key] ?? 0) + assignedLabels.length;

    // Mostrar indicador de carga
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.panelBackground,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(
              'Guardando ${assignedLabels.length} registros en inventario...',
              style: const TextStyle(color: Colors.white),
            ),
          ],
        ),
      ),
    );

    int savedCount = 0;
    int errorCount = 0;

    // Guardar cada etiqueta en la base de datos
    for (final entry in assignedLabels.entries) {
      final label = entry.key;  // Código de etiqueta (warehousing code)
      final lot = entry.value;   // Lote del proveedor
      
      final data = {
        'forma_material': 'OriginCode',
        'cliente': _selectedCliente,
        'codigo_material_original': _materialOriginalCodeController.text,
        'codigo_material': _materialCodeController.text,
        'material_importacion_local': 'Local',
        'fecha_recibo': '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')} ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}',
        'fecha_fabricacion': _makingDateController.text.split('/').reversed.join('-'),
        'cantidad_actual': int.tryParse(_currentQtyController.text) ?? 0,
        'numero_lote_material': lot,
        'codigo_material_recibido': label,
        'numero_parte': _getFullPartNumber(), // Part Number completo con versión PCB
        'cantidad_estandarizada': _packagingUnitController.text,
        'codigo_material_final': _materialCodeController.text,
        'propiedad_material': 'Customer Supply',
        'especificacion': _materialSpecController.text,
        'material_importacion_local_final': 'Local',
        'estado_desecho': 0,
        'ubicacion_destino': _ubicacionDestinoController.text,
        'vendedor': _selectedVendor ?? '',
        'usuario_registro': _directEntryMode && _manualUserController.text.trim().isNotEmpty
            ? _manualUserController.text.trim()
            : AuthService.currentUser?.nombreCompleto ?? 'Desconocido',
        'unidad_medida': _unidadMedida,
      };

      final result = await ApiService.createWarehousing(data);
      if (result['success'] == true) {
        savedCount++;
      } else {
        errorCount++;
      }
    }

    // Cerrar indicador de carga
    if (mounted) Navigator.pop(context);

    if (mounted) {
      String message;
      Color bgColor;
      
      if (errorCount == 0) {
        message = '✓ $savedCount registros guardados en inventario';
        bgColor = Colors.green;
      } else {
        message = '⚠ $savedCount guardados, $errorCount con error';
        bgColor = Colors.orange;
      }
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: bgColor,
          duration: const Duration(seconds: 3),
        ),
      );
      
      // Limpiar formulario
      _clearForm();
      
      // Notificar que se guardaron datos para recargar la tabla
      widget.onDataSaved?.call();
    }
  }

  // Limpiar formulario (no limpia ubicación destino para escaneo continuo)
  void _clearForm() {
    setState(() {
      _materialOriginalCodeController.clear();
      _materialSpecController.clear();
      _partNumberController.clear();
      _packagingUnitController.clear();
      _currentQtyController.clear();
      _warehousingCodeController.clear();
      _materialCodeController.clear();
      // No limpiar _ubicacionDestinoController para mantenerlo entre entradas
      _unidadMedida = 'EA';
      // Reset tracking variables para permitir nueva selección
      _lastSelectedMaterialIndex = null;
      _lastScannedCode = '';
      // Limpiar etiquetas impresas para nueva sesión
      _printedLabels = [];
      // Limpiar ubicaciones rollos esperadas
      _expectedRollosLocations = [];
    });
    // Regresar focus al campo de escaneo después de limpiar
    _scanFocusNode.requestFocus();
  }

  Future<void> _loadMateriales() async {
    final materiales = await ApiService.getMateriales();
    if (mounted) {
      setState(() {
        _materiales = materiales;
      });
    }
  }
  
  /// Método público para recargar materiales desde afuera
  Future<void> reloadMateriales() async {
    await _loadMateriales();
    
    // Si hay un material seleccionado actualmente, actualizar sus configuraciones
    if (_partNumberController.text.isNotEmpty) {
      // Buscar el material actual en la lista actualizada
      final currentPartNumber = _partNumberController.text;
      final materialIndex = _materiales.indexWhere(
        (m) => m['numero_parte']?.toString() == currentPartNumber
      );
      
      if (materialIndex >= 0) {
        final material = _materiales[materialIndex];
        final assignInternalLot = material['asignar_lote_interno'] == 1 || material['asignar_lote_interno'] == true;

        setState(() {
          _assignInternalLot = assignInternalLot;
        });
      }
    }
  }

  // Generar código de almacenamiento (preview): PARTNUMBER-YYYYMMDD0001
  // Ahora es async y consulta la base de datos
  // NOTA: Usa getNextSequencePreview para NO afectar el cache del backend
  Future<String> _generateWarehousingCode(String partNumber) async {
    final now = DateTime.now();
    final dateStr = '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
    final key = '$partNumber-$dateStr';
    
    // Consultar la base de datos para obtener la siguiente secuencia (PREVIEW - no afecta cache)
    try {
      final result = await ApiService.getNextSequencePreview(partNumber, dateStr);
      final nextSeq = result['nextSequence'] as int? ?? 1;
      _secuencias[key] = nextSeq - 1; // Guardar la última secuencia usada (solo para preview)
      return result['nextCode'] as String? ?? '$partNumber-$dateStr${nextSeq.toString().padLeft(4, '0')}';
    } catch (e) {
      // Fallback si hay error
      final nextSeq = ((_secuencias[key] ?? 0) + 1).toString().padLeft(4, '0');
      return '$partNumber-$dateStr$nextSeq';
    }
  }

  void _onMaterialSelected(int index) async {
    if (index >= 0 && index < _materiales.length) {
      final material = _materiales[index];
      final partNumber = material['numero_parte']?.toString() ?? '';
      final unidadEmpaque = material['unidad_empaque']?.toString() ?? '';
      final codigoMaterial = material['codigo_material']?.toString() ?? '';
      final ubicacion = material['ubicacion_material']?.toString() ?? '';
      final unidadMedida = material['unidad_medida']?.toString() ?? 'EA';
      final ubicacionRollos = material['ubicacion_rollos']?.toString() ?? '';
      
      // Cargar versiones disponibles del material
      List<String> versions = [];
      final versionStr = material['version']?.toString() ?? '';
      if (versionStr.isNotEmpty) {
        versions = versionStr.split(',').map((v) => v.trim()).where((v) => v.isNotEmpty).toList();
      }
      
      // Cargar ubicaciones disponibles del material (separadas por coma)
      List<String> locations = [];
      if (ubicacion.isNotEmpty) {
        locations = ubicacion.split(',').map((v) => v.trim()).where((v) => v.isNotEmpty).toList();
      }
      
      // Cargar vendedores disponibles del material (separados por coma)
      final vendedor = material['vendedor']?.toString() ?? '';
      List<String> vendors = [];
      if (vendedor.isNotEmpty) {
        vendors = vendedor.split(',').map((v) => v.trim()).where((v) => v.isNotEmpty).toList();
      }
      
      // Mostrar campo de versión si el Part Number empieza con EAX O si tiene versiones configuradas
      final needsVersion = partNumber.toUpperCase().startsWith('EAX') || versions.isNotEmpty;
      
      // Obtener configuración de lote interno (definida por Supervisores en Material Control)
      final assignInternalLot = material['assign_internal_lot'] == 1 || material['assign_internal_lot'] == true;
      
      setState(() {
        _materialSpecController.text = material['especificacion_material']?.toString() ?? '';
        _partNumberController.text = partNumber;
        _packagingUnitController.text = unidadEmpaque;
        _currentQtyController.text = unidadEmpaque;
        _materialCodeController.text = codigoMaterial;
        // Configurar ubicaciones
        _availableLocations = locations;
        _selectedLocation = locations.isNotEmpty ? locations.first : null;
        _locationController.text = _selectedLocation ?? '';
        // Configurar vendedores
        _availableVendors = vendors;
        _selectedVendor = vendors.isNotEmpty ? vendors.first : null;
        _currentPartNumber = partNumber;
        _warehousingCodeController.text = 'Cargando...';
        _requiresPcbVersion = needsVersion;
        _availablePcbVersions = versions;
        _selectedPcbVersion = null; // Reset selection
        _pcbVersionController.clear(); // Limpiar versión anterior
        _assignInternalLot = assignInternalLot; // Auto-set from Material Control config
        _unidadMedida = unidadMedida; // Set unit of measure from material
        // Guardar ubicaciones rollos esperadas para validación (multi-valor)
        _expectedRollosLocations = ubicacionRollos.isNotEmpty
            ? ubicacionRollos.split(',').map((v) => v.trim()).where((v) => v.isNotEmpty).toList()
            : [];
      });
      
      // Generar código de almacenamiento consultando la DB
      if (partNumber.isNotEmpty) {
        final code = await _generateWarehousingCode(partNumber);
        if (mounted) {
          setState(() {
            _warehousingCodeController.text = code;
          });
        }
      }
    }
  }

  // Convertir materiales a formato de filas para TableDropdownField
  List<List<String>> get _materialesRows {
    return _materiales.map((m) => [
      m['codigo_material']?.toString() ?? '',
      m['numero_parte']?.toString() ?? '',
      m['especificacion_material']?.toString() ?? '',
    ]).toList();
  }

  @override
  Widget build(BuildContext context) {
    final tr = widget.languageProvider.tr;
    return Container(
      color: AppColors.panelBackground,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: ConstrainedBox(
                constraints: BoxConstraints(minWidth: MediaQuery.of(context).size.width - 32),
                child: IntrinsicWidth(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Fila 1: Customer + Material Original Code
                      Row(
                        children: [
                          SizedBox(
                            width: 130,
                            child: Text(tr('customer'), style: const TextStyle(fontSize: 14, color: Colors.white)),
                          ),
                          const SizedBox(width: 50),
                          SizedBox(
                            width: 350,
                            child: DropdownButtonFormField2<String>(
                              decoration: fieldDecoration(),
                              value: _selectedCliente,
                              isExpanded: true,
                              items: const [
                                DropdownMenuItem(
                                  value: 'REFRIS',
                                  child: Text('REFRIS', style: TextStyle(fontSize: 14)),
                                ),
                                DropdownMenuItem(
                                  value: 'OVEN',
                                  child: Text('OVEN', style: TextStyle(fontSize: 14)),
                                ),
                                DropdownMenuItem(
                                  value: 'OTROS',
                                  child: Text('OTROS', style: TextStyle(fontSize: 14)),
                                ),
                              ],
                              onChanged: (value) {
                                if (value != null) {
                                  setState(() => _selectedCliente = value);
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
                          const SizedBox(width: 18),
                          SizedBox(
                            width: 160,
                            child: Text(tr('material_original_code'), style: const TextStyle(fontSize: 14, color: Colors.white)),
                          ),
                          SizedBox(
                            width: 400,
                            child: TextFormField(
                              controller: _materialOriginalCodeController,
                              focusNode: _scanFocusNode,
                              decoration: fieldDecoration().copyWith(
                                hintText: tr('scan_code'),
                                hintStyle: const TextStyle(fontSize: 12, color: Colors.white38),
                              ),
                              style: const TextStyle(fontSize: 14),
                              onFieldSubmitted: (_) {
                                // Forzar búsqueda inmediata cuando presione Enter
                                _forceSearch();
                                // Regresar focus al campo de escaneo
                                _scanFocusNode.requestFocus();
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      // Fila 3: Material Code + Material Consigned + Warehousing Date
                      Row(
                        children: [
                          SizedBox(
                            width: 130,
                            child: Text(tr('material_code'), style: const TextStyle(fontSize: 14, color: Colors.white)),
                          ),
                          const SizedBox(width: 50),
                          SizedBox(
                            width: 350,
                            child: TableDropdownField(
                              value: '',
                              headers: [tr('code'), tr('name'), tr('spec')],
                              rows: _materialesRows,
                              onRowSelected: _onMaterialSelected,
                              tableWidth: 600,
                            ),
                          ),
                          const SizedBox(width: 20),
                          SizedBox(
                            width: 130,
                            child: Text(tr('warehousing_date'), style: const TextStyle(fontSize: 14, color: Colors.white)),
                          ),
                          const SizedBox(width: 28),
                          SizedBox(
                            width: 400,
                            child: TextFormField(
                              controller: _warehousingDateController,
                              decoration: fieldDecoration().copyWith(
                                suffixIcon: IconButton(
                                  icon: const Icon(Icons.calendar_today, color: Colors.white70, size: 18),
                                  onPressed: () async {
                                    final date = await showDatePicker(
                                      context: context,
                                      initialDate: DateTime.now(),
                                      firstDate: DateTime(2000),
                                      lastDate: DateTime(2100),
                                    );
                                    if (date != null) {
                                      setState(() {
                                        _warehousingDateController.text = _formatDate(date);
                                      });
                                    }
                                  },
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                ),
                                suffixIconConstraints: const BoxConstraints(minWidth: 30, minHeight: 20),
                              ),
                              style: const TextStyle(fontSize: 14),
                              readOnly: true,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      // Fila 4: Making Date + Current Qty + Material LotNo
                      Row(
                        children: [
                          SizedBox(
                            width: 130,
                            child: Text(tr('making_date'), style: const TextStyle(fontSize: 14, color: Colors.white)),
                          ),
                          const SizedBox(width: 50),
                          SizedBox(
                            width: 350,
                            child: TextFormField(
                              controller: _makingDateController,
                              decoration: fieldDecoration().copyWith(
                                suffixIcon: IconButton(
                                  icon: const Icon(Icons.calendar_today, color: Colors.white70, size: 18),
                                  onPressed: () async {
                                    final date = await showDatePicker(
                                      context: context,
                                      initialDate: DateTime.now(),
                                      firstDate: DateTime(2000),
                                      lastDate: DateTime(2100),
                                    );
                                    if (date != null) {
                                      setState(() {
                                        _makingDateController.text = _formatDate(date);
                                      });
                                    }
                                  },
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                ),
                                suffixIconConstraints: const BoxConstraints(minWidth: 30, minHeight: 20),
                              ),
                              style: const TextStyle(fontSize: 14),
                              readOnly: true,
                            ),
                          ),
                          const SizedBox(width: 20),
                          SizedBox(
                            width: 140,
                            child: Text(tr('current_qty'), style: const TextStyle(fontSize: 14, color: Colors.white)),
                          ),
                          const SizedBox(width: 18),
                          SizedBox(
                            width: 350,
                            child: TextFormField(
                              controller: _currentQtyController,
                              decoration: fieldDecoration(),
                              style: const TextStyle(fontSize: 14),
                              keyboardType: TextInputType.number,
                            ),
                          ),
                          // Unit of measure display
                          Container(
                            width: 40,
                            padding: const EdgeInsets.only(left: 8),
                            child: Text(
                              _unidadMedida,
                              style: const TextStyle(fontSize: 14, color: Colors.cyan, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      // Fila 5: Vendor + Destination Location
                      Row(
                        children: [
                          SizedBox(
                            width: 130,
                            child: Text(tr('vendor'), style: const TextStyle(fontSize: 14, color: Colors.white)),
                          ),
                          const SizedBox(width: 50),
                          SizedBox(
                            width: 350,
                            child: _availableVendors.isNotEmpty
                                ? DropdownButtonFormField2<String>(
                                    decoration: fieldDecoration(),
                                    value: _selectedVendor,
                                    isExpanded: true,
                                    hint: Text(tr('select_vendor'), style: const TextStyle(fontSize: 12, color: Colors.white38)),
                                    style: const TextStyle(fontSize: 14, color: Colors.white),
                                    items: _availableVendors.map((vendor) => DropdownMenuItem(
                                      value: vendor,
                                      child: Text(vendor, style: const TextStyle(fontSize: 14)),
                                    )).toList(),
                                    onChanged: (value) {
                                      setState(() {
                                        _selectedVendor = value;
                                      });
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
                                    ),
                                  )
                                : TextFormField(
                                    decoration: fieldDecoration(hintText: tr('no_vendors_configured')),
                                    style: const TextStyle(fontSize: 14, color: Colors.white54),
                                    readOnly: true,
                                  ),
                          ),
                          const SizedBox(width: 20),
                          SizedBox(
                            width: 140,
                            child: Text(tr('destination_location'), style: const TextStyle(fontSize: 14, color: Colors.white)),
                          ),
                          const SizedBox(width: 18),
                          Expanded(
                            flex: 2,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                TextFormField(
                                  controller: _ubicacionDestinoController,
                                  focusNode: _ubicacionDestinoFocusNode,
                                  decoration: fieldDecoration().copyWith(
                                    hintText: tr('scan_destination'),
                                    hintStyle: const TextStyle(fontSize: 12, color: Colors.white38),
                                    prefixIcon: const Icon(Icons.qr_code_scanner, color: Colors.cyan, size: 18),
                                    prefixIconConstraints: const BoxConstraints(minWidth: 35, minHeight: 20),
                                  ),
                                  style: const TextStyle(fontSize: 14, color: Colors.cyan),
                                  onFieldSubmitted: (_) {
                                    // Regresar focus al campo de escaneo principal
                                    _scanFocusNode.requestFocus();
                                  },
                                ),
                                if (_expectedRollosLocations.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4, left: 8),
                                    child: Row(
                                      children: [
                                        const Icon(Icons.info_outline, size: 14, color: Colors.amber),
                                        const SizedBox(width: 4),
                                        Expanded(
                                          child: Wrap(
                                            spacing: 4,
                                            runSpacing: 2,
                                            crossAxisAlignment: WrapCrossAlignment.center,
                                            children: [
                                              Text(
                                                '${tr('expected_location')}:',
                                                style: const TextStyle(fontSize: 11, color: Colors.amber, fontWeight: FontWeight.w500),
                                              ),
                                              ..._expectedRollosLocations.map((loc) => Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                decoration: BoxDecoration(
                                                  color: Colors.amber.withOpacity(0.15),
                                                  borderRadius: BorderRadius.circular(4),
                                                  border: Border.all(color: Colors.amber.withOpacity(0.4)),
                                                ),
                                                child: Text(
                                                  loc,
                                                  style: const TextStyle(fontSize: 10, color: Colors.amber, fontWeight: FontWeight.w600),
                                                ),
                                              )),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          // Panel inferior (subpanel morado)
          Container(
            color: AppColors.subPanelBackground,
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    children: [
                      // Fila 1 del subpanel
                      Row(
                        children: [
                          SizedBox(
                            width: 180,
                            child: Text(tr('material_warehousing_code'), style: const TextStyle(fontSize: 14, color: Colors.white)),
                          ),
                          SizedBox(
                            width: 350,
                            child: TextFormField(
                              controller: _warehousingCodeController,
                              decoration: readOnlyFieldDecoration(),
                              style: const TextStyle(fontSize: 14, color: Colors.white54),
                              readOnly: true,
                            ),
                          ),
                          const SizedBox(width: 20),
                          SizedBox(
                            width: 100,
                            child: Text(tr('part_number'), style: const TextStyle(fontSize: 14, color: Colors.white)),
                          ),
                          const SizedBox(width: 60),
                          SizedBox(
                            width: _requiresPcbVersion ? 280 : 400,
                            child: TextFormField(
                              controller: _partNumberController,
                              decoration: readOnlyFieldDecoration(),
                              style: const TextStyle(fontSize: 14, color: Colors.white54),
                              readOnly: true,
                            ),
                          ),
                          // Campo de versión PCB (solo si Part Number empieza con EAX)
                          if (_requiresPcbVersion) ...[
                            const SizedBox(width: 8),
                            SizedBox(
                              width: 100,
                              child: _availablePcbVersions.isNotEmpty
                                  ? DropdownButtonFormField2<String>(
                                      decoration: fieldDecoration().copyWith(
                                        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                      ),
                                      value: _selectedPcbVersion,
                                      isExpanded: true,
                                      hint: const Text('-Ver-', style: TextStyle(fontSize: 12, color: Colors.white38)),
                                      style: const TextStyle(fontSize: 14, color: Colors.yellow),
                                      dropdownStyleData: DropdownStyleData(
                                        decoration: BoxDecoration(
                                          color: AppColors.panelBackground,
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                      ),
                                      items: _availablePcbVersions.map((v) => DropdownMenuItem(
                                        value: v,
                                        child: Text(v, style: const TextStyle(fontSize: 12)),
                                      )).toList(),
                                      onChanged: (value) {
                                        setState(() {
                                          _selectedPcbVersion = value;
                                          _pcbVersionController.text = value ?? '';
                                        });
                                      },
                                    )
                                  : TextFormField(
                                      controller: _pcbVersionController,
                                      decoration: fieldDecoration().copyWith(
                                        hintText: '-A, -B...',
                                        hintStyle: const TextStyle(fontSize: 12, color: Colors.white38),
                                      ),
                                      style: const TextStyle(fontSize: 14, color: Colors.yellow),
                                      textAlign: TextAlign.center,
                                    ),
                            ),
                          ],
                          const SizedBox(width: 20),
                          SizedBox(
                            width: 110,
                            child: Text(tr('packaging_unit'), style: const TextStyle(fontSize: 14, color: Colors.white)),
                          ),
                          const SizedBox(width: 20),
                          Expanded(
                            child: TextFormField(
                              controller: _packagingUnitController,
                              decoration: readOnlyFieldDecoration(),
                              style: const TextStyle(fontSize: 14, color: Colors.white54),
                              readOnly: true,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      // Fila 2 del subpanel
                      Row(
                        children: [
                          SizedBox(
                            width: 180,
                            child: Text(tr('material_code'), style: const TextStyle(fontSize: 14, color: Colors.white)),
                          ),
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
                            width: 100,
                            child: Text(tr('material_spec'), style: const TextStyle(fontSize: 14, color: Colors.white)),
                          ),
                          const SizedBox(width: 60),
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
                    ],
                  ),
                ),
                const SizedBox(width: 24),
                // Controles: Entrada Directa + Usuario + Auto Entry + Save
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Toggle entrada directa (con candado)
                    Row(
                      children: [
                        GestureDetector(
                          onTap: _toggleDirectEntry,
                          child: Row(
                            children: [
                              Icon(
                                _directEntryMode ? Icons.lock_open : Icons.lock,
                                color: _directEntryMode ? Colors.orange : Colors.white38,
                                size: 18,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'Entrada Directa',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: _directEntryMode ? Colors.orange : Colors.white38,
                                  fontWeight: _directEntryMode ? FontWeight.bold : FontWeight.normal,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    // Campo usuario manual (solo visible en modo directo)
                    if (_directEntryMode)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: SizedBox(
                          width: 150,
                          height: 30,
                          child: TextFormField(
                            controller: _manualUserController,
                            style: const TextStyle(fontSize: 12, color: Colors.orange),
                            decoration: InputDecoration(
                              hintText: 'Usuario',
                              hintStyle: const TextStyle(fontSize: 11, color: Colors.white30),
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                              enabledBorder: OutlineInputBorder(
                                borderSide: const BorderSide(color: Colors.orange, width: 1),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderSide: const BorderSide(color: Colors.orange, width: 1.5),
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                          ),
                        ),
                      ),
                    const SizedBox(height: 4),
                    // Checkbox entrada automática
                    Row(
                      children: [
                        SizedBox(
                          width: 20,
                          height: 20,
                          child: Checkbox(
                            value: _autoEntry,
                            onChanged: (value) {
                              setState(() => _autoEntry = value ?? false);
                              if (value == true) {
                                // Al activar, poner focus en campo de escaneo
                                _scanFocusNode.requestFocus();
                              }
                            },
                            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                        ),
                        const SizedBox(width: 6),
                        GestureDetector(
                          onTap: () {
                            setState(() => _autoEntry = !_autoEntry);
                            if (_autoEntry) _scanFocusNode.requestFocus();
                          },
                          child: Text(
                            tr('auto_entry'),
                            style: const TextStyle(fontSize: 12, color: Colors.white70),
                          ),
                        ),
                      ],
                    ),
                    // Indicador de cola
                    if (_scanQueue.isNotEmpty || _processingQueue)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Row(
                          children: [
                            if (_processingQueue)
                              const SizedBox(
                                width: 12,
                                height: 12,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                            const SizedBox(width: 4),
                            Text(
                              '${_scanQueue.length} en cola',
                              style: const TextStyle(fontSize: 11, color: Colors.cyan),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: 120,
                      height: 40,
                      child: Tooltip(
                        message: AuthService.canWriteWarehousing ? '' : 'No tienes permiso para crear entradas',
                        child: ElevatedButton(
                          onPressed: AuthService.canWriteWarehousing 
                              ? _confirmWarehouseEntry
                              : null,
                          style: ElevatedButton.styleFrom(
                            padding: EdgeInsets.zero,
                            backgroundColor: AuthService.canWriteWarehousing 
                                ? AppColors.buttonSave 
                                : Colors.grey,
                            disabledBackgroundColor: Colors.grey.shade700,
                          ),
                          child: Text(tr('save'),
                              style: const TextStyle(fontSize: 14)),
                        ),
                      ),
                    ),
                  ],
                )
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// Widget para el diálogo de asignación de etiquetas
class _LabelAssignmentDialog extends StatefulWidget {
  final List<String> labels;
  final Map<String, String> labelLotMap;
  final String partNumber;
  final LanguageProvider languageProvider;
  final Function(Map<String, String> assigned, List<String> unassigned) onComplete;

  const _LabelAssignmentDialog({
    required this.labels,
    required this.labelLotMap,
    required this.partNumber,
    required this.languageProvider,
    required this.onComplete,
  });

  @override
  State<_LabelAssignmentDialog> createState() => _LabelAssignmentDialogState();
}

class _LabelAssignmentDialogState extends State<_LabelAssignmentDialog> {
  final TextEditingController _labelScanController = TextEditingController();
  final TextEditingController _lotScanController = TextEditingController();
  final FocusNode _labelFocusNode = FocusNode();
  final FocusNode _lotFocusNode = FocusNode();
  
  String? _currentScannedLabel;
  final Map<String, String> _assignedLabels = {};
  
  // Modo Multi-Lote
  bool _multiLotMode = false;
  final Set<String> _selectedLabels = {};  // Etiquetas seleccionadas para multi-lote
  final TextEditingController _multiLotController = TextEditingController();
  int? _lastSelectedIndex; // Para selección con Shift
  
  @override
  void initState() {
    super.initState();
    // Enfocar el campo de etiqueta al inicio
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _labelFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _labelScanController.dispose();
    _lotScanController.dispose();
    _labelFocusNode.dispose();
    _lotFocusNode.dispose();
    _multiLotController.dispose();
    super.dispose();
  }
  
  // Aplicar lote a todas las etiquetas seleccionadas
  void _applyMultiLot() {
    final lot = _multiLotController.text.trim();
    if (lot.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('❌ Ingrese un lote'), backgroundColor: Colors.red, duration: Duration(milliseconds: 800)),
      );
      return;
    }
    if (_selectedLabels.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('❌ Seleccione etiquetas primero'), backgroundColor: Colors.red, duration: Duration(milliseconds: 800)),
      );
      return;
    }
    
    final count = _selectedLabels.length;
    setState(() {
      for (final label in _selectedLabels) {
        _assignedLabels[label] = lot;
      }
      _selectedLabels.clear();
      _multiLotController.clear();
    });
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('✓ Lote "$lot" asignado a $count etiquetas'), backgroundColor: Colors.green, duration: const Duration(seconds: 1)),
    );
    
    _labelFocusNode.requestFocus();
  }
  
  // Desasignar lote de una etiqueta
  void _unassignLot(String label) {
    setState(() {
      _assignedLabels.remove(label);
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Lote desasignado de $label'), backgroundColor: Colors.orange, duration: const Duration(milliseconds: 800)),
    );
    // Regresar focus al campo de escaneo para continuar escaneando
    _labelFocusNode.requestFocus();
  }
  
  // Toggle selección manual de etiqueta con soporte para Shift+click
  void _toggleManualSelect(String label, {int? index, bool isShiftPressed = false}) {
    if (_assignedLabels.containsKey(label)) return;
    
    final pendingLabels = widget.labels.where((l) => !_assignedLabels.containsKey(l)).toList();
    
    setState(() {
      if (isShiftPressed && _lastSelectedIndex != null && index != null) {
        // Selección en rango con Shift
        final start = _lastSelectedIndex! < index ? _lastSelectedIndex! : index;
        final end = _lastSelectedIndex! > index ? _lastSelectedIndex! : index;
        for (int i = start; i <= end; i++) {
          if (i >= 0 && i < pendingLabels.length && !_assignedLabels.containsKey(pendingLabels[i])) {
            _selectedLabels.add(pendingLabels[i]);
          }
        }
        _lastSelectedIndex = index;
      } else {
        // Selección individual normal
        if (_selectedLabels.contains(label)) {
          _selectedLabels.remove(label);
        } else {
          _selectedLabels.add(label);
        }
        _lastSelectedIndex = index;
      }
    });
  }
  
  // Seleccionar/deseleccionar todas las pendientes
  void _toggleSelectAll() {
    final pendingLabels = widget.labels.where((l) => !_assignedLabels.containsKey(l)).toList();
    
    setState(() {
      if (_selectedLabels.length == pendingLabels.length) {
        _selectedLabels.clear();
      } else {
        _selectedLabels.clear();
        _selectedLabels.addAll(pendingLabels);
      }
    });
  }

  void _onLabelScanned(String scannedValue) {
    if (scannedValue.isEmpty) return;
    
    // Buscar si la etiqueta escaneada coincide con alguna de las generadas
    final matchedLabel = widget.labels.firstWhere(
      (label) => scannedValue.toUpperCase().contains(label.toUpperCase()) || 
                 label.toUpperCase().contains(scannedValue.toUpperCase()) ||
                 scannedValue.toUpperCase() == label.toUpperCase(),
      orElse: () => '',
    );

    // MODO MULTI-LOTE: agregar/quitar de selección
    if (_multiLotMode) {
      if (matchedLabel.isNotEmpty && !_assignedLabels.containsKey(matchedLabel)) {
        setState(() {
          if (_selectedLabels.contains(matchedLabel)) {
            _selectedLabels.remove(matchedLabel);
          } else {
            _selectedLabels.add(matchedLabel);
          }
          _labelScanController.clear();
        });
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${_selectedLabels.length} etiquetas seleccionadas'),
            backgroundColor: Colors.purple,
            duration: const Duration(milliseconds: 600),
          ),
        );
        _labelFocusNode.requestFocus();
      } else if (matchedLabel.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('❌ Etiqueta no encontrada'), backgroundColor: Colors.red, duration: Duration(milliseconds: 800)),
        );
        _labelScanController.clear();
        _labelFocusNode.requestFocus();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('⚠ Etiqueta ya asignada'), backgroundColor: Colors.orange, duration: Duration(milliseconds: 800)),
        );
        _labelScanController.clear();
        _labelFocusNode.requestFocus();
      }
      return;
    }

    // MODO NORMAL: flujo individual
    if (matchedLabel.isNotEmpty && !_assignedLabels.containsKey(matchedLabel)) {
      setState(() {
        _currentScannedLabel = matchedLabel;
        _labelScanController.clear();
      });
      // Mover foco al campo de lote después de que el widget se reconstruya
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _lotFocusNode.requestFocus();
        }
      });
    } else if (matchedLabel.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('❌ Etiqueta no encontrada'), backgroundColor: Colors.red, duration: Duration(milliseconds: 800)),
      );
      _labelScanController.clear();
      _labelFocusNode.requestFocus();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('⚠ Etiqueta ya asignada'), backgroundColor: Colors.orange, duration: Duration(milliseconds: 800)),
      );
      _labelScanController.clear();
      _labelFocusNode.requestFocus();
    }
  }

  void _onLotScanned(String lotValue) {
    if (_currentScannedLabel != null && lotValue.isNotEmpty) {
      setState(() {
        _assignedLabels[_currentScannedLabel!] = lotValue;
        _currentScannedLabel = null;
        _lotScanController.clear();
      });
      
      // Mostrar confirmación rápida
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✓ Asignada (${_assignedLabels.length}/${widget.labels.length})'),
          backgroundColor: Colors.green,
          duration: const Duration(milliseconds: 600),
        ),
      );
      
      // Volver al campo de etiqueta después de que el widget se reconstruya
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _labelFocusNode.requestFocus();
        }
      });
      
      // Si ya se asignaron todas, mostrar mensaje
      if (_assignedLabels.length == widget.labels.length) {
        Future.delayed(const Duration(milliseconds: 700), () {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(widget.languageProvider.tr('all_labels_assigned')),
                backgroundColor: Colors.blue,
                duration: const Duration(seconds: 2),
              ),
            );
          }
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final pendingLabels = widget.labels.where((l) => !_assignedLabels.containsKey(l)).toList();
    String tr(String key) => widget.languageProvider.tr(key);
    
    return AlertDialog(
      backgroundColor: AppColors.panelBackground,
      title: Row(
        children: [
          const Icon(Icons.qr_code_scanner, color: Colors.white70),
          const SizedBox(width: 8),
          Text(tr('label_assignment'), style: const TextStyle(color: Colors.white, fontSize: 18)),
          const Spacer(),
          // Toggle Multi-Lote (incluye selección manual)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: _multiLotMode ? Colors.purple.withOpacity(0.3) : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _multiLotMode ? Colors.purple : Colors.white24),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.layers, color: _multiLotMode ? Colors.purple : Colors.white54, size: 16),
                const SizedBox(width: 4),
                Text('Multi-Lote', style: TextStyle(color: _multiLotMode ? Colors.purple : Colors.white54, fontSize: 12)),
                Switch(
                  value: _multiLotMode,
                  onChanged: (v) {
                    setState(() {
                      _multiLotMode = v;
                      _selectedLabels.clear();
                      _multiLotController.clear();
                      _currentScannedLabel = null;
                    });
                  },
                  activeColor: Colors.purple,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.buttonSave,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '${_assignedLabels.length}/${widget.labels.length}',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 700,
        height: 500,
        child: Column(
          children: [
            // Campos de escaneo - cambian según el modo
            if (_multiLotMode)
              // MODO MULTI-LOTE
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Escanear etiquetas (${_selectedLabels.length} seleccionadas)', style: const TextStyle(color: Colors.purple, fontSize: 12, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 4),
                        TextField(
                          controller: _labelScanController,
                          focusNode: _labelFocusNode,
                          autofocus: true,
                          style: const TextStyle(color: Colors.white, fontSize: 16),
                          decoration: InputDecoration(
                            hintText: 'Escanear etiquetas para seleccionar...',
                            hintStyle: const TextStyle(color: Colors.white38, fontSize: 12),
                            filled: true,
                            fillColor: Colors.purple.withOpacity(0.15),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(4),
                              borderSide: const BorderSide(color: Colors.purple),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(4),
                              borderSide: const BorderSide(color: Colors.purple, width: 2),
                            ),
                            prefixIcon: const Icon(Icons.qr_code, color: Colors.purple),
                          ),
                          textInputAction: TextInputAction.next,
                          onSubmitted: _onLabelScanned,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Lote para todas las seleccionadas', style: const TextStyle(color: Colors.purple, fontSize: 12, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _multiLotController,
                                style: const TextStyle(color: Colors.white, fontSize: 16),
                                decoration: InputDecoration(
                                  hintText: 'Escribir o escanear lote...',
                                  hintStyle: const TextStyle(color: Colors.white38, fontSize: 12),
                                  filled: true,
                                  fillColor: _selectedLabels.isNotEmpty ? Colors.purple.withOpacity(0.15) : Colors.grey[800],
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(4),
                                    borderSide: BorderSide(color: _selectedLabels.isNotEmpty ? Colors.purple : AppColors.border),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(4),
                                    borderSide: const BorderSide(color: Colors.purple, width: 2),
                                  ),
                                  prefixIcon: const Icon(Icons.inventory, color: Colors.purple),
                                ),
                                onSubmitted: (_) => _applyMultiLot(),
                              ),
                            ),
                            const SizedBox(width: 8),
                            ElevatedButton(
                              onPressed: _selectedLabels.isNotEmpty ? _applyMultiLot : null,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.purple,
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
                              ),
                              child: Text('Aplicar (${_selectedLabels.length})'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              )
            else
              // MODO NORMAL
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${tr('scan_label')}', style: const TextStyle(color: Colors.white70, fontSize: 12)),
                        const SizedBox(height: 4),
                        TextField(
                          controller: _labelScanController,
                          focusNode: _labelFocusNode,
                          autofocus: true,
                          style: const TextStyle(color: Colors.white, fontSize: 16),
                          decoration: InputDecoration(
                            hintText: tr('scan_label_code'),
                            hintStyle: const TextStyle(color: Colors.white38, fontSize: 12),
                            filled: true,
                            fillColor: _currentScannedLabel == null ? Colors.green.withOpacity(0.15) : AppColors.fieldBackground,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(4),
                              borderSide: BorderSide(color: _currentScannedLabel == null ? Colors.green : AppColors.border),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(4),
                              borderSide: const BorderSide(color: Colors.green, width: 2),
                            ),
                            prefixIcon: const Icon(Icons.qr_code, color: Colors.green),
                          ),
                          textInputAction: TextInputAction.next,
                          onSubmitted: _onLabelScanned,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${tr('supplier_lot')}', style: const TextStyle(color: Colors.white70, fontSize: 12)),
                        const SizedBox(height: 4),
                        TextField(
                          controller: _lotScanController,
                          focusNode: _lotFocusNode,
                          enabled: _currentScannedLabel != null,
                          style: const TextStyle(color: Colors.white, fontSize: 16),
                          decoration: InputDecoration(
                            hintText: _currentScannedLabel != null ? tr('scan_code') : tr('scan_first'),
                            hintStyle: const TextStyle(color: Colors.white38, fontSize: 12),
                            filled: true,
                            fillColor: _currentScannedLabel != null ? Colors.blue.withOpacity(0.15) : Colors.grey[800],
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(4),
                              borderSide: BorderSide(color: _currentScannedLabel != null ? Colors.blue : AppColors.border),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(4),
                              borderSide: const BorderSide(color: Colors.blue, width: 2),
                            ),
                            prefixIcon: Icon(Icons.inventory, color: _currentScannedLabel != null ? Colors.blue : Colors.white54),
                          ),
                          textInputAction: TextInputAction.done,
                          onSubmitted: _onLotScanned,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            
            // Etiqueta actual seleccionada (solo en modo normal)
            if (!_multiLotMode && _currentScannedLabel != null)
              Container(
                margin: const EdgeInsets.only(top: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.blue),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.label, color: Colors.blue),
                    const SizedBox(width: 8),
                    Text(
                      'Etiqueta seleccionada: $_currentScannedLabel',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            
            const SizedBox(height: 16),
            
            // Tabla de etiquetas
            Expanded(
              child: Row(
                children: [
                  // Etiquetas pendientes
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                          color: Colors.orange.withOpacity(0.3),
                          width: double.infinity,
                          child: Row(
                            children: [
                              Text(
                                '${tr('pending')} (${pendingLabels.length})',
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                              ),
                              const Spacer(),
                              // Botón seleccionar todas (en modo multi-lote)
                              if (_multiLotMode && pendingLabels.isNotEmpty)
                                TextButton.icon(
                                  onPressed: _toggleSelectAll,
                                  icon: Icon(
                                    _selectedLabels.length == pendingLabels.length
                                        ? Icons.deselect
                                        : Icons.select_all,
                                    size: 14,
                                    color: Colors.purple,
                                  ),
                                  label: Text(
                                    _selectedLabels.length == pendingLabels.length ? 'Ninguna' : 'Todas',
                                    style: const TextStyle(fontSize: 11, color: Colors.purple),
                                  ),
                                  style: TextButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(horizontal: 8),
                                    minimumSize: Size.zero,
                                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: Container(
                            decoration: BoxDecoration(
                              color: AppColors.fieldBackground,
                              border: Border.all(color: AppColors.border),
                            ),
                            child: ListView.builder(
                              itemCount: pendingLabels.length,
                              itemBuilder: (context, index) {
                                final label = pendingLabels[index];
                                final isSelected = _selectedLabels.contains(label);
                                
                                return InkWell(
                                  onTap: _multiLotMode ? () {
                                    final isShiftPressed = HardwareKeyboard.instance.isShiftPressed;
                                    _toggleManualSelect(label, index: index, isShiftPressed: isShiftPressed);
                                  } : null,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: isSelected ? Colors.purple.withOpacity(0.2) : null,
                                      border: Border(bottom: BorderSide(color: AppColors.border.withOpacity(0.3))),
                                    ),
                                    child: Row(
                                      children: [
                                        if (_multiLotMode)
                                          Checkbox(
                                            value: isSelected,
                                            onChanged: (_) {
                                              final isShiftPressed = HardwareKeyboard.instance.isShiftPressed;
                                              _toggleManualSelect(label, index: index, isShiftPressed: isShiftPressed);
                                            },
                                            activeColor: Colors.purple,
                                            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                            visualDensity: VisualDensity.compact,
                                          ),
                                        Expanded(
                                          child: Text(
                                            label,
                                            style: TextStyle(
                                              color: isSelected ? Colors.purple : Colors.orange,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  // Etiquetas asignadas
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          color: Colors.green.withOpacity(0.3),
                          width: double.infinity,
                          child: Text(
                            '  ${tr('assigned')} (${_assignedLabels.length})',
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                          ),
                        ),
                        Expanded(
                          child: Container(
                            decoration: BoxDecoration(
                              color: AppColors.fieldBackground,
                              border: Border.all(color: AppColors.border),
                            ),
                            child: ListView.builder(
                              itemCount: _assignedLabels.length,
                              itemBuilder: (context, index) {
                                final entry = _assignedLabels.entries.elementAt(index);
                                return Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    border: Border(bottom: BorderSide(color: AppColors.border.withOpacity(0.3))),
                                  ),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(entry.key, style: const TextStyle(color: Colors.green, fontSize: 11)),
                                            Text('Lote: ${entry.value}', style: const TextStyle(color: Colors.white54, fontSize: 10)),
                                          ],
                                        ),
                                      ),
                                      // Botón desasignar
                                      IconButton(
                                        icon: const Icon(Icons.link_off, color: Colors.orange, size: 16),
                                        onPressed: () => _unassignLot(entry.key),
                                        tooltip: 'Desasignar',
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(tr('cancel'), style: const TextStyle(color: Colors.white70)),
        ),
        ElevatedButton(
          onPressed: () {
            Navigator.pop(context);
            final unassigned = widget.labels.where((l) => !_assignedLabels.containsKey(l)).toList();
            widget.onComplete(_assignedLabels, unassigned);
          },
          style: ElevatedButton.styleFrom(backgroundColor: AppColors.buttonSave),
          child: Text(tr('finish')),
        ),
      ],
    );
  }
}

// Widget para mostrar progreso de impresión
class _PrintingProgressDialog extends StatefulWidget {
  final List<String> labels;
  final String fecha;
  final String especificacion;
  final String cantidad;
  final Function(int printedCount, int errorCount) onComplete;
  final LanguageProvider languageProvider;
  final int nivelMsl; // Nivel MSL del material para imprimir copia espejo

  const _PrintingProgressDialog({
    required this.labels,
    required this.fecha,
    required this.especificacion,
    required this.cantidad,
    required this.onComplete,
    required this.languageProvider,
    this.nivelMsl = 0, // Por defecto 0 (sin copia MSL)
  });

  @override
  State<_PrintingProgressDialog> createState() => _PrintingProgressDialogState();
}

class _PrintingProgressDialogState extends State<_PrintingProgressDialog> {
  int _currentIndex = 0;
  int _printedCount = 0;
  int _errorCount = 0;
  bool _isComplete = false;
  String _status = 'Preparando...';
  
  String tr(String key) => widget.languageProvider.tr(key);

  @override
  void initState() {
    super.initState();
    _startPrintingBatch();
  }

  /// Impresión en batch - envía todas las etiquetas de una vez
  Future<void> _startPrintingBatch() async {
    if (!mounted) return;
    
    setState(() {
      _status = 'Generando etiquetas...';
    });
    
    // Preparar lista de etiquetas para batch
    // Si nivelMsl >= 1, duplicar cada etiqueta para MSL mirror
    final List<Map<String, String>> labelsData = [];
    for (final label in widget.labels) {
      labelsData.add({'codigo': label});
      if (widget.nivelMsl >= 1) {
        labelsData.add({'codigo': label}); // Copia MSL espejo
      }
    }
    
    final mslInfo = widget.nivelMsl >= 1 ? ' (con copia MSL)' : '';
    print('>>> Iniciando impresión en BATCH de ${labelsData.length} etiquetas$mslInfo');
    
    // Usar el método batch del PrinterService
    final results = await PrinterService.printLabelsBatch(
      labels: labelsData,
      fecha: widget.fecha,
      especificacion: widget.especificacion,
      cantidadActual: widget.cantidad,
      onProgress: (current, total, label) {
        if (mounted) {
          setState(() {
            _currentIndex = current;
            _status = 'Preparando etiqueta $current de $total: $label';
          });
        }
      },
    );
    
    // Contar resultados
    _printedCount = results.values.where((success) => success).length;
    _errorCount = results.values.where((success) => !success).length;
    
    print('>>> Batch completado: $_printedCount impresas, $_errorCount errores');

    if (mounted) {
      setState(() {
        _isComplete = true;
        _currentIndex = widget.labels.length;
        _status = _errorCount == 0 
            ? '¡Todas las etiquetas enviadas!' 
            : '$_printedCount impresas, $_errorCount errores';
      });
      
      // Esperar un momento para mostrar el resultado
      await Future.delayed(const Duration(milliseconds: 800));
      
      if (mounted) {
        Navigator.pop(context);
        widget.onComplete(_printedCount, _errorCount);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.panelBackground,
      title: Row(
        children: [
          Icon(
            _isComplete ? Icons.check_circle : Icons.print,
            color: _isComplete 
              ? (_errorCount == 0 ? Colors.green : Colors.orange)
              : Colors.blue,
          ),
          const SizedBox(width: 8),
          Text(
            _isComplete ? tr('print_completed') : tr('printing_labels'),
            style: const TextStyle(color: Colors.white, fontSize: 18),
          ),
        ],
      ),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Barra de progreso
            LinearProgressIndicator(
              value: widget.labels.isEmpty ? 0 : _currentIndex / widget.labels.length,
              backgroundColor: Colors.grey[800],
              valueColor: AlwaysStoppedAnimation<Color>(
                _errorCount > 0 ? Colors.orange : Colors.green,
              ),
            ),
            const SizedBox(height: 16),
            
            // Contador
            Text(
              '$_currentIndex / ${widget.labels.length}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            
            // Etiqueta actual
            if (!_isComplete)
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.fieldBackground,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  _status,
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                  textAlign: TextAlign.center,
                ),
              ),
            
            const SizedBox(height: 16),
            
            // Resumen
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.check, color: Colors.green, size: 16),
                      const SizedBox(width: 4),
                      Text(
                        '$_printedCount ${tr('printed')}',
                        style: const TextStyle(color: Colors.green, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                if (_errorCount > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.error, color: Colors.red, size: 16),
                        const SizedBox(width: 4),
                        Text(
                          '$_errorCount ${tr('errors')}',
                          style: const TextStyle(color: Colors.red, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
