import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../theme/app_colors.dart';
import '../localization/app_translations.dart';

/// Pantalla de Login con soporte multi-idioma
/// 
/// Características:
/// - Campo de usuario y contraseña
/// - Botón de mostrar/ocultar contraseña
/// - Mensajes de error con intentos restantes
/// - Selector de idioma (EN/ES/KO)
/// - Navegación con teclado (Tab, Enter)
class LoginScreen extends StatefulWidget {
  /// Proveedor de idioma para traducciones
  final LanguageProvider languageProvider;
  
  /// Callback cuando el login es exitoso
  final VoidCallback onLoginSuccess;
  
  /// Ruta del logo (opcional)
  final String logoPath;

  const LoginScreen({
    super.key,
    required this.languageProvider,
    required this.onLoginSuccess,
    this.logoPath = 'assets/logo.png',
  });

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _usernameFocusNode = FocusNode();
  final _passwordFocusNode = FocusNode();
  
  bool _isLoading = false;
  bool _obscurePassword = true;
  String? _errorMessage;
  int? _intentosRestantes;

  String tr(String key) => widget.languageProvider.tr(key);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _usernameFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _usernameFocusNode.dispose();
    _passwordFocusNode.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    final username = _usernameController.text.trim();
    final password = _passwordController.text;

    if (username.isEmpty || password.isEmpty) {
      setState(() {
        _errorMessage = tr('login_empty_fields');
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _intentosRestantes = null;
    });

    final result = await AuthService.login(username, password);

    if (mounted) {
      setState(() {
        _isLoading = false;
      });

      if (result.success) {
        widget.onLoginSuccess();
      } else {
        setState(() {
          _errorMessage = result.message;
          _intentosRestantes = result.intentosRestantes;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A1E2C),
      body: Center(
        child: SingleChildScrollView(
          child: Container(
            width: 420,
            padding: const EdgeInsets.all(40),
            decoration: BoxDecoration(
              color: AppColors.panelBackground,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.3),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Logo
                Container(
                  width: 150,
                  height: 150,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.asset(
                      widget.logoPath,
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) {
                        return Container(
                          decoration: BoxDecoration(
                            color: AppColors.gridHeader,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.lock_person,
                            size: 80,
                            color: Colors.white70,
                          ),
                        );
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                
                // Título
                Text(
                  tr('login_title'),
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  tr('login_subtitle'),
                  style: const TextStyle(
                    fontSize: 14,
                    color: Colors.white54,
                  ),
                ),
                const SizedBox(height: 32),
                
                // Campo de usuario
                TextField(
                  controller: _usernameController,
                  focusNode: _usernameFocusNode,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: tr('login_username'),
                    labelStyle: const TextStyle(color: Colors.white70),
                    prefixIcon: const Icon(Icons.person_outline, color: Colors.white54),
                    filled: true,
                    fillColor: AppColors.gridBackground,
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: AppColors.border),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: AppColors.headerTab, width: 2),
                    ),
                  ),
                  textInputAction: TextInputAction.next,
                  onSubmitted: (_) => _passwordFocusNode.requestFocus(),
                ),
                const SizedBox(height: 16),
                
                // Campo de contraseña
                TextField(
                  controller: _passwordController,
                  focusNode: _passwordFocusNode,
                  obscureText: _obscurePassword,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: tr('login_password'),
                    labelStyle: const TextStyle(color: Colors.white70),
                    prefixIcon: const Icon(Icons.lock_outline, color: Colors.white54),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassword ? Icons.visibility_off : Icons.visibility,
                        color: Colors.white54,
                      ),
                      onPressed: () {
                        setState(() {
                          _obscurePassword = !_obscurePassword;
                        });
                      },
                    ),
                    filled: true,
                    fillColor: AppColors.gridBackground,
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: AppColors.border),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: AppColors.headerTab, width: 2),
                    ),
                  ),
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _handleLogin(),
                ),
                const SizedBox(height: 24),
                
                // Mensaje de error
                if (_errorMessage != null) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.red.withOpacity(0.3)),
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.error_outline, color: Colors.red, size: 20),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _errorMessage!,
                                style: const TextStyle(color: Colors.red, fontSize: 13),
                              ),
                            ),
                          ],
                        ),
                        if (_intentosRestantes != null && _intentosRestantes! > 0) ...[
                          const SizedBox(height: 4),
                          Text(
                            '${tr('login_attempts_remaining')}: $_intentosRestantes',
                            style: const TextStyle(color: Colors.orange, fontSize: 12),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                
                // Botón de login
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _handleLogin,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.headerTab,
                      disabledBackgroundColor: AppColors.headerTab.withOpacity(0.5),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : Text(
                            tr('login_button'),
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 24),
                
                // Selector de idioma
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _buildLanguageButton('EN', 'en'),
                    const SizedBox(width: 8),
                    _buildLanguageButton('ES', 'es'),
                    const SizedBox(width: 8),
                    _buildLanguageButton('KO', 'ko'),
                  ],
                ),
                const SizedBox(height: 16),
                
                // Footer
                Text(
                  tr('system_name'),
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.white.withOpacity(0.3),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLanguageButton(String label, String code) {
    final isSelected = widget.languageProvider.currentLocale == code;
    
    return InkWell(
      onTap: () {
        widget.languageProvider.setLocale(code);
        setState(() {});
      },
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.headerTab : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: isSelected ? AppColors.headerTab : Colors.white24,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: isSelected ? Colors.white : Colors.white54,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}
