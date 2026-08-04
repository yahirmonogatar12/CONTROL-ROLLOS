import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:material_warehousing_flutter/core/config/server_config.dart';

/// Mantiene en Android un monitor contra el backend de la red local.
/// No usa Firebase, el servidor central ni una conexión a Internet.
class SolderPasteLocalNotificationService {
  static const MethodChannel _channel = MethodChannel(
    'control_inventario_smd/local_solder_paste_notifications',
  );

  static Future<bool> configure({ServerProfile? server}) async {
    if (kIsWeb || !Platform.isAndroid) return false;

    final selectedServer = server ?? ServerConfig.activeServer;
    if (selectedServer == null) return false;

    try {
      return await _channel.invokeMethod<bool>('configure', {
            'baseUrl': selectedServer.baseUrl,
          }) ??
          false;
    } on PlatformException catch (error) {
      debugPrint(
        '[Control de pasta local] No se pudo iniciar el monitor: '
        '${error.message}',
      );
      return false;
    }
  }

  static Future<void> stop() async {
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('stop');
    } on PlatformException catch (error) {
      debugPrint(
        '[Control de pasta local] No se pudo detener el monitor: '
        '${error.message}',
      );
    }
  }
}
