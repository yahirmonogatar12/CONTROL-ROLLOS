import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:dropdown_button2/dropdown_button2.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:material_warehousing_flutter/core/localization/app_translations.dart';
import 'package:material_warehousing_flutter/core/services/api_service.dart';
import 'package:material_warehousing_flutter/core/services/auth_service.dart';
import 'package:material_warehousing_flutter/core/theme/app_colors.dart';
import 'package:material_warehousing_flutter/core/widgets/field_decoration.dart';

/// Pantalla móvil de ENTRADA de PCBs.
/// Adaptación compacta de [pcb_entrada_form_panel.dart] para PDA/handheld.
/// Soporta arrays, reparación, defect_type y component_location.
class MobilePcbEntryScreen extends StatefulWidget {
  final LanguageProvider languageProvider;

  const MobilePcbEntryScreen({
    super.key,
    required this.languageProvider,
  });

  @override
  State<MobilePcbEntryScreen> createState() => _MobilePcbEntryScreenState();
}

class _MobilePcbEntryScreenState extends State<MobilePcbEntryScreen> {
  final TextEditingController _scanController = TextEditingController();
  final TextEditingController _commentController = TextEditingController();
  final TextEditingController _dateController = TextEditingController();
  final TextEditingController _arrayCountController =
      TextEditingController(text: '1');
  final TextEditingController _repairCountController =
      TextEditingController(text: '1');
  final TextEditingController _componentLocationController =
      TextEditingController();
  final FocusNode _scanFocusNode = FocusNode();

  String _selectedProceso = 'SMD';
  String _selectedArea = 'INVENTARIO';
  String? _selectedDefectType;
  List<Map<String, dynamic>> _defects = [];
  DateTime _inventoryDate = DateTime.now();
  bool _isLoading = false;
  String? _statusMessage;
  bool _statusIsError = false;

  int _pendingArrayRemaining = 0;
  int _pendingArrayCount = 1;
  int _pendingRepairRemaining = 0;
  int _pendingInventoryRemaining = 0;
  String? _pendingArrayGroupCode;
  String? _pendingArrayParentCode;
  String _pendingArrayTargetArea = 'INVENTARIO';

  static const List<String> _procesos = ['SMD', 'IMD', 'ASSY'];
  static const List<String> _areas = ['INVENTARIO', 'REPARACION'];

  String tr(String key) => widget.languageProvider.tr(key);

  String get _formattedDate =>
      '${_inventoryDate.year}-${_inventoryDate.month.toString().padLeft(2, '0')}-${_inventoryDate.day.toString().padLeft(2, '0')}';

  bool get _hasPendingArrayScans => _pendingArrayRemaining > 0;

  @override
  void initState() {
    super.initState();
    _dateController.text = _formattedDate;
    _loadLocalPrefs();
    _loadDefects();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _scanFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _scanController.dispose();
    _commentController.dispose();
    _dateController.dispose();
    _arrayCountController.dispose();
    _repairCountController.dispose();
    _componentLocationController.dispose();
    _scanFocusNode.dispose();
    super.dispose();
  }

  void _requestScanFocus() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _scanFocusNode.requestFocus();
    });
  }

  Future<void> _loadLocalPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedProcess = prefs.getString('mobile_pcb_entry_last_process');
      final savedArea = prefs.getString('mobile_pcb_entry_last_area');
      final savedComment = prefs.getString('mobile_pcb_entry_last_comment');
      final savedArrayCount =
          prefs.getString('mobile_pcb_entry_last_array_count');
      final savedRepairCount =
          prefs.getString('mobile_pcb_entry_last_repair_count');
      final savedDefectType =
          prefs.getString('mobile_pcb_entry_last_defect_type');
      final savedComponentLocation =
          prefs.getString('mobile_pcb_entry_last_component_location');
      if (mounted) {
        setState(() {
          if (savedProcess != null && _procesos.contains(savedProcess)) {
            _selectedProceso = savedProcess;
          }
          if (savedArea != null && _areas.contains(savedArea)) {
            _selectedArea = savedArea;
          }
          if (savedComment != null) _commentController.text = savedComment;
          if (savedArrayCount != null &&
              (int.tryParse(savedArrayCount) ?? 0) > 0) {
            _arrayCountController.text = savedArrayCount;
          }
          if (savedRepairCount != null &&
              (int.tryParse(savedRepairCount) ?? 0) > 0) {
            _repairCountController.text = savedRepairCount;
          }
          if (savedDefectType != null && savedDefectType.isNotEmpty) {
            _selectedDefectType = savedDefectType;
          }
          if (savedComponentLocation != null) {
            _componentLocationController.text = savedComponentLocation;
          }
        });
      }
    } catch (_) {}
  }

  Future<void> _saveLocalPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('mobile_pcb_entry_last_process', _selectedProceso);
      await prefs.setString('mobile_pcb_entry_last_area', _selectedArea);
      await prefs.setString(
          'mobile_pcb_entry_last_comment', _commentController.text);
      await prefs.setString(
          'mobile_pcb_entry_last_array_count', _arrayCountController.text);
      await prefs.setString(
          'mobile_pcb_entry_last_repair_count', _repairCountController.text);
      if (_selectedDefectType != null) {
        await prefs.setString(
            'mobile_pcb_entry_last_defect_type', _selectedDefectType!);
      }
      await prefs.setString('mobile_pcb_entry_last_component_location',
          _componentLocationController.text);
    } catch (_) {}
  }

  Future<void> _loadDefects() async {
    final defects = await ApiService.getPcbDefects();
    if (!mounted) return;
    setState(() {
      _defects = defects;
      final names = _defects.map((d) => d['defect_name']?.toString()).toSet();
      if (_selectedDefectType != null && !names.contains(_selectedDefectType)) {
        _selectedDefectType = null;
      }
    });
  }

  int _getArrayCount() {
    final value = int.tryParse(_arrayCountController.text.trim()) ?? 1;
    return value < 1 ? 1 : value;
  }

  int _getRepairCount() {
    if (_selectedArea != 'REPARACION') return 0;
    final value = int.tryParse(_repairCountController.text.trim()) ?? 1;
    return value < 1 ? 1 : value;
  }

  void _updatePendingArrayTargetArea() {
    _pendingArrayTargetArea =
        _pendingRepairRemaining > 0 ? 'REPARACION' : 'INVENTARIO';
  }

  String _normalizePcbCode(String code) =>
      code.trim().toUpperCase().replaceAll(RegExp(r'\s+'), '');

  String? _buildComments({required bool isArrayItem}) {
    final parts = <String>[];
    final comment = _commentController.text.trim();
    if (comment.isNotEmpty) parts.add(comment);
    if (isArrayItem && _pendingArrayParentCode != null) {
      parts.add('${tr('pcb_same_array_as')}: $_pendingArrayParentCode');
    }
    return parts.isEmpty ? null : parts.join(' | ');
  }

  void _clearPendingArray() {
    _pendingArrayRemaining = 0;
    _pendingArrayCount = 1;
    _pendingRepairRemaining = 0;
    _pendingInventoryRemaining = 0;
    _pendingArrayGroupCode = null;
    _pendingArrayParentCode = null;
    _pendingArrayTargetArea = 'INVENTARIO';
  }

  void _cancelPendingArray() {
    setState(() {
      _clearPendingArray();
      _statusMessage = tr('pcb_array_cancelled');
      _statusIsError = false;
    });
    _requestScanFocus();
  }

  Future<void> _onScan() async {
    final code = _scanController.text.trim();
    if (code.isEmpty) return;
    final isArrayItem = _hasPendingArrayScans;
    final arrayCount = isArrayItem ? _pendingArrayCount : _getArrayCount();
    final repairCount = isArrayItem ? 0 : _getRepairCount();
    final effectiveArea = isArrayItem ? _pendingArrayTargetArea : _selectedArea;
    final isRepairEntry = effectiveArea == 'REPARACION';
    final arrayGroupCode =
        isArrayItem ? _pendingArrayGroupCode : _normalizePcbCode(code);
    final arrayRole = arrayCount > 1
        ? (effectiveArea == 'REPARACION' ? 'DEFECT' : 'ARRAY_ITEM')
        : 'SINGLE';

    if (arrayCount > 99) {
      setState(() {
        _statusMessage = tr('pcb_invalid_array_count');
        _statusIsError = true;
      });
      _requestScanFocus();
      return;
    }

    if (!isArrayItem &&
        _selectedArea == 'REPARACION' &&
        (repairCount > arrayCount || repairCount < 1)) {
      setState(() {
        _statusMessage = tr('pcb_invalid_repair_count');
        _statusIsError = true;
      });
      _requestScanFocus();
      return;
    }

    if (isRepairEntry &&
        (_selectedDefectType == null || _selectedDefectType!.isEmpty)) {
      setState(() {
        _statusMessage = tr('pcb_defect_required');
        _statusIsError = true;
      });
      _requestScanFocus();
      return;
    }

    if (!AuthService.canWritePcbInventory) {
      setState(() {
        _statusMessage = tr('pcb_no_write_permission');
        _statusIsError = true;
      });
      _scanController.clear();
      _requestScanFocus();
      return;
    }

    setState(() {
      _isLoading = true;
      _statusMessage = null;
    });

    final result = await ApiService.scanPcbInventory(
      scannedCode: code,
      inventoryDate: _formattedDate,
      proceso: _selectedProceso,
      area: effectiveArea,
      tipoMovimiento: 'ENTRADA',
      arrayCount: arrayCount,
      qty: 1,
      arrayGroupCode: arrayGroupCode,
      arrayRole: arrayRole,
      defectType: isRepairEntry ? _selectedDefectType : null,
      componentLocation:
          isRepairEntry && _componentLocationController.text.trim().isNotEmpty
              ? _componentLocationController.text.trim()
              : null,
      comentarios: _buildComments(isArrayItem: isArrayItem),
      scannedBy: AuthService.currentUser?.nombreCompleto,
    );

    if (!mounted) return;

    if (result['success'] == true) {
      final data = result['data'];
      String nextMessage;
      if (isArrayItem) {
        if (effectiveArea == 'REPARACION' && _pendingRepairRemaining > 0) {
          _pendingRepairRemaining -= 1;
        } else if (_pendingInventoryRemaining > 0) {
          _pendingInventoryRemaining -= 1;
        }
        _pendingArrayRemaining =
            _pendingRepairRemaining + _pendingInventoryRemaining;
        if (_pendingArrayRemaining <= 0) {
          _clearPendingArray();
          nextMessage =
              '${tr('pcb_array_complete')}: ${data?['pcb_part_no'] ?? ''} - ${data?['modelo'] ?? 'N/A'}';
        } else {
          _updatePendingArrayTargetArea();
          nextMessage =
              '${tr('pcb_scan_saved')}: ${data?['pcb_part_no'] ?? ''} | ${tr('pcb_array_remaining')}: $_pendingArrayRemaining ($_pendingArrayTargetArea)';
        }
      } else if (arrayCount > 1) {
        _pendingArrayCount = arrayCount;
        _pendingArrayGroupCode = _normalizePcbCode(code);
        _pendingArrayParentCode = code;
        if (_selectedArea == 'REPARACION') {
          _pendingRepairRemaining = repairCount - 1;
          _pendingInventoryRemaining = arrayCount - repairCount;
        } else {
          _pendingRepairRemaining = 0;
          _pendingInventoryRemaining = arrayCount - 1;
        }
        _pendingArrayRemaining =
            _pendingRepairRemaining + _pendingInventoryRemaining;
        _updatePendingArrayTargetArea();
        nextMessage =
            '${tr('pcb_scan_saved')}: ${data?['pcb_part_no'] ?? ''} | ${tr('pcb_array_remaining')}: $_pendingArrayRemaining ($_pendingArrayTargetArea)';
      } else {
        nextMessage =
            '${tr('pcb_scan_saved')}: ${data?['pcb_part_no'] ?? ''} - ${data?['modelo'] ?? 'N/A'} (${data?['proceso'] ?? ''})';
      }
      setState(() {
        _statusMessage = nextMessage;
        _statusIsError = false;
      });
      _scanController.clear();
      _saveLocalPrefs();
    } else {
      final errorCode = result['code'] ?? '';
      String msg = result['message'] ?? tr('pcb_scan_error');
      if (errorCode == 'DUPLICATE_SCAN') {
        msg = tr('pcb_duplicate_scan');
      } else if (errorCode == 'INVALID_PCB_PART_NO') {
        msg = tr('pcb_invalid_part_no');
      } else if (errorCode == 'INVALID_PROCESO') {
        msg = tr('pcb_invalid_proceso');
      } else if (errorCode == 'INVALID_ARRAY_COUNT') {
        msg = tr('pcb_invalid_array_count');
      } else if (errorCode == 'MISSING_DEFECT_TYPE' ||
          errorCode == 'INVALID_DEFECT_TYPE') {
        msg = tr('pcb_defect_required');
      }
      setState(() {
        _statusMessage = msg;
        _statusIsError = true;
      });
      _scanController.clear();
    }

    setState(() => _isLoading = false);
    _requestScanFocus();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _inventoryDate,
      firstDate: DateTime(2024),
      lastDate: DateTime(2030),
    );
    if (picked != null && mounted) {
      setState(() {
        _inventoryDate = picked;
        _dateController.text = _formattedDate;
      });
    }
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    final isRepairContext = _hasPendingArrayScans
        ? _pendingArrayTargetArea == 'REPARACION'
        : _selectedArea == 'REPARACION';

    return Container(
      color: const Color(0xFF1A1E2C),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_hasPendingArrayScans) _buildPendingBanner(),
              _buildScanField(isRepairContext),
              const SizedBox(height: 12),
              if (_statusMessage != null) ...[
                _buildStatusBanner(),
                const SizedBox(height: 12),
              ],
              _buildProcesoAreaRow(),
              const SizedBox(height: 10),
              _buildArrayRow(),
              if (isRepairContext) ...[
                const SizedBox(height: 10),
                _buildDefectField(),
                const SizedBox(height: 10),
                _buildComponentLocationField(),
              ],
              const SizedBox(height: 10),
              _buildDateField(),
              const SizedBox(height: 10),
              _buildCommentField(),
              if (_isLoading) ...[
                const SizedBox(height: 14),
                const Center(child: CircularProgressIndicator()),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPendingBanner() {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.amber.withValues(alpha: 0.18),
        border: Border.all(color: Colors.amber, width: 1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const Icon(Icons.layers, color: Colors.amber, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${tr('pcb_array_remaining')}: $_pendingArrayRemaining',
                  style: const TextStyle(
                    color: Colors.amber,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
                Text(
                  '${tr('pcb_scan_remaining_array')} ($_pendingArrayTargetArea)',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ),
          TextButton.icon(
            onPressed: _cancelPendingArray,
            icon: const Icon(Icons.close, color: Colors.redAccent, size: 18),
            label: Text(
              tr('pcb_cancel_array'),
              style: const TextStyle(color: Colors.redAccent, fontSize: 12),
            ),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: const Size(0, 32),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScanField(bool isRepairContext) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF252A3C),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isRepairContext ? Colors.orange : AppColors.headerTab,
          width: 2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.qr_code_scanner,
                color: isRepairContext ? Colors.orange : AppColors.headerTab,
                size: 22,
              ),
              const SizedBox(width: 8),
              Text(
                tr('pcb_scan_field'),
                style: TextStyle(
                  color: isRepairContext ? Colors.orange : AppColors.headerTab,
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _scanController,
            focusNode: _scanFocusNode,
            autofocus: true,
            enabled: !_isLoading,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _onScan(),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              letterSpacing: 1.0,
            ),
            decoration: fieldDecoration(hintText: 'EBR########').copyWith(
              suffixIcon: IconButton(
                icon: const Icon(Icons.send, color: Colors.white70),
                onPressed: _isLoading ? null : _onScan,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBanner() {
    final color = _statusIsError ? Colors.redAccent : Colors.greenAccent;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        border: Border.all(color: color, width: 1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        _statusMessage ?? '',
        style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget _buildProcesoAreaRow() {
    return Row(
      children: [
        Expanded(child: _buildLabeledDropdown(
          label: tr('pcb_proceso'),
          value: _selectedProceso,
          items: _procesos,
          enabled: !_hasPendingArrayScans,
          onChanged: (val) {
            if (val != null) {
              setState(() => _selectedProceso = val);
              _saveLocalPrefs();
            }
          },
        )),
        const SizedBox(width: 10),
        Expanded(child: _buildLabeledDropdown(
          label: tr('pcb_area'),
          value: _selectedArea,
          items: _areas,
          enabled: !_hasPendingArrayScans,
          onChanged: (val) {
            if (val != null) {
              setState(() => _selectedArea = val);
              _saveLocalPrefs();
            }
          },
        )),
      ],
    );
  }

  Widget _buildArrayRow() {
    return Row(
      children: [
        Expanded(
          child: _buildLabeledTextField(
            label: tr('pcb_array_count'),
            controller: _arrayCountController,
            enabled: !_hasPendingArrayScans,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _buildLabeledTextField(
            label: tr('pcb_repair_count'),
            controller: _repairCountController,
            enabled: !_hasPendingArrayScans && _selectedArea == 'REPARACION',
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          ),
        ),
      ],
    );
  }

  Widget _buildDefectField() {
    final defectNames = _defects
        .map((d) => d['defect_name']?.toString() ?? '')
        .where((s) => s.isNotEmpty)
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(tr('pcb_defect_type'),
            style: const TextStyle(color: Colors.white70, fontSize: 12)),
        const SizedBox(height: 4),
        Autocomplete<String>(
          // Re-key with the saved defect so cargar prefs después del primer
          // build refleje el valor en el campo.
          key: ValueKey('defect_autocomplete_${_selectedDefectType ?? ''}'),
          initialValue: TextEditingValue(text: _selectedDefectType ?? ''),
          optionsBuilder: (textValue) {
            final query = textValue.text.trim().toLowerCase();
            if (query.isEmpty) return defectNames;
            return defectNames
                .where((d) => d.toLowerCase().contains(query));
          },
          onSelected: (val) {
            setState(() => _selectedDefectType = val);
            _saveLocalPrefs();
            FocusScope.of(context).unfocus();
          },
          fieldViewBuilder: (context, controller, focusNode, onSubmit) {
            return TextField(
              controller: controller,
              focusNode: focusNode,
              style: const TextStyle(color: Colors.white, fontSize: 14),
              decoration: fieldDecoration(hintText: tr('pcb_select_defect'))
                  .copyWith(
                suffixIcon: controller.text.isEmpty
                    ? const Icon(Icons.search,
                        color: Colors.white54, size: 18)
                    : IconButton(
                        icon: const Icon(Icons.clear,
                            color: Colors.white54, size: 18),
                        onPressed: () {
                          controller.clear();
                          setState(() => _selectedDefectType = null);
                          _saveLocalPrefs();
                        },
                      ),
              ),
              onChanged: (val) {
                final exact = defectNames.firstWhere(
                  (d) => d.toLowerCase() == val.trim().toLowerCase(),
                  orElse: () => '',
                );
                final newValue = exact.isEmpty ? null : exact;
                if (newValue != _selectedDefectType) {
                  setState(() => _selectedDefectType = newValue);
                  if (newValue != null) _saveLocalPrefs();
                }
              },
            );
          },
          optionsViewBuilder: (context, onSelected, options) {
            return Align(
              alignment: Alignment.topLeft,
              child: Material(
                color: AppColors.panelBackground,
                elevation: 6,
                borderRadius: BorderRadius.circular(6),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: 240,
                    maxWidth: MediaQuery.of(context).size.width - 24,
                  ),
                  child: ListView.separated(
                    shrinkWrap: true,
                    padding: EdgeInsets.zero,
                    itemCount: options.length,
                    separatorBuilder: (_, __) =>
                        const Divider(height: 1, color: Colors.white12),
                    itemBuilder: (context, idx) {
                      final option = options.elementAt(idx);
                      return InkWell(
                        onTap: () => onSelected(option),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 12),
                          child: Text(
                            option,
                            style: const TextStyle(
                                color: Colors.white, fontSize: 14),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildComponentLocationField() {
    return _buildLabeledTextField(
      label: tr('pcb_component_location'),
      controller: _componentLocationController,
      hintText: tr('pcb_component_location_hint'),
      onChanged: (_) => _saveLocalPrefs(),
    );
  }

  Widget _buildDateField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(tr('pcb_date'),
            style: const TextStyle(color: Colors.white70, fontSize: 12)),
        const SizedBox(height: 4),
        TextField(
          controller: _dateController,
          readOnly: true,
          onTap: _hasPendingArrayScans ? null : _pickDate,
          style: const TextStyle(color: Colors.white, fontSize: 14),
          decoration: fieldDecoration().copyWith(
            suffixIcon: IconButton(
              icon: const Icon(Icons.calendar_today,
                  color: Colors.white70, size: 18),
              onPressed: _hasPendingArrayScans ? null : _pickDate,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCommentField() {
    return _buildLabeledTextField(
      label: tr('pcb_comentarios'),
      controller: _commentController,
      maxLines: 2,
      onChanged: (_) => _saveLocalPrefs(),
    );
  }

  Widget _buildLabeledDropdown({
    required String label,
    required String? value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
    bool enabled = true,
    String? hint,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(color: Colors.white70, fontSize: 12)),
        const SizedBox(height: 4),
        DropdownButtonFormField2<String>(
          decoration: fieldDecoration(),
          value: value,
          isExpanded: true,
          hint: hint != null
              ? Text(hint,
                  style: const TextStyle(color: Colors.white38, fontSize: 13))
              : null,
          style: const TextStyle(fontSize: 14, color: Colors.white),
          items: items
              .map((v) => DropdownMenuItem(
                    value: v,
                    child: Text(v, style: const TextStyle(fontSize: 14)),
                  ))
              .toList(),
          onChanged: enabled ? onChanged : null,
          iconStyleData: const IconStyleData(
            icon: Icon(Icons.arrow_drop_down,
                color: Colors.white70, size: 22),
          ),
          dropdownStyleData: DropdownStyleData(
            maxHeight: 280,
            decoration: BoxDecoration(
              color: AppColors.fieldBackground,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          menuItemStyleData: const MenuItemStyleData(
            height: 36,
            padding: EdgeInsets.symmetric(horizontal: 10),
          ),
        ),
      ],
    );
  }

  Widget _buildLabeledTextField({
    required String label,
    required TextEditingController controller,
    bool enabled = true,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
    String? hintText,
    int maxLines = 1,
    ValueChanged<String>? onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(color: Colors.white70, fontSize: 12)),
        const SizedBox(height: 4),
        TextField(
          controller: controller,
          enabled: enabled,
          keyboardType: keyboardType,
          inputFormatters: inputFormatters,
          maxLines: maxLines,
          onChanged: onChanged,
          style: const TextStyle(color: Colors.white, fontSize: 14),
          decoration: fieldDecoration(hintText: hintText),
        ),
      ],
    );
  }
}
