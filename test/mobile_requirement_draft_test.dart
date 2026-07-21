import 'package:flutter_test/flutter_test.dart';
import 'package:material_warehousing_flutter/screens/mobile/mobile_requirement_draft.dart';

void main() {
  group('MobileRequirementDraft', () {
    test('agrega un material y genera el payload esperado', () {
      final draft = MobileRequirementDraft();
      draft.addOrIncrement(
        partNumber: 'EBR123',
        description: 'Resistor',
        quantity: 2,
      );

      expect(draft.items, hasLength(1));
      expect(draft.toJson().single, containsPair('cantidad_requerida', 2));
    });

    test('combina números de parte duplicados sin importar mayúsculas', () {
      final draft = MobileRequirementDraft();
      draft.addOrIncrement(
        partNumber: 'ebr123',
        description: 'Resistor',
        quantity: 2,
      );
      draft.addOrIncrement(
        partNumber: 'EBR123',
        description: 'Resistor',
        quantity: 3,
      );

      expect(draft.items, hasLength(1));
      expect(draft.items.single.quantity, 5);
    });

    test('rechaza cantidades no positivas', () {
      final draft = MobileRequirementDraft();
      expect(
        () => draft.addOrIncrement(
          partNumber: 'EBR123',
          description: '',
          quantity: 0,
        ),
        throwsArgumentError,
      );
    });

    test('permite editar y eliminar materiales', () {
      final draft = MobileRequirementDraft();
      draft.addOrIncrement(
        partNumber: 'EBR123',
        description: '',
        quantity: 1,
      );
      draft.updateQuantity(0, 4);
      expect(draft.items.single.quantity, 4);
      draft.removeAt(0);
      expect(draft.isEmpty, isTrue);
    });
  });

  group('filterRequirementMaterials', () {
    final materials = [
      {
        'numero_parte': 'EBR123',
        'codigo_material': 'R123',
        'especificacion_material': 'Resistor 10K',
      },
      {
        'numero_parte': 'CAP456',
        'codigo_material': 'C456',
        'especificacion_material': 'Capacitor cerámico 10uF',
      },
    ];

    test('sugiere por coincidencia parcial del número de parte', () {
      final result = filterRequirementMaterials(materials, 'br12');
      expect(result.single['numero_parte'], 'EBR123');
    });

    test('sugiere por SPEC sin importar mayúsculas ni acentos', () {
      final result = filterRequirementMaterials(materials, 'CERAMICO');
      expect(result.single['numero_parte'], 'CAP456');
    });

    test('prioriza número de parte y respeta el límite', () {
      final result = filterRequirementMaterials(materials, 'c', limit: 1);
      expect(result, hasLength(1));
      expect(result.single['numero_parte'], 'CAP456');
    });
  });

  group('acciones por estado del requerimiento', () {
    test('agregar materiales requiere escritura y estado Pendiente', () {
      expect(
        canAddMaterialsToRequirement('Pendiente', canWrite: true),
        isTrue,
      );
      expect(
        canAddMaterialsToRequirement('En Preparación', canWrite: true),
        isFalse,
      );
      expect(
        canAddMaterialsToRequirement('Pendiente', canWrite: false),
        isFalse,
      );
    });

    test('cancelar requiere escritura y un estado no terminal', () {
      expect(canCancelRequirement('Pendiente', canWrite: true), isTrue);
      expect(canCancelRequirement('En Preparación', canWrite: true), isTrue);
      expect(canCancelRequirement('Entregado', canWrite: true), isFalse);
      expect(canCancelRequirement('Cancelado', canWrite: true), isFalse);
      expect(canCancelRequirement('Pendiente', canWrite: false), isFalse);
    });
  });
}
