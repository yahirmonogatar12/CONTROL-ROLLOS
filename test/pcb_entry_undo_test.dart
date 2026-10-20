import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_warehousing_flutter/core/config/server_config.dart';
import 'package:material_warehousing_flutter/core/localization/app_translations.dart';
import 'package:material_warehousing_flutter/core/services/auth_service.dart';
import 'package:material_warehousing_flutter/screens/pcb_entrada/pcb_entrada_form_panel.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late HttpServer server;
  final deletedIds = <int>[];
  var nextId = 0;
  int? blockedId;
  var refreshes = 0;
  var completedLoads = 0;

  setUpAll(() async {
    HttpOverrides.global = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity'),
      (_) async => ['wifi'],
    );
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      Object body = {'success': true, 'data': []};
      final path = request.uri.path;
      if (path == '/api/auth/verify/1') {
        body = {'valid': true};
      } else if (path == '/api/users/1/permissions' || path == '/api/users') {
        body = [];
      } else if (path == '/api/pcb-inventory/previous-repair') {
        body = {'success': true, 'data': null};
      } else if (request.method == 'POST') {
        final payload = jsonDecode(await utf8.decoder.bind(request).join());
        if (payload['scanned_code'] == 'ERROR') {
          request.response.statusCode = 409;
          body = {'success': false, 'message': 'Entrada rechazada'};
        } else if (payload['scanned_code'] == 'GROUP') {
          body = {
            'success': true,
            'inserted_ids': [101, 102],
            'data': {'id': 101, 'pcb_part_no': 'GROUP'},
          };
        } else {
          nextId++;
          // También probar servidores que solo devuelven data.id.
          body = {
            'success': true,
            'data': {'id': nextId}
          };
        }
      } else if (request.method == 'DELETE') {
        final id = int.parse(request.uri.pathSegments.last);
        if (id == blockedId) {
          request.response.statusCode = 409;
          body = {'success': false, 'message': 'El ciclo ya tiene salida'};
        } else {
          deletedIds.add(id);
          body = {'success': true};
        }
      }
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode(body));
      await request.response.close();
      if (path == '/api/pcb-defects' || path == '/api/users') completedLoads++;
    });
    SharedPreferences.setMockInitialValues({
      'server_profiles': jsonEncode([
        {
          'id': 'test',
          'name': 'Test',
          'ip': '127.0.0.1',
          'port': server.port,
          'isActive': true,
        },
      ]),
      'active_server_id': 'test',
      'user_session': jsonEncode({
        'id': 1,
        'username': 'test',
        'departamento': 'Sistemas',
      }),
      'session_start_time': DateTime.now().millisecondsSinceEpoch,
    });
    await ServerConfig.init();
    expect(await AuthService.restoreSession(), isTrue);
  });

  tearDownAll(() async => server.close(force: true));

  setUp(() {
    nextId = 0;
    refreshes = 0;
    blockedId = null;
    deletedIds.clear();
  });

  final scan = find.byKey(const ValueKey('pcbEntryScan'));
  final undo = find.byKey(const ValueKey('pcbEntryUndo'));

  Future<void> waitFor(WidgetTester tester, bool Function() ready) async {
    for (var i = 0; i < 200; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)));
      await tester.pump();
      if (ready()) return;
    }
    fail('La operación no terminó');
  }

  Future<void> openPanel(WidgetTester tester) async {
    final previousLoads = completedLoads;
    tester.view.physicalSize = const Size(2560, 1440);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PcbEntradaFormPanel(
          languageProvider: LanguageProvider(),
          onDataSaved: () => refreshes++,
        ),
      ),
    ));
    await waitFor(tester, () => completedLoads >= previousLoads + 2);
  }

  Future<void> submit(WidgetTester tester, String code) async {
    await tester.enterText(scan, code);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await waitFor(tester,
        () => find.byType(CircularProgressIndicator).evaluate().isEmpty);
  }

  Future<void> closePanel(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 16));
  }

  testWidgets('deshace solo las diez entradas más recientes en orden inverso',
      (tester) async {
    await openPanel(tester);
    for (var i = 1; i <= 11; i++) {
      await submit(tester, 'PCB-$i');
    }
    expect(refreshes, 11);
    expect(find.text('Undo last scan (10/10)'), findsOneWidget);
    await submit(tester, 'ERROR');
    expect(find.text('Undo last scan (10/10)'), findsOneWidget);

    for (var i = 0; i < 10; i++) {
      await tester.tap(undo);
      await waitFor(tester, () => refreshes == 12 + i);
    }
    expect(deletedIds, [11, 10, 9, 8, 7, 6, 5, 4, 3, 2]);
    expect(undo, findsNothing);
    await closePanel(tester);
  });

  testWidgets(
      'conserva las entradas si falla y reintenta solo los IDs pendientes',
      (tester) async {
    await openPanel(tester);
    await submit(tester, 'PCB-1');
    await submit(tester, 'GROUP');
    blockedId = 101;
    await tester.tap(undo);
    await waitFor(tester,
        () => find.text('El ciclo ya tiene salida').evaluate().isNotEmpty);
    expect(deletedIds, [102]);
    expect(find.text('Undo last scan (2/10)'), findsOneWidget);
    expect(refreshes, 3);

    blockedId = null;
    await tester.tap(undo);
    await waitFor(tester, () => refreshes == 4);
    expect(deletedIds, [102, 101]);
    expect(find.text('Undo last scan (1/10)'), findsOneWidget);
    await tester.tap(undo);
    await waitFor(tester, () => refreshes == 5);
    expect(deletedIds, [102, 101, 1]);
    expect(undo, findsNothing);
    await closePanel(tester);
  });

  testWidgets('el historial se limpia al salir de la pantalla', (tester) async {
    await openPanel(tester);
    await submit(tester, 'PCB-1');
    expect(undo, findsOneWidget);
    await closePanel(tester);
    await openPanel(tester);
    expect(undo, findsNothing);
    expect(deletedIds, isEmpty);
    await closePanel(tester);
  });
}
