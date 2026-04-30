import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Utilidades para detectar la plataforma y adaptar la UI
class PlatformUtils {
  /// Determina si estamos en un dispositivo móvil (Android o iOS)
  static bool get isMobile {
    if (kIsWeb) return false;
    return Platform.isAndroid || Platform.isIOS;
  }

  /// Determina si estamos en desktop (Windows, Linux, macOS)
  static bool get isDesktop {
    if (kIsWeb) return false;
    return Platform.isWindows || Platform.isLinux || Platform.isMacOS;
  }

  /// Determina si estamos en Android
  static bool get isAndroid {
    if (kIsWeb) return false;
    return Platform.isAndroid;
  }

  /// Determina si estamos en iOS
  static bool get isIOS {
    if (kIsWeb) return false;
    return Platform.isIOS;
  }

  /// Determina si estamos en Windows
  static bool get isWindows {
    if (kIsWeb) return false;
    return Platform.isWindows;
  }

  /// Determina si estamos en web
  static bool get isWeb => kIsWeb;

  /// Obtiene el nombre de la plataforma actual
  static String get platformName {
    if (kIsWeb) return 'Web';
    if (Platform.isAndroid) return 'Android';
    if (Platform.isIOS) return 'iOS';
    if (Platform.isWindows) return 'Windows';
    if (Platform.isLinux) return 'Linux';
    if (Platform.isMacOS) return 'macOS';
    return 'Unknown';
  }

  /// Determina si la app debe usar layout móvil
  /// Basado en plataforma y tamaño de pantalla
  static bool shouldUseMobileLayout(double screenWidth) {
    // Siempre usar móvil layout en Android/iOS
    if (isMobile) return true;
    
    // En desktop, podría usarse para tablets o pantallas pequeñas
    // Por ahora, siempre usar desktop layout en desktop
    return false;
  }

  /// Tamaño mínimo para considerar desktop layout
  static const double desktopBreakpoint = 800;

  /// Determina si soporta cámara para escaneo de códigos
  static bool get supportsCameraScanning {
    // Solo soportado en móviles por ahora
    return isMobile;
  }

  /// Determina si soporta window manager
  static bool get supportsWindowManager {
    return isDesktop;
  }
}

/// Extensión para adaptaciones de UI por plataforma
extension PlatformContext on BuildContext {
  // Esto se puede extender para acceder fácilmente a info de plataforma desde BuildContext
}
