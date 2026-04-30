import 'package:shared_preferences/shared_preferences.dart';

/// Modos de escaneo disponibles
enum ScannerMode {
  camera,   // Usa la cámara del dispositivo
  reader,   // Usa escáner externo (PDA, pistola, etc.)
}

/// Servicio de configuración del escáner
/// Permite configurar si usar cámara o lector externo (PDA)
class ScannerConfigService {
  static const String _scannerModeKey = 'scanner_mode';
  
  static ScannerMode _currentMode = ScannerMode.camera;
  static bool _initialized = false;
  
  /// Modo actual de escaneo
  static ScannerMode get currentMode => _currentMode;
  
  /// Verifica si está en modo cámara
  static bool get isCameraMode => _currentMode == ScannerMode.camera;
  
  /// Verifica si está en modo lector/PDA
  static bool get isReaderMode => _currentMode == ScannerMode.reader;
  
  /// Inicializa el servicio cargando la configuración guardada
  static Future<void> init() async {
    if (_initialized) return;
    
    try {
      final prefs = await SharedPreferences.getInstance();
      final modeIndex = prefs.getInt(_scannerModeKey) ?? 0;
      _currentMode = ScannerMode.values[modeIndex];
      _initialized = true;
    } catch (e) {
      print('Error loading scanner config: $e');
      _currentMode = ScannerMode.camera;
      _initialized = true;
    }
  }
  
  /// Cambia el modo de escaneo y guarda la configuración
  static Future<void> setMode(ScannerMode mode) async {
    _currentMode = mode;
    
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_scannerModeKey, mode.index);
    } catch (e) {
      print('Error saving scanner config: $e');
    }
  }
  
  /// Alterna entre modo cámara y lector
  static Future<void> toggleMode() async {
    final newMode = _currentMode == ScannerMode.camera 
        ? ScannerMode.reader 
        : ScannerMode.camera;
    await setMode(newMode);
  }
  
  /// Obtiene el nombre legible del modo actual
  static String getModeName({bool spanish = false}) {
    if (spanish) {
      return _currentMode == ScannerMode.camera ? 'Cámara' : 'Lector/PDA';
    }
    return _currentMode == ScannerMode.camera ? 'Camera' : 'Reader/PDA';
  }
}
