import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:material_warehousing_flutter/core/localization/app_translations.dart';
import 'package:material_warehousing_flutter/core/services/api_service.dart';
import 'package:material_warehousing_flutter/core/services/auth_service.dart';
import 'package:material_warehousing_flutter/core/services/feedback_service.dart';
import 'package:material_warehousing_flutter/core/services/scanner_config_service.dart';
import 'package:material_warehousing_flutter/screens/mobile/mobile_requirement_draft.dart';

int _asMobileRequirementInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

class MobileRequirementFormScreen extends StatefulWidget {
  final LanguageProvider languageProvider;
  final int? appendToRequirementId;
  final String? requirementCode;

  const MobileRequirementFormScreen({
    super.key,
    required this.languageProvider,
    this.appendToRequirementId,
    this.requirementCode,
  });

  @override
  State<MobileRequirementFormScreen> createState() =>
      _MobileRequirementFormScreenState();
}

class _MobileRequirementFormScreenState
    extends State<MobileRequirementFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _modelController = TextEditingController();
  final _notesController = TextEditingController();
  final _materialCodeController = TextEditingController();
  final _quantityController = TextEditingController(text: '1');
  final _packController = TextEditingController();
  final _unitsController = TextEditingController(text: '1');
  final MobileRequirementDraft _draft = MobileRequirementDraft();

  List<String> _areas = [];
  List<Map<String, dynamic>> _materialCatalog = [];
  List<Map<String, dynamic>> _materialSuggestions = [];
  String? _selectedArea;
  String? _selectedShift;
  String _selectedPriority = 'Normal';
  DateTime _requiredDate = DateTime.now().add(const Duration(days: 1));
  Map<String, dynamic>? _pendingMaterial;
  bool _loadingAreas = true;
  bool _loadingCatalog = true;
  bool _resolvingMaterial = false;
  bool _saving = false;
  bool _allowPop = false;

  static const _shifts = ['Día', 'Noche', 'Mixto'];
  static const _priorities = ['Normal', 'Urgente', 'Crítico'];

  bool get _isAppendMode => widget.appendToRequirementId != null;

  int get _pendingMaterialAvailable =>
      _asMobileRequirementInt(_pendingMaterial?['cantidad_disponible']);

  int get _pendingMaterialInvoiceQuantity =>
      _asMobileRequirementInt(_pendingMaterial?['cantidad_pendiente_entrada']);

  String get _pendingMaterialInvoices {
    final value =
        (_pendingMaterial?['pendiente_entrada_en'] ?? '').toString().trim();
    return value == 'null' ? '' : value;
  }

  bool get _pendingMaterialIsInvoiceOnly =>
      _pendingMaterialAvailable <= 0 && _pendingMaterialInvoiceQuantity > 0;

  @override
  void initState() {
    super.initState();
    if (!_isAppendMode) _loadAreas();
    _loadMaterialCatalog();
  }

  @override
  void dispose() {
    _modelController.dispose();
    _notesController.dispose();
    _materialCodeController.dispose();
    _quantityController.dispose();
    _packController.dispose();
    _unitsController.dispose();
    super.dispose();
  }

  Future<void> _loadAreas() async {
    final loadedAreas = await ApiService.getRequirementAreas();
    final areas = loadedAreas.isNotEmpty
        ? loadedAreas
        : const [
            'SMD',
            'Assy',
            'Molding',
            'Pre-Assy',
            'Empaque',
            'Rework',
            'Mantenimiento',
            'Ingeniería',
            'Calidad',
            'Otro',
          ];
    if (!mounted) return;
    setState(() {
      _areas = areas;
      _loadingAreas = false;
    });
  }

  Future<void> _loadMaterialCatalog() async {
    final materials = await ApiService.getMateriales();
    if (!mounted) return;
    final suggestions = filterRequirementMaterials(
      materials,
      _materialCodeController.text,
    );
    setState(() {
      _materialCatalog = materials;
      _loadingCatalog = false;
      _materialSuggestions = suggestions;
    });
  }

  void _updateMaterialSuggestions(String value) {
    final suggestions = filterRequirementMaterials(_materialCatalog, value);
    if (mounted) {
      setState(() {
        _pendingMaterial = null;
        _materialSuggestions = suggestions;
      });
    }
  }

  int? _positiveInt(dynamic value) {
    final parsed = int.tryParse(value?.toString().trim() ?? '');
    return parsed != null && parsed > 0 ? parsed : null;
  }

  int? get _packSize => _positiveInt(_packController.text);
  int get _unitCount => _positiveInt(_unitsController.text) ?? 1;
  bool get _usesUnits => _packSize != null;

  // Prefill de empaque/unidades como en PC (standard_pack o unidad_empaque)
  void _applyPendingMaterial(Map<String, dynamic>? material) {
    _pendingMaterial = material;
    if (material == null) return;
    final pack = _positiveInt(material['standard_pack']) ??
        _positiveInt(material['unidad_empaque']);
    _packController.text = pack == null ? '' : '$pack';
    _unitsController.text = '1';
    _quantityController.text = '${pack ?? 1}';
  }

  void _syncTotalFromUnits() {
    final pack = _packSize;
    if (pack != null) {
      _quantityController.text = '${pack * _unitCount}';
    }
    setState(() {});
  }

  void _selectMaterialSuggestion(Map<String, dynamic> material) {
    final partNumber = material['numero_parte']?.toString().trim() ?? '';
    setState(() {
      _applyPendingMaterial(material);
      _materialSuggestions = [];
      _materialCodeController.text = partNumber;
      _materialCodeController.selection = TextSelection.collapsed(
        offset: partNumber.length,
      );
    });
    FocusScope.of(context).unfocus();
  }

  bool get _hasDraftChanges =>
      (!_isAppendMode &&
          (_selectedArea != null ||
              _selectedShift != null ||
              _modelController.text.trim().isNotEmpty ||
              _notesController.text.trim().isNotEmpty)) ||
      _materialCodeController.text.trim().isNotEmpty ||
      _pendingMaterial != null ||
      _draft.isNotEmpty;

  Future<bool> _confirmDiscard() async {
    if (_saving) return false;
    if (!_hasDraftChanges) return true;
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Descartar requerimiento'),
            content: const Text(
              'Hay información sin guardar. ¿Deseas descartarla?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Continuar editando'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                child: const Text('Descartar'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _selectDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _requiredDate,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (date != null && mounted) setState(() => _requiredDate = date);
  }

  Map<String, dynamic>? _catalogEntry(String partNumber) {
    final normalized = partNumber.trim().toUpperCase();
    if (normalized.isEmpty) return null;
    for (final material in _materialCatalog) {
      final part =
          material['numero_parte']?.toString().trim().toUpperCase() ?? '';
      if (part == normalized) return material;
    }
    return null;
  }

  // El catálogo trae cantidad_disponible; el API by-part-number no.
  Future<Map<String, dynamic>?> _resolvePartNumber(String partNumber) async {
    if (partNumber.trim().isEmpty) return null;
    return _catalogEntry(partNumber) ??
        await ApiService.getMaterialByPartNumber(partNumber);
  }

  Future<Map<String, dynamic>?> _resolveMaterial(String rawCode) async {
    final code = rawCode.trim();
    if (code.isEmpty) return null;

    final byPart = await _resolvePartNumber(code);
    if (byPart != null) return byPart;

    final byCode = await ApiService.getMaterialByCode(code);
    if (byCode != null) return byCode;

    // Etiqueta de rollo (ej. MCK67482303-202607210001): buscar en almacén
    final roll = await ApiService.getWarehousingByCode(code);
    final rollPart = roll?['numero_parte']?.toString().trim() ?? '';
    if (rollPart.isNotEmpty) {
      final material = await _resolvePartNumber(rollPart);
      if (material != null) return material;
    }

    // Formato PARTE-LOTE (ej. EAX69471801-1.0-20260721000105):
    // el primer segmento es el número de parte
    if (code.contains('-')) {
      final material = await _resolvePartNumber(code.split('-').first);
      if (material != null) return material;
    }

    return null;
  }

  Future<void> _resolveCurrentInput() async {
    if (_resolvingMaterial) return;
    final code = _materialCodeController.text.trim();
    if (code.isEmpty) {
      _showMessage('Escribe o escanea un código de material.', isError: true);
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() {
      _resolvingMaterial = true;
      _pendingMaterial = null;
      _materialSuggestions = [];
    });

    var material = await _resolveMaterial(code);

    // Ubicación escaneada (ej. rack H8): elegir material de esa ubicación
    List<Map<String, dynamic>> locationParts = const [];
    if (material == null) {
      locationParts = await ApiService.getPartsByLocation(code);
    }
    if (material == null && locationParts.isEmpty) {
      material = await ApiService.parseBarcodeForMaterial(code);
    }
    if (!mounted) return;

    if (locationParts.isNotEmpty) {
      setState(() => _resolvingMaterial = false);
      await FeedbackService.playSuccess();
      await _pickMaterialFromLocation(code.toUpperCase(), locationParts);
      return;
    }

    setState(() {
      _applyPendingMaterial(material);
      _resolvingMaterial = false;
    });

    if (material == null) {
      await FeedbackService.playError();
      _showMessage('No se encontró un material para ese código.',
          isError: true);
    } else {
      await FeedbackService.playSuccess();
    }
  }

  Future<void> _pickMaterialFromLocation(
    String location,
    List<Map<String, dynamic>> parts,
  ) async {
    Map<String, dynamic>? selected = parts.length == 1 ? parts.first : null;
    selected ??= await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF252A3C),
        title: Text(
          'Materiales en $location',
          style: const TextStyle(color: Colors.white),
        ),
        contentPadding: const EdgeInsets.symmetric(vertical: 8),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: parts.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final part = parts[index];
              final partNumber = part['numero_parte']?.toString() ?? '';
              final specification =
                  part['especificacion_material']?.toString() ?? '';
              final rolls = _asMobileRequirementInt(part['rollos']);
              final total = _asMobileRequirementInt(part['cantidad_total']);
              return ListTile(
                dense: true,
                leading: const Icon(Icons.inventory_2_outlined,
                    color: Colors.tealAccent),
                title: Text(
                  partNumber,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (specification.isNotEmpty)
                      Text(
                        specification,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white70),
                      ),
                    Text(
                      '$rolls rollos · $total pzas en $location',
                      style: const TextStyle(
                          color: Colors.white54, fontSize: 11),
                    ),
                  ],
                ),
                onTap: () => Navigator.pop(dialogContext, part),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancelar'),
          ),
        ],
      ),
    );
    if (selected == null || !mounted) return;

    final partNumber = selected['numero_parte']?.toString().trim() ?? '';
    final material = await _resolvePartNumber(partNumber) ?? selected;
    if (!mounted) return;
    setState(() {
      _applyPendingMaterial(material);
      _materialSuggestions = [];
      _materialCodeController.text = partNumber;
      _materialCodeController.selection =
          TextSelection.collapsed(offset: partNumber.length);
    });
  }

  Future<void> _openScanner() async {
    FocusScope.of(context).unfocus();
    final code = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const _RequirementScannerPage()),
    );
    if (code == null || code.trim().isEmpty || !mounted) return;
    _materialCodeController.text = code.trim();
    await _resolveCurrentInput();
  }

  void _addPendingMaterial() {
    final material = _pendingMaterial;
    final quantity = int.tryParse(_quantityController.text.trim());
    if (material == null) return;
    if (quantity == null || quantity <= 0) {
      _showMessage('La cantidad debe ser un entero mayor que cero.',
          isError: true);
      return;
    }

    final partNumber = material['numero_parte']?.toString().trim() ?? '';
    if (partNumber.isEmpty) {
      _showMessage('El material no tiene número de parte.', isError: true);
      return;
    }

    setState(() {
      _draft.addOrIncrement(
        partNumber: partNumber,
        description: material['especificacion_material']?.toString() ?? '',
        quantity: quantity,
        packSize: _packSize,
        units: _usesUnits ? _unitCount : null,
      );
      _pendingMaterial = null;
      _materialSuggestions = [];
      _materialCodeController.clear();
      _quantityController.text = '1';
      _packController.clear();
      _unitsController.text = '1';
    });
    _showMessage('Material agregado al requerimiento.');
  }

  Future<void> _editQuantity(int index) async {
    final controller = TextEditingController(
      text: _draft.items[index].quantity.toString(),
    );
    final quantity = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cantidad requerida'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () {
              final value = int.tryParse(controller.text.trim());
              if (value != null && value > 0) Navigator.pop(context, value);
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (quantity != null && mounted) {
      setState(() => _draft.updateQuantity(index, quantity));
    }
  }

  Future<void> _save() async {
    if (_saving || !_formKey.currentState!.validate()) return;
    if (!_isAppendMode && _selectedArea == null) {
      _showMessage('Selecciona el área destino.', isError: true);
      return;
    }
    if (_draft.isEmpty) {
      _showMessage('Agrega al menos un material.', isError: true);
      return;
    }

    setState(() => _saving = true);
    late final Map<String, dynamic> result;
    if (_isAppendMode) {
      result = await ApiService.addRequirementItemsDetailed(
        widget.appendToRequirementId!,
        _draft.toJson(),
      );
    } else {
      final user = AuthService.currentUser;
      result = await ApiService.createRequirementDetailed({
        'area_destino': _selectedArea,
        'modelo': _modelController.text.trim().isEmpty
            ? null
            : _modelController.text.trim(),
        'fecha_requerida': DateFormat('yyyy-MM-dd').format(_requiredDate),
        'turno': _selectedShift,
        'prioridad': _selectedPriority,
        'notas': _notesController.text.trim().isEmpty
            ? null
            : _notesController.text.trim(),
        'creado_por': user?.nombreCompleto ?? user?.username ?? 'Sistema',
        'items': _draft.toJson(),
      });
    }
    if (!mounted) return;
    setState(() => _saving = false);

    if (result['success'] == true) {
      await FeedbackService.playSuccess();
      if (mounted) {
        setState(() => _allowPop = true);
        Navigator.pop(context, result);
      }
      return;
    }

    await FeedbackService.playError();
    _showMessage(
      result['error']?.toString() ??
          (_isAppendMode
              ? 'No se pudieron agregar los materiales.'
              : 'No se pudo crear el requerimiento.'),
      isError: true,
    );
  }

  void _showMessage(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _allowPop || (!_hasDraftChanges && !_saving),
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final discard = await _confirmDiscard();
        if (discard && mounted) {
          setState(() => _allowPop = true);
          Navigator.pop(context);
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF1A1E2C),
        appBar: AppBar(
          title: Text(
            _isAppendMode
                ? 'Agregar a ${widget.requirementCode ?? 'requerimiento'}'
                : 'Nuevo requerimiento',
          ),
          backgroundColor: const Color(0xFF252A3C),
        ),
        body: Form(
          key: _formKey,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (!_isAppendMode) ...[
                  _buildHeaderSection(),
                  const SizedBox(height: 16),
                ],
                _buildMaterialSection(),
                const SizedBox(height: 16),
                _buildDraftSection(),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: _saving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.cloud_upload),
                  label: Text(
                    _saving
                        ? 'Enviando...'
                        : _isAppendMode
                            ? 'AGREGAR MATERIALES'
                            : 'ENVIAR REQUERIMIENTO',
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.teal,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderSection() {
    return _SectionCard(
      title: 'Datos del requerimiento',
      icon: Icons.assignment_outlined,
      child: Column(
        children: [
          DropdownButtonFormField<String>(
            initialValue: _selectedArea,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: 'Área destino *',
              prefixIcon: const Icon(Icons.factory_outlined),
              suffixIcon: _loadingAreas
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : null,
            ),
            items: _areas
                .map((area) => DropdownMenuItem(value: area, child: Text(area)))
                .toList(),
            onChanged: _loadingAreas
                ? null
                : (value) => setState(() => _selectedArea = value),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _modelController,
            decoration: const InputDecoration(
              labelText: 'Modelo (opcional)',
              prefixIcon: Icon(Icons.precision_manufacturing_outlined),
            ),
          ),
          const SizedBox(height: 12),
          InkWell(
            onTap: _selectDate,
            child: InputDecorator(
              decoration: const InputDecoration(
                labelText: 'Fecha requerida *',
                prefixIcon: Icon(Icons.calendar_today),
              ),
              child: Text(DateFormat('dd/MM/yyyy').format(_requiredDate)),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: _selectedShift,
                  decoration: const InputDecoration(labelText: 'Turno'),
                  items: _shifts
                      .map((shift) =>
                          DropdownMenuItem(value: shift, child: Text(shift)))
                      .toList(),
                  onChanged: (value) => setState(() => _selectedShift = value),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: _selectedPriority,
                  decoration: const InputDecoration(labelText: 'Prioridad'),
                  items: _priorities
                      .map((priority) => DropdownMenuItem(
                          value: priority, child: Text(priority)))
                      .toList(),
                  onChanged: (value) => setState(
                    () => _selectedPriority = value ?? 'Normal',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _notesController,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Notas',
              alignLabelWithHint: true,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMaterialSection() {
    return _SectionCard(
      title: 'Agregar material',
      icon: Icons.qr_code_scanner,
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  controller: _materialCodeController,
                  textInputAction: TextInputAction.search,
                  onChanged: _updateMaterialSuggestions,
                  onSubmitted: (_) => _resolveCurrentInput(),
                  decoration: InputDecoration(
                    labelText: 'NParte, rollo o ubicación',
                    hintText: 'Escanea etiqueta o rack',
                    helperText:
                        'Acepta número de parte, etiqueta de rollo o ubicación',
                    prefixIcon: const Icon(Icons.keyboard),
                    suffixIcon: _loadingCatalog
                        ? const Padding(
                            padding: EdgeInsets.all(12),
                            child: SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        : null,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                tooltip: 'Escanear',
                onPressed: _resolvingMaterial ? null : _openScanner,
                icon: const Icon(Icons.qr_code_scanner),
              ),
            ],
          ),
          if (_materialSuggestions.isNotEmpty) ...[
            const SizedBox(height: 6),
            _buildMaterialSuggestions(),
          ],
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _resolvingMaterial ? null : _resolveCurrentInput,
              icon: _resolvingMaterial
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.search),
              label:
                  Text(_resolvingMaterial ? 'Buscando...' : 'BUSCAR MATERIAL'),
            ),
          ),
          if (_pendingMaterial != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: (_pendingMaterialIsInvoiceOnly
                        ? Colors.orange
                        : Colors.teal)
                    .withValues(alpha: 0.12),
                border: Border.all(
                  color: _pendingMaterialIsInvoiceOnly
                      ? Colors.orangeAccent
                      : Colors.teal,
                ),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _pendingMaterial!['numero_parte']?.toString() ?? '',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _pendingMaterial!['especificacion_material']?.toString() ??
                        'Sin descripción',
                    style: const TextStyle(color: Colors.white70),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Existencia en almacén: $_pendingMaterialAvailable${_pendingMaterialInvoiceQuantity > 0 ? ' · Pendiente por invoice: $_pendingMaterialInvoiceQuantity' : ''}',
                    style: TextStyle(
                      color: _pendingMaterialIsInvoiceOnly
                          ? Colors.orangeAccent
                          : Colors.white60,
                      fontWeight: _pendingMaterialIsInvoiceOnly
                          ? FontWeight.bold
                          : FontWeight.normal,
                    ),
                  ),
                  if (_pendingMaterialIsInvoiceOnly)
                    Text(
                      _pendingMaterialInvoices.isEmpty
                          ? 'Sin material en almacén; existe material pendiente por invoice.'
                          : 'Pendiente en: $_pendingMaterialInvoices',
                      style: const TextStyle(
                        color: Colors.orangeAccent,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _packController,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly
                          ],
                          onChanged: (_) => _syncTotalFromUnits(),
                          decoration: const InputDecoration(
                            labelText: 'Cant. por empaque',
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _unitsController,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly
                          ],
                          onChanged: (_) => _syncTotalFromUnits(),
                          decoration: const InputDecoration(
                            labelText: 'Unidades',
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (_usesUnits)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        '$_packSize × $_unitCount = ${_packSize! * _unitCount} pzas',
                        style: const TextStyle(
                          color: Colors.tealAccent,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      SizedBox(
                        width: 110,
                        child: TextField(
                          controller: _quantityController,
                          keyboardType: TextInputType.number,
                          readOnly: _usesUnits,
                          decoration:
                              const InputDecoration(labelText: 'Cantidad *'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _addPendingMaterial,
                          icon: const Icon(Icons.add),
                          label: const Text('AGREGAR'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMaterialSuggestions() {
    return Container(
      constraints: const BoxConstraints(maxHeight: 280),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1E2C),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.teal.withValues(alpha: 0.55)),
      ),
      child: ListView.separated(
        shrinkWrap: true,
        padding: EdgeInsets.zero,
        itemCount: _materialSuggestions.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final material = _materialSuggestions[index];
          final partNumber = material['numero_parte']?.toString() ?? '';
          final specification =
              material['especificacion_material']?.toString() ?? '';
          final code = material['codigo_material']?.toString() ?? '';
          final available =
              _asMobileRequirementInt(material['cantidad_disponible']);
          final pending =
              _asMobileRequirementInt(material['cantidad_pendiente_entrada']);
          final pendingOnly = available <= 0 && pending > 0;
          return ListTile(
            dense: true,
            leading: Icon(
              pendingOnly ? Icons.pending_actions : Icons.inventory_2_outlined,
              color: pendingOnly ? Colors.orangeAccent : Colors.tealAccent,
            ),
            title: Text(
              partNumber,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (specification.isNotEmpty)
                  Text(
                    specification,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white70),
                  ),
                if (code.isNotEmpty)
                  Text(
                    'Código: $code',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white38, fontSize: 11),
                  ),
                Text(
                  pendingOnly
                      ? 'Sin existencia · +$pending pendiente por invoice'
                      : 'Existencia: $available',
                  style: TextStyle(
                    color: pendingOnly ? Colors.orangeAccent : Colors.white54,
                    fontSize: 11,
                    fontWeight:
                        pendingOnly ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ],
            ),
            trailing: const Icon(Icons.chevron_right, color: Colors.white38),
            onTap: () => _selectMaterialSuggestion(material),
          );
        },
      ),
    );
  }

  Widget _buildDraftSection() {
    return _SectionCard(
      title: 'Materiales (${_draft.items.length})',
      icon: Icons.inventory_2_outlined,
      child: _draft.isEmpty
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: Text(
                  'Aún no hay materiales agregados.',
                  style: TextStyle(color: Colors.white54),
                ),
              ),
            )
          : Column(
              children: List.generate(_draft.items.length, (index) {
                final item = _draft.items[index];
                return Card(
                  color: const Color(0xFF1A1E2C),
                  child: ListTile(
                    title: Text(
                      item.partNumber,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.description.isEmpty
                              ? 'Sin descripción'
                              : item.description,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white60),
                        ),
                        if (item.packSize != null && item.units != null)
                          Text(
                            '${item.packSize} × ${item.units} unidades = ${item.quantity}',
                            style: const TextStyle(
                              color: Colors.tealAccent,
                              fontSize: 11,
                            ),
                          ),
                      ],
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        InkWell(
                          onTap: () => _editQuantity(index),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.teal.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              'x${item.quantity}',
                              style: const TextStyle(
                                color: Colors.tealAccent,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: () =>
                              setState(() => _draft.removeAt(index)),
                          icon: const Icon(Icons.delete_outline,
                              color: Colors.red),
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget child;

  const _SectionCard({
    required this.title,
    required this.icon,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF252A3C),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: Colors.tealAccent, size: 20),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class _RequirementScannerPage extends StatefulWidget {
  const _RequirementScannerPage();

  @override
  State<_RequirementScannerPage> createState() =>
      _RequirementScannerPageState();
}

class _RequirementScannerPageState extends State<_RequirementScannerPage> {
  MobileScannerController? _controller;
  final _readerController = TextEditingController();
  String? _detectedCode;

  @override
  void initState() {
    super.initState();
    if (ScannerConfigService.isCameraMode) {
      _controller = MobileScannerController(
        detectionSpeed: DetectionSpeed.normal,
        facing: CameraFacing.back,
      );
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    _readerController.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (capture.barcodes.isEmpty) return;
    final code = capture.barcodes.first.rawValue?.trim();
    if (code == null || code.isEmpty || code == _detectedCode) return;
    setState(() => _detectedCode = code);
  }

  void _submitReader(String value) {
    final code = value.trim();
    if (code.isNotEmpty) Navigator.pop(context, code);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A1E2C),
      appBar: AppBar(
        title: Text(ScannerConfigService.isCameraMode
            ? 'Escanear material'
            : 'Lector / PDA'),
        backgroundColor: const Color(0xFF252A3C),
      ),
      body: ScannerConfigService.isReaderMode
          ? Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.barcode_reader,
                      color: Colors.white54, size: 80),
                  const SizedBox(height: 20),
                  const Text(
                    'Escanea con el lector y presiona Enter.',
                    style: TextStyle(color: Colors.white, fontSize: 17),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: _readerController,
                    autofocus: true,
                    onSubmitted: _submitReader,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      labelText: 'Código leído',
                      prefixIcon: Icon(Icons.qr_code),
                    ),
                  ),
                ],
              ),
            )
          : Stack(
              fit: StackFit.expand,
              children: [
                MobileScanner(controller: _controller!, onDetect: _onDetect),
                Center(
                  child: Container(
                    width: 280,
                    height: 180,
                    decoration: BoxDecoration(
                      border: Border.all(
                        color:
                            _detectedCode == null ? Colors.teal : Colors.green,
                        width: 4,
                      ),
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
                Positioned(
                  left: 20,
                  right: 20,
                  bottom: 28,
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.black87,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: [
                        Text(
                          _detectedCode ?? 'Apunta la cámara al código',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 10),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: _detectedCode == null
                                ? null
                                : () => Navigator.pop(context, _detectedCode),
                            icon: const Icon(Icons.check),
                            label: const Text('USAR CÓDIGO'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
