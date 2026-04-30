import 'package:flutter/material.dart';
import 'package:material_warehousing_flutter/core/localization/app_translations.dart';
import 'package:material_warehousing_flutter/core/theme/app_colors.dart';
import 'package:material_warehousing_flutter/core/services/auth_service.dart';
import 'package:material_warehousing_flutter/core/services/api_service.dart';
import 'iqc_pending_grid.dart';
import 'iqc_form_panel.dart';
import 'iqc_history_grid.dart';
import 'iqc_tab_section.dart';

class IqcInspectionScreen extends StatefulWidget {
  final LanguageProvider languageProvider;
  
  const IqcInspectionScreen({
    super.key,
    required this.languageProvider,
  });

  @override
  State<IqcInspectionScreen> createState() => _IqcInspectionScreenState();
}

class _IqcInspectionScreenState extends State<IqcInspectionScreen> {
  final TextEditingController _scanController = TextEditingController();
  final FocusNode _scanFocusNode = FocusNode();
  
  Map<String, dynamic>? _currentLotData;
  bool _isLoading = false;
  String? _errorMessage;
  
  // Key para refrescar el grid
  final GlobalKey<IqcPendingGridState> _gridKey = GlobalKey();
  final GlobalKey<IqcHistoryGridState> _historyKey = GlobalKey();
  
  String tr(String key) => widget.languageProvider.tr(key);
  
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scanFocusNode.requestFocus();
    });
  }
  
  @override
  void dispose() {
    _scanController.dispose();
    _scanFocusNode.dispose();
    super.dispose();
  }
  
  Future<void> _onScanSubmitted(String code) async {
    if (code.isEmpty) return;
    
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    
    try {
      final result = await ApiService.getIqcLotByLabel(code);
      
      if (result != null) {
        setState(() {
          _currentLotData = result;
          _isLoading = false;
        });
      } else {
        setState(() {
          _errorMessage = tr('lot_not_found');
          _currentLotData = null;
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
        _isLoading = false;
      });
    }
    
    _scanController.clear();
    _scanFocusNode.requestFocus();
  }
  
  void _onLotSelected(Map<String, dynamic> lotData) {
    // Cuando se selecciona un lote del grid, escanearlo
    final receivingLotCode = lotData['receiving_lot_code']?.toString() ?? '';
    if (receivingLotCode.isNotEmpty) {
      _onScanSubmitted('${receivingLotCode}0001'); // Simular escaneo de primera etiqueta
    }
  }
  
  void _clearCurrentLot() {
    setState(() {
      _currentLotData = null;
      _errorMessage = null;
    });
    _scanFocusNode.requestFocus();
  }
  
  void _onInspectionSaved() {
    // Refrescar el grid y limpiar el formulario
    _gridKey.currentState?.reloadData();
    _historyKey.currentState?.reloadData();
    _clearCurrentLot();
    // Forzar rebuild del estado
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final canWrite = AuthService.canWriteIqc;
    
    return Container(
      color: AppColors.panelBackground,
      child: Column(
        children: [
          // Barra superior con escáner y pestañas
          Container(
            color: AppColors.gridHeader,
            child: Column(
              children: [
                // Fila del escáner
                Container(
                  height: 48,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      // Campo de escaneo
                      const Icon(Icons.qr_code_scanner, color: Colors.white70, size: 20),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 300,
                        child: TextField(
                          controller: _scanController,
                          focusNode: _scanFocusNode,
                          style: const TextStyle(color: Colors.white, fontSize: 14),
                          decoration: InputDecoration(
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            hintText: tr('scan_label_code'),
                            hintStyle: const TextStyle(color: Colors.white38, fontSize: 12),
                            filled: true,
                            fillColor: AppColors.gridBackground,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(4),
                              borderSide: const BorderSide(color: AppColors.border),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(4),
                              borderSide: const BorderSide(color: AppColors.border),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(4),
                              borderSide: const BorderSide(color: Colors.blue, width: 2),
                            ),
                            prefixIcon: const Icon(Icons.search, color: Colors.white38, size: 18),
                          ),
                          onSubmitted: _onScanSubmitted,
                        ),
                      ),
                      const SizedBox(width: 16),
                      
                      // Mostrar información del lote cargado
                      if (_currentLotData != null) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.blue.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: Colors.blue.withOpacity(0.5)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.inventory_2, color: Colors.blue, size: 16),
                              const SizedBox(width: 8),
                              Text(
                                '${tr('receiving_lot')}: ${_currentLotData!['receiving_lot_code']}',
                                style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '| ${_currentLotData!['total_labels']} ${tr('labels')} | ${_currentLotData!['total_qty_received']} pcs',
                                style: const TextStyle(color: Colors.white70, fontSize: 11),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          onPressed: _clearCurrentLot,
                          icon: const Icon(Icons.close, color: Colors.white54, size: 18),
                          tooltip: tr('clean'),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                        ),
                      ],
                      
                      // Mensaje de error
                      if (_errorMessage != null)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.red.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.error_outline, color: Colors.red, size: 16),
                              const SizedBox(width: 8),
                              Text(
                                _errorMessage!,
                                style: const TextStyle(color: Colors.red, fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                      
                      const Spacer(),
                      
                      // Indicador de permisos
                      if (!canWrite)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.orange.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.visibility, color: Colors.orange, size: 16),
                              const SizedBox(width: 8),
                              Text(
                                tr('read_only_mode'),
                                style: const TextStyle(color: Colors.orange, fontSize: 11),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                
                // Pestañas Pending / History se mueven al IqcTabSection
              ],
            ),
          ),
          
          // Contenido principal
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _currentLotData != null
                    ? IqcFormPanel(
                        languageProvider: widget.languageProvider,
                        lotData: _currentLotData!,
                        onInspectionCompleted: _onInspectionSaved,
                        onCancel: _clearCurrentLot,
                      )
                    : IqcTabSection(
                        languageProvider: widget.languageProvider,
                        onLotSelected: _onLotSelected,
                        pendingGridKey: _gridKey,
                        historyGridKey: _historyKey,
                      ),
          ),
        ],
      ),
    );
  }
}
