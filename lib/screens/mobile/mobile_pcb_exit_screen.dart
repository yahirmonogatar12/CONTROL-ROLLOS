import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:dropdown_button2/dropdown_button2.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:material_warehousing_flutter/core/localization/app_translations.dart';
import 'package:material_warehousing_flutter/core/services/api_service.dart';
import 'package:material_warehousing_flutter/core/services/auth_service.dart';
import 'package:material_warehousing_flutter/core/theme/app_colors.dart';
import 'package:material_warehousing_flutter/core/widgets/field_decoration.dart';

class _PcbManualExitSelection {
  final int qty;
  final String? area;
  final String? proceso;

  const _PcbManualExitSelection({
    required this.qty,
    this.area,
    this.proceso,
  });
}

/// Pantalla móvil de SALIDA / SCRAP de PCBs.
/// Adaptación compacta de [pcb_salida_form_panel.dart] para PDA/handheld.
class MobilePcbExitScreen extends StatefulWidget {
  final LanguageProvider languageProvider;

  const MobilePcbExitScreen({
    super.key,
    required this.languageProvider,
  });

  @override
  State<MobilePcbExitScreen> createState() => _MobilePcbExitScreenState();
}

class _MobilePcbExitScreenState extends State<MobilePcbExitScreen> {
  final TextEditingController _scanController = TextEditingController();
  final TextEditingController _commentController = TextEditingController();
  final TextEditingController _dateController = TextEditingController();
  final FocusNode _scanFocusNode = FocusNode();

  String _selectedProceso = 'SMD';
  String _selectedArea = 'INVENTARIO';
  String _tipoMovimiento = 'SALIDA';
  DateTime _inventoryDate = DateTime.now();
  bool _isLoading = false;
  String? _statusMessage;
  bool _statusIsError = false;

  static const List<String> _procesos = ['SMD', 'IMD', 'ASSY'];
  static const List<String> _areas = ['INVENTARIO', 'REPARACION'];

  String tr(String key) => widget.languageProvider.tr(key);

  Color get _accentColor =>
      _tipoMovimiento == 'SCRAP' ? Colors.redAccent : Colors.orangeAccent;

  String get _formattedDate =>
      '${_inventoryDate.year}-${_inventoryDate.month.toString().padLeft(2, '0')}-${_inventoryDate.day.toString().padLeft(2, '0')}';

  @override
  void initState() {
    super.initState();
    _dateController.text = _formattedDate;
    _loadLocalPrefs();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _scanFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _scanController.dispose();
    _commentController.dispose();
    _dateController.dispose();
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
      final savedProcess = prefs.getString('mobile_pcb_exit_last_process');
      final savedArea = prefs.getString('mobile_pcb_exit_last_area');
      final savedComment = prefs.getString('mobile_pcb_exit_last_comment');
      final savedTipo = prefs.getString('mobile_pcb_exit_last_tipo');
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
      await prefs.setString('mobile_pcb_exit_last_process', _selectedProceso);
      await prefs.setString('mobile_pcb_exit_last_area', _selectedArea);
      await prefs.setString(
          'mobile_pcb_exit_last_comment', _commentController.text);
      await prefs.setString('mobile_pcb_exit_last_tipo', _tipoMovimiento);
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
      _requestScanFocus();
      return;
    }

    setState(() {
      _isLoading = true;
      _statusMessage = null;
    });

    await _submitScan(code: code);
  }

  Future<void> _submitScan({
    required String code,
    int qty = 1,
    bool manualQtyConfirmed = false,
    String? initialStockArea,
    String? initialStockProceso,
  }) async {
    final result = await ApiService.scanPcbInventory(
      scannedCode: code,
      inventoryDate: _formattedDate,
      proceso: _selectedProceso,
      area: _selectedArea,
      tipoMovimiento: _tipoMovimiento,
      qty: qty,
      manualQtyConfirmed: manualQtyConfirmed,
      initialStockArea: initialStockArea,
      initialStockProceso: initialStockProceso,
      comentarios:
          _commentController.text.isNotEmpty ? _commentController.text : null,
      scannedBy: AuthService.currentUser?.nombreCompleto,
    );

    if (!mounted) return;

    if (result['success'] == true) {
      final data = result['data'];
      final isArrayExit = result['array_exit'] == true;
      final totalQty = result['total_qty'] ??
          ((result['inserted_ids'] as List?)?.length ?? 1);
      setState(() {
        _statusMessage = isArrayExit
            ? '$_tipoMovimiento ${tr('pcb_array_complete')}: $totalQty PCBs'
            : '$_tipoMovimiento: ${data?['pcb_part_no'] ?? ''} - ${data?['modelo'] ?? 'N/A'} (${data?['proceso'] ?? ''})';
        _statusIsError = false;
      });
      _scanController.clear();
      _saveLocalPrefs();
    } else {
      final errorCode = result['code'] ?? '';
      if (errorCode == 'PCB_QR_NOT_IN_INVENTORY' &&
          !manualQtyConfirmed &&
          _tipoMovimiento == 'SALIDA' &&
          result['manual_allowed'] == true) {
        setState(() => _isLoading = false);
        final manualSelection = await _showManualQtyDialog(result);
        if (manualSelection != null && mounted) {
          setState(() {
            _isLoading = true;
            _statusMessage = null;
          });
          await _submitScan(
            code: code,
            qty: manualSelection.qty,
            manualQtyConfirmed: true,
            initialStockArea: manualSelection.area,
            initialStockProceso: manualSelection.proceso,
          );
          return;
        }
        _scanController.clear();
        _requestScanFocus();
        return;
      }

      String msg = result['message'] ?? tr('pcb_scan_error');
      if (errorCode == 'DUPLICATE_SCAN') {
        msg = tr('pcb_duplicate_scan');
      } else if (errorCode == 'INVALID_PCB_PART_NO') {
        msg = tr('pcb_invalid_part_no');
      } else if (errorCode == 'INVALID_PROCESO') {
        msg = tr('pcb_invalid_proceso');
      } else if (errorCode == 'ARRAY_INCOMPLETE') {
        msg = tr('pcb_array_incomplete');
      } else if (errorCode == 'ARRAY_ALREADY_OUT') {
        msg = tr('pcb_array_already_out');
      } else if (errorCode == 'INSUFFICIENT_STOCK' ||
          errorCode == 'INSUFFICIENT_QR_STOCK') {
        msg = tr('pcb_insufficient_stock');
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

  Future<_PcbManualExitSelection?> _showManualQtyDialog(
      Map<String, dynamic> scanResult) async {
    final qtyController = TextEditingController(text: '1');
    final partNo = scanResult['pcb_part_no']?.toString() ?? _extractPcbPartNo();
    final stockOptions = (scanResult['stock_options'] as List? ?? [])
        .whereType<Map<String, dynamic>>()
        .toList();
    Map<String, dynamic>? selectedOption = stockOptions.isNotEmpty
        ? stockOptions.firstWhere(
            (option) =>
                option['area']?.toString() == scanResult['area']?.toString() &&
                option['proceso']?.toString() ==
                    scanResult['proceso']?.toString(),
            orElse: () => stockOptions.first,
          )
        : null;
    final result = await showDialog<_PcbManualExitSelection>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            final availableStock =
                selectedOption?['available_stock']?.toString() ??
                    scanResult['available_stock']?.toString() ??
                    '0';
            final autoArea = selectedOption?['area']?.toString() ??
                scanResult['area']?.toString() ??
                '';
            final autoProceso = selectedOption?['proceso']?.toString() ??
                scanResult['proceso']?.toString() ??
                '';
            _PcbManualExitSelection? buildSelection() {
              final qty = int.tryParse(qtyController.text.trim()) ?? 0;
              if (qty <= 0) return null;
              return _PcbManualExitSelection(
                qty: qty,
                area: autoArea.isNotEmpty ? autoArea : null,
                proceso: autoProceso.isNotEmpty ? autoProceso : null,
              );
            }

            return AlertDialog(
              backgroundColor: AppColors.panelBackground,
              title: Text(tr('pcb_manual_exit_title'),
                  style: const TextStyle(color: Colors.white, fontSize: 16)),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${tr('pcb_part_no')}: $partNo',
                      style:
                          const TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                    if (stockOptions.length > 1) ...[
                      const SizedBox(height: 10),
                      DropdownButtonFormField<Map<String, dynamic>>(
                        initialValue: selectedOption,
                        decoration: fieldDecoration().copyWith(
                          labelText: tr('pcb_auto_area_process'),
                          labelStyle: const TextStyle(
                              color: Colors.white70, fontSize: 12),
                        ),
                        dropdownColor: AppColors.fieldBackground,
                        style:
                            const TextStyle(color: Colors.white, fontSize: 13),
                        items: stockOptions
                            .map(
                              (option) =>
                                  DropdownMenuItem<Map<String, dynamic>>(
                                value: option,
                                child: Text(
                                  '${option['area']} / ${option['proceso']} - ${tr('pcb_available_stock')}: ${option['available_stock']}',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: (value) {
                          if (value == null) return;
                          setDialogState(() => selectedOption = value);
                        },
                      ),
                    ],
                    const SizedBox(height: 6),
                    Text(
                      '${tr('pcb_available_stock')}: $availableStock',
                      style: const TextStyle(
                          color: Colors.greenAccent, fontSize: 13),
                    ),
                    if (autoArea.isNotEmpty || autoProceso.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        '${tr('pcb_auto_area_process')}: $autoArea / $autoProceso',
                        style: const TextStyle(
                            color: Colors.cyanAccent, fontSize: 13),
                      ),
                    ],
                    const SizedBox(height: 14),
                    TextField(
                      controller: qtyController,
                      autofocus: true,
                      decoration: fieldDecoration().copyWith(
                        labelText: tr('pcb_qty_to_exit'),
                        labelStyle: const TextStyle(
                            color: Colors.white70, fontSize: 12),
                      ),
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      onSubmitted: (_) {
                        final selection = buildSelection();
                        if (selection != null) Navigator.pop(ctx, selection);
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text(tr('cancel'),
                      style: const TextStyle(color: Colors.white70)),
                ),
                ElevatedButton(
                  style:
                      ElevatedButton.styleFrom(backgroundColor: _accentColor),
                  onPressed: () {
                    final selection = buildSelection();
                    if (selection != null) Navigator.pop(ctx, selection);
                  },
                  child: Text(tr('confirm'),
                      style: const TextStyle(color: Colors.white)),
                ),
              ],
            );
          },
        );
      },
    );
    qtyController.dispose();
    return result;
  }

  String _extractPcbPartNo() {
    final parts = _scanController.text
        .split(';')
        .map((part) => part.trim().toUpperCase())
        .toList();
    return parts.length > 2 ? parts[2] : '';
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
    return Container(
      color: const Color(0xFF1A1E2C),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildTipoSelector(),
              const SizedBox(height: 12),
              _buildScanField(),
              const SizedBox(height: 12),
              if (_statusMessage != null) ...[
                _buildStatusBanner(),
                const SizedBox(height: 12),
              ],
              _buildProcesoAreaRow(),
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

  Widget _buildTipoSelector() {
    return Row(
      children: [
        Expanded(
          child: _buildTipoButton(
            'SALIDA',
            tr('pcb_tab_salida'),
            Colors.orangeAccent,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _buildTipoButton(
            'SCRAP',
            tr('pcb_tab_scrap'),
            Colors.redAccent,
          ),
        ),
      ],
    );
  }

  Widget _buildTipoButton(String tipo, String label, Color color) {
    final isSelected = _tipoMovimiento == tipo;
    return InkWell(
      onTap: () {
        setState(() => _tipoMovimiento = tipo);
        _saveLocalPrefs();
        _requestScanFocus();
      },
      borderRadius: BorderRadius.circular(8),
      child: Container(
        height: 48,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isSelected
              ? color.withValues(alpha: 0.22)
              : const Color(0xFF252A3C),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? color : AppColors.border,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? color : Colors.white70,
            fontSize: 16,
            fontWeight: isSelected ? FontWeight.w800 : FontWeight.w500,
          ),
        ),
      ),
    );
  }

  Widget _buildScanField() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF252A3C),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _accentColor, width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.qr_code_scanner, color: _accentColor, size: 22),
              const SizedBox(width: 8),
              Text(
                tr('pcb_scan_field'),
                style: TextStyle(
                  color: _accentColor,
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
        style:
            TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget _buildProcesoAreaRow() {
    return Row(
      children: [
        Expanded(
          child: _buildLabeledDropdown(
            label: tr('pcb_proceso'),
            value: _selectedProceso,
            items: _procesos,
            onChanged: (val) {
              if (val != null) {
                setState(() => _selectedProceso = val);
                _saveLocalPrefs();
              }
            },
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _buildLabeledDropdown(
            label: tr('pcb_area'),
            value: _selectedArea,
            items: _areas,
            onChanged: (val) {
              if (val != null) {
                setState(() => _selectedArea = val);
                _saveLocalPrefs();
              }
            },
          ),
        ),
      ],
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
          onTap: _pickDate,
          style: const TextStyle(color: Colors.white, fontSize: 14),
          decoration: fieldDecoration().copyWith(
            suffixIcon: IconButton(
              icon: const Icon(Icons.calendar_today,
                  color: Colors.white70, size: 18),
              onPressed: _pickDate,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCommentField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(tr('pcb_comentarios'),
            style: const TextStyle(color: Colors.white70, fontSize: 12)),
        const SizedBox(height: 4),
        TextField(
          controller: _commentController,
          maxLines: 2,
          onChanged: (_) => _saveLocalPrefs(),
          style: const TextStyle(color: Colors.white, fontSize: 14),
          decoration: fieldDecoration(),
        ),
      ],
    );
  }

  Widget _buildLabeledDropdown({
    required String label,
    required String? value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
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
          style: const TextStyle(fontSize: 14, color: Colors.white),
          items: items
              .map((v) => DropdownMenuItem(
                    value: v,
                    child: Text(v, style: const TextStyle(fontSize: 14)),
                  ))
              .toList(),
          onChanged: onChanged,
          iconStyleData: const IconStyleData(
            icon: Icon(Icons.arrow_drop_down, color: Colors.white70, size: 22),
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
}
