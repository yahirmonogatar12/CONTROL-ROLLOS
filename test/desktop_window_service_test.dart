import 'dart:convert';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_warehousing_flutter/core/services/desktop_window_service.dart';
import 'package:screen_retriever/screen_retriever.dart';

void main() {
  const primary = Display(
    id: 'primary',
    name: 'Pantalla 1',
    size: Size(1920, 1080),
    visiblePosition: Offset.zero,
    visibleSize: Size(1920, 1040),
  );
  const secondary = Display(
    id: 'secondary',
    name: 'Pantalla 2',
    size: Size(2560, 1440),
    visiblePosition: Offset(1920, 0),
    visibleSize: Size(2560, 1400),
  );

  test('elige una pantalla distinta de la principal', () {
    final selected = DesktopWindowService.selectTargetDisplay(
      const [primary, secondary],
      primary,
    );

    expect(selected.id, secondary.id);
  });

  test('usa la pantalla principal cuando no hay una segunda pantalla', () {
    final selected = DesktopWindowService.selectTargetDisplay(
      const [primary],
      primary,
    );

    expect(selected.id, primary.id);
  });

  test('envía la posición y tamaño visibles de la segunda pantalla', () {
    final encoded = DesktopWindowService.solderPasteDisplayArguments(
      secondary,
    );
    final data = jsonDecode(encoded) as Map<String, dynamic>;

    expect(
      data['businessId'],
      DesktopWindowService.solderPasteDisplayBusinessId,
    );
    expect(data['display'], {
      'left': 1920.0,
      'top': 0.0,
      'width': 2560.0,
      'height': 1400.0,
    });
    expect(DesktopWindowService.isSolderPasteDisplay(encoded), isTrue);
  });
}
