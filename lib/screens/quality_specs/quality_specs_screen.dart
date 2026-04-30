import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:excel/excel.dart' as xl;
import 'package:file_picker/file_picker.dart';
import 'package:material_warehousing_flutter/core/localization/app_translations.dart';
import 'package:material_warehousing_flutter/core/theme/app_colors.dart';
import 'package:material_warehousing_flutter/core/services/api_service.dart';
import 'package:material_warehousing_flutter/core/widgets/grid_footer.dart';

// ============================================
// Quality Specs Screen - Configuración IQC por Material
// Muestra todos los materiales y permite configurar:
// - Si requiere IQC
// - Nivel de muestreo (Sampling Level)
// - Specs de brillo, dimensión, etc.
// ============================================
class QualitySpecsScreen extends StatefulWidget {
  final LanguageProvider languageProvider;
  
  const QualitySpecsScreen({
    super.key,
    required this.languageProvider,
  });

  @override
  State<QualitySpecsScreen> createState() => _QualitySpecsScreenState();
}

class _QualitySpecsScreenState extends State<QualitySpecsScreen> {
  List<Map<String, dynamic>> _materials = [];
  List<Map<String, dynamic>> _filteredMaterials = [];
  bool _isLoading = true;
  int _selectedIndex = -1;
  
  // Filtros
  String _searchText = '';
  bool _showOnlyIqcRequired = false;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _keyboardFocusNode = FocusNode();
  
  String tr(String key) => widget.languageProvider.tr(key);

  @override
  void initState() {
    super.initState();
    _loadMaterials();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _keyboardFocusNode.dispose();
    super.dispose();
  }

  Future<void> _loadMaterials() async {
    setState(() => _isLoading = true);
    try {
      final data = await ApiService.getMaterialesForIqc();
      setState(() {
        _materials = data;
        _applyFilters();
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      _showSnackBar('${tr("error_loading_materials")}: $e', isError: true);
    }
  }

  void _applyFilters() {
    _filteredMaterials = _materials.where((m) {
      // Filtro de búsqueda
      if (_searchText.isNotEmpty) {
        final searchLower = _searchText.toLowerCase();
        final partNumber = m['numero_parte']?.toString().toLowerCase() ?? '';
        final materialCode = m['codigo_material']?.toString().toLowerCase() ?? '';
        final classification = m['clasificacion']?.toString().toLowerCase() ?? '';
        if (!partNumber.contains(searchLower) && 
            !materialCode.contains(searchLower) &&
            !classification.contains(searchLower)) {
          return false;
        }
      }
      
      // Filtro solo IQC Required
      if (_showOnlyIqcRequired && m['iqc_required'] != 1) {
        return false;
      }
      
      return true;
    }).toList();
  }

  void _showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
      ),
    );
  }

  Future<void> _toggleIqcRequired(Map<String, dynamic> material) async {
    final partNumber = material['numero_parte'];
    final currentValue = material['iqc_required'] == 1;
    
    final result = await ApiService.updateMaterialIqcConfig(
      partNumber, 
      {'iqc_required': !currentValue ? 1 : 0},
    );
    
    if (result['success'] == true) {
      await _loadMaterials();
      _showSnackBar(!currentValue ? '${tr("iqc_activated")} $partNumber' : '${tr("iqc_deactivated")} $partNumber');
    } else {
      _showSnackBar('Error: ${result['message']}', isError: true);
    }
  }

  Future<void> _showSpecsDialog(Map<String, dynamic> material) async {
    final partNumber = material['numero_parte'];
    
    // Estados de habilitación
    bool rohsEnabled = material['rohs_enabled'] == 1;
    bool brightnessEnabled = material['brightness_enabled'] == 1;
    bool dimensionEnabled = material['dimension_enabled'] == 1;
    bool colorEnabled = material['color_enabled'] == 1;
    bool appearanceEnabled = material['appearance_enabled'] == 1;
    
    // Brightness
    String brightnessSampling = material['brightness_sampling_level'] ?? 'S-1';
    String brightnessAql = material['brightness_aql_level'] ?? '2.5';
    final brightnessTargetController = TextEditingController(text: material['brightness_target']?.toString() ?? '');
    final brightnessLslController = TextEditingController(text: material['brightness_lsl']?.toString() ?? '');
    final brightnessUslController = TextEditingController(text: material['brightness_usl']?.toString() ?? '');
    
    // Dimension (mm with decimals)
    String dimensionSampling = material['dimension_sampling_level'] ?? 'S-1';
    String dimensionAql = material['dimension_aql_level'] ?? '2.5';
    final dimLengthController = TextEditingController(text: material['dimension_length']?.toString() ?? '');
    final dimLengthTolController = TextEditingController(text: material['dimension_length_tol']?.toString() ?? '');
    final dimWidthController = TextEditingController(text: material['dimension_width']?.toString() ?? '');
    final dimWidthTolController = TextEditingController(text: material['dimension_width_tol']?.toString() ?? '');
    final dimHeightController = TextEditingController(text: material['dimension_height']?.toString() ?? '');
    final dimHeightTolController = TextEditingController(text: material['dimension_height_tol']?.toString() ?? '');
    
    // Color
    String colorSampling = material['color_sampling_level'] ?? 'S-1';
    String colorAql = material['color_aql_level'] ?? '2.5';
    final colorSpecController = TextEditingController(text: material['color_spec'] ?? '');
    
    // Appearance
    String appearanceSampling = material['appearance_sampling_level'] ?? 'S-1';
    String appearanceAql = material['appearance_aql_level'] ?? '2.5';
    final appearanceSpecController = TextEditingController(text: material['appearance_spec'] ?? '');
    
    final samplingLevels = ['I', 'II', 'III', 'S-1', 'S-2', 'S-3', 'S-4'];
    final aqlLevels = ['0.065', '0.10', '0.15', '0.25', '0.40', '0.65', '1.0', '1.5', '2.5', '4.0', '6.5'];
    
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          
          Widget buildInspectionSection({
            required String title,
            required IconData icon,
            required Color color,
            required bool enabled,
            required Function(bool) onEnabledChanged,
            required String sampling,
            required Function(String) onSamplingChanged,
            required String aql,
            required Function(String) onAqlChanged,
            List<Widget>? extraFields,
          }) {
            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: enabled ? color.withOpacity(0.1) : AppColors.gridBackground,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: enabled ? color.withOpacity(0.5) : AppColors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header con checkbox y título
                  Row(
                    children: [
                      SizedBox(
                        width: 24,
                        height: 24,
                        child: Checkbox(
                          value: enabled,
                          onChanged: (v) => onEnabledChanged(v ?? false),
                          activeColor: color,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(icon, size: 18, color: enabled ? color : Colors.white38),
                      const SizedBox(width: 8),
                      Text(
                        title,
                        style: TextStyle(
                          color: enabled ? color : Colors.white38,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                  
                  // Campos de Sampling y AQL (solo si está habilitado)
                  if (enabled) ...[
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        // Sampling Level
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(tr('sampling_level'), style: const TextStyle(color: Colors.white70, fontSize: 10)),
                              const SizedBox(height: 4),
                              Container(
                                height: 32,
                                padding: const EdgeInsets.symmetric(horizontal: 8),
                                decoration: BoxDecoration(
                                  color: AppColors.panelBackground,
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(color: AppColors.border),
                                ),
                                child: DropdownButtonHideUnderline(
                                  child: DropdownButton<String>(
                                    value: samplingLevels.contains(sampling) ? sampling : 'II',
                                    items: samplingLevels.map((e) => DropdownMenuItem(
                                      value: e,
                                      child: Text(e, style: const TextStyle(color: Colors.white, fontSize: 11)),
                                    )).toList(),
                                    onChanged: (v) => onSamplingChanged(v ?? 'II'),
                                    isExpanded: true,
                                    isDense: true,
                                    dropdownColor: AppColors.panelBackground,
                                    icon: const Icon(Icons.arrow_drop_down, size: 16, color: Colors.white54),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        // AQL Level
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(tr('aql_level'), style: const TextStyle(color: Colors.white70, fontSize: 10)),
                              const SizedBox(height: 4),
                              Container(
                                height: 32,
                                padding: const EdgeInsets.symmetric(horizontal: 8),
                                decoration: BoxDecoration(
                                  color: AppColors.panelBackground,
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(color: AppColors.border),
                                ),
                                child: DropdownButtonHideUnderline(
                                  child: DropdownButton<String>(
                                    value: aqlLevels.contains(aql) ? aql : '0.65',
                                    items: aqlLevels.map((e) => DropdownMenuItem(
                                      value: e,
                                      child: Text(e, style: const TextStyle(color: Colors.white, fontSize: 11)),
                                    )).toList(),
                                    onChanged: (v) => onAqlChanged(v ?? '0.65'),
                                    isExpanded: true,
                                    isDense: true,
                                    dropdownColor: AppColors.panelBackground,
                                    icon: const Icon(Icons.arrow_drop_down, size: 16, color: Colors.white54),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    
                    // Campos extra específicos de cada tipo
                    if (extraFields != null) ...[
                      const SizedBox(height: 12),
                      ...extraFields,
                    ],
                  ],
                ],
              ),
            );
          }
          
          return AlertDialog(
            backgroundColor: AppColors.panelBackground,
            title: Row(
              children: [
                const Icon(Icons.settings, color: Colors.cyan),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(tr('iqc_configuration'), style: const TextStyle(color: Colors.white)),
                      Text(partNumber, style: const TextStyle(color: Colors.cyan, fontSize: 12)),
                    ],
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: 600,
              height: 500,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // RoHS - Solo checkbox, sin sampling/aql
                    Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: rohsEnabled ? Colors.green.withOpacity(0.1) : AppColors.gridBackground,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: rohsEnabled ? Colors.green.withOpacity(0.5) : AppColors.border),
                      ),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 24,
                            height: 24,
                            child: Checkbox(
                              value: rohsEnabled,
                              onChanged: (v) => setDialogState(() => rohsEnabled = v ?? false),
                              activeColor: Colors.green,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Icon(Icons.eco, size: 18, color: rohsEnabled ? Colors.green : Colors.white38),
                          const SizedBox(width: 8),
                          Text(
                            tr('rohs_inspection'),
                            style: TextStyle(
                              color: rohsEnabled ? Colors.green : Colors.white38,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                          if (rohsEnabled) ...[
                            const Spacer(),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.green.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                tr('pass_fail_only'),
                                style: const TextStyle(color: Colors.green, fontSize: 10),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    
                    // Brightness
                    buildInspectionSection(
                      title: tr('brightness_inspection'),
                      icon: Icons.light_mode,
                      color: Colors.amber,
                      enabled: brightnessEnabled,
                      onEnabledChanged: (v) => setDialogState(() => brightnessEnabled = v),
                      sampling: brightnessSampling,
                      onSamplingChanged: (v) => setDialogState(() => brightnessSampling = v),
                      aql: brightnessAql,
                      onAqlChanged: (v) => setDialogState(() => brightnessAql = v),
                      extraFields: [
                        Row(
                          children: [
                            Expanded(child: _buildDialogTextField(tr('target'), brightnessTargetController, isNumeric: true)),
                            const SizedBox(width: 8),
                            Expanded(child: _buildDialogTextField(tr('lsl'), brightnessLslController, isNumeric: true)),
                            const SizedBox(width: 8),
                            Expanded(child: _buildDialogTextField(tr('usl'), brightnessUslController, isNumeric: true)),
                          ],
                        ),
                      ],
                    ),
                    
                    // Dimension (mm with decimals)
                    buildInspectionSection(
                      title: '${tr('dimension_inspection')} (mm)',
                      icon: Icons.straighten,
                      color: Colors.purple,
                      enabled: dimensionEnabled,
                      onEnabledChanged: (v) => setDialogState(() => dimensionEnabled = v),
                      sampling: dimensionSampling,
                      onSamplingChanged: (v) => setDialogState(() => dimensionSampling = v),
                      aql: dimensionAql,
                      onAqlChanged: (v) => setDialogState(() => dimensionAql = v),
                      extraFields: [
                        // Length
                        Row(
                          children: [
                            SizedBox(width: 60, child: Text('${tr("length")}:', style: const TextStyle(color: Colors.white70, fontSize: 11))),
                            Expanded(child: _buildDialogTextField('mm', dimLengthController, isNumeric: true)),
                            const SizedBox(width: 8),
                            const Text('±', style: TextStyle(color: Colors.white54)),
                            const SizedBox(width: 8),
                            Expanded(child: _buildDialogTextField(tr('tolerance'), dimLengthTolController, isNumeric: true)),
                          ],
                        ),
                        const SizedBox(height: 8),
                        // Width
                        Row(
                          children: [
                            SizedBox(width: 60, child: Text('${tr("width")}:', style: const TextStyle(color: Colors.white70, fontSize: 11))),
                            Expanded(child: _buildDialogTextField('mm', dimWidthController, isNumeric: true)),
                            const SizedBox(width: 8),
                            const Text('±', style: TextStyle(color: Colors.white54)),
                            const SizedBox(width: 8),
                            Expanded(child: _buildDialogTextField(tr('tolerance'), dimWidthTolController, isNumeric: true)),
                          ],
                        ),
                        const SizedBox(height: 8),
                        // Height
                        Row(
                          children: [
                            SizedBox(width: 60, child: Text('${tr("height")}:', style: const TextStyle(color: Colors.white70, fontSize: 11))),
                            Expanded(child: _buildDialogTextField('mm', dimHeightController, isNumeric: true)),
                            const SizedBox(width: 8),
                            const Text('±', style: TextStyle(color: Colors.white54)),
                            const SizedBox(width: 8),
                            Expanded(child: _buildDialogTextField(tr('tolerance'), dimHeightTolController, isNumeric: true)),
                          ],
                        ),
                      ],
                    ),
                    
                    // Color
                    buildInspectionSection(
                      title: tr('color_inspection'),
                      icon: Icons.palette,
                      color: Colors.orange,
                      enabled: colorEnabled,
                      onEnabledChanged: (v) => setDialogState(() => colorEnabled = v),
                      sampling: colorSampling,
                      onSamplingChanged: (v) => setDialogState(() => colorSampling = v),
                      aql: colorAql,
                      onAqlChanged: (v) => setDialogState(() => colorAql = v),
                      extraFields: [
                        _buildDialogTextField(tr('color_specification'), colorSpecController, hint: 'e.g., White RAL 9010'),
                      ],
                    ),
                    
                    // Appearance (new)
                    buildInspectionSection(
                      title: tr('appearance_inspection'),
                      icon: Icons.visibility,
                      color: Colors.teal,
                      enabled: appearanceEnabled,
                      onEnabledChanged: (v) => setDialogState(() => appearanceEnabled = v),
                      sampling: appearanceSampling,
                      onSamplingChanged: (v) => setDialogState(() => appearanceSampling = v),
                      aql: appearanceAql,
                      onAqlChanged: (v) => setDialogState(() => appearanceAql = v),
                      extraFields: [
                        _buildDialogTextField(
                          tr('how_should_material_look'), 
                          appearanceSpecController,
                          hint: tr('describe_expected_appearance'),
                          maxLines: 3,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(tr('cancel'), style: const TextStyle(color: Colors.white54)),
              ),
              ElevatedButton(
                onPressed: () async {
                  final configData = {
                    // RoHS (solo enabled, sin sampling/aql)
                    'rohs_enabled': rohsEnabled ? 1 : 0,
                    // Brightness
                    'brightness_enabled': brightnessEnabled ? 1 : 0,
                    'brightness_sampling_level': brightnessSampling,
                    'brightness_aql_level': brightnessAql,
                    'brightness_target': double.tryParse(brightnessTargetController.text),
                    'brightness_lsl': double.tryParse(brightnessLslController.text),
                    'brightness_usl': double.tryParse(brightnessUslController.text),
                    // Dimension
                    'dimension_enabled': dimensionEnabled ? 1 : 0,
                    'dimension_sampling_level': dimensionSampling,
                    'dimension_aql_level': dimensionAql,
                    'dimension_length': double.tryParse(dimLengthController.text),
                    'dimension_length_tol': double.tryParse(dimLengthTolController.text),
                    'dimension_width': double.tryParse(dimWidthController.text),
                    'dimension_width_tol': double.tryParse(dimWidthTolController.text),
                    'dimension_height': double.tryParse(dimHeightController.text),
                    'dimension_height_tol': double.tryParse(dimHeightTolController.text),
                    // Color
                    'color_enabled': colorEnabled ? 1 : 0,
                    'color_sampling_level': colorSampling,
                    'color_aql_level': colorAql,
                    'color_spec': colorSpecController.text,
                    // Appearance
                    'appearance_enabled': appearanceEnabled ? 1 : 0,
                    'appearance_sampling_level': appearanceSampling,
                    'appearance_aql_level': appearanceAql,
                    'appearance_spec': appearanceSpecController.text,
                  };
                  
                  final result = await ApiService.updateMaterialIqcConfig(partNumber, configData);
                  
                  Navigator.pop(ctx);
                  
                  if (result['success'] == true) {
                    _showSnackBar('${tr("configuration_saved")} $partNumber');
                    await _loadMaterials();
                  } else {
                    _showSnackBar('Error: ${result['message']}', isError: true);
                  }
                },
                style: ElevatedButton.styleFrom(backgroundColor: Colors.cyan),
                child: Text(tr('save')),
              ),
            ],
          );
        },
      ),
    );
    
    // Limpiar controladores
    brightnessTargetController.dispose();
    brightnessLslController.dispose();
    brightnessUslController.dispose();
    dimLengthController.dispose();
    dimLengthTolController.dispose();
    dimWidthController.dispose();
    dimWidthTolController.dispose();
    dimHeightController.dispose();
    dimHeightTolController.dispose();
    colorSpecController.dispose();
    appearanceSpecController.dispose();
  }

  Widget _buildDialogSection(String title, IconData icon, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 16, color: Colors.cyan),
            const SizedBox(width: 8),
            Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.gridBackground,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: children,
          ),
        ),
      ],
    );
  }

  Widget _buildDialogTextField(String label, TextEditingController controller, {
    String? hint,
    bool isNumeric = false,
    int maxLines = 1,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11)),
        const SizedBox(height: 4),
        TextField(
          controller: controller,
          maxLines: maxLines,
          keyboardType: isNumeric ? TextInputType.number : TextInputType.text,
          style: const TextStyle(color: Colors.white, fontSize: 12),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: Colors.white24, fontSize: 11),
            filled: true,
            fillColor: AppColors.panelBackground,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(4),
              borderSide: BorderSide(color: AppColors.border),
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            isDense: true,
          ),
        ),
      ],
    );
  }

  Widget _buildInspectionCheckbox(String label, bool value, Function(bool?) onChanged) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 24,
          height: 24,
          child: Checkbox(
            value: value,
            onChanged: onChanged,
            activeColor: Colors.cyan,
          ),
        ),
        Text(label, style: const TextStyle(color: Colors.white, fontSize: 12)),
      ],
    );
  }

  // ============ BULK UPLOAD ============
  Future<void> _handleBulkUpload() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'xls'],
      );
      
      if (result == null || result.files.isEmpty) return;
      
      final file = File(result.files.single.path!);
      final bytes = await file.readAsBytes();
      final excel = xl.Excel.decodeBytes(bytes);
      
      final sheet = excel.tables.values.first;
      if (sheet.maxRows < 2) {
        _showSnackBar(tr('file_empty'), isError: true);
        return;
      }
      
      // Leer encabezados
      final headers = <String>[];
      for (int col = 0; col < sheet.maxColumns; col++) {
        final cell = sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: col, rowIndex: 0));
        final cellValue = cell.value;
        String headerText = '';
        if (cellValue is xl.TextCellValue) {
          headerText = cellValue.value.toString().toLowerCase().trim();
        } else {
          headerText = cellValue?.toString().toLowerCase().trim() ?? '';
        }
        headers.add(headerText);
      }
      
      // Mapear columnas
      final columnMap = <String, int>{};
      final expectedColumns = [
        'numero_parte', 'iqc_required', 'sampling_level', 'aql_level',
        'rohs_enabled', 'brightness_enabled', 'dimension_enabled', 'color_enabled',
        'brightness_target', 'brightness_lsl', 'brightness_usl', 'dimension_spec'
      ];
      
      for (var col in expectedColumns) {
        final idx = headers.indexOf(col.toLowerCase());
        if (idx >= 0) columnMap[col] = idx;
      }
      
      if (!columnMap.containsKey('numero_parte')) {
        _showSnackBar('${tr("missing_required_column")}: numero_parte', isError: true);
        return;
      }
      
      // Leer datos
      final configs = <Map<String, dynamic>>[];
      for (int row = 1; row < sheet.maxRows; row++) {
        final config = <String, dynamic>{};
        
        for (var entry in columnMap.entries) {
          final cell = sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: entry.value, rowIndex: row));
          final cellValue = cell.value;
          
          dynamic realValue;
          if (cellValue is xl.TextCellValue) {
            realValue = cellValue.value;
          } else if (cellValue is xl.IntCellValue) {
            realValue = cellValue.value;
          } else if (cellValue is xl.DoubleCellValue) {
            realValue = cellValue.value;
          } else if (cellValue is xl.BoolCellValue) {
            realValue = cellValue.value;
          } else {
            realValue = cellValue?.toString();
          }
          
          // Convertir booleans
          if (['iqc_required', 'rohs_enabled', 'brightness_enabled', 'dimension_enabled', 'color_enabled'].contains(entry.key)) {
            realValue = realValue?.toString().toLowerCase() == 'true' || realValue?.toString() == '1' ? 1 : 0;
          } else if (['brightness_target', 'brightness_lsl', 'brightness_usl'].contains(entry.key)) {
            realValue = double.tryParse(realValue?.toString() ?? '');
          }
          
          config[entry.key] = realValue;
        }
        
        if (config['numero_parte'] != null) {
          configs.add(config);
        }
      }
      
      if (configs.isEmpty) {
        _showSnackBar(tr('no_valid_data'), isError: true);
        return;
      }
      
      // Confirmar
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppColors.panelBackground,
          title: Text(tr('confirm_upload'), style: const TextStyle(color: Colors.white)),
          content: Text('${configs.length} ${tr("materials_will_be_updated")}',
            style: const TextStyle(color: Colors.white70)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(tr('cancel')),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(tr('confirm')),
            ),
          ],
        ),
      );
      
      if (confirm != true) return;
      
      // Enviar al backend
      setState(() => _isLoading = true);
      final response = await ApiService.bulkUpdateMaterialIqcConfig(configs);
      
      if (response['success'] == true) {
        _showSnackBar('${tr("updated_materials")}: ${response['updated']}');
        await _loadMaterials();
      } else {
        _showSnackBar('Error: ${response['message']}', isError: true);
      }
    } catch (e) {
      _showSnackBar('${tr("error_processing_file")}: $e', isError: true);
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // ============ EXPORT TO EXCEL ============
  Future<void> _exportToExcel() async {
    try {
      final excel = xl.Excel.createExcel();
      final sheet = excel['IQC_Config'];
      
      // Encabezados
      final headers = [
        'numero_parte', 'codigo_material', 'clasificacion', 'iqc_required',
        'sampling_level', 'aql_level', 'rohs_enabled', 'brightness_enabled',
        'dimension_enabled', 'color_enabled', 'brightness_target', 
        'brightness_lsl', 'brightness_usl', 'dimension_spec'
      ];
      
      for (int i = 0; i < headers.length; i++) {
        sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0)).value = 
            xl.TextCellValue(headers[i]);
      }
      
      // Datos
      for (int row = 0; row < _filteredMaterials.length; row++) {
        final m = _filteredMaterials[row];
        for (int col = 0; col < headers.length; col++) {
          final value = m[headers[col]]?.toString() ?? '';
          sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row + 1)).value = 
              xl.TextCellValue(value);
        }
      }
      
      if (excel.tables.containsKey('Sheet1')) {
        excel.delete('Sheet1');
      }
      
      final bytes = excel.encode();
      if (bytes == null) return;
      
      final documentsPath = Platform.environment['USERPROFILE'] ?? 'C:\\Users\\Public';
      final fileName = 'IQC_Config_${DateTime.now().millisecondsSinceEpoch}.xlsx';
      final filePath = '$documentsPath\\Documents\\$fileName';
      
      final file = File(filePath);
      await file.writeAsBytes(bytes);
      
      _showSnackBar('${tr("exported_to")} $filePath');
    } catch (e) {
      _showSnackBar('${tr("error_exporting")}: $e', isError: true);
    }
  }

  void _handleKeyEvent(KeyEvent event) {
    if (event is KeyDownEvent) {
      // Navegación con flechas
      if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
        if (_selectedIndex < _filteredMaterials.length - 1) {
          setState(() => _selectedIndex++);
        }
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
        if (_selectedIndex > 0) {
          setState(() => _selectedIndex--);
        }
      }
      // Enter para abrir specs
      if (event.logicalKey == LogicalKeyboardKey.enter && _selectedIndex >= 0) {
        _showSpecsDialog(_filteredMaterials[_selectedIndex]);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return KeyboardListener(
      focusNode: _keyboardFocusNode,
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: Column(
        children: [
          // Toolbar
          _buildToolbar(),
          
          // Data grid
          Expanded(
            child: _isLoading 
                ? const Center(child: CircularProgressIndicator())
                : _buildDataGrid(),
          ),
          
          // Footer
          GridFooter(
            text: '${_filteredMaterials.length} ${tr("materials")}${_selectedIndex >= 0 ? " | ${tr("selected")}: ${_selectedIndex + 1}" : ""}',
          ),
        ],
      ),
    );
  }

  Widget _buildToolbar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.panelBackground,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          // Title
          const Icon(Icons.settings, color: Colors.cyan, size: 20),
          const SizedBox(width: 8),
          Text(
            tr('iqc_configuration_by_material'),
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 24),
          
          // Search
          SizedBox(
            width: 250,
            height: 32,
            child: TextField(
              controller: _searchController,
              style: const TextStyle(color: Colors.white, fontSize: 12),
              decoration: InputDecoration(
                hintText: tr('search_part_number'),
                hintStyle: const TextStyle(color: Colors.white38, fontSize: 11),
                prefixIcon: const Icon(Icons.search, size: 18, color: Colors.white54),
                filled: true,
                fillColor: AppColors.gridBackground,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(4),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 8),
              ),
              onChanged: (value) {
                setState(() {
                  _searchText = value;
                  _applyFilters();
                });
              },
            ),
          ),
          const SizedBox(width: 16),
          
          // Filter IQC Required
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 20,
                height: 20,
                child: Checkbox(
                  value: _showOnlyIqcRequired,
                  onChanged: (v) {
                    setState(() {
                      _showOnlyIqcRequired = v ?? false;
                      _applyFilters();
                    });
                  },
                  activeColor: Colors.cyan,
                ),
              ),
              const SizedBox(width: 4),
              Text(tr('only_iqc_required'), style: const TextStyle(color: Colors.white70, fontSize: 11)),
            ],
          ),
          
          const Spacer(),
          
          // Upload Excel
          Tooltip(
            message: tr('upload_excel_config'),
            child: ElevatedButton.icon(
              icon: const Icon(Icons.upload_file, size: 16),
              label: Text(tr('upload'), style: const TextStyle(fontSize: 11)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              onPressed: _handleBulkUpload,
            ),
          ),
          const SizedBox(width: 8),
          
          // Export
          Tooltip(
            message: tr('export_excel'),
            child: IconButton(
              icon: Icon(Icons.download, color: AppColors.buttonExcel, size: 20),
              onPressed: _exportToExcel,
            ),
          ),
          
          // Refresh
          Tooltip(
            message: tr('refresh'),
            child: IconButton(
              icon: const Icon(Icons.refresh, color: Colors.white54, size: 20),
              onPressed: _loadMaterials,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDataGrid() {
    if (_filteredMaterials.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.inventory_2, size: 64, color: Colors.white24),
            const SizedBox(height: 16),
            Text(
              _materials.isEmpty ? tr('no_materials_found') : tr('no_matching_materials'),
              style: const TextStyle(fontSize: 16, color: Colors.white54),
            ),
          ],
        ),
      );
    }
    
    return Column(
      children: [
        // Header row
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.panelBackground,
            border: Border(bottom: BorderSide(color: AppColors.border, width: 2)),
          ),
          child: Row(
            children: [
              _buildHeaderCell('IQC', width: 50, centered: true),
              _buildHeaderCell(tr('part_number'), flex: 2),
              _buildHeaderCell(tr('specification'), flex: 3),
              _buildHeaderCell(tr('inspections_enabled'), flex: 2, centered: true),
              _buildHeaderCell('', width: 50), // Edit column
            ],
          ),
        ),
        
        // Data rows
        Expanded(
          child: ListView.builder(
            itemCount: _filteredMaterials.length,
            itemBuilder: (context, index) {
              final m = _filteredMaterials[index];
              final isSelected = index == _selectedIndex;
              final iqcRequired = m['iqc_required'] == 1;
              
              return InkWell(
                onTap: () => setState(() => _selectedIndex = index),
                onDoubleTap: () => _showSpecsDialog(m),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: isSelected 
                        ? AppColors.gridSelectedRow 
                        : (index % 2 == 0 ? AppColors.gridRowEven : AppColors.gridRowOdd),
                    border: Border(
                      bottom: BorderSide(color: AppColors.border.withOpacity(0.3)),
                    ),
                  ),
                  child: Row(
                    children: [
                      // IQC Required Checkbox
                      SizedBox(
                        width: 50,
                        child: Center(
                          child: Checkbox(
                            value: iqcRequired,
                            onChanged: (_) => _toggleIqcRequired(m),
                            activeColor: Colors.cyan,
                            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                        ),
                      ),
                      
                      // Part Number
                      Expanded(
                        flex: 2,
                        child: Text(
                          m['numero_parte'] ?? '',
                          style: TextStyle(
                            color: iqcRequired ? Colors.cyan : Colors.white,
                            fontWeight: iqcRequired ? FontWeight.bold : FontWeight.normal,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      
                      // Specification (Especificacion)
                      Expanded(
                        flex: 3,
                        child: Text(
                          m['especificacion_material'] ?? '',
                          style: const TextStyle(color: Colors.white70, fontSize: 11),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 2,
                        ),
                      ),
                      
                      // Inspections Enabled (badges)
                      Expanded(
                        flex: 2,
                        child: iqcRequired
                            ? Wrap(
                                spacing: 4,
                                runSpacing: 4,
                                alignment: WrapAlignment.center,
                                children: [
                                  if (m['rohs_enabled'] == 1) _buildInspectionBadge('RoHS', Colors.green, m['rohs_sampling_level'], m['rohs_aql_level']),
                                  if (m['brightness_enabled'] == 1) _buildInspectionBadge('Bright', Colors.amber, m['brightness_sampling_level'], m['brightness_aql_level']),
                                  if (m['dimension_enabled'] == 1) _buildInspectionBadge('Dim', Colors.purple, m['dimension_sampling_level'], m['dimension_aql_level']),
                                  if (m['color_enabled'] == 1) _buildInspectionBadge('Color', Colors.orange, m['color_sampling_level'], m['color_aql_level']),
                                  if (m['appearance_enabled'] == 1) _buildInspectionBadge('Appear', Colors.teal, m['appearance_sampling_level'], m['appearance_aql_level']),
                                  if (m['rohs_enabled'] != 1 && m['brightness_enabled'] != 1 && m['dimension_enabled'] != 1 && m['color_enabled'] != 1 && m['appearance_enabled'] != 1)
                                    Text(tr('no_inspections'), style: const TextStyle(color: Colors.white38, fontSize: 10)),
                                ],
                              )
                            : const Center(child: Text('-', style: TextStyle(color: Colors.white38))),
                      ),
                      
                      // Edit button
                      SizedBox(
                        width: 50,
                        child: IconButton(
                          icon: const Icon(Icons.edit, size: 16),
                          color: iqcRequired ? Colors.cyan : Colors.white38,
                          onPressed: iqcRequired ? () => _showSpecsDialog(m) : null,
                          tooltip: 'Edit Configuration',
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
  
  Widget _buildInspectionBadge(String label, Color color, String? sampling, String? aql) {
    return Tooltip(
      message: 'Sampling: ${sampling ?? 'II'} | AQL: ${aql ?? '0.65'}',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: color.withOpacity(0.2),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: color.withOpacity(0.5)),
        ),
        child: Text(
          label,
          style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  Widget _buildHeaderCell(String text, {int flex = 0, double? width, bool centered = false}) {
    final child = Text(
      text,
      style: const TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.bold,
        fontSize: 11,
      ),
      textAlign: centered ? TextAlign.center : TextAlign.left,
    );
    
    if (width != null) {
      return SizedBox(width: width, child: centered ? Center(child: child) : child);
    }
    return Expanded(flex: flex > 0 ? flex : 1, child: child);
  }

  Widget _buildEditableDropdown({
    required String value,
    required List<String> items,
    required Function(String) onChanged,
    double width = 70,
  }) {
    return Container(
      width: width,
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: AppColors.gridBackground,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: AppColors.border),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: items.contains(value) ? value : items.first,
          items: items.map((e) => DropdownMenuItem(
            value: e,
            child: Text(e, style: const TextStyle(color: Colors.white, fontSize: 10)),
          )).toList(),
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
          isExpanded: true,
          isDense: true,
          dropdownColor: AppColors.panelBackground,
          icon: const Icon(Icons.arrow_drop_down, size: 16, color: Colors.white54),
        ),
      ),
    );
  }

  Future<void> _quickUpdate(Map<String, dynamic> material, String field, String value) async {
    final partNumber = material['numero_parte'];
    final result = await ApiService.updateMaterialIqcConfig(partNumber, {field: value});
    
    if (result['success'] == true) {
      // Actualizar localmente sin recargar todo
      setState(() {
        final index = _materials.indexWhere((m) => m['numero_parte'] == partNumber);
        if (index >= 0) {
          _materials[index][field] = value;
          _applyFilters();
        }
      });
    } else {
      _showSnackBar('Error: ${result['message']}', isError: true);
    }
  }

  Widget _buildSpecBadge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.2),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withOpacity(0.5)),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.bold),
      ),
    );
  }
}
