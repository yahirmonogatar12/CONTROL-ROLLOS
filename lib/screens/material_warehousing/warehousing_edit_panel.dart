import 'package:flutter/material.dart';
import 'package:material_warehousing_flutter/core/localization/app_translations.dart';
import 'package:material_warehousing_flutter/core/theme/app_colors.dart';
import 'package:material_warehousing_flutter/core/services/api_service.dart';
import 'package:material_warehousing_flutter/core/services/auth_service.dart';

class WarehousingEditPanel extends StatefulWidget {
  final LanguageProvider languageProvider;
  final Map<String, dynamic> rowData;
  final VoidCallback onClose;
  final VoidCallback onSaved;
  
  const WarehousingEditPanel({
    super.key,
    required this.languageProvider,
    required this.rowData,
    required this.onClose,
    required this.onSaved,
  });

  @override
  State<WarehousingEditPanel> createState() => _WarehousingEditPanelState();
}

class _WarehousingEditPanelState extends State<WarehousingEditPanel> {
  late TextEditingController _warehousingCodeController;
  late TextEditingController _materialCodeController;
  late TextEditingController _partNumberController;
  late TextEditingController _materialLotNoController;
  late TextEditingController _currentQtyController;
  late TextEditingController _materialSpecController;
  late TextEditingController _locationController;
  String _selectedMaterialConsigned = 'Customer Supply';
  bool _isCancelled = false;
  bool _isSaving = false;
  
  // Estado de cancelación
  bool _hasPendingCancellation = false;
  Map<String, dynamic>? _pendingRequest;
  bool _loadingCancellationStatus = true;
  
  final List<String> _materialConsignedOptions = ['Customer Supply', 'Company Stock', 'Consignment'];
  
  // Verificar si el usuario puede editar
  bool get _canEdit => AuthService.canWriteWarehousing;
  
  // Verificar si el usuario puede aprobar cancelaciones directamente
  bool get _canApproveCancellation => AuthService.canApproveCancellation;

  String tr(String key) => widget.languageProvider.tr(key);

  @override
  void initState() {
    super.initState();
    _initControllers();
    _loadCancellationStatus();
  }

  void _initControllers() {
    _warehousingCodeController = TextEditingController(
      text: widget.rowData['codigo_material_recibido']?.toString() ?? ''
    );
    _materialCodeController = TextEditingController(
      text: widget.rowData['codigo_material']?.toString() ?? ''
    );
    _partNumberController = TextEditingController(
      text: widget.rowData['numero_parte']?.toString() ?? ''
    );
    _materialLotNoController = TextEditingController(
      text: widget.rowData['numero_lote_material']?.toString() ?? ''
    );
    _currentQtyController = TextEditingController(
      text: widget.rowData['cantidad_actual']?.toString() ?? '0'
    );
    _materialSpecController = TextEditingController(
      text: widget.rowData['especificacion']?.toString() ?? ''
    );
    _locationController = TextEditingController(
      text: widget.rowData['ubicacion_salida']?.toString() ?? ''
    );
    
    final consigned = widget.rowData['material_importacion_local']?.toString() ?? 'Customer Supply';
    if (_materialConsignedOptions.contains(consigned)) {
      _selectedMaterialConsigned = consigned;
    }
    
    _isCancelled = widget.rowData['cancelado']?.toString() == '1';
  }

  Future<void> _loadCancellationStatus() async {
    final id = widget.rowData['id'];
    if (id == null) return;
    
    final status = await ApiService.getCancellationStatus(id);
    if (mounted) {
      setState(() {
        _hasPendingCancellation = status['hasPendingRequest'] ?? false;
        _pendingRequest = status['pendingRequest'];
        _loadingCancellationStatus = false;
      });
    }
  }

  @override
  void dispose() {
    _warehousingCodeController.dispose();
    _materialCodeController.dispose();
    _partNumberController.dispose();
    _materialLotNoController.dispose();
    _currentQtyController.dispose();
    _materialSpecController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  Future<void> _saveChanges() async {
    final id = widget.rowData['id'];
    if (id == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr('error_no_id')), backgroundColor: Colors.red),
      );
      return;
    }

    setState(() => _isSaving = true);

    final updatedData = {
      'numero_lote_material': _materialLotNoController.text,
      'cantidad_actual': int.tryParse(_currentQtyController.text) ?? 0,
      'ubicacion_salida': _locationController.text,
      'material_importacion_local': _selectedMaterialConsigned,
      // Solo incluir cancelado si el usuario puede aprobar cancelaciones
      if (_canApproveCancellation) 'cancelado': _isCancelled ? 1 : 0,
    };

    final success = await ApiService.updateWarehousing(id, updatedData);

    setState(() => _isSaving = false);

    if (mounted) {
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('✓ ${tr('record_updated')}'), backgroundColor: Colors.green),
        );
        widget.onSaved();
        widget.onClose();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('✗ ${tr('error_updating')}'), backgroundColor: Colors.red),
        );
      }
    }
  }

  // Mostrar diálogo para solicitar cancelación
  Future<void> _showRequestCancellationDialog() async {
    final reasonController = TextEditingController();
    
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.panelBackground,
        title: Row(
          children: [
            const Icon(Icons.cancel_outlined, color: Colors.orange, size: 24),
            const SizedBox(width: 8),
            Text(tr('request_cancellation'), style: const TextStyle(color: Colors.white)),
          ],
        ),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                tr('cancellation_reason_prompt'),
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: reasonController,
                maxLines: 3,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: tr('enter_cancellation_reason'),
                  hintStyle: const TextStyle(color: Colors.white38),
                  filled: true,
                  fillColor: AppColors.fieldBackground,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(4),
                    borderSide: const BorderSide(color: AppColors.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(4),
                    borderSide: const BorderSide(color: AppColors.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(4),
                    borderSide: const BorderSide(color: Colors.orange),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.blue.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline, color: Colors.blue, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        tr('cancellation_approval_required'),
                        style: const TextStyle(color: Colors.blue, fontSize: 11),
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
            onPressed: () => Navigator.pop(context, false),
            child: Text(tr('cancel'), style: const TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () {
              if (reasonController.text.trim().isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(tr('reason_required')), backgroundColor: Colors.orange),
                );
                return;
              }
              Navigator.pop(context, true);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            child: Text(tr('send_request')),
          ),
        ],
      ),
    );

    if (result == true && reasonController.text.trim().isNotEmpty) {
      final id = widget.rowData['id'];
      final currentUser = AuthService.currentUser;
      
      setState(() => _isSaving = true);
      
      final response = await ApiService.requestCancellation(
        warehousingId: id,
        reason: reasonController.text.trim(),
        requestedBy: currentUser?.nombreCompleto ?? currentUser?.username ?? 'Unknown',
        requestedById: currentUser?.id,
      );
      
      setState(() => _isSaving = false);
      
      if (mounted) {
        if (response['success'] == true) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('✓ ${tr('cancellation_requested')}'), backgroundColor: Colors.green),
          );
          _loadCancellationStatus();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('✗ ${response['error']}'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  // Cancelar directamente (para supervisores)
  void _handleDirectCancellation(bool? value) {
    if (_canApproveCancellation) {
      setState(() => _isCancelled = value ?? false);
    } else if (value == true && !_isCancelled) {
      // Si no puede aprobar y quiere cancelar, mostrar diálogo de solicitud
      _showRequestCancellationDialog();
    }
  }

  void _selectAll(TextEditingController controller) {
    final text = controller.text;
    controller.selection = TextSelection(baseOffset: 0, extentOffset: text.length);
  }

  Widget _buildReadOnlyField(String label, TextEditingController controller) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11)),
          const SizedBox(height: 4),
          TextField(
            controller: controller,
            readOnly: true,
            maxLines: 2,
            style: const TextStyle(color: Colors.white54, fontSize: 12),
            onTap: () => _selectAll(controller),
            enableInteractiveSelection: true,
            decoration: InputDecoration(
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
              filled: true,
              fillColor: AppColors.fieldBackground.withOpacity(0.5),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(4),
                borderSide: const BorderSide(color: AppColors.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(4),
                borderSide: const BorderSide(color: AppColors.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(4),
                borderSide: const BorderSide(color: Colors.blue),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEditableField(String label, TextEditingController controller, {TextInputType? keyboardType}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11)),
          const SizedBox(height: 4),
          SizedBox(
            height: 32,
            child: TextField(
              controller: controller,
              keyboardType: keyboardType,
              style: const TextStyle(color: Colors.white, fontSize: 12),
              onTap: () => _selectAll(controller),
              decoration: InputDecoration(
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                filled: true,
                fillColor: AppColors.fieldBackground,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(4),
                  borderSide: const BorderSide(color: AppColors.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(4),
                  borderSide: const BorderSide(color: AppColors.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(4),
                  borderSide: const BorderSide(color: Colors.blue),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDropdownField(String label, String value, List<String> options, ValueChanged<String?> onChanged) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11)),
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
                value: value,
                isExpanded: true,
                dropdownColor: AppColors.panelBackground,
                style: const TextStyle(color: Colors.white, fontSize: 12),
                padding: const EdgeInsets.symmetric(horizontal: 8),
                items: options.map((opt) => DropdownMenuItem(
                  value: opt,
                  child: Text(opt),
                )).toList(),
                onChanged: onChanged,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCancellationSection() {
    // Si ya está cancelado, mostrar estado
    if (_isCancelled) {
      return Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.red.withOpacity(0.2),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: Colors.red),
        ),
        child: Row(
          children: [
            const Icon(Icons.cancel, color: Colors.red, size: 18),
            const SizedBox(width: 8),
            Text(
              tr('entry_cancelled'),
              style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 12),
            ),
            if (_canApproveCancellation) ...[
              const Spacer(),
              TextButton(
                onPressed: () => setState(() => _isCancelled = false),
                child: Text(tr('undo'), style: const TextStyle(color: Colors.white70, fontSize: 11)),
              ),
            ],
          ],
        ),
      );
    }
    
    // Si hay solicitud pendiente
    if (_hasPendingCancellation && _pendingRequest != null) {
      return Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.orange.withOpacity(0.2),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: Colors.orange),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.pending_actions, color: Colors.orange, size: 18),
                const SizedBox(width: 8),
                Text(
                  tr('cancellation_pending'),
                  style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold, fontSize: 12),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '${tr('requested_by')}: ${_pendingRequest!['requested_by']}',
              style: const TextStyle(color: Colors.white70, fontSize: 11),
            ),
            const SizedBox(height: 4),
            Text(
              '${tr('reason')}: ${_pendingRequest!['reason']}',
              style: const TextStyle(color: Colors.white70, fontSize: 11),
            ),
          ],
        ),
      );
    }
    
    // Checkbox normal (supervisor puede marcar directo, otros solicitan)
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.fieldBackground,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          if (_canApproveCancellation) ...[
            // Supervisor puede marcar checkbox directamente
            Checkbox(
              value: _isCancelled,
              onChanged: _canEdit ? _handleDirectCancellation : null,
              activeColor: Colors.red,
              side: const BorderSide(color: AppColors.border),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.cancel_outlined, color: Colors.white54, size: 18),
            const SizedBox(width: 8),
            Text(
              tr('cancelled'),
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ] else ...[
            // Usuario normal ve botón para solicitar
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _canEdit ? _showRequestCancellationDialog : null,
                icon: const Icon(Icons.cancel_outlined, size: 16),
                label: Text(tr('request_cancellation'), style: const TextStyle(fontSize: 11)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange.withOpacity(0.8),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 280,
      decoration: const BoxDecoration(
        color: AppColors.panelBackground,
        border: Border(left: BorderSide(color: AppColors.border, width: 1)),
      ),
      child: Column(
        children: [
          // Header
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
                  tr('edit_record'),
                  style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                ),
                IconButton(
                  onPressed: widget.onClose,
                  icon: const Icon(Icons.close, color: Colors.white70, size: 20),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  splashRadius: 16,
                ),
              ],
            ),
          ),
          // Campos de edición
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildReadOnlyField('Material Warehousing Code', _warehousingCodeController),
                  _buildReadOnlyField('Material Code', _materialCodeController),
                  _buildReadOnlyField('PartNumber', _partNumberController),
                  _buildEditableField('Material LotNo', _materialLotNoController),
                  _buildEditableField(tr('location'), _locationController),
                  _buildEditableField('Current Qty', _currentQtyController, keyboardType: TextInputType.number),
                  _buildDropdownField('Material Consigned', _selectedMaterialConsigned, _materialConsignedOptions, (val) {
                    if (val != null) setState(() => _selectedMaterialConsigned = val);
                  }),
                  // Sección de Cancelación
                  const SizedBox(height: 8),
                  if (_loadingCancellationStatus)
                    const Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)))
                  else
                    _buildCancellationSection(),
                ],
              ),
            ),
          ),
          // Botón Modify
          Padding(
            padding: const EdgeInsets.all(12),
            child: SizedBox(
              width: double.infinity,
              height: 36,
              child: Tooltip(
                message: _canEdit ? '' : tr('no_edit_permission'),
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
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : Text(_canEdit ? tr('modify') : tr('read_only'), style: const TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
