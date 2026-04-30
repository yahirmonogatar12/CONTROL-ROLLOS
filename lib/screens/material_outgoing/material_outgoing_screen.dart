import 'package:flutter/material.dart';
import 'package:material_warehousing_flutter/core/localization/app_translations.dart';
import 'package:material_warehousing_flutter/core/services/api_service.dart';
import 'outgoing_form_panel.dart';
import 'outgoing_tab_section.dart';

class MaterialOutgoingScreen extends StatefulWidget {
  final LanguageProvider languageProvider;
  
  const MaterialOutgoingScreen({super.key, required this.languageProvider});

  @override
  State<MaterialOutgoingScreen> createState() => MaterialOutgoingScreenState();
}

class MaterialOutgoingScreenState extends State<MaterialOutgoingScreen> {
  // Key para acceder al form panel
  final GlobalKey<OutgoingFormPanelState> _formKey = GlobalKey();
  
  // Key para acceder al tab section (para actualizar historial)
  final GlobalKey<OutgoingTabSectionState> _tabSectionKey = GlobalKey();
  
  // Datos del BOM seleccionado con outgoing_qty acumulado
  List<Map<String, dynamic>> _bomData = [];
  String? _selectedModel;
  int _planCount = 0;
  
  // Lista de salidas de la sesión actual
  List<Map<String, dynamic>> _sessionOutgoings = [];
  
  // Mapa para rastrear las cantidades de salida por material_code
  Map<String, double> _outgoingQtyByMaterial = {};
  
  // Mapa de ubicaciones por part number
  Map<String, List<String>> _locationsByPartNumber = {};
  
  // Requirements mode
  bool _isRequirementsMode = false;

  void _onModelSelected(String modelo, List<Map<String, dynamic>> bomData, int planCount) async {
    setState(() {
      _selectedModel = modelo;
      _planCount = planCount;
      // Reiniciar el tracking de cantidades al cambiar modelo
      _outgoingQtyByMaterial = {};
      _sessionOutgoings = [];
      _locationsByPartNumber = {};
      // Agregar outgoing_qty a cada item del BOM
      // Preserve in_line and location if they come from requirements (already have values)
      _bomData = bomData.map((item) {
        final materialCode = item['material_code']?.toString() ?? item['codigo_material']?.toString() ?? '';
        final existingInLine = item['in_line'];
        final existingLocation = item['location']?.toString() ?? '';
        return {
          ...item,
          'outgoing_qty': item['outgoing_qty'] ?? _outgoingQtyByMaterial[materialCode] ?? 0.0,
          'in_line': existingInLine ?? 0, // Preserve if from requirements (cantidad_disponible)
          'location': existingLocation.isNotEmpty ? existingLocation : '', // Preserve if from requirements
        };
      }).toList();
    });
    
    // Solo consultar ubicaciones si no vienen del requerimiento (location vacío)
    final needsLocationQuery = _bomData.any((item) => (item['location']?.toString() ?? '').isEmpty);
    
    if (needsLocationQuery) {
      // Consultar ubicaciones para los part numbers del BOM
      final partNumbers = bomData
          .map((item) => item['numero_parte']?.toString() ?? '')
          .where((pn) => pn.isNotEmpty)
          .toSet()
          .toList();
      
      if (partNumbers.isNotEmpty) {
        final locations = await ApiService.getLocationsByPartNumbers(partNumbers);
        setState(() {
          _locationsByPartNumber = locations;
          // Actualizar el BOM con las ubicaciones solo si no tienen una
          _bomData = _bomData.map((item) {
            final partNumber = item['numero_parte']?.toString() ?? '';
            final existingLocation = item['location']?.toString() ?? '';
            if (existingLocation.isEmpty) {
              final locationList = _locationsByPartNumber[partNumber] ?? [];
              return {
                ...item,
                'location': locationList.isNotEmpty ? locationList.join(', ') : '',
              };
            }
            return item;
          }).toList();
        });
      }
    }
  }

  void _onOutgoingSaved(Map<String, dynamic> outgoingData) {
    setState(() {
      // Agregar a la lista de sesión
      _sessionOutgoings.insert(0, outgoingData);
      
      // Actualizar el outgoing_qty del material correspondiente en el BOM
      // Comparar usando part_number ya que material_code puede ser diferente
      final partNumber = outgoingData['numero_parte']?.toString() ?? '';
      final qty = double.tryParse(outgoingData['cantidad_salida']?.toString() ?? '0') ?? 0;
      
      if (partNumber.isNotEmpty) {
        // Acumular la cantidad por part_number
        _outgoingQtyByMaterial[partNumber] = (_outgoingQtyByMaterial[partNumber] ?? 0) + qty;
        
        // Actualizar el BOM con la nueva cantidad
        _bomData = _bomData.map((item) {
          final itemPartNumber = item['numero_parte']?.toString() ?? '';
          if (itemPartNumber.toUpperCase() == partNumber.toUpperCase()) {
            return {
              ...item,
              'outgoing_qty': _outgoingQtyByMaterial[partNumber] ?? 0.0,
            };
          }
          return item;
        }).toList();
      }
    });
    
    // Actualizar historial en tiempo real
    _tabSectionKey.currentState?.addOutgoingToHistory(outgoingData);
    
    // Refrescar ubicaciones después de guardar salida (por si cambia alguna)
    _refreshLocations();
  }
  
  Future<void> _refreshLocations() async {
    final partNumbers = _bomData
        .map((item) => item['numero_parte']?.toString() ?? '')
        .where((pn) => pn.isNotEmpty)
        .toSet()
        .toList();
    
    if (partNumbers.isNotEmpty) {
      final locations = await ApiService.getLocationsByPartNumbers(partNumbers);
      setState(() {
        _locationsByPartNumber = locations;
        _bomData = _bomData.map((item) {
          final partNumber = item['numero_parte']?.toString() ?? '';
          final locationList = _locationsByPartNumber[partNumber] ?? [];
          return {
            ...item,
            'location': locationList.isNotEmpty ? locationList.join(', ') : '',
          };
        }).toList();
      });
    }
  }

  /// Método público para solicitar focus en el campo de escaneo
  void requestScanFocus() {
    _formKey.currentState?.requestScanFocus();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        OutgoingFormPanel(
          key: _formKey,
          languageProvider: widget.languageProvider,
          onModelSelected: _onModelSelected,
          onOutgoingSaved: _onOutgoingSaved,
          currentBomData: _bomData,
          onRequirementsModeChanged: (isReqMode, requirement) {
            setState(() => _isRequirementsMode = isReqMode);
          },
        ),
        Expanded(child: OutgoingTabSection(
          key: _tabSectionKey,
          languageProvider: widget.languageProvider,
          bomData: _bomData,
          planCount: _planCount,
          sessionOutgoings: _sessionOutgoings,
          isRequirementsMode: _isRequirementsMode,
        )),
      ],
    );
  }
}
