import 'package:flutter/material.dart';
import 'package:material_warehousing_flutter/core/localization/app_translations.dart';
import 'package:material_warehousing_flutter/core/theme/app_colors.dart';
import 'package:material_warehousing_flutter/core/services/api_service.dart';
import 'package:material_warehousing_flutter/core/services/auth_service.dart';

// ============================================
// Requirements Form Panel - Crear/Editar Requerimiento
// ============================================
class RequirementsFormPanel extends StatefulWidget {
  final LanguageProvider languageProvider;
  final Map<String, dynamic>? requirement;
  final bool isCreatingNew;
  final VoidCallback? onSaved;
  final VoidCallback? onCancelled;
  
  const RequirementsFormPanel({
    super.key,
    required this.languageProvider,
    this.requirement,
    this.isCreatingNew = false,
    this.onSaved,
    this.onCancelled,
  });

  @override
  State<RequirementsFormPanel> createState() => _RequirementsFormPanelState();
}

class _RequirementsFormPanelState extends State<RequirementsFormPanel> {
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;
  
  // Áreas disponibles
  List<String> _areas = [];
  
  // Form fields
  String? _selectedArea;
  String? _selectedPartNumber;
  String? _selectedSpec;
  DateTime _fechaRequerida = DateTime.now().add(const Duration(days: 1));
  String? _selectedTurno;
  String _selectedPrioridad = 'Normal';
  String _selectedStatus = 'Pendiente';
  final _notasController = TextEditingController();

  String tr(String key) => widget.languageProvider.tr(key);
  
  static const List<String> _turnos = ['Día', 'Noche', 'Mixto'];
  static const List<String> _prioridades = ['Normal', 'Urgente', 'Crítico'];
  static const List<String> _statuses = ['Pendiente', 'En Preparación', 'Listo', 'Entregado', 'Cancelado'];

  @override
  void initState() {
    super.initState();
    _loadAreas();
    _loadFormData();
  }
  
  @override
  void didUpdateWidget(RequirementsFormPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.requirement != oldWidget.requirement || 
        widget.isCreatingNew != oldWidget.isCreatingNew) {
      _loadFormData();
    }
  }
  
  Future<void> _loadAreas() async {
    // Always use the fixed list of valid areas - do not depend on database
    const validAreas = ['SMD', 'Assy', 'IMD', 'Coating', 'Micom', 'IPM', 'Mantenimiento'];
    if (mounted) {
      setState(() => _areas = validAreas);
    }
  }
  
  void _loadFormData() {
    if (widget.isCreatingNew) {
      // Limpiar formulario
      _selectedArea = null;
      _selectedPartNumber = null;
      _selectedSpec = null;
      _fechaRequerida = DateTime.now().add(const Duration(days: 1));
      _selectedTurno = null;
      _selectedPrioridad = 'Normal';
      _selectedStatus = 'Pendiente';
      _notasController.clear();
    } else if (widget.requirement != null) {
      // Cargar datos del requerimiento
      _selectedArea = widget.requirement!['area_destino'];
      _selectedPartNumber = widget.requirement!['modelo'];
      _selectedSpec = widget.requirement!['spec'];
      try {
        _fechaRequerida = DateTime.parse(widget.requirement!['fecha_requerida'].toString());
      } catch (e) {
        _fechaRequerida = DateTime.now();
      }
      _selectedTurno = widget.requirement!['turno'];
      _selectedPrioridad = widget.requirement!['prioridad'] ?? 'Normal';
      _selectedStatus = widget.requirement!['status'] ?? 'Pendiente';
      _notasController.text = widget.requirement!['notas'] ?? '';
    }
    setState(() {});
  }
  
  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedArea == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr('select_area')), backgroundColor: Colors.red),
      );
      return;
    }
    
    setState(() => _isLoading = true);
    
    try {
      final data = {
        'area_destino': _selectedArea,
        'modelo': _selectedPartNumber,
        'fecha_requerida': _fechaRequerida.toIso8601String().split('T')[0],
        'turno': _selectedTurno,
        'prioridad': _selectedPrioridad,
        'status': _selectedStatus,
        'notas': _notasController.text.trim().isEmpty ? null : _notasController.text.trim(),
      };
      
      bool success;
      if (widget.isCreatingNew) {
        data['creado_por'] = AuthService.currentUser?.nombreCompleto ?? 
                             AuthService.currentUser?.username ?? 'Sistema';
        success = await ApiService.createRequirement(data);
      } else {
        data['actualizado_por'] = AuthService.currentUser?.nombreCompleto ?? 
                                  AuthService.currentUser?.username ?? 'Sistema';
        success = await ApiService.updateRequirement(widget.requirement!['id'], data);
      }
      
      if (success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr('saved_successfully')), backgroundColor: Colors.green),
        );
        widget.onSaved?.call();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }
  
  Future<void> _selectDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _fechaRequerida,
      firstDate: DateTime.now().subtract(const Duration(days: 30)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (context, child) {
        return Theme(
          data: ThemeData.dark().copyWith(
            colorScheme: const ColorScheme.dark(primary: Colors.teal),
          ),
          child: child!,
        );
      },
    );
    
    if (picked != null) {
      setState(() => _fechaRequerida = picked);
    }
  }
  
  Future<void> _openPartNumberSelector() async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => _PartNumberSelectorDialog(
        languageProvider: widget.languageProvider,
        currentPartNumber: _selectedPartNumber,
      ),
    );
    
    if (result != null) {
      setState(() {
        _selectedPartNumber = result['numero_parte'];
        _selectedSpec = result['especificacion_material'];
      });
    }
  }
  
  void _clearPartNumber() {
    setState(() {
      _selectedPartNumber = null;
      _selectedSpec = null;
    });
  }

  @override
  void dispose() {
    _notasController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
                Icon(
                  widget.isCreatingNew ? Icons.add_circle : Icons.edit,
                  color: Colors.teal,
                  size: 16,
                ),
                const SizedBox(width: 8),
                Text(
                  widget.isCreatingNew ? tr('new_requirement') : tr('edit_requirement'),
                  style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
          // Form content
          Expanded(
            child: Form(
              key: _formKey,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Botones de acción
                    Row(
                      children: [
                        if (AuthService.canWriteRequirements)
                          _buildActionButton(
                            icon: Icons.save,
                            label: tr('save'),
                            color: Colors.teal,
                            onPressed: _isLoading ? null : _save,
                          ),
                        if (AuthService.canWriteRequirements)
                          const SizedBox(width: 8),
                        _buildActionButton(
                          icon: Icons.close,
                          label: tr('cancel'),
                          color: Colors.grey,
                          onPressed: widget.onCancelled,
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    
                    // Campos requeridos
                    Text(tr('required_fields'), style: const TextStyle(color: Colors.amber, fontSize: 10, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    
                    // Área destino
                    _buildDropdownField(
                      label: tr('target_area'),
                      value: _selectedArea,
                      items: _areas,
                      required: true,
                      icon: Icons.place,
                      onChanged: (value) => setState(() => _selectedArea = value),
                    ),
                    
                    // Fecha requerida
                    _buildDateField(
                      label: tr('required_date'),
                      value: _fechaRequerida,
                      required: true,
                      onTap: _selectDate,
                    ),
                    
                    const SizedBox(height: 16),
                    Text(tr('optional_fields'), style: const TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    
                    // Turno
                    _buildDropdownField(
                      label: tr('shift'),
                      value: _selectedTurno,
                      items: _turnos,
                      icon: Icons.access_time,
                      onChanged: (value) => setState(() => _selectedTurno = value),
                      allowNull: true,
                    ),
                    
                    // Prioridad
                    _buildPriorityField(),
                    
                    // Status (solo para edición)
                    if (!widget.isCreatingNew)
                      _buildDropdownField(
                        label: tr('status'),
                        value: _selectedStatus,
                        items: _statuses,
                        icon: Icons.flag,
                        onChanged: (value) => setState(() => _selectedStatus = value ?? 'Pendiente'),
                      ),
                    
                    // Notas
                    _buildTextField(
                      label: tr('notes'),
                      controller: _notasController,
                      icon: Icons.notes,
                      maxLines: 3,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildPartNumberField() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: _openPartNumberSelector,
            child: InputDecorator(
              decoration: InputDecoration(
                labelText: tr('part_number'),
                labelStyle: const TextStyle(fontSize: 10, color: Colors.white54),
                prefixIcon: const Icon(Icons.inventory_2, size: 14, color: Colors.white38),
                prefixIconConstraints: const BoxConstraints(minWidth: 32),
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_selectedPartNumber != null)
                      IconButton(
                        icon: const Icon(Icons.clear, size: 14, color: Colors.white38),
                        onPressed: _clearPartNumber,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    const Icon(Icons.search, size: 16, color: Colors.teal),
                    const SizedBox(width: 8),
                  ],
                ),
                filled: true,
                fillColor: AppColors.gridBackground,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: const BorderSide(color: AppColors.border)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: const BorderSide(color: AppColors.border)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                isDense: true,
              ),
              child: Text(
                _selectedPartNumber ?? tr('select'),
                style: TextStyle(
                  color: _selectedPartNumber != null ? Colors.white : Colors.white38,
                  fontSize: 11,
                ),
              ),
            ),
          ),
          // Mostrar spec si hay un part number seleccionado
          if (_selectedSpec != null && _selectedSpec!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.teal.withOpacity(0.1),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: Colors.teal.withOpacity(0.3)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${tr('spec')}: ', style: const TextStyle(color: Colors.teal, fontSize: 9, fontWeight: FontWeight.w600)),
                  Expanded(
                    child: Text(
                      _selectedSpec!,
                      style: const TextStyle(color: Colors.white70, fontSize: 9),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
  
  Widget _buildActionButton({
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
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: color.withOpacity(0.2),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: color.withOpacity(0.5)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _isLoading && color == Colors.teal
                ? SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: color))
                : Icon(icon, size: 14, color: color),
              const SizedBox(width: 6),
              Text(label, style: TextStyle(fontSize: 11, color: color)),
            ],
          ),
        ),
      ),
    );
  }
  
  Widget _buildTextField({
    required String label,
    required TextEditingController controller,
    IconData? icon,
    bool required = false,
    int maxLines = 1,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TextFormField(
        controller: controller,
        maxLines: maxLines,
        style: const TextStyle(fontSize: 11, color: Colors.white),
        decoration: InputDecoration(
          labelText: required ? '$label *' : label,
          labelStyle: TextStyle(fontSize: 10, color: required ? Colors.amber : Colors.white54),
          prefixIcon: icon != null ? Icon(icon, size: 14, color: Colors.white38) : null,
          prefixIconConstraints: const BoxConstraints(minWidth: 32),
          filled: true,
          fillColor: AppColors.gridBackground,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: const BorderSide(color: AppColors.border)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: const BorderSide(color: AppColors.border)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: const BorderSide(color: Colors.teal)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          isDense: true,
        ),
        validator: required ? (value) {
          if (value == null || value.trim().isEmpty) return tr('field_required');
          return null;
        } : null,
      ),
    );
  }
  
  Widget _buildDropdownField({
    required String label,
    required String? value,
    required List<String> items,
    IconData? icon,
    bool required = false,
    bool allowNull = false,
    required void Function(String?) onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: required ? '$label *' : label,
          labelStyle: TextStyle(fontSize: 10, color: required ? Colors.amber : Colors.white54),
          prefixIcon: icon != null ? Icon(icon, size: 14, color: Colors.white38) : null,
          prefixIconConstraints: const BoxConstraints(minWidth: 32),
          filled: true,
          fillColor: AppColors.gridBackground,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: const BorderSide(color: AppColors.border)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: const BorderSide(color: AppColors.border)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          isDense: true,
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: value,
            hint: Text(tr('select'), style: const TextStyle(color: Colors.white38, fontSize: 11)),
            isExpanded: true,
            dropdownColor: AppColors.panelBackground,
            style: const TextStyle(color: Colors.white, fontSize: 11),
            icon: const Icon(Icons.arrow_drop_down, size: 16, color: Colors.white54),
            items: [
              if (allowNull)
                DropdownMenuItem<String>(
                  value: null,
                  child: Text('-', style: const TextStyle(fontSize: 11, color: Colors.white54)),
                ),
              ...items.map((item) => DropdownMenuItem<String>(
                value: item,
                child: Text(item, style: const TextStyle(fontSize: 11)),
              )),
            ],
            onChanged: onChanged,
          ),
        ),
      ),
    );
  }
  
  Widget _buildDateField({
    required String label,
    required DateTime value,
    bool required = false,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: onTap,
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: required ? '$label *' : label,
            labelStyle: TextStyle(fontSize: 10, color: required ? Colors.amber : Colors.white54),
            prefixIcon: const Icon(Icons.calendar_today, size: 14, color: Colors.white38),
            prefixIconConstraints: const BoxConstraints(minWidth: 32),
            suffixIcon: const Icon(Icons.arrow_drop_down, size: 16, color: Colors.white54),
            filled: true,
            fillColor: AppColors.gridBackground,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: const BorderSide(color: AppColors.border)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: const BorderSide(color: AppColors.border)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            isDense: true,
          ),
          child: Text(
            '${value.day.toString().padLeft(2, '0')}/${value.month.toString().padLeft(2, '0')}/${value.year}',
            style: const TextStyle(color: Colors.white, fontSize: 11),
          ),
        ),
      ),
    );
  }
  
  Widget _buildPriorityField() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(tr('priority'), style: const TextStyle(color: Colors.white54, fontSize: 10)),
          const SizedBox(height: 4),
          Row(
            children: _prioridades.map((prioridad) {
              final isSelected = _selectedPrioridad == prioridad;
              Color color;
              IconData icon;
              switch (prioridad) {
                case 'Crítico': color = Colors.red; icon = Icons.priority_high; break;
                case 'Urgente': color = Colors.orange; icon = Icons.warning; break;
                default: color = Colors.grey; icon = Icons.remove;
              }
              
              return Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _selectedPrioridad = prioridad),
                  child: Container(
                    margin: const EdgeInsets.only(right: 4),
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    decoration: BoxDecoration(
                      color: isSelected ? color.withOpacity(0.3) : AppColors.gridBackground,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: isSelected ? color : AppColors.border,
                        width: isSelected ? 2 : 1,
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(icon, size: 12, color: isSelected ? color : Colors.white54),
                        const SizedBox(width: 4),
                        Text(
                          prioridad,
                          style: TextStyle(
                            fontSize: 9,
                            color: isSelected ? color : Colors.white54,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

// ============================================
// Diálogo de selección de número de parte
// ============================================
class _PartNumberSelectorDialog extends StatefulWidget {
  final LanguageProvider languageProvider;
  final String? currentPartNumber;
  
  const _PartNumberSelectorDialog({
    required this.languageProvider,
    this.currentPartNumber,
  });
  
  @override
  State<_PartNumberSelectorDialog> createState() => _PartNumberSelectorDialogState();
}

class _PartNumberSelectorDialogState extends State<_PartNumberSelectorDialog> {
  final _searchController = TextEditingController();
  List<Map<String, dynamic>> _materials = [];
  List<Map<String, dynamic>> _filteredMaterials = [];
  bool _isLoading = true;
  int? _selectedIndex;
  
  String tr(String key) => widget.languageProvider.tr(key);
  
  @override
  void initState() {
    super.initState();
    _loadMaterials();
  }
  
  Future<void> _loadMaterials() async {
    try {
      final materials = await ApiService.getMateriales();
      if (mounted) {
        setState(() {
          _materials = materials;
          _filteredMaterials = materials;
          _isLoading = false;
          
          // Seleccionar el material actual si existe
          if (widget.currentPartNumber != null) {
            final idx = materials.indexWhere((m) => m['numero_parte'] == widget.currentPartNumber);
            if (idx != -1) _selectedIndex = idx;
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }
  
  void _onSearch(String query) {
    setState(() {
      if (query.isEmpty) {
        _filteredMaterials = _materials;
      } else {
        _filteredMaterials = _materials.where((m) {
          final partNumber = (m['numero_parte'] ?? '').toString().toLowerCase();
          final spec = (m['especificacion_material'] ?? '').toString().toLowerCase();
          final searchLower = query.toLowerCase();
          return partNumber.contains(searchLower) || spec.contains(searchLower);
        }).toList();
      }
      _selectedIndex = null;
    });
  }
  
  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.panelBackground,
      child: Container(
        width: 600,
        height: 500,
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Header
            Row(
              children: [
                const Icon(Icons.search, color: Colors.teal, size: 20),
                const SizedBox(width: 8),
                Text(
                  tr('select_part_number'),
                  style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white54, size: 18),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 12),
            
            // Search bar
            TextField(
              controller: _searchController,
              style: const TextStyle(color: Colors.white, fontSize: 12),
              decoration: InputDecoration(
                hintText: '${tr('search')} ${tr('part_number')} / ${tr('spec')}...',
                hintStyle: const TextStyle(color: Colors.white38, fontSize: 11),
                prefixIcon: const Icon(Icons.search, size: 18, color: Colors.white54),
                filled: true,
                fillColor: AppColors.gridBackground,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
              onChanged: _onSearch,
            ),
            const SizedBox(height: 12),
            
            // Table header
            Container(
              height: 28,
              decoration: const BoxDecoration(
                color: AppColors.gridHeader,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(4),
                  topRight: Radius.circular(4),
                ),
              ),
              child: Row(
                children: [
                  _buildHeaderCell(tr('part_number'), flex: 2),
                  _buildHeaderCell(tr('spec'), flex: 4),
                  _buildHeaderCell(tr('location'), flex: 2),
                ],
              ),
            ),
            
            // Table data
            Expanded(
              child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: Colors.teal))
                : _filteredMaterials.isEmpty
                  ? Center(
                      child: Text(
                        tr('no_materials_found'),
                        style: const TextStyle(color: Colors.white38, fontSize: 11),
                      ),
                    )
                  : ListView.builder(
                      itemCount: _filteredMaterials.length,
                      itemBuilder: (context, index) {
                        final m = _filteredMaterials[index];
                        final isSelected = _selectedIndex == index;
                        final isEven = index % 2 == 0;
                        
                        return GestureDetector(
                          onTap: () => setState(() => _selectedIndex = index),
                          onDoubleTap: () {
                            Navigator.pop(context, m);
                          },
                          child: Container(
                            height: 28,
                            decoration: BoxDecoration(
                              color: isSelected
                                ? Colors.teal.withOpacity(0.3)
                                : isEven ? AppColors.gridBackground : AppColors.gridRowAlt,
                              border: Border(
                                left: isSelected
                                  ? const BorderSide(color: Colors.teal, width: 3)
                                  : BorderSide.none,
                              ),
                            ),
                            child: Row(
                              children: [
                                _buildDataCell(m['numero_parte'] ?? '', flex: 2),
                                _buildDataCell(m['especificacion_material'] ?? '-', flex: 4),
                                _buildDataCell(m['ubicacion_material'] ?? '-', flex: 2),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
            
            // Footer
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${_filteredMaterials.length} ${tr('materials')}',
                  style: const TextStyle(color: Colors.white54, fontSize: 10),
                ),
                Row(
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text(tr('cancel'), style: const TextStyle(color: Colors.white54)),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: _selectedIndex == null
                        ? null
                        : () => Navigator.pop(context, _filteredMaterials[_selectedIndex!]),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.teal),
                      child: Text(tr('select')),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildHeaderCell(String text, {int flex = 1}) {
    return Expanded(
      flex: flex,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        alignment: Alignment.centerLeft,
        child: Text(
          text,
          style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600),
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
  
  Widget _buildDataCell(String text, {int flex = 1}) {
    return Expanded(
      flex: flex,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        alignment: Alignment.centerLeft,
        child: Text(
          text,
          style: const TextStyle(color: Colors.white70, fontSize: 10),
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}

