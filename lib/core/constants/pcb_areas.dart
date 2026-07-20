abstract final class PcbAreas {
  static const String inventory = 'INVENTARIO';
  static const String inventoryRepair = 'INVENTARIO_REPARACION';
  static const String repair = 'REPARACION';

  static const List<String> values = [
    inventory,
    inventoryRepair,
    repair,
  ];

  static const List<String> filterValues = [
    'ALL',
    ...values,
  ];

  static bool isRepair(String? area) =>
      area == inventoryRepair || area == repair;

  static String label(Object? area) {
    switch (area?.toString()) {
      case inventory:
        return 'INVENTARIO OK';
      case inventoryRepair:
        return 'INVENTARIO REPARACION';
      case repair:
        return 'REPARACION';
      default:
        return area?.toString() ?? '';
    }
  }

  static Map<String, dynamic> withDisplayArea(Map<String, dynamic> row) => {
        ...row,
        'area': label(row['area']),
      };
}
