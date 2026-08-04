enum SolderPasteStatus {
  tempering,
  readyForAgitation,
  agitating,
  readyForLine,
  inLine,
  consumed,
  scrap,
  cancelled,
  returnedToCold,
  unknown,
}

SolderPasteStatus solderPasteStatusFromWire(String? value) {
  switch ((value ?? '').toUpperCase()) {
    case 'TEMPERING':
      return SolderPasteStatus.tempering;
    case 'READY_FOR_AGITATION':
      return SolderPasteStatus.readyForAgitation;
    case 'AGITATING':
      return SolderPasteStatus.agitating;
    case 'READY_FOR_LINE':
      return SolderPasteStatus.readyForLine;
    case 'IN_LINE':
      return SolderPasteStatus.inLine;
    case 'CONSUMED':
      return SolderPasteStatus.consumed;
    case 'SCRAP':
      return SolderPasteStatus.scrap;
    case 'CANCELLED':
      return SolderPasteStatus.cancelled;
    case 'RETURNED_TO_COLD':
      return SolderPasteStatus.returnedToCold;
    default:
      return SolderPasteStatus.unknown;
  }
}

String? solderPasteUnitDisplayName(dynamic value) {
  if (value == null) return null;
  final unit = value.toString();
  return unit.trim().toUpperCase() == 'FRASCO' ? 'BOTE' : unit;
}

extension SolderPasteStatusText on SolderPasteStatus {
  String get wireName {
    switch (this) {
      case SolderPasteStatus.tempering:
        return 'TEMPERING';
      case SolderPasteStatus.readyForAgitation:
        return 'READY_FOR_AGITATION';
      case SolderPasteStatus.agitating:
        return 'AGITATING';
      case SolderPasteStatus.readyForLine:
        return 'READY_FOR_LINE';
      case SolderPasteStatus.inLine:
        return 'IN_LINE';
      case SolderPasteStatus.consumed:
        return 'CONSUMED';
      case SolderPasteStatus.scrap:
        return 'SCRAP';
      case SolderPasteStatus.cancelled:
        return 'CANCELLED';
      case SolderPasteStatus.returnedToCold:
        return 'RETURNED_TO_COLD';
      case SolderPasteStatus.unknown:
        return 'UNKNOWN';
    }
  }

  String get displayName {
    switch (this) {
      case SolderPasteStatus.tempering:
        return 'A temperatura ambiente';
      case SolderPasteStatus.readyForAgitation:
        return 'Listo para agitación';
      case SolderPasteStatus.agitating:
        return 'En agitación';
      case SolderPasteStatus.readyForLine:
        return 'Listo para línea';
      case SolderPasteStatus.inLine:
        return 'En línea';
      case SolderPasteStatus.consumed:
        return 'Consumido';
      case SolderPasteStatus.scrap:
        return 'Scrap';
      case SolderPasteStatus.cancelled:
        return 'Cancelado';
      case SolderPasteStatus.returnedToCold:
        return 'Regresado al refrigerador';
      case SolderPasteStatus.unknown:
        return 'Sin proceso';
    }
  }
}

class SolderPasteProcess {
  final int id;
  final String code;
  final String partNumber;
  final int cycleNo;
  final SolderPasteStatus status;
  final String persistedStatus;
  final String nextAction;
  final String severity;
  final String startedBy;
  final String inventorySource;
  final String? lineCode;
  final double? issuedQuantity;
  final String? unit;
  final DateTime? removedFromColdAt;
  final DateTime? ambientReadyAt;
  final DateTime? agitationDeadlineAt;
  final DateTime? agitationStartedAt;
  final DateTime? agitationReadyAt;
  final DateTime? agitationCompletedAt;
  final DateTime? lineStartedAt;
  final DateTime? expiresAt;
  final DateTime? consumedAt;
  final DateTime? scrappedAt;
  final DateTime? cancelledAt;
  final DateTime? returnedToColdAt;
  final int ambientRemainingSnapshot;
  final int ambientElapsedSnapshot;
  final int readyForAgitationRemainingSnapshot;
  final int agitationRemainingSnapshot;
  final int lineRemainingSnapshot;
  final DateTime snapshotAt;

  const SolderPasteProcess({
    required this.id,
    required this.code,
    required this.partNumber,
    required this.cycleNo,
    required this.status,
    required this.persistedStatus,
    required this.nextAction,
    required this.severity,
    required this.startedBy,
    required this.inventorySource,
    required this.lineCode,
    required this.issuedQuantity,
    required this.unit,
    required this.removedFromColdAt,
    required this.ambientReadyAt,
    required this.agitationDeadlineAt,
    required this.agitationStartedAt,
    required this.agitationReadyAt,
    required this.agitationCompletedAt,
    required this.lineStartedAt,
    required this.expiresAt,
    required this.consumedAt,
    required this.scrappedAt,
    required this.cancelledAt,
    required this.returnedToColdAt,
    required this.ambientRemainingSnapshot,
    required this.ambientElapsedSnapshot,
    required this.readyForAgitationRemainingSnapshot,
    required this.agitationRemainingSnapshot,
    required this.lineRemainingSnapshot,
    required this.snapshotAt,
  });

  factory SolderPasteProcess.fromJson(Map<String, dynamic> json) {
    int intValue(dynamic value) => int.tryParse(value?.toString() ?? '') ?? 0;
    double? doubleValue(dynamic value) =>
        value == null ? null : double.tryParse(value.toString());
    DateTime? dateValue(dynamic value) =>
        value == null ? null : DateTime.tryParse(value.toString())?.toLocal();

    return SolderPasteProcess(
      id: intValue(json['id']),
      code: json['codigo_material_recibido']?.toString() ?? '',
      partNumber: json['numero_parte']?.toString() ?? '',
      cycleNo: intValue(json['cycle_no']),
      status: solderPasteStatusFromWire(json['status']?.toString()),
      persistedStatus: json['persisted_status']?.toString() ??
          json['status']?.toString() ??
          '',
      nextAction: json['next_action']?.toString() ?? '',
      severity: json['severity']?.toString() ?? 'info',
      startedBy: json['started_by']?.toString() ?? 'Sistema',
      inventorySource:
          json['inventory_source']?.toString().toUpperCase() ?? 'WAREHOUSE',
      lineCode: json['line_code']?.toString(),
      issuedQuantity: doubleValue(json['issued_quantity']),
      unit: solderPasteUnitDisplayName(json['unit']),
      removedFromColdAt: dateValue(json['removed_from_cold_at']),
      ambientReadyAt: dateValue(json['ambient_ready_at']),
      agitationDeadlineAt: dateValue(json['agitation_deadline_at']),
      agitationStartedAt: dateValue(json['agitation_started_at']),
      agitationReadyAt: dateValue(json['agitation_ready_at']),
      agitationCompletedAt: dateValue(json['agitation_completed_at']),
      lineStartedAt: dateValue(json['line_started_at']),
      expiresAt: dateValue(json['expires_at']),
      consumedAt: dateValue(json['consumed_at']),
      scrappedAt: dateValue(json['scrapped_at']),
      cancelledAt: dateValue(json['cancelled_at']),
      returnedToColdAt: dateValue(json['returned_to_cold_at']),
      ambientRemainingSnapshot: intValue(json['ambient_remaining_seconds']),
      ambientElapsedSnapshot: intValue(json['ambient_elapsed_seconds']),
      readyForAgitationRemainingSnapshot:
          intValue(json['ready_for_agitation_remaining_seconds']),
      agitationRemainingSnapshot: intValue(json['agitation_remaining_seconds']),
      lineRemainingSnapshot: intValue(json['line_remaining_seconds']),
      snapshotAt: DateTime.now(),
    );
  }

  int _remaining(int snapshot) {
    final elapsed = DateTime.now().difference(snapshotAt).inSeconds;
    final remaining = snapshot - elapsed;
    return remaining > 0 ? remaining : 0;
  }

  int get ambientRemainingSeconds => _remaining(ambientRemainingSnapshot);
  int get ambientElapsedSeconds {
    if (status == SolderPasteStatus.tempering) {
      return (7200 - ambientRemainingSeconds).clamp(0, 7200);
    }
    return ambientElapsedSnapshot.clamp(0, 7200);
  }

  int get agitationRemainingSeconds => _remaining(agitationRemainingSnapshot);
  int get readyForAgitationRemainingSeconds =>
      _remaining(readyForAgitationRemainingSnapshot);
  int get lineRemainingSeconds => _remaining(lineRemainingSnapshot);

  double get ambientProgress =>
      ((7200 - ambientRemainingSeconds) / 7200).clamp(0.0, 1.0);
  double get agitationProgress =>
      ((60 - agitationRemainingSeconds) / 60).clamp(0.0, 1.0);
  double get readyForAgitationProgress =>
      ((28800 - readyForAgitationRemainingSeconds) / 28800).clamp(0.0, 1.0);
  double get lineProgress =>
      ((43200 - lineRemainingSeconds) / 43200).clamp(0.0, 1.0);

  bool get isActive => !{
        SolderPasteStatus.consumed,
        SolderPasteStatus.scrap,
        SolderPasteStatus.cancelled,
        SolderPasteStatus.returnedToCold,
      }.contains(status);

  bool get canCancel => {
        SolderPasteStatus.tempering,
        SolderPasteStatus.readyForAgitation,
        SolderPasteStatus.agitating,
        SolderPasteStatus.readyForLine,
      }.contains(status);

  bool get canReturnToCold =>
      {
        SolderPasteStatus.tempering,
        SolderPasteStatus.readyForAgitation,
        SolderPasteStatus.agitating,
        SolderPasteStatus.readyForLine,
      }.contains(status) ||
      (status == SolderPasteStatus.inLine && inventorySource == 'WAREHOUSE');

  bool get canRecoverUnopenedScrapToCold =>
      status == SolderPasteStatus.scrap &&
      inventorySource == 'WAREHOUSE' &&
      lineStartedAt == null &&
      (lineCode == null || lineCode!.trim().isEmpty);
}
