import 'package:flutter/material.dart';
import 'package:dropdown_button2/dropdown_button2.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:material_warehousing_flutter/core/localization/app_translations.dart';
import 'package:material_warehousing_flutter/core/theme/app_colors.dart';
import 'package:material_warehousing_flutter/core/widgets/field_decoration.dart';
import 'package:material_warehousing_flutter/core/services/api_service.dart';
import 'package:material_warehousing_flutter/core/services/auth_service.dart';

class PcbSalidaFormPanel extends StatefulWidget {
  final LanguageProvider languageProvider;
  final VoidCallback onDataSaved;

  const PcbSalidaFormPanel({
    super.key,
    required this.languageProvider,
    required this.onDataSaved,
  });

  @override
  State<PcbSalidaFormPanel> createState() => PcbSalidaFormPanelState();
}

class PcbSalidaFormPanelState extends State<PcbSalidaFormPanel> {
  final TextEditingController _scanController = TextEditingController();
  final TextEditingController _commentController = TextEditingController();
  final TextEditingController _dateController = TextEditingController();
  final FocusNode _scanFocusNode = FocusNode();

  String _selectedProceso = 'SMD';
  String _selectedArea = 'INVENTARIO';
  String _tipoMovimiento = 'SALIDA'; // SALIDA or SCRAP
  DateTime _inventoryDate = DateTime.now();
  bool _isLoading = false;
  String? _statusMessage;
  bool _statusIsError = false;
  List<int> _lastInsertedIds = [];

  static const List<String> _procesos = ['SMD', 'IMD', 'ASSY'];
  static const List<String> _areas = ['INVENTARIO', 'REPARACION'];

  String tr(String key) => widget.languageProvider.tr(key);

  Color get _accentColor =>
      _tipoMovimiento == 'SCRAP' ? Colors.red : Colors.orange;

  String get _formattedDate =>
      '${_inventoryDate.year}-${_inventoryDate.month.toString().padLeft(2, '0')}-${_inventoryDate.day.toString().padLeft(2, '0')}';

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
      final savedProcess = prefs.getString('pcb_salida_last_process');
      final savedArea = prefs.getString('pcb_salida_last_area');
      final savedComment = prefs.getString('pcb_salida_last_comment');
      final savedTipo = prefs.getString('pcb_salida_last_tipo');
      if (mounted) {
        setState(() {
          if (savedProcess != null && _procesos.contains(savedProcess)) {
            _selectedProceso = savedProcess;
          }
          if (savedArea != null && _areas.contains(savedArea)) {
            _selectedArea = savedArea;
          }
          if (savedComment != null) _commentController.text = savedComment;
          if (savedTipo != null &&
              (savedTipo == 'SALIDA' || savedTipo == 'SCRAP')) {
            _tipoMovimiento = savedTipo;
          }
        });
      }
    } catch (_) {}
  }

  Future<void> _saveLocalPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('pcb_salida_last_process', _selectedProceso);
      await prefs.setString('pcb_salida_last_area', _selectedArea);
      await prefs.setString('pcb_salida_last_comment', _commentController.text);
      await prefs.setString('pcb_salida_last_tipo', _tipoMovimiento);
    } catch (_) {}
  }

  Future<void> _onScan() async {
    final code = _scanController.text.trim();
    if (code.isEmpty) return;

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
      area: _selectedArea,
      tipoMovimiento: _tipoMovimiento,
      comentarios:
          _commentController.text.isNotEmpty ? _commentController.text : null,
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
        final isArrayExit = result['array_exit'] == true;
        final totalQty = result['total_qty'] ?? _lastInsertedIds.length;
        setState(() {
          _statusMessage = isArrayExit
              ? '$_tipoMovimiento ${tr('pcb_array_complete')}: $totalQty PCBs'
              : '$_tipoMovimiento: ${data?['pcb_part_no'] ?? ''} - ${data?['modelo'] ?? 'N/A'} (${data?['proceso'] ?? ''})';
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
        else if (errorCode == 'ARRAY_INCOMPLETE')
          msg = tr('pcb_array_incomplete');
        else if (errorCode == 'ARRAY_ALREADY_OUT')
          msg = tr('pcb_array_already_out');
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
      });
      widget.onDataSaved();
    }
  }

  Widget _buildTipoButton(String tipo, String label, Color color) {
    final isSelected = _tipoMovimiento == tipo;
    return InkWell(
      onTap: () {
        setState(() => _tipoMovimiento = tipo);
        _saveLocalPrefs();
      },
      borderRadius: BorderRadius.circular(4),
      child: Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 18),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color:
              isSelected ? color.withOpacity(0.25) : AppColors.fieldBackground,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
              color: isSelected ? color : AppColors.border,
              width: isSelected ? 2 : 1),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? color : Colors.white70,
            fontSize: 13,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.panelBackground,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Fila 1: Tipo selector + Area + Proceso
          Row(
            children: [
              SizedBox(
                width: 60,
                child: Text(tr('pcb_tipo_movimiento'),
                    style: const TextStyle(fontSize: 14, color: Colors.white)),
              ),
              const SizedBox(width: 8),
              _buildTipoButton('SALIDA', tr('pcb_tab_salida'), Colors.orange),
              const SizedBox(width: 6),
              _buildTipoButton('SCRAP', tr('pcb_tab_scrap'), Colors.red),
              const SizedBox(width: 24),
              SizedBox(
                width: 60,
                child: Text(tr('pcb_area'),
                    style: const TextStyle(fontSize: 14, color: Colors.white)),
              ),
              SizedBox(
                width: 170,
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
                  onChanged: (val) {
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
                width: 70,
                child: Text(tr('pcb_proceso'),
                    style: const TextStyle(fontSize: 14, color: Colors.white)),
              ),
              SizedBox(
                width: 150,
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
                  onChanged: (val) {
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
                      onPressed: _pickDate,
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
          // Fila 3: Scan field principal + Undo + Status
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
                  style: TextStyle(
                      fontSize: 14,
                      color: _accentColor,
                      fontWeight: FontWeight.w600),
                  decoration: fieldDecoration().copyWith(
                    hintText: '${tr('pcb_scan_field')} ($_tipoMovimiento)',
                    hintStyle:
                        const TextStyle(fontSize: 12, color: Colors.white38),
                    prefixIcon: Icon(Icons.qr_code_scanner,
                        color: _accentColor, size: 18),
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
                    icon: Icon(Icons.undo, color: _accentColor, size: 20),
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
                              : _accentColor.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                              color: _statusIsError
                                  ? Colors.red.withOpacity(0.3)
                                  : _accentColor.withOpacity(0.3)),
                        ),
                        child: Text(
                          _statusMessage!,
                          style: TextStyle(
                              color: _statusIsError
                                  ? Colors.redAccent
                                  : _accentColor,
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
