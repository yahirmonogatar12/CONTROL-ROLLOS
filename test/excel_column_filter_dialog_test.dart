import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_warehousing_flutter/core/widgets/excel_column_filter_dialog.dart';

void main() {
  testWidgets('filters the value list and returns checked values',
      (tester) async {
    ExcelColumnFilterResult? result;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                result = await showDialog<ExcelColumnFilterResult>(
                  context: context,
                  builder: (_) => const ExcelColumnFilterDialog(
                    columnLabel: 'Ubicación',
                    values: ['A-01', 'A-02', 'B-01'],
                    selectedValues: {'A-01', 'A-02', 'B-01'},
                    hasActiveFilter: false,
                    currentSortAscending: null,
                    sortAscendingLabel: 'Ordenar de A a Z',
                    sortDescendingLabel: 'Ordenar de Z a A',
                    clearFilterLabel: 'Limpiar filtro',
                    searchLabel: 'Buscar',
                    selectAllLabel: 'Seleccionar todo',
                    emptyValueLabel: '(Vacíos)',
                    applyLabel: 'Aplicar',
                    cancelLabel: 'Cancelar',
                    noValuesLabel: 'Sin datos',
                  ),
                );
              },
              child: const Text('Abrir'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Abrir'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'A-02');
    await tester.pump();

    expect(find.text('A-01'), findsNothing);
    expect(
      find.widgetWithText(CheckboxListTile, 'A-02'),
      findsOneWidget,
    );
    expect(find.text('B-01'), findsNothing);

    await tester.tap(find.widgetWithText(CheckboxListTile, 'A-02'));
    await tester.pump();
    await tester.tap(find.text('Aplicar'));
    await tester.pumpAndSettle();

    expect(result?.action, ExcelColumnFilterAction.apply);
    expect(result?.selectedValues, {'A-01', 'B-01'});
  });

  testWidgets('select all toggles only values visible in the search',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ExcelColumnFilterDialog(
            columnLabel: 'Ubicación',
            values: ['A-01', 'A-02', 'B-01'],
            selectedValues: {},
            hasActiveFilter: true,
            currentSortAscending: null,
            sortAscendingLabel: 'Ordenar de A a Z',
            sortDescendingLabel: 'Ordenar de Z a A',
            clearFilterLabel: 'Limpiar filtro',
            searchLabel: 'Buscar',
            selectAllLabel: 'Seleccionar todo',
            emptyValueLabel: '(Vacíos)',
            applyLabel: 'Aplicar',
            cancelLabel: 'Cancelar',
            noValuesLabel: 'Sin datos',
          ),
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), 'A-');
    await tester.pump();
    await tester.tap(find.text('(Seleccionar todo)'));
    await tester.pump();

    final a01 = tester.widget<CheckboxListTile>(
      find.widgetWithText(CheckboxListTile, 'A-01'),
    );
    final a02 = tester.widget<CheckboxListTile>(
      find.widgetWithText(CheckboxListTile, 'A-02'),
    );

    expect(a01.value, isTrue);
    expect(a02.value, isTrue);
  });
}
