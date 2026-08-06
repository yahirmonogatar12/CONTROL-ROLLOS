import 'package:flutter_test/flutter_test.dart';
import 'package:material_warehousing_flutter/core/models/solder_paste_process.dart';

void main() {
  test('convierte todos los estados enviados por el backend', () {
    const expected = {
      'TEMPERING': SolderPasteStatus.tempering,
      'READY_FOR_AGITATION': SolderPasteStatus.readyForAgitation,
      'AGITATING': SolderPasteStatus.agitating,
      'READY_FOR_LINE': SolderPasteStatus.readyForLine,
      'IN_LINE': SolderPasteStatus.inLine,
      'CONSUMED': SolderPasteStatus.consumed,
      'SCRAP': SolderPasteStatus.scrap,
      'CANCELLED': SolderPasteStatus.cancelled,
      'RETURNED_TO_COLD': SolderPasteStatus.returnedToCold,
    };

    for (final entry in expected.entries) {
      expect(solderPasteStatusFromWire(entry.key), entry.value);
      expect(entry.value.wireName, entry.key);
    }
  });

  test('interpreta proceso y calcula progreso con tiempos del servidor', () {
    final process = SolderPasteProcess.fromJson({
      'id': 7,
      'codigo_material_recibido': '49111007000-202607060055',
      'numero_parte': '49111007000',
      'cycle_no': 2,
      'status': 'TEMPERING',
      'persisted_status': 'TEMPERING',
      'next_action': 'Esperar',
      'severity': 'info',
      'started_by': 'operador',
      'ambient_remaining_seconds': 3600,
      'ambient_elapsed_seconds': 3600,
      'agitation_remaining_seconds': 60,
      'line_remaining_seconds': 43200,
    });

    expect(process.id, 7);
    expect(process.code, '49111007000-202607060055');
    expect(process.cycleNo, 2);
    expect(process.ambientRemainingSeconds, inInclusiveRange(3599, 3600));
    expect(process.ambientElapsedSeconds, inInclusiveRange(3600, 3601));
    expect(process.ambientProgress, closeTo(.5, .001));
    expect(process.agitationProgress, closeTo(0, .001));
    expect(process.lineProgress, closeTo(0, .001));
    expect(process.isActive, isTrue);
    expect(process.canCancel, isTrue);
  });

  test('los estados terminales ya no son activos ni cancelables', () {
    for (final status in [
      'CONSUMED',
      'SCRAP',
      'CANCELLED',
      'RETURNED_TO_COLD',
    ]) {
      final process = SolderPasteProcess.fromJson({
        'id': 1,
        'status': status,
      });
      expect(process.isActive, isFalse);
      expect(process.canCancel, isFalse);
    }
  });

  test('muestra la ventana de 8 horas para agitar o retornar', () {
    final process = SolderPasteProcess.fromJson({
      'id': 8,
      'status': 'READY_FOR_AGITATION',
      'ready_for_agitation_remaining_seconds': 14400,
    });

    expect(process.readyForAgitationRemainingSeconds,
        inInclusiveRange(14399, 14400));
    expect(process.readyForAgitationProgress, closeTo(.5, .001));
    expect(process.canReturnToCold, isTrue);
  });

  test('mantiene la cuenta de 12 horas mientras espera selección de línea', () {
    final process = SolderPasteProcess.fromJson({
      'id': 9,
      'status': 'READY_FOR_LINE',
      'line_remaining_seconds': 21600,
    });

    expect(process.lineRemainingSeconds, inInclusiveRange(21599, 21600));
    expect(process.lineProgress, closeTo(.5, .001));
  });

  test('permite retorno desde línea solo para material del almacén general',
      () {
    final warehouseProcess = SolderPasteProcess.fromJson({
      'id': 10,
      'status': 'IN_LINE',
      'inventory_source': 'WAREHOUSE',
    });
    final legacyProcess = SolderPasteProcess.fromJson({
      'id': 11,
      'status': 'IN_LINE',
      'inventory_source': 'SMD_LEGACY',
    });

    expect(warehouseProcess.canReturnToCold, isTrue);
    expect(legacyProcess.canReturnToCold, isFalse);
  });

  test('permite retornar desde todas las etapas activas recuperables', () {
    for (final status in [
      'TEMPERING',
      'READY_FOR_AGITATION',
      'AGITATING',
      'READY_FOR_LINE',
    ]) {
      final process = SolderPasteProcess.fromJson({
        'id': 12,
        'status': status,
        'inventory_source': 'WAREHOUSE',
      });
      expect(process.canReturnToCold, isTrue, reason: status);
    }
  });

  test('solo identifica como recuperable el scrap que nunca llegó a línea', () {
    final unopened = SolderPasteProcess.fromJson({
      'id': 13,
      'status': 'SCRAP',
      'inventory_source': 'WAREHOUSE',
    });
    final sentToLine = SolderPasteProcess.fromJson({
      'id': 14,
      'status': 'SCRAP',
      'inventory_source': 'WAREHOUSE',
      'line_code': 'SMT A',
      'line_started_at': '2026-08-04T10:00:00',
    });

    expect(unopened.canRecoverUnopenedScrapToCold, isTrue);
    expect(sentToLine.canRecoverUnopenedScrapToCold, isFalse);
  });

  test('muestra como bote las unidades históricas guardadas como frasco', () {
    final process = SolderPasteProcess.fromJson({
      'id': 9,
      'status': 'TEMPERING',
      'unit': 'FRASCO',
    });

    expect(process.unit, 'BOTE');
  });
}
