import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_warehousing_flutter/core/config/server_config.dart';
import 'package:material_warehousing_flutter/core/widgets/server_config_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await ServerConfig.clearAll();
    await ServerConfig.init();
  });

  testWidgets('permite editar y guardar el servidor sin configurar FCM',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(width: 440, child: ServerConfigWidget()),
          ),
        ),
      ),
    );

    await tester.tap(find.textContaining('Servidor:'));
    await tester.pump();
    expect(find.byTooltip('Editar servidor'), findsOneWidget);

    await tester.tap(find.byTooltip('Editar servidor'));
    await tester.pump();
    expect(find.text('Editar servidor'), findsOneWidget);

    final fields = find.byType(TextField);
    expect(fields, findsAtLeastNWidgets(3));
    await tester.enterText(fields.at(1), '10.20.30.40');

    final saveButton = find.widgetWithText(ElevatedButton, 'Guardar');
    await tester.ensureVisible(saveButton);
    await tester.tap(saveButton);
    await tester.pump();

    expect(ServerConfig.activeServer?.ip, '10.20.30.40');
    expect(find.text('Editar servidor'), findsNothing);
    expect(find.text('Configuración del servidor guardada'), findsOneWidget);
  });
}
