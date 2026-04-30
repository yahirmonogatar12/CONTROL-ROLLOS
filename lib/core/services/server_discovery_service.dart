import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

/// Información de un servidor descubierto
class DiscoveredServer {
  final String ip;
  final int port;
  final String name;
  final DateTime discoveredAt;
  final String method; // 'udp' o 'http'

  DiscoveredServer({
    required this.ip,
    required this.port,
    required this.name,
    required this.discoveredAt,
    this.method = 'udp',
  });

  String get displayName => name.isNotEmpty ? name : ip;
  String get baseUrl => 'http://$ip:$port/api';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DiscoveredServer &&
          runtimeType == other.runtimeType &&
          ip == other.ip &&
          port == other.port;

  @override
  int get hashCode => ip.hashCode ^ port.hashCode;
}

/// Servicio para descubrir servidores en la red local
/// Usa principalmente HTTP probe ya que es más confiable en Android
class ServerDiscoveryService {
  static const int _discoveryPort = 41234;
  static const int _httpPort = 3010;
  static const String _serviceName = 'MaterialControl';
  static const Duration _scanTimeout = Duration(seconds: 8);

  RawDatagramSocket? _socket;
  final _serversController = StreamController<List<DiscoveredServer>>.broadcast();
  final Map<String, DiscoveredServer> _foundServers = {};
  Timer? _cleanupTimer;
  bool _isScanning = false;

  /// Stream de servidores descubiertos
  Stream<List<DiscoveredServer>> get serversStream => _serversController.stream;

  /// Lista actual de servidores
  List<DiscoveredServer> get servers => _foundServers.values.toList();

  /// ¿Está escaneando actualmente?
  bool get isScanning => _isScanning;

  /// Inicia el escaneo de servidores usando múltiples métodos
  Future<List<DiscoveredServer>> scanForServers({
    Duration timeout = _scanTimeout,
  }) async {
    if (_isScanning) {
      return servers;
    }

    _isScanning = true;
    _foundServers.clear();

    try {
      // HTTP es más confiable en Android, darle prioridad
      // UDP broadcast a menudo está bloqueado en redes WiFi por aislamiento de clientes
      await Future.wait([
        _scanHTTP(timeout),
        _scanUDP(timeout).catchError((_) {}), // UDP puede fallar, no es crítico
      ]);
    } catch (e) {
      print('Error en discovery: $e');
    } finally {
      _isScanning = false;
    }

    return servers;
  }

  /// Escaneo UDP broadcast (puede no funcionar en todas las redes)
  Future<void> _scanUDP(Duration timeout) async {
    try {
      _socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      _socket!.broadcastEnabled = true;

      _socket!.listen((event) {
        if (event == RawSocketEvent.read) {
          final datagram = _socket!.receive();
          if (datagram != null) {
            _handleUDPResponse(datagram);
          }
        }
      });

      // Enviar a múltiples direcciones broadcast
      _sendDiscoveryRequests();

      await Future.delayed(Duration(milliseconds: timeout.inMilliseconds ~/ 2));
      _sendDiscoveryRequests();
      await Future.delayed(Duration(milliseconds: timeout.inMilliseconds ~/ 2));

    } catch (e) {
      print('UDP discovery no disponible: $e');
    } finally {
      _socket?.close();
      _socket = null;
    }
  }

  /// Escaneo HTTP - prueba endpoints de health en subredes comunes
  /// Este es el método más confiable para Android
  Future<void> _scanHTTP(Duration timeout) async {
    final subnetsToScan = await _getSubnetsToScan();
    final futures = <Future>[];

    print('🔍 Escaneando subredes: $subnetsToScan');

    for (final subnet in subnetsToScan) {
      // Probar TODAS las IPs del 1 al 254 sería muy lento
      // Probar las más comunes: gateway, DHCP típicos, y específicas
      final ipsToTry = <String>{
        '$subnet.1',   // Gateway típico
        '$subnet.2',   
        '$subnet.27',  // Tu PC específica
        '$subnet.100', '$subnet.101', '$subnet.102', '$subnet.103', '$subnet.104',
        '$subnet.105', '$subnet.106', '$subnet.107', '$subnet.108', '$subnet.109',
        '$subnet.110', '$subnet.111', '$subnet.112', '$subnet.113', '$subnet.114',
        '$subnet.115', '$subnet.116', '$subnet.117', '$subnet.118', '$subnet.119',
        '$subnet.120',
        '$subnet.200', '$subnet.201', '$subnet.202', '$subnet.203', '$subnet.204',
        '$subnet.205', '$subnet.206', '$subnet.207', '$subnet.208', '$subnet.209',
        '$subnet.210',
        // IPs bajas también comunes en DHCP
        '$subnet.10', '$subnet.11', '$subnet.12', '$subnet.13', '$subnet.14',
        '$subnet.15', '$subnet.16', '$subnet.17', '$subnet.18', '$subnet.19',
        '$subnet.20', '$subnet.21', '$subnet.22', '$subnet.23', '$subnet.24',
        '$subnet.25', '$subnet.26', '$subnet.28', '$subnet.29', '$subnet.30',
        '$subnet.31', '$subnet.32', '$subnet.33', '$subnet.34', '$subnet.35',
        '$subnet.36', '$subnet.37', '$subnet.38', '$subnet.39', '$subnet.40',
        '$subnet.50', '$subnet.51', '$subnet.52', '$subnet.53', '$subnet.54',
        '$subnet.55', '$subnet.56', '$subnet.57', '$subnet.58', '$subnet.59',
        '$subnet.60',
      };

      for (final ip in ipsToTry) {
        futures.add(_probeServer(ip, _httpPort));
      }
    }

    // Probar IPs de Tailscale conocidas
    // Tailscale usa el rango 100.x.x.x
    futures.add(_probeServer('100.111.108.116', _httpPort));
    
    // Tu IP WiFi específica
    futures.add(_probeServer('192.168.1.27', _httpPort));

    // Esperar con timeout
    await Future.wait(futures).timeout(
      timeout,
      onTimeout: () => [],
    );
  }

  /// Obtiene las subredes a escanear basado en las interfaces de red
  Future<List<String>> _getSubnetsToScan() async {
    final subnets = <String>{};

    try {
      final interfaces = await NetworkInterface.list(
        includeLoopback: false,
        type: InternetAddressType.IPv4,
      );
      
      for (final interface in interfaces) {
        // Ignorar interfaces virtuales, VPN, Docker, etc. para WiFi
        final name = interface.name.toLowerCase();
        final isRealInterface = !name.contains('docker') && 
                                !name.contains('veth') && 
                                !name.contains('br-') &&
                                !name.contains('vmware') &&
                                !name.contains('virtualbox');
        
        if (isRealInterface) {
          for (final addr in interface.addresses) {
            if (!addr.isLoopback && !addr.isLinkLocal) {
              final parts = addr.address.split('.');
              if (parts.length == 4) {
                final subnet = '${parts[0]}.${parts[1]}.${parts[2]}';
                subnets.add(subnet);
                print('🔍 Encontrada interfaz ${interface.name}: ${addr.address} -> $subnet');
              }
            }
          }
        }
      }
    } catch (e) {
      print('Error obteniendo interfaces: $e');
    }

    // SIEMPRE agregar estas subredes comunes (para cuando la detección falle)
    subnets.addAll([
      '192.168.1',   // Tu red WiFi
      '192.168.0',   // Común
      '10.0.0',      // Común empresarial
      '10.0.1',      
      '100.111.108', // Tailscale
      '100.64.0',    // Tailscale alternativo
    ]);

    return subnets.toList();
  }

  /// Prueba si un servidor está disponible en una IP específica
  Future<void> _probeServer(String ip, int port) async {
    try {
      final url = Uri.parse('http://$ip:$port/api/health');
      final response = await http.get(url).timeout(
        const Duration(milliseconds: 1500), // Timeout corto para escaneo rápido
        onTimeout: () => http.Response('', 408),
      );

      if (response.statusCode == 200) {
        try {
          final data = jsonDecode(response.body);
          if (data['status'] == 'OK') {
            _addServer(DiscoveredServer(
              ip: ip,
              port: port,
              name: _getHostnameFromIP(ip),
              discoveredAt: DateTime.now(),
              method: 'http',
            ));
          }
        } catch (_) {
          // Si la respuesta no es JSON pero es 200, aún es válido
          _addServer(DiscoveredServer(
            ip: ip,
            port: port,
            name: _getHostnameFromIP(ip),
            discoveredAt: DateTime.now(),
            method: 'http',
          ));
        }
      }
    } catch (e) {
      // Ignorar errores de conexión - es normal que la mayoría fallen
    }
  }

  String _getHostnameFromIP(String ip) {
    if (ip.startsWith('100.')) return 'Servidor (Tailscale)';
    if (ip == '192.168.1.27') return 'PC Local (WiFi)';
    if (ip.startsWith('192.168.') || ip.startsWith('10.')) return 'Servidor (LAN)';
    return 'Servidor';
  }

  void _sendDiscoveryRequests() {
    if (_socket == null) return;

    final request = jsonEncode({
      'type': 'DISCOVER',
      'service': _serviceName,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });

    final data = utf8.encode(request);

    // Enviar a broadcast general y específicos
    final broadcasts = [
      '255.255.255.255',
      '192.168.1.255',
      '192.168.0.255',
      '10.0.0.255',
      '100.111.108.255', // Tailscale subnet
      '100.64.0.255',    // Tailscale alternativo
    ];

    for (final addr in broadcasts) {
      try {
        _socket!.send(data, InternetAddress(addr), _discoveryPort);
      } catch (e) {
        // Ignorar errores
      }
    }
  }

  void _handleUDPResponse(Datagram datagram) {
    try {
      final message = utf8.decode(datagram.data);
      final data = jsonDecode(message) as Map<String, dynamic>;

      if (data['service'] != _serviceName) return;

      final type = data['type'];
      if (type != 'BEACON' && type != 'ANNOUNCE') return;

      _addServer(DiscoveredServer(
        ip: data['ip'] ?? datagram.address.address,
        port: data['port'] ?? 3010,
        name: data['name'] ?? '',
        discoveredAt: DateTime.now(),
        method: 'udp',
      ));
    } catch (e) {
      // Ignorar mensajes inválidos
    }
  }

  void _addServer(DiscoveredServer server) {
    final key = '${server.ip}:${server.port}';
    if (!_foundServers.containsKey(key)) {
      _foundServers[key] = server;
      _serversController.add(servers);
      print('✅ Servidor descubierto: ${server.displayName} (${server.ip}:${server.port}) via ${server.method}');
    }
  }

  /// Escucha continuamente por beacons de servidores
  Future<void> startListening() async {
    if (_socket != null) return;

    try {
      _socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, _discoveryPort);
      _socket!.broadcastEnabled = true;

      _socket!.listen((event) {
        if (event == RawSocketEvent.read) {
          final datagram = _socket!.receive();
          if (datagram != null) {
            _handleUDPResponse(datagram);
          }
        }
      });

      _cleanupTimer = Timer.periodic(const Duration(seconds: 10), (_) {
        _cleanupOldServers();
      });

      print('🔍 Escuchando beacons de servidores en puerto $_discoveryPort');
    } catch (e) {
      print('Error iniciando listener UDP: $e');
    }
  }

  void stopListening() {
    _cleanupTimer?.cancel();
    _cleanupTimer = null;
    _socket?.close();
    _socket = null;
  }

  void _cleanupOldServers() {
    final now = DateTime.now();
    final maxAge = const Duration(seconds: 15);
    
    _foundServers.removeWhere((key, server) {
      return now.difference(server.discoveredAt) > maxAge;
    });
    
    _serversController.add(servers);
  }

  void dispose() {
    stopListening();
    _serversController.close();
  }
}
