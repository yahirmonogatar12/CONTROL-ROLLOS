class RequirementDraftItem {
  final String partNumber;
  final String description;
  final String? notes;
  int quantity;
  int? packSize; // cantidad por empaque (cantidad_estandarizada)
  int? units; // número de empaques (cantidad_unidades)

  RequirementDraftItem({
    required this.partNumber,
    required this.description,
    required this.quantity,
    this.notes,
    this.packSize,
    this.units,
  });

  Map<String, dynamic> toJson() => {
        'numero_parte': partNumber,
        'descripcion': description.isEmpty ? null : description,
        'cantidad_requerida': quantity,
        'cantidad_estandarizada': packSize,
        'cantidad_unidades': packSize == null ? null : units,
        'unidad_empaque': packSize?.toString(),
        'notas': notes,
      };
}

class MobileRequirementDraft {
  final List<RequirementDraftItem> items = [];

  bool get isEmpty => items.isEmpty;
  bool get isNotEmpty => items.isNotEmpty;

  void addOrIncrement({
    required String partNumber,
    required String description,
    required int quantity,
    String? notes,
    int? packSize,
    int? units,
  }) {
    final normalized = partNumber.trim().toUpperCase();
    if (normalized.isEmpty) {
      throw ArgumentError('El número de parte es requerido');
    }
    if (quantity <= 0) {
      throw ArgumentError('La cantidad debe ser mayor que cero');
    }

    RequirementDraftItem? existing;
    for (final item in items) {
      if (item.partNumber.toUpperCase() == normalized) {
        existing = item;
        break;
      }
    }
    if (existing != null) {
      existing.quantity += quantity;
      if (packSize != null && existing.packSize == packSize) {
        existing.units = (existing.units ?? 0) + (units ?? 0);
      } else {
        // Mezcla de empaques distintos: se conserva solo el total
        existing.packSize = null;
        existing.units = null;
      }
      return;
    }

    items.add(RequirementDraftItem(
      partNumber: partNumber.trim(),
      description: description.trim(),
      quantity: quantity,
      notes: notes?.trim().isEmpty == true ? null : notes?.trim(),
      packSize: packSize,
      units: packSize == null ? null : units,
    ));
  }

  void updateQuantity(int index, int quantity) {
    if (index < 0 || index >= items.length) {
      throw RangeError.index(index, items);
    }
    if (quantity <= 0) {
      throw ArgumentError('La cantidad debe ser mayor que cero');
    }
    items[index].quantity = quantity;
    // Edición manual del total invalida el desglose por empaques
    items[index].packSize = null;
    items[index].units = null;
  }

  void removeAt(int index) => items.removeAt(index);

  List<Map<String, dynamic>> toJson() =>
      items.map((item) => item.toJson()).toList(growable: false);
}

bool canAddMaterialsToRequirement(String? status, {required bool canWrite}) =>
    canWrite && status?.trim() == 'Pendiente';

bool canCancelRequirement(String? status, {required bool canWrite}) {
  final normalized = status?.trim() ?? '';
  return canWrite && normalized != 'Cancelado' && normalized != 'Entregado';
}

List<Map<String, dynamic>> filterRequirementMaterials(
  Iterable<Map<String, dynamic>> materials,
  String query, {
  int limit = 8,
}) {
  final normalizedQuery = _normalizeMaterialSearchText(query);
  if (normalizedQuery.isEmpty || limit <= 0) return const [];

  final matches = <({int score, Map<String, dynamic> material})>[];
  for (final material in materials) {
    final partNumber = _normalizeMaterialSearchText(
      (material['numero_parte'] ?? '').toString(),
    );
    final materialCode = _normalizeMaterialSearchText(
      (material['codigo_material'] ?? '').toString(),
    );
    final specification = _normalizeMaterialSearchText(
      (material['especificacion_material'] ?? material['spec'] ?? '')
          .toString(),
    );

    int? score;
    if (partNumber == normalizedQuery) {
      score = 0;
    } else if (partNumber.startsWith(normalizedQuery)) {
      score = 1;
    } else if (materialCode == normalizedQuery) {
      score = 2;
    } else if (materialCode.startsWith(normalizedQuery)) {
      score = 3;
    } else if (specification.startsWith(normalizedQuery)) {
      score = 4;
    } else if (partNumber.contains(normalizedQuery)) {
      score = 5;
    } else if (materialCode.contains(normalizedQuery)) {
      score = 6;
    } else if (specification.contains(normalizedQuery)) {
      score = 7;
    }

    if (score != null) matches.add((score: score, material: material));
  }

  matches.sort((a, b) {
    final scoreComparison = a.score.compareTo(b.score);
    if (scoreComparison != 0) return scoreComparison;
    return (a.material['numero_parte'] ?? '')
        .toString()
        .compareTo((b.material['numero_parte'] ?? '').toString());
  });

  return matches
      .take(limit)
      .map((match) => match.material)
      .toList(growable: false);
}

String _normalizeMaterialSearchText(String value) => value
    .trim()
    .toLowerCase()
    .replaceAll(RegExp('[áàäâ]'), 'a')
    .replaceAll(RegExp('[éèëê]'), 'e')
    .replaceAll(RegExp('[íìïî]'), 'i')
    .replaceAll(RegExp('[óòöô]'), 'o')
    .replaceAll(RegExp('[úùüû]'), 'u');
