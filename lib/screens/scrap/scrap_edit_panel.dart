import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_warehousing_flutter/core/localization/app_translations.dart';
import 'package:material_warehousing_flutter/core/services/api_service.dart';
import 'package:material_warehousing_flutter/core/services/auth_service.dart';
import 'package:material_warehousing_flutter/core/theme/app_colors.dart';
import 'package:material_warehousing_flutter/core/widgets/field_decoration.dart';
import 'package:material_warehousing_flutter/core/widgets/table_dropdown_field.dart';

class ScrapEditPanel extends StatefulWidget {
  final LanguageProvider languageProvider;
  final Map<String, dynamic> rowData;
  final VoidCallback onClose;
  final VoidCallback onSaved;

  const ScrapEditPanel({
    super.key,
    required this.languageProvider,
    required this.rowData,
    required this.onClose,
    required this.onSaved,
  });

  @override
  State<ScrapEditPanel> createState() => _ScrapEditPanelState();
}

class _ScrapEditPanelState extends State<ScrapEditPanel> {
  late final TextEditingController _codeController;
  late final TextEditingController _rawBarcodeController;
  late final TextEditingController _commentsController;
  late final TextEditingController _qtyController;
  late final TextEditingController _reasonController;

  String _selectedArea = 'SMD';
  String _selectedProceso = 'SMT';
  int? _selectedMotivoId;
  String? _selectedMotivoText;
  bool _isSaving = false;
  bool _isLoadingMotivos = true;

  List<Map<String, dynamic>> _motivos = [];

  static const List<String> _areas = [
    'M1',
    'M2',
    'M3',
    'M4',
    'D1',
    'D2',
    'D3',
    'CALIDAD',
    'MANTENIMIENTO',
    'SMD',
    'IMD',
    'IPM',
    'COATING',
    'PROVEEDOR',
    'COMPONENTE',
  ];
  static const Map<String, String> _procesos = {
    'CALIDAD': 'Calidad',
    'ASSY': 'Assy',
    'IMD': 'IMD',
    'SMD': 'SMD',
    'SMT': 'SMT',
    'MANTENIMIENTO': 'Mantenimiento',
    'COATING': 'Coating',
    'MICOM': 'Micom',
    'COMPONENTE': 'Componente',
  };

  bool get _canEdit => AuthService.canEditScrapHistory;

  String tr(String key) => widget.languageProvider.tr(key);

  @override
  void initState() {
    super.initState();
    _initControllers();
    _loadMotivos();
  }

  void _initControllers() {
    _codeController = TextEditingController(
      text: widget.rowData['scanned_original']?.toString() ?? '',
    );
    _rawBarcodeController = TextEditingController(
      text: widget.rowData['raw_barcode']?.toString() ?? '',
    );
    _commentsController = TextEditingController(
      text: widget.rowData['comentarios']?.toString() ?? '',
    );
    _qtyController = TextEditingController(
      text: (widget.rowData['cantidad'] ?? 1).toString(),
    );
    _reasonController = TextEditingController();

    final area = widget.rowData['area']?.toString() ?? 'SMD';
    _selectedArea = _areas.contains(area) ? area : 'SMD';
    final proceso =
        widget.rowData['proceso']?.toString().toUpperCase() ?? 'SMT';
    _selectedProceso = _procesos.containsKey(proceso) ? proceso : 'SMT';
    _selectedMotivoId = _asInt(widget.rowData['motivo_scrap_id']);
    _selectedMotivoText = widget.rowData['motivo_scrap_texto']?.toString();
  }

  Future<void> _loadMotivos() async {
    final result = await ApiService.getScrapMotivos();
    if (!mounted) return;

    final motivos =
        (result['data'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final selectedExists =
        motivos.any((m) => _asInt(m['id']) == _selectedMotivoId);

    setState(() {
      _motivos = motivos;
      if (!selectedExists) {
        _selectedMotivoId =
            motivos.isNotEmpty ? _asInt(motivos.first['id']) : null;
        _selectedMotivoText =
            motivos.isNotEmpty ? motivos.first['motivo']?.toString() : null;
      }
      _isLoadingMotivos = false;
    });
  }

  @override
  void dispose() {
    _codeController.dispose();
    _rawBarcodeController.dispose();
    _commentsController.dispose();
    _qtyController.dispose();
    _reasonController.dispose();
    super.dispose();
  }

  int _asInt(dynamic value) {
    if (value is int) return value;
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  void _selectAll(TextEditingController controller) {
    final text = controller.text;
    controller.selection =
        TextSelection(baseOffset: 0, extentOffset: text.length);
  }

  void _showMessage(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red.shade700 : Colors.green.shade700,
      ),
    );
  }

  List<List<String>> get _motivoRows {
    return _motivos.map((m) {
      return [
        m['motivo']?.toString() ?? '',
        '',
      ];
    }).toList();
  }

  Future<void> _saveChanges() async {
    final currentUser = AuthService.currentUser;
    final id = _asInt(widget.rowData['id']);
    final code = _codeController.text.trim();
    final reason = _reasonController.text.trim();
    final qty = int.tryParse(_qtyController.text.trim()) ?? 0;

    if (!_canEdit) {
      _showMessage(tr('scrap_no_edit_permission'), isError: true);
      return;
    }

    if (id <= 0 ||
        currentUser == null ||
        code.isEmpty ||
        reason.isEmpty ||
        _selectedMotivoId == null ||
        qty < 1) {
      _showMessage(tr('scrap_required_field'), isError: true);
      return;
    }

    setState(() => _isSaving = true);

    final result = await ApiService.updateScrapRecord(
      id: id,
      scannedCode: code,
      area: _selectedArea,
      proceso: _selectedProceso,
      motivoScrapId: _selectedMotivoId!,
      comentarios: _commentsController.text.trim().isEmpty
          ? null
          : _commentsController.text.trim(),
      cantidad: qty,
      editReason: reason,
      editedByUserId: currentUser.id,
      editedByName: currentUser.nombreCompleto,
      rawBarcode: _rawBarcodeController.text.trim(),
    );

    if (!mounted) return;

    setState(() => _isSaving = false);

    if (result['success'] == true) {
      _showMessage(tr('scrap_history_updated'));
      widget.onSaved();
      widget.onClose();
      return;
    }

    final codeResult = result['code']?.toString();
    var message = result['message']?.toString() ?? tr('scrap_scan_error');
    if (codeResult == 'DUPLICATE_SCAN') {
      message = tr('scrap_duplicate_scan');
    } else if (codeResult == 'INVALID_PROCESO') {
      message = tr('scrap_invalid_proceso');
    }
    _showMessage(message, isError: true);
  }

  Widget _buildEditableField(
    String label,
    TextEditingController controller, {
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
    int maxLines = 1,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(color: Colors.white70, fontSize: 11)),
          const SizedBox(height: 4),
          TextField(
            controller: controller,
            keyboardType: keyboardType,
            inputFormatters: inputFormatters,
            maxLines: maxLines,
            style: const TextStyle(color: Colors.white, fontSize: 12),
            onTap: () => _selectAll(controller),
            decoration: fieldDecoration().copyWith(
              isDense: true,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAreaDropdown() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(tr('scrap_area'),
              style: const TextStyle(color: Colors.white70, fontSize: 11)),
          const SizedBox(height: 4),
          Container(
            height: 32,
            decoration: BoxDecoration(
              color: AppColors.fieldBackground,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: AppColors.border),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _selectedArea,
                isExpanded: true,
                dropdownColor: AppColors.panelBackground,
                style: const TextStyle(color: Colors.white, fontSize: 12),
                padding: const EdgeInsets.symmetric(horizontal: 8),
                items: _areas
                    .map((area) => DropdownMenuItem(
                          value: area,
                          child: Text(area),
                        ))
                    .toList(),
                onChanged: _isSaving
                    ? null
                    : (value) {
                        if (value != null)
                          setState(() => _selectedArea = value);
                      },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMotivoDropdown() {
    final motivoRows = _motivoRows;
    final selectedValue = motivoRows
            .any((row) => row.isNotEmpty && row.first == _selectedMotivoText)
        ? _selectedMotivoText
        : '';

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(tr('scrap_motivo'),
              style: const TextStyle(color: Colors.white70, fontSize: 11)),
          const SizedBox(height: 4),
          if (_isLoadingMotivos)
            const SizedBox(
              height: 32,
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else
            TableDropdownField(
              value: selectedValue ?? '',
              headers: [tr('scrap_motivo'), tr('description')],
              rows: motivoRows,
              tableWidth: 420,
              tableHeight: 300,
              onRowSelected: (index) {
                if (index < 0 || index >= _motivos.length) return;
                final motivo = _motivos[index];
                setState(() {
                  _selectedMotivoId = _asInt(motivo['id']);
                  _selectedMotivoText = motivo['motivo']?.toString();
                });
              },
            ),
        ],
      ),
    );
  }

  Widget _buildProcesoDropdown() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(tr('scrap_proceso'),
              style: const TextStyle(color: Colors.white70, fontSize: 11)),
          const SizedBox(height: 4),
          Container(
            height: 32,
            decoration: BoxDecoration(
              color: AppColors.fieldBackground,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: AppColors.border),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _selectedProceso,
                isExpanded: true,
                dropdownColor: AppColors.panelBackground,
                style: const TextStyle(color: Colors.white, fontSize: 12),
                padding: const EdgeInsets.symmetric(horizontal: 8),
                items: _procesos.entries
                    .map((entry) => DropdownMenuItem(
                          value: entry.key,
                          child: Text(entry.value),
                        ))
                    .toList(),
                onChanged: _isSaving
                    ? null
                    : (value) {
                        if (value != null) {
                          setState(() => _selectedProceso = value);
                        }
                      },
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 340,
      decoration: const BoxDecoration(
        color: AppColors.panelBackground,
        border: Border(left: BorderSide(color: AppColors.border, width: 1)),
      ),
      child: Column(
        children: [
          Container(
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: const BoxDecoration(
              color: AppColors.gridHeader,
              border: Border(bottom: BorderSide(color: AppColors.border)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  tr('scrap_edit_history'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                IconButton(
                  onPressed: _isSaving ? null : widget.onClose,
                  icon:
                      const Icon(Icons.close, color: Colors.white70, size: 20),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  splashRadius: 16,
                ),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildEditableField(
                      tr('scrap_scanned_code'), _codeController),
                  _buildEditableField(
                      tr('scrap_raw_barcode'), _rawBarcodeController),
                  _buildAreaDropdown(),
                  _buildProcesoDropdown(),
                  _buildMotivoDropdown(),
                  _buildEditableField(
                    'Cantidad',
                    _qtyController,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  ),
                  _buildEditableField(
                    tr('scrap_comentarios'),
                    _commentsController,
                    maxLines: 3,
                  ),
                  _buildEditableField(
                    tr('scrap_edit_reason'),
                    _reasonController,
                    maxLines: 3,
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: SizedBox(
              width: double.infinity,
              height: 36,
              child: Tooltip(
                message: _canEdit ? '' : tr('scrap_no_edit_permission'),
                child: ElevatedButton(
                  onPressed: (_isSaving || !_canEdit) ? null : _saveChanges,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _canEdit ? Colors.orange : Colors.grey,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: Colors.grey.shade700,
                  ),
                  child: _isSaving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(
                          tr('scrap_save_changes'),
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
