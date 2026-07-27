import 'package:flutter_test/flutter_test.dart';
import 'package:material_warehousing_flutter/core/localization/app_translations.dart';
import 'package:material_warehousing_flutter/screens/mobile/mobile_audit_flow_policy.dart';

void main() {
  group('MobileAuditFlowPolicy', () {
    test('el resumen no permite escanear ni encolar materiales', () {
      expect(canUseMobileAuditScanner('summary'), isFalse);
      expect(canQueueMobileAuditMaterialScan('summary'), isFalse);
    });

    test('la ubicación acepta QR y No coincide acepta materiales', () {
      expect(canUseMobileAuditScanner('location'), isTrue);
      expect(canQueueMobileAuditMaterialScan('location'), isFalse);
      expect(canUseMobileAuditScanner('mismatch_scan'), isTrue);
      expect(canQueueMobileAuditMaterialScan('mismatch_scan'), isTrue);
    });

    test('pide la cantidad solo cuando la etiqueta no existe', () {
      expect(isMobileAuditUnknownLabel('MATERIAL_NOT_FOUND'), isTrue);
      expect(isMobileAuditUnknownLabel('CODE_NOT_FOUND'), isTrue);
      expect(isMobileAuditUnknownLabel('ALREADY_SCANNED'), isFalse);
      expect(isMobileAuditUnknownLabel('WRONG_PART'), isFalse);
      expect(isMobileAuditUnknownLabel(null), isFalse);
    });

    test('solo permite terminar cuando ya no hay escaneos pendientes', () {
      expect(
        canFinishMobileAuditMismatchScan(
          mode: 'mismatch_scan',
          isProcessing: false,
          isQueueProcessing: false,
          hasPendingScans: false,
        ),
        isTrue,
      );
      expect(
        canFinishMobileAuditMismatchScan(
          mode: 'mismatch_scan',
          isProcessing: false,
          isQueueProcessing: true,
          hasPendingScans: false,
        ),
        isFalse,
      );
      expect(
        canFinishMobileAuditMismatchScan(
          mode: 'mismatch_scan',
          isProcessing: false,
          isQueueProcessing: false,
          hasPendingScans: true,
        ),
        isFalse,
      );
    });
  });

  test('Terminar escaneo está traducido en los tres idiomas', () {
    expect(
      AppTranslations.translate('audit_finish_scan', 'en'),
      'Finish scanning',
    );
    expect(
      AppTranslations.translate('audit_finish_scan', 'es'),
      'Terminar escaneo',
    );
    expect(
      AppTranslations.translate('audit_finish_scan', 'ko'),
      '스캔 종료',
    );
  });
}
