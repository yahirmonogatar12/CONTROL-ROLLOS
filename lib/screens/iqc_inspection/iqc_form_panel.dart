import 'package:flutter/material.dart';
import 'package:material_warehousing_flutter/core/localization/app_translations.dart';
import 'package:material_warehousing_flutter/core/theme/app_colors.dart';
import 'package:material_warehousing_flutter/core/services/api_service.dart';
import 'package:material_warehousing_flutter/core/services/auth_service.dart';

class IqcFormPanel extends StatefulWidget {
  final LanguageProvider languageProvider;
  final Map<String, dynamic>? lotData;
  final VoidCallback? onInspectionCompleted;
  final VoidCallback? onCancel;
  
  const IqcFormPanel({
    super.key,
    required this.languageProvider,
    this.lotData,
    this.onInspectionCompleted,
    this.onCancel,
  });

  @override
  State<IqcFormPanel> createState() => _IqcFormPanelState();
}

class _IqcFormPanelState extends State<IqcFormPanel> {
  final _formKey = GlobalKey<FormState>();
  
  // Datos del lote
  String _receivingLotCode = '';
  String _partNumber = '';
  String _customer = '';
  int _totalLabels = 0;
  int _totalQtyReceived = 0;
  String _currentStatus = 'Pending';
  int? _inspectionId;
  
  // Campos del formulario IQC
  int _sampleSize = 0;
  
  // Resultados de pruebas
  String _rohsResult = 'Pending';
  String _brightnessResult = 'Pending';
  String _dimensionResult = 'Pending';
  String _colorResult = 'Pending';
  
  // Valores medidos de brillo (5 muestras)
  final List<TextEditingController> _brightnessControllers = 
      List.generate(5, (_) => TextEditingController());
  double? _brightnessTarget;
  double? _brightnessLsl;
  double? _brightnessUsl;
  
  // Valores medidos de dimensión (pueden ser múltiples dimensiones)
  final List<TextEditingController> _dimensionControllers = 
      List.generate(5, (_) => TextEditingController());
  String _dimensionSpec = '';
  
  // Comentarios y disposición
  final _commentsController = TextEditingController();
  String _disposition = 'Pending';
  
  // Estado
  bool _isLoading = false;
  bool _isSaving = false;
  bool _isReadOnly = false;
  
  // Configuración IQC del material (desde Quality Specs)
  Map<String, dynamic>? _materialConfig;
  bool _configLoaded = false;
  
  // Resultado de Appearance
  String _appearanceResult = 'Pending';
  
  // Sample Size por tipo de inspección (calculado según su Sampling Level)
  int _brightnessSampleSize = 0;
  int _dimensionSampleSize = 0;
  int _colorSampleSize = 0;
  int _appearanceSampleSize = 0;
  
  // Mediciones individuales por tipo de inspección
  // Cada elemento: {sampleNum: int, result: 'Pass'/'Fail'/'Pending', value: String?}
  List<Map<String, dynamic>> _brightnessMeasurements = [];
  List<Map<String, dynamic>> _dimensionMeasurements = [];
  List<Map<String, dynamic>> _colorMeasurements = [];
  List<Map<String, dynamic>> _appearanceMeasurements = [];
  
  String tr(String key) => widget.languageProvider.tr(key);
  
  @override
  void initState() {
    super.initState();
    _isReadOnly = !AuthService.canWriteIqc;
    if (widget.lotData != null) {
      _loadLotData(widget.lotData!);
    }
  }
  
  @override
  void didUpdateWidget(covariant IqcFormPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.lotData != oldWidget.lotData && widget.lotData != null) {
      _loadLotData(widget.lotData!);
    }
  }
  
  void _loadLotData(Map<String, dynamic> data) async {
    setState(() {
      _receivingLotCode = data['receiving_lot_code']?.toString() ?? '';
      _partNumber = data['part_number']?.toString() ?? '';
      _customer = data['customer']?.toString() ?? '';
      _totalLabels = int.tryParse(data['total_labels']?.toString() ?? '0') ?? 0;
      _totalQtyReceived = int.tryParse(data['total_qty_received']?.toString() ?? '0') ?? 0;
      _currentStatus = data['status']?.toString() ?? 'Pending';
      _inspectionId = int.tryParse(data['inspection_id']?.toString() ?? '');
      
      // Si hay datos de inspección, cargarlos
      if (data['sample_size'] != null) {
        _sampleSize = int.tryParse(data['sample_size']?.toString() ?? '0') ?? 0;
      } else {
        _calculateSampleSize();
      }
      
      _rohsResult = data['rohs_result']?.toString() ?? 'Pending';
      _brightnessResult = data['brightness_result']?.toString() ?? 'Pending';
      _dimensionResult = data['dimension_result']?.toString() ?? 'Pending';
      _colorResult = data['color_result']?.toString() ?? 'Pending';
      _appearanceResult = data['appearance_result']?.toString() ?? 'Pending';
      _disposition = data['disposition']?.toString() ?? 'Pending';
      _commentsController.text = data['comments']?.toString() ?? '';
      
      _configLoaded = false;
    });
    
    // Cargar configuración IQC del material
    if (_partNumber.isNotEmpty) {
      final config = await ApiService.getMaterialIqcConfig(_partNumber);
      if (mounted) {
        setState(() {
          _materialConfig = config;
          _configLoaded = true;
          
          // Aplicar especificaciones del material a los campos
          if (config != null) {
            _brightnessTarget = double.tryParse(config['brightness_target']?.toString() ?? '');
            _brightnessLsl = double.tryParse(config['brightness_lsl']?.toString() ?? '');
            _brightnessUsl = double.tryParse(config['brightness_usl']?.toString() ?? '');
            _dimensionSpec = _buildDimensionSpecString(config);
            
            // Calcular sample sizes para cada tipo de inspección
            _calculateAllSampleSizes();
          }
        });
        
        // Si hay una inspección existente, cargar las mediciones guardadas
        if (_inspectionId != null) {
          await _loadMeasurements(_inspectionId!);
        }
      }
    }
  }
  
  /// Carga las mediciones guardadas de una inspección existente
  Future<void> _loadMeasurements(int inspectionId) async {
    try {
      final data = await ApiService.getIqcMeasurements(inspectionId);
      if (data.isEmpty) return;
      
      setState(() {
        // Cargar brightness
        if (data['brightness'] != null && data['brightness'] is List) {
          final savedBrightness = data['brightness'] as List;
          for (final saved in savedBrightness) {
            final idx = (saved['sampleNum'] ?? 1) - 1;
            if (idx >= 0 && idx < _brightnessMeasurements.length) {
              _brightnessMeasurements[idx]['result'] = saved['result'] ?? 'Pending';
              _brightnessMeasurements[idx]['value'] = saved['value'] ?? '';
            }
          }
        }
        
        // Cargar dimension
        if (data['dimension'] != null && data['dimension'] is List) {
          final savedDimension = data['dimension'] as List;
          for (final saved in savedDimension) {
            final idx = (saved['sampleNum'] ?? 1) - 1;
            if (idx >= 0 && idx < _dimensionMeasurements.length) {
              _dimensionMeasurements[idx]['result'] = saved['result'] ?? 'Pending';
              _dimensionMeasurements[idx]['value'] = saved['value'] ?? '';
            }
          }
        }
        
        // Cargar color
        if (data['color'] != null && data['color'] is List) {
          final savedColor = data['color'] as List;
          for (final saved in savedColor) {
            final idx = (saved['sampleNum'] ?? 1) - 1;
            if (idx >= 0 && idx < _colorMeasurements.length) {
              _colorMeasurements[idx]['result'] = saved['result'] ?? 'Pending';
              _colorMeasurements[idx]['value'] = saved['value'] ?? '';
            }
          }
        }
        
        // Cargar appearance
        if (data['appearance'] != null && data['appearance'] is List) {
          final savedAppearance = data['appearance'] as List;
          for (final saved in savedAppearance) {
            final idx = (saved['sampleNum'] ?? 1) - 1;
            if (idx >= 0 && idx < _appearanceMeasurements.length) {
              _appearanceMeasurements[idx]['result'] = saved['result'] ?? 'Pending';
              _appearanceMeasurements[idx]['value'] = saved['value'] ?? '';
            }
          }
        }
      });
    } catch (e) {
      print('Error cargando mediciones: $e');
    }
  }
  
  String _buildDimensionSpecString(Map<String, dynamic> config) {
    final parts = <String>[];
    final length = config['dimension_length'];
    final lengthTol = config['dimension_length_tol'];
    final width = config['dimension_width'];
    final widthTol = config['dimension_width_tol'];
    final height = config['dimension_height'];
    final heightTol = config['dimension_height_tol'];
    
    if (length != null) {
      parts.add('L:$length${lengthTol != null ? "±$lengthTol" : ""}');
    }
    if (width != null) {
      parts.add('W:$width${widthTol != null ? "±$widthTol" : ""}');
    }
    if (height != null) {
      parts.add('H:$height${heightTol != null ? "±$heightTol" : ""}');
    }
    return parts.join(' ');
  }
  
  void _calculateSampleSize() {
    // Calcular sample size general (mantener para compatibilidad)
    _sampleSize = _calculateSampleSizeForLevel(_totalQtyReceived, 'II');
  }
  
  // Tabla AQL completa - Lot Size to Code Letter
  // Formato: {maxLotSize: {level: codeLetterIndex}}
  // Índices de code letters: A=0, B=1, C=2, D=3, E=4, F=5, G=6, H=7, J=8, K=9, L=10, M=11, N=12, P=13, Q=14, R=15
  static const Map<int, Map<String, int>> _lotSizeToCodeLetter = {
    2: {'S-1': 0, 'S-2': 0, 'S-3': 0, 'S-4': 0, 'I': 0, 'II': 0, 'III': 1},
    8: {'S-1': 0, 'S-2': 0, 'S-3': 0, 'S-4': 0, 'I': 0, 'II': 1, 'III': 2},
    15: {'S-1': 0, 'S-2': 0, 'S-3': 0, 'S-4': 1, 'I': 0, 'II': 2, 'III': 3},
    25: {'S-1': 0, 'S-2': 0, 'S-3': 1, 'S-4': 2, 'I': 1, 'II': 3, 'III': 4},
    50: {'S-1': 0, 'S-2': 1, 'S-3': 2, 'S-4': 3, 'I': 2, 'II': 4, 'III': 5},
    90: {'S-1': 1, 'S-2': 1, 'S-3': 2, 'S-4': 3, 'I': 2, 'II': 5, 'III': 6},
    150: {'S-1': 1, 'S-2': 2, 'S-3': 3, 'S-4': 4, 'I': 3, 'II': 6, 'III': 7},
    280: {'S-1': 1, 'S-2': 2, 'S-3': 3, 'S-4': 5, 'I': 3, 'II': 7, 'III': 8},
    500: {'S-1': 1, 'S-2': 2, 'S-3': 4, 'S-4': 5, 'I': 4, 'II': 8, 'III': 9},
    1200: {'S-1': 2, 'S-2': 3, 'S-3': 4, 'S-4': 6, 'I': 5, 'II': 9, 'III': 10},
    3200: {'S-1': 2, 'S-2': 3, 'S-3': 5, 'S-4': 7, 'I': 6, 'II': 10, 'III': 11},
    10000: {'S-1': 2, 'S-2': 4, 'S-3': 6, 'S-4': 8, 'I': 7, 'II': 11, 'III': 12},
    35000: {'S-1': 3, 'S-2': 4, 'S-3': 6, 'S-4': 8, 'I': 7, 'II': 12, 'III': 13},
    150000: {'S-1': 3, 'S-2': 4, 'S-3': 7, 'S-4': 9, 'I': 8, 'II': 13, 'III': 14},
    500000: {'S-1': 3, 'S-2': 5, 'S-3': 7, 'S-4': 10, 'I': 9, 'II': 14, 'III': 15},
    999999999: {'S-1': 3, 'S-2': 5, 'S-3': 8, 'S-4': 10, 'I': 9, 'II': 15, 'III': 15},
  };
  
  // Code Letter to Sample Size (índice -> tamaño de muestra)
  static const List<int> _codeLetterToSampleSize = [
    2,   // A = 0
    3,   // B = 1
    5,   // C = 2
    8,   // D = 3
    13,  // E = 4
    20,  // F = 5
    32,  // G = 6
    50,  // H = 7
    80,  // J = 8
    125, // K = 9
    200, // L = 10
    315, // M = 11
    500, // N = 12
    800, // P = 13
    1250, // Q = 14
    2000, // R = 15
  ];
  
  /// Calcula el sample size para un nivel de muestreo específico
  int _calculateSampleSizeForLevel(int lotSize, String samplingLevel) {
    if (lotSize <= 0) return 0;
    
    // Normalizar el nivel de muestreo
    String level = samplingLevel.toUpperCase().trim();
    // Convertir formatos como "Level II" a "II"
    if (level.contains('LEVEL')) {
      level = level.replaceAll('LEVEL', '').trim();
    }
    
    // Encontrar el rango del lot size
    int? codeLetterIndex;
    for (final entry in _lotSizeToCodeLetter.entries) {
      if (lotSize <= entry.key) {
        final levelMap = entry.value;
        codeLetterIndex = levelMap[level];
        break;
      }
    }
    
    if (codeLetterIndex == null) {
      // Si no se encuentra el nivel, usar Level II por defecto
      for (final entry in _lotSizeToCodeLetter.entries) {
        if (lotSize <= entry.key) {
          codeLetterIndex = entry.value['II'];
          break;
        }
      }
    }
    
    if (codeLetterIndex == null || codeLetterIndex >= _codeLetterToSampleSize.length) {
      return 2; // Mínimo sample size
    }
    
    return _codeLetterToSampleSize[codeLetterIndex];
  }
  
  /// Calcula el sample size para cada tipo de inspección según su configuración
  void _calculateAllSampleSizes() {
    if (_materialConfig == null) return;
    
    final lotSize = _totalQtyReceived;
    
    // Brightness
    if (_materialConfig!['brightness_enabled'] == 1) {
      final level = _materialConfig!['brightness_sampling_level']?.toString() ?? 'S-1';
      _brightnessSampleSize = _calculateSampleSizeForLevel(lotSize, level);
      _initializeMeasurements('brightness', _brightnessSampleSize);
    }
    
    // Dimension
    if (_materialConfig!['dimension_enabled'] == 1) {
      final level = _materialConfig!['dimension_sampling_level']?.toString() ?? 'S-1';
      _dimensionSampleSize = _calculateSampleSizeForLevel(lotSize, level);
      _initializeMeasurements('dimension', _dimensionSampleSize);
    }
    
    // Color
    if (_materialConfig!['color_enabled'] == 1) {
      final level = _materialConfig!['color_sampling_level']?.toString() ?? 'S-1';
      _colorSampleSize = _calculateSampleSizeForLevel(lotSize, level);
      _initializeMeasurements('color', _colorSampleSize);
    }
    
    // Appearance
    if (_materialConfig!['appearance_enabled'] == 1) {
      final level = _materialConfig!['appearance_sampling_level']?.toString() ?? 'S-1';
      _appearanceSampleSize = _calculateSampleSizeForLevel(lotSize, level);
      _initializeMeasurements('appearance', _appearanceSampleSize);
    }
  }
  
  /// Inicializa la lista de mediciones para un tipo de inspección
  void _initializeMeasurements(String type, int sampleSize) {
    final measurements = List.generate(sampleSize, (i) => {
      'sampleNum': i + 1,
      'result': 'Pending',
      'value': '',
    });
    
    switch (type) {
      case 'brightness':
        if (_brightnessMeasurements.isEmpty || _brightnessMeasurements.length != sampleSize) {
          _brightnessMeasurements = measurements;
        }
        break;
      case 'dimension':
        if (_dimensionMeasurements.isEmpty || _dimensionMeasurements.length != sampleSize) {
          _dimensionMeasurements = measurements;
        }
        break;
      case 'color':
        if (_colorMeasurements.isEmpty || _colorMeasurements.length != sampleSize) {
          _colorMeasurements = measurements;
        }
        break;
      case 'appearance':
        if (_appearanceMeasurements.isEmpty || _appearanceMeasurements.length != sampleSize) {
          _appearanceMeasurements = measurements;
        }
        break;
    }
  }
  
  /// Calcula el resultado final basado en las mediciones individuales
  String _calculateResultFromMeasurements(List<Map<String, dynamic>> measurements) {
    if (measurements.isEmpty) return 'Pending';
    
    final completed = measurements.where((m) => m['result'] != 'Pending').length;
    if (completed == 0) return 'Pending';
    
    final hasFail = measurements.any((m) => m['result'] == 'Fail');
    if (hasFail) return 'Fail';
    
    final allPass = measurements.every((m) => m['result'] == 'Pass');
    if (allPass) return 'Pass';
    
    return 'Pending';
  }
  
  /// Cuenta las mediciones completadas
  int _countCompletedMeasurements(List<Map<String, dynamic>> measurements) {
    return measurements.where((m) => m['result'] != 'Pending').length;
  }
  
  /// Muestra el modal de inspección para un tipo específico
  Future<void> _showInspectionModal({
    required String type,
    required String title,
    required Color color,
    required IconData icon,
    required int sampleSize,
    required List<Map<String, dynamic>> measurements,
    required Function(List<Map<String, dynamic>>) onSave,
    bool hasValueField = false,
    String? spec,
    double? target,
    double? lsl,
    double? usl,
  }) async {
    if (_isReadOnly) return;
    if (sampleSize == 0) return;
    
    // Crear copia local para editar
    final localMeasurements = measurements.map((m) => Map<String, dynamic>.from(m)).toList();
    
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final completed = localMeasurements.where((m) => m['result'] != 'Pending').length;
          final hasFail = localMeasurements.any((m) => m['result'] == 'Fail');
          final allPass = localMeasurements.every((m) => m['result'] == 'Pass');
          final resultPreview = completed == 0 ? 'Pending' : (hasFail ? 'Fail' : (allPass ? 'Pass' : 'Pending'));
          
          return AlertDialog(
            backgroundColor: const Color(0xFF1E1E2E),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            title: Row(
              children: [
                Icon(icon, color: color, size: 24),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('$title (n=$sampleSize)', style: TextStyle(color: color, fontSize: 16, fontWeight: FontWeight.bold)),
                      if (spec != null && spec.isNotEmpty)
                        Text('Spec: $spec', style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 11)),
                      if (target != null)
                        Text('Target: $target (${lsl ?? "-"} ~ ${usl ?? "-"})', style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 11)),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white54),
                  onPressed: () => Navigator.pop(ctx),
                ),
              ],
            ),
            content: SizedBox(
              width: 500,
              height: 400,
              child: Column(
                children: [
                  // Header row
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      children: [
                        const SizedBox(width: 40, child: Text('#', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontSize: 12))),
                        if (hasValueField)
                          const Expanded(child: Text('Value', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontSize: 12))),
                        const SizedBox(width: 140, child: Center(child: Text('Result', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontSize: 12)))),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Scrollable list of samples
                  Expanded(
                    child: ListView.builder(
                      itemCount: sampleSize,
                      itemBuilder: (ctx, index) {
                        final sample = localMeasurements[index];
                        final isPass = sample['result'] == 'Pass';
                        final isFail = sample['result'] == 'Fail';
                        
                        return Container(
                          margin: const EdgeInsets.only(bottom: 6),
                          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
                          decoration: BoxDecoration(
                            color: isPass 
                                ? Colors.green.withOpacity(0.1)
                                : isFail 
                                    ? Colors.red.withOpacity(0.1)
                                    : Colors.white.withOpacity(0.05),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: isPass 
                                  ? Colors.green.withOpacity(0.3)
                                  : isFail 
                                      ? Colors.red.withOpacity(0.3)
                                      : Colors.white.withOpacity(0.1),
                            ),
                          ),
                          child: Row(
                            children: [
                              // Sample number
                              SizedBox(
                                width: 40,
                                child: Text(
                                  '#${index + 1}',
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(0.8),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                              // Value field (only for brightness)
                              if (hasValueField) ...[
                                Expanded(
                                  child: SizedBox(
                                    height: 32,
                                    child: TextField(
                                      style: const TextStyle(color: Colors.white, fontSize: 12),
                                      decoration: InputDecoration(
                                        hintText: 'Enter value...',
                                        hintStyle: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 11),
                                        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                        isDense: true,
                                        filled: true,
                                        fillColor: Colors.white.withOpacity(0.05),
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(4),
                                          borderSide: BorderSide.none,
                                        ),
                                      ),
                                      keyboardType: TextInputType.number,
                                      controller: TextEditingController(text: sample['value'] ?? ''),
                                      onChanged: (v) {
                                        localMeasurements[index]['value'] = v;
                                      },
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                              ],
                              // Pass/Fail buttons
                              SizedBox(
                                width: 140,
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    // Pass button
                                    InkWell(
                                      onTap: () {
                                        setDialogState(() {
                                          localMeasurements[index]['result'] = 'Pass';
                                        });
                                      },
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                        decoration: BoxDecoration(
                                          color: isPass ? Colors.green : Colors.green.withOpacity(0.1),
                                          borderRadius: BorderRadius.circular(4),
                                          border: Border.all(color: Colors.green, width: isPass ? 2 : 1),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            if (isPass) const Icon(Icons.check, color: Colors.white, size: 14),
                                            if (isPass) const SizedBox(width: 4),
                                            Text('Pass', style: TextStyle(color: isPass ? Colors.white : Colors.green, fontSize: 11, fontWeight: FontWeight.bold)),
                                          ],
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    // Fail button
                                    InkWell(
                                      onTap: () {
                                        setDialogState(() {
                                          localMeasurements[index]['result'] = 'Fail';
                                        });
                                      },
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                        decoration: BoxDecoration(
                                          color: isFail ? Colors.red : Colors.red.withOpacity(0.1),
                                          borderRadius: BorderRadius.circular(4),
                                          border: Border.all(color: Colors.red, width: isFail ? 2 : 1),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            if (isFail) const Icon(Icons.close, color: Colors.white, size: 14),
                                            if (isFail) const SizedBox(width: 4),
                                            Text('Fail', style: TextStyle(color: isFail ? Colors.white : Colors.red, fontSize: 11, fontWeight: FontWeight.bold)),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              // Status summary
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  children: [
                    Text('Completed: $completed/$sampleSize', style: const TextStyle(color: Colors.white70, fontSize: 12)),
                    const SizedBox(width: 16),
                    Text(
                      'Result: $resultPreview',
                      style: TextStyle(
                        color: resultPreview == 'Pass' ? Colors.green : resultPreview == 'Fail' ? Colors.red : Colors.white70,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
              ),
              ElevatedButton(
                onPressed: () {
                  onSave(localMeasurements);
                  Navigator.pop(ctx);
                },
                style: ElevatedButton.styleFrom(backgroundColor: color),
                child: const Text('Save', style: TextStyle(color: Colors.white)),
              ),
            ],
          );
        },
      ),
    );
  }
  
  Future<void> _saveInspection() async {
    if (_isReadOnly) return;
    if (!_formKey.currentState!.validate()) return;
    
    setState(() => _isSaving = true);
    
    try {
      // Obtener datos del lote para enviar al crear
      final lotData = widget.lotData ?? {};
      
      final data = {
        'sample_size': _sampleSize,
        'rohs_result': _rohsResult,
        'brightness_result': _brightnessResult,
        'dimension_result': _dimensionResult,
        'color_result': _colorResult,
        'appearance_result': _appearanceResult,
        'comments': _commentsController.text,
        'inspector': AuthService.currentUser?.username ?? 'unknown',
        'inspector_id': AuthService.currentUser?.id,
        'status': 'InProgress',
        // Datos del lote necesarios para crear
        'material_code': lotData['material_code']?.toString() ?? '',
        'part_number': _partNumber,
        'customer': _customer,
        'total_qty_received': _totalQtyReceived,
        'total_labels': _totalLabels,
        'arrival_date': lotData['arrival_date']?.toString(),
      };
      
      Map<String, dynamic> result;
      if (_inspectionId != null) {
        result = await ApiService.updateIqcInspection(_inspectionId!, data);
      } else {
        // Obtener una etiqueta del lote para crear la inspección
        final labelCode = '${_receivingLotCode}0001';
        result = await ApiService.createIqcInspection(labelCode, data);
      }
      
      if (mounted) {
        if (result['success'] == true) {
          // Guardar el ID de la inspección
          int? savedInspectionId = _inspectionId;
          if (result['data'] != null && result['data']['id'] != null) {
            savedInspectionId = result['data']['id'];
          }
          
          // Guardar las mediciones individuales
          if (savedInspectionId != null) {
            final allMeasurements = <Map<String, dynamic>>[];
            
            // Agregar mediciones de cada tipo
            for (final m in _brightnessMeasurements) {
              allMeasurements.add({
                'type': 'brightness',
                'sampleNum': m['sampleNum'],
                'result': m['result'],
                'value': m['value'],
              });
            }
            for (final m in _dimensionMeasurements) {
              allMeasurements.add({
                'type': 'dimension',
                'sampleNum': m['sampleNum'],
                'result': m['result'],
                'value': m['value'],
              });
            }
            for (final m in _colorMeasurements) {
              allMeasurements.add({
                'type': 'color',
                'sampleNum': m['sampleNum'],
                'result': m['result'],
                'value': m['value'],
              });
            }
            for (final m in _appearanceMeasurements) {
              allMeasurements.add({
                'type': 'appearance',
                'sampleNum': m['sampleNum'],
                'result': m['result'],
                'value': m['value'],
              });
            }
            
            if (allMeasurements.isNotEmpty) {
              await ApiService.saveIqcMeasurements(savedInspectionId, allMeasurements);
            }
          }
          
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(tr('inspection_saved')),
              backgroundColor: Colors.green,
            ),
          );
          setState(() {
            _currentStatus = 'InProgress';
            if (result['data'] != null && result['data']['id'] != null) {
              _inspectionId = result['data']['id'];
            }
          });
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(result['error'] ?? 'Error'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }
  
  Future<void> _closeInspection() async {
    if (_isReadOnly) return;
    if (_inspectionId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr('save_first')), backgroundColor: Colors.orange),
      );
      return;
    }
    
    if (_disposition == 'Pending') {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr('select_disposition')), backgroundColor: Colors.orange),
      );
      return;
    }
    
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.panelBackground,
        title: Text(tr('confirm_close'), style: const TextStyle(color: Colors.white)),
        content: Text(
          '${tr('close_inspection_confirm')} ${tr(_disposition.toLowerCase())}?',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(tr('cancel')),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: _getDispositionColor(_disposition),
            ),
            onPressed: () => Navigator.pop(context, true),
            child: Text(tr('confirm')),
          ),
        ],
      ),
    );
    
    if (confirm != true) return;
    
    setState(() => _isSaving = true);
    
    try {
      final data = {
        'disposition': _disposition,
        'rohs_result': _rohsResult,
        'brightness_result': _brightnessResult,
        'dimension_result': _dimensionResult,
        'color_result': _colorResult,
        'appearance_result': _appearanceResult,
        'comments': _commentsController.text,
        'inspector': AuthService.currentUser?.username ?? 'unknown',
        'inspector_id': AuthService.currentUser?.id,
      };
      
      final result = await ApiService.closeIqcInspection(_inspectionId!, data);
      
      debugPrint('📋 closeIqcInspection result: $result');
      
      if (mounted) {
        if (result['success'] == true) {
          debugPrint('✅ Inspección cerrada, llamando onInspectionCompleted');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(tr('inspection_closed')),
              backgroundColor: Colors.green,
            ),
          );
          widget.onInspectionCompleted?.call();
        } else {
          debugPrint('❌ Error al cerrar: ${result['error']}');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(result['error'] ?? 'Error'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('❌ Exception en closeInspection: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }
  
  Color _getDispositionColor(String disposition) {
    switch (disposition.toLowerCase()) {
      case 'release':
        return Colors.green;
      case 'return':
        return Colors.red;
      case 'scrap':
        return Colors.red.shade900;
      case 'hold':
        return Colors.orange;
      case 'rework':
        return Colors.amber;
      default:
        return Colors.grey;
    }
  }
  
  @override
  void dispose() {
    _commentsController.dispose();
    for (var c in _brightnessControllers) {
      c.dispose();
    }
    for (var c in _dimensionControllers) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.lotData == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.qr_code_scanner, size: 64, color: Colors.white.withOpacity(0.3)),
            const SizedBox(height: 16),
            Text(
              tr('scan_label_to_inspect'),
              style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 16),
            ),
          ],
        ),
      );
    }
    
    return Container(
      color: AppColors.panelBackground,
      child: Form(
        key: _formKey,
        child: Column(
          children: [
            // Header con info del lote
            _buildLotInfoHeader(),
            
            // Formulario
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Sección Resultados de pruebas
                          _buildSectionTitle(tr('test_results'), Icons.fact_check),
                          _buildTestResultsSection(),
                          
                          const SizedBox(height: 20),
                          
                          // Sección Disposición
                          _buildSectionTitle(tr('disposition'), Icons.gavel),
                          _buildDispositionSection(),
                          
                          const SizedBox(height: 20),
                          
                          // Comentarios
                          _buildSectionTitle(tr('comments'), Icons.comment),
                          _buildCommentsSection(),
                        ],
                      ),
                    ),
            ),
            
            // Botones de acción
            if (!_isReadOnly) _buildActionButtons(),
          ],
        ),
      ),
    );
  }
  
  Widget _buildLotInfoHeader() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.gridHeader,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.inventory_2, color: Colors.blue, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _receivingLotCode,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              _buildStatusChip(_currentStatus),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 16,
            runSpacing: 8,
            children: [
              _buildInfoChip(Icons.code, '$_partNumber'),
              _buildInfoChip(Icons.business, _customer),
              _buildInfoChip(Icons.label, '${tr('labels')}: $_totalLabels'),
              _buildInfoChip(Icons.inventory, '${tr('qty')}: $_totalQtyReceived'),
            ],
          ),
        ],
      ),
    );
  }
  
  Widget _buildStatusChip(String status) {
    Color color;
    String text;
    
    switch (status.toLowerCase()) {
      case 'pending':
        color = Colors.orange;
        text = tr('pending');
        break;
      case 'inprogress':
        color = Colors.blue;
        text = tr('iqc_in_progress');
        break;
      case 'released':
        color = Colors.green;
        text = tr('released');
        break;
      case 'rejected':
        color = Colors.red;
        text = tr('rejected');
        break;
      default:
        color = Colors.grey;
        text = status;
    }
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.3),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color),
      ),
      child: Text(
        text,
        style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.bold),
      ),
    );
  }
  
  Widget _buildInfoChip(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: Colors.white54),
        const SizedBox(width: 4),
        Text(text, style: const TextStyle(color: Colors.white70, fontSize: 12)),
      ],
    );
  }
  
  Widget _buildSectionTitle(String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Colors.blue),
          const SizedBox(width: 8),
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildTestResultsSection() {
    // Si no se ha cargado la configuración aún, mostrar loading
    if (!_configLoaded) {
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: AppColors.gridBackground,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.border),
        ),
        child: const Center(
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    
    // Verificar qué inspecciones están habilitadas
    final rohsEnabled = _materialConfig?['rohs_enabled'] == 1;
    final brightnessEnabled = _materialConfig?['brightness_enabled'] == 1;
    final dimensionEnabled = _materialConfig?['dimension_enabled'] == 1;
    final colorEnabled = _materialConfig?['color_enabled'] == 1;
    final appearanceEnabled = _materialConfig?['appearance_enabled'] == 1;
    
    final anyEnabled = rohsEnabled || brightnessEnabled || dimensionEnabled || colorEnabled || appearanceEnabled;
    
    // Si no hay ninguna inspección configurada, mostrar mensaje
    if (!anyEnabled) {
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: AppColors.gridBackground,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.orange.withOpacity(0.5)),
        ),
        child: Column(
          children: [
            Icon(Icons.warning_amber, size: 48, color: Colors.orange.withOpacity(0.7)),
            const SizedBox(height: 12),
            Text(
              tr('no_inspection_configured'),
              style: const TextStyle(color: Colors.orange, fontSize: 14, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              tr('configure_in_quality_specs'),
              style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }
    
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.gridBackground,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // RoHS - Pass/Fail only
          if (rohsEnabled) ...[
            _buildRohsSection(),
            const SizedBox(height: 16),
          ],
          
          // Brightness - con campos de medición
          if (brightnessEnabled) ...[
            _buildBrightnessMeasurements(),
            const SizedBox(height: 16),
          ],
          
          // Dimension - con campos de medición
          if (dimensionEnabled) ...[
            _buildDimensionMeasurements(),
            const SizedBox(height: 16),
          ],
          
          // Color - con spec
          if (colorEnabled) ...[
            _buildColorSection(),
            const SizedBox(height: 16),
          ],
          
          // Appearance - con spec
          if (appearanceEnabled) ...[
            _buildAppearanceSection(),
          ],
        ],
      ),
    );
  }
  
  Widget _buildRohsSection() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.teal.withOpacity(0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.teal.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.eco, size: 18, color: Colors.teal),
          const SizedBox(width: 8),
          Text('RoHS', style: const TextStyle(color: Colors.teal, fontWeight: FontWeight.bold, fontSize: 13)),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.teal.withOpacity(0.2),
              borderRadius: BorderRadius.circular(4),
            ),
            child: const Text('Pass / Fail only', style: TextStyle(color: Colors.teal, fontSize: 10)),
          ),
          const Spacer(),
          SizedBox(
            width: 120,
            child: _buildMiniDropdown(_rohsResult, (v) => setState(() => _rohsResult = v)),
          ),
        ],
      ),
    );
  }
  
  Widget _buildColorSection() {
    final colorSpec = _materialConfig?['color_spec']?.toString() ?? '';
    final samplingLevel = _materialConfig?['color_sampling_level']?.toString() ?? 'S-1';
    final aqlLevel = _materialConfig?['color_aql_level']?.toString() ?? '2.5';
    final completed = _countCompletedMeasurements(_colorMeasurements);
    
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.purple.withOpacity(0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.purple.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.palette, size: 18, color: Colors.purple),
              const SizedBox(width: 8),
              Text(tr('color'), style: const TextStyle(color: Colors.purple, fontWeight: FontWeight.bold, fontSize: 13)),
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.purple.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text('$samplingLevel / AQL $aqlLevel', style: const TextStyle(color: Colors.purple, fontSize: 10)),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.purple.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.purple, width: 1),
                ),
                child: Text('n = $_colorSampleSize', style: const TextStyle(color: Colors.purple, fontSize: 10, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: 12),
              // Botón para abrir modal de inspección
              ElevatedButton.icon(
                onPressed: _colorSampleSize > 0 ? () => _showInspectionModal(
                  type: 'color',
                  title: tr('color'),
                  color: Colors.purple,
                  icon: Icons.palette,
                  sampleSize: _colorSampleSize,
                  measurements: _colorMeasurements,
                  hasValueField: false,
                  spec: colorSpec,
                  onSave: (measurements) {
                    setState(() {
                      _colorMeasurements = measurements;
                      _colorResult = _calculateResultFromMeasurements(measurements);
                    });
                  },
                ) : null,
                icon: const Icon(Icons.assignment, size: 14),
                label: Text('Inspect ($completed/$_colorSampleSize)', style: const TextStyle(fontSize: 11)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.purple.withOpacity(0.3),
                  foregroundColor: Colors.purple,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  minimumSize: Size.zero,
                ),
              ),
              const Spacer(),
              // Resultado
              _buildResultBadge(_colorResult, Colors.purple),
            ],
          ),
          if (colorSpec.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('Spec: $colorSpec', style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 11)),
          ],
        ],
      ),
    );
  }
  
  Widget _buildAppearanceSection() {
    final appearanceSpec = _materialConfig?['appearance_spec']?.toString() ?? '';
    final samplingLevel = _materialConfig?['appearance_sampling_level']?.toString() ?? 'S-1';
    final aqlLevel = _materialConfig?['appearance_aql_level']?.toString() ?? '2.5';
    final completed = _countCompletedMeasurements(_appearanceMeasurements);
    
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.cyan.withOpacity(0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.cyan.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.visibility, size: 18, color: Colors.cyan),
              const SizedBox(width: 8),
              Text(tr('appearance'), style: const TextStyle(color: Colors.cyan, fontWeight: FontWeight.bold, fontSize: 13)),
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.cyan.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text('$samplingLevel / AQL $aqlLevel', style: const TextStyle(color: Colors.cyan, fontSize: 10)),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.cyan.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.cyan, width: 1),
                ),
                child: Text('n = $_appearanceSampleSize', style: const TextStyle(color: Colors.cyan, fontSize: 10, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: 12),
              // Botón para abrir modal de inspección
              ElevatedButton.icon(
                onPressed: _appearanceSampleSize > 0 ? () => _showInspectionModal(
                  type: 'appearance',
                  title: tr('appearance'),
                  color: Colors.cyan,
                  icon: Icons.visibility,
                  sampleSize: _appearanceSampleSize,
                  measurements: _appearanceMeasurements,
                  hasValueField: false,
                  spec: appearanceSpec,
                  onSave: (measurements) {
                    setState(() {
                      _appearanceMeasurements = measurements;
                      _appearanceResult = _calculateResultFromMeasurements(measurements);
                    });
                  },
                ) : null,
                icon: const Icon(Icons.assignment, size: 14),
                label: Text('Inspect ($completed/$_appearanceSampleSize)', style: const TextStyle(fontSize: 11)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.cyan.withOpacity(0.3),
                  foregroundColor: Colors.cyan,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  minimumSize: Size.zero,
                ),
              ),
              const Spacer(),
              // Resultado
              _buildResultBadge(_appearanceResult, Colors.cyan),
            ],
          ),
          if (appearanceSpec.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('Spec: $appearanceSpec', style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 11)),
          ],
        ],
      ),
    );
  }

  Widget _buildBrightnessMeasurements() {
    final samplingLevel = _materialConfig?['brightness_sampling_level']?.toString() ?? 'S-1';
    final aqlLevel = _materialConfig?['brightness_aql_level']?.toString() ?? '2.5';
    final completed = _countCompletedMeasurements(_brightnessMeasurements);
    
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.amber.withOpacity(0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.amber.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.light_mode, size: 18, color: Colors.amber),
              const SizedBox(width: 8),
              Text(tr('brightness'), style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 13)),
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.amber.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text('$samplingLevel / AQL $aqlLevel', style: const TextStyle(color: Colors.amber, fontSize: 10)),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.amber.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.amber, width: 1),
                ),
                child: Text('n = $_brightnessSampleSize', style: const TextStyle(color: Colors.amber, fontSize: 10, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: 12),
              // Spec info
              if (_brightnessTarget != null)
                Text(
                  'Target: $_brightnessTarget (${_brightnessLsl ?? "-"} ~ ${_brightnessUsl ?? "-"})',
                  style: const TextStyle(color: Colors.amber, fontSize: 10),
                ),
              const SizedBox(width: 12),
              // Botón para abrir modal de inspección
              ElevatedButton.icon(
                onPressed: _brightnessSampleSize > 0 ? () => _showInspectionModal(
                  type: 'brightness',
                  title: tr('brightness'),
                  color: Colors.amber,
                  icon: Icons.light_mode,
                  sampleSize: _brightnessSampleSize,
                  measurements: _brightnessMeasurements,
                  hasValueField: true,
                  target: _brightnessTarget,
                  lsl: _brightnessLsl,
                  usl: _brightnessUsl,
                  onSave: (measurements) {
                    setState(() {
                      _brightnessMeasurements = measurements;
                      _brightnessResult = _calculateResultFromMeasurements(measurements);
                    });
                  },
                ) : null,
                icon: const Icon(Icons.assignment, size: 14),
                label: Text('Inspect ($completed/$_brightnessSampleSize)', style: const TextStyle(fontSize: 11)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.amber.withOpacity(0.3),
                  foregroundColor: Colors.amber,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  minimumSize: Size.zero,
                ),
              ),
              const Spacer(),
              // Resultado
              _buildResultBadge(_brightnessResult, Colors.amber),
            ],
          ),
        ],
      ),
    );
  }
  
  Widget _buildDimensionMeasurements() {
    final samplingLevel = _materialConfig?['dimension_sampling_level']?.toString() ?? 'S-1';
    final aqlLevel = _materialConfig?['dimension_aql_level']?.toString() ?? '2.5';
    final completed = _countCompletedMeasurements(_dimensionMeasurements);
    
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.blue.withOpacity(0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.blue.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.straighten, size: 18, color: Colors.blue),
              const SizedBox(width: 8),
              Text(tr('dimension'), style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold, fontSize: 13)),
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text('$samplingLevel / AQL $aqlLevel', style: const TextStyle(color: Colors.blue, fontSize: 10)),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.blue, width: 1),
                ),
                child: Text('n = $_dimensionSampleSize', style: const TextStyle(color: Colors.blue, fontSize: 10, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: 12),
              // Spec info
              if (_dimensionSpec.isNotEmpty)
                Text(
                  _dimensionSpec,
                  style: const TextStyle(color: Colors.blue, fontSize: 10),
                ),
              const SizedBox(width: 12),
              // Botón para abrir modal de inspección
              ElevatedButton.icon(
                onPressed: _dimensionSampleSize > 0 ? () => _showInspectionModal(
                  type: 'dimension',
                  title: tr('dimension'),
                  color: Colors.blue,
                  icon: Icons.straighten,
                  sampleSize: _dimensionSampleSize,
                  measurements: _dimensionMeasurements,
                  hasValueField: true,
                  spec: _dimensionSpec,
                  onSave: (measurements) {
                    setState(() {
                      _dimensionMeasurements = measurements;
                      _dimensionResult = _calculateResultFromMeasurements(measurements);
                    });
                  },
                ) : null,
                icon: const Icon(Icons.assignment, size: 14),
                label: Text('Inspect ($completed/$_dimensionSampleSize)', style: const TextStyle(fontSize: 11)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue.withOpacity(0.3),
                  foregroundColor: Colors.blue,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  minimumSize: Size.zero,
                ),
              ),
              const Spacer(),
              // Resultado
              _buildResultBadge(_dimensionResult, Colors.blue),
            ],
          ),
        ],
      ),
    );
  }
  
  Widget _buildMiniDropdown(String value, Function(String) onChanged) {
    return Container(
      height: 28,
      decoration: BoxDecoration(
        color: value == 'Pass' ? Colors.green.withOpacity(0.2) : 
               value == 'Fail' ? Colors.red.withOpacity(0.2) : 
               AppColors.panelBackground,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: value == 'Pass' ? Colors.green : 
                 value == 'Fail' ? Colors.red : 
                 AppColors.border,
        ),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isExpanded: true,
          dropdownColor: AppColors.panelBackground,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          style: const TextStyle(color: Colors.white, fontSize: 10),
          icon: const Icon(Icons.arrow_drop_down, size: 16),
          items: ['Pending', 'Pass', 'Fail'].map((e) => DropdownMenuItem(
            value: e,
            child: Text(tr(e.toLowerCase())),
          )).toList(),
          onChanged: _isReadOnly ? null : (v) => onChanged(v!),
        ),
      ),
    );
  }
  
  Widget _buildResultBadge(String result, Color baseColor) {
    Color bgColor;
    Color textColor;
    IconData? icon;
    
    switch (result) {
      case 'Pass':
        bgColor = Colors.green.withOpacity(0.2);
        textColor = Colors.green;
        icon = Icons.check_circle;
        break;
      case 'Fail':
        bgColor = Colors.red.withOpacity(0.2);
        textColor = Colors.red;
        icon = Icons.cancel;
        break;
      default:
        bgColor = baseColor.withOpacity(0.1);
        textColor = baseColor.withOpacity(0.7);
        icon = Icons.hourglass_empty;
    }
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: textColor.withOpacity(0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: textColor),
          const SizedBox(width: 4),
          Text(result, style: TextStyle(color: textColor, fontSize: 11, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
  
  Widget _buildDispositionSection() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.gridBackground,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _getDispositionColor(_disposition).withOpacity(0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(tr('select_disposition'), style: const TextStyle(color: Colors.white70, fontSize: 11)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildDispositionChip('Release', Icons.check_circle, Colors.green),
              _buildDispositionChip('Hold', Icons.pause_circle, Colors.orange),
              _buildDispositionChip('Rework', Icons.build_circle, Colors.amber),
              _buildDispositionChip('Return', Icons.undo, Colors.red),
              _buildDispositionChip('Scrap', Icons.delete_forever, Colors.red.shade900),
            ],
          ),
        ],
      ),
    );
  }
  
  Widget _buildDispositionChip(String disposition, IconData icon, Color color) {
    final isSelected = _disposition == disposition;
    
    return InkWell(
      onTap: _isReadOnly ? null : () => setState(() => _disposition = disposition),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? color.withOpacity(0.3) : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: isSelected ? color : Colors.grey.withOpacity(0.5)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: isSelected ? color : Colors.grey),
            const SizedBox(width: 4),
            Text(
              tr(disposition.toLowerCase()),
              style: TextStyle(
                color: isSelected ? color : Colors.grey,
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildCommentsSection() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.gridBackground,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: TextFormField(
        controller: _commentsController,
        maxLines: 3,
        enabled: !_isReadOnly,
        style: const TextStyle(color: Colors.white, fontSize: 12),
        decoration: InputDecoration(
          hintText: tr('enter_comments'),
          hintStyle: const TextStyle(color: Colors.white38),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.all(12),
        ),
      ),
    );
  }
  
  Widget _buildActionButtons() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.gridHeader,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          if (widget.onCancel != null)
            TextButton.icon(
              onPressed: widget.onCancel,
              icon: const Icon(Icons.arrow_back, size: 16),
              label: Text(tr('back')),
            ),
          const Spacer(),
          ElevatedButton.icon(
            onPressed: _isSaving ? null : _saveInspection,
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
            icon: _isSaving 
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.save, size: 16),
            label: Text(tr('save')),
          ),
          const SizedBox(width: 12),
          ElevatedButton.icon(
            onPressed: _isSaving || _inspectionId == null ? null : _closeInspection,
            style: ElevatedButton.styleFrom(
              backgroundColor: _getDispositionColor(_disposition),
            ),
            icon: const Icon(Icons.check, size: 16),
            label: Text(tr('close_inspection')),
          ),
        ],
      ),
    );
  }
}
