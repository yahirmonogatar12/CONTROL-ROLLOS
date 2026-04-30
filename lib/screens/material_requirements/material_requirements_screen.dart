import 'package:flutter/material.dart';
import 'package:material_warehousing_flutter/core/localization/app_translations.dart';
import 'package:material_warehousing_flutter/core/theme/app_colors.dart';
import 'package:material_warehousing_flutter/core/services/auth_service.dart';
import 'requirements_grid_panel.dart';
import 'requirements_items_panel.dart';
import 'requirements_form_panel.dart';

// ============================================
// Material Requirements Screen - Pantalla Principal
// ============================================
class MaterialRequirementsScreen extends StatefulWidget {
  final LanguageProvider languageProvider;
  
  const MaterialRequirementsScreen({
    super.key,
    required this.languageProvider,
  });

  @override
  State<MaterialRequirementsScreen> createState() => MaterialRequirementsScreenState();
}

class MaterialRequirementsScreenState extends State<MaterialRequirementsScreen> {
  // Keys para comunicación entre paneles
  final GlobalKey<RequirementsGridPanelState> _gridKey = GlobalKey();
  final GlobalKey<RequirementsItemsPanelState> _itemsKey = GlobalKey();
  
  // Requerimiento seleccionado
  Map<String, dynamic>? _selectedRequirement;
  bool _showForm = false;
  bool _isCreatingNew = false;

  String tr(String key) => widget.languageProvider.tr(key);

  void _onRequirementSelected(Map<String, dynamic>? requirement) {
    setState(() {
      _selectedRequirement = requirement;
      _showForm = false;
    });
    _itemsKey.currentState?.loadItems(requirement?['id']);
  }
  
  void _onCreateNew() {
    setState(() {
      _selectedRequirement = null;
      _showForm = true;
      _isCreatingNew = true;
    });
  }
  
  /// Verificar si el usuario actual puede editar el requerimiento
  bool _canEditRequirement() {
    if (_selectedRequirement == null) return false;
    // Cualquier usuario con permisos de escritura puede editar
    return AuthService.canWriteRequirements;
  }
  
  void _onEditRequirement() {
    if (_selectedRequirement != null) {
      if (!_canEditRequirement()) return;
      setState(() {
        _showForm = true;
        _isCreatingNew = false;
      });
    }
  }
  
  void _onSaved() {
    setState(() {
      _showForm = false;
      _selectedRequirement = null;
    });
    _gridKey.currentState?.loadData();
  }
  
  void _onCancelled() {
    setState(() {
      _showForm = false;
    });
  }
  
  void _onItemsChanged() {
    _gridKey.currentState?.loadData();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.panelBackground,
      child: Row(
        children: [
          // Panel izquierdo: Grids (75%)
          Expanded(
            flex: 3,
            child: Column(
              children: [
                // Header del módulo
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: const BoxDecoration(
                    color: AppColors.gridHeader,
                    border: Border(bottom: BorderSide(color: AppColors.border, width: 1)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.assignment, color: Colors.teal, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        tr('material_requirements'),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                // Grid de requerimientos (50%)
                Expanded(
                  flex: 1,
                  child: RequirementsGridPanel(
                    key: _gridKey,
                    languageProvider: widget.languageProvider,
                    onRequirementSelected: _onRequirementSelected,
                    onCreateNew: _onCreateNew,
                    onEdit: _onEditRequirement,
                  ),
                ),
                // Divisor
                Container(
                  height: 1,
                  color: AppColors.border,
                ),
                // Grid de items (50%)
                Expanded(
                  flex: 1,
                  child: RequirementsItemsPanel(
                    key: _itemsKey,
                    languageProvider: widget.languageProvider,
                    requirement: _selectedRequirement,
                    onItemsChanged: _onItemsChanged,
                  ),
                ),
              ],
            ),
          ),
          // Divisor vertical
          Container(
            width: 1,
            color: AppColors.border,
          ),
          // Panel derecho: Formulario (25%)
          Expanded(
            flex: 1,
            child: _showForm
                ? RequirementsFormPanel(
                    languageProvider: widget.languageProvider,
                    requirement: _isCreatingNew ? null : _selectedRequirement,
                    isCreatingNew: _isCreatingNew,
                    onSaved: _onSaved,
                    onCancelled: _onCancelled,
                  )
                : _buildInfoPanel(),
          ),
        ],
      ),
    );
  }
  
  Widget _buildInfoPanel() {
    if (_selectedRequirement == null) {
      return Container(
        color: AppColors.panelBackground,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.assignment_outlined, size: 48, color: Colors.white.withOpacity(0.1)),
              const SizedBox(height: 8),
              Text(
                tr('select_requirement'),
                style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 12),
              ),
              const SizedBox(height: 16),
              _buildInfoButton(
                icon: Icons.add,
                label: tr('new_requirement'),
                color: Colors.teal,
                onPressed: _onCreateNew,
              ),
            ],
          ),
        ),
      );
    }
    
    return Container(
      color: AppColors.panelBackground,
      child: Column(
        children: [
          // Header
          Container(
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: const BoxDecoration(
              color: AppColors.gridHeader,
              border: Border(bottom: BorderSide(color: AppColors.border, width: 1)),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline, color: Colors.teal, size: 16),
                const SizedBox(width: 8),
                Text(
                  tr('requirement_details'),
                  style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                ),
                const Spacer(),
                _buildEditButton(),
              ],
            ),
          ),
          // Contenido
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildInfoRow(tr('id'), '#${_selectedRequirement!['id']}'),
                  _buildInfoRow(tr('target_area'), _selectedRequirement!['area_destino'] ?? '-'),
                  _buildInfoRow(tr('model'), _selectedRequirement!['modelo'] ?? '-'),
                  _buildInfoRow(tr('required_date'), _formatDate(_selectedRequirement!['fecha_requerida'])),
                  _buildStatusChip(_selectedRequirement!['status'] ?? 'Pendiente'),
                  _buildPriorityChip(_selectedRequirement!['prioridad'] ?? 'Normal'),
                  const SizedBox(height: 12),
                  _buildInfoRow(tr('total_items'), '${_selectedRequirement!['total_items'] ?? 0}'),
                  _buildInfoRow(tr('qty_required'), '${_selectedRequirement!['total_qty_requerida'] ?? 0}'),
                  _buildInfoRow(tr('qty_delivered'), '${_selectedRequirement!['total_qty_entregada'] ?? 0}'),
                  const SizedBox(height: 12),
                  _buildInfoRow(tr('created_by'), _selectedRequirement!['creado_por'] ?? '-'),
                  _buildInfoRow(tr('created_at'), _formatDateTime(_selectedRequirement!['fecha_creacion'])),
                  if (_selectedRequirement!['notas'] != null && _selectedRequirement!['notas'].toString().isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(tr('notes'), style: const TextStyle(color: Colors.white54, fontSize: 10)),
                    const SizedBox(height: 4),
                    Text(
                      _selectedRequirement!['notas'],
                      style: const TextStyle(color: Colors.white70, fontSize: 11),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 90,
            child: Text(label, style: const TextStyle(color: Colors.white54, fontSize: 10)),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(color: Colors.white, fontSize: 11)),
          ),
        ],
      ),
    );
  }
  
  Widget _buildStatusChip(String status) {
    Color color;
    switch (status) {
      case 'Pendiente':
        color = Colors.orange;
        break;
      case 'En Preparación':
        color = Colors.blue;
        break;
      case 'Listo':
        color = Colors.green;
        break;
      case 'Entregado':
        color = Colors.teal;
        break;
      case 'Cancelado':
        color = Colors.red;
        break;
      default:
        color = Colors.grey;
    }
    
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(
            width: 90,
            child: Text(tr('status'), style: const TextStyle(color: Colors.white54, fontSize: 10)),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: color.withOpacity(0.2),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: color.withOpacity(0.5)),
            ),
            child: Text(status, style: TextStyle(color: color, fontSize: 10)),
          ),
        ],
      ),
    );
  }
  
  Widget _buildPriorityChip(String priority) {
    Color color;
    IconData icon;
    switch (priority) {
      case 'Crítico':
        color = Colors.red;
        icon = Icons.priority_high;
        break;
      case 'Urgente':
        color = Colors.orange;
        icon = Icons.warning;
        break;
      default:
        color = Colors.grey;
        icon = Icons.remove;
    }
    
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(
            width: 90,
            child: Text(tr('priority'), style: const TextStyle(color: Colors.white54, fontSize: 10)),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: color.withOpacity(0.2),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: color.withOpacity(0.5)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 10, color: color),
                const SizedBox(width: 4),
                Text(priority, style: TextStyle(color: color, fontSize: 10)),
              ],
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildInfoButton({
    required IconData icon,
    required String label,
    required Color color,
    VoidCallback? onPressed,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: color.withOpacity(0.2),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: color.withOpacity(0.5)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 8),
              Text(label, style: TextStyle(fontSize: 12, color: color)),
            ],
          ),
        ),
      ),
    );
  }
  
  Widget _buildEditButton() {
    final canEdit = _canEditRequirement();
    final color = canEdit ? Colors.blue : Colors.grey;
    
    return Tooltip(
      message: canEdit
        ? tr('edit')
        : tr('no_permission'),
      child: InkWell(
        onTap: canEdit ? _onEditRequirement : null,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: color.withOpacity(0.2),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: color.withOpacity(0.5)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(canEdit ? Icons.edit : Icons.lock, size: 12, color: color),
              const SizedBox(width: 4),
              Text(tr('edit'), style: TextStyle(fontSize: 10, color: color)),
            ],
          ),
        ),
      ),
    );
  }
  
  String _formatDate(dynamic date) {
    if (date == null) return '-';
    try {
      final d = DateTime.parse(date.toString());
      return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
    } catch (e) {
      return date.toString();
    }
  }
  
  String _formatDateTime(dynamic date) {
    if (date == null) return '-';
    try {
      final d = DateTime.parse(date.toString());
      return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    } catch (e) {
      return date.toString();
    }
  }
}
