import 'dart:async';
import 'package:http/http.dart' as http;
import '../config/server_config.dart';

class BackendService {
  /// El backend es central; ninguna PC cliente debe intentar levantar Node.js.
  static String get baseUrl => ServerConfig.baseUrl;
  static const int maxRetries = 30; // 30 intentos
  static const Duration retryDelay =
      Duration(milliseconds: 500); // 500ms entre intentos

  /// Compatibilidad con llamadas antiguas: solo comprueba el backend remoto.
  static Future<bool> startBackend() async {
    print('🌐 Verificando backend remoto en $baseUrl');
    return isBackendReady();
  }

  /// Verifica si el backend está respondiendo
  static Future<bool> isBackendReady() async {
    try {
      final response = await http
          .get(
            Uri.parse('$baseUrl/health'),
          )
          .timeout(const Duration(seconds: 2));

      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  /// Espera hasta que el backend esté listo
  static Future<bool> waitForBackend({
    Function(String message, double progress)? onProgress,
  }) async {
    for (int i = 0; i < maxRetries; i++) {
      final progress = (i + 1) / maxRetries;
      onProgress?.call(
          'Conectando al servidor... (${i + 1}/$maxRetries)', progress);

      if (await isBackendReady()) {
        onProgress?.call('¡Servidor listo!', 1.0);
        return true;
      }

      await Future.delayed(retryDelay);
    }

    onProgress?.call('Error: No se pudo conectar al servidor', 1.0);
    return false;
  }

  /// No hay proceso local que detener; el backend vive en el servidor central.
  static Future<void> stopBackend() async {
    return;
  }

  /// Verifica si el backend ya está corriendo externamente
  static Future<bool> isBackendAlreadyRunning() async {
    return await isBackendReady();
  }
}
