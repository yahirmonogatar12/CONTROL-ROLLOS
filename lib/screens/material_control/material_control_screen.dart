import 'package:flutter/material.dart';
import 'package:material_warehousing_flutter/core/localization/app_translations.dart';
import 'package:material_warehousing_flutter/core/theme/app_colors.dart';
import 'material_control_grid_panel.dart';
import 'material_control_form_panel.dart';

// ============================================
// Material Control Screen - Pantalla principal
// ============================================
class MaterialControlScreen extends StatefulWidget {
  final LanguageProvider languageProvider;
  
  const MaterialControlScreen({
    super.key,
    required this.languageProvider,
  });

  @override
  State<MaterialControlScreen> createState() => _MaterialControlScreenState();
}

class _MaterialControlScreenState extends State<MaterialControlScreen> {
  // Claves para comunicación entre paneles
  final GlobalKey<MaterialControlGridPanelState> _gridKey = GlobalKey();
  final GlobalKey<MaterialControlFormPanelState> _formKey = GlobalKey();
  
  // Material seleccionado para edición
  Map<String, dynamic>? _selectedMaterial;
  bool _isCreatingNew = false;

  String tr(String key) => widget.languageProvider.tr(key);

  void _onMaterialSelected(Map<String, dynamic>? material) {
    setState(() {
      _selectedMaterial = material;
      _isCreatingNew = false;
    });
    _formKey.currentState?.loadMaterial(material);
  }
  
  void _onCreateNew() {
    setState(() {
      _selectedMaterial = null;
      _isCreatingNew = true;
    });
    _formKey.currentState?.clearForm();
  }
  
  Future<void> _onSaved() async {
    // Limpiar selección y form ANTES de recargar para evitar datos obsoletos
    _formKey.currentState?.clearForm();
    setState(() {
      _selectedMaterial = null;
      _isCreatingNew = false;
    });
    // Recargar grid después de guardar (await para evitar race condition)
    await _gridKey.currentState?.loadData();
  }
  
  void _onCancelled() {
    setState(() {
      _isCreatingNew = false;
    });
    _formKey.currentState?.loadMaterial(_selectedMaterial);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.panelBackground,
      child: Row(
        children: [
          // Panel izquierdo: Grid (70%)
          Expanded(
            flex: 7,
            child: Column(
              children: [
                // Header del grid
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: const BoxDecoration(
                    color: AppColors.gridHeader,
                    border: Border(bottom: BorderSide(color: AppColors.border, width: 1)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.inventory_2, color: Colors.cyan, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        tr('material_control'),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                // Grid
                Expanded(
                  child: MaterialControlGridPanel(
                    key: _gridKey,
                    languageProvider: widget.languageProvider,
                    onMaterialSelected: _onMaterialSelected,
                    onCreateNew: _onCreateNew,
                  ),
                ),
              ],
            ),
          ),
          // Divisor
          Container(
            width: 1,
            color: AppColors.border,
          ),
          // Panel derecho: Formulario (30%)
          Expanded(
            flex: 3,
            child: MaterialControlFormPanel(
              key: _formKey,
              languageProvider: widget.languageProvider,
              onSaved: _onSaved,
              onCancelled: _onCancelled,
              isCreatingNew: _isCreatingNew,
            ),
          ),
        ],
      ),
    );
  }
}
