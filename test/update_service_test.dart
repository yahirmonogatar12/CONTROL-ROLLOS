import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_warehousing_flutter/core/services/update_service.dart';

void main() {
  testWidgets('el aviso automático de PC permite actualizar más tarde',
      (tester) async {
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (value) {
            context = value;
            return const Scaffold();
          },
        ),
      ),
    );

    final dialog = UpdateService.showUpdateDialog(
      context,
      UpdateInfo(
        updateAvailable: true,
        currentVersion: '2.2.0',
        latestVersion: '2.2.1',
        isMandatory: true,
      ),
      enforceMandatory: false,
    );
    await tester.pumpAndSettle();

    expect(find.text('¡Nueva Versión Disponible!'), findsOneWidget);
    expect(find.text('Más tarde'), findsOneWidget);
    expect(
      find.text(
        'Esta actualización es obligatoria para continuar usando la aplicación.',
      ),
      findsNothing,
    );

    await tester.tap(find.text('Más tarde'));
    await tester.pumpAndSettle();
    await dialog;
  });

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

  group('UpdateService.pickLatestAndroidApk', () {
    test('elige el APK con la versión semántica más alta', () {
      final best = UpdateService.pickLatestAndroidApk([
        'Control_inventario_SMD_v1.2.9.apk',
        'app-release-1.10.0.apk',
        'Control_inventario_SMD_v1.3.0.apk',
        'app-release.apk',
        'notas.txt',
      ]);

      expect(best?.fileName, 'app-release-1.10.0.apk');
      expect(best?.version, '1.10.0');
    });

    test('regresa null si ningún APK contiene versión', () {
      expect(
        UpdateService.pickLatestAndroidApk([
          'app-release.apk',
          'archivo.exe',
        ]),
        isNull,
      );
    });

    test('construye la ruta relativa dentro del recurso updates', () {
      expect(
        AndroidUpdateShareConfig.remotePath(
          'Control_inventario_SMD_v1.2.3.apk',
        ),
        '/updates/SMT/ANDROID/Control_inventario_SMD_v1.2.3.apk',
      );
    });

    test('no intenta abrir una ruta SMB en el navegador', () {
      expect(
        UpdateService.canOpenDownloadUrl(
          'smb://192.168.1.10/updates/SMT/ANDROID/app-v1.2.3.apk',
        ),
        isFalse,
      );
      expect(
        UpdateService.canOpenDownloadUrl('https://example.test/app.apk'),
        isTrue,
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
