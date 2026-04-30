# Flutter Launcher + Login Module

Módulo reutilizable para aplicaciones Flutter Desktop que incluye:

- ✅ **Launcher Screen** - Pantalla de carga animada con logo pulsante
- ✅ **Backend Service** - Servicio para iniciar/gestionar backend Node.js
- ✅ **Login Screen** - Pantalla de login con soporte multi-idioma
- ✅ **Auth Service** - Servicio de autenticación con sesiones
- ✅ **Theme Colors** - Colores del tema oscuro

## 📦 Estructura

```
flutter_launcher_login/
├── lib/
│   ├── screens/
│   │   ├── launcher/
│   │   │   └── launcher_screen.dart
│   │   └── login/
│   │       └── login_screen.dart
│   ├── services/
│   │   ├── backend_service.dart
│   │   └── auth_service.dart
│   ├── localization/
│   │   └── app_translations.dart
│   └── theme/
│       └── app_colors.dart
├── assets/
│   └── logo.png (agregar tu logo)
└── README.md
```

## 🚀 Cómo Usar

### 1. Copiar archivos

Copia la carpeta `lib/` a tu proyecto Flutter.

### 2. Agregar dependencias al `pubspec.yaml`

```yaml
dependencies:
  flutter:
    sdk: flutter
  http: ^1.1.0
  shared_preferences: ^2.2.2

flutter:
  assets:
    - assets/logo.png
```

### 3. Crear archivo `VERSION.txt` en la raíz

```
1.0.0
```

### 4. Implementar en tu `main.dart`

```dart
import 'package:flutter/material.dart';
import 'screens/launcher/launcher_screen.dart';
import 'screens/login/login_screen.dart';
import 'localization/app_translations.dart';

void main() {
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
      theme: ThemeData.dark(),
      home: _buildCurrentScreen(),
    );
  }

  Widget _buildCurrentScreen() {
    switch (_currentScreen) {
      case AppScreen.launcher:
        return LauncherScreen(
          onReady: () => setState(() => _currentScreen = AppScreen.login),
        );
      case AppScreen.login:
        return LoginScreen(
          languageProvider: _languageProvider,
          onLoginSuccess: () => setState(() => _currentScreen = AppScreen.main),
        );
      case AppScreen.main:
        return YourMainScreen(); // Tu pantalla principal
    }
  }
}

enum AppScreen { launcher, login, main }
```

## ⚙️ Configuración del Backend

El `BackendService` busca el backend en:

1. **Producción**: `backend-server.exe` junto al ejecutable
2. **Desarrollo**: `backend/server.js` en el directorio del proyecto

### Endpoint requerido para verificar si el backend está listo:

```
GET http://localhost:3000/api/health
```

Puedes modificar el endpoint en `backend_service.dart`.

## 🎨 Personalización

### Cambiar colores

Edita `theme/app_colors.dart`:

```dart
class AppColors {
  static const Color headerTab = Color(0xFF4A90D9);  // Color principal
  static const Color panelBackground = Color(0xFF252A3A);
  // ...
}
```

### Cambiar textos/idiomas

Edita `localization/app_translations.dart` para agregar o modificar traducciones.

### Cambiar tiempo mínimo del launcher

En `launcher_screen.dart`, busca:

```dart
// Tiempo mínimo de animación (2 segundos)
final minimumDisplayTime = Future.delayed(const Duration(seconds: 2));
```

## 📋 Endpoints de Autenticación Requeridos

Tu backend debe implementar:

```
POST /api/auth/login
Body: { "username": "...", "password": "..." }
Response: { "success": true, "user": {...}, "message": "..." }

POST /api/auth/logout
Body: { "userId": 123 }

GET /api/auth/verify/:userId
Response: { "valid": true }
```

## 📝 Notas

- El password se hashea con SHA-256 en el cliente antes de enviarlo
- Las sesiones se guardan en SharedPreferences
- Compatible con Windows Desktop (fácilmente adaptable a otras plataformas)

---

*Creado por MES Team - 2025*
