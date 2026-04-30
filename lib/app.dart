import 'dart:async';
import 'package:flutter/material.dart';
import 'package:material_warehousing_flutter/core/localization/app_translations.dart';
import 'package:material_warehousing_flutter/core/services/auth_service.dart';
import 'package:material_warehousing_flutter/core/services/backend_service.dart';
import 'package:material_warehousing_flutter/core/services/update_service.dart';
import 'package:material_warehousing_flutter/core/utils/platform_utils.dart';
import 'package:material_warehousing_flutter/screens/launcher/launcher_screen.dart';
import 'package:material_warehousing_flutter/screens/login/login_screen.dart';
import 'package:material_warehousing_flutter/screens/main_tabbed_screen.dart';
import 'package:material_warehousing_flutter/screens/mobile/mobile_home_scaffold.dart';

/// Navigator key global para poder mostrar overlays desde servicios/timers
/// sin necesitar un BuildContext directamente.
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

class MesTabsApp extends StatefulWidget {
  const MesTabsApp({super.key});

  @override
  State<MesTabsApp> createState() => _MesTabsAppState();
}

class _MesTabsAppState extends State<MesTabsApp> {
  final LanguageProvider _languageProvider = LanguageProvider();
  bool _isLoggedIn = false;
  bool _isCheckingSession = true;
  bool _isBackendReady = false;
  
  // Timer para verificar expiración de sesión cada hora
  Timer? _sessionExpirationTimer;

  @override
  void initState() {
    super.initState();
    _languageProvider.addListener(() {
      setState(() {});
    });
    
    // Inicializar idioma (detecta sistema o carga guardado)
    _initializeLanguage();
    
    // En móvil, no necesitamos el launcher del backend
    // El backend corre en el servidor
    if (PlatformUtils.isMobile) {
      _onMobileReady();
    }
  }

  Future<void> _initializeLanguage() async {
    await _languageProvider.initialize();
    if (mounted) {
      setState(() {});
    }
  }

  /// En móvil, marcamos como listo directamente ya que el backend
  /// está en un servidor remoto
  void _onMobileReady() {
    setState(() {
      _isBackendReady = true;
    });
    _checkExistingSession();
  }

  void _onBackendReady() {
    setState(() {
      _isBackendReady = true;
    });
    _checkExistingSession();
  }

  Future<void> _checkExistingSession() async {
    // Intentar restaurar sesión guardada
    final hasSession = await AuthService.restoreSession();
    if (mounted) {
      setState(() {
        _isLoggedIn = hasSession;
        _isCheckingSession = false;
      });
      // Si hay sesión activa, iniciar timer de verificación
      if (hasSession) {
        _startSessionExpirationTimer();
      }
    }
  }

  void _handleLoginSuccess() {
    setState(() {
      _isLoggedIn = true;
    });
    // Iniciar timer de verificación de expiración
    _startSessionExpirationTimer();
    // Verificar actualizaciones después del login (solo desktop)
    if (PlatformUtils.isDesktop) {
      _checkForUpdates();
    }
  }
  
  /// Iniciar timer que verifica expiración de sesión cada hora
  void _startSessionExpirationTimer() {
    _sessionExpirationTimer?.cancel();
    _sessionExpirationTimer = Timer.periodic(
      const Duration(hours: 1),
      (_) => _checkSessionExpiration(),
    );
  }
  
  /// Detener timer de expiración
  void _stopSessionExpirationTimer() {
    _sessionExpirationTimer?.cancel();
    _sessionExpirationTimer = null;
  }
  
  /// Verificar si la sesión ha expirado
  Future<void> _checkSessionExpiration() async {
    if (!_isLoggedIn) return;
    
    final expired = await AuthService.isSessionExpired();
    if (expired && mounted) {
      // Cerrar sesión silenciosamente
      await AuthService.logout();
      setState(() {
        _isLoggedIn = false;
      });
      _stopSessionExpirationTimer();
    }
  }
  
  /// Verificar si hay actualizaciones disponibles
  Future<void> _checkForUpdates() async {
    // Esperar un momento para que la pantalla principal se cargue
    await Future.delayed(const Duration(seconds: 2));
    
    final updateInfo = await UpdateService.checkForUpdates();
    
    if (updateInfo != null && updateInfo.updateAvailable && mounted) {
      // Obtener el contexto actual
      final context = this.context;
      if (context.mounted) {
        await UpdateService.showUpdateDialog(context, updateInfo);
      }
    }
  }

  void _handleLogout() async {
    _stopSessionExpirationTimer();
    await AuthService.logout();
    if (mounted) {
      setState(() {
        _isLoggedIn = false;
      });
    }
  }

  @override
  void dispose() {
    // Detener timer de expiración
    _stopSessionExpirationTimer();
    // Detener el backend cuando se cierra la app (solo en desktop)
    if (PlatformUtils.isDesktop) {
      BackendService.stopBackend();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Control inventario SMD',
      debugShowCheckedModeBanner: false,
      navigatorKey: appNavigatorKey,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF262C3A),
        textTheme: ThemeData.dark().textTheme.apply(fontFamily: 'Segoe UI'),
      ),
      home: _buildHomeScreen(),
    );
  }

  Widget _buildHomeScreen() {
    // En móvil, saltar el launcher del backend
    if (PlatformUtils.isMobile) {
      return _buildMobileFlow();
    }
    
    // En desktop, usar el flujo normal con launcher
    return _buildDesktopFlow();
  }

  Widget _buildMobileFlow() {
    if (_isCheckingSession) {
      return const Scaffold(
        backgroundColor: Color(0xFF1A1E2C),
        body: Center(
          child: CircularProgressIndicator(color: Colors.white70),
        ),
      );
    }
    
    if (_isLoggedIn) {
      return MobileHomeScaffold(
        languageProvider: _languageProvider,
        onLogout: _handleLogout,
      );
    }
    
    return LoginScreen(
      languageProvider: _languageProvider,
      onLoginSuccess: _handleLoginSuccess,
    );
  }

  Widget _buildDesktopFlow() {
    if (!_isBackendReady) {
      return LauncherScreen(onReady: _onBackendReady);
    }
    
    if (_isCheckingSession) {
      return const Scaffold(
        backgroundColor: Color(0xFF1A1E2C),
        body: Center(
          child: CircularProgressIndicator(color: Colors.white70),
        ),
      );
    }
    
    if (_isLoggedIn) {
      return MainTabbedScreen(
        languageProvider: _languageProvider,
        onLogout: _handleLogout,
      );
    }
    
    return LoginScreen(
      languageProvider: _languageProvider,
      onLoginSuccess: _handleLoginSuccess,
    );
  }
}

