import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Configuration for the print server (separate from main backend)
/// This allows using Vercel for API and a local PC for printing
class PrintServerConfig {
  static const String _serverIpKey = 'print_server_ip';
  static const String _serverPortKey = 'print_server_port';
  static const String _useHttpsKey = 'print_server_https';
  static const String _enabledKey = 'print_server_enabled';

  static String? _serverIp;
  static int _serverPort = 3010;
  static bool _useHttps = false;
  static bool _enabled = false;
  static bool _isInitialized = false;

  /// Get the print server IP
  static String? get serverIp => _serverIp;
  
  /// Get the print server port
  static int get serverPort => _serverPort;
  
  /// Check if HTTPS is enabled
  static bool get useHttps => _useHttps;
  
  /// Check if print server is enabled
  static bool get isEnabled => _enabled;
  
  /// Check if print server is configured
  static bool get isConfigured => _serverIp != null && _serverIp!.isNotEmpty;

  /// Get the protocol
  static String get protocol => _useHttps ? 'https' : 'http';

  /// Check if using standard port (omit from URL)
  static bool get _useStandardPort => 
      (_useHttps && _serverPort == 443) || (!_useHttps && _serverPort == 80);

  /// Get the base URL for print server API calls
  static String get baseUrl {
    if (!isConfigured) return '';
    return _useStandardPort 
        ? '$protocol://$_serverIp/api'
        : '$protocol://$_serverIp:$_serverPort/api';
  }

  /// Get display string for UI
  static String get displayString {
    if (!isConfigured) return 'No configurado';
    return _useStandardPort
        ? '$protocol://$_serverIp'
        : '$protocol://$_serverIp:$_serverPort';
  }

  /// Initialize the service
  static Future<void> init() async {
    if (_isInitialized) return;

    final prefs = await SharedPreferences.getInstance();
    _serverIp = prefs.getString(_serverIpKey);
    _serverPort = prefs.getInt(_serverPortKey) ?? 3010;
    _useHttps = prefs.getBool(_useHttpsKey) ?? false;
    _enabled = prefs.getBool(_enabledKey) ?? false;

    _isInitialized = true;
    print('PrintServerConfig initialized: ${_enabled ? displayString : "disabled"}');
  }

  /// Save configuration
  static Future<void> setConfig({
    required String ip,
    required int port,
    bool useHttps = false,
    bool enabled = true,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    
    await prefs.setString(_serverIpKey, ip);
    await prefs.setInt(_serverPortKey, port);
    await prefs.setBool(_useHttpsKey, useHttps);
    await prefs.setBool(_enabledKey, enabled);
    
    _serverIp = ip;
    _serverPort = port;
    _useHttps = useHttps;
    _enabled = enabled;
    
    print('PrintServerConfig updated: $displayString (enabled: $_enabled)');
  }

  /// Enable/disable print server
  static Future<void> setEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, enabled);
    _enabled = enabled;
  }

  /// Test connection to print server
  static Future<bool> testConnection({String? ip, int? port, bool? useHttps}) async {
    final testIp = ip ?? _serverIp ?? '';
    final testPort = port ?? _serverPort;
    final testHttps = useHttps ?? _useHttps;
    
    if (testIp.isEmpty) return false;
    
    final testProtocol = testHttps ? 'https' : 'http';
    final useStandard = (testHttps && testPort == 443) || (!testHttps && testPort == 80);
    final testUrl = useStandard 
        ? '$testProtocol://$testIp/api/health'
        : '$testProtocol://$testIp:$testPort/api/health';

    try {
      final response = await http.get(
        Uri.parse(testUrl),
      ).timeout(const Duration(seconds: 5));
      
      return response.statusCode == 200;
    } catch (e) {
      print('Print server connection test failed for $testUrl: $e');
      return false;
    }
  }

  /// Send print job to the print server
  static Future<bool> sendPrintJob({
    required String zplCode,
    String? printerIp,
    int printerPort = 9100,
  }) async {
    if (!_enabled || !isConfigured) {
      print('Print server not enabled or configured');
      return false;
    }

    try {
      final response = await http.post(
        Uri.parse('$baseUrl/print/zpl'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'zpl': zplCode,
          'printerIp': printerIp,
          'printerPort': printerPort,
        }),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        print('Print job sent successfully via print server');
        return true;
      } else {
        print('Print server error: ${response.statusCode} - ${response.body}');
        return false;
      }
    } catch (e) {
      print('Error sending print job to server: $e');
      return false;
    }
  }

  /// Clear configuration
  static Future<void> clearConfig() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_serverIpKey);
    await prefs.remove(_serverPortKey);
    await prefs.remove(_useHttpsKey);
    await prefs.remove(_enabledKey);
    
    _serverIp = null;
    _serverPort = 3010;
    _useHttps = false;
    _enabled = false;
  }
}
