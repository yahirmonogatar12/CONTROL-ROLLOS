import 'package:flutter_test/flutter_test.dart';
import 'package:material_warehousing_flutter/core/constants/pcb_areas.dart';

void main() {
  group('PcbAreas', () {
    test('exposes the three persisted area values', () {
      expect(PcbAreas.values, [
        PcbAreas.inventory,
        PcbAreas.inventoryRepair,
        PcbAreas.repair,
      ]);
    });

    test('uses business labels without changing persisted values', () {
      expect(PcbAreas.label(PcbAreas.inventory), 'INVENTARIO OK');
      expect(
        PcbAreas.label(PcbAreas.inventoryRepair),
        'INVENTARIO REPARACION',
      );
      expect(PcbAreas.label(PcbAreas.repair), 'REPARACION');
    });

    test('treats both repair inventories as repair areas', () {
      expect(PcbAreas.isRepair(PcbAreas.inventory), isFalse);
      expect(PcbAreas.isRepair(PcbAreas.inventoryRepair), isTrue);
      expect(PcbAreas.isRepair(PcbAreas.repair), isTrue);
    });
  });
}
