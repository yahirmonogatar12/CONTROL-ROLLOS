import 'package:flutter/material.dart';
import 'package:dropdown_button2/dropdown_button2.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:material_warehousing_flutter/core/localization/app_translations.dart';
import 'package:material_warehousing_flutter/core/theme/app_colors.dart';
import 'package:material_warehousing_flutter/core/widgets/field_decoration.dart';
import 'package:material_warehousing_flutter/core/widgets/table_dropdown_field.dart';
import 'package:material_warehousing_flutter/core/services/api_service.dart';
import 'package:material_warehousing_flutter/core/services/auth_service.dart';

class PcbEntradaFormPanel extends StatefulWidget {
  final LanguageProvider languageProvider;
  final VoidCallback onDataSaved;

  const PcbEntradaFormPanel({
    super.key,
    required this.languageProvider,
    required this.onDataSaved,
  });

  @override
  State<PcbEntradaFormPanel> createState() => PcbEntradaFormPanelState();
}

class PcbEntradaFormPanelState extends State<PcbEntradaFormPanel> {
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
  List<int> _lastInsertedIds = [];
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

  void requestScanFocus() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _scanFocusNode.requestFocus();
    });
  }

  Future<void> _loadLocalPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedProcess = prefs.getString('pcb_entrada_last_process');
      final savedArea = prefs.getString('pcb_entrada_last_area');
      final savedComment = prefs.getString('pcb_entrada_last_comment');
      final savedArrayCount = prefs.getString('pcb_entrada_last_array_count');
      final savedRepairCount = prefs.getString('pcb_entrada_last_repair_count');
      final savedDefectType = prefs.getString('pcb_entrada_last_defect_type');
      final savedComponentLocation =
          prefs.getString('pcb_entrada_last_component_location');
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

  Future<void> _saveLocalPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('pcb_entrada_last_process', _selectedProceso);
      await prefs.setString('pcb_entrada_last_area', _selectedArea);
      await prefs.setString(
          'pcb_entrada_last_comment', _commentController.text);
      await prefs.setString(
          'pcb_entrada_last_array_count', _arrayCountController.text);
      await prefs.setString(
          'pcb_entrada_last_repair_count', _repairCountController.text);
      if (_selectedDefectType != null) {
        await prefs.setString(
            'pcb_entrada_last_defect_type', _selectedDefectType!);
      }
      await prefs.setString('pcb_entrada_last_component_location',
          _componentLocationController.text);
    } catch (_) {}
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

  List<List<String>> get _defectRows {
    return _defects.map((defect) {
      return [
        defect['defect_name']?.toString() ?? '',
        defect['description']?.toString() ?? '',
      ];
    }).toList();
  }

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
    requestScanFocus();
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
      requestScanFocus();
      return;
    }

    if (!isArrayItem &&
        _selectedArea == 'REPARACION' &&
        (repairCount > arrayCount || repairCount < 1)) {
      setState(() {
        _statusMessage = tr('pcb_invalid_repair_count');
        _statusIsError = true;
      });
      requestScanFocus();
      return;
    }

    if (isRepairEntry &&
        (_selectedDefectType == null || _selectedDefectType!.isEmpty)) {
      setState(() {
        _statusMessage = tr('pcb_defect_required');
        _statusIsError = true;
      });
      requestScanFocus();
      return;
    }

    if (!AuthService.canWritePcbInventory) {
      setState(() {
        _statusMessage = tr('pcb_no_write_permission');
        _statusIsError = true;
      });
      _scanController.clear();
      requestScanFocus();
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

    if (mounted) {
      if (result['success'] == true) {
        final data = result['data'];
        final ids = (result['inserted_ids'] as List?)
            ?.map((id) => (id as num).toInt())
            .toList();
        final fallbackId = data?['id'] is num ? (data['id'] as num).toInt() : 0;
        _lastInsertedIds = ids?.isNotEmpty == true
            ? ids!
            : (fallbackId > 0 ? [fallbackId] : []);
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
        widget.onDataSaved();
      } else {
        final errorCode = result['code'] ?? '';
        String msg = result['message'] ?? tr('pcb_scan_error');
        if (errorCode == 'DUPLICATE_SCAN')
          msg = tr('pcb_duplicate_scan');
        else if (errorCode == 'INVALID_PCB_PART_NO')
          msg = tr('pcb_invalid_part_no');
        else if (errorCode == 'INVALID_PROCESO')
          msg = tr('pcb_invalid_proceso');
        else if (errorCode == 'INVALID_ARRAY_COUNT')
          msg = tr('pcb_invalid_array_count');
        else if (errorCode == 'MISSING_DEFECT_TYPE' ||
            errorCode == 'INVALID_DEFECT_TYPE') msg = tr('pcb_defect_required');
        setState(() {
          _statusMessage = msg;
          _statusIsError = true;
        });
        _scanController.clear();
      }
      setState(() => _isLoading = false);
      requestScanFocus();
    }
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

  Future<void> _undoLastScan() async {
    if (_lastInsertedIds.isEmpty) return;
    var ok = true;
    for (final id in _lastInsertedIds.reversed) {
      final result = await ApiService.deletePcbInventoryScan(id);
      ok = ok && result['success'] == true;
    }
    if (ok) {
      setState(() {
        _statusMessage = tr('pcb_scan_deleted');
        _statusIsError = false;
        _lastInsertedIds = [];
        if (_hasPendingArrayScans) _clearPendingArray();
      });
      widget.onDataSaved();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isRepairContext = _hasPendingArrayScans
        ? _pendingArrayTargetArea == 'REPARACION'
        : _selectedArea == 'REPARACION';
    final defectRows = _defectRows;
    final selectedDefectValue = defectRows
            .any((row) => row.isNotEmpty && row.first == _selectedDefectType)
        ? _selectedDefectType
        : null;

    return Container(
      color: AppColors.subPanelBackground,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Fila 1: Area + Proceso + Fecha
          Row(
            children: [
              SizedBox(
                width: 60,
                child: Text(tr('pcb_area'),
                    style: const TextStyle(fontSize: 14, color: Colors.white)),
              ),
              SizedBox(
                width: 180,
                child: DropdownButtonFormField2<String>(
                  decoration: fieldDecoration(),
                  value: _selectedArea,
                  isExpanded: true,
                  style: const TextStyle(fontSize: 14, color: Colors.white),
                  items: _areas
                      .map((a) => DropdownMenuItem(
                            value: a,
                            child:
                                Text(a, style: const TextStyle(fontSize: 14)),
                          ))
                      .toList(),
                  onChanged: _hasPendingArrayScans
                      ? null
                      : (val) {
                          if (val != null) {
                            setState(() => _selectedArea = val);
                            _saveLocalPrefs();
                          }
                        },
                  iconStyleData: const IconStyleData(
                    icon: Icon(Icons.arrow_drop_down,
                        color: Colors.white70, size: 20),
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
              const SizedBox(width: 24),
              SizedBox(
                width: 80,
                child: Text(tr('pcb_proceso'),
                    style: const TextStyle(fontSize: 14, color: Colors.white)),
              ),
              SizedBox(
                width: 160,
                child: DropdownButtonFormField2<String>(
                  decoration: fieldDecoration(),
                  value: _selectedProceso,
                  isExpanded: true,
                  style: const TextStyle(fontSize: 14, color: Colors.white),
                  items: _procesos
                      .map((p) => DropdownMenuItem(
                            value: p,
                            child:
                                Text(p, style: const TextStyle(fontSize: 14)),
                          ))
                      .toList(),
                  onChanged: _hasPendingArrayScans
                      ? null
                      : (val) {
                          if (val != null) {
                            setState(() => _selectedProceso = val);
                            _saveLocalPrefs();
                          }
                        },
                  iconStyleData: const IconStyleData(
                    icon: Icon(Icons.arrow_drop_down,
                        color: Colors.white70, size: 20),
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
              const SizedBox(width: 24),
              SizedBox(
                width: 90,
                child: Text(tr('pcb_array_count'),
                    style: const TextStyle(fontSize: 14, color: Colors.white)),
              ),
              SizedBox(
                width: 80,
                child: TextFormField(
                  controller: _arrayCountController,
                  decoration: fieldDecoration(),
                  style: const TextStyle(fontSize: 14),
                  enabled: !_hasPendingArrayScans,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  onChanged: (_) => _saveLocalPrefs(),
                ),
              ),
              const SizedBox(width: 24),
              SizedBox(
                width: 90,
                child: Text(tr('pcb_repair_count'),
                    style: const TextStyle(fontSize: 14, color: Colors.white)),
              ),
              SizedBox(
                width: 70,
                child: TextFormField(
                  controller: _repairCountController,
                  decoration: fieldDecoration(),
                  style: const TextStyle(fontSize: 14),
                  enabled:
                      !_hasPendingArrayScans && _selectedArea == 'REPARACION',
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  onChanged: (_) => _saveLocalPrefs(),
                ),
              ),
              const SizedBox(width: 24),
              SizedBox(
                width: 60,
                child: Text(tr('pcb_date'),
                    style: const TextStyle(fontSize: 14, color: Colors.white)),
              ),
              Expanded(
                child: TextFormField(
                  controller: _dateController,
                  decoration: fieldDecoration().copyWith(
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.calendar_today,
                          color: Colors.white70, size: 18),
                      onPressed: _hasPendingArrayScans ? null : _pickDate,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                    suffixIconConstraints:
                        const BoxConstraints(minWidth: 30, minHeight: 20),
                  ),
                  style: const TextStyle(fontSize: 14),
                  readOnly: true,
                ),
              ),
            ],
          ),
          if (_hasPendingArrayScans) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.cyan.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: Colors.cyan.withValues(alpha: 0.30)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.qr_code_scanner,
                      color: Colors.cyan, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${tr('pcb_scan_remaining_array')}: $_pendingArrayRemaining / ${_pendingArrayCount - 1} ($_pendingArrayTargetArea) | ${tr('pcb_area_repair_short')}: $_pendingRepairRemaining, ${tr('pcb_area_inventory_short')}: $_pendingInventoryRemaining',
                      style: const TextStyle(
                          color: Colors.cyan,
                          fontSize: 12,
                          fontWeight: FontWeight.w600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _cancelPendingArray,
                    icon: const Icon(Icons.close, size: 14),
                    label: Text(tr('pcb_cancel_array'),
                        style: const TextStyle(fontSize: 11)),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.white70,
                      minimumSize: const Size(0, 28),
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          // Fila 2: Defecto + Ubicacion de componente (solo reparacion)
          Row(
            children: [
              SizedBox(
                width: 100,
                child: Text(tr('pcb_defect_type'),
                    style: const TextStyle(fontSize: 14, color: Colors.white)),
              ),
              SizedBox(
                width: 220,
                child: Opacity(
                  opacity: isRepairContext ? 1 : 0.55,
                  child: IgnorePointer(
                    ignoring: !isRepairContext,
                    child: TableDropdownField(
                      value: selectedDefectValue ?? '',
                      headers: [tr('pcb_defect_type'), tr('description')],
                      rows: defectRows,
                      tableWidth: 520,
                      tableHeight: 300,
                      onRowSelected: (index) {
                        if (index < 0 || index >= defectRows.length) return;
                        final defectName = defectRows[index].isNotEmpty
                            ? defectRows[index][0]
                            : '';
                        if (defectName.isEmpty) return;
                        setState(() => _selectedDefectType = defectName);
                        _saveLocalPrefs();
                      },
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                height: 36,
                width: 36,
                child: IconButton(
                  onPressed: _loadDefects,
                  icon: const Icon(Icons.refresh,
                      color: Colors.white70, size: 18),
                  tooltip: tr('pcb_refresh_defects'),
                  padding: EdgeInsets.zero,
                ),
              ),
              const SizedBox(width: 18),
              SizedBox(
                width: 150,
                child: Text(tr('pcb_component_location'),
                    style: const TextStyle(fontSize: 14, color: Colors.white)),
              ),
              Expanded(
                child: TextFormField(
                  controller: _componentLocationController,
                  decoration: fieldDecoration().copyWith(
                    hintText: tr('pcb_component_location_hint'),
                    hintStyle:
                        const TextStyle(fontSize: 12, color: Colors.white38),
                  ),
                  style: const TextStyle(fontSize: 14),
                  enabled: isRepairContext,
                  textCapitalization: TextCapitalization.characters,
                  onChanged: (_) => _saveLocalPrefs(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Fila 2: Comentarios
          Row(
            children: [
              SizedBox(
                width: 100,
                child: Text(tr('pcb_comentarios'),
                    style: const TextStyle(fontSize: 14, color: Colors.white)),
              ),
              Expanded(
                child: TextFormField(
                  controller: _commentController,
                  decoration: fieldDecoration(),
                  style: const TextStyle(fontSize: 14),
                  onChanged: (_) => _saveLocalPrefs(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Fila 2: Scan field principal + Undo + Status
          Row(
            children: [
              SizedBox(
                width: 100,
                child: Text(tr('pcb_scan_field'),
                    style: const TextStyle(fontSize: 14, color: Colors.white)),
              ),
              Expanded(
                flex: 3,
                child: TextField(
                  controller: _scanController,
                  focusNode: _scanFocusNode,
                  style: const TextStyle(
                      fontSize: 14,
                      color: Colors.cyan,
                      fontWeight: FontWeight.w600),
                  decoration: fieldDecoration().copyWith(
                    hintText: tr('pcb_scan_field'),
                    hintStyle:
                        const TextStyle(fontSize: 12, color: Colors.white38),
                    prefixIcon: const Icon(Icons.qr_code_scanner,
                        color: Colors.cyan, size: 18),
                    prefixIconConstraints:
                        const BoxConstraints(minWidth: 32, minHeight: 20),
                    suffixIcon: _isLoading
                        ? const Padding(
                            padding: EdgeInsets.all(8),
                            child: SizedBox(
                                width: 16,
                                height: 16,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2)),
                          )
                        : null,
                  ),
                  onSubmitted: (_) => _onScan(),
                ),
              ),
              if (_lastInsertedIds.isNotEmpty) ...[
                const SizedBox(width: 8),
                SizedBox(
                  height: 36,
                  width: 36,
                  child: IconButton(
                    onPressed: _undoLastScan,
                    icon:
                        const Icon(Icons.undo, color: Colors.orange, size: 20),
                    tooltip: tr('pcb_undo_last'),
                    padding: EdgeInsets.zero,
                  ),
                ),
              ],
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: _statusMessage != null
                    ? Container(
                        height: 36,
                        alignment: Alignment.centerLeft,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        decoration: BoxDecoration(
                          color: _statusIsError
                              ? Colors.red.withValues(alpha: 0.15)
                              : Colors.green.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                              color: _statusIsError
                                  ? Colors.red.withValues(alpha: 0.3)
                                  : Colors.green.withValues(alpha: 0.3)),
                        ),
                        child: Text(
                          _statusMessage!,
                          style: TextStyle(
                              color: _statusIsError
                                  ? Colors.redAccent
                                  : Colors.green,
                              fontSize: 13),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      )
                    : const SizedBox(),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
