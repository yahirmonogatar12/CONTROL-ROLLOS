import 'dart:async';
import 'dart:io';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:material_warehousing_flutter/core/config/server_config.dart';
import 'package:material_warehousing_flutter/core/services/api_service.dart';
import 'package:material_warehousing_flutter/firebase_options.dart';

/// Background message handler (must be top-level function)
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  }
  debugPrint('[FCM] Background message: ${message.messageId}');
}

class FCMConnectionStatus {
  final bool isSupported;
  final bool isChecking;
  final AuthorizationStatus? permissionStatus;
  final String? token;
  final bool? backendRegistered;
  final bool? topicSubscribed;
  final String? backendMessage;
  final String? topicMessage;
  final String? lastError;

  const FCMConnectionStatus({
    required this.isSupported,
    required this.isChecking,
    required this.permissionStatus,
    required this.token,
    required this.backendRegistered,
    required this.topicSubscribed,
    required this.backendMessage,
    required this.topicMessage,
    required this.lastError,
  });

  bool get hasToken => token != null && token!.isNotEmpty;

  bool get topicManagedByBackend =>
      backendRegistered == true && topicSubscribed != true;

  bool get topicReady => topicSubscribed == true || topicManagedByBackend;

  bool get isActive =>
      isSupported &&
      permissionStatus == AuthorizationStatus.authorized &&
      hasToken &&
      backendRegistered == true &&
      topicReady;

  String get permissionLabel {
    switch (permissionStatus) {
      case AuthorizationStatus.authorized:
        return 'Autorizado';
      case AuthorizationStatus.denied:
        return 'Denegado';
      case AuthorizationStatus.notDetermined:
        return 'Pendiente';
      case AuthorizationStatus.provisional:
        return 'Provisional';
      default:
        return 'Sin revisar';
    }
  }

  String get tokenLabel => hasToken ? 'Disponible' : 'No disponible';

  String get backendLabel {
    if (backendRegistered == true) return 'Registrado';
    if (backendRegistered == false) return 'Error';
    return 'Pendiente';
  }

  String get topicLabel {
    if (topicSubscribed == true) return 'Suscrito local';
    if (topicManagedByBackend) return 'Via backend';
    if (topicSubscribed == false) return 'Error local';
    return 'Pendiente';
  }

  String get shortToken {
    if (!hasToken) return 'Sin token';
    if (token!.length <= 20) return token!;
    return '${token!.substring(0, 12)}...${token!.substring(token!.length - 6)}';
  }
}

/// Servicio de Firebase Cloud Messaging para notificaciones push
class FCMService {
  static final FCMService _instance = FCMService._();
  static FCMService get instance => _instance;

  FCMService._();

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  String? _token;
  AuthorizationStatus? _permissionStatus;
  bool? _backendRegistered;
  bool? _topicSubscribed;
  String? _backendMessage;
  String? _topicMessage;
  String? _lastError;
  bool _isConnecting = false;
  bool _listenersRegistered = false;
  bool _backgroundHandlerRegistered = false;
  bool _localNotificationsInitialized = false;
  Future<void>? _pendingInit;

  String? get token => _token;

  static const Map<String, String> _lineLabels = {
    'SA': 'SMT A',
    'SB': 'SMT B',
    'SC': 'SMT C',
    'SD': 'SMT D',
    'SE': 'SMT E',
  };

  /// Callback cuando se recibe una notificacion de material request
  void Function(Map<String, dynamic> data)? onMaterialRequest;

  FCMConnectionStatus get status => FCMConnectionStatus(
        isSupported: !kIsWeb && (Platform.isAndroid || Platform.isIOS),
        isChecking: _isConnecting,
        permissionStatus: _permissionStatus,
        token: _token,
        backendRegistered: _backendRegistered,
        topicSubscribed: _topicSubscribed,
        backendMessage: _backendMessage,
        topicMessage: _topicMessage,
        lastError: _lastError,
      );

  String _formatLineLabel(String? lineId) {
    if (lineId == null || lineId.isEmpty) {
      return 'Solicitud de material';
    }
    return _lineLabels[lineId] ?? lineId;
  }

  String _extractPartNumber(String? reelCode) {
    final normalized = (reelCode ?? '').trim();
    if (normalized.isEmpty) {
      return '';
    }
    return normalized.split('-').first.trim();
  }

  /// Inicializar o reconectar FCM sin duplicar listeners.
  Future<FCMConnectionStatus> init({ServerProfile? serverOverride}) async {
    if (_pendingInit != null) {
      await _pendingInit;
      if (serverOverride != null) {
        return init(serverOverride: serverOverride);
      }
      return status;
    }

    final future = _runInit(serverOverride: serverOverride);
    _pendingInit = future;

    try {
      await future;
    } finally {
      if (identical(_pendingInit, future)) {
        _pendingInit = null;
      }
    }

    return status;
  }

  Future<void> _runInit({ServerProfile? serverOverride}) async {
    _isConnecting = true;
    _lastError = null;

    try {
      if (!status.isSupported) {
        _lastError = 'FCM solo esta soportado en Android/iOS';
        return;
      }

      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        );
      }
      await _messaging.setAutoInitEnabled(true);

      if (!_backgroundHandlerRegistered) {
        FirebaseMessaging.onBackgroundMessage(
          _firebaseMessagingBackgroundHandler,
        );
        _backgroundHandlerRegistered = true;
      }

      await _ensureLocalNotificationsInitialized();
      _registerRealtimeListeners();

      final settings = await _messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      _permissionStatus = settings.authorizationStatus;
      debugPrint('[FCM] Permission: ${settings.authorizationStatus}');

      _token = await _messaging.getToken();
      debugPrint('[FCM] Token: $_token');
      if (_token != null) {
        await _registerToken(_token!, serverOverride: serverOverride);
      } else {
        _backendRegistered = false;
        _backendMessage = 'No se obtuvo token FCM';
      }

      await _subscribeToMaterialRequestsTopic();

      final initialMessage = await _messaging.getInitialMessage();
      if (initialMessage != null) {
        _handleMessageOpenedApp(initialMessage);
      }
    } catch (e) {
      _lastError = e.toString();
      debugPrint('[FCM] Init error: $e');
    } finally {
      _isConnecting = false;
    }
  }

  /// Register FCM token with backend
  Future<void> _registerToken(
    String token, {
    ServerProfile? serverOverride,
  }) async {
    try {
      final activeServer = serverOverride ?? ServerConfig.activeServer;
      final serverIp = activeServer?.ip.trim().toLowerCase();
      if (Platform.isAndroid &&
          (serverIp == 'localhost' ||
              serverIp == '127.0.0.1' ||
              serverIp == '0.0.0.0')) {
        debugPrint(
          '[FCM] Warning: active server is localhost on Android. Token registration will not reach the PC backend.',
        );
      }

      final result = await ApiService.registerFCMToken(
        token,
        baseUrlOverride: activeServer?.baseUrl,
      );
      if (result['ok'] == true) {
        _backendRegistered = true;
        _backendMessage = 'Token registrado con backend';
        _topicMessage ??= 'Topic gestionado por backend central';
        debugPrint('[FCM] Token registered with backend');
      } else {
        _backendRegistered = false;
        _backendMessage = result['error']?.toString() ?? 'Registro rechazado';
        debugPrint(
          '[FCM] Token registration rejected: ${result['error'] ?? result}',
        );
      }
    } catch (e) {
      _backendRegistered = false;
      _backendMessage = e.toString();
      debugPrint('[FCM] Token registration error: $e');
    }
  }

  Future<void> _subscribeToMaterialRequestsTopic() async {
    try {
      await _messaging
          .subscribeToTopic('smt_material_requests')
          .timeout(const Duration(seconds: 8));
      _topicSubscribed = true;
      _topicMessage = 'Suscrito al topic smt_material_requests';
      debugPrint('[FCM] Subscribed to topic: smt_material_requests');
    } catch (e) {
      _topicSubscribed = false;
      _topicMessage = _backendRegistered == true
          ? 'Suscripcion local fallo, pero el backend registra el topic: $e'
          : e.toString();
      debugPrint('[FCM] Topic subscription error: $e');
    }
  }

  void _registerRealtimeListeners() {
    if (_listenersRegistered) return;

    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);
    FirebaseMessaging.onMessageOpenedApp.listen(_handleMessageOpenedApp);
    _messaging.onTokenRefresh.listen((newToken) {
      _token = newToken;
      unawaited(_registerToken(newToken));
    });

    _listenersRegistered = true;
  }

  Future<void> _ensureLocalNotificationsInitialized() async {
    if (_localNotificationsInitialized || !Platform.isAndroid) {
      return;
    }

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidInit);
    await _localNotifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onNotificationTapped,
    );

    const channel = AndroidNotificationChannel(
      'smt_material_requests',
      'SMT Material Requests',
      description: 'Solicitudes de material desde lineas SMT',
      importance: Importance.high,
    );
    await _localNotifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);
    await _localNotifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();

    _localNotificationsInitialized = true;
  }

  /// Handle foreground messages - show local notification
  void _handleForegroundMessage(RemoteMessage message) {
    debugPrint('[FCM] Foreground message: ${message.data}');

    final notification = message.notification;
    if (Platform.isAndroid) {
      final lineId = message.data['lineId']?.toString();
      final reelCode = message.data['reelCode']?.toString();
      final partNumber = _extractPartNumber(reelCode);
      final title = lineId != null && lineId.isNotEmpty
          ? 'Material - ${_formatLineLabel(lineId)}'
          : (notification?.title ?? 'Solicitud de material');
      final body = partNumber.isNotEmpty
          ? 'Parte: $partNumber'
          : (notification?.body ?? 'Nueva solicitud de material');

      _localNotifications.show(
        message.hashCode,
        title,
        body,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'smt_material_requests',
            'SMT Material Requests',
            importance: Importance.high,
            priority: Priority.high,
            icon: '@mipmap/ic_launcher',
          ),
        ),
      );
      debugPrint('[FCM] Local notification displayed');
    }

    if (message.data['type'] == 'material_request') {
      onMaterialRequest?.call(message.data);
    }
  }

  /// Handle notification tap when app was in background
  void _handleMessageOpenedApp(RemoteMessage message) {
    debugPrint('[FCM] Opened from notification: ${message.data}');
    if (message.data['type'] == 'material_request') {
      onMaterialRequest?.call(message.data);
    }
  }

  /// Handle local notification tap
  void _onNotificationTapped(NotificationResponse response) {
    debugPrint('[FCM] Local notification tapped: ${response.payload}');
  }
}
