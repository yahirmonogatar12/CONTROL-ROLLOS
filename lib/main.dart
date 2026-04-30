import 'dart:async';
import 'dart:io';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'package:material_warehousing_flutter/app.dart';
import 'package:material_warehousing_flutter/core/config/server_config.dart';
import 'package:material_warehousing_flutter/core/config/print_server_config.dart';
import 'package:material_warehousing_flutter/core/services/printer_service.dart';
import 'package:material_warehousing_flutter/core/services/mobile_printer_service.dart';
import 'package:material_warehousing_flutter/core/services/scanner_config_service.dart';
import 'package:material_warehousing_flutter/core/services/update_service.dart';
import 'package:material_warehousing_flutter/core/services/fcm_service.dart';
import 'package:material_warehousing_flutter/firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Inicializar configuración de servidor (antes de cualquier llamada API)
  await ServerConfig.init();

  // Inicializar configuración de servidor de impresión (separado del API)
  await PrintServerConfig.init();

  // Inicializar servicios
  await PrinterService.init();

  // Cargar versión actual de la app
  await UpdateService.loadCurrentVersion();

  // En Windows/Desktop, usar window_manager para control de ventana
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    await _initDesktopWindow();
    runApp(const MesTabsApp());
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _showDesktopWindow();
    });
  } else {
    // En Android/iOS, inicializar servicios móviles
    await MobilePrinterService.init();
    await ScannerConfigService.init();
    if (Platform.isAndroid && Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    }
    runApp(const MesTabsApp());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_initializeMobileFcm());
    });
  }
}

Future<void> _initializeMobileFcm() async {
  try {
    await FCMService.instance.init();
  } catch (e) {
    debugPrint('FCM init skipped: $e');
  }
}

/// Inicializar ventana en Desktop (Windows/Linux/macOS)
Future<void> _initDesktopWindow() async {
  await windowManager.ensureInitialized();
  await windowManager.setPreventClose(false);

  const windowOptions = WindowOptions(
    minimumSize: Size(1500, 750),
    size: Size(1500, 750),
    center: true,
    backgroundColor: Color(0xFF1A1E2C),
    skipTaskbar: false,
    titleBarStyle: TitleBarStyle.normal,
  );

  await windowManager.waitUntilReadyToShow(windowOptions, () async {});
}

/// Mostrar ventana en Desktop después del primer frame
Future<void> _showDesktopWindow() async {
  await Future.delayed(const Duration(milliseconds: 100));
  await windowManager.show();
  await windowManager.maximize();
  await windowManager.focus();
}
