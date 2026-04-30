import 'dart:async';
import 'dart:io';
import 'package:http/http.dart' as http;

class BackendService {
  static Process? _backendProcess;
  static const String baseUrl = 'http://localhost:3010';
  static const int maxRetries = 30; // 30 intentos
  static const Duration retryDelay = Duration(milliseconds: 500); // 500ms entre intentos
  static const String backendExeName = 'backend-server.exe';

  /// Inicia el servidor backend
  static Future<bool> startBackend() async {
    try {
      // Obtener el directorio del ejecutable
      final exeDir = File(Platform.resolvedExecutable).parent.path;
      
      String? backendExePath;
      String? workingDirectory;
      bool useNodeJs = false;
      
      // Opción 1: Backend compilado junto al ejecutable (distribución)
      final prodExePath = '$exeDir\\$backendExeName';
      if (await File(prodExePath).exists()) {
        backendExePath = prodExePath;
        workingDirectory = exeDir;
        print('📦 Usando backend compilado: $prodExePath');
      }
      
      // Opción 2: En desarrollo (usar node server.js)
      if (backendExePath == null) {
        final devPath = '${Directory.current.path}\\backend';
        if (await Directory(devPath).exists() && await File('$devPath\\server.js').exists()) {
          // Verificar si Node.js está instalado
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
        Uri.parse('$baseUrl/api/health'),
      ).timeout(const Duration(seconds: 2));
      
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
}
