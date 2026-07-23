import 'package:flutter_test/flutter_test.dart';
import 'package:material_warehousing_flutter/core/services/update_service.dart';

void main() {
  group('UpdateInfo.fromGitHub', () {
    test('detecta una versión más reciente y usa el asset ejecutable', () {
      final info = UpdateInfo.fromGitHub(
        {
          'tag_name': 'v1.3.3',
          'prerelease': false,
          'assets': [
            {
              'name': 'Control_inventario_SMD_Setup_v1.3.3.exe',
              'browser_download_url': 'https://example.test/setup.exe',
            },
          ],
        },
        '1.3.2',
      );

      expect(info.updateAvailable, isTrue);
      expect(info.latestVersion, '1.3.3');
      expect(info.downloadUrl, 'https://example.test/setup.exe');
    });

    test('construye un enlace de instalador y nunca usa html_url como exe', () {
      final info = UpdateInfo.fromGitHub(
        {
          'tag_name': 'v1.3.3',
          'html_url': 'https://example.test/release-page',
          'prerelease': false,
          'assets': <Map<String, dynamic>>[],
        },
        '1.3.2',
      );

      expect(
        info.downloadUrl,
        'https://github.com/yahirmonogatar12/CONTROL-ROLLOS/releases/download/v1.3.3/Control_inventario_SMD_Setup_v1.3.3.exe',
      );
    });

    test('no ofrece actualización cuando la versión instalada es mayor', () {
      final info = UpdateInfo.fromGitHub(
        {
          'tag_name': 'v1.3.3',
          'prerelease': false,
          'assets': <Map<String, dynamic>>[],
        },
        '1.3.4',
      );

      expect(info.updateAvailable, isFalse);
    });
  });

  group('UpdateService.pickLatestInstallerVersion', () {
    test('elige la versión más alta e ignora archivos ajenos', () {
      final best = UpdateService.pickLatestInstallerVersion([
        'Control_inventario_SMD_Setup_v1.3.1.exe',
        'Control_inventario_SMD_Setup_v1.3.10.exe', // 10 > 2, no orden textual
        'Control_inventario_SMD_Setup_v1.3.2.exe',
        'notas.txt',
        'otro_instalador.exe',
      ]);

      expect(best, '1.3.10');
    });

    test('regresa null cuando no hay instaladores', () {
      expect(
        UpdateService.pickLatestInstallerVersion(['readme.md', 'foo.exe']),
        isNull,
      );
    });
  });

  group('UpdateService.parseEnvContent', () {
    test('lee valores con comillas, espacios y caracteres especiales', () {
      final values = UpdateService.parseEnvContent('''
        # comentario
        UPDATE_SHARE_USERNAME = operador
        UPDATE_SHARE_PASSWORD="p@ss word#2026"
        UPDATE_SHARE_DOMAIN='PLANTA'
        INVALID_LINE
      ''');

      expect(values['UPDATE_SHARE_USERNAME'], 'operador');
      expect(values['UPDATE_SHARE_PASSWORD'], 'p@ss word#2026');
      expect(values['UPDATE_SHARE_DOMAIN'], 'PLANTA');
      expect(values.containsKey('INVALID_LINE'), isFalse);
    });

    test('obtiene la raíz SMB a partir de la subcarpeta de instaladores', () {
      expect(UpdateShareConfig.shareRoot, r'\\192.168.1.10\updates');
    });
  });
}
