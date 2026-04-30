import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../config/server_config.dart';

/// Servicio de WebSocket para actualizaciones en tiempo real de auditoría
class AuditWebSocketService {
  static AuditWebSocketService? _instance;
  
  WebSocketChannel? _channel;
  StreamSubscription? _subscription;
  
  // Stream controllers para diferentes eventos
  final _locationUpdateController = StreamController<Map<String, dynamic>>.broadcast();
  final _itemScannedController = StreamController<Map<String, dynamic>>.broadcast();
  final _auditEndedController = StreamController<Map<String, dynamic>>.broadcast();
  final _connectionStateController = StreamController<bool>.broadcast();
  
  // Estado de conexión
  bool _isConnected = false;
  int? _currentAuditId;
  String? _clientType; // 'pc' o 'mobile'
  int? _operatorId;
  
  // Reconnection
  Timer? _reconnectTimer;
  int _reconnectAttempts = 0;
  static const int _maxReconnectAttempts = 5;
  static const Duration _reconnectDelay = Duration(seconds: 3);
  
  // Heartbeat
  Timer? _heartbeatTimer;
  static const Duration _heartbeatInterval = Duration(seconds: 25);
  
  // Singleton
  factory AuditWebSocketService() {
    _instance ??= AuditWebSocketService._internal();
    return _instance!;
  }
  
  AuditWebSocketService._internal();
  
  /// Streams públicos para escuchar eventos
  Stream<Map<String, dynamic>> get locationUpdates => _locationUpdateController.stream;
  Stream<Map<String, dynamic>> get itemScanned => _itemScannedController.stream;
  Stream<Map<String, dynamic>> get auditEnded => _auditEndedController.stream;
  Stream<bool> get connectionState => _connectionStateController.stream;
  
  bool get isConnected => _isConnected;
  
  /// Obtener URL del WebSocket basado en la configuración del servidor
  String get _wsUrl {
    final httpUrl = ServerConfig.baseUrl;
    // Convertir http://host:port/api a ws://host:port/ws/audit
    final uri = Uri.parse(httpUrl);
    final wsScheme = uri.scheme == 'https' ? 'wss' : 'ws';
    return '$wsScheme://${uri.host}:${uri.port}/ws/audit';
  }
  
  /// Conectar al WebSocket y suscribirse a una auditoría
  Future<bool> connect({
    required int auditId,
    required String clientType, // 'pc' o 'mobile'
    int? operatorId,
  }) async {
    // Si ya está conectado a la misma auditoría, no reconectar
    if (_isConnected && _currentAuditId == auditId) {
      return true;
    }
    
    // Desconectar si hay conexión previa
    await disconnect();
    
    _currentAuditId = auditId;
    _clientType = clientType;
    _operatorId = operatorId;
    
    return _attemptConnect();
  }
  
  Future<bool> _attemptConnect() async {
    try {
      print('🔌 Conectando a WebSocket: $_wsUrl');
      
      _channel = WebSocketChannel.connect(Uri.parse(_wsUrl));
      
      // Escuchar mensajes
      _subscription = _channel!.stream.listen(
        _handleMessage,
        onError: _handleError,
        onDone: _handleDisconnect,
      );
      
      // Esperar un poco para que se establezca la conexión
      await Future.delayed(const Duration(milliseconds: 500));
      
      // Suscribirse a la auditoría
      _subscribe();
      
      _isConnected = true;
      _reconnectAttempts = 0;
      _connectionStateController.add(true);
      
      // Iniciar heartbeat
      _startHeartbeat();
      
      print('✅ WebSocket conectado');
      return true;
      
    } catch (e) {
      print('❌ Error conectando WebSocket: $e');
      _isConnected = false;
      _connectionStateController.add(false);
      _scheduleReconnect();
      return false;
    }
  }
  
  void _subscribe() {
    if (_channel == null || _currentAuditId == null) return;
    
    final subscribeMessage = {
      'type': 'subscribe',
      'auditId': _currentAuditId,
      'clientType': _clientType,
      'operatorId': _operatorId,
    };
    
    _channel!.sink.add(json.encode(subscribeMessage));
    print('📡 Suscrito a auditoría $_currentAuditId como $_clientType');
  }
  
  void _handleMessage(dynamic message) {
    try {
      final data = json.decode(message as String) as Map<String, dynamic>;
      final type = data['type'] as String?;
      
      print('📨 Mensaje WebSocket recibido: $type');
      
      switch (type) {
        case 'connected':
          print('   Conexión confirmada por servidor');
          break;
          
        case 'pong':
          // Respuesta a ping, conexión activa
          break;
          
        case 'location_update':
          _locationUpdateController.add(data['data'] ?? data);
          break;
          
        case 'item_scanned':
          _itemScannedController.add(data['data'] ?? data);
          break;
          
        case 'audit_ended':
          _auditEndedController.add(data['data'] ?? data);
          break;
          
        default:
          print('   Tipo de mensaje desconocido: $type');
      }
    } catch (e) {
      print('❌ Error procesando mensaje WebSocket: $e');
    }
  }
  
  void _handleError(dynamic error) {
    print('❌ Error WebSocket: $error');
    _isConnected = false;
    _connectionStateController.add(false);
    _scheduleReconnect();
  }
  
  void _handleDisconnect() {
    print('🔌 WebSocket desconectado');
    _isConnected = false;
    _connectionStateController.add(false);
    _scheduleReconnect();
  }
  
  void _scheduleReconnect() {
    if (_reconnectTimer?.isActive ?? false) return;
    if (_currentAuditId == null) return;
    
    _reconnectAttempts++;
    
    if (_reconnectAttempts > _maxReconnectAttempts) {
      print('❌ Máximo de intentos de reconexión alcanzado');
      return;
    }
    
    print('🔄 Reintentando conexión en ${_reconnectDelay.inSeconds}s (intento $_reconnectAttempts/$_maxReconnectAttempts)');
    
    _reconnectTimer = Timer(_reconnectDelay, () {
      if (_currentAuditId != null && !_isConnected) {
        _attemptConnect();
      }
    });
  }
  
  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(_heartbeatInterval, (_) {
      if (_isConnected && _channel != null) {
        try {
          _channel!.sink.add(json.encode({'type': 'ping'}));
        } catch (e) {
          print('❌ Error enviando heartbeat: $e');
        }
      }
    });
  }
  
  /// Desconectar del WebSocket
  Future<void> disconnect() async {
    print('🔌 Desconectando WebSocket...');
    
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    
    await _subscription?.cancel();
    _subscription = null;
    
    await _channel?.sink.close();
    _channel = null;
    
    _isConnected = false;
    _currentAuditId = null;
    _clientType = null;
    _operatorId = null;
    _reconnectAttempts = 0;
    
    _connectionStateController.add(false);
  }
  
  /// Liberar recursos
  void dispose() {
    disconnect();
    _locationUpdateController.close();
    _itemScannedController.close();
    _auditEndedController.close();
    _connectionStateController.close();
    _instance = null;
  }
}
