import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../services/backend_http_client.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Represents a saved server configuration profile
class ServerProfile {
  final String id;
  final String name;
  final String ip;
  final int port;
  final bool useHttps; // Nuevo: soporte para HTTPS
  bool isActive;
  DateTime? lastConnected;

  ServerProfile({
    required this.id,
    required this.name,
    required this.ip,
    required this.port,
    this.useHttps = false, // Por defecto HTTP
    this.isActive = false,
    this.lastConnected,
  });

  /// Get the protocol (http or https)
  String get protocol => useHttps ? 'https' : 'http';

  /// Check if port should be included in URL (omit for standard ports)
  bool get _useStandardPort =>
      (useHttps && port == 443) || (!useHttps && port == 80);

  /// Get the full API base URL for this server
  String get baseUrl =>
      _useStandardPort ? '$protocol://$ip/api' : '$protocol://$ip:$port/api';

  /// Get display string for UI
  String get displayString => _useStandardPort
      ? '$name ($protocol://$ip)'
      : '$name ($protocol://$ip:$port)';

  /// Create from JSON
  factory ServerProfile.fromJson(Map<String, dynamic> json) {
    return ServerProfile(
      id: json['id'] ?? DateTime.now().millisecondsSinceEpoch.toString(),
      name: json['name'] ?? 'Server',
      ip: json['ip'] ?? 'localhost',
      port: json['port'] ?? 3010,
      useHttps: json['useHttps'] ?? false,
      isActive: json['isActive'] ?? false,
      lastConnected: json['lastConnected'] != null
          ? DateTime.tryParse(json['lastConnected'])
          : null,
    );
  }

  /// Convert to JSON for storage
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'ip': ip,
      'port': port,
      'useHttps': useHttps,
      'isActive': isActive,
      'lastConnected': lastConnected?.toIso8601String(),
    };
  }

  /// Create a copy with updated fields
  ServerProfile copyWith({
    String? id,
    String? name,
    String? ip,
    int? port,
    bool? useHttps,
    bool? isActive,
    DateTime? lastConnected,
  }) {
    return ServerProfile(
      id: id ?? this.id,
      name: name ?? this.name,
      ip: ip ?? this.ip,
      port: port ?? this.port,
      useHttps: useHttps ?? this.useHttps,
      isActive: isActive ?? this.isActive,
      lastConnected: lastConnected ?? this.lastConnected,
    );
  }
}

/// Service for managing server configuration
/// Supports multiple saved servers with one active at a time
class ServerConfig {
  static const String _serversKey = 'server_profiles';
  static const String _activeServerKey = 'active_server_id';

  static List<ServerProfile> _servers = [];
  static String? _activeServerId;
  static bool _isInitialized = false;

  /// Get all saved servers
  static List<ServerProfile> get servers => List.unmodifiable(_servers);

  /// Get the currently active server profile
  static ServerProfile? get activeServer {
    if (_servers.isEmpty) return null;
    return _servers.firstWhere(
      (s) => s.id == _activeServerId,
      orElse: () => _servers.first,
    );
  }

  /// Get the base URL for API calls
  static String get baseUrl {
    final server = activeServer;
    if (server != null) {
      return server.baseUrl;
    }
    // Default fallback based on platform
    if (!kIsWeb && Platform.isWindows) {
      return 'http://localhost:3010/api';
    }
    return 'http://localhost:3010/api';
  }

  /// Check if service is initialized
  static bool get isInitialized => _isInitialized;

  /// Check if there's at least one server configured
  static bool get hasServers => _servers.isNotEmpty;

  /// Initialize the service - must be called at app startup
  static Future<void> init() async {
    if (_isInitialized) return;

    final prefs = await SharedPreferences.getInstance();

    // Load saved servers
    final serversJson = prefs.getString(_serversKey);
    if (serversJson != null) {
      try {
        final List<dynamic> serversList = json.decode(serversJson);
        _servers = serversList.map((s) => ServerProfile.fromJson(s)).toList();
      } catch (e) {
        print('Error loading server profiles: $e');
        _servers = [];
      }
    }

    // Load active server ID
    _activeServerId = prefs.getString(_activeServerKey);

    // If no servers exist, create default based on platform
    if (_servers.isEmpty) {
      final defaultServer = ServerProfile(
        id: 'default',
        name: 'Local',
        ip: 'localhost',
        port: 3010,
        isActive: true,
      );
      _servers.add(defaultServer);
      _activeServerId = defaultServer.id;
      await _saveToPrefs();
    }

    // Ensure active server exists in list
    if (_activeServerId != null &&
        !_servers.any((s) => s.id == _activeServerId)) {
      _activeServerId = _servers.first.id;
      await _saveToPrefs();
    }

    _isInitialized = true;
    print(
        'ServerConfig initialized with ${_servers.length} servers. Active: ${activeServer?.displayString}');
  }

  /// Save current state to SharedPreferences
  static Future<void> _saveToPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final serversJson = json.encode(_servers.map((s) => s.toJson()).toList());
    await prefs.setString(_serversKey, serversJson);
    if (_activeServerId != null) {
      await prefs.setString(_activeServerKey, _activeServerId!);
    }
  }

  /// Add a new server profile
  static Future<void> addServer(ServerProfile server) async {
    // Generate unique ID if not provided
    final newServer = server.copyWith(
      id: server.id.isEmpty
          ? DateTime.now().millisecondsSinceEpoch.toString()
          : server.id,
    );

    _servers.add(newServer);

    // If this is the first server, make it active
    if (_servers.length == 1) {
      _activeServerId = newServer.id;
    }

    await _saveToPrefs();
  }

  /// Update an existing server profile
  static Future<void> updateServer(ServerProfile server) async {
    final index = _servers.indexWhere((s) => s.id == server.id);
    if (index >= 0) {
      _servers[index] = server;
      await _saveToPrefs();
    }
  }

  /// Remove a server profile
  static Future<void> removeServer(String serverId) async {
    _servers.removeWhere((s) => s.id == serverId);

    // If we removed the active server, select another
    if (_activeServerId == serverId && _servers.isNotEmpty) {
      _activeServerId = _servers.first.id;
    } else if (_servers.isEmpty) {
      _activeServerId = null;
    }

    await _saveToPrefs();
  }

  /// Set the active server by ID
  static Future<void> setActiveServer(String serverId) async {
    if (_servers.any((s) => s.id == serverId)) {
      _activeServerId = serverId;

      // Update isActive flag on all servers
      for (var server in _servers) {
        server.isActive = server.id == serverId;
      }

      await _saveToPrefs();
      print('Active server changed to: ${activeServer?.displayString}');
    }
  }

  /// Update last connected timestamp for active server
  static Future<void> updateLastConnected() async {
    final server = activeServer;
    if (server != null) {
      final index = _servers.indexWhere((s) => s.id == server.id);
      if (index >= 0) {
        _servers[index] = server.copyWith(lastConnected: DateTime.now());
        await _saveToPrefs();
      }
    }
  }

  /// Test connection to a specific server
  static Future<bool> testConnection(
      {String? ip, int? port, bool? useHttps}) async {
    final testIp = ip ?? activeServer?.ip ?? 'localhost';
    final testPort = port ?? activeServer?.port ?? 3010;
    final testHttps = useHttps ?? activeServer?.useHttps ?? false;
    final protocol = testHttps ? 'https' : 'http';

    // Omit port for standard ports (443 for HTTPS, 80 for HTTP)
    final useStandardPort =
        (testHttps && testPort == 443) || (!testHttps && testPort == 80);
    final testUrl = useStandardPort
        ? '$protocol://$testIp/api/health'
        : '$protocol://$testIp:$testPort/api/health';

    try {
      final response = await http
          .get(
            Uri.parse(testUrl),
          )
          .timeout(const Duration(seconds: 5));

      return response.statusCode == 200;
    } catch (e) {
      print('Connection test failed for $testUrl: $e');
      return false;
    }
  }

  /// Test connection to active server and update timestamp if successful
  static Future<bool> testActiveConnection() async {
    final success = await testConnection();
    if (success) {
      await updateLastConnected();
    }
    return success;
  }

  static Map<String, dynamic> _parseSmtConfigResponse(
    http.Response response, {
    required String method,
  }) {
    final rawBody = response.body.trim();
    final requestPath = '/api/smt-requests/config';
    dynamic decodedBody;

    if (rawBody.isNotEmpty) {
      try {
        decodedBody = json.decode(rawBody);
      } catch (_) {
        decodedBody = null;
      }
    }

    if (decodedBody is Map<String, dynamic>) {
      return {
        'success': response.statusCode == 200 && decodedBody['ok'] == true,
        'config': decodedBody['config'],
        'error': decodedBody['error'] ??
            (response.statusCode == 200
                ? null
                : 'Error ${response.statusCode}'),
      };
    }

    final looksLikeHtml = rawBody.startsWith('<!DOCTYPE html') ||
        rawBody.startsWith('<html') ||
        rawBody.contains('<html');

    if (looksLikeHtml && response.statusCode == 404) {
      return {
        'success': false,
        'error':
            'El backend seleccionado no expone $method $requestPath. Reinicia o actualiza el backend en ${response.request?.url.host}:${response.request?.url.port}.',
      };
    }

    if (looksLikeHtml) {
      return {
        'success': false,
        'error':
            'El backend devolvio HTML en lugar de JSON para $method $requestPath (HTTP ${response.statusCode}).',
      };
    }

    return {
      'success': false,
      'error': rawBody.isNotEmpty
          ? 'Respuesta no valida del backend (HTTP ${response.statusCode})'
          : 'Respuesta vacia del backend (HTTP ${response.statusCode})',
    };
  }

  /// Obtener configuracion remota SMT/FCM desde el backend seleccionado
  static Future<Map<String, dynamic>> getSmtRequestsConfig(
    ServerProfile server,
  ) async {
    try {
      final response = await http.get(
        Uri.parse('${server.baseUrl}/smt-requests/config'),
        headers: {'Accept': 'application/json'},
      ).timeout(const Duration(seconds: 5));

      return _parseSmtConfigResponse(response, method: 'GET');
    } catch (e) {
      return {
        'success': false,
        'error': e.toString(),
      };
    }
  }

  /// Guardar configuracion remota SMT/FCM en el backend seleccionado
  static Future<Map<String, dynamic>> updateSmtRequestsConfig(
    ServerProfile server, {
    required String centralHost,
    required int centralPort,
    required bool centralUseHttps,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('${server.baseUrl}/smt-requests/config'),
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: json.encode({
              'centralHost': centralHost,
              'centralPort': centralPort,
              'centralUseHttps': centralUseHttps,
            }),
          )
          .timeout(const Duration(seconds: 5));

      return _parseSmtConfigResponse(response, method: 'POST');
    } catch (e) {
      return {
        'success': false,
        'error': e.toString(),
      };
    }
  }

  /// Get local IP address of the device (for QR code generation)
  static Future<String?> getLocalIpAddress() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLinkLocal: false,
      );

      for (var interface in interfaces) {
        for (var addr in interface.addresses) {
          // Skip loopback addresses
          if (!addr.isLoopback && addr.address.startsWith('192.168')) {
            return addr.address;
          }
        }
      }

      // Fallback: return first non-loopback address
      for (var interface in interfaces) {
        for (var addr in interface.addresses) {
          if (!addr.isLoopback) {
            return addr.address;
          }
        }
      }
    } catch (e) {
      print('Error getting local IP: $e');
    }
    return null;
  }

  /// Generate QR code data for sharing server config
  static String generateQrData() {
    final server = activeServer;
    if (server == null) return '';

    return json.encode({
      'name': server.name,
      'ip': server.ip,
      'port': server.port,
      'useHttps': server.useHttps,
    });
  }

  /// Parse QR code data and return a ServerProfile
  static ServerProfile? parseQrData(String qrData) {
    try {
      final data = json.decode(qrData);
      return ServerProfile(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        name: data['name'] ?? 'Scanned Server',
        ip: data['ip'] ?? '',
        port: data['port'] ?? 3010,
        useHttps: data['useHttps'] ?? false,
      );
    } catch (e) {
      print('Error parsing QR data: $e');
      return null;
    }
  }

  /// Clear all saved data (for testing/reset)
  static Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_serversKey);
    await prefs.remove(_activeServerKey);
    _servers.clear();
    _activeServerId = null;
    _isInitialized = false;
  }
}
