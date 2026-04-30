import 'package:flutter/material.dart';
import 'package:material_warehousing_flutter/core/localization/app_translations.dart';
import 'package:material_warehousing_flutter/core/theme/app_colors.dart';
import 'package:material_warehousing_flutter/core/services/api_service.dart';
import 'package:material_warehousing_flutter/core/services/auth_service.dart';

/// Panel lateral para editar múltiples entradas a la vez (mismo estilo que edit panel)
class WarehousingMultiEditPanel extends StatefulWidget {
  final LanguageProvider languageProvider;
  final List<Map<String, dynamic>> selectedItems;
  final VoidCallback onClose;
  final VoidCallback onSaved;

  const WarehousingMultiEditPanel({
    super.key,
    required this.languageProvider,
    required this.selectedItems,
    required this.onClose,
    required this.onSaved,
  });

  @override
  State<WarehousingMultiEditPanel> createState() => _WarehousingMultiEditPanelState();
}

class _WarehousingMultiEditPanelState extends State<WarehousingMultiEditPanel> {
  // Controladores para los campos editables
  final TextEditingController _lotNoController = TextEditingController();
  final TextEditingController _locationController = TextEditingController();
  final TextEditingController _currentQtyController = TextEditingController();
  
  // Checkboxes para indicar qué campos aplicar
  bool _applyLotNo = false;
  bool _applyLocation = false;
  bool _applyCurrentQty = false;
  bool _applyCancelled = false;
  bool _cancelledValue = false;
  
  bool _isSaving = false;
  bool _showConfirmation = false;

  String tr(String key) => widget.languageProvider.tr(key);
  
  // Solo supervisores pueden cambiar el estado de cancelación
  bool get _canApproveCancellation => AuthService.canApproveCancellation;

  @override
  void dispose() {
    _lotNoController.dispose();
    _locationController.dispose();
    _currentQtyController.dispose();
    super.dispose();
  }

  bool get _hasFieldsToApply {
    return _applyLotNo || _applyLocation || _applyCurrentQty || _applyCancelled;
  }

  void _onApply() {
    if (!_hasFieldsToApply) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(tr('select_fields_to_apply')),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // Mostrar confirmación
    setState(() => _showConfirmation = true);
  }

  Future<void> _confirmAndApply() async {
    setState(() {
      _isSaving = true;
    });

    // Construir campos a actualizar
    final Map<String, dynamic> fields = {};
    
    if (_applyLotNo && _lotNoController.text.isNotEmpty) {
      fields['numero_lote_material'] = _lotNoController.text;
    }
    if (_applyLocation && _locationController.text.isNotEmpty) {
      fields['ubicacion_salida'] = _locationController.text;
    }
    if (_applyCurrentQty) {
      final qty = int.tryParse(_currentQtyController.text);
      if (qty != null) {
        fields['cantidad_actual'] = qty;
      }
    }
    if (_applyCancelled && _canApproveCancellation) {
      fields['cancelado'] = _cancelledValue ? 1 : 0;
    }

    if (fields.isEmpty) {
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(tr('no_valid_fields')),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // Obtener IDs de los items seleccionados
    final ids = widget.selectedItems
        .map((item) => item['id'] as int?)
        .where((id) => id != null)
        .cast<int>()
        .toList();

    if (ids.isEmpty) {
      setState(() => _isSaving = false);
      return;
    }

    // Llamar al API
    final result = await ApiService.bulkUpdateWarehousing(ids, fields);

    if (mounted) {
      setState(() => _isSaving = false);
      
      if (result['success'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✓ ${result['message']}'),
            backgroundColor: Colors.green,
          ),
        );
        widget.onSaved();
        widget.onClose();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${result['error'] ?? 'Unknown error'}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Widget _buildCheckboxField({
    required String label,
    required bool isChecked,
    required ValueChanged<bool?> onCheckChanged,
    required Widget field,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: 20,
                height: 20,
                child: Checkbox(
                  value: isChecked,
                  onChanged: onCheckChanged,
                  activeColor: Colors.orange,
                  side: const BorderSide(color: AppColors.border),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: const TextStyle(color: Colors.white70, fontSize: 11),
              ),
            ],
          ),
          const SizedBox(height: 4),
          field,
        ],
      ),
    );
  }

  Widget _buildEditableField(TextEditingController controller, bool enabled, {TextInputType? keyboardType}) {
    return SizedBox(
      height: 32,
      child: TextField(
        controller: controller,
        enabled: enabled,
        keyboardType: keyboardType,
        style: TextStyle(
          color: enabled ? Colors.white : Colors.white54,
          fontSize: 12,
        ),
        decoration: InputDecoration(
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          filled: true,
          fillColor: enabled ? AppColors.fieldBackground : AppColors.fieldBackground.withOpacity(0.5),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(4),
            borderSide: const BorderSide(color: AppColors.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(4),
            borderSide: const BorderSide(color: AppColors.border),
          ),
          disabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(4),
            borderSide: const BorderSide(color: AppColors.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(4),
            borderSide: const BorderSide(color: Colors.blue),
          ),
        ),
      ),
    );
  }

  Widget _buildCancellationCheckbox() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: 20,
                height: 20,
                child: Checkbox(
                  value: _applyCancelled,
                  onChanged: (v) => setState(() => _applyCancelled = v ?? false),
                  activeColor: Colors.orange,
                  side: const BorderSide(color: AppColors.border),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                'Cancelled',
                style: TextStyle(color: Colors.white70, fontSize: 11),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            decoration: BoxDecoration(
              color: _applyCancelled ? AppColors.fieldBackground : AppColors.fieldBackground.withOpacity(0.5),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                Checkbox(
                  value: _cancelledValue,
                  onChanged: _applyCancelled
                      ? (v) => setState(() => _cancelledValue = v ?? false)
                      : null,
                  activeColor: Colors.red,
                  side: const BorderSide(color: AppColors.border),
                ),
                Icon(
                  Icons.cancel_outlined,
                  color: _applyCancelled
                      ? (_cancelledValue ? Colors.red : Colors.white54)
                      : Colors.white38,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Text(
                  _cancelledValue ? tr('yes') : tr('no'),
                  style: TextStyle(
                    color: _applyCancelled
                        ? (_cancelledValue ? Colors.red : Colors.white70)
                        : Colors.white54,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEditContent() {
    final itemCount = widget.selectedItems.length;
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Info de selección (estilo read-only como en edit panel)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(tr('selected_records'), style: const TextStyle(color: Colors.white70, fontSize: 11)),
              const SizedBox(height: 4),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.fieldBackground.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: AppColors.border),
                ),
                child: Text(
                  '$itemCount',
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ),
            ],
          ),
        ),
        
        const SizedBox(height: 8),
        Text(
          tr('select_fields_to_edit'),
          style: const TextStyle(fontSize: 11, color: Colors.white54),
        ),
        const SizedBox(height: 12),
        
        // Material Lot No
        _buildCheckboxField(
          label: 'Material LotNo',
          isChecked: _applyLotNo,
          onCheckChanged: (v) => setState(() => _applyLotNo = v ?? false),
          field: _buildEditableField(_lotNoController, _applyLotNo),
        ),
        
        // Location
        _buildCheckboxField(
          label: tr('location'),
          isChecked: _applyLocation,
          onCheckChanged: (v) => setState(() => _applyLocation = v ?? false),
          field: _buildEditableField(_locationController, _applyLocation),
        ),
        
        // Current Qty
        _buildCheckboxField(
          label: 'Current Qty',
          isChecked: _applyCurrentQty,
          onCheckChanged: (v) => setState(() => _applyCurrentQty = v ?? false),
          field: _buildEditableField(_currentQtyController, _applyCurrentQty, keyboardType: TextInputType.number),
        ),
        
        // Cancelled (solo para supervisores)
        if (_canApproveCancellation) _buildCancellationCheckbox(),
      ],
    );
  }

  Widget _buildConfirmationContent() {
    final itemCount = widget.selectedItems.length;
    final fieldsToApply = <String>[];
    
    if (_applyLotNo) fieldsToApply.add('Material LotNo: ${_lotNoController.text}');
    if (_applyLocation) fieldsToApply.add('${tr('location')}: ${_locationController.text}');
    if (_applyCurrentQty) fieldsToApply.add('Current Qty: ${_currentQtyController.text}');
    if (_applyCancelled) fieldsToApply.add('Cancelled: ${_cancelledValue ? tr('yes') : tr('no')}');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Warning box
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.orange.withOpacity(0.2),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: Colors.orange),
          ),
          child: Row(
            children: [
              const Icon(Icons.warning_amber, color: Colors.orange, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  tr('confirm_multi_edit'),
                  style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold, fontSize: 12),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        
        // Records to update (read-only style)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(tr('records_to_update'), style: const TextStyle(color: Colors.white70, fontSize: 11)),
              const SizedBox(height: 4),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.fieldBackground.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: AppColors.border),
                ),
                child: Text(
                  '$itemCount',
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ),
            ],
          ),
        ),
        
        // Fields to apply
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(tr('fields_to_apply'), style: const TextStyle(color: Colors.white70, fontSize: 11)),
              const SizedBox(height: 4),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.fieldBackground.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: fieldsToApply.map((f) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      children: [
                        const Icon(Icons.check, size: 14, color: Colors.green),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(f, style: const TextStyle(fontSize: 11, color: Colors.white70)),
                        ),
                      ],
                    ),
                  )).toList(),
                ),
              ),
            ],
          ),
        ),
        
        const SizedBox(height: 8),
        Text(
          tr('this_action_cannot_be_undone'),
          style: const TextStyle(fontSize: 10, color: Colors.red, fontStyle: FontStyle.italic),
        ),
      ],
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
          // Header (mismo estilo que edit panel)
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
                  tr('multi_edit'),
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
          
          // Contenido
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: _showConfirmation ? _buildConfirmationContent() : _buildEditContent(),
            ),
          ),
          
          // Botones (mismo estilo que edit panel)
          Padding(
            padding: const EdgeInsets.all(12),
            child: _showConfirmation
                ? Row(
                    children: [
                      Expanded(
                        child: SizedBox(
                          height: 36,
                          child: OutlinedButton(
                            onPressed: () => setState(() => _showConfirmation = false),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.white70,
                              side: const BorderSide(color: AppColors.border),
                            ),
                            child: Text(tr('back'), style: const TextStyle(fontSize: 12)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: SizedBox(
                          height: 36,
                          child: ElevatedButton(
                            onPressed: _isSaving ? null : _confirmAndApply,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.orange,
                              foregroundColor: Colors.white,
                              disabledBackgroundColor: Colors.grey.shade700,
                            ),
                            child: _isSaving
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                  )
                                : Text(tr('confirm'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                          ),
                        ),
                      ),
                    ],
                  )
                : SizedBox(
                    width: double.infinity,
                    height: 36,
                    child: ElevatedButton(
                      onPressed: _isSaving ? null : _onApply,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: Colors.grey.shade700,
                      ),
                      child: _isSaving
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : Text(tr('apply'), style: const TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
