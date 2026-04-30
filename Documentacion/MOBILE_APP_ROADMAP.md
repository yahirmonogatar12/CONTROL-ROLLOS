# 📱 Mobile App & Server Configuration Roadmap

> **Última actualización:** Enero 2026

## Objetivo
Refactorizar la aplicación Flutter para soportar IP/puerto configurable del servidor, agregar funcionalidad de escaneo con cámara para dispositivos móviles, navegación simplificada en Android, impresión por red (Bluetooth en fase 2), descubrimiento de servidor por QR, y control de permisos `mobile_entry`.

---

## Fase 1: Configuración de Servidor Dinámica ✅
> **Estado:** Completado

### 1.1 Crear ServerConfig Service
- [x] Crear `lib/core/config/server_config.dart`
- [x] Implementar `ServerProfile` class (name, ip, port, isActive, lastConnected)
- [x] Implementar lista de servidores múltiples guardados
- [x] `activeServer` getter para selección actual
- [x] `baseUrl` getter → `http://$ip:$port/api`
- [x] `testConnection()` → validar conectividad
- [x] Load/save desde `SharedPreferences`
- [x] Default `localhost:3000` en Windows

### 1.2 Refactorizar ApiService
- [x] Cambiar `static const String baseUrl` a `static String get baseUrl => ServerConfig.baseUrl`
- [x] Todas las llamadas API usan baseUrl dinámico

### 1.3 Refactorizar AuthService
- [x] Cambiar `static const String baseUrl` a `static String get baseUrl => ServerConfig.baseUrl`
- [x] Verificar que login/logout usen URL dinámica

### 1.4 Actualizar main.dart
- [x] Agregar `await ServerConfig.init()` en inicialización
- [x] Cargar configuración antes de mostrar app

---

## Fase 2: UI de Configuración de Servidor en Login ✅
> **Estado:** Completado

### 2.1 Crear Server Settings Widget
- [x] Crear `lib/core/widgets/server_config_widget.dart`
- [x] Lista de servidores guardados con opciones: editar, eliminar, activar
- [x] Formulario agregar/editar servidor (nombre, IP, puerto)
- [x] Botón "Probar conexión" con feedback visual (✓/✗)
- [x] Botón "Escanear QR" (solo Android) para auto-configurar

### 2.2 Modificar Pantalla de Login
- [x] Widget de configuración colapsable/expandible
- [x] Mostrar estado de conexión actual
- [x] Integrado en pantalla de login

---

## Fase 3: Dependencias y Permisos Android ✅
> **Estado:** Completado

### 3.1 Agregar Paquetes a pubspec.yaml
```yaml
mobile_scanner: ^5.2.3       # Escaneo de códigos con cámara ✅
qr_flutter: ^4.1.0           # Generación de códigos QR ✅
connectivity_plus: ^5.0.2    # Detección de estado de red ✅
```

### 3.2 Permisos Android (AndroidManifest.xml)
```xml
<uses-permission android:name="android.permission.CAMERA" /> ✅
<uses-permission android:name="android.permission.INTERNET" /> ✅
<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" /> ✅
android:usesCleartextTraffic="true" ✅
```

---

## Fase 4: Sistema de Permisos Mobile ✅
> **Estado:** Completado (usa permisos existentes)

### 4.1 Permisos Existentes Utilizados
- [x] `canWriteWarehousing` - Para entrada de material móvil
- [x] `canWriteOutgoing` - Para salida de material móvil
- [x] `canViewInventory` - Para consulta de inventario móvil

### 4.2 Frontend - AuthService
- [x] Getters existentes funcionan para pantallas móviles
- [x] Pantallas móviles verifican permisos al renderizar

---

## Fase 5: Navegación Móvil Simplificada ✅
> **Estado:** Completado

### 5.1 Layout Móvil con BottomNavigationBar
- [x] Crear `lib/screens/mobile/mobile_home_scaffold.dart`
- [x] Detectar `Platform.isAndroid` para mostrar UI móvil
- [x] BottomNavigationBar con 3 opciones:
  - 📥 Material Entry (Entradas)
  - 📤 Outgoing (Salidas)
  - 📦 Inventory (Inventario)

### 5.2 Módulos Ocultos en Móvil
- [x] IQC - Solo desktop
- [x] Quarantine - Solo desktop
- [x] User Management - Solo desktop
- [x] Material Control - Solo desktop
- [x] Quality Specs - Solo desktop

---

## Fase 6: Pantallas Móviles con Scanner ✅
> **Estado:** Completado

### 6.1 Mobile Entry Screen
- [x] Crear `lib/screens/mobile/mobile_entry_screen.dart`
- [x] Botón grande para abrir escáner de cámara
- [x] Buscar información de material por código escaneado
- [x] Mostrar detalles del material encontrado
- [x] Entradas recientes del día

### 6.2 Mobile Outgoing Screen
- [x] Crear `lib/screens/mobile/mobile_outgoing_screen.dart`
- [x] Escanear código para dar salida
- [x] Verificar si material ya tiene salida
- [x] Confirmar y registrar salida
- [x] Envía todos los campos requeridos (numero_lote, etc.)

### 6.3 Mobile Inventory Screen
- [x] Crear `lib/screens/mobile/mobile_inventory_screen.dart`
- [x] Búsqueda por texto o escáner
- [x] Resumen de inventario
- [x] Vista detallada de items

### 6.4 Scanner Widget
- [x] Integrar `mobile_scanner` package
- [x] Pantalla completa de cámara con overlay
- [x] Controles: flash, cancelar, cambiar cámara
- [x] **FIX:** Controlador se recrea para cada escaneo (evita bug de cámara bloqueada)

---

## Fase 7: Generador de QR del Servidor ✅
> **Estado:** Completado

### 7.1 QR en Desktop
- [x] Crear `lib/core/widgets/server_qr_dialog.dart`
- [x] Generar QR con: `{"name":"...","ip":"...","port":...}`
- [x] Obtener IP local automáticamente
- [x] Mostrar instrucciones para escanear desde móvil

---

## Fase 8: Backend - Servidor Accesible en Red ✅
> **Estado:** Completado

### 8.1 Configuración del Servidor
- [x] Servidor escucha en `0.0.0.0` (todas las interfaces)
- [x] Muestra IP local al iniciar para fácil configuración
- [x] Variable de entorno `HOST` opcional
- [x] Log con direcciones local y de red

```javascript
// Output del servidor:
🚀 API escuchando en:
   - Local:   http://localhost:3000
   - Red:     http://192.168.x.x:3000
📱 Usa la dirección de Red para conectar desde dispositivos móviles
```

---

## Fase 9: Auto-descubrimiento de Servidores ✅
> **Estado:** Completado

### 9.1 Broadcast UDP
- [x] Backend emite beacon UDP en red local (puerto 41234)
- [x] App móvil puede "Buscar servidores" en la red
- [x] Listar servidores encontrados automáticamente
- [x] Agregar servidor descubierto con un tap

### Archivos Creados
- `backend/utils/udpDiscovery.js` - Servicio UDP beacon
- `lib/core/services/server_discovery_service.dart` - Cliente discovery Flutter

---

## Fase 10: Impresión Bluetooth ✅
> **Estado:** Completado

### 10.1 Soporte Bluetooth
- [x] Agregar `flutter_blue_plus` package
- [x] Método `scanBluetoothPrinters()` en MobilePrinterService
- [x] Método `printZPLViaBluetooth()` para enviar ZPL directo
- [x] UI para seleccionar tipo: Backend / Bluetooth
- [x] Escanear y emparejar impresora Bluetooth desde app
- [x] Guardar impresora reciente en SharedPreferences

---

## Fase 11: Sistema de Traducción Móvil ✅
> **Estado:** Completado

### 11.1 Traducciones en app_translations.dart
- [x] Agregar claves de traducción para Mobile Entry Screen
- [x] Agregar claves de traducción para Mobile Label Assignment
- [x] Agregar claves de traducción para Mobile Outgoing Screen
- [x] Agregar claves de traducción para Mobile Inventory
- [x] Agregar claves de traducción para Mobile Drawer/Navigation
- [x] Soporte para 3 idiomas: Inglés (en), Español (es), Coreano (ko)

### 11.2 Pantallas Móviles Actualizadas
- [x] `mobile_entry_screen.dart` - Usar `tr()` para todos los textos
- [x] `mobile_label_assignment_screen.dart` - Usar `tr()` para todos los textos
- [x] `mobile_outgoing_screen.dart` - Usar `tr()` para todos los textos
- [x] `mobile_inventory_screen.dart` - Usar `tr()` para búsqueda
- [x] `mobile_home_scaffold.dart` - Selector de idioma en drawer

### 11.3 Selector de Idioma
- [x] Agregar widget selector de idioma en el drawer móvil
- [x] Banderas: 🇺🇸 English, 🇪🇸 Español, 🇰🇷 한국어
- [x] Cambio dinámico sin reiniciar app
- [x] Mismo sistema que PC (LanguageProvider)

---

## Modelo de Datos

### ServerProfile
```dart
class ServerProfile {
  final String id;          // UUID único
  final String name;        // "Producción", "Desarrollo", etc.
  final String ip;          // "192.168.1.50"
  final int port;           // 3000
  final bool isActive;      // Currently selected
  final DateTime? lastConnected;
  
  String get baseUrl => 'http://$ip:$port/api';
}
```

### Permisos Utilizados
| Permission Key | Descripción | Pantalla Móvil |
|----------------|-------------|----------------|
| `write_warehousing` | Entrada de material | ✅ Entry |
| `write_outgoing` | Salida de material | ✅ Outgoing |
| `view_inventory` | Ver inventario | ✅ Inventory |

---

## Endpoints API Utilizados

| Módulo | Endpoint | Uso Móvil |
|--------|----------|-----------|
| Auth | `POST /api/auth/login` | ✅ Login |
| Health | `GET /api/health` | ✅ Test conexión |
| Warehousing | `GET /api/warehousing/by-code/:code` | ✅ Buscar material |
| Warehousing | `GET /api/warehousing/search` | ✅ Entradas recientes |
| Outgoing | `POST /api/outgoing` | ✅ Crear salida |
| Outgoing | `GET /api/outgoing/check-salida/:code` | ✅ Verificar salida |
| Outgoing | `GET /api/outgoing/search` | ✅ Salidas recientes |
| Inventory | `GET /api/inventory/summary` | ✅ Resumen inventario |
| Inventory | `GET /api/inventory/lots` | ✅ Detalle lotes |

---

## Progreso General

| Fase | Descripción | Estado |
|------|-------------|--------|
| 1 | Configuración Servidor Dinámica | ✅ Completado |
| 2 | UI Configuración en Login | ✅ Completado |
| 3 | Dependencias y Permisos Android | ✅ Completado |
| 4 | Sistema de Permisos Mobile | ✅ Completado |
| 5 | Navegación Móvil Simplificada | ✅ Completado |
| 6 | Pantallas Móviles con Scanner | ✅ Completado |
| 7 | Generador QR del Servidor | ✅ Completado |
| 8 | Backend Accesible en Red | ✅ Completado |
| 9 | Auto-descubrimiento UDP | ✅ Completado |
| 10 | Impresión Bluetooth | ✅ Completado |
| 11 | Sistema de Traducción Móvil | ✅ Completado |

**Progreso Total: 11/11 Fases Completadas (100%)**

---

## Archivos Creados/Modificados

### Nuevos Archivos
| Archivo | Descripción |
|---------|-------------|
| `lib/core/config/server_config.dart` | Gestión de perfiles de servidor |
| `lib/core/utils/platform_utils.dart` | Utilidades de detección de plataforma |
| `lib/core/widgets/server_config_widget.dart` | Widget UI para config servidor |
| `lib/core/widgets/server_qr_dialog.dart` | Dialog QR para compartir config |
| `lib/screens/mobile/mobile_home_scaffold.dart` | Scaffold principal móvil |
| `lib/screens/mobile/mobile_entry_screen.dart` | Pantalla entrada con scanner |
| `lib/screens/mobile/mobile_outgoing_screen.dart` | Pantalla salidas con scanner |
| `lib/screens/mobile/mobile_inventory_screen.dart` | Pantalla inventario |

### Archivos Modificados
| Archivo | Cambio |
|---------|--------|
| `lib/main.dart` | Inicialización ServerConfig, detección plataforma |
| `lib/app.dart` | Flow móvil vs desktop |
| `lib/core/services/api_service.dart` | baseUrl dinámico desde ServerConfig |
| `lib/core/services/auth_service.dart` | baseUrl dinámico desde ServerConfig |
| `lib/core/localization/app_translations.dart` | Traducciones móviles |
| `pubspec.yaml` | mobile_scanner, qr_flutter, connectivity_plus |
| `android/app/src/main/AndroidManifest.xml` | CAMERA, INTERNET, cleartextTraffic |
| `backend/server.js` | Escucha en 0.0.0.0, muestra IP local |

---

## Bugs Corregidos

| Bug | Solución | Fecha |
|-----|----------|-------|
| Cámara no reabre después del primer escaneo | Recrear `MobileScannerController` en cada escaneo | 3 Dic 2025 |
| Error `numero_lote cannot be null` al dar salida | Enviar `lote_interno` del material en el request | 3 Dic 2025 |
| Servidor solo accesible desde localhost | Cambiar `HOST` a `0.0.0.0` en server.js | 3 Dic 2025 |

---

## Próximos Pasos

1. **Probar APK en dispositivo físico Android**
   - Compilar: `flutter build apk --release`
   - Instalar en dispositivo
   - Probar conexión al servidor por WiFi

2. **Agregar botón de impresión en pantalla de entrada móvil** (si se requiere)

3. **Considerar modo offline** (cache local de materiales frecuentes)

---

## Notas de Implementación

1. **Detección de Plataforma**: Usar `Platform.isAndroid` o `Platform.isWindows` para mostrar UI apropiada
2. **Impresión**: Fase 1 usa TCP/IP a impresoras Zebra en red; Bluetooth es fase posterior
3. **Offline**: No implementado en fase inicial; requiere conexión al servidor
4. **Múltiples Servidores**: Útil para dev/staging/producción sin reinstalar app
5. **Scanner**: El controlador se recrea cada vez para evitar bugs de estado

---

*Documento creado: 2 de Diciembre 2025*
*Última actualización: Enero 2026*
