bool canUseMobileAuditScanner(String mode) {
  return mode == 'location' || mode == 'mismatch_scan';
}

bool canQueueMobileAuditMaterialScan(String mode) {
  return mode == 'mismatch_scan';
}

// Etiqueta escaneada que el backend no encontró en inventario ni en almacén:
// el operador la tiene en la mano, así que se pide la cantidad para darla de alta.
bool isMobileAuditUnknownLabel(Object? errorCode) {
  return errorCode == 'MATERIAL_NOT_FOUND' || errorCode == 'CODE_NOT_FOUND';
}

bool canFinishMobileAuditMismatchScan({
  required String mode,
  required bool isProcessing,
  required bool isQueueProcessing,
  required bool hasPendingScans,
}) {
  return mode == 'mismatch_scan' &&
      !isProcessing &&
      !isQueueProcessing &&
      !hasPendingScans;
}
