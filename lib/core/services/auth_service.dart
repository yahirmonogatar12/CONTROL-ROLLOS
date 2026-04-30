import 'dart:convert';
import 'backend_http_client.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config/server_config.dart';

class UserSession {
  final int id;
  final String username;
  final String email;
  final String nombreCompleto;
  final String departamento;
  final String cargo;

  UserSession({
    required this.id,
    required this.username,
    required this.email,
    required this.nombreCompleto,
    required this.departamento,
    required this.cargo,
  });

  factory UserSession.fromJson(Map<String, dynamic> json) {
    return UserSession(
      id: json['id'] ?? 0,
      username: json['username'] ?? '',
      email: json['email'] ?? '',
      nombreCompleto: json['nombre_completo'] ?? '',
      departamento: json['departamento'] ?? '',
      cargo: json['cargo'] ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'username': username,
      'email': email,
      'nombre_completo': nombreCompleto,
      'departamento': departamento,
      'cargo': cargo,
    };
  }
}

class AuthResult {
  final bool success;
  final String message;
  final UserSession? user;
  final int? intentosRestantes;

  AuthResult({
    required this.success,
    required this.message,
    this.user,
    this.intentosRestantes,
  });
}

class AuthService {
  /// Dynamic base URL from ServerConfig
  /// Falls back to localhost if ServerConfig not initialized
  static String get baseUrl => ServerConfig.baseUrl;
  
  static UserSession? _currentUser;
  
  // Permisos del usuario actual cargados desde la BD
  static Set<String> _userPermissions = {};
  
  // Departamentos con acceso total (siempre tienen todos los permisos)
  static const List<String> _fullAccessDepartments = ['Sistemas', 'Gerencia', 'Administración'];
  
  // Getter para el usuario actual
  static UserSession? get currentUser => _currentUser;
  
  // Verificar si hay sesión activa
  static bool get isLoggedIn => _currentUser != null;
  
  // Getter para el departamento actual
  static String get currentDepartment => _currentUser?.departamento ?? '';
  
  // ============================================
  // VERIFICACIÓN DE PERMISOS
  // ============================================
  
  /// Verifica si el usuario tiene un permiso específico
  static bool hasPermission(String permissionKey) {
    if (_currentUser == null) return false;
    // Los departamentos con acceso total tienen todos los permisos
    if (_fullAccessDepartments.contains(_currentUser!.departamento)) return true;
    return _userPermissions.contains(permissionKey);
  }
  
  /// Verifica si el usuario tiene acceso completo a todo
  static bool get hasFullAccess {
    if (_currentUser == null) return false;
    return _fullAccessDepartments.contains(_currentUser!.departamento);
  }
  
  // ============================================
  // PERMISOS POR MÓDULO (usando BD)
  // ============================================
  
  /// Verifica si el usuario puede ver Warehousing
  static bool get canViewWarehousing {
    if (_currentUser == null) return false;
    if (hasFullAccess) return true;
    return hasPermission('view_warehousing');
  }
  
  /// Verifica si el usuario puede escribir en Warehousing (Entradas)
  static bool get canWriteWarehousing {
    if (_currentUser == null) return false;
    if (hasFullAccess) return true;
    return hasPermission('write_warehousing');
  }
  
  /// Verifica si el usuario puede editar múltiples entradas a la vez
  static bool get canMultiEditWarehousing {
    if (_currentUser == null) return false;
    if (hasFullAccess) return true;
    return hasPermission('multi_edit_warehousing');
  }
  
  /// Verifica si el usuario puede ver Outgoing
  static bool get canViewOutgoing {
    if (_currentUser == null) return false;
    if (hasFullAccess) return true;
    return hasPermission('view_outgoing');
  }
  
  /// Verifica si el usuario puede escribir en Outgoing (Salidas)
  static bool get canWriteOutgoing {
    if (_currentUser == null) return false;
    if (hasFullAccess) return true;
    return hasPermission('write_outgoing');
  }
  
  /// Verifica si el usuario puede ver Inventario
  static bool get canViewInventory {
    if (_currentUser == null) return false;
    if (hasFullAccess) return true;
    return hasPermission('view_inventory');
  }
  
  /// Verifica si el usuario puede ver IQC
  static bool get canViewIqc {
    if (_currentUser == null) return false;
    if (hasFullAccess) return true;
    return hasPermission('view_iqc');
  }
  
  /// Verifica si el usuario puede escribir en IQC (Inspección de Calidad)
  static bool get canWriteIqc {
    if (_currentUser == null) return false;
    if (hasFullAccess) return true;
    return hasPermission('write_iqc');
  }
  
  /// Verifica si el usuario puede ver Cuarentena
  static bool get canViewQuarantine {
    if (_currentUser == null) return false;
    if (hasFullAccess) return true;
    return hasPermission('view_quarantine');
  }
  
  /// Verifica si el usuario puede enviar a Cuarentena
  static bool get canSendToQuarantine {
    if (_currentUser == null) return false;
    if (hasFullAccess) return true;
    return hasPermission('send_quarantine');
  }

  /// Verifica si el usuario puede liberar/modificar en Cuarentena
  static bool get canWriteQuarantine {
    if (_currentUser == null) return false;
    if (hasFullAccess) return true;
    return hasPermission('release_quarantine');
  }

  /// Verifica si el usuario puede ver la Lista Negra
  static bool get canViewBlacklist {
    if (_currentUser == null) return false;
    if (hasFullAccess) return true;
    return hasPermission('view_blacklist');
  }

  /// Verifica si el usuario puede editar la Lista Negra
  static bool get canWriteBlacklist {
    if (_currentUser == null) return false;
    if (hasFullAccess) return true;
    return hasPermission('write_blacklist');
  }

  /// Verifica si el usuario puede administrar usuarios
  static bool get canManageUsers {
    if (_currentUser == null) return false;
    if (hasFullAccess) return true;
    return hasPermission('manage_users');
  }
  
  /// Verifica si el usuario puede ver reportes
  static bool get canViewReports {
    if (_currentUser == null) return false;
    if (hasFullAccess) return true;
    return hasPermission('view_reports');
  }
  
  /// Verifica si el usuario puede exportar datos
  static bool get canExportData {
    if (_currentUser == null) return false;
    if (hasFullAccess) return true;
    return hasPermission('export_data');
  }
  
  /// Verifica si el usuario puede aprobar cancelaciones de entradas
  static bool get canApproveCancellation {
    if (_currentUser == null) return false;
    if (hasFullAccess) return true;
    return hasPermission('approve_cancellation');
  }

  /// Verifica si el usuario puede ver Devoluciones de Material
  static bool get canViewMaterialReturn {
    if (_currentUser == null) return false;
    if (hasFullAccess) return true;
    return hasPermission('view_material_return');
  }

  /// Verifica si el usuario puede crear Devoluciones de Material
  static bool get canWriteMaterialReturn {
    if (_currentUser == null) return false;
    if (hasFullAccess) return true;
    return hasPermission('write_material_return');
  }

  /// Verifica si el usuario puede ver Requerimientos de Material
  static bool get canViewRequirements {
    if (_currentUser == null) return false;
    if (hasFullAccess) return true;
    return hasPermission('view_requirements');
  }

  /// Verifica si el usuario puede crear/editar Requerimientos de Material
  static bool get canWriteRequirements {
    if (_currentUser == null) return false;
    if (hasFullAccess) return true;
    return hasPermission('write_requirements');
  }

  /// Verifica si el usuario puede aprobar Requerimientos de Material
  static bool get canApproveRequirements {
    if (_currentUser == null) return false;
    if (hasFullAccess) return true;
    return hasPermission('approve_requirements');
  }

  /// Verifica si el usuario puede ver Reingreso/Reubicación
  static bool get canViewReentry {
    if (_currentUser == null) return false;
    if (hasFullAccess) return true;
    return hasPermission('view_reentry');
  }

  /// Verifica si el usuario puede reubicar material
  static bool get canWriteReentry {
    if (_currentUser == null) return false;
    if (hasFullAccess) return true;
    return hasPermission('write_reentry');
  }

  /// Verifica si el usuario puede ver Auditoría de Inventario
  static bool get canViewAudit {
    if (_currentUser == null) return false;
    if (hasFullAccess) return true;
    // Supervisores de almacén pueden ver auditoría
    if (_currentUser!.departamento.contains('Almacén')) return true;
    return hasPermission('view_audit');
  }

  /// Verifica si el usuario puede iniciar/terminar Auditoría (solo supervisores desde PC)
  static bool get canManageAudit {
    if (_currentUser == null) return false;
    if (hasFullAccess) return true;
    // Solo supervisores pueden iniciar/terminar
    if (_currentUser!.departamento == 'Almacén Supervisor') return true;
    return hasPermission('start_audit');
  }

  /// Verifica si el usuario puede escanear en Auditoría (operadores desde móvil)
  static bool get canScanAudit {
    if (_currentUser == null) return false;
    if (hasFullAccess) return true;
    // Personal de almacén puede escanear
    if (_currentUser!.departamento.contains('Almacén')) return true;
    return hasPermission('scan_audit');
  }

  /// Verifica si el usuario puede ver Búsqueda de Ubicación
  static bool get canViewLocationSearch {
    if (_currentUser == null) return false;
    if (hasFullAccess) return true;
    if (_currentUser!.departamento.contains('Almacén')) return true;
    return hasPermission('view_location_search');
  }
  /// Verifica si el usuario puede registrar escaneos PCB Inventory
  static bool get canWritePcbInventory {
    if (_currentUser == null) return false;
    if (hasFullAccess) return true;
    return hasPermission('write_pcb_inventory');
  }

  /// Verifica si el usuario puede ver PCB Entrada
  static bool get canViewPcbEntrada {
    if (_currentUser == null) return false;
    if (hasFullAccess) return true;
    return hasPermission('view_pcb_entrada');
  }

  /// Verifica si el usuario puede ver PCB Salida
  static bool get canViewPcbSalida {
    if (_currentUser == null) return false;
    if (hasFullAccess) return true;
    return hasPermission('view_pcb_salida');
  }

  /// Verifica si el usuario puede ver PCB Inventario
  static bool get canViewPcbInventario {
    if (_currentUser == null) return false;
    if (hasFullAccess) return true;
    return hasPermission('view_pcb_inventario');
  }

  /// Verifica si el usuario puede ver solicitudes de material SMT
  static bool get canViewSMTRequests {
    if (_currentUser == null) return false;
    if (hasFullAccess) return true;
    return hasPermission('view_smt_requests');
  }

  // ============================================
  // CARGA DE PERMISOS
  // ============================================
  
  /// Carga los permisos del usuario desde la BD
  static Future<void> _loadUserPermissions(int userId) async {
    try {
      print('========================================');
      print('CARGANDO PERMISOS PARA USUARIO ID: $userId');
      print('URL: $baseUrl/users/$userId/permissions');
      
      final response = await http.get(
        Uri.parse('$baseUrl/users/$userId/permissions'),
      );
      
      print('Response status: ${response.statusCode}');
      print('Response body: ${response.body}');
      
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        _userPermissions = data
            .where((p) => p['enabled'] == 1)
            .map((p) => p['permission_key'].toString())
            .toSet();
        
        print('PERMISOS ACTIVOS: $_userPermissions');
        print('========================================');
      } else {
        _userPermissions = {};
        print('ERROR: Response no fue 200');
      }
    } catch (e) {
      print('ERROR cargando permisos: $e');
      _userPermissions = {};
    }
  }

  // Login
  static Future<AuthResult> login(String username, String password) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/auth/login'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'username': username,
          'password': password,
        }),
      );

      final data = json.decode(response.body);

      if (response.statusCode == 200 && data['success'] == true) {
        _currentUser = UserSession.fromJson(data['user']);
        
        // Cargar permisos del usuario desde la BD
        await _loadUserPermissions(_currentUser!.id);
        
        // Guardar sesión en SharedPreferences
        await _saveSession(_currentUser!);
        
        return AuthResult(
          success: true,
          message: data['message'] ?? 'Login exitoso',
          user: _currentUser,
        );
      } else {
        return AuthResult(
          success: false,
          message: data['message'] ?? 'Error de autenticación',
          intentosRestantes: data['intentosRestantes'],
        );
      }
    } catch (e) {
      print('Error en login: $e');
      return AuthResult(
        success: false,
        message: 'Error de conexión. Verifique que el servidor esté activo.',
      );
    }
  }

  // Logout
  static Future<void> logout() async {
    try {
      if (_currentUser != null) {
        await http.post(
          Uri.parse('$baseUrl/auth/logout'),
          headers: {'Content-Type': 'application/json'},
          body: json.encode({'userId': _currentUser!.id}),
        );
      }
    } catch (e) {
      print('Error en logout: $e');
    } finally {
      _currentUser = null;
      _userPermissions = {};
      await _clearSession();
    }
  }

  // Restaurar sesión guardada
  static Future<bool> restoreSession() async {
    try {
      // Verificar si la sesión ha expirado (24 horas)
      if (await isSessionExpired()) {
        await _clearSession();
        return false;
      }
      
      final prefs = await SharedPreferences.getInstance();
      final userJson = prefs.getString('user_session');
      
      if (userJson != null) {
        final userData = json.decode(userJson);
        final userId = userData['id'];
        
        // Verificar que el usuario siga activo en el servidor
        final response = await http.get(
          Uri.parse('$baseUrl/auth/verify/$userId'),
        );
        
        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          if (data['valid'] == true) {
            _currentUser = UserSession.fromJson(userData);
            
            // Cargar permisos del usuario desde la BD
            await _loadUserPermissions(_currentUser!.id);
            
            return true;
          }
        }
        
        // Si no es válido, limpiar sesión
        await _clearSession();
      }
    } catch (e) {
      print('Error restaurando sesión: $e');
    }
    return false;
  }
  
  /// Recargar permisos del usuario actual (útil después de modificar permisos)
  static Future<void> reloadPermissions() async {
    if (_currentUser != null) {
      await _loadUserPermissions(_currentUser!.id);
    }
  }

  // Duración de la sesión: 24 horas
  static const int sessionDurationHours = 24;
  
  // Guardar sesión con timestamp de inicio
  static Future<void> _saveSession(UserSession user) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('user_session', json.encode(user.toJson()));
      await prefs.setInt('session_start_time', DateTime.now().millisecondsSinceEpoch);
    } catch (e) {
      print('Error guardando sesión: $e');
    }
  }

  // Limpiar sesión
  static Future<void> _clearSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('user_session');
      await prefs.remove('session_start_time');
    } catch (e) {
      print('Error limpiando sesión: $e');
    }
  }
  
  /// Verificar si la sesión ha expirado (24 horas desde login)
  static Future<bool> isSessionExpired() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final sessionStartTime = prefs.getInt('session_start_time');
      
      if (sessionStartTime == null) return true;
      
      final loginTime = DateTime.fromMillisecondsSinceEpoch(sessionStartTime);
      final now = DateTime.now();
      final difference = now.difference(loginTime);
      
      return difference.inHours >= sessionDurationHours;
    } catch (e) {
      return true;
    }
  }
}
