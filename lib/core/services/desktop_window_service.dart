import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/services.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:window_manager/window_manager.dart';

class DesktopWindowService {
  static const String solderPasteDisplayBusinessId = 'solder_paste_display';
  static Completer<void>? _currentWindowReady;

  static bool get isSupported =>
      Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  static String solderPasteDisplayArguments(Display display) => jsonEncode({
        'businessId': solderPasteDisplayBusinessId,
        'display': displayArguments(display),
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
    if (isSolderPasteDisplay(controller.arguments)) {
      _currentWindowReady = Completer<void>();
    }
    await controller.setWindowMethodHandler((call) async {
      switch (call.method) {
        case 'window_focus':
          await windowManager.show();
          return windowManager.focus();
        case 'window_open_on_display':
          await _currentWindowReady?.future;
          await openCurrentWindowOnDisplay(call.arguments);
          return;
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

  static void markCurrentWindowReady() {
    final ready = _currentWindowReady;
    if (ready != null && !ready.isCompleted) ready.complete();
  }

  /// Abre el monitor en la primera pantalla que no sea la principal.
  /// Regresa `true` cuando sí se encontró una pantalla secundaria.
  static Future<bool> openSolderPasteDisplay() async {
    if (!isSupported) {
      throw UnsupportedError(
        'La ventana de pantalla grande solo está disponible en escritorio',
      );
    }

    final displays = await screenRetriever.getAllDisplays();
    final primaryDisplay = await screenRetriever.getPrimaryDisplay();
    final targetDisplay = selectTargetDisplay(displays, primaryDisplay);
    final openedOnSecondary = targetDisplay.id != primaryDisplay.id;

    final windows = await WindowController.getAll();
    for (final controller in windows) {
      if (!isSolderPasteDisplay(controller.arguments)) continue;
      await _showOnDisplay(controller, targetDisplay);
      return openedOnSecondary;
    }

    final controller = await WindowController.create(
      WindowConfiguration(
        hiddenAtLaunch: true,
        arguments: solderPasteDisplayArguments(targetDisplay),
      ),
    );
    await _showOnDisplay(controller, targetDisplay);
    return openedOnSecondary;
  }

  static Display selectTargetDisplay(
    List<Display> displays,
    Display primaryDisplay,
  ) {
    for (final display in displays) {
      if (display.id != primaryDisplay.id) return display;
    }
    return primaryDisplay;
  }

  static Map<String, double> displayArguments(Display display) {
    final position = display.visiblePosition ?? Offset.zero;
    final size = display.visibleSize ?? display.size;
    return {
      'left': position.dx,
      'top': position.dy,
      'width': size.width,
      'height': size.height,
    };
  }

  static Future<void> openCurrentWindowFromArguments(String arguments) async {
    if (arguments.isEmpty) return;
    final data = jsonDecode(arguments);
    if (data is! Map) return;
    final display = data['display'];
    if (display is Map) {
      await openCurrentWindowOnDisplay(display);
    }
  }

  static Future<void> openCurrentWindowOnDisplay(Object? arguments) async {
    if (arguments is! Map) {
      throw const FormatException('No se recibieron datos de la pantalla');
    }

    double value(String key) {
      final raw = arguments[key];
      if (raw is num) return raw.toDouble();
      throw FormatException('Dato de pantalla inválido: $key');
    }

    final bounds = Rect.fromLTWH(
      value('left'),
      value('top'),
      value('width'),
      value('height'),
    );
    await windowManager.setFullScreen(false);
    await windowManager.setBounds(bounds);
    await windowManager.setFullScreen(true);
    await windowManager.show();
    await windowManager.focus();
  }

  static Future<void> _showOnDisplay(
    WindowController controller,
    Display display,
  ) async {
    final arguments = displayArguments(display);
    Object? lastError;

    // Una ventana recién creada tarda unos instantes en registrar su canal.
    // Reintentar evita mostrarla primero en el monitor equivocado.
    for (var attempt = 0; attempt < 20; attempt++) {
      try {
        await controller.invokeMethod<void>(
          'window_open_on_display',
          arguments,
        );
        return;
      } catch (error) {
        lastError = error;
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    }

    await controller.show();
    throw StateError(
      'La ventana abrió, pero no pudo colocarse en la segunda pantalla: '
      '$lastError',
    );
  }
}
