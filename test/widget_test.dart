import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_warehousing_flutter/core/localization/app_translations.dart';
import 'package:material_warehousing_flutter/screens/mobile/mobile_home_scaffold.dart';

void main() {
  testWidgets('el menú móvil protege los módulos cuando no hay sesión',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MobileHomeScaffold(
          languageProvider: LanguageProvider(),
          onLogout: () {},
        ),
      ),
    );

    expect(find.text('Sin acceso'), findsOneWidget);
    expect(
      find.byKey(const Key('mobile_check_updates_button')),
      findsOneWidget,
    );

    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('mobile_check_updates_drawer')),
      findsOneWidget,
    );
    expect(find.text('Check for updates'), findsOneWidget);
  });
}
