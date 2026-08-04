import 'dart:convert';
import 'dart:io';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

class DesktopWindowService {
  static const String solderPasteDisplayBusinessId = 'solder_paste_display';

  static bool get isSupported =>
      Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  static String get solderPasteDisplayArguments => jsonEncode({
        'businessId': solderPasteDisplayBusinessId,
      });

  static bool isSolderPasteDisplay(String arguments) {
    if (arguments.isEmpty) return false;
    try {
      final data = jsonDecode(arguments);
      return data is Map && data['businessId'] == solderPasteDisplayBusinessId;
    } catch (_) {
      return false;
    }
  }

  static Future<WindowController> initializeCurrentWindow() async {
    final controller = await WindowController.fromCurrentEngine();
    await controller.setWindowMethodHandler((call) async {
      switch (call.method) {
        case 'window_focus':
          await windowManager.show();
          return windowManager.focus();
        case 'window_center':
          return windowManager.center();
        case 'window_close':
          return windowManager.close();
        default:
          throw MissingPluginException(
            'Método de ventana no implementado: ${call.method}',
          );
      }
    });
    return controller;
  }

  static Future<void> openSolderPasteDisplay() async {
    if (!isSupported) {
      throw UnsupportedError(
        'La ventana de pantalla grande solo está disponible en escritorio',
      );
    }

    final windows = await WindowController.getAll();
    for (final controller in windows) {
      if (!isSolderPasteDisplay(controller.arguments)) continue;
      await controller.show();
      try {
        await controller.invokeMethod<void>('window_focus');
      } catch (_) {
        // La ventana puede seguir inicializando; show() es suficiente.
      }
      return;
    }

    final controller = await WindowController.create(
      WindowConfiguration(
        hiddenAtLaunch: true,
        arguments: solderPasteDisplayArguments,
      ),
    );
    await controller.show();
  }
}
