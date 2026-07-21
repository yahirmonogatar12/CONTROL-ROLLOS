import 'dart:io';

class FileOpener {
  static Future<void> openInDefaultApp(String path) async {
    try {
      if (Platform.isWindows) {
        await Process.run(
          'cmd',
          ['/c', 'start', '', path],
          runInShell: true,
        );
      } else if (Platform.isMacOS) {
        await Process.run('open', [path]);
      } else if (Platform.isLinux) {
        await Process.run('xdg-open', [path]);
      }
    } catch (_) {
      // El archivo ya fue guardado; abrirlo es una mejora no bloqueante.
    }
  }
}
