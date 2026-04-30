# Technology Stack

> **Última actualización:** Enero 2026

## Frontend (Flutter Multi-platform)

### Plataformas
- **Desktop:** Windows (primary), macOS, Linux
- **Mobile:** Android, iOS (con funcionalidad adaptada)

### Framework
- Flutter SDK >=3.0.0 <4.0.0
- State management: StatefulWidget with ChangeNotifier pattern

### Key Dependencies

| Package | Uso |
|---------|-----|
| `http` | REST API communication |
| `window_manager` | Desktop window control |
| `printing` | Label printing |
| `excel` | Excel file generation |
| `file_picker` | File selection dialogs |
| `shared_preferences` | Local storage |
| `dropdown_button2` | Enhanced dropdowns |
| `intl` | Date/number formatting |
| `mobile_scanner` | Camera barcode scanning (mobile) |
| `flutter_blue_plus` | Bluetooth printer support (mobile) |
| `vibration` | Haptic feedback (mobile) |
| `audioplayers` | Sound feedback |
| `connectivity_plus` | Network status detection |
| `device_info_plus` | Device information |

---

## Backend (Node.js) - Arquitectura Modular

### Framework
- Express.js REST API
- **14 controllers** organizados en módulos
- **16 archivos de rutas**
- MySQL database via mysql2 (timezone: 'local', dateStrings: true)
- CORS enabled for multi-device access
- Rate limiting for protection against overload
- UDP discovery service for mobile auto-connect

### Estructura del Backend
```
backend/
├── server.js              # ~275 líneas (punto de entrada)
├── config/                # Configuración (database, permissions)
├── controllers/           # 14 controllers de lógica de negocio
├── routes/                # 16 archivos de rutas
├── middleware/            # errorHandler.js, rateLimiter.js
└── utils/                 # dbMigrations.js, udpDiscovery.js, sequenceService.js
```

### Backend Dependencies
| Package | Uso |
|---------|-----|
| `express` | Web framework |
| `mysql2` | MySQL driver with promises |
| `cors` | Cross-origin support |
| `dotenv` | Environment configuration |
| `dgram` | UDP socket for discovery |

---

## API Endpoints

### Prefijos de API (16 rutas principales)

| Prefijo | Módulo | Descripción |
|---------|--------|-------------|
| `/api/warehousing` | Warehousing | Entradas de material |
| `/api/outgoing` | Outgoing | Salidas de material |
| `/api/return` | Return | Devoluciones de material |
| `/api/plan`, `/api/bom` | Plan | Plan de producción y BOM |
| `/api/auth` | Auth | Autenticación |
| `/api/users` | Users | Gestión de usuarios |
| `/api/departments` | Departments | Departamentos |
| `/api/cargos` | Cargos | Cargos/posiciones |
| `/api/permissions` | Permissions | Permisos |
| `/api/materiales`, `/api/materials` | Materials | Catálogo de materiales |
| `/api/iqc` | IQC | Inspección de calidad |
| `/api/quality-specs` | Quality Specs | Especificaciones de calidad |
| `/api/quarantine` | Quarantine | Cuarentena |
| `/api/inventory` | Inventory | Inventario de lotes |
| `/api/customers` | Customers | Catálogo de clientes |
| `/api/cancellation` | Cancellation | Solicitudes de cancelación |
| `/api/print` | Print | Impresión remota para móviles |
| `/api/audit` | Audit | Auditoría de inventario físico |
| `/api/blacklist` | Blacklist | Lista negra de lotes |
| `/api/health` | Health | Health check del servidor |

---

## Database

### MySQL Configuration
- Database: `meslocal`
- Timezone: `local`
- Date strings: enabled

### Key Tables

| Tabla | Descripción |
|-------|-------------|
| `control_material_almacen` | Entradas de material (warehousing) |
| `salidas_material` | Salidas de material (outgoing) |
| `materiales` | Catálogo de materiales |
| `bom` | Bill of Materials |
| `plan_main` | Plan de producción |
| `iqc_inspection_lot` | Inspecciones IQC |
| `iqc_inspection_detail` | Detalles de inspección |
| `quality_specs` | Especificaciones de calidad |
| `quarantine` | Material en cuarentena |
| `usuarios` | Usuarios del sistema |
| `cancellation_requests` | Solicitudes de cancelación |
| `inventory_audit` | Auditorías de inventario |
| `inventory_audit_items` | Items de auditoría |
| `material_returns` | Devoluciones de material |
| `ic_part_mapping` | Mapeo IC Part |

---

## Common Commands

### Flutter (Desktop)
```bash
# Run in development
flutter run -d windows

# Build Windows release
flutter build windows --release

# Analyze code
flutter analyze

# Get dependencies
flutter pub get
```

### Flutter (Mobile)
```bash
# Run on Android device
flutter run -d <device_id>

# Build Android APK
flutter build apk --release

# Build Android App Bundle
flutter build appbundle --release
```

### Backend
```bash
# Development (from backend/)
npm run dev

# Production
npm start

# Build standalone executable
npm run build
```

### Full Build (PowerShell)
```powershell
# Run build.ps1 for complete build process
.\build.ps1
```

---

## API Configuration

### Server
- Backend runs on `http://localhost:3000`
- API base path: `/api`
- UDP discovery on port `3001`

### Database Configuration
Via `.env` file in backend folder:
```
DB_HOST=localhost
DB_PORT=3306
DB_USER=root
DB_PASSWORD=
DB_NAME=meslocal
```

---

## Mobile Features

### Auto-Discovery
Los dispositivos móviles descubren automáticamente el servidor usando UDP broadcast en la red local.

### Remote Printing
Los móviles envían trabajos de impresión al servidor desktop que tiene acceso a las impresoras.

### Offline Capability
- Feedback visual y sonoro para operaciones
- Validación local antes de enviar al servidor
- Retry automático en caso de fallo de red

---

## Deployment

### Desktop App
1. Build con `flutter build windows --release`
2. Package backend con `pkg` a .exe
3. Crear installer con Inno Setup (`installer/setup.iss`)

### Mobile App
1. Build APK: `flutter build apk --release`
2. Distribuir via Play Store o instalación directa

### Backend Standalone
```bash
cd backend
npm run build  # Genera server.exe con pkg
```
