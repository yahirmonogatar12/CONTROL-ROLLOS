import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:material_warehousing_flutter/core/theme/app_colors.dart';
import 'package:material_warehousing_flutter/core/services/printer_service.dart';

class PrinterSettingsDialog extends StatefulWidget {
  const PrinterSettingsDialog({super.key});

  static Future<void> show(BuildContext context) async {
    await showDialog(
      context: context,
      builder: (context) => const PrinterSettingsDialog(),
    );
  }

  @override
  State<PrinterSettingsDialog> createState() => _PrinterSettingsDialogState();
}

class _PrinterSettingsDialogState extends State<PrinterSettingsDialog> {
  List<Printer> _printers = [];
  bool _isLoading = true;
  String? _selectedPrinterName;
  String? _errorMessage;
  
  // Para configuración de red
  final TextEditingController _ipController = TextEditingController();
  final TextEditingController _portController = TextEditingController();
  bool _useNetworkPrinting = false;

  @override
  void initState() {
    super.initState();
    _selectedPrinterName = PrinterService.selectedPrinterName;
    _ipController.text = PrinterService.printerIp ?? '';
    _portController.text = PrinterService.printerPort.toString();
    _useNetworkPrinting = PrinterService.hasNetworkConfig;
    _loadPrinters();
  }
  
  @override
  void dispose() {
    _ipController.dispose();
    _portController.dispose();
    super.dispose();
  }

  Future<void> _loadPrinters() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final printers = await PrinterService.getAvailablePrinters();
      if (mounted) {
        setState(() {
          _printers = printers;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Error al cargar impresoras: $e';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _savePrinter() async {
    if (_selectedPrinterName == null) return;

    final printer = _printers.firstWhere(
      (p) => p.name == _selectedPrinterName,
    );

    // Guardar configuración de red si está habilitada
    final ip = (_useNetworkPrinting && _ipController.text.trim().isNotEmpty)
        ? _ipController.text.trim()
        : '';
    final port = int.tryParse(_portController.text) ?? 9100;

    if (ip.isNotEmpty) {
      await PrinterService.setSelectedPrinter(printer, ip: ip, port: port);
    } else {
      await PrinterService.setSelectedPrinter(printer);
    }

    final serverError = await PrinterService.syncServerPrinterConfig(
      printerName: printer.name,
      printerIp: ip,
      printerPort: port,
    );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            serverError == null
                ? 'Impresora "${printer.name}" guardada y servidor actualizado'
                : 'Impresora guardada, pero no se pudo actualizar el servidor: $serverError',
          ),
          backgroundColor: serverError == null ? Colors.green : Colors.orange,
        ),
      );
      Navigator.of(context).pop();
    }
  }
  
  Future<void> _testConnection() async {
    if (_ipController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ingrese una dirección IP'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    
    setState(() => _isLoading = true);
    
    final port = int.tryParse(_portController.text) ?? 9100;
    final success = await PrinterService.printZPLToNetwork(
      '^XA^FO50,50^A0N,50,50^FDTest OK^FS^XZ', // Etiqueta de prueba simple
      _ipController.text,
      port: port,
    );
    
    setState(() => _isLoading = false);
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success ? '✓ Conexión exitosa' : '✗ Error de conexión'),
          backgroundColor: success ? Colors.green : Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.panelBackground,
      title: Row(
        children: [
          const Icon(Icons.print, color: Colors.white70),
          const SizedBox(width: 8),
          const Text(
            'Configuración de Impresora ZPL',
            style: TextStyle(color: Colors.white, fontSize: 18),
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white70),
            onPressed: _loadPrinters,
            tooltip: 'Recargar impresoras',
          ),
        ],
      ),
      content: SizedBox(
        width: 550,
        height: 500,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Impresora actual
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.fieldBackground,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                children: [
                  Icon(
                    PrinterService.hasPrinterConfigured
                        ? Icons.check_circle
                        : Icons.warning,
                    color: PrinterService.hasPrinterConfigured
                        ? Colors.green
                        : Colors.orange,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Impresora Actual:',
                          style: TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                        Text(
                          PrinterService.hasPrinterConfigured
                              ? PrinterService.selectedPrinterName!
                              : 'No configurada',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (PrinterService.hasNetworkConfig)
                          Text(
                            'IP: ${PrinterService.printerIp}:${PrinterService.printerPort}',
                            style: const TextStyle(color: Colors.blue, fontSize: 11),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 16),
            
            const Text(
              'Seleccione una impresora:',
              style: TextStyle(color: Colors.white70, fontSize: 14),
            ),
            
            const SizedBox(height: 8),
            
            // Lista de impresoras
            Expanded(
              flex: 2,
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.fieldBackground,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: AppColors.border),
                ),
                child: _isLoading
                    ? const Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CircularProgressIndicator(),
                            SizedBox(height: 16),
                            Text(
                              'Buscando impresoras...',
                              style: TextStyle(color: Colors.white70),
                            ),
                          ],
                        ),
                      )
                    : _errorMessage != null
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.error, color: Colors.red, size: 48),
                                const SizedBox(height: 8),
                                Text(
                                  _errorMessage!,
                                  style: const TextStyle(color: Colors.red),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          )
                        : _printers.isEmpty
                            ? const Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.print_disabled, color: Colors.white54, size: 48),
                                    SizedBox(height: 8),
                                    Text(
                                      'No se encontraron impresoras',
                                      style: TextStyle(color: Colors.white54),
                                    ),
                                  ],
                                ),
                              )
                            : ListView.builder(
                                itemCount: _printers.length,
                                itemBuilder: (context, index) {
                                  final printer = _printers[index];
                                  final isSelected = printer.name == _selectedPrinterName;
                                  final isCurrentConfig = printer.name == PrinterService.selectedPrinterName;
                                  
                                  return Container(
                                    margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: isSelected
                                          ? Colors.blue.withOpacity(0.3)
                                          : Colors.transparent,
                                      borderRadius: BorderRadius.circular(4),
                                      border: isSelected
                                          ? Border.all(color: Colors.blue)
                                          : null,
                                    ),
                                    child: ListTile(
                                      dense: true,
                                      leading: Icon(
                                        printer.isDefault ? Icons.star : Icons.print,
                                        color: printer.isDefault ? Colors.amber : Colors.white54,
                                        size: 20,
                                      ),
                                      title: Text(
                                        printer.name,
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 13,
                                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                        ),
                                      ),
                                      subtitle: Row(
                                        children: [
                                          if (printer.isDefault)
                                            Container(
                                              margin: const EdgeInsets.only(right: 8),
                                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: Colors.amber.withOpacity(0.2),
                                                borderRadius: BorderRadius.circular(4),
                                              ),
                                              child: const Text(
                                                'Por defecto',
                                                style: TextStyle(color: Colors.amber, fontSize: 10),
                                              ),
                                            ),
                                          if (isCurrentConfig)
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: Colors.green.withOpacity(0.2),
                                                borderRadius: BorderRadius.circular(4),
                                              ),
                                              child: const Text(
                                                'Configurada',
                                                style: TextStyle(color: Colors.green, fontSize: 10),
                                              ),
                                            ),
                                        ],
                                      ),
                                      trailing: isSelected
                                          ? const Icon(Icons.check_circle, color: Colors.blue, size: 20)
                                          : null,
                                      onTap: () {
                                        setState(() {
                                          _selectedPrinterName = printer.name;
                                        });
                                      },
                                    ),
                                  );
                                },
                              ),
              ),
            ),
            
            const SizedBox(height: 16),
            
            // Configuración de red (para impresoras Zebra en red)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.1),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: Colors.orange.withOpacity(0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Checkbox(
                        value: _useNetworkPrinting,
                        onChanged: (value) {
                          setState(() {
                            _useNetworkPrinting = value ?? false;
                          });
                        },
                        activeColor: Colors.orange,
                      ),
                      const Text(
                        'Usar impresión por red (Zebra)',
                        style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  if (_useNetworkPrinting) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: TextField(
                            controller: _ipController,
                            style: const TextStyle(color: Colors.white, fontSize: 13),
                            decoration: InputDecoration(
                              isDense: true,
                              labelText: 'IP de la impresora',
                              labelStyle: const TextStyle(color: Colors.white70, fontSize: 12),
                              hintText: '192.168.1.100',
                              hintStyle: const TextStyle(color: Colors.white38, fontSize: 12),
                              filled: true,
                              fillColor: AppColors.fieldBackground,
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(4)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 1,
                          child: TextField(
                            controller: _portController,
                            style: const TextStyle(color: Colors.white, fontSize: 13),
                            decoration: InputDecoration(
                              isDense: true,
                              labelText: 'Puerto',
                              labelStyle: const TextStyle(color: Colors.white70, fontSize: 12),
                              filled: true,
                              fillColor: AppColors.fieldBackground,
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(4)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: _testConnection,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.orange,
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                          ),
                          child: const Text('Probar', style: TextStyle(fontSize: 12)),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            
            const SizedBox(height: 12),
            
            // Nota informativa
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.1),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: Colors.blue.withOpacity(0.3)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.blue, size: 16),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Para impresoras Zebra en red, habilite la opción de red e ingrese la IP.',
                      style: TextStyle(color: Colors.blue, fontSize: 11),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel', style: TextStyle(color: Colors.white70)),
        ),
        ElevatedButton.icon(
          onPressed: _selectedPrinterName != null ? _savePrinter : null,
          icon: const Icon(Icons.save),
          label: const Text('Save'),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.buttonSave,
            disabledBackgroundColor: Colors.grey,
          ),
        ),
      ],
    );
  }
}
