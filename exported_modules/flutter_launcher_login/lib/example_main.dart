import 'package:flutter/material.dart';
import 'screens/launcher/launcher_screen.dart';
import 'screens/login/login_screen.dart';
import 'localization/app_translations.dart';
import 'services/backend_service.dart';
import 'services/auth_service.dart';

/// Ejemplo de uso del módulo Launcher + Login
/// 
/// Copia este código a tu main.dart y ajusta según tus necesidades
void main() {
  // Configuración opcional del backend
  BackendService.configure(
    url: 'http://localhost:3000',
    endpoint: '/api/health',
    exeName: 'backend-server.exe',
  );
  
  // Configuración opcional del auth
  AuthService.configure(
    url: 'http://localhost:3000/api',
    useHashPassword: true,
  );
  
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final LanguageProvider _languageProvider = LanguageProvider();
  AppScreen _currentScreen = AppScreen.launcher;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Mi Aplicación',
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF1A1E2C),
      ),
      home: _buildCurrentScreen(),
    );
  }

  Widget _buildCurrentScreen() {
    switch (_currentScreen) {
      case AppScreen.launcher:
        return LauncherScreen(
          appTitle: 'Mi Aplicación',
          appSubtitle: 'Sistema de Control',
          minimumAnimationSeconds: 2,
          onReady: () => setState(() => _currentScreen = AppScreen.login),
        );
      
      case AppScreen.login:
        return LoginScreen(
          languageProvider: _languageProvider,
          onLoginSuccess: () => setState(() => _currentScreen = AppScreen.main),
        );
      
      case AppScreen.main:
        return Scaffold(
          appBar: AppBar(
            title: const Text('Pantalla Principal'),
            actions: [
              IconButton(
                icon: const Icon(Icons.logout),
                onPressed: () async {
                  await AuthService.logout();
                  setState(() => _currentScreen = AppScreen.login);
                },
              ),
            ],
          ),
          body: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.check_circle, size: 80, color: Colors.green),
                const SizedBox(height: 20),
                Text(
                  '¡Bienvenido, ${AuthService.currentUser?.nombreCompleto ?? "Usuario"}!',
                  style: const TextStyle(fontSize: 24),
                ),
                const SizedBox(height: 10),
                Text(
                  'Departamento: ${AuthService.currentUser?.departamento ?? "N/A"}',
                  style: const TextStyle(fontSize: 16, color: Colors.white70),
                ),
              ],
            ),
          ),
        );
    }
  }
}

enum AppScreen { launcher, login, main }
