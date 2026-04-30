import 'dart:io';
import 'package:audioplayers/audioplayers.dart';
import 'package:vibration/vibration.dart';

/// Servicio de feedback para escaneo móvil
/// Proporciona tonos y vibración para indicar éxito/error
class FeedbackService {
  static AudioPlayer? _player;
  static bool _initialized = false;

  /// Inicializar el servicio
  static Future<void> init() async {
    if (_initialized) return;
    
    try {
      _player = AudioPlayer();
      await _player!.setReleaseMode(ReleaseMode.stop);
      _initialized = true;
    } catch (e) {
      print('FeedbackService init error: $e');
    }
  }

  /// Reproducir tono de éxito (beep corto agudo) + vibración corta
  static Future<void> playSuccess() async {
    try {
      // Vibración corta
      if (Platform.isAndroid || Platform.isIOS) {
        final hasVibrator = await Vibration.hasVibrator() ?? false;
        if (hasVibrator) {
          Vibration.vibrate(duration: 100);
        }
      }
      
      // Tono de éxito - usar beep del sistema
      if (_player != null) {
        // Generar un tono simple usando un asset o TTS beep
        await _player!.setSource(AssetSource('sounds/success.wav'));
        await _player!.resume();
      }
    } catch (e) {
      // Fallback: solo vibración
      print('FeedbackService playSuccess error: $e');
      _vibrateOnly(100);
    }
  }

  /// Reproducir tono de error (beep largo grave) + vibración doble
  static Future<void> playError() async {
    try {
      // Vibración doble
      if (Platform.isAndroid || Platform.isIOS) {
        final hasVibrator = await Vibration.hasVibrator() ?? false;
        if (hasVibrator) {
          Vibration.vibrate(pattern: [0, 200, 100, 200]);
        }
      }
      
      // Tono de error
      if (_player != null) {
        await _player!.setSource(AssetSource('sounds/error.wav'));
        await _player!.resume();
      }
    } catch (e) {
      print('FeedbackService playError error: $e');
      _vibrateOnly(300);
    }
  }

  /// Reproducir tono de duplicado (doble beep rápido) + vibración corta
  static Future<void> playDuplicate() async {
    try {
      // Vibración patrón especial
      if (Platform.isAndroid || Platform.isIOS) {
        final hasVibrator = await Vibration.hasVibrator() ?? false;
        if (hasVibrator) {
          Vibration.vibrate(pattern: [0, 50, 50, 50]);
        }
      }
      
      // Tono duplicado
      if (_player != null) {
        await _player!.setSource(AssetSource('sounds/duplicate.wav'));
        await _player!.resume();
      }
    } catch (e) {
      print('FeedbackService playDuplicate error: $e');
      _vibrateOnly(100);
    }
  }

  /// Solo vibración (fallback)
  static Future<void> _vibrateOnly(int duration) async {
    try {
      if (Platform.isAndroid || Platform.isIOS) {
        final hasVibrator = await Vibration.hasVibrator() ?? false;
        if (hasVibrator) {
          Vibration.vibrate(duration: duration);
        }
      }
    } catch (e) {
      print('Vibration error: $e');
    }
  }

  /// Vibración simple de éxito
  static Future<void> vibrateSuccess() async {
    await _vibrateOnly(100);
  }

  /// Vibración de error (doble)
  static Future<void> vibrateError() async {
    try {
      if (Platform.isAndroid || Platform.isIOS) {
        final hasVibrator = await Vibration.hasVibrator() ?? false;
        if (hasVibrator) {
          Vibration.vibrate(pattern: [0, 200, 100, 200]);
        }
      }
    } catch (e) {
      print('Vibration error: $e');
    }
  }

  /// Liberar recursos
  static void dispose() {
    _player?.dispose();
    _player = null;
    _initialized = false;
  }
}
