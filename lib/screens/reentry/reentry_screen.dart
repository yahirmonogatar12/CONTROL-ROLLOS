import 'package:flutter/material.dart';
import 'package:material_warehousing_flutter/core/localization/app_translations.dart';
import 'package:material_warehousing_flutter/core/services/api_service.dart';
import 'package:material_warehousing_flutter/core/services/auth_service.dart';
import 'package:material_warehousing_flutter/core/theme/app_colors.dart';
import 'package:material_warehousing_flutter/core/widgets/field_decoration.dart';
import 'package:material_warehousing_flutter/core/widgets/horizontal_field.dart';
import 'package:material_warehousing_flutter/screens/reentry/reentry_history_grid.dart';

/// Pantalla de Reingreso para PC
/// Permite reubicar materiales escaneando o ingresando códigos
class ReentryScreen extends StatefulWidget {
  final LanguageProvider languageProvider;

  const ReentryScreen({
    super.key,
    required this.languageProvider,
  });

  @override
  State<ReentryScreen> createState() => _ReentryScreenState();
}

class _ReentryScreenState extends State<ReentryScreen> {
  // Nueva ubicación
  final TextEditingController _locationController = TextEditingController();
  
  // Campo de escaneo
  final TextEditingController _scanController = TextEditingController();
  final FocusNode _scanFocusNode = FocusNode();
  
  // Lista de materiales a reubicar
  final List<Map<String, dynamic>> _materialsToRelocate = [];
  
  // Key para el grid de historial
  final GlobalKey<ReentryHistoryGridState> _historyGridKey = GlobalKey();
  
  // Estado
  bool _isProcessing = false;
  bool _isSubmitting = false;
  String? _statusMessage;
  bool _statusIsError = false;
  
  // Tab activo: 0 = Reingreso, 1 = Historial
  int _activeTab = 0;

  String tr(String key) => widget.languageProvider.tr(key);

  @override
  void initState() {
    super.initState();
    
    // Auto-focus en el campo de ubicación
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scanFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _locationController.dispose();
    _scanController.dispose();
    _scanFocusNode.dispose();
    super.dispose();
  }

  void _reloadHistory() {
    _historyGridKey.currentState?.reloadData();
  }

  Future<void> _onScan(String code) async {
    if (code.trim().isEmpty) return;
    
    _scanController.clear();
    
    // Verificar ubicación
    if (_locationController.text.trim().isEmpty) {
      _showStatus(tr('enter_new_location_first'), isError: true);
      _scanFocusNode.requestFocus();
      return;
    }
    
    // Verificar duplicados
    final exists = _materialsToRelocate.any(
      (m) => m['codigo_material_recibido'] == code.trim()
    );
    if (exists) {
      _showStatus(tr('material_already_added'), isError: true);
      _scanFocusNode.requestFocus();
      return;
    }

    setState(() => _isProcessing = true);

    try {
      final material = await ApiService.getReentryByCode(code.trim());
      
      if (material == null) {
        _showStatus('${tr('material_not_found')}: $code', isError: true);
      } else {
        setState(() {
          _materialsToRelocate.add(material);
        });
        _showStatus('✓ ${material['numero_parte']} ${tr('added')}', isError: false);
      }
    } catch (e) {
      _showStatus('Error: $e', isError: true);
    } finally {
      setState(() => _isProcessing = false);
      _scanFocusNode.requestFocus();
    }
  }

  void _removeMaterial(int index) {
    setState(() {
      _materialsToRelocate.removeAt(index);
    });
  }

  void _clearAll() {
    setState(() {
      _materialsToRelocate.clear();
      _statusMessage = null;
    });
  }

  Future<void> _confirmReentry() async {
    if (_materialsToRelocate.isEmpty) {
      _showStatus(tr('no_materials_scanned'), isError: true);
      return;
    }
    
    final newLocation = _locationController.text.trim();
    if (newLocation.isEmpty) {
      _showStatus(tr('enter_new_location_first'), isError: true);
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final ids = _materialsToRelocate.map((m) => m['id'] as int).toList();
      final user = AuthService.currentUser;
      
      final result = await ApiService.bulkReentry(
        ids,
        newLocation,
        user?.nombreCompleto,
      );

      if (result['success'] == true) {
        final count = result['successCount'] ?? ids.length;
        _showStatus('✓ $count ${tr('materials_relocated')}', isError: false);
        
        setState(() {
          _materialsToRelocate.clear();
        });
        
        // Recargar historial
        _reloadHistory();
      } else {
        _showStatus(result['error'] ?? tr('reentry_error'), isError: true);
      }
    } catch (e) {
      _showStatus('Error: $e', isError: true);
    } finally {
      setState(() => _isSubmitting = false);
    }
  }

  void _showStatus(String message, {bool isError = false}) {
    setState(() {
      _statusMessage = message;
      _statusIsError = isError;
    });
    
    Future.delayed(Duration(seconds: isError ? 5 : 3), () {
      if (mounted && _statusMessage == message) {
        setState(() => _statusMessage = null);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Panel de formulario superior (estilo Warehousing)
        _buildFormPanel(),
        // Sección de tabs inferior
        Expanded(
          child: _buildTabSection(),
        ),
      ],
    );
  }

  /// Panel de formulario superior con campos de entrada
  Widget _buildFormPanel() {
    final canWrite = AuthService.canWriteReentry;
    
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.panelBackground,
        border: Border(
          bottom: BorderSide(color: AppColors.border, width: 1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Fila 1: Ubicación y escaneo
          Row(
            children: [
              // Campo de nueva ubicación
              Expanded(
                flex: 2,
                child: HorizontalField(
                  label: tr('new_location'),
                  labelWidth: 110,
                  child: Expanded(
                    child: SizedBox(
                      height: 28,
                      child: TextField(
                        controller: _locationController,
                        enabled: canWrite,
                        style: const TextStyle(color: Colors.white, fontSize: 12),
                        decoration: fieldDecoration(hintText: canWrite ? tr('enter_new_location') : tr('view_only_mode')).copyWith(
                          prefixIcon: const Padding(
                            padding: EdgeInsets.only(left: 8, right: 4),
                            child: Icon(Icons.location_on, color: AppColors.headerTab, size: 16),
                          ),
                          prefixIconConstraints: const BoxConstraints(minWidth: 30, minHeight: 28),
                          fillColor: canWrite ? AppColors.fieldBackground : const Color(0xFF1A1A2E),
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              // Campo de escaneo
              Expanded(
                flex: 3,
                child: HorizontalField(
                  label: tr('scan_code'),
                  labelWidth: 100,
                  child: Expanded(
                    child: SizedBox(
                      height: 28,
                      child: TextField(
                        controller: _scanController,
                        focusNode: _scanFocusNode,
                        enabled: canWrite && _locationController.text.trim().isNotEmpty,
                        style: const TextStyle(color: Colors.white, fontSize: 12),
                        decoration: fieldDecoration(hintText: canWrite ? tr('scan_or_enter_code') : tr('view_only_mode')).copyWith(
                          prefixIcon: const Padding(
                            padding: EdgeInsets.only(left: 8, right: 4),
                            child: Icon(Icons.qr_code_scanner, color: Colors.white54, size: 16),
                          ),
                          prefixIconConstraints: const BoxConstraints(minWidth: 30, minHeight: 28),
                          fillColor: canWrite && _locationController.text.trim().isNotEmpty
                              ? AppColors.fieldBackground
                              : const Color(0xFF1A1A2E),
                        ),
                        onSubmitted: canWrite ? _onScan : null,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              // Contador de materiales
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.headerTab.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: AppColors.headerTab.withOpacity(0.5)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.inventory_2, color: AppColors.headerTab, size: 16),
                    const SizedBox(width: 6),
                    Text(
                      '${_materialsToRelocate.length}',
                      style: const TextStyle(
                        color: AppColors.headerTab,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      tr('materials_scanned'),
                      style: const TextStyle(color: Colors.white70, fontSize: 11),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Fila 2: Mensaje de estado y botones
          Row(
            children: [
              // Mensaje de estado
              Expanded(
                child: _statusMessage != null
                    ? Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: _statusIsError
                              ? Colors.red.withOpacity(0.15)
                              : Colors.green.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: _statusIsError ? Colors.red.withOpacity(0.5) : Colors.green.withOpacity(0.5),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _statusIsError ? Icons.error_outline : Icons.check_circle_outline,
                              color: _statusIsError ? Colors.red : Colors.green,
                              size: 16,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _statusMessage!,
                              style: TextStyle(
                                color: _statusIsError ? Colors.red : Colors.green,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      )
                    : !canWrite
                        ? Row(
                            children: [
                              const Icon(Icons.lock_outline, color: Colors.orange, size: 16),
                              const SizedBox(width: 8),
                              Text(
                                tr('view_only_mode'),
                                style: const TextStyle(color: Colors.orange, fontSize: 12),
                              ),
                            ],
                          )
                    : _locationController.text.trim().isEmpty
                        ? Row(
                            children: [
                              const Icon(Icons.info_outline, color: Colors.orange, size: 16),
                              const SizedBox(width: 8),
                              Text(
                                tr('enter_new_location_first'),
                                style: const TextStyle(color: Colors.orange, fontSize: 12),
                              ),
                            ],
                          )
                        : const SizedBox.shrink(),
              ),
              const SizedBox(width: 16),
              // Botón Limpiar
              if (canWrite)
              SizedBox(
                height: 30,
                child: ElevatedButton.icon(
                  onPressed: _materialsToRelocate.isNotEmpty ? _clearAll : null,
                  icon: const Icon(Icons.clear_all, size: 16),
                  label: Text(tr('clear_all'), style: const TextStyle(fontSize: 12)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange.withOpacity(0.8),
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: Colors.grey.withOpacity(0.3),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                  ),
                ),
              ),
              if (canWrite)
              const SizedBox(width: 8),
              // Botón Confirmar
              if (canWrite)
              SizedBox(
                height: 30,
                child: ElevatedButton.icon(
                  onPressed: _materialsToRelocate.isNotEmpty &&
                             _locationController.text.trim().isNotEmpty &&
                             !_isSubmitting
                      ? _confirmReentry
                      : null,
                  icon: _isSubmitting
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.check_circle, size: 16),
                  label: Text(
                    _isSubmitting ? tr('processing') : tr('confirm_reentry'),
                    style: const TextStyle(fontSize: 12),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: Colors.grey.withOpacity(0.3),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Sección de tabs con lista de materiales e historial
  Widget _buildTabSection() {
    return Container(
      color: AppColors.panelBackground,
      child: Column(
        children: [
          // Tab bar
          Container(
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.subPanelBackground,
              border: Border(
                bottom: BorderSide(color: AppColors.border),
              ),
            ),
            child: Row(
              children: [
                _buildTab(0, tr('materials_to_relocate'), Icons.move_to_inbox),
                _buildTab(1, tr('reentry_history'), Icons.history),
                const Spacer(),
                if (_activeTab == 1)
                  IconButton(
                    onPressed: _reloadHistory,
                    icon: const Icon(Icons.refresh, color: Colors.white54, size: 18),
                    tooltip: tr('refresh'),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                  ),
              ],
            ),
          ),
          // Tab content
          Expanded(
            child: _activeTab == 0 ? _buildMaterialsTab() : _buildHistoryTab(),
          ),
        ],
      ),
    );
  }

  Widget _buildTab(int index, String label, IconData icon) {
    final isActive = _activeTab == index;
    return InkWell(
      onTap: () => setState(() => _activeTab = index),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: isActive ? AppColors.headerTab.withOpacity(0.2) : Colors.transparent,
          border: Border(
            bottom: BorderSide(
              color: isActive ? AppColors.headerTab : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: isActive ? AppColors.headerTab : Colors.white54),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: isActive ? AppColors.headerTab : Colors.white54,
                fontSize: 12,
                fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
              ),
            ),
            if (index == 0 && _materialsToRelocate.isNotEmpty) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.headerTab,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${_materialsToRelocate.length}',
                  style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Tab de materiales a reubicar - Estilo grid igual a Entradas
  Widget _buildMaterialsTab() {
    if (_materialsToRelocate.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.move_to_inbox, size: 64, color: Colors.white.withOpacity(0.15)),
            const SizedBox(height: 12),
            Text(
              tr('no_materials_to_relocate'),
              style: const TextStyle(color: Colors.white38, fontSize: 14),
            ),
            const SizedBox(height: 4),
            Text(
              tr('scan_to_add'),
              style: const TextStyle(color: Colors.white24, fontSize: 12),
            ),
          ],
        ),
      );
    }

    final newLocation = _locationController.text.trim();

    // Definir columnas con flex factors
    final columns = [
      {'header': tr('code'), 'field': 'codigo_material_recibido', 'flex': 3.5},
      {'header': tr('part_number'), 'field': 'numero_parte', 'flex': 3.0},
      {'header': tr('specification'), 'field': 'especificacion', 'flex': 3.5},
      {'header': tr('quantity'), 'field': 'cantidad_actual', 'flex': 2.0},
      {'header': tr('current_location'), 'field': 'ubicacion_salida', 'flex': 2.5},
      {'header': tr('new_location'), 'field': 'nueva_ubicacion', 'flex': 2.5},
      {'header': '', 'field': 'actions', 'flex': 1.0},
    ];

    return Column(
      children: [
        // Header
        Container(
          height: 32,
          decoration: BoxDecoration(
            color: AppColors.gridHeader,
            border: Border(bottom: BorderSide(color: AppColors.border)),
          ),
          child: Row(
            children: columns.map((col) {
              return Expanded(
                flex: ((col['flex'] as double) * 100).round(),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  alignment: Alignment.centerLeft,
                  decoration: BoxDecoration(
                    border: Border(right: BorderSide(color: AppColors.border.withOpacity(0.5))),
                  ),
                  child: Text(
                    col['header'] as String,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        // Data rows
        Expanded(
          child: ListView.builder(
            itemCount: _materialsToRelocate.length,
            itemBuilder: (context, index) {
              final material = _materialsToRelocate[index];
              final isEven = index % 2 == 0;

              return Container(
                height: 28,
                decoration: BoxDecoration(
                  color: isEven 
                      ? AppColors.gridBackground 
                      : AppColors.gridBackground.withOpacity(0.7),
                  border: Border(
                    bottom: BorderSide(color: AppColors.border.withOpacity(0.5)),
                    left: const BorderSide(color: Colors.blue, width: 3),
                  ),
                ),
                child: Row(
                  children: [
                    // Código de almacén
                    Expanded(
                      flex: 350,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        alignment: Alignment.centerLeft,
                        child: Text(
                          material['codigo_material_recibido'] ?? '-',
                          style: const TextStyle(color: Colors.white, fontFamily: 'monospace', fontSize: 11),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    // Número de parte
                    Expanded(
                      flex: 300,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        alignment: Alignment.centerLeft,
                        child: Text(
                          material['numero_parte'] ?? '-',
                          style: const TextStyle(color: Colors.white70, fontSize: 11),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    // Especificación
                    Expanded(
                      flex: 350,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        alignment: Alignment.centerLeft,
                        child: Text(
                          material['especificacion'] ?? '-',
                          style: const TextStyle(color: Colors.white70, fontSize: 11),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    // Cantidad
                    Expanded(
                      flex: 200,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        alignment: Alignment.centerLeft,
                        child: Text(
                          '${material['cantidad_actual'] ?? 0}',
                          style: const TextStyle(color: AppColors.headerTab, fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                    // Ubicación actual
                    Expanded(
                      flex: 250,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        alignment: Alignment.centerLeft,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.orange.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            material['ubicacion_salida'] ?? '-',
                            style: const TextStyle(color: Colors.orange, fontSize: 10, fontWeight: FontWeight.bold),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ),
                    // Nueva ubicación
                    Expanded(
                      flex: 250,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        alignment: Alignment.centerLeft,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.green.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.arrow_forward, size: 12, color: Colors.green),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  newLocation.isNotEmpty ? newLocation : '-',
                                  style: const TextStyle(color: Colors.green, fontSize: 10, fontWeight: FontWeight.bold),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    // Botón eliminar
                    Expanded(
                      flex: 100,
                      child: Center(
                        child: IconButton(
                          onPressed: () => _removeMaterial(index),
                          icon: const Icon(Icons.close, color: Colors.red, size: 16),
                          tooltip: tr('remove'),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        // Footer con conteo
        Container(
          height: 24,
          color: const Color(0xFF2D2D30),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              Text(
                '${_materialsToRelocate.length} ${tr('materials')}',
                style: const TextStyle(color: Colors.white54, fontSize: 11),
              ),
              const Spacer(),
              if (newLocation.isNotEmpty)
                Text(
                  '${tr('destination')}: $newLocation',
                  style: const TextStyle(color: Colors.green, fontSize: 11),
                ),
            ],
          ),
        ),
      ],
    );
  }

  /// Tab de historial de reingresos - Usa el grid con filtros y ordenamiento
  Widget _buildHistoryTab() {
    return ReentryHistoryGrid(
      key: _historyGridKey,
      languageProvider: widget.languageProvider,
    );
  }
}
