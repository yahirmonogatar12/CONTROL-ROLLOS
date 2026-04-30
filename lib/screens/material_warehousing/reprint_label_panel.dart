import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_warehousing_flutter/core/localization/app_translations.dart';
import 'package:material_warehousing_flutter/core/theme/app_colors.dart';
import 'package:material_warehousing_flutter/core/services/api_service.dart';
import 'package:material_warehousing_flutter/core/services/printer_service.dart';
import 'package:material_warehousing_flutter/core/widgets/printer_settings_dialog.dart';

/// Panel para reimprimir etiquetas escaneando el código de almacén
class ReprintLabelPanel extends StatefulWidget {
  final LanguageProvider languageProvider;
  
  const ReprintLabelPanel({
    super.key,
    required this.languageProvider,
  });

  @override
  State<ReprintLabelPanel> createState() => _ReprintLabelPanelState();
}

class _ReprintLabelPanelState extends State<ReprintLabelPanel> {
  final TextEditingController _scanController = TextEditingController();
  final FocusNode _scanFocusNode = FocusNode();
  
  bool _isLoading = false;
  bool _isPrinting = false;
  bool _autoPrint = true; // Activado por defecto para escaneo rápido
  Map<String, dynamic>? _foundMaterial;
  String? _errorMessage;
  
  @override
  void initState() {
    super.initState();
    // Auto-focus en el campo de escaneo
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
  
  /// Buscar material por código escaneado
  Future<void> _searchMaterial() async {
    final code = _scanController.text.trim();
    if (code.isEmpty) return;
    
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _foundMaterial = null;
    });
    
    try {
      final result = await ApiService.getWarehousingByCode(code);
      
      if (result != null) {
        setState(() {
          _foundMaterial = result;
          _isLoading = false;
        });
        
        // Si está habilitada la impresión automática, imprimir inmediatamente
        if (_autoPrint) {
          await _reprintLabel();
        }
      } else {
        setState(() {
          _errorMessage = widget.languageProvider.tr('material_not_found');
          _isLoading = false;
        });
        // Limpiar y regresar focus para el siguiente escaneo
        _scanController.clear();
        _scanFocusNode.requestFocus();
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Error: $e';
        _isLoading = false;
      });
      // Limpiar y regresar focus para el siguiente escaneo
      _scanController.clear();
      _scanFocusNode.requestFocus();
    }
  }
  
  /// Reimprimir la etiqueta del material encontrado
  Future<void> _reprintLabel() async {
    if (_foundMaterial == null) return;
    
    // Verificar impresora
    if (!PrinterService.hasPrinterConfigured) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('⚠ ${widget.languageProvider.tr('configure_printer_first')}'),
          backgroundColor: Colors.orange,
        ),
      );
      PrinterSettingsDialog.show(context);
      return;
    }
    
    setState(() {
      _isPrinting = true;
    });
    
    try {
      // Extraer datos del material
      final codigo = _foundMaterial!['codigo_material_recibido']?.toString() ?? '';
      final fechaRaw = _foundMaterial!['fecha_recibo']?.toString() ?? '';
      String fecha = '';
      
      // Formatear fecha
      if (fechaRaw.isNotEmpty) {
        try {
          final date = DateTime.parse(fechaRaw);
          fecha = '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
        } catch (_) {
          fecha = fechaRaw;
        }
      }
      
      final especificacion = _foundMaterial!['especificacion']?.toString() ?? '';
      final cantidadActual = _foundMaterial!['cantidad_actual']?.toString() ?? '';
      
      // Mostrar indicador
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
                const SizedBox(width: 12),
                Text('${widget.languageProvider.tr('printing_to')}: ${PrinterService.selectedPrinterName}...'),
              ],
            ),
            duration: const Duration(seconds: 2),
          ),
        );
      }
      
      // Imprimir
      final success = await PrinterService.printLabel(
        codigo: codigo,
        fecha: fecha,
        especificacion: especificacion,
        cantidadActual: cantidadActual,
      );
      
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(success 
              ? '✓ ${widget.languageProvider.tr('label_printed_successfully')}' 
              : '✗ ${widget.languageProvider.tr('print_error')}'),
            backgroundColor: success ? Colors.green : Colors.red,
          ),
        );
        
        if (success) {
          // Limpiar y volver a enfocar para el siguiente escaneo
          _scanController.clear();
          setState(() {
            _foundMaterial = null;
          });
          _scanFocusNode.requestFocus();
        }
      }
    } finally {
      if (mounted) {
        setState(() {
          _isPrinting = false;
        });
      }
    }
  }
  
  /// Limpiar y reiniciar
  void _clear() {
    _scanController.clear();
    setState(() {
      _foundMaterial = null;
      _errorMessage = null;
    });
    _scanFocusNode.requestFocus();
  }
  
  String _formatDate(String? dateStr) {
    if (dateStr == null || dateStr.isEmpty) return '-';
    try {
      final date = DateTime.parse(dateStr);
      return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
    } catch (_) {
      return dateStr;
    }
  }

  @override
  Widget build(BuildContext context) {
    final tr = widget.languageProvider.tr;
    
    return Container(
      margin: const EdgeInsets.all(8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.panelBackground,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Título
          Row(
            children: [
              const Icon(Icons.print, color: AppColors.headerTab, size: 24),
              const SizedBox(width: 8),
              Text(
                tr('reprint_label'),
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 24),
              // Checkbox de impresión automática
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Checkbox(
                    value: _autoPrint,
                    onChanged: (v) => setState(() => _autoPrint = v ?? false),
                    side: const BorderSide(color: AppColors.border),
                    activeColor: Colors.green,
                    checkColor: Colors.white,
                  ),
                  GestureDetector(
                    onTap: () => setState(() => _autoPrint = !_autoPrint),
                    child: Text(
                      tr('auto_print'),
                      style: TextStyle(
                        fontSize: 13,
                        color: _autoPrint ? Colors.green : Colors.white70,
                        fontWeight: _autoPrint ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                  ),
                  if (_autoPrint)
                    const Padding(
                      padding: EdgeInsets.only(left: 6),
                      child: Icon(Icons.flash_on, color: Colors.green, size: 16),
                    ),
                ],
              ),
              const Spacer(),
              // Botón de configuración de impresora
              IconButton(
                onPressed: () => PrinterSettingsDialog.show(context),
                icon: const Icon(Icons.settings_outlined, color: Colors.white70),
                tooltip: tr('printer_settings'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          
          // Campo de escaneo
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _scanController,
                  focusNode: _scanFocusNode,
                  style: const TextStyle(color: Colors.white, fontSize: 16),
                  decoration: InputDecoration(
                    labelText: tr('scan_warehousing_code'),
                    labelStyle: const TextStyle(color: Colors.white70),
                    hintText: tr('scan_or_enter_code'),
                    hintStyle: const TextStyle(color: Colors.white30),
                    prefixIcon: const Icon(Icons.qr_code_scanner, color: AppColors.headerTab),
                    filled: true,
                    fillColor: AppColors.fieldBackground,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: AppColors.headerTab, width: 2),
                    ),
                  ),
                  onSubmitted: (_) => _searchMaterial(),
                  inputFormatters: [
                    // Permitir escaneos rápidos
                    FilteringTextInputFormatter.deny(RegExp(r'[\n\r]')),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                onPressed: _isLoading ? null : _searchMaterial,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.headerTab,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                ),
                icon: _isLoading 
                  ? const SizedBox(
                      width: 20, 
                      height: 20, 
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)
                    )
                  : const Icon(Icons.search),
                label: Text(tr('search')),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: _clear,
                icon: const Icon(Icons.clear, color: Colors.white70),
                tooltip: tr('clear'),
              ),
            ],
          ),
          
          const SizedBox(height: 16),
          
          // Error message
          if (_errorMessage != null)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.withValues(alpha: 0.5)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline, color: Colors.red),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _errorMessage!,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
                ],
              ),
            ),
          
          // Material encontrado
          if (_foundMaterial != null) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.green.withValues(alpha: 0.5)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header con ícono de éxito
                  Row(
                    children: [
                      const Icon(Icons.check_circle, color: Colors.green, size: 24),
                      const SizedBox(width: 8),
                      Text(
                        tr('material_found'),
                        style: const TextStyle(
                          color: Colors.green,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  
                  // Datos del material en grid
                  Wrap(
                    spacing: 24,
                    runSpacing: 12,
                    children: [
                      _buildInfoItem(tr('warehousing_code'), _foundMaterial!['codigo_material_recibido']?.toString() ?? '-'),
                      _buildInfoItem(tr('part_number'), _foundMaterial!['numero_parte']?.toString() ?? '-'),
                      _buildInfoItem(tr('warehousing_date'), _formatDate(_foundMaterial!['fecha_recibo']?.toString())),
                      _buildInfoItem(tr('quantity'), _foundMaterial!['cantidad_actual']?.toString() ?? '-'),
                      _buildInfoItem(tr('specification'), _foundMaterial!['especificacion']?.toString() ?? '-'),
                      _buildInfoItem(tr('location'), _foundMaterial!['ubicacion_salida']?.toString() ?? '-'),
                    ],
                  ),
                  
                  const SizedBox(height: 20),
                  
                  // Botón de reimprimir
                  Center(
                    child: ElevatedButton.icon(
                      onPressed: _isPrinting ? null : _reprintLabel,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                      ),
                      icon: _isPrinting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.print, size: 24),
                      label: Text(
                        tr('reprint_label'),
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
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
  
  Widget _buildInfoItem(String label, String value) {
    return SizedBox(
      width: 200,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Colors.white54,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
