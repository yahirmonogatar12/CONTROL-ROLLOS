# Project Structure

> **Última actualización:** Enero 2026

```
material_warehousing_flutter/
├── lib/                          # Flutter application source
│   ├── main.dart                 # App entry point, window initialization
│   ├── app.dart                  # Root widget, navigation, auth state
│   ├── core/                     # Shared code
│   │   ├── config/               # Server configuration
│   │   │   └── server_config.dart          # Multi-server profiles
│   │   ├── localization/         # Multi-language translations (en/es/ko)
│   │   ├── services/             # API, auth, backend, printing services
│   │   │   ├── api_service.dart            # REST API calls (~88KB)
│   │   │   ├── auth_service.dart           # Authentication & permissions
│   │   │   ├── backend_service.dart        # Backend process management
│   │   │   ├── printer_service.dart        # Desktop label printing (ZPL)
│   │   │   ├── mobile_printer_service.dart # Mobile remote/Bluetooth printing
│   │   │   ├── excel_export_service.dart   # Excel file generation
│   │   │   ├── feedback_service.dart       # Audio/haptic feedback
│   │   │   ├── server_discovery_service.dart # UDP server discovery
│   │   │   └── audit_websocket_service.dart  # Real-time audit sync
│   │   ├── theme/                # AppColors and styling constants
│   │   ├── utils/                # Platform utilities
│   │   └── widgets/              # 12 reusable UI components
│   └── screens/                  # Feature screens (15 módulos + mobile)
│       ├── launcher/             # Startup/backend connection screen
│       ├── login/                # Authentication screen
│       ├── material_warehousing/ # Material receiving module
│       ├── material_outgoing/    # Material outgoing module
│       ├── material_return/      # Material return to supplier
│       ├── material_control/     # Material master data
│       ├── iqc_inspection/       # Quality inspection module (5 archivos)
│       ├── quality_specs/        # Quality specifications
│       ├── quarantine/           # Quarantine management (3 archivos)
│       ├── long_term_inventory/  # Inventory tracking module
│       ├── inventory_audit/      # Physical inventory audit
│       ├── blacklist/            # Lot blacklist management
│       ├── user_management/      # User administration
│       ├── mobile/               # Mobile app screens (6 archivos)
│       │   ├── mobile_home_scaffold.dart      # Mobile navigation + drawer
│       │   ├── mobile_entry_screen.dart       # Mobile receiving (~62KB)
│       │   ├── mobile_outgoing_screen.dart    # Mobile outgoing (~30KB)
│       │   ├── mobile_inventory_screen.dart   # Mobile inventory lookup
│       │   ├── mobile_audit_screen.dart       # Mobile audit scanning
│       │   └── mobile_label_assignment_screen.dart # Label assignment (~48KB)
│       └── main_tabbed_screen.dart  # Main navigation container (~29KB)
├── backend/                      # Node.js REST API (Modularizado)
│   ├── server.js                 # Express server (~275 líneas, punto de entrada)
│   ├── config/
│   │   ├── database.js           # MySQL connection pool
│   │   └── permissions.js        # Constantes de permisos por departamento
│   ├── controllers/              # Lógica de negocio (14 controllers)
│   │   ├── warehousing.controller.js   # Entradas de material (~20KB)
│   │   ├── outgoing.controller.js      # Salidas de material (~21KB)
│   │   ├── return.controller.js        # Devoluciones de material
│   │   ├── plan.controller.js          # Plan de producción + BOM
│   │   ├── auth.controller.js          # Auth + Users + Permisos (~16KB)
│   │   ├── materials.controller.js     # Catálogo + Config IQC (~19KB)
│   │   ├── iqc.controller.js           # Inspección de calidad (~20KB)
│   │   ├── quality-specs.controller.js # Especificaciones de calidad
│   │   ├── quarantine.controller.js    # Cuarentena
│   │   ├── inventory.controller.js     # Inventario de lotes
│   │   ├── customers.controller.js     # Catálogo de clientes
│   │   ├── cancellation.controller.js  # Solicitudes de cancelación
│   │   ├── audit.controller.js         # Auditoría de inventario (~37KB)
│   │   └── blacklist.controller.js     # Lista negra de lotes
│   ├── routes/                   # Definición de rutas (16 archivos)
│   │   ├── index.js              # Agregador de rutas (~2.4KB)
│   │   ├── warehousing.routes.js
│   │   ├── outgoing.routes.js
│   │   ├── return.routes.js      # Material return
│   │   ├── plan.routes.js
│   │   ├── auth.routes.js
│   │   ├── materials.routes.js
│   │   ├── iqc.routes.js
│   │   ├── quality-specs.routes.js
│   │   ├── quarantine.routes.js
│   │   ├── inventory.routes.js
│   │   ├── customers.routes.js
│   │   ├── cancellation.routes.js
│   │   ├── print.routes.js       # Remote printing for mobile (~16KB)
│   │   ├── audit.routes.js       # Inventory audit
│   │   └── blacklist.routes.js   # Lot blacklist
│   ├── middleware/
│   │   ├── errorHandler.js       # Manejo centralizado de errores
│   │   └── rateLimiter.js        # Rate limiting para múltiples dispositivos
│   ├── utils/
│   │   ├── dbMigrations.js       # Migraciones de base de datos (~16KB)
│   │   ├── udpDiscovery.js       # Servicio UDP para descubrimiento de servidor
│   │   ├── sequenceService.js    # Generador de secuencias (~10KB)
│   │   └── partNumberHelper.js   # Utilidades de números de parte
│   ├── .env                      # Database credentials (not in git)
│   └── database/schema.sql       # Database schema reference
├── assets/                       # Images, logos
├── windows/                      # Windows platform files
├── android/                      # Android platform files (mobile app)
├── ios/                          # iOS platform files (mobile app)
├── installer/                    # Inno Setup installer config
└── Documentacion/                # User documentation
```

## Architecture Patterns

### Screen Organization
Each feature module follows this pattern:
- `*_screen.dart` - Main screen container
- `*_form_panel.dart` - Input forms
- `*_grid_panel.dart` - Data tables/grids
- `*_search_bar_panel.dart` - Search/filter controls

### Service Layer
| Service | Descripción |
|---------|-------------|
| `ApiService` | Static methods for all REST API calls |
| `BackendService` | Backend process management |
| `AuthService` | User authentication and session |
| `PrinterService` | Desktop label printing |
| `MobilePrinterService` | Remote printing for mobile devices |
| `ExcelExportService` | Excel file generation |
| `FeedbackService` | Audio/haptic feedback |
| `ServerDiscoveryService` | UDP-based server discovery for mobile |
| `AuditWebsocketService` | Real-time audit synchronization |

### Localization
- `LanguageProvider` - ChangeNotifier for language state
- `AppTranslations` - Static translation map
- Use `languageProvider.tr('key')` for translations

### UI Components
- `AppColors` - Centralized color constants
- `SimpleGrid` - Basic data grid widget
- `LabeledField`, `HorizontalField` - Form field wrappers
- `TableDropdownField` - Searchable dropdown with table display

### Mobile Architecture
- Separate `mobile/` folder for mobile-specific screens
- `MobileHomeScaffold` - Bottom navigation for mobile
- Responsive layouts that adapt to mobile screen sizes
- Camera integration for barcode scanning
- Remote printing via desktop server
- UDP-based automatic server discovery
