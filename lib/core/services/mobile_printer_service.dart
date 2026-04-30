import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:bluetooth_classic/bluetooth_classic.dart';
import 'package:bluetooth_classic/models/device.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vibration/vibration.dart';
import 'package:material_warehousing_flutter/core/config/server_config.dart';
import 'package:material_warehousing_flutter/core/config/print_server_config.dart';

/// Modos de impresión disponibles
enum PrinterMode { backend, bluetooth }

/// Información de una impresora Bluetooth
class BluetoothPrinterInfo {
  final String id;
  final String name;
  final DateTime lastUsed;

  BluetoothPrinterInfo({
    required this.id,
    required this.name,
    required this.lastUsed,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'lastUsed': lastUsed.toIso8601String(),
  };

  factory BluetoothPrinterInfo.fromJson(Map<String, dynamic> json) {
    return BluetoothPrinterInfo(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      lastUsed: DateTime.tryParse(json['lastUsed'] ?? '') ?? DateTime.now(),
    );
  }
}

/// Resultado de una operación de impresión
class PrintResult {
  final bool success;
  final String? error;

  PrintResult({required this.success, this.error});
}

/// Servicio de impresión móvil con soporte para Backend y Bluetooth
class MobilePrinterService {
  static const String _modeKey = 'mobile_printer_mode';
  static const String _bluetoothDeviceIdKey = 'mobile_printer_bt_id';
  static const String _bluetoothDeviceNameKey = 'mobile_printer_bt_name';
  static const String _recentPrintersKey = 'mobile_printer_recent';

  static PrinterMode _currentMode = PrinterMode.backend;
  static String? _bluetoothDeviceId;
  static String? _bluetoothDeviceName;
  static List<BluetoothPrinterInfo> _recentPrinters = [];
  static final BluetoothClassic _bluetoothClassic = BluetoothClassic();
  static bool _isConnected = false;

  // Getters
  static PrinterMode get currentMode => _currentMode;
  static String? get currentPrinterName => _currentMode == PrinterMode.bluetooth 
      ? _bluetoothDeviceName 
      : 'Servidor: ${ServerConfig.activeServer?.name ?? "No configurado"}';
  static bool get isConfigured => _currentMode == PrinterMode.backend 
      ? ServerConfig.activeServer != null 
      : _bluetoothDeviceId != null;
  static List<BluetoothPrinterInfo> get recentPrinters => _recentPrinters;
  static String? get bluetoothDeviceId => _bluetoothDeviceId;
  static String? get bluetoothDeviceName => _bluetoothDeviceName;

  /// Inicializar el servicio cargando configuración guardada
  static Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // Cargar modo
      final modeStr = prefs.getString(_modeKey);
      _currentMode = modeStr == 'bluetooth' ? PrinterMode.bluetooth : PrinterMode.backend;
      
      // Cargar dispositivo Bluetooth
      _bluetoothDeviceId = prefs.getString(_bluetoothDeviceIdKey);
      _bluetoothDeviceName = prefs.getString(_bluetoothDeviceNameKey);
      
      // Cargar historial de impresoras recientes
      final recentJson = prefs.getString(_recentPrintersKey);
      if (recentJson != null) {
        final List<dynamic> list = json.decode(recentJson);
        _recentPrinters = list
            .map((e) => BluetoothPrinterInfo.fromJson(e))
            .toList()
          ..sort((a, b) => b.lastUsed.compareTo(a.lastUsed));
        // Limitar a 5
        if (_recentPrinters.length > 5) {
          _recentPrinters = _recentPrinters.take(5).toList();
        }
      }
      
      print('MobilePrinterService initialized: mode=$_currentMode, btDevice=$_bluetoothDeviceName');
    } catch (e) {
      print('Error initializing MobilePrinterService: $e');
    }
  }

  /// Cambiar modo de impresión
  static Future<void> setMode(PrinterMode mode) async {
    _currentMode = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_modeKey, mode == PrinterMode.bluetooth ? 'bluetooth' : 'backend');
  }

  /// Configurar dispositivo Bluetooth
  static Future<void> setBluetoothDevice(String id, String name) async {
    _bluetoothDeviceId = id;
    _bluetoothDeviceName = name;
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_bluetoothDeviceIdKey, id);
    await prefs.setString(_bluetoothDeviceNameKey, name);
    
    // Agregar a recientes
    await _addToRecentPrinters(id, name);
  }

  /// Agregar impresora al historial de recientes
  static Future<void> _addToRecentPrinters(String id, String name) async {
    // Remover si ya existe
    _recentPrinters.removeWhere((p) => p.id == id);
    
    // Agregar al inicio
    _recentPrinters.insert(0, BluetoothPrinterInfo(
      id: id,
      name: name,
      lastUsed: DateTime.now(),
    ));
    
    // Limitar a 5
    if (_recentPrinters.length > 5) {
      _recentPrinters = _recentPrinters.take(5).toList();
    }
    
    // Guardar
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_recentPrintersKey, json.encode(_recentPrinters.map((p) => p.toJson()).toList()));
  }

  /// Obtener dispositivos Bluetooth ya vinculados (bonded/paired)
  /// Esto obtiene las impresoras que ya fueron emparejadas previamente en Android
  /// Usa Bluetooth Classic (SPP) que es lo que usan las impresoras Zebra
  static Future<List<Device>> getBondedPrinters({bool filterZebraOnly = false}) async {
    final List<Device> printers = [];
    
    try {
      // Inicializar permisos
      await _bluetoothClassic.initPermissions();
      
      // Obtener dispositivos ya vinculados (bonded) - Bluetooth Classic
      final bondedDevices = await _bluetoothClassic.getPairedDevices();
      print('Total bonded devices found: ${bondedDevices.length}');
      
      for (final device in bondedDevices) {
        final name = device.name ?? '';
        final nameUpper = name.toUpperCase();
        final deviceId = device.address;
        
        print('Bonded device: name="$name", address=$deviceId');
        
        if (filterZebraOnly) {
          // Filtrar solo impresoras Zebra
          if (nameUpper.contains('ZEBRA') || 
              nameUpper.contains('ZQ') || 
              nameUpper.contains('ZD') || 
              nameUpper.contains('IMZ') ||
              nameUpper.contains('ZT') ||
              nameUpper.contains('QL') ||
              nameUpper.contains('PRINTER') ||
              nameUpper.contains('PRINT')) {
            printers.add(device);
            print('  -> Added as Zebra printer');
          }
        } else {
          // Agregar TODOS los dispositivos vinculados
          printers.add(device);
        }
      }
      
      print('Returning ${printers.length} bonded printers (filterZebraOnly=$filterZebraOnly)');
    } on MissingPluginException catch (e) {
      print('Bluetooth plugin not available: $e');
      throw Exception('Bluetooth no disponible en este dispositivo');
    } catch (e) {
      print('Error getting bonded devices: $e');
      rethrow;
    }
    
    return printers;
  }

  /// Escanear impresoras Bluetooth (obtiene dispositivos vinculados + discovery)
  /// Para Bluetooth Classic, el escaneo requiere permisos de ubicación
  static Future<List<Device>> scanBluetoothPrinters({bool includeNewDevices = true}) async {
    final List<Device> printers = [];
    
    try {
      // Inicializar permisos
      await _bluetoothClassic.initPermissions();

      // PRIMERO: Obtener dispositivos ya vinculados (bonded)
      final bondedDevices = await _bluetoothClassic.getPairedDevices();
      for (final device in bondedDevices) {
        final name = (device.name ?? '').toUpperCase();
        // Filtrar solo impresoras Zebra
        if (name.contains('ZEBRA') || 
            name.contains('ZQ') || 
            name.contains('ZD') || 
            name.contains('IMZ') ||
            name.contains('ZT') ||
            name.contains('QL')) {
          if (!printers.any((p) => p.address == device.address)) {
            printers.add(device);
            print('Found bonded printer: ${device.name}');
          }
        }
      }

      // Si no queremos escanear nuevos dispositivos, retornar solo los vinculados
      if (!includeNewDevices) {
        return printers;
      }

      // SEGUNDO: Discovery de nuevos dispositivos (10 segundos)
      // Nota: Esto requiere permisos de ubicación en Android
      try {
        final discoveredDevices = <Device>[];
        _bluetoothClassic.onDeviceDiscovered().listen((device) {
          final name = (device.name ?? '').toUpperCase();
          if (name.contains('ZEBRA') || 
              name.contains('ZQ') || 
              name.contains('ZD') || 
              name.contains('IMZ') ||
              name.contains('ZT') ||
              name.contains('QL')) {
            if (!printers.any((p) => p.address == device.address) &&
                !discoveredDevices.any((p) => p.address == device.address)) {
              discoveredDevices.add(device);
              print('Found new printer: ${device.name}');
            }
          }
        });
        
        await _bluetoothClassic.startScan();
        await Future.delayed(const Duration(seconds: 10));
        await _bluetoothClassic.stopScan();
        
        printers.addAll(discoveredDevices);
      } catch (e) {
        // Timeout o error en discovery, continuar con lo que tenemos
        print('Discovery ended: $e');
      }
      
    } on MissingPluginException catch (e) {
      print('Bluetooth plugin not available (emulator?): $e');
      throw Exception('Bluetooth no disponible en este dispositivo');
    } catch (e) {
      print('Error scanning Bluetooth: $e');
      rethrow;
    }
    
    return printers;
  }

  /// Imprimir etiqueta ZPL
  static Future<PrintResult> printLabel(String zpl) async {
    try {
      PrintResult result;
      
      if (_currentMode == PrinterMode.backend) {
        result = await _printViaBackend(zpl);
      } else {
        result = await _printViaBluetooth(zpl);
      }
      
      // Vibración corta al éxito
      if (result.success) {
        if (await Vibration.hasVibrator() ?? false) {
          Vibration.vibrate(duration: 100);
        }
      }
      
      return result;
    } catch (e) {
      return PrintResult(success: false, error: e.toString());
    }
  }

  /// Imprimir vía Backend (proxy a impresora de red)
  /// Si PrintServerConfig está habilitado, usa el servidor de impresión separado
  /// De lo contrario, usa el servidor principal (ServerConfig)
  static Future<PrintResult> _printViaBackend(String zpl) async {
    try {
      String url;
      
      // Determinar qué servidor usar para impresión
      if (PrintServerConfig.isEnabled && PrintServerConfig.isConfigured) {
        // Usar servidor de impresión separado (PC local)
        url = '${PrintServerConfig.baseUrl}/print/label';
        print('Imprimiendo vía Print Server: $url');
      } else {
        // Usar servidor principal (API)
        final server = ServerConfig.activeServer;
        if (server == null) {
          return PrintResult(success: false, error: 'No hay servidor configurado');
        }
        url = '${server.baseUrl}/print/label';
        print('Imprimiendo vía API Server: $url');
      }

      final response = await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'zpl': zpl}),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          return PrintResult(success: true);
        } else {
          return PrintResult(success: false, error: data['error'] ?? data['message'] ?? 'Error desconocido');
        }
      } else {
        return PrintResult(success: false, error: 'Error del servidor: ${response.statusCode}');
      }
    } on SocketException {
      return PrintResult(success: false, error: 'No se puede conectar al servidor');
    } on TimeoutException {
      return PrintResult(success: false, error: 'Tiempo de espera agotado');
    } catch (e) {
      return PrintResult(success: false, error: e.toString());
    }
  }

  /// Imprimir vía Bluetooth directo (Bluetooth Classic SPP)
  static Future<PrintResult> _printViaBluetooth(String zpl) async {
    try {
      if (_bluetoothDeviceId == null) {
        return PrintResult(success: false, error: 'No hay impresora Bluetooth configurada');
      }

      // Inicializar permisos
      await _bluetoothClassic.initPermissions();

      // Conectar si no está conectado
      // UUID para SPP (Serial Port Profile)
      const sppUuid = "00001101-0000-1000-8000-00805f9b34fb";
      
      if (!_isConnected) {
        try {
          print('Connecting to Bluetooth device: $_bluetoothDeviceId');
          await _bluetoothClassic.connect(_bluetoothDeviceId!, sppUuid);
          _isConnected = true;
          print('Connected to ${_bluetoothDeviceName}');
        } catch (e) {
          print('Connection error: $e');
          _isConnected = false;
          return PrintResult(success: false, error: 'Error al conectar: ${e.toString()}');
        }
      }

      // Limpiar ZPL: quitar espacios al inicio de cada línea y líneas vacías
      final cleanZpl = zpl
          .split('\n')
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty)
          .join('\r\n');
      
      // Convertir a bytes - usar latin1 para compatibilidad con Zebra
      final bytes = Uint8List.fromList(latin1.encode(cleanZpl));
      
      print('Sending ZPL to printer (${bytes.length} bytes)...');
      
      // Enviar usando writeBytes
      await _bluetoothClassic.writeBytes(bytes);
      
      print('ZPL sent successfully');

      // Actualizar último uso
      await _addToRecentPrinters(_bluetoothDeviceId!, _bluetoothDeviceName ?? 'Unknown');

      return PrintResult(success: true);
    } on TimeoutException {
      return PrintResult(success: false, error: 'Tiempo de espera agotado al conectar');
    } catch (e) {
      print('Bluetooth print error: $e');
      _isConnected = false;
      return PrintResult(success: false, error: e.toString());
    }
  }

  /// Probar conexión (5 segundos timeout)
  static Future<PrintResult> testConnection() async {
    try {
      if (_currentMode == PrinterMode.backend) {
        String url;
        
        // Determinar qué servidor probar
        if (PrintServerConfig.isEnabled && PrintServerConfig.isConfigured) {
          // Probar servidor de impresión separado
          url = '${PrintServerConfig.baseUrl}/print/status';
        } else {
          // Probar servidor principal
          final server = ServerConfig.activeServer;
          if (server == null) {
            return PrintResult(success: false, error: 'No hay servidor configurado');
          }
          url = '${server.baseUrl}/print/status';
        }

        final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 5));
        
        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          if (data['configured'] == true) {
            return PrintResult(success: true);
          } else {
            return PrintResult(success: false, error: 'Impresora no configurada en servidor');
          }
        }
        return PrintResult(success: false, error: 'Error: ${response.statusCode}');
      } else {
        // Test Bluetooth Classic
        if (_bluetoothDeviceId == null) {
          return PrintResult(success: false, error: 'No hay impresora seleccionada');
        }

        // Inicializar permisos
        await _bluetoothClassic.initPermissions();

        // Intentar conectar y desconectar para verificar
        const sppUuid = "00001101-0000-1000-8000-00805f9b34fb";
        try {
          await _bluetoothClassic.connect(_bluetoothDeviceId!, sppUuid);
          await _bluetoothClassic.disconnect();
          return PrintResult(success: true);
        } catch (e) {
          return PrintResult(success: false, error: 'No se pudo conectar: ${e.toString()}');
        }
      }
    } on TimeoutException {
      return PrintResult(success: false, error: 'Tiempo de espera agotado');
    } catch (e) {
      return PrintResult(success: false, error: e.toString());
    }
  }

  /// Desconectar Bluetooth si está conectado
  static Future<void> disconnect() async {
    try {
      if (_isConnected) {
        await _bluetoothClassic.disconnect();
        _isConnected = false;
      }
    } catch (e) {
      print('Error disconnecting: $e');
    }
  }

  /// Limpiar configuración
  static Future<void> clear() async {
    _bluetoothDeviceId = null;
    _bluetoothDeviceName = null;
    await disconnect();
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_bluetoothDeviceIdKey);
    await prefs.remove(_bluetoothDeviceNameKey);
  }
}
