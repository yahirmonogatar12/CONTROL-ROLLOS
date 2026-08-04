import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_warehousing_flutter/core/localization/app_translations.dart';
import 'package:material_warehousing_flutter/screens/solder_paste/solder_paste_screen.dart';

void main() {
  testWidgets(
      'muestra los apartados operativo y de consulta sin modificar datos',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SolderPasteScreen(
            languageProvider: LanguageProvider(),
            enableBackgroundTasks: false,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Proceso y seguimiento'), findsOneWidget);
    expect(find.text('Consultar estatus'), findsOneWidget);
    expect(find.text('Escanear pasta de soldadura'), findsOneWidget);
    expect(find.byType(Switch), findsNothing);
    final fifoCheckbox = find.byKey(
      const ValueKey('solderPasteFifoCheckbox'),
    );
    expect(fifoCheckbox, findsOneWidget);
    expect(tester.widget<Checkbox>(fifoCheckbox).value, isTrue);
    expect(find.text('FIFO de Almacén activado'), findsNothing);

    await tester.tap(find.text('Consultar estatus'));
    await tester.pumpAndSettle();

    expect(find.text('Consultar estatus por etiqueta'), findsOneWidget);
    expect(find.textContaining('solo lectura'), findsOneWidget);
  });
}
