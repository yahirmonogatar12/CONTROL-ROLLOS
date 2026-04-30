import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:excel/excel.dart' as xl;
import 'package:intl/intl.dart';
import 'package:material_warehousing_flutter/core/localization/app_translations.dart';
import 'package:material_warehousing_flutter/core/theme/app_colors.dart';
import 'package:material_warehousing_flutter/core/services/api_service.dart';
import 'package:material_warehousing_flutter/core/services/auth_service.dart';
import 'package:material_warehousing_flutter/core/widgets/grid_footer.dart';

// ============================================
// Requirements Grid Panel - Lista de Requerimientos
// ============================================
class RequirementsGridPanel extends StatefulWidget {
  final LanguageProvider languageProvider;
  final Function(Map<String, dynamic>?)? onRequirementSelected;
  final VoidCallback? onCreateNew;
  final VoidCallback? onEdit;
  
  const RequirementsGridPanel({
    super.key,
    required this.languageProvider,
    this.onRequirementSelected,
    this.onCreateNew,
    this.onEdit,
  });

  @override
  State<RequirementsGridPanel> createState() => RequirementsGridPanelState();
}

class RequirementsGridPanelState extends State<RequirementsGridPanel> {
  List<Map<String, dynamic>> _data = [];
  List<Map<String, dynamic>> _filteredData = [];
  bool _isLoading = true;
  int _selectedIndex = -1;
  
  // Filtros
  String? _filterArea;
  String? _filterStatus;
  String _searchText = '';
  DateTime? _fechaInicio;
  DateTime? _fechaFin;
  bool _showPendingOnly = true; // Por defecto mostrar solo pendientes
  final TextEditingController _searchController = TextEditingController();
  
  // Áreas disponibles
  List<String> _areas = [];

  String tr(String key) => widget.languageProvider.tr(key);

  @override
  void initState() {
    super.initState();
    // Por defecto: fecha de hoy para mostrar requerimientos del día
    _fechaInicio = DateTime.now();
    _fechaFin = DateTime.now();
    _loadAreas();
    loadData();
  }
  
  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }
  
  Future<void> _loadAreas() async {
    try {
      final areas = await ApiService.getRequirementAreas();
      if (mounted) {
        setState(() => _areas = areas);
      }
    } catch (e) {
      // Usar áreas por defecto si falla
      setState(() => _areas = ['SMD', 'Assy', 'Molding', 'Pre-Assy', 'Empaque', 'Rework']);
    }
  }
  
  Future<void> loadData() async {
    setState(() => _isLoading = true);
    
    try {
      final dateFormat = DateFormat('yyyy-MM-dd');
      final data = await ApiService.getRequirements(
        area: _filterArea,
        status: _filterStatus,
        fechaInicio: _fechaInicio != null ? dateFormat.format(_fechaInicio!) : null,
        fechaFin: _fechaFin != null ? dateFormat.format(_fechaFin!) : null,
        pendingOnly: _showPendingOnly,
      );
      if (mounted) {
        setState(() {
          _data = data;
          _applyFilters();
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading data: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }
  
  void _applyFilters() {
    var result = List<Map<String, dynamic>>.from(_data);
    
    // Aplicar búsqueda
    if (_searchText.isNotEmpty) {
      result = result.where((row) {
        return row.values.any((value) => 
          value?.toString().toLowerCase().contains(_searchText.toLowerCase()) ?? false
        );
      }).toList();
    }
    
    _filteredData = result;
    _selectedIndex = -1;
  }
  
  void _onSearch(String value) {
    setState(() {
      _searchText = value;
      _applyFilters();
    });
  }
  
  Future<void> _exportToExcel() async {
    try {
      final excel = xl.Excel.createExcel();
      final sheet = excel['Requirements'];
      
      final headers = [tr('code'), tr('target_area'), tr('required_date'), 
                       tr('status'), tr('priority'), tr('items'), tr('created_by')];
      
      for (var i = 0; i < headers.length; i++) {
        sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0)).value = 
          xl.TextCellValue(headers[i]);
      }
      
      for (var rowIdx = 0; rowIdx < _filteredData.length; rowIdx++) {
        final row = _filteredData[rowIdx];
        final values = [
          row['codigo_requerimiento'] ?? row['id']?.toString() ?? '',
          row['area_destino'] ?? '',
          row['fecha_requerida']?.toString() ?? '',
          row['status'] ?? '',
          row['prioridad'] ?? '',
          row['total_items']?.toString() ?? '0',
          row['creado_por'] ?? '',
        ];
        
        for (var colIdx = 0; colIdx < values.length; colIdx++) {
          sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: colIdx, rowIndex: rowIdx + 1)).value = 
            xl.TextCellValue(values[colIdx]);
        }
      }
      
      final bytes = excel.encode();
      if (bytes != null) {
        final timestamp = DateTime.now().toString().replaceAll(':', '-').split('.')[0];
        final fileName = 'Requirements_$timestamp.xlsx';
        final downloadsDir = Directory('${Platform.environment['USERPROFILE']}\\Downloads');
        final file = File('${downloadsDir.path}\\$fileName');
        await file.writeAsBytes(bytes);
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${tr('exported_to')}: $fileName'), backgroundColor: Colors.green),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.gridBackground,
      child: Column(
        children: [
          // Toolbar
          _buildToolbar(),
          // Header
          _buildHeader(),
          // Data rows
          Expanded(child: _buildDataRows()),
          // Footer
          GridFooter(
            text: '${tr('total_rows')}: ${_filteredData.length}${_data.length != _filteredData.length ? ' / ${_data.length}' : ''}',
          ),
        ],
      ),
    );
  }
  
  Widget _buildToolbar() {
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: const BoxDecoration(
        color: AppColors.gridHeader,
        border: Border(bottom: BorderSide(color: AppColors.border, width: 1)),
      ),
      child: Row(
        children: [
          // Nuevo - Solo si tiene permiso
          if (AuthService.canWriteRequirements)
            _buildToolbarButton(
              icon: Icons.add,
              label: tr('new'),
              color: Colors.teal,
              onPressed: widget.onCreateNew,
            ),
          if (AuthService.canWriteRequirements)
            const SizedBox(width: 8),
          // Refrescar
          _buildToolbarButton(
            icon: Icons.refresh,
            label: tr('refresh'),
            color: Colors.blue,
            onPressed: loadData,
          ),
          const SizedBox(width: 8),
          // Exportar
          _buildToolbarButton(
            icon: Icons.file_download,
            label: tr('export_excel'),
            color: AppColors.buttonExcel,
            onPressed: _exportToExcel,
          ),
          const SizedBox(width: 16),
          // Filtro por Área
          Container(
            width: 120,
            height: 24,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: AppColors.gridBackground,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: AppColors.border),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _filterArea,
                hint: Text(tr('all_areas'), style: const TextStyle(color: Colors.white54, fontSize: 10)),
                isExpanded: true,
                dropdownColor: AppColors.panelBackground,
                style: const TextStyle(color: Colors.white, fontSize: 10),
                icon: const Icon(Icons.arrow_drop_down, size: 16, color: Colors.white54),
                items: [
                  DropdownMenuItem<String>(
                    value: null,
                    child: Text(tr('all_areas'), style: const TextStyle(fontSize: 10)),
                  ),
                  ..._areas.map((area) => DropdownMenuItem<String>(
                    value: area,
                    child: Text(area, style: const TextStyle(fontSize: 10)),
                  )),
                ],
                onChanged: (value) {
                  setState(() => _filterArea = value);
                  loadData();
                },
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Filtro por Status
          Container(
            width: 130,
            height: 24,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: AppColors.gridBackground,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: AppColors.border),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _filterStatus,
                hint: Text(tr('all_status'), style: const TextStyle(color: Colors.white54, fontSize: 10)),
                isExpanded: true,
                dropdownColor: AppColors.panelBackground,
                style: const TextStyle(color: Colors.white, fontSize: 10),
                icon: const Icon(Icons.arrow_drop_down, size: 16, color: Colors.white54),
                items: [
                  DropdownMenuItem<String>(
                    value: null,
                    child: Text(tr('all_status'), style: const TextStyle(fontSize: 10)),
                  ),
                  const DropdownMenuItem<String>(value: 'Pendiente', child: Text('Pendiente', style: TextStyle(fontSize: 10))),
                  const DropdownMenuItem<String>(value: 'En Preparación', child: Text('En Preparación', style: TextStyle(fontSize: 10))),
                  const DropdownMenuItem<String>(value: 'Listo', child: Text('Listo', style: TextStyle(fontSize: 10))),
                  const DropdownMenuItem<String>(value: 'Entregado', child: Text('Entregado', style: TextStyle(fontSize: 10))),
                  const DropdownMenuItem<String>(value: 'Cancelado', child: Text('Cancelado', style: TextStyle(fontSize: 10))),
                ],
                onChanged: (value) {
                  setState(() => _filterStatus = value);
                  loadData();
                },
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Filtro de fecha inicio
          _buildDateFilter(
            label: tr('from'),
            date: _fechaInicio,
            onTap: () => _selectDate(isStart: true),
            onClear: _fechaInicio != null ? () {
              setState(() => _fechaInicio = null);
              loadData();
            } : null,
          ),
          const SizedBox(width: 4),
          // Filtro de fecha fin
          _buildDateFilter(
            label: tr('to'),
            date: _fechaFin,
            onTap: () => _selectDate(isStart: false),
            onClear: _fechaFin != null ? () {
              setState(() => _fechaFin = null);
              loadData();
            } : null,
          ),
          const SizedBox(width: 8),
          // Toggle: Solo pendientes / Todos
          _buildToggleButton(
            isActive: _showPendingOnly,
            activeLabel: tr('pending_only'),
            inactiveLabel: tr('show_all'),
            activeIcon: Icons.pending_actions,
            inactiveIcon: Icons.all_inclusive,
            onTap: () {
              setState(() => _showPendingOnly = !_showPendingOnly);
              loadData();
            },
          ),
          const Spacer(),
          // Búsqueda
          Container(
            width: 180,
            height: 24,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: AppColors.gridBackground,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                const Icon(Icons.search, size: 14, color: Colors.white54),
                const SizedBox(width: 4),
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    style: const TextStyle(fontSize: 10, color: Colors.white),
                    decoration: InputDecoration(
                      hintText: tr('search'),
                      hintStyle: const TextStyle(color: Colors.white38, fontSize: 10),
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                    onChanged: _onSearch,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildToolbarButton({
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
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: color.withOpacity(0.2),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: color.withOpacity(0.5)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 4),
              Text(label, style: TextStyle(fontSize: 11, color: color)),
            ],
          ),
        ),
      ),
    );
  }
  
  Widget _buildToggleButton({
    required bool isActive,
    required String activeLabel,
    required String inactiveLabel,
    required IconData activeIcon,
    required IconData inactiveIcon,
    required VoidCallback onTap,
  }) {
    final color = isActive ? Colors.amber : Colors.grey;
    final label = isActive ? activeLabel : inactiveLabel;
    final icon = isActive ? activeIcon : inactiveIcon;
    
    return Tooltip(
      message: isActive ? tr('click_to_show_all') : tr('click_to_show_pending'),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(4),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            decoration: BoxDecoration(
              color: color.withOpacity(0.2),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: color.withOpacity(0.5)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 12, color: color),
                const SizedBox(width: 4),
                Text(label, style: TextStyle(fontSize: 10, color: color)),
              ],
            ),
          ),
        ),
      ),
    );
  }
  
  Widget _buildDateFilter({
    required String label,
    DateTime? date,
    required VoidCallback onTap,
    VoidCallback? onClear,
  }) {
    final dateFormat = DateFormat('dd/MM/yy');
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 24,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          color: date != null ? Colors.teal.withOpacity(0.2) : AppColors.gridBackground,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: date != null ? Colors.teal : AppColors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.calendar_today, size: 10, color: date != null ? Colors.teal : Colors.white54),
            const SizedBox(width: 4),
            Text(
              date != null ? dateFormat.format(date) : label,
              style: TextStyle(fontSize: 10, color: date != null ? Colors.teal : Colors.white54),
            ),
            if (onClear != null) ...[
              const SizedBox(width: 4),
              GestureDetector(
                onTap: onClear,
                child: const Icon(Icons.close, size: 12, color: Colors.teal),
              ),
            ],
          ],
        ),
      ),
    );
  }
  
  Future<void> _selectDate({required bool isStart}) async {
    final initialDate = isStart ? (_fechaInicio ?? DateTime.now()) : (_fechaFin ?? DateTime.now());
    final result = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.dark(
              primary: Colors.teal,
              onPrimary: Colors.white,
              surface: AppColors.panelBackground,
              onSurface: Colors.white,
            ),
          ),
          child: child!,
        );
      },
    );
    
    if (result != null) {
      setState(() {
        if (isStart) {
          _fechaInicio = result;
        } else {
          _fechaFin = result;
        }
      });
      loadData();
    }
  }
  
  Widget _buildHeader() {
    return Container(
      height: 28,
      decoration: const BoxDecoration(
        color: AppColors.gridHeader,
        border: Border(bottom: BorderSide(color: AppColors.border, width: 1)),
      ),
      child: Row(
        children: [
          _buildHeaderCell(tr('code'), flex: 3),
          _buildHeaderCell(tr('target_area'), flex: 2),
          _buildHeaderCell(tr('required_date'), flex: 2),
          _buildHeaderCell(tr('status'), flex: 2),
          _buildHeaderCell(tr('priority'), flex: 2),
          _buildHeaderCell(tr('items'), flex: 1),
          _buildHeaderCell(tr('created_by'), flex: 2),
        ],
      ),
    );
  }
  
  Widget _buildHeaderCell(String text, {int flex = 1}) {
    return Expanded(
      flex: flex,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        decoration: const BoxDecoration(
          border: Border(right: BorderSide(color: AppColors.border, width: 0.5)),
        ),
        child: Text(
          text,
          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.white),
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
  
  Widget _buildDataRows() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: Colors.teal));
    }
    
    if (_filteredData.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.assignment_outlined, size: 48, color: Colors.white.withOpacity(0.1)),
            const SizedBox(height: 8),
            Text(tr('no_data'), style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 12)),
          ],
        ),
      );
    }
    
    return ListView.builder(
      itemCount: _filteredData.length,
      itemBuilder: (context, index) {
        final row = _filteredData[index];
        final isSelected = index == _selectedIndex;
        final isEven = index % 2 == 0;
        
        return GestureDetector(
          onTap: () {
            setState(() => _selectedIndex = isSelected ? -1 : index);
            widget.onRequirementSelected?.call(isSelected ? null : row);
          },
          onDoubleTap: () {
            // Solo permitir editar si tiene permiso
            if (!AuthService.canWriteRequirements) return;
            setState(() => _selectedIndex = index);
            widget.onRequirementSelected?.call(row);
            widget.onEdit?.call();
          },
          child: Container(
            height: 26,
            decoration: BoxDecoration(
              color: isSelected
                ? AppColors.gridSelectedRow
                : isEven ? AppColors.gridBackground : AppColors.gridRowAlt,
              border: Border(
                bottom: const BorderSide(color: AppColors.border, width: 0.5),
                left: isSelected 
                  ? const BorderSide(color: Colors.teal, width: 3) 
                  : BorderSide.none,
              ),
            ),
            child: Row(
              children: [
                _buildCodeCell(row['codigo_requerimiento'] ?? 'REQ-${row['id']?.toString() ?? ''}', flex: 3),
                _buildDataCell(row['area_destino'] ?? '', flex: 2),
                _buildDataCell(_formatDate(row['fecha_requerida']), flex: 2),
                _buildStatusCell(row['status'] ?? 'Pendiente', flex: 2),
                _buildPriorityCell(row['prioridad'] ?? 'Normal', flex: 2),
                _buildDataCell(row['total_items']?.toString() ?? '0', flex: 1),
                _buildDataCell(row['creado_por'] ?? '', flex: 2),
              ],
            ),
          ),
        );
      },
    );
  }
  
  Widget _buildDataCell(String text, {int flex = 1}) {
    return Expanded(
      flex: flex,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        alignment: Alignment.centerLeft,
        decoration: const BoxDecoration(
          border: Border(right: BorderSide(color: AppColors.border, width: 0.5)),
        ),
        child: Text(
          text,
          style: const TextStyle(fontSize: 10, color: Colors.white),
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
  
  Widget _buildCodeCell(String code, {int flex = 1}) {
    return Expanded(
      flex: flex,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        alignment: Alignment.centerLeft,
        decoration: const BoxDecoration(
          border: Border(right: BorderSide(color: AppColors.border, width: 0.5)),
        ),
        child: Text(
          code,
          style: const TextStyle(fontSize: 10, color: Colors.teal, fontWeight: FontWeight.w600),
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
  
  Widget _buildStatusCell(String status, {int flex = 1}) {
    Color color;
    switch (status) {
      case 'Pendiente': color = Colors.orange; break;
      case 'En Preparación': color = Colors.blue; break;
      case 'Listo': color = Colors.green; break;
      case 'Entregado': color = Colors.teal; break;
      case 'Cancelado': color = Colors.red; break;
      default: color = Colors.grey;
    }
    
    return Expanded(
      flex: flex,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        alignment: Alignment.centerLeft,
        decoration: const BoxDecoration(
          border: Border(right: BorderSide(color: AppColors.border, width: 0.5)),
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
          decoration: BoxDecoration(
            color: color.withOpacity(0.2),
            borderRadius: BorderRadius.circular(3),
          ),
          child: Text(status, style: TextStyle(fontSize: 9, color: color)),
        ),
      ),
    );
  }
  
  Widget _buildPriorityCell(String priority, {int flex = 1}) {
    Color color;
    IconData icon;
    switch (priority) {
      case 'Crítico': color = Colors.red; icon = Icons.priority_high; break;
      case 'Urgente': color = Colors.orange; icon = Icons.warning; break;
      default: color = Colors.grey; icon = Icons.remove;
    }
    
    return Expanded(
      flex: flex,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        alignment: Alignment.centerLeft,
        decoration: const BoxDecoration(
          border: Border(right: BorderSide(color: AppColors.border, width: 0.5)),
        ),
        child: priority == 'Normal'
          ? Text(priority, style: const TextStyle(fontSize: 10, color: Colors.white54))
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 10, color: color),
                const SizedBox(width: 2),
                Text(priority, style: TextStyle(fontSize: 9, color: color, fontWeight: FontWeight.bold)),
              ],
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
}
