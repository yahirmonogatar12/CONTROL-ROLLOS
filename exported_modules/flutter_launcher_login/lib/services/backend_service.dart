import 'dart:async';
import 'dart:io';
import 'package:http/http.dart' as http;

/// Servicio para gestionar el backend Node.js
/// 
/// Funcionalidades:
/// - Inicia el backend automáticamente
/// - Detecta si está en modo desarrollo o producción
/// - Espera a que el servidor esté listo
/// - Gestiona el ciclo de vida del proceso
class BackendService {
  static Process? _backendProcess;
  
  /// URL base del backend
  static String baseUrl = 'http://localhost:3000';
  
  /// Número máximo de reintentos para conectar
  static int maxRetries = 30;
  
  /// Delay entre reintentos
  static Duration retryDelay = const Duration(milliseconds: 500);
  
  /// Nombre del ejecutable del backend (para producción)
  static String backendExeName = 'backend-server.exe';
  
  /// Endpoint para verificar si el backend está listo
  static String healthEndpoint = '/api/health';

  /// Inicia el servidor backend
  /// 
  /// Busca en orden:
  /// 1. Backend compilado junto al ejecutable (producción)
  /// 2. Backend en carpeta backend/ usando Node.js (desarrollo)
  static Future<bool> startBackend() async {
    try {
      final exeDir = File(Platform.resolvedExecutable).parent.path;
      final pathSeparator = Platform.pathSeparator;
      
      String? backendExePath;
      String? workingDirectory;
      bool useNodeJs = false;
      
      // Opción 1: Backend compilado junto al ejecutable (distribución)
      final prodExePath = '$exeDir$pathSeparator$backendExeName';
      if (await File(prodExePath).exists()) {
        backendExePath = prodExePath;
        workingDirectory = exeDir;
        print('📦 Usando backend compilado: $prodExePath');
      }
      
      // Opción 2: En desarrollo (usar node server.js)
      if (backendExePath == null) {
        final devPath = '${Directory.current.path}${pathSeparator}backend';
        if (await Directory(devPath).exists() && 
            await File('$devPath${pathSeparator}server.js').exists()) {
          try {
            final nodeCheck = await Process.run('node', ['--version']);
            if (nodeCheck.exitCode == 0) {
              backendExePath = 'node';
              workingDirectory = devPath;
              useNodeJs = true;
              print('🔧 Modo desarrollo: usando Node.js en $devPath');
              print('✓ Node.js: ${nodeCheck.stdout.toString().trim()}');
            }
          } catch (e) {
            print('⚠️ Node.js no disponible para modo desarrollo');
          }
        }
      }

      if (backendExePath == null) {
        print('❌ No se encontró el backend (ni compilado ni desarrollo)');
        return false;
      }

      // Iniciar el servidor backend
      if (useNodeJs) {
        _backendProcess = await Process.start(
          'node',
          ['server.js'],
          workingDirectory: workingDirectory,
          runInShell: true,
        );
      } else {
        _backendProcess = await Process.start(
          backendExePath,
          [],
          workingDirectory: workingDirectory,
          runInShell: true,
        );
      }

      // Escuchar la salida del proceso para debug
      _backendProcess!.stdout.listen((data) {
        print('Backend: ${String.fromCharCodes(data)}');
      });

      _backendProcess!.stderr.listen((data) {
        print('Backend Error: ${String.fromCharCodes(data)}');
      });

      print('🚀 Proceso backend iniciado con PID: ${_backendProcess!.pid}');
      return true;
    } catch (e) {
      print('❌ Error iniciando backend: $e');
      return false;
    }
  }

  /// Verifica si el backend está respondiendo
  static Future<bool> isBackendReady() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl$healthEndpoint'),
      ).timeout(const Duration(seconds: 2));
      
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  /// Espera hasta que el backend esté listo
  /// 
  /// [onProgress] callback con mensaje y progreso (0.0 - 1.0)
  static Future<bool> waitForBackend({
    Function(String message, double progress)? onProgress,
  }) async {
    for (int i = 0; i < maxRetries; i++) {
      final progress = (i + 1) / maxRetries;
      onProgress?.call('Conectando al servidor... (${i + 1}/$maxRetries)', progress);
      
      if (await isBackendReady()) {
        onProgress?.call('¡Servidor listo!', 1.0);
        return true;
      }
      
      await Future.delayed(retryDelay);
    }
    
    onProgress?.call('Error: No se pudo conectar al servidor', 1.0);
    return false;
  }

  /// Detiene el servidor backend
  static Future<void> stopBackend() async {
    if (_backendProcess != null) {
      print('🛑 Deteniendo backend...');
      _backendProcess!.kill();
      _backendProcess = null;
    }
  }

  /// Verifica si el backend ya está corriendo externamente
  static Future<bool> isBackendAlreadyRunning() async {
    return await isBackendReady();
  }
  
  /// Configura los parámetros del servicio
  static void configure({
    String? url,
    int? retries,
    Duration? delay,
    String? exeName,
    String? endpoint,
  }) {
    if (url != null) baseUrl = url;
    if (retries != null) maxRetries = retries;
    if (delay != null) retryDelay = delay;
    if (exeName != null) backendExeName = exeName;
    if (endpoint != null) healthEndpoint = endpoint;
  }
}
