import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_warehousing_flutter/core/widgets/column_filter.dart';

void main() {
  group('ColumnFilter.matches', () {
    test('sin filtro deja pasar todo', () {
      expect(ColumnFilter.matches('lo que sea', null), isTrue);
      expect(ColumnFilter.matches('', null), isTrue);
    });

    test('un valor concreto compara exacto', () {
      expect(ColumnFilter.matches('EAX65150407', 'EAX65150407'), isTrue);
      expect(ColumnFilter.matches('EAX65150408', 'EAX65150407'), isFalse);
      // Sin coincidencia parcial: elegir un valor de la lista no debe arrastrar
      // a sus parecidos.
      expect(ColumnFilter.matches('EAX65150407-1.0', 'EAX65150407'), isFalse);
    });

    test('(Non blanks) deja solo las filas con dato', () {
      expect(ColumnFilter.matches('A24', ColumnFilter.nonBlanks), isTrue);
      expect(ColumnFilter.matches('', ColumnFilter.nonBlanks), isFalse);
      expect(ColumnFilter.matches('   ', ColumnFilter.nonBlanks), isFalse);
    });

    test('(Blanks) deja solo las vacias', () {
      expect(ColumnFilter.matches('', ColumnFilter.blanks), isTrue);
      expect(ColumnFilter.matches('   ', ColumnFilter.blanks), isTrue);
      expect(ColumnFilter.matches('A24', ColumnFilter.blanks), isFalse);
    });
  });

  group('ColumnFilterResult', () {
    test('distingue limpiar el filtro de cerrar sin elegir', () {
      // Ambos llevan filter == null, pero solo uno debe aplicarse: si se
      // confunden, cerrar con Esc borraria el filtro puesto.
      const limpiar = ColumnFilterResult(null);
      const cerrar = ColumnFilterResult.unchanged();
      expect(limpiar.changed, isTrue);
      expect(limpiar.filter, isNull);
      expect(cerrar.changed, isFalse);
    });
  });

  testWidgets('el desplegable busca y devuelve el valor elegido',
      (tester) async {
    final anchor = GlobalKey();
    ColumnFilterResult? result;

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            key: anchor,
            onPressed: () async {
              result = await ColumnFilter.show(
                context: context,
                anchorKey: anchor,
                values: const ['A24', 'B12', 'F41', ''],
              );
            },
            child: const Text('abrir'),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();

    // Los tres valores con dato, mas (Blanks) porque la columna trae vacios.
    expect(find.text('A24'), findsOneWidget);
    expect(find.text('(Blanks)'), findsOneWidget);
    expect(find.text('(Non blanks)'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'b1');
    await tester.pumpAndSettle();
    expect(find.text('B12'), findsOneWidget);
    expect(find.text('A24'), findsNothing);

    await tester.tap(find.text('B12'));
    await tester.pumpAndSettle();

    expect(result?.changed, isTrue);
    expect(result?.filter, 'B12');
  });
}
