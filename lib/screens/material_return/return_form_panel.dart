import 'package:flutter/material.dart';
import 'package:material_warehousing_flutter/core/localization/app_translations.dart';
import 'package:material_warehousing_flutter/core/theme/app_colors.dart';
import 'package:material_warehousing_flutter/core/widgets/field_decoration.dart';
import 'package:material_warehousing_flutter/core/widgets/printer_settings_dialog.dart';
import 'package:material_warehousing_flutter/core/services/api_service.dart';
import 'package:material_warehousing_flutter/core/services/printer_service.dart';
import 'package:material_warehousing_flutter/core/services/auth_service.dart';
import 'return_grid_panel.dart';

class ReturnFormPanel extends StatefulWidget {
  final LanguageProvider languageProvider;
  final VoidCallback? onDataSaved;
  final GlobalKey<ReturnGridPanelState>? gridKey;
  
  const ReturnFormPanel({
    super.key, 
    required this.languageProvider,
    this.onDataSaved,
    this.gridKey,
  });

  @override
  State<ReturnFormPanel> createState() => ReturnFormPanelState();
}

class ReturnFormPanelState extends State<ReturnFormPanel> {
  // Controladores
  final TextEditingController _warehousingCodeController = TextEditingController();
  final TextEditingController _materialCodeController = TextEditingController();
  final TextEditingController _materialSpecController = TextEditingController();
  final TextEditingController _partNumberController = TextEditingController();
  final TextEditingController _packagingUnitController = TextEditingController();
  final TextEditingController _remainQtyController = TextEditingController();
  final TextEditingController _returnQtyController = TextEditingController();
  final TextEditingController _reasonController = TextEditingController();
  final TextEditingController _locationController = TextEditingController();
  
  // FocusNode para el campo de escaneo principal
  final FocusNode _scanFocusNode = FocusNode();
  
  // Datos de la entrada encontrada
  int? _warehousingId;
  String? _materialLotNo;
  
  // Ubicaciones disponibles del material
  List<String> _availableLocations = [];
  String? _selectedLocation;
  
  // Verificar si el usuario puede escribir
  bool get _canWrite => AuthService.canWriteMaterialReturn;
  
  String tr(String key) => widget.languageProvider.tr(key);

  @override
  void initState() {
    super.initState();
    // Auto-focus inicial en el campo de escaneo
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scanFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _warehousingCodeController.dispose();
    _materialCodeController.dispose();
    _materialSpecController.dispose();
    _partNumberController.dispose();
    _packagingUnitController.dispose();
    _remainQtyController.dispose();
    _returnQtyController.dispose();
    _reasonController.dispose();
    _locationController.dispose();
    _scanFocusNode.dispose();
    super.dispose();
  }

  /// Método público para recuperar el focus en el campo de escaneo
  /// Se llama de forma no invasiva - solo si ningún otro campo tiene focus activo
  void requestScanFocus() {
    final currentFocus = FocusManager.instance.primaryFocus;
    final isTextFieldFocused = currentFocus?.context?.widget is EditableText;
    
    if (!isTextFieldFocused) {
      _scanFocusNode.requestFocus();
    }
  }
  
  /// Forzar focus en el campo de escaneo (después de operaciones importantes)
  void forceScanFocus() {
    _scanFocusNode.requestFocus();
  }

  // Buscar entrada por código de almacenamiento
  Future<void> _searchWarehousingCode() async {
    final code = _warehousingCodeController.text.trim();
    if (code.isEmpty) return;
    
    try {
      // forReturn: true valida que el lote tenga salidas previas
      final data = await ApiService.getWarehousingByCode(code, forReturn: true);
      
      if (data != null) {
        // Cargar ubicaciones disponibles del material (separadas por coma)
        final ubicacion = data['location']?.toString() ?? '';
        List<String> locations = [];
        if (ubicacion.isNotEmpty) {
          locations = ubicacion.split(',').map((v) => v.trim()).where((v) => v.isNotEmpty).toList();
        }
        
        // Usar la ubicación guardada en el registro, o la primera disponible
        final savedLocation = data['ubicacion_salida']?.toString() ?? '';
        String? selectedLoc;
        if (savedLocation.isNotEmpty && locations.contains(savedLocation)) {
          selectedLoc = savedLocation;
        } else if (locations.isNotEmpty) {
          selectedLoc = locations.first;
        }
        
        setState(() {
          _warehousingId = data['id'];
          _materialCodeController.text = data['codigo_material']?.toString() ?? '';
          _partNumberController.text = data['numero_parte']?.toString() ?? '';
          _materialLotNo = data['numero_lote_material']?.toString();
          _packagingUnitController.text = data['cantidad_estandarizada']?.toString() ?? '';
          _remainQtyController.text = data['cantidad_actual']?.toString() ?? '0';
          _materialSpecController.text = data['especificacion']?.toString() ?? '';
          _availableLocations = locations;
          _selectedLocation = selectedLoc;
          _locationController.text = selectedLoc ?? '';
        });
      } else {
        _clearForm();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(tr('warehousing_not_found')),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _clearForm() {
    setState(() {
      _warehousingId = null;
      _materialLotNo = null;
      _materialCodeController.clear();
      _partNumberController.clear();
      _packagingUnitController.clear();
      _remainQtyController.clear();
      _returnQtyController.clear();
      _materialSpecController.clear();
      _reasonController.clear();
      _locationController.clear();
      _availableLocations = [];
      _selectedLocation = null;
    });
    // Regresar focus al campo de escaneo después de limpiar
    _scanFocusNode.requestFocus();
  }

  Future<void> _saveReturn() async {
    // Validaciones
    if (_warehousingId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr('scan_warehousing_code_first')), backgroundColor: Colors.red),
      );
      return;
    }
    
    final returnQty = int.tryParse(_returnQtyController.text) ?? 0;
    final remainQty = int.tryParse(_remainQtyController.text) ?? 0;
    
    if (returnQty <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr('enter_valid_return_qty')), backgroundColor: Colors.red),
      );
      return;
    }
    
    // Confirmar la devolución
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.panelBackground,
        title: Text(tr('confirm_return'), style: const TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${tr('code')}: ${_warehousingCodeController.text}', 
                style: const TextStyle(color: Colors.white70)),
            Text('${tr('part_number')}: ${_partNumberController.text}', 
                style: const TextStyle(color: Colors.white70)),
            const SizedBox(height: 8),
            Text('${tr('return_qty')}: $returnQty', 
                style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(tr('cancel'), style: const TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.buttonSave),
            child: Text(tr('confirm')),
          ),
        ],
      ),
    );
    
    if (confirm != true) return;
    
    // Guardar
    try {
      final data = {
        'warehousing_id': _warehousingId,
        'material_warehousing_code': _warehousingCodeController.text,
        'material_code': _materialCodeController.text,
        'part_number': _partNumberController.text,
        'material_lot_no': _materialLotNo,
        'packaging_unit': _packagingUnitController.text,
        'material_spec': _materialSpecController.text,
        'remain_qty': remainQty,
        'return_qty': returnQty,
        'loss_qty': 0,
        'returned_by': AuthService.currentUser?.nombreCompleto ?? 'Unknown',
        'returned_by_id': AuthService.currentUser?.id,
        'remarks': _reasonController.text.trim().isEmpty ? null : _reasonController.text.trim(),
      };
      
      final result = await ApiService.createReturn(data);
      
      if (result['success'] == true && mounted) {
        // Usar la nueva cantidad del backend (calculada desde la BD)
        // El API devuelve {success: true, data: {new_qty: ...}}
        final responseData = result['data'] as Map<String, dynamic>?;
        final newQty = responseData?['new_qty'] ?? returnQty;
        final now = DateTime.now();
        final fecha = '${now.year}/${now.month.toString().padLeft(2, '0')}/${now.day.toString().padLeft(2, '0')}';
        
        await PrinterService.printLabel(
          codigo: _warehousingCodeController.text,
          fecha: fecha,
          especificacion: _materialSpecController.text,
          cantidadActual: newQty.toString(),
        );
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✓ ${tr('return_saved_successfully')}'),
            backgroundColor: Colors.green,
          ),
        );
        
        _clearForm();
        _warehousingCodeController.clear();
        widget.onDataSaved?.call();
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result['error']?.toString() ?? 'Error al guardar'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Fila 1: Material Warehousing Code (fondo gris)
        Container(
          color: AppColors.panelBackground,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              SizedBox(
                width: 180,
                child: Text(tr('material_warehousing_code'), 
                    style: const TextStyle(fontSize: 14, color: Colors.white)),
              ),
              SizedBox(
                width: 400,
                child: SizedBox(
                  height: 32,
                  child: TextFormField(
                    controller: _warehousingCodeController,
                    focusNode: _scanFocusNode,
                    enabled: _canWrite,
                    decoration: fieldDecoration().copyWith(
                      hintText: tr('scan_or_enter_code'),
                      hintStyle: const TextStyle(fontSize: 12, color: Colors.white38),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                      suffixIcon: InkWell(
                        onTap: _searchWarehousingCode,
                        child: const Padding(
                          padding: EdgeInsets.all(6),
                          child: Icon(Icons.search, color: Colors.white70, size: 16),
                        ),
                      ),
                      suffixIconConstraints: const BoxConstraints(maxHeight: 28, maxWidth: 28),
                    ),
                    style: const TextStyle(fontSize: 13),
                    onFieldSubmitted: (_) {
                      _searchWarehousingCode();
                      // Regresar focus al campo de escaneo después de buscar
                      _scanFocusNode.requestFocus();
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
        // Resto del formulario (fondo morado)
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
                      Row(
                        children: [
                          SizedBox(
                            width: 100,
                            child: Text(tr('material_code'), 
                                style: const TextStyle(fontSize: 14, color: Colors.white)),
                          ),
                          const SizedBox(width: 80),
                          SizedBox(
                            width: 400,
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
                            child: Text(tr('location'), 
                                style: const TextStyle(fontSize: 14, color: Colors.white)),
                          ),
                          SizedBox(
                            width: 200,
                            child: _availableLocations.isNotEmpty
                                ? DropdownButtonFormField<String>(
                                    value: _selectedLocation,
                                    decoration: fieldDecoration().copyWith(
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                    ),
                                    dropdownColor: AppColors.panelBackground,
                                    items: _availableLocations.map((loc) => DropdownMenuItem(
                                      value: loc,
                                      child: Text(loc, style: const TextStyle(fontSize: 13)),
                                    )).toList(),
                                    onChanged: _canWrite ? (value) {
                                      setState(() {
                                        _selectedLocation = value;
                                        _locationController.text = value ?? '';
                                      });
                                    } : null,
                                    style: const TextStyle(fontSize: 13, color: Colors.white),
                                  )
                                : TextFormField(
                                    controller: _locationController,
                                    decoration: readOnlyFieldDecoration(),
                                    style: const TextStyle(fontSize: 14, color: Colors.white54),
                                    readOnly: true,
                                  ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      // Fila: Material Spec
                      Row(
                        children: [
                          SizedBox(
                            width: 100,
                            child: Text(tr('material_spec'), 
                                style: const TextStyle(fontSize: 14, color: Colors.white)),
                          ),
                          const SizedBox(width: 80),
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
                      // Fila 3: Part Number
                      Row(
                        children: [
                          SizedBox(
                            width: 100,
                            child: Text(tr('part_number'), 
                                style: const TextStyle(fontSize: 14, color: Colors.white)),
                          ),
                          const SizedBox(width: 80),
                          SizedBox(
                            width: 400,
                            child: TextFormField(
                              controller: _partNumberController,
                              decoration: readOnlyFieldDecoration(),
                              style: const TextStyle(fontSize: 14, color: Colors.white54),
                              readOnly: true,
                            ),
                          ),
                          const SizedBox(width: 20),
                          SizedBox(
                            width: 100,
                            child: Text(tr('reason_optional'), 
                                style: const TextStyle(fontSize: 14, color: Colors.white70)),
                          ),
                          Expanded(
                            child: TextFormField(
                              controller: _reasonController,
                              enabled: _canWrite,
                              decoration: fieldDecoration().copyWith(
                                hintText: tr('reason_optional'),
                                hintStyle: const TextStyle(fontSize: 12, color: Colors.white38),
                              ),
                              style: const TextStyle(fontSize: 14),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      // Fila 4: Packaging Unit + Remain Qty + Return Qty
                      Row(
                        children: [
                          SizedBox(
                            width: 100,
                            child: Text(tr('packaging_unit'), 
                                style: const TextStyle(fontSize: 14, color: Colors.white)),
                          ),
                          const SizedBox(width: 80),
                          SizedBox(
                            width: 400,
                            child: TextFormField(
                              controller: _packagingUnitController,
                              decoration: readOnlyFieldDecoration(),
                              style: const TextStyle(fontSize: 14, color: Colors.white54),
                              readOnly: true,
                            ),
                          ),
                          const SizedBox(width: 20),
                          SizedBox(
                            width: 100,
                            child: Text(tr('remain_qty'), 
                                style: const TextStyle(fontSize: 14, color: Colors.white)),
                          ),
                          SizedBox(
                            width: 150,
                            child: TextFormField(
                              controller: _remainQtyController,
                              decoration: readOnlyFieldDecoration(),
                              style: const TextStyle(fontSize: 14, color: Colors.cyan),
                              readOnly: true,
                            ),
                          ),
                          const SizedBox(width: 20),
                          SizedBox(
                            width: 100,
                            child: Text(tr('return_qty'), 
                                style: const TextStyle(fontSize: 14, color: Colors.orange)),
                          ),
                          SizedBox(
                            width: 150,
                            child: TextFormField(
                              controller: _returnQtyController,
                              enabled: _canWrite,
                              decoration: fieldDecoration().copyWith(
                                filled: true,
                                fillColor: _canWrite ? Colors.orange.withOpacity(0.1) : Colors.grey.withOpacity(0.1),
                              ),
                              style: TextStyle(fontSize: 14, color: _canWrite ? Colors.orange : Colors.grey, fontWeight: FontWeight.bold),
                              keyboardType: TextInputType.number,
                            ),
                          ),
                          const Spacer(),
                          // Botones en la misma fila
                          SizedBox(
                            height: 36,
                            child: ElevatedButton(
                              onPressed: () => PrinterSettingsDialog.show(context),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.buttonGray,
                                padding: const EdgeInsets.symmetric(horizontal: 20),
                              ),
                              child: Text(tr('setting_printer'), style: const TextStyle(fontSize: 13)),
                            ),
                          ),
                          const SizedBox(width: 12),
                          SizedBox(
                            height: 36,
                            child: ElevatedButton(
                              onPressed: _canWrite ? _saveReturn : null,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _canWrite ? AppColors.buttonSave : Colors.grey,
                                padding: const EdgeInsets.symmetric(horizontal: 24),
                              ),
                              child: Text(tr('save'), style: const TextStyle(fontSize: 13)),
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
        ],
      );
  }
}