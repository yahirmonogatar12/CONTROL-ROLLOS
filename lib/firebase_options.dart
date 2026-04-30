import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;

/// Configuracion explicita de Firebase para Android.
/// Evita depender solo del autoload nativo cuando FCM arranca antes de tiempo.
class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      throw UnsupportedError(
        'FirebaseOptions no esta configurado para Web en esta app.',
      );
    }

    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
      case TargetPlatform.macOS:
      case TargetPlatform.windows:
      case TargetPlatform.linux:
      case TargetPlatform.fuchsia:
        throw UnsupportedError(
          'FirebaseOptions no esta configurado para esta plataforma.',
        );
    }
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyC820aUW7B9mWsht4CFW4UeREgxsGtyIoo',
    appId: '1:774858544239:android:0a68cd99151eb03966e99a',
    messagingSenderId: '774858544239',
    projectId: 'ilsan-mes-fcm',
    storageBucket: 'ilsan-mes-fcm.firebasestorage.app',
  );
}
