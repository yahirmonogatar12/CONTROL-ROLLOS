import 'package:flutter_test/flutter_test.dart';
import 'package:material_warehousing_flutter/core/services/backend_http_client.dart';
import 'package:material_warehousing_flutter/core/services/update_service.dart';

void main() {
  test('agrega la versión actual a todas las solicitudes del backend', () {
    final headers = buildBackendRequestHeaders({
      'Content-Type': 'application/json',
    });

    expect(headers['X-App-Version'], UpdateService.currentVersion);
    expect(headers['Content-Type'], 'application/json');
  });

  test('conserva una versión proporcionada explícitamente', () {
    final headers = buildBackendRequestHeaders({
      'X-App-Version': '9.9.9-prueba',
    });

    expect(headers['X-App-Version'], '9.9.9-prueba');
  });
}
