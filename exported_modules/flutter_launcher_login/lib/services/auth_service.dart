import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Datos de la sesión del usuario
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
      nombreCompleto: json['nombre_completo'] ?? json['nombreCompleto'] ?? '',
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

/// Resultado de una operación de autenticación
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

/// Servicio de autenticación
/// 
/// Funcionalidades:
/// - Login con hash SHA-256
/// - Gestión de sesiones persistentes
/// - Logout
/// - Restauración de sesión
class AuthService {
  /// URL base del API
  static String baseUrl = 'http://localhost:3000/api';
  
  /// Usuario actual
  static UserSession? _currentUser;
  
  /// Si se debe hashear el password antes de enviar
  static bool hashPassword = true;
  
  /// Getter para el usuario actual
  static UserSession? get currentUser => _currentUser;
  
  /// Verificar si hay sesión activa
  static bool get isLoggedIn => _currentUser != null;

  /// Configura la URL base del servicio
  static void configure({String? url, bool? useHashPassword}) {
    if (url != null) baseUrl = url;
    if (useHashPassword != null) hashPassword = useHashPassword;
  }

  /// Hashea un password con SHA-256
  static String _hashSHA256(String password) {
    final bytes = utf8.encode(password);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  /// Login de usuario
  /// 
  /// Retorna [AuthResult] con el resultado de la operación
  static Future<AuthResult> login(String username, String password) async {
    try {
      final passwordToSend = hashPassword ? _hashSHA256(password) : password;
      
      final response = await http.post(
        Uri.parse('$baseUrl/auth/login'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'username': username,
          'password': passwordToSend,
        }),
      );

      final data = json.decode(response.body);

      if (response.statusCode == 200 && data['success'] == true) {
        _currentUser = UserSession.fromJson(data['user']);
        
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

  /// Cierra la sesión del usuario
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
      await _clearSession();
    }
  }

  /// Restaura la sesión guardada
  /// 
  /// Retorna true si se pudo restaurar una sesión válida
  static Future<bool> restoreSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userJson = prefs.getString('user_session');
      
      if (userJson != null) {
        final userData = json.decode(userJson);
        final userId = userData['id'];
        
        // Verificar que el usuario siga activo en el servidor
        final response = await http.get(
          Uri.parse('$baseUrl/auth/verify/$userId'),
        ).timeout(const Duration(seconds: 5));
        
        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          if (data['valid'] == true) {
            _currentUser = UserSession.fromJson(userData);
            return true;
          }
        }
        
        await _clearSession();
      }
    } catch (e) {
      print('Error restaurando sesión: $e');
    }
    return false;
  }

  /// Guarda la sesión en SharedPreferences
  static Future<void> _saveSession(UserSession user) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('user_session', json.encode(user.toJson()));
    } catch (e) {
      print('Error guardando sesión: $e');
    }
  }

  /// Limpia la sesión guardada
  static Future<void> _clearSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('user_session');
    } catch (e) {
      print('Error limpiando sesión: $e');
    }
  }
}
