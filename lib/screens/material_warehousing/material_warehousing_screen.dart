import 'package:flutter/material.dart';
import 'package:material_warehousing_flutter/core/localization/app_translations.dart';
import 'package:material_warehousing_flutter/core/services/auth_service.dart';
import 'package:material_warehousing_flutter/core/theme/app_colors.dart';
import 'warehousing_search_bar_panel.dart';
import 'warehousing_grid_panel.dart';
import 'warehousing_edit_panel.dart';
import 'warehousing_multi_edit_dialog.dart'; // Contiene WarehousingMultiEditPanel
import 'warehouse_outgoing_confirm_panel.dart';
import 'warehousing_form_panel.dart';

class MaterialWarehousingScreen extends StatefulWidget {
  final LanguageProvider languageProvider;
  
  const MaterialWarehousingScreen({super.key, required this.languageProvider});

  @override
  State<MaterialWarehousingScreen> createState() => MaterialWarehousingScreenState();
}

class MaterialWarehousingScreenState extends State<MaterialWarehousingScreen> with SingleTickerProviderStateMixin {
  final GlobalKey<WarehousingGridPanelState> _gridKey = GlobalKey();
  final GlobalKey<WarehouseOutgoingConfirmPanelState> _warehouseOutgoingPanelKey = GlobalKey();
  final GlobalKey<WarehousingFormPanelState> _formPanelKey = GlobalKey();
  Map<String, dynamic>? _editingRow; // Fila en edición individual
  List<Map<String, dynamic>>? _multiEditingItems; // Items para edición múltiple
  
  // Modo de entrada: false = Desde Salidas de Almacén, true = Formulario Manual
  bool _useManualForm = false;
  
  // Animación del panel
  late AnimationController _animationController;
  late Animation<Offset> _slideAnimation;
  
  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(1.0, 0.0), // Empieza fuera de la pantalla (derecha)
      end: Offset.zero, // Termina en posición normal
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOutCubic,
    ));
  }
  
  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }
  
  void _onSearch(DateTime? fechaInicio, DateTime? fechaFin, String? texto) {
    _gridKey.currentState?.searchByDate(fechaInicio, fechaFin, texto: texto);
  }

  /// Compatibilidad con llamadas desde el tab principal
  void requestScanFocus() {}

  /// Recargar materiales y ubicaciones desde el botón refresh
  Future<void> reloadFormMateriales() async {
    await _formPanelKey.currentState?.reloadMateriales();
  }
  
  void _onDataSaved() {
    // Recargar la tabla cuando se guardan nuevos datos
    _gridKey.currentState?.reloadData();
  }
  
  void _onRowDoubleClick(Map<String, dynamic> rowData) {
    // Verificar si hay múltiples selecciones y tiene permiso de multi-edit
    final selectedItems = _gridKey.currentState?.getSelectedItems() ?? [];
    
    if (selectedItems.length > 1 && AuthService.canMultiEditWarehousing) {
      // Mostrar panel de edición múltiple
      setState(() {
        _editingRow = null;
        _multiEditingItems = selectedItems;
      });
      _animationController.forward(from: 0.0);
    } else {
      // Edición individual (comportamiento actual)
      setState(() {
        _multiEditingItems = null;
        _editingRow = rowData;
      });
      _animationController.forward(from: 0.0);
    }
  }
  
  void _closeEditPanel() async {
    await _animationController.reverse();
    setState(() {
      _editingRow = null;
      _multiEditingItems = null;
    });
  }
  
  void _onWarehouseOutgoingConfirmed() {
    _gridKey.currentState?.reloadData();
  }

  Widget _buildModeButton({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.headerTab : AppColors.buttonGray,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: isSelected ? AppColors.headerTab : Colors.transparent,
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.white70,
            fontSize: 13,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  String tr(String key) => widget.languageProvider.tr(key);

  @override
  Widget build(BuildContext context) {
    final canConfirmWarehouseOutgoing = AuthService.canWriteWarehousing;
    
    return Row(
      children: [
        // Panel principal
        Expanded(
          child: Column(
            children: [
              if (canConfirmWarehouseOutgoing) ...[
                // Botón de alternancia entre modos
                Container(
                  color: AppColors.panelBackground,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    children: [
                      Text(
                        tr('entry_mode'),
                        style: const TextStyle(color: Colors.white70, fontSize: 14),
                      ),
                      const SizedBox(width: 12),
                      _buildModeButton(
                        label: tr('from_warehouse_outgoing'),
                        isSelected: !_useManualForm,
                        onTap: () => setState(() => _useManualForm = false),
                      ),
                      const SizedBox(width: 8),
                      _buildModeButton(
                        label: tr('manual_form'),
                        isSelected: _useManualForm,
                        onTap: () => setState(() => _useManualForm = true),
                      ),
                      const Spacer(),
                    ],
                  ),
                ),
                // Panel según el modo seleccionado
                if (_useManualForm)
                  WarehousingFormPanel(
                    key: _formPanelKey,
                    languageProvider: widget.languageProvider,
                    onDataSaved: _onDataSaved,
                    gridKey: _gridKey,
                  )
                else
                  WarehouseOutgoingConfirmPanel(
                    key: _warehouseOutgoingPanelKey,
                    languageProvider: widget.languageProvider,
                    onConfirmed: _onWarehouseOutgoingConfirmed,
                  ),
              ],
              Row(
                children: [
                  Expanded(
                    child: WarehousingSearchBarPanel(
                      languageProvider: widget.languageProvider,
                      onSearch: _onSearch,
                      gridKey: _gridKey,
                    ),
                  ),
                ],
              ),
              Expanded(child: WarehousingGridPanel(
                key: _gridKey,
                languageProvider: widget.languageProvider,
                onRowDoubleClick: _onRowDoubleClick,
              )),
            ],
          ),
        ),
        // Panel de edición con animación de deslizamiento
        if (_editingRow != null)
          SlideTransition(
            position: _slideAnimation,
            child: WarehousingEditPanel(
              key: ValueKey(_editingRow!['id']),
              languageProvider: widget.languageProvider,
              rowData: _editingRow!,
              onClose: _closeEditPanel,
              onSaved: _onDataSaved,
            ),
          ),
        // Panel de edición múltiple con animación de deslizamiento
        if (_multiEditingItems != null)
          SlideTransition(
            position: _slideAnimation,
            child: WarehousingMultiEditPanel(
              key: ValueKey(_multiEditingItems!.map((e) => e['id']).join('-')),
              languageProvider: widget.languageProvider,
              selectedItems: _multiEditingItems!,
              onClose: _closeEditPanel,
              onSaved: _onDataSaved,
            ),
          ),
      ],
    );
  }
}
