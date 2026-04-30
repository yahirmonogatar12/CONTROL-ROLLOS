import 'package:flutter/material.dart';
import 'package:material_warehousing_flutter/core/localization/app_translations.dart';
import 'package:material_warehousing_flutter/core/theme/app_colors.dart';
import 'package:material_warehousing_flutter/core/services/api_service.dart';

/// Result class for the requirements loader dialog
class RequirementsLoaderResult {
  final int requirementId;
  final String codigoRequerimiento;
  final String areaDestino;
  final List<Map<String, dynamic>> items;

  RequirementsLoaderResult({
    required this.requirementId,
    required this.codigoRequerimiento,
    required this.areaDestino,
    required this.items,
  });
}

/// Dialog to load pending requirements into the outgoing module
class RequirementsLoaderDialog extends StatefulWidget {
  final LanguageProvider languageProvider;
  final String? preselectedArea;

  const RequirementsLoaderDialog({
    super.key,
    required this.languageProvider,
    this.preselectedArea,
  });

  @override
  State<RequirementsLoaderDialog> createState() => _RequirementsLoaderDialogState();
}

class _RequirementsLoaderDialogState extends State<RequirementsLoaderDialog> {
  List<Map<String, dynamic>> _requirements = [];
  List<String> _areas = [];
  String? _selectedArea; // null = All Areas (default)
  int? _selectedRequirementId;
  bool _isLoading = true;

  // Only these areas are valid for Requirements in Outgoing
  static const List<String> _validRequirementAreas = [
    'SMD',
    'Assy',
    'IMD',
    'Coating',
    'Micom',
    'IPM',
    'Mantenimiento',
  ];

  String tr(String key) => widget.languageProvider.tr(key);

  @override
  void initState() {
    super.initState();
    // Default to All Areas (null), ignore preselectedArea
    _selectedArea = null;
    _loadAreas();
    _loadRequirements();
  }

  Future<void> _loadAreas() async {
    final areas = await ApiService.getRequirementAreas();
    if (mounted) {
      setState(() {
        // Filter to only valid requirement areas
        _areas = areas.where((a) => _validRequirementAreas.contains(a)).toList();
      });
    }
  }

  Future<void> _loadRequirements() async {
    setState(() => _isLoading = true);
    
    final requirements = await ApiService.getPendingRequirementsForOutgoing(
      area: _selectedArea,
    );
    
    if (mounted) {
      setState(() {
        _requirements = requirements;
        _isLoading = false;
      });
    }
  }

  /// Safely parse a dynamic value to num
  num _parseNum(dynamic value) {
    if (value == null) return 0;
    if (value is num) return value;
    if (value is String) return num.tryParse(value) ?? 0;
    return 0;
  }

  String _formatDate(String? dateStr) {
    if (dateStr == null || dateStr.isEmpty) return '';
    try {
      final date = DateTime.parse(dateStr);
      return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    } catch (e) {
      return dateStr;
    }
  }

  Future<void> _onConfirm() async {
    if (_selectedRequirementId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(tr('select_requirement_first')),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final requirement = await ApiService.getRequirementById(_selectedRequirementId!);
    
    if (requirement != null && mounted) {
      final items = (requirement['items'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [];
      
      Navigator.of(context).pop(RequirementsLoaderResult(
        requirementId: _selectedRequirementId!,
        codigoRequerimiento: requirement['codigo_requerimiento']?.toString() ?? '',
        areaDestino: requirement['area_destino']?.toString() ?? '',
        items: items,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.panelBackground,
      child: Container(
        width: 850,
        height: 500,
        child: Column(
          children: [
            // Toolbar
            _buildToolbar(),
            // Header
            _buildHeader(),
            // Data rows
            Expanded(child: _buildDataRows()),
            // Footer
            _buildFooter(),
          ],
        ),
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
          // Title
          const Icon(Icons.assignment, size: 16, color: Colors.teal),
          const SizedBox(width: 6),
          Text(tr('load_requirements'), style: const TextStyle(fontSize: 12, color: Colors.white, fontWeight: FontWeight.w600)),
          const SizedBox(width: 16),
          // Refresh
          _buildToolbarButton(
            icon: Icons.refresh,
            label: tr('refresh'),
            color: Colors.blue,
            onPressed: _loadRequirements,
          ),
          const SizedBox(width: 16),
          // Filtro por Área
          Container(
            width: 140,
            height: 24,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: AppColors.gridBackground,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: AppColors.border),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: (_selectedArea == null || _areas.contains(_selectedArea)) ? _selectedArea : null,
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
                  setState(() {
                    _selectedArea = value;
                    _selectedRequirementId = null;
                  });
                  _loadRequirements();
                },
              ),
            ),
          ),
          const Spacer(),
          // Count
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.teal.withOpacity(0.2),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '${_requirements.length} ${tr('pending')}',
              style: const TextStyle(color: Colors.teal, fontSize: 10),
            ),
          ),
          const SizedBox(width: 8),
          // Close button
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white54, size: 18),
            onPressed: () => Navigator.of(context).pop(),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
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

  Widget _buildHeader() {
    return Container(
      height: 28,
      decoration: const BoxDecoration(
        color: AppColors.gridHeader,
        border: Border(bottom: BorderSide(color: AppColors.border, width: 1)),
      ),
      child: Row(
        children: [
          _buildHeaderCell('', width: 30), // Radio
          _buildHeaderCell(tr('code'), flex: 3),
          _buildHeaderCell(tr('target_area'), flex: 2),
          _buildHeaderCell(tr('required_date'), flex: 2),
          _buildHeaderCell(tr('priority'), flex: 2),
          _buildHeaderCell(tr('items'), flex: 1),
          _buildHeaderCell(tr('progress'), flex: 3),
        ],
      ),
    );
  }

  Widget _buildHeaderCell(String text, {int flex = 1, double? width}) {
    final child = Container(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: const BoxDecoration(
        border: Border(right: BorderSide(color: AppColors.border, width: 0.5)),
      ),
      child: Text(
        text,
        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.white),
        overflow: TextOverflow.ellipsis,
      ),
    );
    
    if (width != null) {
      return SizedBox(width: width, child: child);
    }
    return Expanded(flex: flex, child: child);
  }

  Widget _buildDataRows() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: Colors.teal));
    }
    
    if (_requirements.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.assignment_outlined, size: 48, color: Colors.white.withOpacity(0.1)),
            const SizedBox(height: 8),
            Text(tr('no_pending_requirements'), style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 12)),
          ],
        ),
      );
    }
    
    return ListView.builder(
      itemCount: _requirements.length,
      itemBuilder: (context, index) {
        final row = _requirements[index];
        final isSelected = _selectedRequirementId == row['id'];
        final isEven = index % 2 == 0;
        final totalQty = _parseNum(row['total_qty_requerida']);
        final deliveredQty = _parseNum(row['total_qty_entregada']);
        final progress = totalQty > 0 ? deliveredQty / totalQty : 0.0;
        
        return GestureDetector(
          onTap: () {
            setState(() => _selectedRequirementId = row['id']);
          },
          onDoubleTap: () {
            setState(() => _selectedRequirementId = row['id']);
            _onConfirm();
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
                // Radio
                SizedBox(
                  width: 30,
                  child: Radio<int>(
                    value: row['id'],
                    groupValue: _selectedRequirementId,
                    onChanged: (value) => setState(() => _selectedRequirementId = value),
                    activeColor: Colors.teal,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                  ),
                ),
                _buildDataCell(row['codigo_requerimiento']?.toString() ?? 'REQ-${row['id']}', flex: 3, isBold: true),
                _buildDataCell(row['area_destino']?.toString() ?? '', flex: 2),
                _buildDataCell(_formatDate(row['fecha_requerida']?.toString()), flex: 2),
                _buildPriorityCell(row['prioridad']?.toString() ?? 'Normal', flex: 2),
                _buildDataCell(row['total_items']?.toString() ?? '0', flex: 1, align: TextAlign.center),
                _buildProgressCell(progress, flex: 3),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildDataCell(String text, {int flex = 1, bool isBold = false, TextAlign align = TextAlign.left}) {
    return Expanded(
      flex: flex,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        alignment: align == TextAlign.center ? Alignment.center : Alignment.centerLeft,
        decoration: const BoxDecoration(
          border: Border(right: BorderSide(color: AppColors.border, width: 0.5)),
        ),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 10, 
            color: Colors.white,
            fontWeight: isBold ? FontWeight.w600 : FontWeight.normal,
          ),
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }

  Widget _buildPriorityCell(String priority, {int flex = 1}) {
    Color color;
    switch (priority.toLowerCase()) {
      case 'crítico':
        color = Colors.red;
        break;
      case 'urgente':
        color = Colors.orange;
        break;
      case 'alta':
        color = Colors.amber;
        break;
      default:
        color = Colors.grey;
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
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
          decoration: BoxDecoration(
            color: color.withOpacity(0.2),
            borderRadius: BorderRadius.circular(3),
            border: Border.all(color: color.withOpacity(0.5)),
          ),
          child: Text(
            priority,
            style: TextStyle(fontSize: 9, color: color, fontWeight: FontWeight.w600),
          ),
        ),
      ),
    );
  }

  Widget _buildProgressCell(double progress, {int flex = 1}) {
    return Expanded(
      flex: flex,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        alignment: Alignment.centerLeft,
        decoration: const BoxDecoration(
          border: Border(right: BorderSide(color: AppColors.border, width: 0.5)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Container(
                height: 8,
                decoration: BoxDecoration(
                  color: Colors.white12,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: progress.clamp(0.0, 1.0),
                  child: Container(
                    decoration: BoxDecoration(
                      color: progress >= 1.0 ? Colors.green : Colors.teal,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
            Text(
              '${(progress * 100).toInt()}%',
              style: const TextStyle(fontSize: 9, color: Colors.white54),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFooter() {
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: const BoxDecoration(
        color: AppColors.gridHeader,
        border: Border(top: BorderSide(color: AppColors.border, width: 1)),
      ),
      child: Row(
        children: [
          Text(
            '${_requirements.length} ${tr('total')}',
            style: const TextStyle(fontSize: 10, color: Colors.white54),
          ),
          const Spacer(),
          // Cancel button
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => Navigator.of(context).pop(),
              borderRadius: BorderRadius.circular(4),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.buttonGray.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: AppColors.buttonGray),
                ),
                child: Text(tr('cancel'), style: const TextStyle(fontSize: 11, color: Colors.white70)),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Load button
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: _selectedRequirementId != null ? _onConfirm : null,
              borderRadius: BorderRadius.circular(4),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                decoration: BoxDecoration(
                  color: _selectedRequirementId != null 
                    ? AppColors.buttonSave.withOpacity(0.8)
                    : Colors.grey.shade700,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: _selectedRequirementId != null 
                      ? AppColors.buttonSave 
                      : Colors.grey.shade600,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.check,
                      size: 14,
                      color: _selectedRequirementId != null ? Colors.white : Colors.white38,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      tr('load'),
                      style: TextStyle(
                        fontSize: 11,
                        color: _selectedRequirementId != null ? Colors.white : Colors.white38,
                        fontWeight: FontWeight.w600,
                      ),
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
}
