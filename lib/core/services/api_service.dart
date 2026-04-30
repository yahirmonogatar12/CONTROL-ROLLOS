import 'dart:convert';
import 'backend_http_client.dart' as http;
import '../config/server_config.dart';

class ApiService {
  /// Dynamic base URL from ServerConfig
  /// Falls back to localhost if ServerConfig not initialized
  static String get baseUrl => ServerConfig.baseUrl;
  static bool get isSlowLinkAndroid => http.isSlowLinkAndroid;

  // GET - Obtener todos los registros de warehousing
  static Future<List<Map<String, dynamic>>> getWarehousing() async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/warehousing'));
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return data.cast<Map<String, dynamic>>();
      } else {
        throw Exception('Error al cargar datos: ${response.statusCode}');
      }
    } catch (e) {
      print('Error en getWarehousing: $e');
      return [];
    }
  }

  // GET - Buscar por rango de fechas y/o texto
  static Future<List<Map<String, dynamic>>> searchWarehousing({
    String? fechaInicio,
    String? fechaFin,
    String? texto,
  }) async {
    try {
      String url = '$baseUrl/warehousing/search?';
      if (fechaInicio != null) url += 'fecha_inicio=$fechaInicio&';
      if (fechaFin != null) url += 'fecha_fin=$fechaFin&';
      if (texto != null && texto.isNotEmpty)
        url += 'texto=${Uri.encodeComponent(texto)}';

      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return data.cast<Map<String, dynamic>>();
      } else {
        throw Exception('Error en búsqueda: ${response.statusCode}');
      }
    } catch (e) {
      print('Error en searchWarehousing: $e');
      return [];
    }
  }

  // GET - Salidas de almacén pendientes de confirmar (entradas SMD)
  static Future<Map<String, dynamic>> getPendingWarehouseOutgoing({
    String? fechaInicio,
    String? fechaFin,
    bool compact = false,
    bool groupedByPart = false,
  }) async {
    try {
      String url = '$baseUrl/warehousing/pending-from-warehouse';
      final params = <String>[];
      if (fechaInicio != null) params.add('fechaInicio=$fechaInicio');
      if (fechaFin != null) params.add('fechaFin=$fechaFin');
      if (compact) params.add('compact=1');
      if (groupedByPart) params.add('grouped=part');
      if (params.isNotEmpty) url += '?${params.join('&')}';

      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        return json.decode(response.body) as Map<String, dynamic>;
      }
      return {'success': false, 'error': 'Error ${response.statusCode}'};
    } catch (e) {
      print('Error en getPendingWarehouseOutgoing: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  // GET - Buscar material en almacén por código escaneado
  static Future<Map<String, dynamic>> searchWarehouseMaterial(String codigo,
      {bool directEntry = false}) async {
    try {
      final params = 'codigo=$codigo${directEntry ? '&direct_entry=1' : ''}';
      final response = await http.get(
          Uri.parse('$baseUrl/warehousing/search-warehouse-material?$params'));
      if (response.statusCode == 200) {
        return json.decode(response.body) as Map<String, dynamic>;
      }
      return {'success': false, 'error': 'Error ${response.statusCode}'};
    } catch (e) {
      print('Error en searchWarehouseMaterial: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  static Future<List<Map<String, dynamic>>> searchWarehouseMaterials(
    List<String> codigos, {
    bool directEntry = false,
  }) async {
    try {
      final cleanCodes = codigos
          .map((code) => code.trim())
          .where((code) => code.isNotEmpty)
          .toSet()
          .toList();
      if (cleanCodes.isEmpty) return [];

      final response = await http.post(
        Uri.parse('$baseUrl/warehousing/search-warehouse-materials'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'codes': cleanCodes,
          if (directEntry) 'direct_entry': true,
        }),
      );

      if (response.statusCode == 200) {
        final body = json.decode(response.body);
        if (body is Map<String, dynamic> && body['results'] is List) {
          return (body['results'] as List).cast<Map<String, dynamic>>();
        }
      }
      return [];
    } catch (e) {
      print('Error en searchWarehouseMaterials: $e');
      return [];
    }
  }

  // POST - Verificar contraseña de entrada directa
  static Future<bool> verifyDirectEntryPassword(String password) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/warehousing/verify-direct-entry-password'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'password': password}),
      );
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['success'] == true;
      }
      return false;
    } catch (e) {
      print('Error en verifyDirectEntryPassword: $e');
      return false;
    }
  }

  // POST - Confirmar salida de almac?n como entrada SMD
  static Future<Map<String, dynamic>> confirmWarehouseOutgoing(
      {int? id,
      String? codigoMaterialRecibido,
      String? usuario,
      String? ubicacionDestino,
      bool directEntry = false}) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/warehousing/confirm-from-warehouse'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          if (id != null) 'id': id,
          if (codigoMaterialRecibido != null)
            'codigo_material_recibido': codigoMaterialRecibido,
          if (usuario != null) 'usuario': usuario,
          if (ubicacionDestino != null && ubicacionDestino.isNotEmpty)
            'ubicacion_destino': ubicacionDestino,
          if (directEntry) 'direct_entry': true,
        }),
      );
      if (response.statusCode == 200) {
        return json.decode(response.body) as Map<String, dynamic>;
      }
      return {'success': false, 'error': 'Error ${response.statusCode}'};
    } catch (e) {
      print('Error en confirmWarehouseOutgoing: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  // GET - Historial de salidas rechazadas de almac?n
  static Future<Map<String, dynamic>> getRejectedWarehouseOutgoing() async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/warehousing/rejected-from-warehouse'));
      if (response.statusCode == 200) {
        return json.decode(response.body) as Map<String, dynamic>;
      }
      return {'success': false, 'error': 'Error ${response.statusCode}'};
    } catch (e) {
      print('Error en getRejectedWarehouseOutgoing: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  // POST - Confirmar salidas por numero de parte (confirma todas las pendientes)
  static Future<Map<String, dynamic>> confirmWarehouseOutgoingByPart(
      {required String numeroParte, String? usuario}) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/warehousing/confirm-from-warehouse-by-part'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'numero_parte': numeroParte,
          if (usuario != null) 'usuario': usuario,
        }),
      );
      if (response.statusCode == 200) {
        return json.decode(response.body) as Map<String, dynamic>;
      }
      return {'success': false, 'error': 'Error ${response.statusCode}'};
    } catch (e) {
      print('Error en confirmWarehouseOutgoingByPart: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  // POST - Confirmar salidas por ids seleccionados con ubicaciones individuales (batch)
  static Future<Map<String, dynamic>> confirmWarehouseOutgoingByIds({
    required List<int> ids,
    String? usuario,
    String? ubicacionDestino,
    Map<int, String>? ubicacionesPorId, // Mapa de id -> ubicacion para batch
  }) async {
    try {
      final body = <String, dynamic>{
        'ids': ids,
        if (usuario != null) 'usuario': usuario,
      };

      // Si hay ubicaciones por ID, enviar como batch
      if (ubicacionesPorId != null && ubicacionesPorId.isNotEmpty) {
        body['ubicaciones_por_id'] =
            ubicacionesPorId.map((k, v) => MapEntry(k.toString(), v));
      } else if (ubicacionDestino != null) {
        body['ubicacion_destino'] = ubicacionDestino;
      }

      final response = await http.post(
        Uri.parse('$baseUrl/warehousing/confirm-from-warehouse-by-ids'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(body),
      );
      if (response.statusCode == 200) {
        return json.decode(response.body) as Map<String, dynamic>;
      }
      return {'success': false, 'error': 'Error ${response.statusCode}'};
    } catch (e) {
      print('Error en confirmWarehouseOutgoingByIds: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  // POST - Rechazar salidas por numero de parte
  static Future<Map<String, dynamic>> rejectWarehouseOutgoingByPart({
    required String numeroParte,
    required String motivo,
    String? usuario,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/warehousing/reject-from-warehouse-by-part'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'numero_parte': numeroParte,
          'motivo': motivo,
          if (usuario != null) 'usuario': usuario,
        }),
      );
      if (response.statusCode == 200) {
        return json.decode(response.body) as Map<String, dynamic>;
      }
      return {'success': false, 'error': 'Error ${response.statusCode}'};
    } catch (e) {
      print('Error en rejectWarehouseOutgoingByPart: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  // POST - Rechazar salidas por ids seleccionados
  static Future<Map<String, dynamic>> rejectWarehouseOutgoingByIds({
    required List<int> ids,
    required String motivo,
    String? usuario,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/warehousing/reject-from-warehouse-by-ids'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'ids': ids,
          'motivo': motivo,
          if (usuario != null) 'usuario': usuario,
        }),
      );
      if (response.statusCode == 200) {
        return json.decode(response.body) as Map<String, dynamic>;
      }
      return {'success': false, 'error': 'Error ${response.statusCode}'};
    } catch (e) {
      print('Error en rejectWarehouseOutgoingByIds: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  // POST - Crear nuevo registro
  // Retorna Map con 'success', 'blacklisted' (opcional), 'message', etc.
  static Future<Map<String, dynamic>> createWarehousing(
      Map<String, dynamic> data) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/warehousing'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(data),
      );

      if (response.statusCode == 201) {
        final body = json.decode(response.body);
        return {
          'success': true,
          'id': body['id'],
          'message': body['message'],
          'blacklisted': body['blacklisted'] ?? false,
          'blacklist_reason': body['blacklist_reason'],
        };
      }

      // Error
      try {
        final body = json.decode(response.body);
        return {
          'success': false,
          'error': body['error'] ?? 'Error desconocido'
        };
      } catch (_) {
        return {'success': false, 'error': 'Error ${response.statusCode}'};
      }
    } catch (e) {
      print('Error en createWarehousing: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  // PUT - Actualizar registro
  static Future<bool> updateWarehousing(
      int id, Map<String, dynamic> data) async {
    try {
      final response = await http.put(
        Uri.parse('$baseUrl/warehousing/$id'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(data),
      );
      return response.statusCode == 200;
    } catch (e) {
      print('Error en updateWarehousing: $e');
      return false;
    }
  }

  // PUT - Actualizar múltiples registros (bulk update)
  static Future<Map<String, dynamic>> bulkUpdateWarehousing(
      List<int> ids, Map<String, dynamic> fields) async {
    try {
      final response = await http.put(
        Uri.parse('$baseUrl/warehousing/bulk-update'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'ids': ids, 'fields': fields}),
      );
      if (response.statusCode == 200) {
        return json.decode(response.body);
      }
      return {'success': false, 'error': 'Error ${response.statusCode}'};
    } catch (e) {
      print('Error en bulkUpdateWarehousing: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  // DELETE - Eliminar registro
  static Future<bool> deleteWarehousing(int id) async {
    try {
      final response = await http.delete(Uri.parse('$baseUrl/warehousing/$id'));
      return response.statusCode == 200;
    } catch (e) {
      print('Error en deleteWarehousing: $e');
      return false;
    }
  }

  // GET - Obtener clientes
  static Future<List<String>> getCustomers() async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/customers'));
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return data.map((e) => e['name'].toString()).toList();
      }
      return [];
    } catch (e) {
      print('Error en getCustomers: $e');
      return [];
    }
  }

  // GET - Obtener materiales
  static Future<List<Map<String, dynamic>>> getMaterials() async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/materials'));
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return data.cast<Map<String, dynamic>>();
      }
      return [];
    } catch (e) {
      print('Error en getMaterials: $e');
      return [];
    }
  }

  // GET - Obtener materiales desde tabla materiales (para Material Code dropdown)
  static Future<List<Map<String, dynamic>>> getMateriales() async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/materiales'));
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return data.cast<Map<String, dynamic>>();
      }
      return [];
    } catch (e) {
      print('Error en getMateriales: $e');
      return [];
    }
  }

  // GET - Obtener material por código desde catálogo de materiales
  static Future<Map<String, dynamic>?> getMaterialByCode(
      String materialCode) async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/materiales/by-code/$materialCode'));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data as Map<String, dynamic>?;
      }
      return null;
    } catch (e) {
      print('Error en getMaterialByCode: $e');
      return null;
    }
  }

  // GET - Obtener material por número de parte desde catálogo de materiales
  static Future<Map<String, dynamic>?> getMaterialByPartNumber(
      String partNumber) async {
    try {
      final encodedPartNumber = Uri.encodeComponent(partNumber);
      final response = await http.get(
          Uri.parse('$baseUrl/materiales/by-part-number/$encodedPartNumber'));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data as Map<String, dynamic>?;
      }
      return null;
    } catch (e) {
      print('Error en getMaterialByPartNumber: $e');
      return null;
    }
  }

  // POST - Parsear código de barras complejo y encontrar material coincidente
  static Future<Map<String, dynamic>?> parseBarcodeForMaterial(
      String barcode) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/materiales/parse-barcode'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'barcode': barcode}),
      );
      if (response.statusCode == 200) {
        final result = json.decode(response.body);
        if (result['found'] == true) {
          return result['material'];
        }
      }
      return null;
    } catch (e) {
      print('Error en parseBarcodeForMaterial: $e');
      return null;
    }
  }

  // GET - Obtener siguiente secuencia para un part number y fecha
  // NOTA: Esta función actualiza el cache del backend - usar solo cuando se va a guardar
  static Future<Map<String, dynamic>> getNextSequence(
      String partNumber, String date) async {
    try {
      final response = await http.get(
        Uri.parse(
            '$baseUrl/warehousing/next-sequence?partNumber=${Uri.encodeComponent(partNumber)}&date=$date'),
      );
      if (response.statusCode == 200) {
        return json.decode(response.body);
      }
      return {'nextSequence': 1, 'nextCode': '$partNumber-${date}0001'};
    } catch (e) {
      print('Error en getNextSequence: $e');
      return {'nextSequence': 1, 'nextCode': '$partNumber-${date}0001'};
    }
  }

  // GET - Obtener siguiente secuencia para PREVIEW (no actualiza cache)
  // Usar para mostrar el código de preview en el formulario
  static Future<Map<String, dynamic>> getNextSequencePreview(
      String partNumber, String date) async {
    try {
      final response = await http.get(
        Uri.parse(
            '$baseUrl/warehousing/next-sequence-preview?partNumber=${Uri.encodeComponent(partNumber)}&date=$date'),
      );
      if (response.statusCode == 200) {
        return json.decode(response.body);
      }
      return {'nextSequence': 1, 'nextCode': '$partNumber-${date}0001'};
    } catch (e) {
      print('Error en getNextSequencePreview: $e');
      return {'nextSequence': 1, 'nextCode': '$partNumber-${date}0001'};
    }
  }

  // GET - Obtener siguiente secuencia para lote interno (DD/MM/YYYY/XXXXX)
  static Future<Map<String, dynamic>> getNextInternalLotSequence() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/warehousing/next-internal-lot-sequence'),
      );
      if (response.statusCode == 200) {
        return json.decode(response.body);
      }
      return {'nextSequence': 1};
    } catch (e) {
      print('Error en getNextInternalLotSequence: $e');
      return {'nextSequence': 1};
    }
  }

  // GET - Buscar registro por codigo_material_recibido (para escaneo en salidas)
  // forReturn: true para validar que tenga salida previa (usado en retornos)
  static Future<Map<String, dynamic>?> getWarehousingByCode(String code,
      {bool forReturn = false}) async {
    try {
      final queryParams = forReturn ? '?forReturn=true' : '';
      final response = await http.get(
        Uri.parse(
            '$baseUrl/warehousing/by-code/${Uri.encodeComponent(code)}$queryParams'),
      );
      if (response.statusCode == 200) {
        return json.decode(response.body);
      }
      return null;
    } catch (e) {
      print('Error en getWarehousingByCode: $e');
      return null;
    }
  }

  // GET - Búsqueda inteligente por código (detecta tipo automáticamente)
  static Future<Map<String, dynamic>?> smartSearchWarehousing(
      String code) async {
    try {
      final response = await http.get(
        Uri.parse(
            '$baseUrl/warehousing/smart-search/${Uri.encodeComponent(code)}'),
      );
      if (response.statusCode == 200) {
        return json.decode(response.body);
      }
      return null;
    } catch (e) {
      print('Error en smartSearchWarehousing: $e');
      return null;
    }
  }

  // ============================================
  // BOM (Bill of Materials)
  // ============================================

  // GET - Obtener modelos únicos del BOM
  static Future<List<String>> getBomModels() async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/bom/models'));
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return data.map((e) => e.toString()).toList();
      }
      return [];
    } catch (e) {
      print('Error en getBomModels: $e');
      return [];
    }
  }

  // GET - Obtener BOM de un modelo específico
  static Future<List<Map<String, dynamic>>> getBomByModel(String modelo) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/bom/${Uri.encodeComponent(modelo)}'),
      );
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return data.cast<Map<String, dynamic>>();
      }
      return [];
    } catch (e) {
      print('Error en getBomByModel: $e');
      return [];
    }
  }

  // ============================================
  // PLAN MAIN (Plan de producción)
  // ============================================

  // GET - Obtener planes del día (o fecha específica)
  static Future<List<Map<String, dynamic>>> getTodayPlans(
      {String? date}) async {
    try {
      String url = '$baseUrl/plan/today';
      if (date != null) {
        url += '?date=$date';
      }
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return data.cast<Map<String, dynamic>>();
      }
      return [];
    } catch (e) {
      print('Error en getTodayPlans: $e');
      return [];
    }
  }

  // GET - Obtener BOM de un part_no multiplicado por plan_count
  static Future<List<Map<String, dynamic>>> getPlanBom(
      String partNo, int planCount) async {
    try {
      final response = await http.get(
        Uri.parse(
            '$baseUrl/plan/bom/${Uri.encodeComponent(partNo)}?planCount=$planCount'),
      );
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return data.cast<Map<String, dynamic>>();
      }
      return [];
    } catch (e) {
      print('Error en getPlanBom: $e');
      return [];
    }
  }

  // ============================================
  // CONTROL MATERIAL SALIDA (Salidas de Material)
  // ============================================

  // GET - Verificar si un material ya tiene salida
  static Future<Map<String, dynamic>> checkMaterialHasOutgoing(
      String code) async {
    try {
      final response =
          await http.get(Uri.parse('$baseUrl/outgoing/check-salida/$code'));
      if (response.statusCode == 200) {
        return json.decode(response.body);
      }
      return {'has_outgoing': false};
    } catch (e) {
      print('Error en checkMaterialHasOutgoing: $e');
      return {'has_outgoing': false};
    }
  }

  // GET - Obtener ubicaciones por part numbers (para BOM grid)
  static Future<Map<String, List<String>>> getLocationsByPartNumbers(
      List<String> partNumbers) async {
    try {
      if (partNumbers.isEmpty) return {};

      final partNumbersParam = partNumbers.join(',');
      final response = await http.get(Uri.parse(
          '$baseUrl/outgoing/locations-by-partnumber?partNumbers=${Uri.encodeComponent(partNumbersParam)}'));

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(response.body);
        // Convertir a Map<String, List<String>>
        final Map<String, List<String>> result = {};
        data.forEach((key, value) {
          if (value is List) {
            result[key] = value.cast<String>();
          }
        });
        return result;
      }
      return {};
    } catch (e) {
      print('Error en getLocationsByPartNumbers: $e');
      return {};
    }
  }

  // POST - Crear registro de salida (devuelve mapa con éxito y posible error)
  static Future<Map<String, dynamic>> createOutgoingWithResponse(
      Map<String, dynamic> data) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/outgoing'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(data),
      );
      if (response.statusCode == 201) {
        return {'success': true};
      } else if (response.statusCode == 400) {
        final body = json.decode(response.body);
        return {
          'success': false,
          'error': body['error'] ?? 'Error',
          'code': body['code']
        };
      }
      return {'success': false, 'error': 'Error desconocido'};
    } catch (e) {
      print('Error en createOutgoingWithResponse: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  // POST - Dividir lote y dar salida a los packs
  // quantities: array de cantidades para cada pack [100, 100, 100, 50] (Auto Split con residuo)
  // O usar standardPack + packsCount para packs uniformes (modal manual)
  static Future<Map<String, dynamic>> splitLotOutgoing({
    required String originalCode,
    List<int>? quantities,
    int? standardPack,
    int? packsCount,
    String? modelo,
    String? deptoSalida,
    String? procesoSalida,
    String? lineaProceso,
    String? comparacionEscaneada,
    String? comparacionResultado,
    String? usuarioRegistro,
  }) async {
    try {
      final Map<String, dynamic> body = {
        'original_code': originalCode,
        'modelo': modelo ?? '',
        'depto_salida': deptoSalida ?? 'Almacen',
        'proceso_salida': procesoSalida ?? 'SMD',
        'linea_proceso': lineaProceso,
        'comparacion_escaneada': comparacionEscaneada,
        'comparacion_resultado': comparacionResultado,
        'usuario_registro': usuarioRegistro ?? 'Sistema',
      };

      // Si se envía quantities, usarlo (Auto Split con residuo)
      if (quantities != null && quantities.isNotEmpty) {
        body['quantities'] = quantities;
      } else if (standardPack != null && packsCount != null) {
        // Modo legacy para modal manual
        body['standard_pack'] = standardPack;
        body['packs_count'] = packsCount;
      }

      print('>>> splitLotOutgoing enviando: $body');

      final response = await http.post(
        Uri.parse('$baseUrl/outgoing/split-lot'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(body),
      );

      final responseBody = json.decode(response.body);
      print('>>> splitLotOutgoing respuesta: $responseBody');

      if (response.statusCode == 200) {
        return responseBody;
      } else {
        return {
          'success': false,
          'error': responseBody['error'] ?? 'Error en división de lote',
        };
      }
    } catch (e) {
      print('Error en splitLotOutgoing: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  // POST - Validar material para salida en lote
  static Future<Map<String, dynamic>> validateMaterialForBatch(
      String code) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/outgoing/validate-batch'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'code': code}),
      );
      if (response.statusCode == 200) {
        return json.decode(response.body);
      }
      return {
        'valid': false,
        'error': 'Error de conexión',
        'code': 'CONNECTION_ERROR'
      };
    } catch (e) {
      print('Error en validateMaterialForBatch: $e');
      return {'valid': false, 'error': e.toString(), 'code': 'EXCEPTION'};
    }
  }

  static Future<List<Map<String, dynamic>>> validateMaterialsForBatch(
      List<String> codes) async {
    try {
      final cleanCodes = codes
          .map((code) => code.trim())
          .where((code) => code.isNotEmpty)
          .toSet()
          .toList();
      if (cleanCodes.isEmpty) return [];

      final response = await http.post(
        Uri.parse('$baseUrl/outgoing/validate-batch'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'codes': cleanCodes}),
      );
      if (response.statusCode == 200) {
        final body = json.decode(response.body);
        if (body is Map<String, dynamic> && body['results'] is List) {
          return (body['results'] as List).cast<Map<String, dynamic>>();
        }
      }
      return [];
    } catch (e) {
      print('Error en validateMaterialsForBatch: $e');
      return [];
    }
  }

  // POST - Crear salidas en lote
  static Future<Map<String, dynamic>> createOutgoingBatch(
      List<Map<String, dynamic>> materials, String usuarioRegistro) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/outgoing/batch'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'materials': materials,
          'usuario_registro': usuarioRegistro,
        }),
      );
      if (response.statusCode == 200) {
        return json.decode(response.body);
      }
      return {
        'success': false,
        'error': 'Error de conexión: ${response.statusCode}',
        'processed': 0,
        'failed': materials.length
      };
    } catch (e) {
      print('Error en createOutgoingBatch: $e');
      return {
        'success': false,
        'error': e.toString(),
        'processed': 0,
        'failed': materials.length
      };
    }
  }

  // POST - Crear registro de salida (legacy - mantener compatibilidad)
  static Future<bool> createOutgoing(Map<String, dynamic> data) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/outgoing'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(data),
      );
      return response.statusCode == 201;
    } catch (e) {
      print('Error en createOutgoing: $e');
      return false;
    }
  }

  // GET - Obtener todos los registros de salida
  static Future<List<Map<String, dynamic>>> getOutgoing() async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/outgoing'));
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return data.cast<Map<String, dynamic>>();
      }
      return [];
    } catch (e) {
      print('Error en getOutgoing: $e');
      return [];
    }
  }

  // GET - Buscar salidas por rango de fechas y/o texto
  static Future<List<Map<String, dynamic>>> searchOutgoing({
    String? fechaInicio,
    String? fechaFin,
    String? texto,
  }) async {
    try {
      String url = '$baseUrl/outgoing/search?';
      if (fechaInicio != null) url += 'fecha_inicio=$fechaInicio&';
      if (fechaFin != null) url += 'fecha_fin=$fechaFin&';
      if (texto != null && texto.isNotEmpty)
        url += 'texto=${Uri.encodeComponent(texto)}';

      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return data.cast<Map<String, dynamic>>();
      }
      return [];
    } catch (e) {
      print('Error en searchOutgoing: $e');
      return [];
    }
  }

  // GET - Validación FIFO: verificar si hay materiales más antiguos
  static Future<Map<String, dynamic>?> checkFifoValidation(
      String materialCode, String currentDate) async {
    try {
      final response = await http.get(
        Uri.parse(
            '$baseUrl/warehousing/fifo-check?material_code=${Uri.encodeComponent(materialCode)}&current_date=${Uri.encodeComponent(currentDate)}'),
      );
      if (response.statusCode == 200) {
        return json.decode(response.body);
      }
      return null;
    } catch (e) {
      print('Error en checkFifoValidation: $e');
      return null;
    }
  }

  // ============================================
  // INVENTARIO LOTES (Current Inventory)
  // ============================================

  // GET - Inventario general agrupado por numero_parte
  static Future<List<Map<String, dynamic>>> getInventorySummary({
    String? numeroParte,
    bool includeZeroStock = false,
    String? fechaInicio,
    String? fechaFin,
  }) async {
    try {
      String url = '$baseUrl/inventory/summary?';
      if (numeroParte != null && numeroParte.isNotEmpty) {
        url += 'numero_parte=${Uri.encodeComponent(numeroParte)}&';
      }
      if (includeZeroStock) {
        url += 'include_zero_stock=true&';
      }
      if (fechaInicio != null && fechaFin != null) {
        url += 'fecha_inicio=$fechaInicio&fecha_fin=$fechaFin&';
      }

      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return data.cast<Map<String, dynamic>>();
      }
      return [];
    } catch (e) {
      print('Error en getInventorySummary: $e');
      return [];
    }
  }

  // GET - Detalle de lotes por numero_parte
  static Future<List<Map<String, dynamic>>> getInventoryLots({
    String? numeroParte,
    String? codigoMaterialRecibido,
    bool includeZeroStock = false,
    String? fechaInicio,
    String? fechaFin,
  }) async {
    try {
      String url = '$baseUrl/inventory/lots?';
      if (numeroParte != null && numeroParte.isNotEmpty) {
        url += 'numero_parte=${Uri.encodeComponent(numeroParte)}&';
      }
      if (codigoMaterialRecibido != null && codigoMaterialRecibido.isNotEmpty) {
        url +=
            'codigo_material_recibido=${Uri.encodeComponent(codigoMaterialRecibido)}&';
      }
      if (includeZeroStock) {
        url += 'include_zero_stock=true&';
      }
      if (fechaInicio != null && fechaFin != null) {
        url += 'fecha_inicio=$fechaInicio&fecha_fin=$fechaFin&';
      }

      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return data.cast<Map<String, dynamic>>();
      }
      return [];
    } catch (e) {
      print('Error en getInventoryLots: $e');
      return [];
    }
  }

  static Future<List<Map<String, dynamic>>> searchInventoryMobile(
      String query) async {
    try {
      final response = await http.get(
        Uri.parse(
            '$baseUrl/inventory/mobile-search?q=${Uri.encodeComponent(query)}'),
      );
      if (response.statusCode == 200) {
        final body = json.decode(response.body);
        if (body is Map<String, dynamic> && body['results'] is List) {
          return (body['results'] as List).cast<Map<String, dynamic>>();
        }
      }
      return [];
    } catch (e) {
      print('Error en searchInventoryMobile: $e');
      return [];
    }
  }

  // GET - Buscar por etiqueta (codigo_material_recibido)
  static Future<List<Map<String, dynamic>>> searchInventoryByLabel(
      String codigo) async {
    try {
      final response = await http.get(
        Uri.parse(
            '$baseUrl/inventory/search-label?codigo=${Uri.encodeComponent(codigo)}'),
      );
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return data.cast<Map<String, dynamic>>();
      }
      return [];
    } catch (e) {
      print('Error en searchInventoryByLabel: $e');
      return [];
    }
  }

  // ============================================
  // IQC - INSPECCIÓN DE CALIDAD DE ENTRADA
  // ============================================

  // GET /api/inventory/location-search - Buscar ubicación por numero de parte
  // Retorna lista de coincidencias (soporta barcode NPARTE-LOTE y parcial)
  static Future<List<Map<String, dynamic>>> getLocationByPartNumber(
      String numeroParte) async {
    try {
      final response = await http.get(
        Uri.parse(
            '$baseUrl/inventory/location-search?numero_parte=${Uri.encodeComponent(numeroParte)}'),
      );
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return data.cast<Map<String, dynamic>>();
      }
      return [];
    } catch (e) {
      print('Error en getLocationByPartNumber: $e');
      return [];
    }
  }

  // ============================================
  // IQC - INSPECCIÓN DE CALIDAD DE ENTRADA (cont.)
  // ============================================

  // GET - Obtener lote IQC por código de etiqueta
  static Future<Map<String, dynamic>?> getIqcLotByLabel(
      String labelCode) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/iqc/lot/${Uri.encodeComponent(labelCode)}'),
      );
      if (response.statusCode == 200) {
        return json.decode(response.body);
      }
      return null;
    } catch (e) {
      print('Error en getIqcLotByLabel: $e');
      return null;
    }
  }

  // POST - Crear inspección IQC
  static Future<Map<String, dynamic>> createIqcInspection(
      String labelCode, Map<String, dynamic> data) async {
    try {
      // Extraer receiving_lot_code (primeros 20 caracteres)
      final receivingLotCode =
          labelCode.length >= 20 ? labelCode.substring(0, 20) : labelCode;

      // Agregar receiving_lot_code a los datos
      final requestData = {
        ...data,
        'receiving_lot_code': receivingLotCode,
        'sample_label_code': labelCode,
      };

      final response = await http.post(
        Uri.parse('$baseUrl/iqc/inspection'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(requestData),
      );
      if (response.statusCode == 201 || response.statusCode == 200) {
        return {'success': true, 'data': json.decode(response.body)};
      }
      final errorBody = json.decode(response.body);
      return {
        'success': false,
        'error': errorBody['error'] ?? 'Error al crear inspección'
      };
    } catch (e) {
      print('Error en createIqcInspection: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  // PUT - Actualizar inspección IQC
  static Future<Map<String, dynamic>> updateIqcInspection(
      int inspectionId, Map<String, dynamic> data) async {
    try {
      final response = await http.put(
        Uri.parse('$baseUrl/iqc/inspection/$inspectionId'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(data),
      );
      if (response.statusCode == 200) {
        return {'success': true};
      }
      return {'success': false, 'error': 'Error al actualizar inspección'};
    } catch (e) {
      print('Error en updateIqcInspection: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  // POST - Guardar mediciones de inspección IQC en batch
  static Future<Map<String, dynamic>> saveIqcMeasurements(
      int inspectionId, List<Map<String, dynamic>> measurements) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/iqc/$inspectionId/measurements'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'measurements': measurements}),
      );
      if (response.statusCode == 200) {
        return {'success': true};
      }
      return {'success': false, 'error': 'Error al guardar mediciones'};
    } catch (e) {
      print('Error en saveIqcMeasurements: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  // GET - Obtener mediciones de inspección IQC agrupadas por tipo
  static Future<Map<String, dynamic>> getIqcMeasurements(
      int inspectionId) async {
    try {
      final response =
          await http.get(Uri.parse('$baseUrl/iqc/$inspectionId/measurements'));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          return data['data'] ?? {};
        }
      }
      return {};
    } catch (e) {
      print('Error en getIqcMeasurements: $e');
      return {};
    }
  }

  // PUT - Cerrar inspección IQC (aplicar disposición)
  static Future<Map<String, dynamic>> closeIqcInspection(
      int inspectionId, Map<String, dynamic> data) async {
    try {
      final response = await http.put(
        Uri.parse('$baseUrl/iqc/close/$inspectionId'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(data),
      );
      if (response.statusCode == 200) {
        return {'success': true};
      }
      return {'success': false, 'error': 'Error al cerrar inspección'};
    } catch (e) {
      print('Error en closeIqcInspection: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  // GET - Obtener lotes pendientes de inspección IQC
  static Future<List<Map<String, dynamic>>> getIqcPending() async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/iqc/pending'));
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return data.cast<Map<String, dynamic>>();
      }
      return [];
    } catch (e) {
      print('Error en getIqcPending: $e');
      return [];
    }
  }

  // GET - Historial de inspecciones IQC
  static Future<List<Map<String, dynamic>>> getIqcHistory({
    String? fechaInicio,
    String? fechaFin,
    String? status,
    String? texto,
  }) async {
    try {
      String url = '$baseUrl/iqc/history?';
      if (fechaInicio != null) url += 'fecha_inicio=$fechaInicio&';
      if (fechaFin != null) url += 'fecha_fin=$fechaFin&';
      if (status != null && status.isNotEmpty) url += 'status=$status&';
      if (texto != null && texto.isNotEmpty)
        url += 'texto=${Uri.encodeComponent(texto)}';

      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return data.cast<Map<String, dynamic>>();
      }
      return [];
    } catch (e) {
      print('Error en getIqcHistory: $e');
      return [];
    }
  }

  // PATCH - Actualizar resultado de un campo de inspección IQC
  static Future<void> updateIqcResult(
      int inspectionId, String field, String result) async {
    try {
      final response = await http.patch(
        Uri.parse('$baseUrl/iqc/inspection/$inspectionId/result'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'field': field,
          'result': result,
        }),
      );
      if (response.statusCode != 200) {
        throw Exception(
            'Error al actualizar resultado: ${response.statusCode}');
      }
    } catch (e) {
      print('Error en updateIqcResult: $e');
      rethrow;
    }
  }

  // GET - Obtener inspección IQC por ID con detalles
  static Future<Map<String, dynamic>?> getIqcInspectionById(
      int inspectionId) async {
    try {
      final response =
          await http.get(Uri.parse('$baseUrl/iqc/inspection/$inspectionId'));
      if (response.statusCode == 200) {
        return json.decode(response.body);
      }
      return null;
    } catch (e) {
      print('Error en getIqcInspectionById: $e');
      return null;
    }
  }

  // GET - Contar lotes pendientes de IQC
  static Future<int> getIqcPendingCount() async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/iqc/count-pending'));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['count'] ?? 0;
      }
      return 0;
    } catch (e) {
      print('Error en getIqcPendingCount: $e');
      return 0;
    }
  }

  // GET - Contar materiales en proceso IQC (para badge en Warehousing)
  static Future<int> getWarehousingIqcPendingCount() async {
    try {
      final response =
          await http.get(Uri.parse('$baseUrl/warehousing/count-iqc-pending'));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['count'] ?? 0;
      }
      return 0;
    } catch (e) {
      print('Error en getWarehousingIqcPendingCount: $e');
      return 0;
    }
  }

  // ===================== QUALITY SPECS ENDPOINTS =====================

  // GET - Listar Quality Specs con filtros opcionales
  static Future<List<Map<String, dynamic>>> getQualitySpecs({
    String? numeroParte,
    String? specCode,
    bool? isBlocking,
  }) async {
    try {
      final queryParams = <String, String>{};
      if (numeroParte != null) queryParams['numero_parte'] = numeroParte;
      if (specCode != null) queryParams['spec_code'] = specCode;
      if (isBlocking != null)
        queryParams['is_blocking'] = isBlocking ? '1' : '0';

      final uri = Uri.parse('$baseUrl/quality-specs').replace(
          queryParameters: queryParams.isNotEmpty ? queryParams : null);
      final response = await http.get(uri);

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return data.cast<Map<String, dynamic>>();
      }
      return [];
    } catch (e) {
      print('Error en getQualitySpecs: $e');
      return [];
    }
  }

  // GET - Obtener specs de un número de parte específico
  static Future<List<Map<String, dynamic>>> getQualitySpecsByPart(
      String partNumber) async {
    try {
      final response =
          await http.get(Uri.parse('$baseUrl/quality-specs/part/$partNumber'));
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return data.cast<Map<String, dynamic>>();
      }
      return [];
    } catch (e) {
      print('Error en getQualitySpecsByPart: $e');
      return [];
    }
  }

  // POST - Crear nuevo Quality Spec
  static Future<Map<String, dynamic>> createQualitySpec(
      Map<String, dynamic> specData) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/quality-specs'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(specData),
      );

      final data = json.decode(response.body);
      return {
        'success': response.statusCode == 201,
        'message': data['message'] ??
            (response.statusCode == 201
                ? 'Spec creado exitosamente'
                : 'Error al crear spec'),
        'id': data['id'],
        'errors': data['errors'],
      };
    } catch (e) {
      print('Error en createQualitySpec: $e');
      return {'success': false, 'message': 'Error de conexión: $e'};
    }
  }

  // PUT - Actualizar Quality Spec
  static Future<Map<String, dynamic>> updateQualitySpec(
      int specId, Map<String, dynamic> specData) async {
    try {
      final response = await http.put(
        Uri.parse('$baseUrl/quality-specs/$specId'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(specData),
      );

      final data = json.decode(response.body);
      return {
        'success': response.statusCode == 200,
        'message': data['message'] ??
            (response.statusCode == 200
                ? 'Spec actualizado'
                : 'Error al actualizar'),
        'errors': data['errors'],
      };
    } catch (e) {
      print('Error en updateQualitySpec: $e');
      return {'success': false, 'message': 'Error de conexión: $e'};
    }
  }

  // DELETE - Eliminar Quality Spec (soft delete)
  static Future<Map<String, dynamic>> deleteQualitySpec(int specId) async {
    try {
      final response =
          await http.delete(Uri.parse('$baseUrl/quality-specs/$specId'));

      final data = json.decode(response.body);
      return {
        'success': response.statusCode == 200,
        'message': data['message'] ??
            (response.statusCode == 200
                ? 'Spec eliminado'
                : 'Error al eliminar'),
      };
    } catch (e) {
      print('Error en deleteQualitySpec: $e');
      return {'success': false, 'message': 'Error de conexión: $e'};
    }
  }

  // POST - Bulk upload de Quality Specs desde Excel
  static Future<Map<String, dynamic>> bulkUploadQualitySpecs(
      List<Map<String, dynamic>> specs) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/quality-specs/bulk-upload'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'specs': specs}),
      );

      final data = json.decode(response.body);
      return {
        'success': response.statusCode == 200,
        'message': data['message'] ?? 'Bulk upload completado',
        'inserted': data['inserted'] ?? 0,
        'updated': data['updated'] ?? 0,
        'errors': data['errors'],
      };
    } catch (e) {
      print('Error en bulkUploadQualitySpecs: $e');
      return {'success': false, 'message': 'Error de conexión: $e'};
    }
  }

  // GET - Verificar si una inspección puede ser liberada
  static Future<Map<String, dynamic>> canReleaseInspection(
      int inspectionId) async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/iqc/inspection/$inspectionId/can-release'));

      if (response.statusCode == 200) {
        return json.decode(response.body);
      }
      return {'canRelease': false, 'message': 'Error al verificar liberación'};
    } catch (e) {
      print('Error en canReleaseInspection: $e');
      return {'canRelease': false, 'message': 'Error de conexión: $e'};
    }
  }

  // GET - Obtener materiales que requieren IQC
  static Future<List<Map<String, dynamic>>> getMaterialesIqcRequired() async {
    try {
      final response =
          await http.get(Uri.parse('$baseUrl/materiales/iqc-required'));
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return data.cast<Map<String, dynamic>>();
      }
      return [];
    } catch (e) {
      print('Error en getMaterialesIqcRequired: $e');
      return [];
    }
  }

  // PUT - Actualizar flag iqc_required de un material
  static Future<Map<String, dynamic>> updateMaterialIqcRequired(
      String numeroParte, bool required) async {
    try {
      final response = await http.put(
        Uri.parse('$baseUrl/materiales/$numeroParte/iqc-required'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'iqc_required': required}),
      );

      final data = json.decode(response.body);
      return {
        'success': response.statusCode == 200,
        'message': data['message'] ?? 'Actualizado',
      };
    } catch (e) {
      print('Error en updateMaterialIqcRequired: $e');
      return {'success': false, 'message': 'Error de conexión: $e'};
    }
  }

  // ===================== IQC CONFIGURATION BY MATERIAL =====================

  // GET - Obtener todos los materiales con su configuración IQC
  static Future<List<Map<String, dynamic>>> getMaterialesForIqc() async {
    try {
      final response =
          await http.get(Uri.parse('$baseUrl/materiales/iqc-config'));
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return data.cast<Map<String, dynamic>>();
      }
      return [];
    } catch (e) {
      print('Error en getMaterialesForIqc: $e');
      return [];
    }
  }

  // PUT - Actualizar configuración IQC de un material
  static Future<Map<String, dynamic>> updateMaterialIqcConfig(
      String numeroParte, Map<String, dynamic> config) async {
    try {
      final response = await http.put(
        Uri.parse('$baseUrl/materiales/$numeroParte/iqc-config'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(config),
      );

      final data = json.decode(response.body);
      return {
        'success': response.statusCode == 200,
        'message': data['message'] ?? 'Configuración actualizada',
      };
    } catch (e) {
      print('Error en updateMaterialIqcConfig: $e');
      return {'success': false, 'message': 'Error de conexión: $e'};
    }
  }

  // POST - Bulk update configuración IQC de múltiples materiales
  static Future<Map<String, dynamic>> bulkUpdateMaterialIqcConfig(
      List<Map<String, dynamic>> configs) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/materiales/iqc-config/bulk'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'configs': configs}),
      );

      final data = json.decode(response.body);
      return {
        'success': response.statusCode == 200,
        'message': data['message'] ?? 'Bulk update completado',
        'updated': data['updated'] ?? 0,
        'errors': data['errors'],
      };
    } catch (e) {
      print('Error en bulkUpdateMaterialIqcConfig: $e');
      return {'success': false, 'message': 'Error de conexión: $e'};
    }
  }

  // GET - Obtener configuración IQC de un material específico por part number
  static Future<Map<String, dynamic>?> getMaterialIqcConfig(
      String partNumber) async {
    try {
      final response = await http.get(
        Uri.parse(
            '$baseUrl/materiales/${Uri.encodeComponent(partNumber)}/iqc-config'),
      );
      if (response.statusCode == 200) {
        return json.decode(response.body);
      }
      return null;
    } catch (e) {
      print('Error en getMaterialIqcConfig: $e');
      return null;
    }
  }

  // ===================== MATERIAL CONTROL (CRUD Materiales) =====================

  // POST - Crear nuevo material
  static Future<Map<String, dynamic>> createMaterial(
      Map<String, dynamic> data) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/materiales'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(data),
      );

      if (response.statusCode == 201) {
        return {'success': true, 'message': 'Material creado exitosamente'};
      }

      final body = json.decode(response.body);
      return {
        'success': false,
        'error': body['error'] ?? 'Error al crear material',
        'code': body['code']
      };
    } catch (e) {
      print('Error en createMaterial: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  // PUT - Actualizar material existente
  static Future<Map<String, dynamic>> updateMaterial(
      String numeroParte, Map<String, dynamic> data) async {
    try {
      final response = await http.put(
        Uri.parse('$baseUrl/materiales/${Uri.encodeComponent(numeroParte)}'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(data),
      );

      if (response.statusCode == 200) {
        return {
          'success': true,
          'message': 'Material actualizado exitosamente'
        };
      }

      final body = json.decode(response.body);
      return {
        'success': false,
        'error': body['error'] ?? 'Error al actualizar material',
        'code': body['code']
      };
    } catch (e) {
      print('Error en updateMaterial: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  // POST - Carga masiva de comparaciones
  static Future<Map<String, dynamic>> bulkUpdateComparacion(
      List<Map<String, dynamic>> items) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/materiales/bulk-update-comparacion'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'items': items}),
      );

      if (response.statusCode == 200) {
        final body = json.decode(response.body);
        return {
          'success': true,
          'message': body['message'] ?? 'Comparaciones actualizadas',
          'updated': body['updated'] ?? 0,
          'notFound': body['notFound'] ?? [],
          'errors': body['errors'] ?? [],
        };
      }

      final body = json.decode(response.body);
      return {
        'success': false,
        'error': body['error'] ?? 'Error al actualizar comparaciones',
      };
    } catch (e) {
      print('Error en bulkUpdateComparacion: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  // POST - Carga masiva de ubicación rollos
  static Future<Map<String, dynamic>> bulkUpdateUbicacionRollos(
      List<Map<String, dynamic>> items) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/materiales/bulk-update-ubicacion-rollos'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'items': items}),
      );

      if (response.statusCode == 200) {
        final body = json.decode(response.body);
        return {
          'success': true,
          'message': body['message'] ?? 'Ubicaciones actualizadas',
          'updated': body['updated'] ?? 0,
          'notFound': body['notFound'] ?? [],
          'errors': body['errors'] ?? [],
        };
      }

      final body = json.decode(response.body);
      return {
        'success': false,
        'error': body['error'] ?? 'Error al actualizar ubicación rollos',
      };
    } catch (e) {
      print('Error en bulkUpdateUbicacionRollos: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  // POST - Validar números de parte que existen en el sistema
  static Future<Map<String, dynamic>> validatePartNumbers(
      List<String> partNumbers) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/materiales/validate-part-numbers'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'partNumbers': partNumbers}),
      );

      if (response.statusCode == 200) {
        final body = json.decode(response.body);
        return {
          'success': true,
          'results': body['results'] ?? [],
          'existCount': body['existCount'] ?? 0,
          'notExistCount': body['notExistCount'] ?? 0,
        };
      }

      return {'success': false, 'error': 'Error validando números de parte'};
    } catch (e) {
      print('Error en validatePartNumbers: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  // POST - Crear material simple (solo numero_parte y comparacion)
  static Future<Map<String, dynamic>> createMaterialSimple(
      String numeroParte, String? comparacion,
      {String? ubicacionRollos}) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/materiales/create-simple'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'numero_parte': numeroParte,
          'comparacion': comparacion,
          if (ubicacionRollos != null && ubicacionRollos.isNotEmpty)
            'ubicacion_rollos': ubicacionRollos,
        }),
      );

      if (response.statusCode == 200) {
        return {'success': true, 'message': 'Material creado exitosamente'};
      }

      final body = json.decode(response.body);
      return {
        'success': false,
        'error': body['error'] ?? 'Error al crear material',
        'code': body['code']
      };
    } catch (e) {
      print('Error en createMaterialSimple: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  // PUT - Actualizar solo comparación
  static Future<Map<String, dynamic>> updateMaterialComparacion(
      String numeroParte, String? comparacion,
      {String? ubicacionRollos}) async {
    try {
      final response = await http.put(
        Uri.parse(
            '$baseUrl/materiales/${Uri.encodeComponent(numeroParte)}/comparacion'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'comparacion': comparacion,
          if (ubicacionRollos != null) 'ubicacion_rollos': ubicacionRollos,
        }),
      );

      if (response.statusCode == 200) {
        return {
          'success': true,
          'message': 'Comparación actualizada exitosamente'
        };
      }

      final body = json.decode(response.body);
      return {
        'success': false,
        'error': body['error'] ?? 'Error al actualizar comparación',
        'code': body['code']
      };
    } catch (e) {
      print('Error en updateMaterialComparacion: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  // DELETE - Eliminar material
  static Future<Map<String, dynamic>> deleteMaterial(String numeroParte) async {
    try {
      final response = await http.delete(
        Uri.parse('$baseUrl/materiales/${Uri.encodeComponent(numeroParte)}'),
      );

      if (response.statusCode == 200) {
        return {'success': true, 'message': 'Material eliminado exitosamente'};
      }

      final body = json.decode(response.body);
      return {
        'success': false,
        'error': body['error'] ?? 'Error al eliminar material',
      };
    } catch (e) {
      print('Error en deleteMaterial: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  // ============================================
  // QUARANTINE (CUARENTENA)
  // ============================================

  // GET - Obtener materiales en cuarentena
  static Future<List<Map<String, dynamic>>> getQuarantine(
      {String? status}) async {
    try {
      String url = '$baseUrl/quarantine';
      if (status != null) url += '?status=$status';

      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return data.cast<Map<String, dynamic>>();
      }
      return [];
    } catch (e) {
      print('Error en getQuarantine: $e');
      return [];
    }
  }

  // GET - Obtener historial de un item de cuarentena
  static Future<List<Map<String, dynamic>>> getQuarantineItemHistory(
      int id) async {
    try {
      final response =
          await http.get(Uri.parse('$baseUrl/quarantine/$id/history'));
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return data.cast<Map<String, dynamic>>();
      }
      return [];
    } catch (e) {
      print('Error en getQuarantineItemHistory: $e');
      return [];
    }
  }

  // GET - Historial completo de cuarentena (cerrados)
  static Future<List<Map<String, dynamic>>> getQuarantineHistory({
    String? fechaInicio,
    String? fechaFin,
  }) async {
    try {
      String url = '$baseUrl/quarantine/history/all?';
      if (fechaInicio != null) url += 'fecha_inicio=$fechaInicio&';
      if (fechaFin != null) url += 'fecha_fin=$fechaFin';

      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return data.cast<Map<String, dynamic>>();
      }
      return [];
    } catch (e) {
      print('Error en getQuarantineHistory: $e');
      return [];
    }
  }

  // POST - Enviar materiales a cuarentena
  static Future<Map<String, dynamic>> sendToQuarantine({
    required List<Map<String, dynamic>> items,
    required String reason,
    required int userId,
    required String userName,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/quarantine/send'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'items': items,
          'reason': reason,
          'userId': userId,
          'userName': userName,
        }),
      );

      if (response.statusCode == 201) {
        final data = json.decode(response.body);
        return {'success': true, ...data};
      }

      final body = json.decode(response.body);
      return {
        'success': false,
        'error': body['error'] ?? 'Error al enviar a cuarentena'
      };
    } catch (e) {
      print('Error en sendToQuarantine: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  // PUT - Actualizar estado de cuarentena
  static Future<Map<String, dynamic>> updateQuarantineStatus({
    required int id,
    required String status,
    String? comments,
    required int userId,
    required String userName,
  }) async {
    try {
      final response = await http.put(
        Uri.parse('$baseUrl/quarantine/$id'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'status': status,
          'comments': comments,
          'userId': userId,
          'userName': userName,
        }),
      );

      if (response.statusCode == 200) {
        return {'success': true};
      }

      final body = json.decode(response.body);
      return {
        'success': false,
        'error': body['error'] ?? 'Error al actualizar'
      };
    } catch (e) {
      print('Error en updateQuarantineStatus: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  // POST - Agregar comentario a cuarentena
  static Future<Map<String, dynamic>> addQuarantineComment({
    required int id,
    required String comments,
    required int userId,
    required String userName,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/quarantine/$id/comment'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'comments': comments,
          'userId': userId,
          'userName': userName,
        }),
      );

      if (response.statusCode == 200) {
        return {'success': true};
      }

      final body = json.decode(response.body);
      return {
        'success': false,
        'error': body['error'] ?? 'Error al agregar comentario'
      };
    } catch (e) {
      print('Error en addQuarantineComment: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  // ============================================
  // BLACKLIST (LISTA NEGRA DE LOTES)
  // ============================================

  /// GET - Obtener todos los lotes en lista negra
  static Future<List<Map<String, dynamic>>> getBlacklist() async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/blacklist'));
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return data.cast<Map<String, dynamic>>();
      }
      return [];
    } catch (e) {
      print('Error en getBlacklist: $e');
      return [];
    }
  }

  /// GET - Verificar si un lote está en lista negra
  static Future<Map<String, dynamic>> checkBlacklist(String lotNumber) async {
    try {
      final response = await http.get(Uri.parse(
          '$baseUrl/blacklist/check/${Uri.encodeComponent(lotNumber)}'));
      if (response.statusCode == 200) {
        return json.decode(response.body);
      }
      return {'blacklisted': false};
    } catch (e) {
      print('Error en checkBlacklist: $e');
      return {'blacklisted': false, 'error': e.toString()};
    }
  }

  /// POST - Agregar lote a lista negra
  static Future<Map<String, dynamic>> addToBlacklist(
      Map<String, dynamic> data) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/blacklist'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(data),
      );

      final body = json.decode(response.body);

      if (response.statusCode == 201) {
        return {'success': true, 'message': body['message'], 'id': body['id']};
      }
      return {
        'success': false,
        'error': body['error'] ?? 'Error al agregar a lista negra'
      };
    } catch (e) {
      print('Error en addToBlacklist: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  /// PUT - Actualizar registro en blacklist
  static Future<Map<String, dynamic>> updateBlacklist(
      int id, Map<String, dynamic> data) async {
    try {
      final response = await http.put(
        Uri.parse('$baseUrl/blacklist/$id'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(data),
      );

      final body = json.decode(response.body);

      if (response.statusCode == 200) {
        return {'success': true, 'message': body['message']};
      }
      return {
        'success': false,
        'error': body['error'] ?? 'Error al actualizar'
      };
    } catch (e) {
      print('Error en updateBlacklist: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  /// GET - Buscar en blacklist
  static Future<List<Map<String, dynamic>>> searchBlacklist({
    String? fechaInicio,
    String? fechaFin,
    String? texto,
  }) async {
    try {
      String url = '$baseUrl/blacklist/search?';
      if (fechaInicio != null) url += 'fecha_inicio=$fechaInicio&';
      if (fechaFin != null) url += 'fecha_fin=$fechaFin&';
      if (texto != null && texto.isNotEmpty)
        url += 'texto=${Uri.encodeComponent(texto)}';

      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return data.cast<Map<String, dynamic>>();
      }
      return [];
    } catch (e) {
      print('Error en searchBlacklist: $e');
      return [];
    }
  }

  /// DELETE - Eliminar lote de lista negra
  static Future<Map<String, dynamic>> removeFromBlacklist(int id) async {
    try {
      final response = await http.delete(Uri.parse('$baseUrl/blacklist/$id'));

      final body = json.decode(response.body);

      if (response.statusCode == 200) {
        return {'success': true, 'message': body['message']};
      }
      return {
        'success': false,
        'error': body['error'] ?? 'Error al eliminar de lista negra'
      };
    } catch (e) {
      print('Error en removeFromBlacklist: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  // ============================================
  // GESTIÓN DE USUARIOS
  // ============================================

  // GET - Listar todos los usuarios
  static Future<List<Map<String, dynamic>>> getUsers() async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/users'));
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return data.map((e) => Map<String, dynamic>.from(e)).toList();
      }
      return [];
    } catch (e) {
      print('Error en getUsers: $e');
      return [];
    }
  }

  // GET - Obtener usuario por ID
  static Future<Map<String, dynamic>?> getUserById(int id) async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/users/$id'));
      if (response.statusCode == 200) {
        return json.decode(response.body);
      }
      return null;
    } catch (e) {
      print('Error en getUserById: $e');
      return null;
    }
  }

  // POST - Crear nuevo usuario
  static Future<Map<String, dynamic>> createUser({
    required String username,
    required String password,
    String? email,
    required String nombreCompleto,
    required String departamento,
    required String cargo,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/users'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'username': username,
          'password': password,
          'email': email,
          'nombre_completo': nombreCompleto,
          'departamento': departamento,
          'cargo': cargo,
        }),
      );

      final data = json.decode(response.body);
      if (response.statusCode == 201) {
        return {'success': true, 'id': data['id']};
      }
      return {
        'success': false,
        'error': data['error'] ?? 'Error al crear usuario'
      };
    } catch (e) {
      print('Error en createUser: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  // PUT - Actualizar usuario
  static Future<Map<String, dynamic>> updateUser({
    required int id,
    String? email,
    required String nombreCompleto,
    required String departamento,
    required String cargo,
  }) async {
    try {
      final response = await http.put(
        Uri.parse('$baseUrl/users/$id'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'email': email,
          'nombre_completo': nombreCompleto,
          'departamento': departamento,
          'cargo': cargo,
        }),
      );

      if (response.statusCode == 200) {
        return {'success': true};
      }
      final data = json.decode(response.body);
      return {
        'success': false,
        'error': data['error'] ?? 'Error al actualizar'
      };
    } catch (e) {
      print('Error en updateUser: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  // PUT - Cambiar contraseña de usuario
  static Future<Map<String, dynamic>> changeUserPassword({
    required int id,
    required String newPassword,
  }) async {
    try {
      final response = await http.put(
        Uri.parse('$baseUrl/users/$id/password'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'newPassword': newPassword}),
      );

      if (response.statusCode == 200) {
        return {'success': true};
      }
      final data = json.decode(response.body);
      return {
        'success': false,
        'error': data['error'] ?? 'Error al cambiar contraseña'
      };
    } catch (e) {
      print('Error en changeUserPassword: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  // PUT - Activar/desactivar usuario
  static Future<Map<String, dynamic>> toggleUserActive(int id) async {
    try {
      final response = await http.put(
        Uri.parse('$baseUrl/users/$id/toggle-active'),
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return {'success': true, 'activo': data['activo']};
      }
      final data = json.decode(response.body);
      return {'success': false, 'error': data['error'] ?? 'Error'};
    } catch (e) {
      print('Error en toggleUserActive: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  // GET - Listar departamentos disponibles
  static Future<List<String>> getDepartments() async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/departments'));
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return data.map((e) => e.toString()).toList();
      }
      return [];
    } catch (e) {
      print('Error en getDepartments: $e');
      return [];
    }
  }

  // GET - Listar cargos disponibles
  static Future<List<String>> getCargos() async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/cargos'));
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return data.map((e) => e.toString()).toList();
      }
      return [];
    } catch (e) {
      print('Error en getCargos: $e');
      return [];
    }
  }

  // ============================================
  // PERMISOS DE USUARIOS
  // ============================================

  // GET - Listar todos los permisos disponibles del sistema
  static Future<List<Map<String, dynamic>>> getAvailablePermissions() async {
    try {
      final response =
          await http.get(Uri.parse('$baseUrl/permissions/available'));
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return data.map((e) => Map<String, dynamic>.from(e)).toList();
      }
      return [];
    } catch (e) {
      print('Error en getAvailablePermissions: $e');
      return [];
    }
  }

  // GET - Obtener permisos de un usuario específico
  static Future<List<Map<String, dynamic>>> getUserPermissions(
      int userId) async {
    try {
      final response =
          await http.get(Uri.parse('$baseUrl/users/$userId/permissions'));
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return data.map((e) => Map<String, dynamic>.from(e)).toList();
      }
      return [];
    } catch (e) {
      print('Error en getUserPermissions: $e');
      return [];
    }
  }

  // PUT - Actualizar permisos de un usuario
  static Future<Map<String, dynamic>> updateUserPermissions({
    required int userId,
    required List<Map<String, dynamic>> permissions,
  }) async {
    try {
      final response = await http.put(
        Uri.parse('$baseUrl/users/$userId/permissions'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'permissions': permissions}),
      );

      if (response.statusCode == 200) {
        return {'success': true};
      }
      final data = json.decode(response.body);
      return {
        'success': false,
        'error': data['error'] ?? 'Error al actualizar permisos'
      };
    } catch (e) {
      print('Error en updateUserPermissions: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  // ============================================
  // CAMBIO DE CONTRASEÑA PROPIA (usuario logueado)
  // ============================================

  // POST - Cambiar contraseña del usuario logueado (requiere contraseña actual)
  static Future<Map<String, dynamic>> changeOwnPassword({
    required int userId,
    required String currentPassword,
    required String newPassword,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/users/$userId/change-password'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'currentPassword': currentPassword,
          'newPassword': newPassword,
        }),
      );

      if (response.statusCode == 200) {
        return {'success': true};
      }
      final data = json.decode(response.body);
      return {
        'success': false,
        'error': data['error'] ?? 'Error al cambiar contraseña'
      };
    } catch (e) {
      print('Error en changeOwnPassword: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  // ============================================
  // SOLICITUDES DE CANCELACIÓN
  // ============================================

  // POST - Solicitar cancelación de una entrada
  static Future<Map<String, dynamic>> requestCancellation({
    required int warehousingId,
    required String reason,
    required String requestedBy,
    int? requestedById,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/cancellation/request'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'warehousingId': warehousingId,
          'reason': reason,
          'requestedBy': requestedBy,
          'requestedById': requestedById,
        }),
      );

      final data = json.decode(response.body);
      if (response.statusCode == 201) {
        return {'success': true, 'id': data['id']};
      }
      return {
        'success': false,
        'error': data['error'] ?? 'Error al solicitar cancelación'
      };
    } catch (e) {
      print('Error en requestCancellation: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  // GET - Obtener solicitudes de cancelación pendientes
  static Future<List<Map<String, dynamic>>> getPendingCancellations() async {
    try {
      final response =
          await http.get(Uri.parse('$baseUrl/cancellation/pending'));
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return data.cast<Map<String, dynamic>>();
      }
      return [];
    } catch (e) {
      print('Error en getPendingCancellations: $e');
      return [];
    }
  }

  // GET - Obtener conteo de solicitudes pendientes
  static Future<int> getPendingCancellationsCount() async {
    try {
      final response =
          await http.get(Uri.parse('$baseUrl/cancellation/pending/count'));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['count'] ?? 0;
      }
      return 0;
    } catch (e) {
      print('Error en getPendingCancellationsCount: $e');
      return 0;
    }
  }

  // POST - Aprobar solicitud de cancelación
  static Future<Map<String, dynamic>> approveCancellation({
    required int requestId,
    required String reviewedBy,
    int? reviewedById,
    String? reviewNotes,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/cancellation/$requestId/approve'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'reviewedBy': reviewedBy,
          'reviewedById': reviewedById,
          'reviewNotes': reviewNotes,
        }),
      );

      final data = json.decode(response.body);
      if (response.statusCode == 200) {
        return {'success': true, 'message': data['message']};
      }
      return {'success': false, 'error': data['error'] ?? 'Error al aprobar'};
    } catch (e) {
      print('Error en approveCancellation: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  // POST - Rechazar solicitud de cancelación
  static Future<Map<String, dynamic>> rejectCancellation({
    required int requestId,
    required String reviewedBy,
    int? reviewedById,
    required String reviewNotes,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/cancellation/$requestId/reject'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'reviewedBy': reviewedBy,
          'reviewedById': reviewedById,
          'reviewNotes': reviewNotes,
        }),
      );

      final data = json.decode(response.body);
      if (response.statusCode == 200) {
        return {'success': true, 'message': data['message']};
      }
      return {'success': false, 'error': data['error'] ?? 'Error al rechazar'};
    } catch (e) {
      print('Error en rejectCancellation: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  // GET - Obtener estado de cancelación de una entrada
  static Future<Map<String, dynamic>> getCancellationStatus(
      int warehousingId) async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/cancellation/status/$warehousingId'));
      if (response.statusCode == 200) {
        return json.decode(response.body);
      }
      return {
        'isCancelled': false,
        'hasPendingRequest': false,
        'pendingRequest': null
      };
    } catch (e) {
      print('Error en getCancellationStatus: $e');
      return {
        'isCancelled': false,
        'hasPendingRequest': false,
        'pendingRequest': null
      };
    }
  }

  // GET - Obtener historial de cancelaciones de una entrada
  static Future<List<Map<String, dynamic>>> getCancellationHistory(
      int warehousingId) async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/cancellation/history/$warehousingId'));
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return data.cast<Map<String, dynamic>>();
      }
      return [];
    } catch (e) {
      print('Error en getCancellationHistory: $e');
      return [];
    }
  }

  // GET - Obtener todas las solicitudes de cancelación (historial completo)
  static Future<List<Map<String, dynamic>>> getAllCancellationRequests(
      {String? status, int limit = 100}) async {
    try {
      String url = '$baseUrl/cancellation/all?limit=$limit';
      if (status != null) {
        url += '&status=$status';
      }
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return data.cast<Map<String, dynamic>>();
      }
      return [];
    } catch (e) {
      print('Error en getAllCancellationRequests: $e');
      return [];
    }
  }

  // ==================== MATERIAL RETURN API ====================

  // GET - Obtener todas las devoluciones de material
  static Future<List<Map<String, dynamic>>> getReturns() async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/return'));
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return data.cast<Map<String, dynamic>>();
      }
      return [];
    } catch (e) {
      print('Error en getReturns: $e');
      return [];
    }
  }

  // GET - Buscar devoluciones por rango de fecha y texto
  static Future<List<Map<String, dynamic>>> searchReturns({
    DateTime? fechaInicio,
    DateTime? fechaFin,
    String? texto,
  }) async {
    try {
      final Map<String, String> queryParams = {};
      if (fechaInicio != null) {
        queryParams['fechaInicio'] =
            fechaInicio.toIso8601String().split('T')[0];
      }
      if (fechaFin != null) {
        queryParams['fechaFin'] = fechaFin.toIso8601String().split('T')[0];
      }
      if (texto != null && texto.isNotEmpty) {
        queryParams['texto'] = texto;
      }

      final uri = Uri.parse('$baseUrl/return/search')
          .replace(queryParameters: queryParams);
      final response = await http.get(uri);

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return data.cast<Map<String, dynamic>>();
      }
      return [];
    } catch (e) {
      print('Error en searchReturns: $e');
      return [];
    }
  }

  // GET - Obtener estadísticas de devoluciones
  static Future<Map<String, dynamic>> getReturnStats() async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/return/stats'));
      if (response.statusCode == 200) {
        return json.decode(response.body);
      }
      return {};
    } catch (e) {
      print('Error en getReturnStats: $e');
      return {};
    }
  }

  // POST - Crear nueva devolución de material
  static Future<Map<String, dynamic>> createReturn(
      Map<String, dynamic> data) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/return'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(data),
      );
      if (response.statusCode == 201) {
        return {'success': true, 'data': json.decode(response.body)};
      }
      final error = json.decode(response.body);
      return {
        'success': false,
        'error': error['error'] ?? 'Error al crear devolución'
      };
    } catch (e) {
      print('Error en createReturn: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  // PUT - Actualizar devolución de material
  static Future<Map<String, dynamic>> updateReturn(
      int id, Map<String, dynamic> data) async {
    try {
      final response = await http.put(
        Uri.parse('$baseUrl/return/$id'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(data),
      );
      if (response.statusCode == 200) {
        return {'success': true, 'data': json.decode(response.body)};
      }
      final error = json.decode(response.body);
      return {
        'success': false,
        'error': error['error'] ?? 'Error al actualizar devolución'
      };
    } catch (e) {
      print('Error en updateReturn: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  // DELETE - Eliminar devolución de material
  static Future<Map<String, dynamic>> deleteReturn(int id) async {
    try {
      final response = await http.delete(Uri.parse('$baseUrl/return/$id'));
      if (response.statusCode == 200) {
        return {'success': true};
      }
      final error = json.decode(response.body);
      return {
        'success': false,
        'error': error['error'] ?? 'Error al eliminar devolución'
      };
    } catch (e) {
      print('Error en deleteReturn: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  // POST - Aprobar devolución de material
  static Future<Map<String, dynamic>> approveReturn(int id,
      {String? notes}) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/return/$id/approve'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'notes': notes}),
      );
      if (response.statusCode == 200) {
        return {'success': true, 'data': json.decode(response.body)};
      }
      final error = json.decode(response.body);
      return {
        'success': false,
        'error': error['error'] ?? 'Error al aprobar devolución'
      };
    } catch (e) {
      print('Error en approveReturn: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  // POST - Rechazar devolución de material
  static Future<Map<String, dynamic>> rejectReturn(int id,
      {String? notes}) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/return/$id/reject'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'notes': notes}),
      );
      if (response.statusCode == 200) {
        return {'success': true, 'data': json.decode(response.body)};
      }
      final error = json.decode(response.body);
      return {
        'success': false,
        'error': error['error'] ?? 'Error al rechazar devolución'
      };
    } catch (e) {
      print('Error en rejectReturn: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  // POST - Completar devolución de material
  static Future<Map<String, dynamic>> completeReturn(int id) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/return/$id/complete'),
        headers: {'Content-Type': 'application/json'},
      );
      if (response.statusCode == 200) {
        return {'success': true, 'data': json.decode(response.body)};
      }
      final error = json.decode(response.body);
      return {
        'success': false,
        'error': error['error'] ?? 'Error al completar devolución'
      };
    } catch (e) {
      print('Error en completeReturn: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  // ============================================
  // AUDIT - Sistema de Auditoria de Inventario
  // ============================================
  // Este bloque encapsula llamadas REST usadas por PC (supervisor)
  // y por la app movil para escaneo. El backend aplica la logica
  // de estados (Found/Missing/ProcessedOut) y validacion de ubicacion.

  // GET - Obtener auditoria activa
  // Devuelve null cuando no hay auditoria (status Pending/InProgress).
  static Future<Map<String, dynamic>> getActiveAudit() async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/audit/active'));
      if (response.statusCode == 200) {
        final body = json.decode(response.body);
        // El backend devuelve {active: bool, audit: object|null}
        if (body['active'] == true && body['audit'] != null) {
          return {'success': true, 'data': body['audit']};
        }
        return {'success': true, 'data': null}; // No hay auditoría activa
      }
      if (response.statusCode == 404) {
        return {'success': true, 'data': null}; // No hay auditoría activa
      }
      final error = json.decode(response.body);
      return {
        'success': false,
        'error': error['error'] ?? 'Error al obtener auditoría'
      };
    } catch (e) {
      print('Error en getActiveAudit: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  // POST - Iniciar nueva auditoria (solo supervisor desde PC)
  // El backend genera ubicaciones e items esperados a partir del inventario activo.
  static Future<Map<String, dynamic>> startAudit(int startedBy) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/audit/start'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'usuario_inicio': startedBy}),
      );
      if (response.statusCode == 200 || response.statusCode == 201) {
        final body = json.decode(response.body);
        if (body['success'] == true || body['auditId'] != null) {
          return {'success': true, 'data': body};
        }
        return {
          'success': false,
          'error': body['error'] ?? 'Error al iniciar auditoría'
        };
      }
      final error = json.decode(response.body);
      return {
        'success': false,
        'error': error['error'] ?? 'Error al iniciar auditoría'
      };
    } catch (e) {
      print('Error en startAudit: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  // POST - Terminar auditoria (solo supervisor desde PC)
  // confirmar_discrepancias=true aplica salida real a items Missing.
  static Future<Map<String, dynamic>> endAudit(
    int auditId,
    int endedBy, {
    bool processDiscrepancies = false,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/audit/end'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'auditId': auditId,
          'usuario_fin': endedBy,
          'confirmar_discrepancias': processDiscrepancies,
        }),
      );
      if (response.statusCode == 200) {
        return {'success': true, 'data': json.decode(response.body)};
      }
      final error = json.decode(response.body);
      return {
        'success': false,
        'error': error['error'] ?? 'Error al terminar auditoría'
      };
    } catch (e) {
      print('Error en endAudit: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  // GET - Obtener ubicaciones de una auditoria con su estado
  // Incluye conteos Found/Missing para UI de progreso.
  static Future<Map<String, dynamic>> getAuditLocations(int auditId) async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/audit/locations?auditId=$auditId'));
      if (response.statusCode == 200) {
        return {'success': true, 'data': json.decode(response.body)};
      }
      final error = json.decode(response.body);
      return {
        'success': false,
        'error': error['error'] ?? 'Error al obtener ubicaciones'
      };
    } catch (e) {
      print('Error en getAuditLocations: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  // GET - Obtener materiales de una ubicacion en auditoria
  // audit_status = Pending cuando no hay registro en inventory_audit_item.
  static Future<Map<String, dynamic>> getAuditLocationItems(
      int auditId, String location) async {
    try {
      final response = await http.get(
        Uri.parse(
            '$baseUrl/audit/location-items?auditId=$auditId&location=${Uri.encodeComponent(location)}'),
      );
      if (response.statusCode == 200) {
        return {'success': true, 'data': json.decode(response.body)};
      }
      final error = json.decode(response.body);
      return {
        'success': false,
        'error': error['error'] ?? 'Error al obtener items'
      };
    } catch (e) {
      print('Error en getAuditLocationItems: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  // GET - Resumen de auditoria
  // Resume estados por ubicacion e item para cierre del supervisor.
  static Future<Map<String, dynamic>> getAuditSummary(int auditId) async {
    try {
      final response =
          await http.get(Uri.parse('$baseUrl/audit/summary?auditId=$auditId'));
      if (response.statusCode == 200) {
        return {'success': true, 'data': json.decode(response.body)};
      }
      final error = json.decode(response.body);
      return {
        'success': false,
        'error': error['error'] ?? 'Error al obtener resumen'
      };
    } catch (e) {
      print('Error en getAuditSummary: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  // POST - Escanear ubicacion (operador movil)
  // Inicia la ubicacion y devuelve lista de items esperados.
  static Future<Map<String, dynamic>> auditScanLocation({
    required int auditId,
    required String location,
    required int scannedBy,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/audit/scan-location'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'auditId': auditId,
          'location': location,
          'usuario': scannedBy,
          'response_mode': 'summary',
        }),
      );
      if (response.statusCode == 200) {
        return {'success': true, 'data': json.decode(response.body)};
      }
      final error = json.decode(response.body);
      return {
        'success': false,
        'error': error['error'] ?? 'Error al escanear ubicación'
      };
    } catch (e) {
      print('Error en auditScanLocation: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  // POST - Escanear material (operador movil)
  // El backend valida ubicacion y evita escaneo duplicado.
  static Future<Map<String, dynamic>> auditScanItem({
    required int auditId,
    required String location,
    required String warehousingCode,
    required int scannedBy,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/audit/scan-item'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'warehousing_code': warehousingCode,
          'location': location,
          'usuario': scannedBy,
        }),
      );
      if (response.statusCode == 200) {
        final body = json.decode(response.body);
        // El backend puede devolver success: false con error
        if (body['success'] == false) {
          return {
            'success': false,
            'error': body['error'] ?? 'Error al escanear'
          };
        }
        return {'success': true, 'data': body};
      }
      final error = json.decode(response.body);
      return {
        'success': false,
        'error': error['error'] ?? 'Error al escanear material'
      };
    } catch (e) {
      print('Error en auditScanItem: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  // POST - Marcar material como faltante (operador movil)
  // Marca Missing y pone la ubicacion en Discrepancy.
  static Future<Map<String, dynamic>> auditMarkMissing({
    required int auditId,
    required int warehousingId,
    required String location,
    required int markedBy,
    String? notes,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/audit/mark-missing'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'warehousing_id': warehousingId,
          'location': location,
          'usuario': markedBy,
          'notas': notes,
        }),
      );
      if (response.statusCode == 200) {
        return {'success': true, 'data': json.decode(response.body)};
      }
      final error = json.decode(response.body);
      return {
        'success': false,
        'error': error['error'] ?? 'Error al marcar faltante'
      };
    } catch (e) {
      print('Error en auditMarkMissing: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  // POST - Completar ubicacion (operador movil)
  // El backend marca pendientes como Missing automaticamente.
  static Future<Map<String, dynamic>> auditCompleteLocation({
    required int auditId,
    required String location,
    required int completedBy,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/audit/complete-location'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'auditId': auditId,
          'location': location,
          'completedBy': completedBy,
        }),
      );
      if (response.statusCode == 200) {
        return {'success': true, 'data': json.decode(response.body)};
      }
      final error = json.decode(response.body);
      return {
        'success': false,
        'error': error['error'] ?? 'Error al completar ubicación'
      };
    } catch (e) {
      print('Error en auditCompleteLocation: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  // GET - Historial de auditorias
  // Solo auditorias Completed; el backend limita a 100.
  static Future<Map<String, dynamic>> getAuditHistory({int limit = 50}) async {
    try {
      final response =
          await http.get(Uri.parse('$baseUrl/audit/history?limit=$limit'));
      if (response.statusCode == 200) {
        return {'success': true, 'data': json.decode(response.body)};
      }
      final error = json.decode(response.body);
      return {
        'success': false,
        'error': error['error'] ?? 'Error al obtener historial'
      };
    } catch (e) {
      print('Error en getAuditHistory: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  // GET - Detalle de auditoria historica
  // Devuelve auditoria + ubicaciones + items + resumen por numero de parte.
  static Future<Map<String, dynamic>> getAuditHistoryDetail(int auditId) async {
    try {
      final response =
          await http.get(Uri.parse('$baseUrl/audit/history/$auditId'));
      if (response.statusCode == 200) {
        return {'success': true, 'data': json.decode(response.body)};
      }
      final error = json.decode(response.body);
      return {
        'success': false,
        'error': error['error'] ?? 'Error al obtener detalle'
      };
    } catch (e) {
      print('Error en getAuditHistoryDetail: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  // GET - Comparar dos auditorias (diferencias por numero de parte)
  // Comparacion usa conteos y cantidades para detectar variaciones.
  static Future<Map<String, dynamic>> compareAudits(
      int auditId1, int auditId2) async {
    try {
      final response = await http.get(Uri.parse(
          '$baseUrl/audit/compare?audit1=$auditId1&audit2=$auditId2'));
      if (response.statusCode == 200) {
        final body = json.decode(response.body);
        return {'success': true, 'data': body['comparison'] ?? body};
      }
      final error = json.decode(response.body);
      return {'success': false, 'error': error['error'] ?? 'Error al comparar'};
    } catch (e) {
      print('Error en compareAudits: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  // ============================================
  // AUDIT V2 - Flujo por número de parte
  // ============================================

  // GET - Obtener resumen de partes por ubicación
  static Future<Map<String, dynamic>> getAuditLocationSummary(
      String location) async {
    try {
      final response = await http.get(
        Uri.parse(
            '$baseUrl/audit/location-summary?location=${Uri.encodeComponent(location)}'),
      );
      if (response.statusCode == 200) {
        return {'success': true, 'data': json.decode(response.body)};
      }
      final error = json.decode(response.body);
      return {
        'success': false,
        'error': error['error'] ?? 'Error al obtener resumen'
      };
    } catch (e) {
      print('Error en getAuditLocationSummary: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  // POST - Confirmar parte como OK sin escaneo
  static Future<Map<String, dynamic>> confirmAuditPart({
    required String location,
    required String numeroParte,
    required int userId,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/audit/confirm-part'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'location': location,
          'numero_parte': numeroParte,
          'usuario': userId,
          'return_summary': 1,
        }),
      );
      if (response.statusCode == 200) {
        final body = json.decode(response.body);
        if (body['success'] == false) {
          return {
            'success': false,
            'error': body['error'] ?? 'Error al confirmar'
          };
        }
        return {'success': true, 'data': body};
      }
      final error = json.decode(response.body);
      return {
        'success': false,
        'error': error['error'] ?? 'Error al confirmar parte'
      };
    } catch (e) {
      print('Error en confirmAuditPart: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  // POST - Marcar parte como discrepancia
  static Future<Map<String, dynamic>> flagAuditMismatch({
    required String location,
    required String numeroParte,
    required int userId,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/audit/flag-mismatch'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'location': location,
          'numero_parte': numeroParte,
          'usuario': userId,
          'return_summary': 1,
        }),
      );
      if (response.statusCode == 200) {
        final body = json.decode(response.body);
        if (body['success'] == false) {
          return {
            'success': false,
            'error': body['error'] ?? 'Error al marcar'
          };
        }
        return {'success': true, 'data': body};
      }
      final error = json.decode(response.body);
      return {
        'success': false,
        'error': error['error'] ?? 'Error al marcar discrepancia'
      };
    } catch (e) {
      print('Error en flagAuditMismatch: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  // POST - Escanear etiqueta individual de una parte en Mismatch
  static Future<Map<String, dynamic>> scanAuditPartItem({
    required String location,
    required String warehousingCode,
    required int userId,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/audit/scan-part-item'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'location': location,
          'warehousing_code': warehousingCode,
          'usuario': userId,
          'return_summary': 1,
        }),
      );
      if (response.statusCode == 200) {
        final body = json.decode(response.body);
        if (body['success'] == false) {
          return {
            'success': false,
            'error': body['error'] ?? 'Error al escanear'
          };
        }
        return {'success': true, 'data': body};
      }
      final error = json.decode(response.body);
      return {
        'success': false,
        'error': error['error'] ?? 'Error al escanear material'
      };
    } catch (e) {
      print('Error en scanAuditPartItem: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  // POST - Confirmar faltantes de una parte en Mismatch
  static Future<Map<String, dynamic>> confirmAuditMissing({
    required String location,
    required String numeroParte,
    required int userId,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/audit/confirm-missing'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'location': location,
          'numero_parte': numeroParte,
          'usuario': userId,
          'return_summary': 1,
        }),
      );
      if (response.statusCode == 200) {
        final body = json.decode(response.body);
        if (body['success'] == false) {
          return {
            'success': false,
            'error': body['error'] ?? 'Error al confirmar'
          };
        }
        return {'success': true, 'data': body};
      }
      final error = json.decode(response.body);
      return {
        'success': false,
        'error': error['error'] ?? 'Error al confirmar faltantes'
      };
    } catch (e) {
      print('Error en confirmAuditMissing: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  // ============================================
  // RAW IPM (IC Part Mapping)
  // ============================================

  // GET - Obtener todos los registros de Raw IPM
  static Future<List<Map<String, dynamic>>> getRawIpm() async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/raw-ipm'));
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return data.cast<Map<String, dynamic>>();
      }
      return [];
    } catch (e) {
      print('Error en getRawIpm: $e');
      return [];
    }
  }

  // POST - Crear registro Raw IPM
  static Future<bool> createRawIpm(Map<String, dynamic> data) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/raw-ipm'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(data),
      );
      return response.statusCode == 200;
    } catch (e) {
      print('Error en createRawIpm: $e');
      return false;
    }
  }

  // PUT - Actualizar registro Raw IPM
  static Future<bool> updateRawIpm(int id, Map<String, dynamic> data) async {
    try {
      final response = await http.put(
        Uri.parse('$baseUrl/raw-ipm/$id'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(data),
      );
      return response.statusCode == 200;
    } catch (e) {
      print('Error en updateRawIpm: $e');
      return false;
    }
  }

  // DELETE - Eliminar registro Raw IPM
  static Future<bool> deleteRawIpm(int id) async {
    try {
      final response = await http.delete(Uri.parse('$baseUrl/raw-ipm/$id'));
      return response.statusCode == 200;
    } catch (e) {
      print('Error en deleteRawIpm: $e');
      return false;
    }
  }

  // POST - Carga masiva Raw IPM
  static Future<Map<String, dynamic>> bulkCreateRawIpm(
      List<Map<String, dynamic>> data) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/raw-ipm/bulk'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'data': data}),
      );
      if (response.statusCode == 200) {
        return json.decode(response.body);
      }
      return {'success': false, 'error': 'Error ${response.statusCode}'};
    } catch (e) {
      print('Error en bulkCreateRawIpm: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  // DELETE - Eliminar todos los registros Raw IPM
  static Future<Map<String, dynamic>> deleteAllRawIpm() async {
    try {
      final response = await http.delete(Uri.parse('$baseUrl/raw-ipm/all'));
      if (response.statusCode == 200) {
        return json.decode(response.body);
      }
      return {'success': false, 'error': 'Error ${response.statusCode}'};
    } catch (e) {
      print('Error en deleteAllRawIpm: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  // GET - Buscar en Raw IPM
  static Future<List<Map<String, dynamic>>> searchRawIpm(String query,
      {String? field}) async {
    try {
      String url = '$baseUrl/raw-ipm/search?q=${Uri.encodeComponent(query)}';
      if (field != null) url += '&field=$field';
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return data.cast<Map<String, dynamic>>();
      }
      return [];
    } catch (e) {
      print('Error en searchRawIpm: $e');
      return [];
    }
  }

  // ============================================
  // IPM (IC Part Mapping Scanner & Labels)
  // ============================================

  // GET - Consulta completa IPM (Part No IC + Part Lot Placa)
  static Future<Map<String, dynamic>> queryIpm({
    required String scanPartNoIc,
    String? scanPartLotPlaca,
  }) async {
    try {
      String url =
          '$baseUrl/ipm/query?scanPartNoIc=${Uri.encodeComponent(scanPartNoIc)}';
      if (scanPartLotPlaca != null && scanPartLotPlaca.isNotEmpty) {
        url += '&scanPartLotPlaca=${Uri.encodeComponent(scanPartLotPlaca)}';
      }
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else if (response.statusCode == 404) {
        final error = json.decode(response.body);
        return {'error': true, 'message': error['message'] ?? 'No encontrado'};
      }
      return {'error': true, 'message': 'Error ${response.statusCode}'};
    } catch (e) {
      print('Error en queryIpm: $e');
      return {'error': true, 'message': e.toString()};
    }
  }

  // POST - Guardar registro IPM
  static Future<Map<String, dynamic>> saveIpmRecord(
      Map<String, dynamic> data) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/ipm'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(data),
      );
      if (response.statusCode == 200) {
        return json.decode(response.body);
      }
      return {'success': false, 'error': 'Error ${response.statusCode}'};
    } catch (e) {
      print('Error en saveIpmRecord: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  // GET - Historial de registros IPM
  static Future<Map<String, dynamic>> getIpmHistory({
    int limit = 100,
    int offset = 0,
    String? search,
    String? startDate,
    String? endDate,
  }) async {
    try {
      String url = '$baseUrl/ipm/history?limit=$limit&offset=$offset';
      if (search != null && search.isNotEmpty) {
        url += '&search=${Uri.encodeComponent(search)}';
      }
      if (startDate != null && startDate.isNotEmpty) {
        url += '&startDate=$startDate';
      }
      if (endDate != null && endDate.isNotEmpty) {
        url += '&endDate=$endDate';
      }
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        return json.decode(response.body);
      }
      return {'data': [], 'total': 0};
    } catch (e) {
      print('Error en getIpmHistory: $e');
      return {'data': [], 'total': 0};
    }
  }

  // DELETE - Eliminar registro IPM
  static Future<bool> deleteIpmRecord(int id) async {
    try {
      final response = await http.delete(Uri.parse('$baseUrl/ipm/$id'));
      return response.statusCode == 200;
    } catch (e) {
      print('Error en deleteIpmRecord: $e');
      return false;
    }
  }

  // ============================================
  // SMT MATERIAL REQUESTS
  // ============================================

  // GET - Listar solicitudes de material SMT
  static Future<List<Map<String, dynamic>>> getSMTRequests({
    String? status,
    String? lineId,
    String? workingDate,
    int limit = 100,
    bool compact = false,
  }) async {
    try {
      final queryParams = <String>[
        if (status != null && status.isNotEmpty)
          'status=${Uri.encodeQueryComponent(status)}',
        if (lineId != null && lineId.isNotEmpty)
          'lineId=${Uri.encodeQueryComponent(lineId)}',
        if (workingDate != null && workingDate.isNotEmpty)
          'workingDate=${Uri.encodeQueryComponent(workingDate)}',
        'limit=$limit',
        if (compact) 'compact=1',
      ];

      final query = queryParams.isEmpty ? '' : '?${queryParams.join('&')}';
      final response = await http.get(
        Uri.parse('$baseUrl/smt-requests$query'),
      );

      if (response.statusCode == 200) {
        final body = json.decode(response.body);
        if (body is Map<String, dynamic> && body['requests'] is List) {
          return (body['requests'] as List).cast<Map<String, dynamic>>();
        }
      }
      return [];
    } catch (e) {
      print('Error en getSMTRequests: $e');
      return [];
    }
  }

  static Future<int> getSMTRequestsPendingCount({String? lineId}) async {
    try {
      final query = (lineId != null && lineId.isNotEmpty)
          ? '?lineId=${Uri.encodeQueryComponent(lineId)}'
          : '';
      final response = await http.get(
        Uri.parse('$baseUrl/smt-requests/pending-count$query'),
      );

      if (response.statusCode == 200) {
        final body = json.decode(response.body);
        if (body is Map<String, dynamic>) {
          final dynamic count = body['count'] ?? body['pendingCount'];
          if (count is int) return count;
          if (count is num) return count.toInt();
          if (count is String) return int.tryParse(count) ?? 0;
        }
      }
      return 0;
    } catch (e) {
      print('Error en getSMTRequestsPendingCount: $e');
      return 0;
    }
  }

  // PUT - Marcar solicitud SMT como surtida
  static Future<bool> fulfillSMTRequest(int id, {String? fulfilledBy}) async {
    try {
      final response = await http.put(
        Uri.parse('$baseUrl/smt-requests/$id/fulfill'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          if (fulfilledBy != null && fulfilledBy.isNotEmpty)
            'fulfilledBy': fulfilledBy,
        }),
      );

      if (response.statusCode == 200) {
        final body = json.decode(response.body);
        return body['ok'] == true || body['success'] == true;
      }
      return false;
    } catch (e) {
      print('Error en fulfillSMTRequest: $e');
      return false;
    }
  }

  // POST - Registrar token FCM para solicitudes SMT
  static Future<Map<String, dynamic>> registerFCMToken(
    String token, {
    String? baseUrlOverride,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('${baseUrlOverride ?? baseUrl}/smt-requests/fcm-token'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'token': token}),
      );

      if (response.statusCode == 200) {
        final body = json.decode(response.body);
        if (body is Map<String, dynamic>) {
          return body;
        }
      }
      return {'ok': false, 'error': 'Error ${response.statusCode}'};
    } catch (e) {
      print('Error en registerFCMToken: $e');
      return {'ok': false, 'error': e.toString()};
    }
  }

  // ============================================
  // REQUIREMENTS (Requerimientos de Material)
  // ============================================

  // GET - Listar requerimientos con filtros opcionales
  static Future<List<Map<String, dynamic>>> getRequirements({
    String? area,
    String? status,
    String? fechaInicio,
    String? fechaFin,
    String? prioridad,
    bool pendingOnly = false,
  }) async {
    try {
      String url = '$baseUrl/requirements?';
      if (area != null) url += 'area=$area&';
      if (status != null) url += 'status=$status&';
      if (fechaInicio != null) url += 'fecha_inicio=$fechaInicio&';
      if (fechaFin != null) url += 'fecha_fin=$fechaFin&';
      if (prioridad != null) url += 'prioridad=$prioridad&';
      if (pendingOnly) url += 'pending_only=true&';

      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return data.cast<Map<String, dynamic>>();
      }
      return [];
    } catch (e) {
      print('Error en getRequirements: $e');
      return [];
    }
  }

  // GET - Obtener áreas disponibles
  static Future<List<String>> getRequirementAreas() async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/requirements/areas'));
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return data.cast<String>();
      }
      return [];
    } catch (e) {
      print('Error en getRequirementAreas: $e');
      return [];
    }
  }

  // GET - Obtener requerimientos pendientes para módulo de salidas
  static Future<List<Map<String, dynamic>>> getPendingRequirementsForOutgoing(
      {String? area}) async {
    try {
      String url = '$baseUrl/requirements/pending-for-outgoing';
      if (area != null) url += '?area=$area';

      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return data.cast<Map<String, dynamic>>();
      }
      return [];
    } catch (e) {
      print('Error en getPendingRequirementsForOutgoing: $e');
      return [];
    }
  }

  // GET - Contador de pendientes (para badge)
  static Future<int> getRequirementsPendingCount() async {
    try {
      final response =
          await http.get(Uri.parse('$baseUrl/requirements/count-pending'));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['count'] ?? 0;
      }
      return 0;
    } catch (e) {
      print('Error en getRequirementsPendingCount: $e');
      return 0;
    }
  }

  // GET - Requerimiento por ID con items
  static Future<Map<String, dynamic>?> getRequirementById(int id) async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/requirements/$id'));
      if (response.statusCode == 200) {
        return json.decode(response.body);
      }
      return null;
    } catch (e) {
      print('Error en getRequirementById: $e');
      return null;
    }
  }

  // POST - Crear requerimiento
  static Future<bool> createRequirement(Map<String, dynamic> data) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/requirements'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(data),
      );
      return response.statusCode == 201;
    } catch (e) {
      print('Error en createRequirement: $e');
      return false;
    }
  }

  // PUT - Actualizar requerimiento
  static Future<bool> updateRequirement(
      int id, Map<String, dynamic> data) async {
    try {
      final response = await http.put(
        Uri.parse('$baseUrl/requirements/$id'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(data),
      );
      return response.statusCode == 200;
    } catch (e) {
      print('Error en updateRequirement: $e');
      return false;
    }
  }

  // DELETE - Cancelar requerimiento
  static Future<bool> cancelRequirement(int id, String? canceladoPor) async {
    try {
      final response = await http.delete(
        Uri.parse('$baseUrl/requirements/$id'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'actualizado_por': canceladoPor}),
      );
      return response.statusCode == 200;
    } catch (e) {
      print('Error en cancelRequirement: $e');
      return false;
    }
  }

  // GET - Items de un requerimiento
  static Future<List<Map<String, dynamic>>> getRequirementItems(
      int requirementId) async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/requirements/$requirementId/items'));
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return data.cast<Map<String, dynamic>>();
      }
      return [];
    } catch (e) {
      print('Error en getRequirementItems: $e');
      return [];
    }
  }

  // POST - Agregar items a requerimiento
  static Future<bool> addRequirementItems(
      int requirementId, List<Map<String, dynamic>> items) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/requirements/$requirementId/items'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'items': items}),
      );
      return response.statusCode == 200;
    } catch (e) {
      print('Error en addRequirementItems: $e');
      return false;
    }
  }

  // PUT - Actualizar item
  static Future<bool> updateRequirementItem(
      int requirementId, int itemId, Map<String, dynamic> data) async {
    try {
      final response = await http.put(
        Uri.parse('$baseUrl/requirements/$requirementId/items/$itemId'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(data),
      );
      return response.statusCode == 200;
    } catch (e) {
      print('Error en updateRequirementItem: $e');
      return false;
    }
  }

  // DELETE - Eliminar item
  static Future<bool> removeRequirementItem(
      int requirementId, int itemId) async {
    try {
      final response = await http.delete(
        Uri.parse('$baseUrl/requirements/$requirementId/items/$itemId'),
      );
      return response.statusCode == 200;
    } catch (e) {
      print('Error en removeRequirementItem: $e');
      return false;
    }
  }

  // POST - Eliminar múltiples items (solo el creador puede eliminar)
  static Future<Map<String, dynamic>> removeMultipleRequirementItems(
      int requirementId, List<int> itemIds, String usuario) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/requirements/$requirementId/items/delete-multiple'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'itemIds': itemIds, 'usuario': usuario}),
      );
      if (response.statusCode == 200) {
        return {'success': true, ...json.decode(response.body)};
      } else if (response.statusCode == 403) {
        final body = json.decode(response.body);
        return {
          'success': false,
          'error': body['error'],
          'creador': body['creador']
        };
      } else {
        return {'success': false, 'error': 'Error al eliminar items'};
      }
    } catch (e) {
      print('Error en removeMultipleRequirementItems: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  // GET - Importar materials desde BOM
  static Future<List<Map<String, dynamic>>> importRequirementsBom(String modelo,
      {int cantidad = 1}) async {
    try {
      final response = await http.get(
        Uri.parse(
            '$baseUrl/requirements/import-bom/$modelo?cantidad=$cantidad'),
      );
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return data.cast<Map<String, dynamic>>();
      }
      return [];
    } catch (e) {
      print('Error en importRequirementsBom: $e');
      return [];
    }
  }

  // POST - Vincular salida a requerimiento
  static Future<Map<String, dynamic>> linkOutgoingToRequirement({
    required String numeroParte,
    required String areaDestino,
    required int cantidad,
    String? codigoSalida,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/requirements/link-outgoing'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'numero_parte': numeroParte,
          'area_destino': areaDestino,
          'cantidad': cantidad,
          'codigo_salida': codigoSalida,
        }),
      );
      if (response.statusCode == 200) {
        return json.decode(response.body);
      }
      return {'linked': false, 'error': 'Error ${response.statusCode}'};
    } catch (e) {
      print('Error en linkOutgoingToRequirement: $e');
      return {'linked': false, 'error': e.toString()};
    }
  }

  // ============================================
  // REENTRY (Reingreso / Reubicación)
  // ============================================

  static Future<List<Map<String, dynamic>>> getReentryByCodes(
      List<String> codes) async {
    try {
      final cleanCodes = codes
          .map((code) => code.trim())
          .where((code) => code.isNotEmpty)
          .toSet()
          .toList();
      if (cleanCodes.isEmpty) return [];

      final response = await http.post(
        Uri.parse('$baseUrl/reentry/by-codes'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'codes': cleanCodes}),
      );
      if (response.statusCode == 200) {
        final body = json.decode(response.body);
        if (body is Map<String, dynamic> && body['results'] is List) {
          return (body['results'] as List).cast<Map<String, dynamic>>();
        }
      }
      return [];
    } catch (e) {
      print('Error en getReentryByCodes: $e');
      return [];
    }
  }

  // GET - Buscar material por código para reingreso
  static Future<Map<String, dynamic>?> getReentryByCode(String code) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/reentry/by-code/${Uri.encodeComponent(code)}'),
      );
      if (response.statusCode == 200) {
        return json.decode(response.body);
      }
      return null;
    } catch (e) {
      print('Error en getReentryByCode: $e');
      return null;
    }
  }

  // PUT - Actualizar ubicación de material (reingreso individual)
  static Future<Map<String, dynamic>> updateMaterialLocation(
    int id,
    String newLocation,
    String? userId,
  ) async {
    try {
      final response = await http.put(
        Uri.parse('$baseUrl/reentry/$id/location'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'nueva_ubicacion': newLocation,
          'usuario_reingreso': userId,
        }),
      );

      if (response.statusCode == 200) {
        final body = json.decode(response.body);
        return {
          'success': true,
          'message': body['message'],
          'codigo': body['codigo'],
          'ubicacion_anterior': body['ubicacion_anterior'],
          'nueva_ubicacion': body['nueva_ubicacion'],
        };
      }

      try {
        final body = json.decode(response.body);
        return {
          'success': false,
          'error': body['error'] ?? 'Error desconocido'
        };
      } catch (_) {
        return {'success': false, 'error': 'Error ${response.statusCode}'};
      }
    } catch (e) {
      print('Error en updateMaterialLocation: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  // POST - Reingreso masivo (múltiples materiales)
  static Future<Map<String, dynamic>> bulkReentry(
    List<int> ids,
    String newLocation,
    String? userId,
  ) async {
    try {
      // No enviar fecha_reingreso - el backend usa NOW() de MySQL
      final response = await http.post(
        Uri.parse('$baseUrl/reentry/bulk'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'ids': ids,
          'nueva_ubicacion': newLocation,
          'usuario_reingreso': userId,
        }),
      );

      if (response.statusCode == 200) {
        return {'success': true, ...json.decode(response.body)};
      }
      return {'success': false, 'error': 'Error ${response.statusCode}'};
    } catch (e) {
      print('Error en bulkReentry: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  // ============================================
  // SHORTAGE (Faltante de Material SMD)
  // ============================================

  // GET - Calcular faltante de material para una fecha
  static Future<Map<String, dynamic>> getShortageCalculation({
    required String date,
    String? line,
  }) async {
    try {
      String url = '$baseUrl/shortage?date=$date';
      if (line != null && line.isNotEmpty)
        url += '&line=${Uri.encodeComponent(line)}';

      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        return json.decode(response.body) as Map<String, dynamic>;
      } else {
        throw Exception('Error: ${response.statusCode}');
      }
    } catch (e) {
      print('Error en getShortageCalculation: $e');
      return {'items': [], 'total_components': 0, 'shortage_count': 0};
    }
  }

  // GET - Obtener lineas disponibles para una fecha
  static Future<List<String>> getShortageLines({required String date}) async {
    try {
      final response =
          await http.get(Uri.parse('$baseUrl/shortage/lines?date=$date'));
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return data.cast<String>();
      }
      return [];
    } catch (e) {
      print('Error en getShortageLines: $e');
      return [];
    }
  }

  // GET - Historial de reingresos
  static Future<List<Map<String, dynamic>>> getReentryHistory({
    String? fechaInicio,
    String? fechaFin,
    DateTime? startDate,
    DateTime? endDate,
    String? texto,
    int limit = 100,
  }) async {
    try {
      String url = '$baseUrl/reentry/history?limit=$limit';

      // Usar DateTime si se proporcionan
      if (startDate != null && endDate != null) {
        final inicio =
            '${startDate.year}-${startDate.month.toString().padLeft(2, '0')}-${startDate.day.toString().padLeft(2, '0')}';
        final fin =
            '${endDate.year}-${endDate.month.toString().padLeft(2, '0')}-${endDate.day.toString().padLeft(2, '0')}';
        url += '&fecha_inicio=$inicio&fecha_fin=$fin';
      } else if (fechaInicio != null && fechaFin != null) {
        url += '&fecha_inicio=$fechaInicio&fecha_fin=$fechaFin';
      }

      if (texto != null && texto.isNotEmpty) {
        url += '&texto=${Uri.encodeComponent(texto)}';
      }

      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return data.cast<Map<String, dynamic>>();
      }
      return [];
    } catch (e) {
      print('Error en getReentryHistory: $e');
      return [];
    }
  }

  // ============================================
  // PCB INVENTORY
  // ============================================

  // POST - Registrar escaneo de PCB (ENTRADA, SALIDA o SCRAP)
  // area: INVENTARIO | REPARACION
  // proceso: SMD | IMD | ASSY
  static Future<Map<String, dynamic>> scanPcbInventory({
    required String scannedCode,
    required String inventoryDate,
    required String proceso,
    String area = 'INVENTARIO',
    String tipoMovimiento = 'ENTRADA',
    int arrayCount = 1,
    int qty = 1,
    String? arrayGroupCode,
    String? arrayRole,
    String? comentarios,
    String? scannedBy,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/pcb-inventory/scan'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'scanned_code': scannedCode,
          'inventory_date': inventoryDate,
          'proceso': proceso,
          'area': area,
          'tipo_movimiento': tipoMovimiento,
          'array_count': arrayCount,
          'qty': qty,
          'array_group_code': arrayGroupCode,
          'array_role': arrayRole,
          'comentarios': comentarios,
          'scanned_by': scannedBy,
        }),
      );

      final body = json.decode(response.body);
      if (response.statusCode == 200 && body['success'] == true) {
        return body;
      } else {
        return {
          'success': false,
          'message': body['message'] ?? 'Error desconocido',
          'code': body['code'] ?? 'UNKNOWN',
          'statusCode': response.statusCode,
        };
      }
    } catch (e) {
      return {
        'success': false,
        'message': 'Error de conexion: $e',
        'code': 'CONNECTION_ERROR',
      };
    }
  }

  // GET - Resumen de inventario PCB agrupado por tipo_movimiento
  static Future<Map<String, dynamic>> getPcbInventorySummary({
    required String inventoryDate,
    String? proceso,
    String tipoMovimiento = 'ENTRADA',
  }) async {
    try {
      String url =
          '$baseUrl/pcb-inventory/summary?inventory_date=$inventoryDate&tipo_movimiento=$tipoMovimiento';
      if (proceso != null && proceso.isNotEmpty && proceso != 'ALL') {
        url += '&proceso=$proceso';
      }

      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        return json.decode(response.body);
      }
      return {'success': false, 'data': [], 'total': 0};
    } catch (e) {
      return {'success': false, 'data': [], 'total': 0};
    }
  }

  // GET - Historial detallado de escaneos PCB por tipo_movimiento
  static Future<Map<String, dynamic>> getPcbInventoryScans({
    required String inventoryDate,
    String? proceso,
    String tipoMovimiento = 'ENTRADA',
    int limit = 300,
  }) async {
    try {
      String url =
          '$baseUrl/pcb-inventory/scans?inventory_date=$inventoryDate&limit=$limit&tipo_movimiento=$tipoMovimiento';
      if (proceso != null && proceso.isNotEmpty && proceso != 'ALL') {
        url += '&proceso=$proceso';
      }

      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        return json.decode(response.body);
      }
      return {'success': false, 'data': [], 'count': 0};
    } catch (e) {
      return {'success': false, 'data': [], 'count': 0};
    }
  }

  // DELETE - Eliminar un escaneo PCB
  static Future<Map<String, dynamic>> deletePcbInventoryScan(int id) async {
    try {
      final response = await http.delete(
        Uri.parse('$baseUrl/pcb-inventory/scan/$id'),
      );
      return json.decode(response.body);
    } catch (e) {
      return {'success': false, 'message': 'Error de conexion: $e'};
    }
  }

  // GET - Stock actual de PCBs (entradas - salidas - scrap)
  static Future<Map<String, dynamic>> getPcbStockSummary({
    String? numeroParte,
    String? area,
    String? proceso,
    bool includeZeroStock = false,
    DateTime? fechaInicio,
    DateTime? fechaFin,
  }) async {
    try {
      String url =
          '$baseUrl/pcb-inventory/stock-summary?include_zero_stock=$includeZeroStock';
      if (numeroParte != null && numeroParte.isNotEmpty) {
        url += '&numero_parte=$numeroParte';
      }
      if (area != null && area.isNotEmpty && area != 'ALL') {
        url += '&area=$area';
      }
      if (proceso != null && proceso.isNotEmpty && proceso != 'ALL') {
        url += '&proceso=$proceso';
      }
      if (fechaInicio != null && fechaFin != null) {
        url +=
            '&fecha_inicio=${fechaInicio.toIso8601String().substring(0, 10)}';
        url += '&fecha_fin=${fechaFin.toIso8601String().substring(0, 10)}';
      }
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        return json.decode(response.body);
      }
      return {'success': false, 'data': [], 'total_rows': 0, 'total_stock': 0};
    } catch (e) {
      return {'success': false, 'data': [], 'total_rows': 0, 'total_stock': 0};
    }
  }

  // GET - Detalle de todos los movimientos PCB para inventario
  static Future<Map<String, dynamic>> getPcbStockDetail({
    String? numeroParte,
    String? area,
    String? proceso,
    bool includeZeroStock = false,
    DateTime? fechaInicio,
    DateTime? fechaFin,
    int limit = 2000,
  }) async {
    try {
      String url =
          '$baseUrl/pcb-inventory/stock-detail?include_zero_stock=$includeZeroStock&limit=$limit';
      if (numeroParte != null && numeroParte.isNotEmpty) {
        url += '&numero_parte=$numeroParte';
      }
      if (area != null && area.isNotEmpty && area != 'ALL') {
        url += '&area=$area';
      }
      if (proceso != null && proceso.isNotEmpty && proceso != 'ALL') {
        url += '&proceso=$proceso';
      }
      if (fechaInicio != null && fechaFin != null) {
        url +=
            '&fecha_inicio=${fechaInicio.toIso8601String().substring(0, 10)}';
        url += '&fecha_fin=${fechaFin.toIso8601String().substring(0, 10)}';
      }
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        return json.decode(response.body);
      }
      return {'success': false, 'data': [], 'count': 0};
    } catch (e) {
      return {'success': false, 'data': [], 'count': 0};
    }
  }
}
