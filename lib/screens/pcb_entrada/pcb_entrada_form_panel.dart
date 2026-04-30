import 'package:flutter/material.dart';
import 'package:dropdown_button2/dropdown_button2.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:material_warehousing_flutter/core/localization/app_translations.dart';
import 'package:material_warehousing_flutter/core/theme/app_colors.dart';
import 'package:material_warehousing_flutter/core/widgets/field_decoration.dart';
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
  final FocusNode _scanFocusNode = FocusNode();

  String _selectedProceso = 'SMD';
  String _selectedArea = 'INVENTARIO';
  DateTime _inventoryDate = DateTime.now();
  bool _isLoading = false;
  String? _statusMessage;
  bool _statusIsError = false;
  List<int> _lastInsertedIds = [];
  int _pendingArrayRemaining = 0;
  int _pendingArrayCount = 1;
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
  }

  @override
  void dispose() {
    _scanController.dispose();
    _commentController.dispose();
    _dateController.dispose();
    _arrayCountController.dispose();
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
        });
      }
    } catch (_) {}
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
    } catch (_) {}
  }

  int _getArrayCount() {
    final value = int.tryParse(_arrayCountController.text.trim()) ?? 1;
    return value < 1 ? 1 : value;
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
    final effectiveArea = isArrayItem ? _pendingArrayTargetArea : _selectedArea;
    final arrayGroupCode =
        isArrayItem ? _pendingArrayGroupCode : _normalizePcbCode(code);
    final arrayRole = arrayCount > 1
        ? (!isArrayItem && _selectedArea == 'REPARACION'
            ? 'DEFECT'
            : 'ARRAY_ITEM')
        : 'SINGLE';

    if (arrayCount > 99) {
      setState(() {
        _statusMessage = tr('pcb_invalid_array_count');
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
          _pendingArrayRemaining -= 1;
          if (_pendingArrayRemaining <= 0) {
            _clearPendingArray();
            nextMessage =
                '${tr('pcb_array_complete')}: ${data?['pcb_part_no'] ?? ''} - ${data?['modelo'] ?? 'N/A'}';
          } else {
            nextMessage =
                '${tr('pcb_scan_saved')}: ${data?['pcb_part_no'] ?? ''} | ${tr('pcb_array_remaining')}: $_pendingArrayRemaining ($_pendingArrayTargetArea)';
          }
        } else if (arrayCount > 1) {
          _pendingArrayRemaining = arrayCount - 1;
          _pendingArrayCount = arrayCount;
          _pendingArrayGroupCode = _normalizePcbCode(code);
          _pendingArrayParentCode = code;
          _pendingArrayTargetArea =
              _selectedArea == 'REPARACION' ? 'INVENTARIO' : _selectedArea;
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
    return Container(
      color: AppColors.panelBackground,
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
                color: Colors.cyan.withOpacity(0.12),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: Colors.cyan.withOpacity(0.30)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.qr_code_scanner,
                      color: Colors.cyan, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${tr('pcb_scan_remaining_array')}: $_pendingArrayRemaining / ${_pendingArrayCount - 1} ($_pendingArrayTargetArea)',
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
                              ? Colors.red.withOpacity(0.15)
                              : Colors.green.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                              color: _statusIsError
                                  ? Colors.red.withOpacity(0.3)
                                  : Colors.green.withOpacity(0.3)),
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
