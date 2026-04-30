import 'package:flutter/material.dart';
import 'package:material_warehousing_flutter/core/localization/app_translations.dart';
import 'package:material_warehousing_flutter/core/theme/app_colors.dart';
import 'package:material_warehousing_flutter/core/services/api_service.dart';
import 'package:material_warehousing_flutter/core/services/auth_service.dart';

// ============================================
// Material Control Form Panel
// ============================================
class MaterialControlFormPanel extends StatefulWidget {
  final LanguageProvider languageProvider;
  final VoidCallback? onSaved;
  final VoidCallback? onCancelled;
  final bool isCreatingNew;
  
  const MaterialControlFormPanel({
    super.key,
    required this.languageProvider,
    this.onSaved,
    this.onCancelled,
    this.isCreatingNew = false,
  });

  @override
  State<MaterialControlFormPanel> createState() => MaterialControlFormPanelState();
}

class MaterialControlFormPanelState extends State<MaterialControlFormPanel> {
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;
  bool _isEditing = false;
  Map<String, dynamic>? _currentMaterial;
  
  // Controllers para los campos
  final _numeroParteController = TextEditingController();
  final _codigoMaterialController = TextEditingController();
  final _propiedadMaterialController = TextEditingController();
  final _clasificacionController = TextEditingController();
  final _especificacionController = TextEditingController();
  final _unidadEmpaqueController = TextEditingController();
  final _ubicacionController = TextEditingController();
  final _prohibidoSacarController = TextEditingController();
  final _nivelMslController = TextEditingController();
  final _espesorMslController = TextEditingController();
  final _versionInputController = TextEditingController();
  final _locationInputController = TextEditingController();
  final _vendorInputController = TextEditingController();
  final _comparacionController = TextEditingController();
  List<String> _ubicacionesRollos = [];
  final _ubicacionRollosInputController = TextEditingController();
  
  // Lista de versiones (PCB versions like -A, -B, -C)
  List<String> _versions = [];
  
  // Lista de ubicaciones
  List<String> _locations = [];
  
  // Lista de vendedores
  List<String> _vendors = [];
  
  // Unidad de medida
  String _unidadMedida = 'EA';
  static const List<String> _unidadMedidaOptions = ['EA', 'm', 'kg', 'g', 'mg'];
  
  // Campos checkbox
  bool _assignInternalLot = false;
  bool _dividirLote = true;  // Default true for new materials
  final _standardPackController = TextEditingController();
  String _fechaRegistro = '';
  String _usuarioRegistro = '';

  String tr(String key) => widget.languageProvider.tr(key);

  // Permisos de edición completa - Solo Almacén Supervisor y Sistemas
  bool get _canEditFull {
    final dept = AuthService.currentUser?.departamento ?? '';
    final hasPermission = AuthService.hasPermission('write_material_control');
    return dept == 'Almacén Supervisor' || dept == 'Sistemas' || hasPermission;
  }
  
  // Permiso para editar solo comparaciones
  bool get _canEditComparacion {
    return AuthService.hasPermission('write_comparacion');
  }
  
  // Puede editar algo (completo o solo comparación)
  bool get _canEdit => _canEditFull || _canEditComparacion;

  @override
  void dispose() {
    _numeroParteController.dispose();
    _codigoMaterialController.dispose();
    _propiedadMaterialController.dispose();
    _clasificacionController.dispose();
    _especificacionController.dispose();
    _unidadEmpaqueController.dispose();
    _ubicacionController.dispose();
    _prohibidoSacarController.dispose();
    _nivelMslController.dispose();
    _espesorMslController.dispose();
    _versionInputController.dispose();
    _locationInputController.dispose();
    _vendorInputController.dispose();
    _standardPackController.dispose();
    _comparacionController.dispose();
    _ubicacionRollosInputController.dispose();
    super.dispose();
  }

  void loadMaterial(Map<String, dynamic>? material) {
    setState(() {
      _currentMaterial = material;
      _isEditing = false;
      
      if (material != null) {
        _numeroParteController.text = material['numero_parte']?.toString() ?? '';
        _codigoMaterialController.text = material['codigo_material']?.toString() ?? '';
        _propiedadMaterialController.text = material['propiedad_material']?.toString() ?? '';
        _clasificacionController.text = material['clasificacion']?.toString() ?? '';
        _especificacionController.text = material['especificacion_material']?.toString() ?? '';
        _unidadEmpaqueController.text = material['unidad_empaque']?.toString() ?? '';
        // Parse locations from comma-separated string
        final ubicacionStr = material['ubicacion_material']?.toString() ?? '';
        _locations = ubicacionStr.isNotEmpty 
            ? ubicacionStr.split(',').map((v) => v.trim()).where((v) => v.isNotEmpty).toList()
            : [];
        _ubicacionController.text = ubicacionStr;
        // Parse vendors from comma-separated string
        final vendedorStr = material['vendedor']?.toString() ?? '';
        _vendors = vendedorStr.isNotEmpty 
            ? vendedorStr.split(',').map((v) => v.trim()).where((v) => v.isNotEmpty).toList()
            : [];
        _prohibidoSacarController.text = material['prohibido_sacar']?.toString() ?? '';
        _nivelMslController.text = material['nivel_msl']?.toString() ?? '';
        _espesorMslController.text = material['espesor_msl']?.toString() ?? '';
        // Parse versions from comma-separated string
        final versionStr = material['version']?.toString() ?? '';
        _versions = versionStr.isNotEmpty 
            ? versionStr.split(',').map((v) => v.trim()).where((v) => v.isNotEmpty).toList()
            : [];
        _unidadMedida = material['unidad_medida']?.toString() ?? 'EA';
        if (!_unidadMedidaOptions.contains(_unidadMedida)) {
          _unidadMedida = 'EA';
        }
        _assignInternalLot = material['assign_internal_lot'] == 1 || material['assign_internal_lot'] == '1';
        _dividirLote = material['dividir_lote'] == 1 || material['dividir_lote'] == '1' || material['dividir_lote'] == true;
        _standardPackController.text = material['standard_pack']?.toString() ?? '';
        _comparacionController.text = material['comparacion']?.toString() ?? '';
        final ubicacionRollosStr = material['ubicacion_rollos']?.toString() ?? '';
        _ubicacionesRollos = ubicacionRollosStr.isNotEmpty
            ? ubicacionRollosStr.split(',').map((v) => v.trim()).where((v) => v.isNotEmpty).toList()
            : [];
        _fechaRegistro = material['fecha_registro']?.toString() ?? '';
        _usuarioRegistro = material['usuario_registro']?.toString() ?? '';
      } else {
        clearForm();
      }
    });
  }
  
  void clearForm() {
    setState(() {
      _currentMaterial = null;
      _isEditing = widget.isCreatingNew;
      _numeroParteController.clear();
      _codigoMaterialController.clear();
      _propiedadMaterialController.clear();
      _clasificacionController.clear();
      _especificacionController.clear();
      _unidadEmpaqueController.clear();
      _ubicacionController.clear();
      _locations = [];
      _locationInputController.clear();
      _vendors = [];
      _vendorInputController.clear();
      _prohibidoSacarController.clear();
      _nivelMslController.clear();
      _espesorMslController.clear();
      _versions = [];
      _versionInputController.clear();
      _unidadMedida = 'EA';
      _assignInternalLot = false;
      _dividirLote = true;  // Default true for new materials
      _standardPackController.clear();
      _comparacionController.clear();
      _ubicacionesRollos = [];
      _ubicacionRollosInputController.clear();
      _fechaRegistro = '';
      _usuarioRegistro = '';
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    
    // Si solo tiene permiso de comparación, usar el flujo simplificado
    if (_canEditComparacion && !_canEditFull) {
      await _saveComparacionOnly();
      return;
    }
    
    // Validate standard_pack when dividir_lote is enabled
    if (_dividirLote && _standardPackController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(tr('standard_pack_required')),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    
    setState(() => _isLoading = true);
    
    try {
      final data = {
        'numero_parte': _numeroParteController.text.trim(),
        'codigo_material': _codigoMaterialController.text.trim(),
        'propiedad_material': _propiedadMaterialController.text.trim(),
        'clasificacion': _clasificacionController.text.trim(),
        'especificacion_material': _especificacionController.text.trim(),
        'unidad_empaque': _unidadEmpaqueController.text.trim(),
        'ubicacion_material': _locations.join(', '),
        'ubicacion_rollos': _ubicacionesRollos.join(', '),
        'vendedor': _vendors.join(', '),
        'prohibido_sacar': _prohibidoSacarController.text.trim(),
        'nivel_msl': _nivelMslController.text.trim(),
        'espesor_msl': _espesorMslController.text.trim(),
        'assign_internal_lot': _assignInternalLot ? 1 : 0,
        'dividir_lote': _dividirLote ? 1 : 0,
        'standard_pack': int.tryParse(_standardPackController.text.trim()),
        'version': _versions.join(', '),
        'unidad_medida': _unidadMedida,
        'comparacion': _comparacionController.text.trim(),
        'usuario_registro': AuthService.currentUser?.nombreCompleto ?? AuthService.currentUser?.username ?? '',
      };
      
      Map<String, dynamic> result;
      if (_currentMaterial != null) {
        // Actualizar
        result = await ApiService.updateMaterial(_currentMaterial!['numero_parte'], data);
      } else {
        // Crear nuevo
        result = await ApiService.createMaterial(data);
      }
      
      if (result['success'] == true && mounted) {
        // Actualizar _currentMaterial con los datos guardados para evitar datos obsoletos
        if (_currentMaterial != null) {
          _currentMaterial = Map<String, dynamic>.from(_currentMaterial!);
          _currentMaterial!['ubicacion_rollos'] = _ubicacionesRollos.join(', ');
          _currentMaterial!['ubicacion_material'] = _locations.join(', ');
          _currentMaterial!['vendedor'] = _vendors.join(', ');
          _currentMaterial!['comparacion'] = _comparacionController.text.trim();
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(tr('saved_successfully')),
            backgroundColor: Colors.green,
          ),
        );
        setState(() => _isEditing = false);
        widget.onSaved?.call();
      } else if (mounted) {
        // Mostrar error específico
        String errorMsg = result['error'] ?? 'Error desconocido';
        if (result['code'] == 'DUPLICATE_PART_NUMBER') {
          errorMsg = tr('duplicate_part_number_error');
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(errorMsg), backgroundColor: Colors.red),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  // Guardar solo comparación y ubicacion_rollos (para usuarios con permiso write_comparacion)
  Future<void> _saveComparacionOnly() async {
    final numeroParte = _numeroParteController.text.trim();
    final comparacion = _comparacionController.text.trim();
    final ubicacionRollos = _ubicacionesRollos.join(', ');
    
    if (numeroParte.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(tr('part_number_required')),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    
    setState(() => _isLoading = true);
    
    try {
      Map<String, dynamic> result;
      
      if (_currentMaterial != null) {
        // Actualizar comparación y ubicacion_rollos
        result = await ApiService.updateMaterialComparacion(
          _currentMaterial!['numero_parte'],
          comparacion,
          ubicacionRollos: ubicacionRollos,
        );
      } else {
        // Crear nuevo con numero_parte, comparacion y ubicacion_rollos
        result = await ApiService.createMaterialSimple(numeroParte, comparacion, ubicacionRollos: ubicacionRollos);
      }
      
      if (result['success'] == true && mounted) {
        // Actualizar _currentMaterial con ubicacion_rollos y comparacion guardados
        if (_currentMaterial != null) {
          _currentMaterial = Map<String, dynamic>.from(_currentMaterial!);
          _currentMaterial!['ubicacion_rollos'] = _ubicacionesRollos.join(', ');
          _currentMaterial!['comparacion'] = _comparacionController.text.trim();
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(tr('saved_successfully')),
            backgroundColor: Colors.green,
          ),
        );
        setState(() => _isEditing = false);
        widget.onSaved?.call();
      } else if (mounted) {
        String errorMsg = result['error'] ?? 'Error desconocido';
        if (result['code'] == 'DUPLICATE_PART_NUMBER') {
          errorMsg = tr('duplicate_part_number_error');
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(errorMsg), backgroundColor: Colors.red),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool showForm = _currentMaterial != null || widget.isCreatingNew;
    
    return Container(
      color: AppColors.panelBackground,
      child: Column(
        children: [
          // Header
          Container(
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: const BoxDecoration(
              color: AppColors.gridHeader,
              border: Border(bottom: BorderSide(color: AppColors.border, width: 1)),
            ),
            child: Row(
              children: [
                Icon(
                  widget.isCreatingNew ? Icons.add_circle : Icons.edit,
                  color: Colors.cyan,
                  size: 16,
                ),
                const SizedBox(width: 8),
                Text(
                  widget.isCreatingNew ? tr('new_material') : tr('material_details'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                if (!_canEdit)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.orange.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.lock, size: 10, color: Colors.orange),
                        const SizedBox(width: 4),
                        Text(
                          tr('read_only'),
                          style: const TextStyle(fontSize: 9, color: Colors.orange),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          // Content
          Expanded(
            child: showForm
                ? _buildForm()
                : Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.touch_app, size: 48, color: Colors.white.withOpacity(0.1)),
                        const SizedBox(height: 8),
                        Text(
                          tr('select_material'),
                          style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 12),
                        ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
  
  // Formulario simplificado solo para Número de Parte y Comparación
  Widget _buildSimpleForm() {
    final bool isReadOnly = !_isEditing && !widget.isCreatingNew;
    final bool isUpdate = _currentMaterial != null;
    
    return Form(
      key: _formKey,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Info de permiso limitado
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.1),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: Colors.orange.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, color: Colors.orange, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      isUpdate 
                          ? tr('edit_comparison_only')
                          : tr('create_simple_mode'),
                      style: const TextStyle(color: Colors.orange, fontSize: 11),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            
            // Botones de acción
            if (!widget.isCreatingNew)
              Row(
                children: [
                  if (!_isEditing)
                    _buildActionButton(
                      icon: Icons.edit,
                      label: tr('edit'),
                      color: Colors.blue,
                      onPressed: () => setState(() => _isEditing = true),
                    )
                  else ...[
                    _buildActionButton(
                      icon: Icons.save,
                      label: tr('save'),
                      color: Colors.green,
                      onPressed: _isLoading ? null : _save,
                    ),
                    const SizedBox(width: 8),
                    _buildActionButton(
                      icon: Icons.cancel,
                      label: tr('cancel'),
                      color: Colors.grey,
                      onPressed: () {
                        setState(() => _isEditing = false);
                        loadMaterial(_currentMaterial);
                        widget.onCancelled?.call();
                      },
                    ),
                  ],
                ],
              ),
            
            // Botones para modo creación
            if (widget.isCreatingNew)
              Row(
                children: [
                  _buildActionButton(
                    icon: Icons.save,
                    label: tr('save'),
                    color: Colors.green,
                    onPressed: _isLoading ? null : _save,
                  ),
                  const SizedBox(width: 8),
                  _buildActionButton(
                    icon: Icons.cancel,
                    label: tr('cancel'),
                    color: Colors.grey,
                    onPressed: widget.onCancelled,
                  ),
                ],
              ),
            
            const SizedBox(height: 16),
            
            // Solo dos campos: Número de Parte y Comparación
            _buildTextField(
              label: tr('part_number'),
              controller: _numeroParteController,
              readOnly: isReadOnly || isUpdate, // PK no editable en update
              required: true,
              icon: Icons.tag,
            ),
            _buildTextField(
              label: tr('comparison'),
              controller: _comparacionController,
              readOnly: isReadOnly,
              icon: Icons.compare_arrows,
            ),
            _buildUbicacionRollosChipsField(isReadOnly: isReadOnly),

            // Mostrar otros datos solo lectura si es update
            if (isUpdate) ...[
              const SizedBox(height: 16),
              const Divider(color: AppColors.border),
              Text(
                tr('other_info'),
                style: const TextStyle(
                  color: Colors.white54,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              _buildReadOnlyField(tr('material_code'), _codigoMaterialController.text),
              _buildReadOnlyField(tr('material_property'), _propiedadMaterialController.text),
              _buildReadOnlyField(tr('material_spec'), _especificacionController.text),
              _buildReadOnlyField(tr('packaging_unit'), _unidadEmpaqueController.text),
            ],
            
            // Loading indicator
            if (_isLoading)
              const Padding(
                padding: EdgeInsets.only(top: 16),
                child: Center(child: CircularProgressIndicator()),
              ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildReadOnlyField(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: const TextStyle(color: Colors.white54, fontSize: 10),
            ),
          ),
          Expanded(
            child: Text(
              value.isEmpty ? '-' : value,
              style: const TextStyle(color: Colors.white70, fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildForm() {
    // Si solo tiene permiso de comparación (no completo), mostrar formulario simplificado
    if (_canEditComparacion && !_canEditFull) {
      return _buildSimpleForm();
    }
    
    final bool isReadOnly = !_canEdit || (!_isEditing && !widget.isCreatingNew);
    
    return Form(
      key: _formKey,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Botones de acción
            if (_canEdit && !widget.isCreatingNew)
              Row(
                children: [
                  if (!_isEditing)
                    _buildActionButton(
                      icon: Icons.edit,
                      label: tr('edit'),
                      color: Colors.blue,
                      onPressed: () => setState(() => _isEditing = true),
                    )
                  else ...[
                    _buildActionButton(
                      icon: Icons.save,
                      label: tr('save'),
                      color: Colors.green,
                      onPressed: _isLoading ? null : _save,
                    ),
                    const SizedBox(width: 8),
                    _buildActionButton(
                      icon: Icons.cancel,
                      label: tr('cancel'),
                      color: Colors.grey,
                      onPressed: () {
                        setState(() => _isEditing = false);
                        loadMaterial(_currentMaterial);
                        widget.onCancelled?.call();
                      },
                    ),
                  ],
                ],
              ),
            
            // Botones para modo creación
            if (widget.isCreatingNew && _canEdit)
              Row(
                children: [
                  _buildActionButton(
                    icon: Icons.save,
                    label: tr('save'),
                    color: Colors.green,
                    onPressed: _isLoading ? null : _save,
                  ),
                  const SizedBox(width: 8),
                  _buildActionButton(
                    icon: Icons.cancel,
                    label: tr('cancel'),
                    color: Colors.grey,
                    onPressed: widget.onCancelled,
                  ),
                ],
              ),
            
            const SizedBox(height: 16),
            
            // Campos obligatorios
            Text(
              tr('required_fields'),
              style: const TextStyle(
                color: Colors.amber,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            
            _buildTextField(
              label: tr('part_number'),
              controller: _numeroParteController,
              readOnly: isReadOnly || _currentMaterial != null, // PK no editable en update
              required: true,
              icon: Icons.tag,
            ),
            _buildTextField(
              label: tr('material_code'),
              controller: _codigoMaterialController,
              readOnly: isReadOnly,
              required: true,
              icon: Icons.qr_code,
            ),
            _buildTextField(
              label: tr('comparison'),
              controller: _comparacionController,
              readOnly: isReadOnly,
              icon: Icons.compare_arrows,
            ),
            _buildUbicacionRollosChipsField(isReadOnly: isReadOnly),
            _buildTextField(
              label: tr('material_property'),
              controller: _propiedadMaterialController,
              readOnly: isReadOnly,
              required: true,
              icon: Icons.category,
            ),
            _buildTextField(
              label: tr('material_spec'),
              controller: _especificacionController,
              readOnly: isReadOnly,
              required: true,
              icon: Icons.description,
            ),
            _buildTextField(
              label: tr('packaging_unit'),
              controller: _unidadEmpaqueController,
              readOnly: isReadOnly,
              required: true,
              icon: Icons.inventory,
            ),
            
            const SizedBox(height: 16),
            Text(
              tr('optional_fields'),
              style: const TextStyle(
                color: Colors.white54,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            
            _buildTextField(
              label: tr('classification'),
              controller: _clasificacionController,
              readOnly: isReadOnly,
              icon: Icons.label,
            ),
            // Location chips input
            _buildLocationChipsField(isReadOnly: isReadOnly),
            // Vendor chips input
            _buildVendorChipsField(isReadOnly: isReadOnly),
            _buildTextField(
              label: tr('prohibited_exit'),
              controller: _prohibidoSacarController,
              readOnly: isReadOnly,
              icon: Icons.block,
            ),
            _buildTextField(
              label: tr('msl_level'),
              controller: _nivelMslController,
              readOnly: isReadOnly,
              icon: Icons.water_drop,
            ),
            _buildTextField(
              label: tr('msl_thickness'),
              controller: _espesorMslController,
              readOnly: isReadOnly,
              icon: Icons.straighten,
            ),
            
            // Unidad de medida dropdown
            _buildDropdownField(
              label: tr('unit'),
              value: _unidadMedida,
              items: _unidadMedidaOptions,
              readOnly: isReadOnly,
              icon: Icons.scale,
              onChanged: (value) {
                setState(() {
                  _unidadMedida = value ?? 'EA';
                });
              },
            ),
            
            // Assign Internal Lot (checkbox editable)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: isReadOnly 
                    ? AppColors.gridBackground.withOpacity(0.5)
                    : AppColors.gridBackground,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: AppColors.border),
              ),
              child: InkWell(
                onTap: isReadOnly ? null : () {
                  setState(() {
                    _assignInternalLot = !_assignInternalLot;
                  });
                },
                child: Row(
                  children: [
                    Icon(
                      _assignInternalLot ? Icons.check_box : Icons.check_box_outline_blank,
                      color: _assignInternalLot ? Colors.cyan : Colors.grey,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            tr('assign_internal_lot'),
                            style: const TextStyle(color: Colors.white, fontSize: 11),
                          ),
                          Text(
                            tr('requires_internal_lot'),
                            style: const TextStyle(color: Colors.white38, fontSize: 9),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            
            // Dividir Lote (Split Lot) checkbox with Standard Pack field
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: isReadOnly 
                    ? AppColors.gridBackground.withOpacity(0.5)
                    : AppColors.gridBackground,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: _dividirLote ? Colors.purple.withOpacity(0.5) : AppColors.border,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  InkWell(
                    onTap: isReadOnly ? null : () {
                      setState(() {
                        _dividirLote = !_dividirLote;
                      });
                    },
                    child: Row(
                      children: [
                        Icon(
                          _dividirLote ? Icons.check_box : Icons.check_box_outline_blank,
                          color: _dividirLote ? Colors.purple : Colors.grey,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Icon(
                          Icons.call_split,
                          color: _dividirLote ? Colors.purple : Colors.grey,
                          size: 16,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                tr('dividir_lote'),
                                style: const TextStyle(color: Colors.white, fontSize: 11),
                              ),
                              Text(
                                tr('allows_lot_splitting'),
                                style: const TextStyle(color: Colors.white38, fontSize: 9),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Standard Pack field (only visible when dividir_lote is enabled)
                  if (_dividirLote) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const SizedBox(width: 28),
                        Expanded(
                          child: TextFormField(
                            controller: _standardPackController,
                            readOnly: isReadOnly,
                            keyboardType: TextInputType.number,
                            style: TextStyle(
                              fontSize: 11,
                              color: isReadOnly ? Colors.white54 : Colors.white,
                            ),
                            decoration: InputDecoration(
                              labelText: '${tr('standard_pack')} *',
                              labelStyle: const TextStyle(
                                fontSize: 10,
                                color: Colors.amber,
                              ),
                              prefixIcon: const Icon(Icons.inventory_2, size: 14, color: Colors.purple),
                              prefixIconConstraints: const BoxConstraints(minWidth: 32),
                              filled: true,
                              fillColor: isReadOnly 
                                  ? AppColors.gridBackground.withOpacity(0.5)
                                  : AppColors.fieldBackground,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(4),
                                borderSide: const BorderSide(color: AppColors.border),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(4),
                                borderSide: BorderSide(color: Colors.purple.withOpacity(0.5)),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(4),
                                borderSide: const BorderSide(color: Colors.purple),
                              ),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                              isDense: true,
                              hintText: tr('qty_per_split'),
                              hintStyle: const TextStyle(fontSize: 9, color: Colors.white38),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            
            // Version chips input
            _buildVersionChipsField(isReadOnly: isReadOnly),
            
            // Información de registro
            if (_fechaRegistro.isNotEmpty || _usuarioRegistro.isNotEmpty) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.gridBackground.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_fechaRegistro.isNotEmpty)
                      Row(
                        children: [
                          const Icon(Icons.calendar_today, size: 12, color: Colors.white38),
                          const SizedBox(width: 4),
                          Text(
                            '${tr('registration_date')}: $_fechaRegistro',
                            style: const TextStyle(fontSize: 10, color: Colors.white54),
                          ),
                        ],
                      ),
                    if (_usuarioRegistro.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(Icons.person, size: 12, color: Colors.white38),
                          const SizedBox(width: 4),
                          Text(
                            '${tr('registered_by')}: $_usuarioRegistro',
                            style: const TextStyle(fontSize: 10, color: Colors.white54),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
  
  Widget _buildTextField({
    required String label,
    required TextEditingController controller,
    bool readOnly = false,
    bool required = false,
    IconData? icon,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TextFormField(
        controller: controller,
        readOnly: readOnly,
        style: TextStyle(
          fontSize: 11,
          color: readOnly ? Colors.white54 : Colors.white,
        ),
        decoration: InputDecoration(
          labelText: required ? '$label *' : label,
          labelStyle: TextStyle(
            fontSize: 10,
            color: required ? Colors.amber : Colors.white54,
          ),
          prefixIcon: icon != null 
              ? Icon(icon, size: 14, color: Colors.white38)
              : null,
          prefixIconConstraints: const BoxConstraints(minWidth: 32),
          filled: true,
          fillColor: readOnly 
              ? AppColors.gridBackground.withOpacity(0.5)
              : AppColors.gridBackground,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(4),
            borderSide: BorderSide(color: AppColors.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(4),
            borderSide: BorderSide(color: AppColors.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(4),
            borderSide: const BorderSide(color: Colors.cyan),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(4),
            borderSide: const BorderSide(color: Colors.red),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          isDense: true,
        ),
        validator: required
            ? (value) {
                if (value == null || value.trim().isEmpty) {
                  return tr('field_required');
                }
                return null;
              }
            : null,
      ),
    );
  }
  
  Widget _buildDropdownField({
    required String label,
    required String value,
    required List<String> items,
    bool readOnly = false,
    IconData? icon,
    void Function(String?)? onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(
            fontSize: 10,
            color: Colors.white54,
          ),
          prefixIcon: icon != null 
              ? Icon(icon, size: 14, color: Colors.white38)
              : null,
          prefixIconConstraints: const BoxConstraints(minWidth: 32),
          filled: true,
          fillColor: readOnly 
              ? AppColors.gridBackground.withOpacity(0.5)
              : AppColors.gridBackground,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(4),
            borderSide: BorderSide(color: AppColors.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(4),
            borderSide: BorderSide(color: AppColors.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(4),
            borderSide: const BorderSide(color: Colors.cyan),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          isDense: true,
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: value,
            isDense: true,
            isExpanded: true,
            dropdownColor: AppColors.gridBackground,
            style: TextStyle(
              fontSize: 11,
              color: readOnly ? Colors.white54 : Colors.white,
            ),
            items: items.map((item) => DropdownMenuItem<String>(
              value: item,
              child: Text(_getUnitDisplayName(item)),
            )).toList(),
            onChanged: readOnly ? null : onChanged,
          ),
        ),
      ),
    );
  }
  
  /// Returns display name for unit
  String _getUnitDisplayName(String unit) {
    switch (unit) {
      case 'EA': return 'EA - ${tr('element')}';
      case 'm': return 'm - ${tr('meter')}';
      case 'kg': return 'kg - ${tr('kilogram')}';
      case 'g': return 'g - ${tr('gram')}';
      case 'mg': return 'mg - ${tr('milligram')}';
      default: return unit;
    }
  }
  
  Widget _buildVersionChipsField({required bool isReadOnly}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: isReadOnly 
            ? AppColors.gridBackground.withOpacity(0.5)
            : AppColors.gridBackground,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Label
          Row(
            children: [
              const Icon(Icons.history, size: 14, color: Colors.white38),
              const SizedBox(width: 8),
              Text(
                tr('version'),
                style: const TextStyle(fontSize: 10, color: Colors.white54),
              ),
              const Spacer(),
              Text(
                '${_versions.length} ${_versions.length == 1 ? 'versión' : 'versiones'}',
                style: const TextStyle(fontSize: 9, color: Colors.white38),
              ),
            ],
          ),
          const SizedBox(height: 8),
          
          // Chips de versiones
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              // Mostrar versiones existentes
              ..._versions.map((version) => Chip(
                label: Text(
                  version,
                  style: const TextStyle(fontSize: 10, color: Colors.white),
                ),
                backgroundColor: Colors.cyan.withOpacity(0.3),
                deleteIcon: isReadOnly ? null : const Icon(Icons.close, size: 14),
                deleteIconColor: Colors.white54,
                onDeleted: isReadOnly ? null : () {
                  setState(() {
                    _versions.remove(version);
                  });
                },
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              )),
              
              // Campo para agregar nueva versión (solo si puede editar)
              if (!isReadOnly)
                SizedBox(
                  width: 80,
                  height: 28,
                  child: TextField(
                    controller: _versionInputController,
                    style: const TextStyle(fontSize: 10, color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Ej: -A',
                      hintStyle: const TextStyle(fontSize: 9, color: Colors.white38),
                      filled: true,
                      fillColor: AppColors.panelBackground,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(4),
                        borderSide: BorderSide(color: AppColors.border),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(4),
                        borderSide: BorderSide(color: AppColors.border),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(4),
                        borderSide: const BorderSide(color: Colors.cyan),
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      isDense: true,
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.add, size: 14, color: Colors.cyan),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(maxWidth: 24, maxHeight: 24),
                        onPressed: _addVersion,
                      ),
                    ),
                    onSubmitted: (_) => _addVersion(),
                  ),
                ),
            ],
          ),
          
          // Mensaje de ayuda
          if (!isReadOnly && _versions.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Ingrese versiones de PCB (ej: -A, -B, -C, -D)',
                style: TextStyle(fontSize: 9, color: Colors.white.withOpacity(0.4)),
              ),
            ),
        ],
      ),
    );
  }
  
  void _addVersion() {
    final value = _versionInputController.text.trim();
    if (value.isNotEmpty && !_versions.contains(value)) {
      setState(() {
        _versions.add(value);
        _versionInputController.clear();
      });
    }
  }
  
  Widget _buildLocationChipsField({required bool isReadOnly}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: isReadOnly 
            ? AppColors.gridBackground.withOpacity(0.5)
            : AppColors.gridBackground,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Label
          Row(
            children: [
              const Icon(Icons.location_on, size: 14, color: Colors.white38),
              const SizedBox(width: 8),
              Text(
                tr('location'),
                style: const TextStyle(fontSize: 10, color: Colors.white54),
              ),
              const Spacer(),
              Text(
                '${_locations.length} ${_locations.length == 1 ? 'ubicación' : 'ubicaciones'}',
                style: const TextStyle(fontSize: 9, color: Colors.white38),
              ),
            ],
          ),
          const SizedBox(height: 8),
          
          // Chips de ubicaciones
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              // Mostrar ubicaciones existentes
              ..._locations.map((location) => Chip(
                label: Text(
                  location,
                  style: const TextStyle(fontSize: 10, color: Colors.white),
                ),
                backgroundColor: Colors.green.withOpacity(0.3),
                deleteIcon: isReadOnly ? null : const Icon(Icons.close, size: 14),
                deleteIconColor: Colors.white54,
                onDeleted: isReadOnly ? null : () {
                  setState(() {
                    _locations.remove(location);
                  });
                },
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              )),
              
              // Campo para agregar nueva ubicación (solo si puede editar)
              if (!isReadOnly)
                SizedBox(
                  width: 100,
                  height: 28,
                  child: TextField(
                    controller: _locationInputController,
                    style: const TextStyle(fontSize: 10, color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Ej: A1-01',
                      hintStyle: const TextStyle(fontSize: 9, color: Colors.white38),
                      filled: true,
                      fillColor: AppColors.panelBackground,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(4),
                        borderSide: BorderSide(color: AppColors.border),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(4),
                        borderSide: BorderSide(color: AppColors.border),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(4),
                        borderSide: const BorderSide(color: Colors.green),
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      isDense: true,
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.add, size: 14, color: Colors.green),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(maxWidth: 24, maxHeight: 24),
                        onPressed: _addLocation,
                      ),
                    ),
                    onSubmitted: (_) => _addLocation(),
                  ),
                ),
            ],
          ),
          
          // Mensaje de ayuda
          if (!isReadOnly && _locations.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Ingrese ubicaciones del material (ej: A1-01, B2-03)',
                style: TextStyle(fontSize: 9, color: Colors.white.withOpacity(0.4)),
              ),
            ),
        ],
      ),
    );
  }
  
  void _addLocation() {
    final value = _locationInputController.text.trim();
    if (value.isNotEmpty && !_locations.contains(value)) {
      setState(() {
        _locations.add(value);
        _locationInputController.clear();
      });
    }
  }

  Widget _buildUbicacionRollosChipsField({required bool isReadOnly}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: isReadOnly
            ? AppColors.gridBackground.withOpacity(0.5)
            : AppColors.gridBackground,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.view_carousel, size: 14, color: Colors.white38),
              const SizedBox(width: 8),
              Text(
                tr('location_rollos'),
                style: const TextStyle(fontSize: 10, color: Colors.white54),
              ),
              const Spacer(),
              Text(
                '${_ubicacionesRollos.length} ${_ubicacionesRollos.length == 1 ? 'ubicación' : 'ubicaciones'}',
                style: const TextStyle(fontSize: 9, color: Colors.white38),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              ..._ubicacionesRollos.map((location) => Chip(
                label: Text(
                  location,
                  style: const TextStyle(fontSize: 10, color: Colors.white),
                ),
                backgroundColor: Colors.teal.withOpacity(0.3),
                deleteIcon: isReadOnly ? null : const Icon(Icons.close, size: 14),
                deleteIconColor: Colors.white54,
                onDeleted: isReadOnly ? null : () {
                  setState(() {
                    _ubicacionesRollos.remove(location);
                  });
                },
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              )),
              if (!isReadOnly)
                SizedBox(
                  width: 100,
                  height: 28,
                  child: TextField(
                    controller: _ubicacionRollosInputController,
                    style: const TextStyle(fontSize: 10, color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Ej: R1-01',
                      hintStyle: const TextStyle(fontSize: 9, color: Colors.white38),
                      filled: true,
                      fillColor: AppColors.panelBackground,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(4),
                        borderSide: BorderSide(color: AppColors.border),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(4),
                        borderSide: BorderSide(color: AppColors.border),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(4),
                        borderSide: const BorderSide(color: Colors.teal),
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      isDense: true,
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.add, size: 14, color: Colors.teal),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(maxWidth: 24, maxHeight: 24),
                        onPressed: _addUbicacionRollos,
                      ),
                    ),
                    onSubmitted: (_) => _addUbicacionRollos(),
                  ),
                ),
            ],
          ),
          if (!isReadOnly && _ubicacionesRollos.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Ingrese ubicaciones de rollos (ej: R1-01, R2-03)',
                style: TextStyle(fontSize: 9, color: Colors.white.withOpacity(0.4)),
              ),
            ),
        ],
      ),
    );
  }

  void _addUbicacionRollos() {
    final value = _ubicacionRollosInputController.text.trim();
    if (value.isNotEmpty && !_ubicacionesRollos.contains(value)) {
      setState(() {
        _ubicacionesRollos.add(value);
        _ubicacionRollosInputController.clear();
      });
    }
  }

  Widget _buildVendorChipsField({required bool isReadOnly}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: isReadOnly 
            ? AppColors.gridBackground.withOpacity(0.5)
            : AppColors.gridBackground,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Label
          Row(
            children: [
              const Icon(Icons.store, size: 14, color: Colors.white38),
              const SizedBox(width: 8),
              Text(
                tr('vendor'),
                style: const TextStyle(fontSize: 10, color: Colors.white54),
              ),
              const Spacer(),
              Text(
                '${_vendors.length} ${_vendors.length == 1 ? 'vendedor' : 'vendedores'}',
                style: const TextStyle(fontSize: 9, color: Colors.white38),
              ),
            ],
          ),
          const SizedBox(height: 8),
          
          // Chips de vendedores
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              // Mostrar vendedores existentes
              ..._vendors.map((vendor) => Chip(
                label: Text(
                  vendor,
                  style: const TextStyle(fontSize: 10, color: Colors.white),
                ),
                backgroundColor: Colors.purple.withOpacity(0.3),
                deleteIcon: isReadOnly ? null : const Icon(Icons.close, size: 14),
                deleteIconColor: Colors.white54,
                onDeleted: isReadOnly ? null : () {
                  setState(() {
                    _vendors.remove(vendor);
                  });
                },
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              )),
              
              // Campo para agregar nuevo vendedor (solo si puede editar)
              if (!isReadOnly)
                SizedBox(
                  width: 120,
                  height: 28,
                  child: TextField(
                    controller: _vendorInputController,
                    style: const TextStyle(fontSize: 10, color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Ej: DELTA',
                      hintStyle: const TextStyle(fontSize: 9, color: Colors.white38),
                      filled: true,
                      fillColor: AppColors.panelBackground,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(4),
                        borderSide: BorderSide(color: AppColors.border),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(4),
                        borderSide: BorderSide(color: AppColors.border),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(4),
                        borderSide: const BorderSide(color: Colors.purple),
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      isDense: true,
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.add, size: 14, color: Colors.purple),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(maxWidth: 24, maxHeight: 24),
                        onPressed: _addVendor,
                      ),
                    ),
                    onSubmitted: (_) => _addVendor(),
                  ),
                ),
            ],
          ),
          
          // Mensaje de ayuda
          if (!isReadOnly && _vendors.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Ingrese vendedores del material (ej: DELTA, FOXCONN)',
                style: TextStyle(fontSize: 9, color: Colors.white.withOpacity(0.4)),
              ),
            ),
        ],
      ),
    );
  }
  
  void _addVendor() {
    final value = _vendorInputController.text.trim();
    if (value.isNotEmpty && !_vendors.contains(value)) {
      setState(() {
        _vendors.add(value);
        _vendorInputController.clear();
      });
    }
  }
  
  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required Color color,
    VoidCallback? onPressed,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: color.withOpacity(0.2),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: color.withOpacity(0.5)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 4),
              Text(label, style: TextStyle(fontSize: 11, color: color)),
            ],
          ),
        ),
      ),
    );
  }
}
