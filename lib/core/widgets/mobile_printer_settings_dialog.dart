import 'package:flutter/material.dart';
import 'package:bluetooth_classic/models/device.dart';
import 'package:material_warehousing_flutter/core/localization/app_translations.dart';
import 'package:material_warehousing_flutter/core/services/mobile_printer_service.dart';
import 'package:material_warehousing_flutter/core/config/server_config.dart';
import 'package:material_warehousing_flutter/core/config/print_server_config.dart';
import 'package:material_warehousing_flutter/core/theme/app_colors.dart';

/// Diálogo de configuración de impresora para móvil
/// Permite elegir entre imprimir vía Backend (servidor) o Bluetooth directo
class MobilePrinterSettingsDialog extends StatefulWidget {
  final LanguageProvider languageProvider;
  
  const MobilePrinterSettingsDialog({
    super.key,
    required this.languageProvider,
  });

  static Future<void> show(BuildContext context, LanguageProvider languageProvider) async {
    await showDialog(
      context: context,
      builder: (context) => MobilePrinterSettingsDialog(languageProvider: languageProvider),
    );
  }

  @override
  State<MobilePrinterSettingsDialog> createState() => _MobilePrinterSettingsDialogState();
}

class _MobilePrinterSettingsDialogState extends State<MobilePrinterSettingsDialog> {
  PrinterMode _selectedMode = MobilePrinterService.currentMode;
  bool _isScanning = false;
  bool _isLoadingBonded = false;
  bool _isTesting = false;
  String? _testResult;
  bool? _testSuccess;
  List<Device> _bondedDevices = [];  // Dispositivos ya vinculados
  List<Device> _foundDevices = [];   // Dispositivos encontrados en escaneo
  String? _selectedBluetoothId;
  String? _selectedBluetoothName;
  
  // Print server configuration
  bool _useSeparatePrintServer = PrintServerConfig.isEnabled;
  final TextEditingController _printServerIpController = TextEditingController();
  final TextEditingController _printServerPortController = TextEditingController();
  bool _printServerHttps = PrintServerConfig.useHttps;
  
  String tr(String key) => widget.languageProvider.tr(key);

  @override
  void initState() {
    super.initState();
    _selectedBluetoothId = MobilePrinterService.bluetoothDeviceId;
    _selectedBluetoothName = MobilePrinterService.bluetoothDeviceName;
    
    // Load print server config
    _printServerIpController.text = PrintServerConfig.serverIp ?? '';
    _printServerPortController.text = PrintServerConfig.serverPort.toString();
    
    // Cargar dispositivos vinculados automáticamente si está en modo Bluetooth
    if (_selectedMode == PrinterMode.bluetooth) {
      _loadBondedDevices();
    }
  }
  
  @override
  void dispose() {
    _printServerIpController.dispose();
    _printServerPortController.dispose();
    super.dispose();
  }

  /// Cargar dispositivos Bluetooth ya vinculados (instantáneo)
  Future<void> _loadBondedDevices() async {
    setState(() {
      _isLoadingBonded = true;
      _testResult = null;
      _testSuccess = null;
    });

    try {
      // Obtener TODOS los dispositivos vinculados (sin filtrar)
      final devices = await MobilePrinterService.getBondedPrinters(filterZebraOnly: false);
      setState(() {
        _bondedDevices = devices;
        _isLoadingBonded = false;
      });
      
      if (devices.isEmpty) {
        setState(() {
          _testResult = 'No hay dispositivos Bluetooth vinculados. Vincule primero en Configuración de Bluetooth de Android.';
          _testSuccess = false;
        });
      } else {
        setState(() {
          _testResult = 'Encontrados ${devices.length} dispositivos vinculados';
          _testSuccess = true;
        });
      }
    } catch (e) {
      setState(() {
        _isLoadingBonded = false;
        _testResult = e.toString();
        _testSuccess = false;
      });
    }
  }

  /// Escanear nuevos dispositivos Bluetooth (10 segundos)
  Future<void> _scanBluetooth() async {
    setState(() {
      _isScanning = true;
      _foundDevices = [];
      _testResult = null;
      _testSuccess = null;
    });

    try {
      final devices = await MobilePrinterService.scanBluetoothPrinters(includeNewDevices: true);
      setState(() {
        // Filtrar los que ya están en bondedDevices
        _foundDevices = devices.where((d) => 
          !_bondedDevices.any((b) => b.address == d.address)
        ).toList();
        // Actualizar bonded también por si encontró nuevos vinculados
        _bondedDevices = devices.where((d) => 
          _bondedDevices.any((b) => b.address == d.address) || 
          devices.any((bd) => bd.address == d.address)
        ).toList();
        _isScanning = false;
      });
      
      if (devices.isEmpty) {
        setState(() {
          _testResult = tr('no_zebra_printers');
          _testSuccess = false;
        });
      }
    } catch (e) {
      setState(() {
        _isScanning = false;
        _testResult = e.toString();
        _testSuccess = false;
      });
    }
  }

  Future<void> _testConnection() async {
    setState(() {
      _isTesting = true;
      _testResult = null;
      _testSuccess = null;
    });

    try {
      final result = await MobilePrinterService.testConnection();
      setState(() {
        _isTesting = false;
        _testSuccess = result.success;
        _testResult = result.success ? tr('connection_success') : result.error;
      });
    } catch (e) {
      setState(() {
        _isTesting = false;
        _testSuccess = false;
        _testResult = e.toString();
      });
    }
  }

  Future<void> _selectBluetoothDevice(Device device) async {
    setState(() {
      _selectedBluetoothId = device.address;
      _selectedBluetoothName = (device.name ?? '').isNotEmpty 
          ? device.name! 
          : device.address;
    });
  }

  Future<void> _selectRecentPrinter(BluetoothPrinterInfo printer) async {
    setState(() {
      _selectedBluetoothId = printer.id;
      _selectedBluetoothName = printer.name;
    });
  }

  Future<void> _save() async {
    // Guardar modo
    await MobilePrinterService.setMode(_selectedMode);
    
    // Si es Bluetooth, guardar dispositivo seleccionado
    if (_selectedMode == PrinterMode.bluetooth && _selectedBluetoothId != null) {
      await MobilePrinterService.setBluetoothDevice(
        _selectedBluetoothId!,
        _selectedBluetoothName ?? 'Unknown',
      );
    }
    
    // Guardar configuración de Print Server si está en modo backend
    if (_selectedMode == PrinterMode.backend && _useSeparatePrintServer) {
      final ip = _printServerIpController.text.trim();
      final port = int.tryParse(_printServerPortController.text) ?? 3010;
      
      if (ip.isNotEmpty) {
        await PrintServerConfig.setConfig(
          ip: ip,
          port: port,
          useHttps: _printServerHttps,
          enabled: true,
        );
      }
    } else if (_selectedMode == PrinterMode.backend && !_useSeparatePrintServer) {
      // Disable separate print server, use main API server
      await PrintServerConfig.setEnabled(false);
    }
    
    if (mounted) {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF1A1E2C),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: MediaQuery.of(context).size.width * 0.9,
        constraints: const BoxConstraints(maxHeight: 600),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                color: Color(0xFF252A3C),
                borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Row(
                children: [
                  Icon(
                    MobilePrinterService.isConfigured ? Icons.print : Icons.print_disabled,
                    color: MobilePrinterService.isConfigured ? Colors.green : Colors.orange,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      tr('printer_config'),
                      style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white54),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Selector de modo
                    Text(tr('print_method'), style: const TextStyle(color: Colors.white70, fontSize: 14)),
                    const SizedBox(height: 8),
                    Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF252A3C),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: _buildModeButton(
                              tr('via_server'),
                              Icons.cloud,
                              PrinterMode.backend,
                            ),
                          ),
                          Expanded(
                            child: _buildModeButton(
                              tr('bluetooth'),
                              Icons.bluetooth,
                              PrinterMode.bluetooth,
                            ),
                          ),
                        ],
                      ),
                    ),
                    
                    const SizedBox(height: 24),
                    
                    // Contenido según modo
                    if (_selectedMode == PrinterMode.backend)
                      _buildBackendSection()
                    else
                      _buildBluetoothSection(),
                    
                    // Resultado de test
                    if (_testResult != null) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: (_testSuccess == true ? Colors.green : Colors.red).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: (_testSuccess == true ? Colors.green : Colors.red).withOpacity(0.3),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              _testSuccess == true ? Icons.check_circle : Icons.error,
                              color: _testSuccess == true ? Colors.green : Colors.red,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _testResult!,
                                style: TextStyle(
                                  color: _testSuccess == true ? Colors.green : Colors.red,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            
            // Botones de acción
            Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                color: Color(0xFF252A3C),
                borderRadius: BorderRadius.vertical(bottom: Radius.circular(16)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _isTesting ? null : _testConnection,
                      icon: _isTesting 
                          ? const SizedBox(
                              width: 16, height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white54),
                            )
                          : const Icon(Icons.wifi_tethering, size: 18),
                      label: Text(tr('test_btn')),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white70,
                        side: const BorderSide(color: Colors.white24),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _save,
                      icon: const Icon(Icons.save, size: 18),
                      label: Text(tr('save_btn')),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.headerTab,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModeButton(String label, IconData icon, PrinterMode mode) {
    final isSelected = _selectedMode == mode;
    return InkWell(
      onTap: () {
        setState(() => _selectedMode = mode);
        // Si cambia a Bluetooth, cargar dispositivos vinculados
        if (mode == PrinterMode.bluetooth && _bondedDevices.isEmpty && !_isLoadingBonded) {
          _loadBondedDevices();
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.headerTab : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: isSelected ? Colors.white : Colors.white54, size: 20),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.white : Colors.white54,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBackendSection() {
    final server = ServerConfig.activeServer;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(tr('connected_server'), style: const TextStyle(color: Colors.white70, fontSize: 14)),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF252A3C),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(
                server != null ? Icons.cloud_done : Icons.cloud_off,
                color: server != null ? Colors.green : Colors.red,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      server?.name ?? tr('not_configured'),
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                    if (server != null)
                      Text(
                        '${server.protocol}://${server.ip}${server.port != 443 && server.port != 80 ? ":${server.port}" : ""}',
                        style: const TextStyle(color: Colors.white54, fontSize: 12),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        
        const SizedBox(height: 16),
        
        // Opción de servidor de impresión separado
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFF252A3C),
            borderRadius: BorderRadius.circular(8),
          ),
          child: SwitchListTile(
            title: Text(
              tr('use_separate_print_server'),
              style: const TextStyle(color: Colors.white, fontSize: 14),
            ),
            subtitle: Text(
              tr('use_separate_print_server_desc'),
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
            value: _useSeparatePrintServer,
            onChanged: (value) {
              setState(() {
                _useSeparatePrintServer = value;
              });
            },
            activeColor: AppColors.headerTab,
          ),
        ),
        
        // Configuración del servidor de impresión
        if (_useSeparatePrintServer) ...[
          const SizedBox(height: 16),
          Text(tr('print_server_config'), style: const TextStyle(color: Colors.white70, fontSize: 14)),
          const SizedBox(height: 8),
          
          // IP del servidor de impresión
          TextField(
            controller: _printServerIpController,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              labelText: tr('print_server_ip'),
              labelStyle: const TextStyle(color: Colors.white54),
              hintText: '192.168.1.100',
              hintStyle: const TextStyle(color: Colors.white24),
              filled: true,
              fillColor: const Color(0xFF252A3C),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide.none,
              ),
              prefixIcon: const Icon(Icons.computer, color: Colors.white54),
            ),
          ),
          
          const SizedBox(height: 12),
          
          // Puerto del servidor de impresión
          Row(
            children: [
              Expanded(
                flex: 2,
                child: TextField(
                  controller: _printServerPortController,
                  style: const TextStyle(color: Colors.white),
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: tr('port'),
                    labelStyle: const TextStyle(color: Colors.white54),
                    hintText: '3000',
                    hintStyle: const TextStyle(color: Colors.white24),
                    filled: true,
                    fillColor: const Color(0xFF252A3C),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 3,
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF252A3C),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: SwitchListTile(
                    title: const Text(
                      'HTTPS',
                      style: TextStyle(color: Colors.white, fontSize: 14),
                    ),
                    value: _printServerHttps,
                    onChanged: (value) {
                      setState(() {
                        _printServerHttps = value;
                      });
                    },
                    activeColor: AppColors.headerTab,
                    dense: true,
                  ),
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 8),
          Text(
            tr('print_server_note'),
            style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 11),
          ),
        ] else ...[
          const SizedBox(height: 12),
          Text(
            tr('printer_config_server_note'),
            style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12),
          ),
        ],
      ],
    );
  }

  Widget _buildBluetoothSection() {
    final recentPrinters = MobilePrinterService.recentPrinters;
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Impresora seleccionada actual
        if (_selectedBluetoothId != null) ...[
          Text(tr('selected_printer'), style: const TextStyle(color: Colors.white70, fontSize: 14)),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.green.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.green.withOpacity(0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.bluetooth_connected, color: Colors.green),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _selectedBluetoothName ?? _selectedBluetoothId!,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white54, size: 20),
                  onPressed: () {
                    setState(() {
                      _selectedBluetoothId = null;
                      _selectedBluetoothName = null;
                    });
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
        
        // DISPOSITIVOS VINCULADOS (bonded) - Se cargan automáticamente
        if (_isLoadingBonded)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                children: [
                  CircularProgressIndicator(strokeWidth: 2, color: Colors.white54),
                  SizedBox(height: 8),
                  Text('Cargando impresoras vinculadas...', style: TextStyle(color: Colors.white54, fontSize: 12)),
                ],
              ),
            ),
          )
        else if (_bondedDevices.isNotEmpty) ...[
          Row(
            children: [
              const Icon(Icons.link, color: Colors.green, size: 16),
              const SizedBox(width: 8),
              const Text('Impresoras vinculadas', style: TextStyle(color: Colors.green, fontSize: 14, fontWeight: FontWeight.bold)),
              const Spacer(),
              Text('${_bondedDevices.length}', style: const TextStyle(color: Colors.white54, fontSize: 12)),
            ],
          ),
          const SizedBox(height: 8),
          ..._bondedDevices.map((device) => _buildBluetoothDeviceTile(
            (device.name ?? '').isNotEmpty ? device.name! : device.address,
            device.address,
            isBonded: true,
            onTap: () => _selectBluetoothDevice(device),
          )),
          const SizedBox(height: 16),
        ],
        
        // Impresoras recientes (si no están en bonded)
        if (recentPrinters.isNotEmpty && _bondedDevices.isEmpty) ...[
          Text(tr('recent_printers'), style: const TextStyle(color: Colors.white70, fontSize: 14)),
          const SizedBox(height: 8),
          ...recentPrinters.map((printer) => _buildBluetoothDeviceTile(
            printer.name,
            printer.id,
            isRecent: true,
            onTap: () => _selectRecentPrinter(printer),
          )),
          const SizedBox(height: 16),
        ],
        
        // Botón buscar nuevos dispositivos
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: (_isScanning || _isLoadingBonded) ? null : _scanBluetooth,
            icon: _isScanning 
                ? const SizedBox(
                    width: 16, height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white54),
                  )
                : const Icon(Icons.search),
            label: Text(_isScanning ? tr('searching') : 'Buscar nuevos dispositivos'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white70,
              side: const BorderSide(color: Colors.white24),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ),
        
        // Si no hay dispositivos vinculados, mostrar mensaje de ayuda
        if (_bondedDevices.isEmpty && !_isLoadingBonded && !_isScanning) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.orange.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.orange.withOpacity(0.3)),
            ),
            child: const Row(
              children: [
                Icon(Icons.info_outline, color: Colors.orange, size: 20),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Para usar Bluetooth, primero vincule la impresora desde Configuración > Bluetooth en su dispositivo Android.',
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        ],
        
        // Dispositivos encontrados en escaneo (no vinculados)
        if (_foundDevices.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(tr('devices_found'), style: const TextStyle(color: Colors.white70, fontSize: 14)),
          const SizedBox(height: 8),
          ..._foundDevices.map((device) => _buildBluetoothDeviceTile(
            (device.name ?? '').isNotEmpty ? device.name! : device.address,
            device.address,
            onTap: () => _selectBluetoothDevice(device),
          )),
        ],
      ],
    );
  }

  Widget _buildBluetoothDeviceTile(String name, String id, {bool isRecent = false, bool isBonded = false, VoidCallback? onTap}) {
    final isSelected = _selectedBluetoothId == id;
    return InkWell(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected 
              ? AppColors.headerTab.withOpacity(0.2)
              : const Color(0xFF252A3C),
          borderRadius: BorderRadius.circular(8),
          border: isSelected 
              ? Border.all(color: AppColors.headerTab)
              : null,
        ),
        child: Row(
          children: [
            Icon(
              isBonded ? Icons.bluetooth_connected : (isRecent ? Icons.history : Icons.bluetooth),
              color: isSelected ? AppColors.headerTab : (isBonded ? Colors.green : Colors.white54),
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                  Row(
                    children: [
                      Text(
                        id,
                        style: const TextStyle(color: Colors.white38, fontSize: 10),
                      ),
                      if (isBonded) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.green.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            'Vinculado',
                            style: TextStyle(color: Colors.green, fontSize: 9),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            if (isSelected)
              const Icon(Icons.check_circle, color: AppColors.headerTab, size: 20),
          ],
        ),
      ),
    );
  }
}
