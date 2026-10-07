// Paso de UI del E2E "Metal Mask por lado". Lo lanza
// ESCANEO_INPUT/backend/test/mask-lado-e2e.check.js con el backend REAL de
// este repo escuchando en TOOLING_E2E_PORT; sin ese puerto se salta.
//
// La pantalla de herramentales habla por HTTP de verdad con ese backend:
// planeacion elige la fila, abre "Editar", escoge el lado y guarda, y da de
// alta una mask nueva con "Nuevo".

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_warehousing_flutter/core/config/server_config.dart';
import 'package:material_warehousing_flutter/core/localization/app_translations.dart';
import 'package:material_warehousing_flutter/screens/tooling/tooling_control_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

const puerto = int.fromEnvironment('TOOLING_E2E_PORT');

void main() {
  setUpAll(() async {
    // flutter_test bloquea la red por defecto: aqui se quiere la de verdad.
    HttpOverrides.global = null;
    // El cliente del backend pregunta por la red antes de cada llamada.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity'),
      (_) async => ['wifi'],
    );
    SharedPreferences.setMockInitialValues({
      'server_profiles': jsonEncode([
        {'id': 'e2e', 'name': 'E2E', 'ip': '127.0.0.1', 'port': puerto, 'isActive': true},
      ]),
      'active_server_id': 'e2e',
    });
    await ServerConfig.init();
  });

  /// Deja correr la red real (fuera del reloj falso) hasta que [listo].
  Future<void> esperar(WidgetTester tester, bool Function() listo, String que) async {
    for (var i = 0; i < 200; i++) {
      if (listo()) return;
      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 50)));
      await tester.pump(const Duration(milliseconds: 50));
    }
    fail('timeout esperando: $que');
  }

  /// Abre el dropdown "Lado" del dialogo (muestra [actual]) y elige [lado].
  Future<void> elegirLado(WidgetTester tester, String actual, String lado) async {
    await tester.tap(find.text(actual));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text(lado).last);
    await tester.pump(const Duration(milliseconds: 400));
  }

  /// Celda "Lado" de [codigo] tal como se ve en el grid (va despues del No
  /// PCB). null si la fila aun no esta.
  String? ladoEnGrid(WidgetTester tester, String codigo) {
    // Solo en el grid: con el dialogo de alta abierto, el codigo tambien esta
    // escrito en su campo.
    final celda = find.descendant(of: find.byType(ListView), matching: find.text(codigo));
    if (celda.evaluate().isEmpty) return null;
    final fila = find.ancestor(of: celda, matching: find.byType(Row)).first;
    final textos = tester
        .widgetList<Text>(find.descendant(of: fila, matching: find.byType(Text)))
        .map((t) => t.data ?? '')
        .toList();
    return textos[textos.indexOf('EAX99120001') + 1];
  }

  /// Guarda el dialogo y espera a que el grid recargado muestre [lado].
  Future<void> guardar(WidgetTester tester, String boton, String codigo, String lado) async {
    await tester.tap(find.widgetWithText(ElevatedButton, boton));
    await esperar(tester, () => ladoEnGrid(tester, codigo) == lado, '$codigo en $lado');
  }

  testWidgets('planeacion define el lado de las masks desde la pantalla', (tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    // La fuente de flutter_test dibuja cada letra como un cuadro ancho: los
    // filtros de ancho fijo de la barra se desbordan aqui y no en la planta.
    final reportar = FlutterError.onError;
    FlutterError.onError = (detalle) {
      if (detalle.exceptionAsString().contains('overflowed')) return;
      reportar?.call(detalle);
    };

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: ToolingControlScreen(languageProvider: LanguageProvider())),
    ));
    await esperar(tester, () => find.text('MM9-1-001').evaluate().isNotEmpty, 'catalogo');
    expect(ladoEnGrid(tester, 'MM9-1-001'), '-', reason: 'del Excel llega sin lado');

    // Editar MM9-1-001 -> BOT.
    await tester.tap(find.text('MM9-1-001'));
    await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 200)));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.widgetWithText(ElevatedButton, 'Editar'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Editar MM9-1-001'), findsOneWidget);
    await elegirLado(tester, 'Sin definir', 'BOT');
    await guardar(tester, 'Guardar', 'MM9-1-001', 'BOT');

    // Editar MM9-2-001 -> TOP.
    await tester.tap(find.text('MM9-2-001'));
    await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 200)));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.widgetWithText(ElevatedButton, 'Editar'));
    await tester.pump(const Duration(milliseconds: 400));
    await elegirLado(tester, 'Sin definir', 'TOP');
    await guardar(tester, 'Guardar', 'MM9-2-001', 'TOP');

    // Alta de una mask nueva ya con su lado.
    await tester.tap(find.widgetWithText(ElevatedButton, 'Nuevo'));
    await tester.pump(const Duration(milliseconds: 400));
    final campos = find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField));
    await tester.enterText(campos.at(0), 'MM9-3-001'); // No control
    await tester.enterText(campos.at(2), 'EAX99120001-1.0'); // No PCB
    await tester.enterText(campos.at(5), '4'); // Array
    await elegirLado(tester, 'Sin definir', 'BOT');
    await guardar(tester, 'Registrar', 'MM9-3-001', 'BOT');

    // El HttpClient deja la conexion viva 15 s en el reloj falso: se cierra.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 16));
    FlutterError.onError = reportar; // flutter_test exige dejarlo como estaba
  }, skip: puerto == 0);
}
