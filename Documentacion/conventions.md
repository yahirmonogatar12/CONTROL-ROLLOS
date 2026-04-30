# Code Conventions

> **Última actualización:** Enero 2026

## Dart/Flutter Style

### Naming
- Classes: PascalCase (`WarehousingFormPanel`, `ApiService`)
- Files: snake_case (`warehousing_form_panel.dart`, `api_service.dart`)
- Variables/methods: camelCase (`_currentLotData`, `_onScanSubmitted`)
- Private members: prefix with underscore (`_controller`, `_isLoading`)
- Constants: camelCase for class constants (`baseUrl`, `maxRetries`)

### Widget Structure
```dart
class FeatureScreen extends StatefulWidget {
  final LanguageProvider languageProvider;  // Required for all screens
  
  const FeatureScreen({super.key, required this.languageProvider});

  @override
  State<FeatureScreen> createState() => _FeatureScreenState();
}
```

### State Management
- Use `StatefulWidget` with `setState()` for local state
- Use `ChangeNotifier` pattern for shared state (e.g., `LanguageProvider`)
- Pass callbacks down for child-to-parent communication
- Use `GlobalKey<ChildState>` to call child methods from parent

### Controllers
- Declare controllers as private class members
- Initialize in `initState()` or at declaration
- Always dispose in `dispose()` method
- Use listeners for reactive updates

## UI Patterns

### Form Fields
- Use `fieldDecoration()` helper for consistent TextField styling
- Wrap fields with `LabeledField` for label + input layout
- Use `TableDropdownField` for searchable dropdown with table display

### Colors
- Always use `AppColors` constants, never hardcode colors
- Common colors: `panelBackground`, `gridHeader`, `fieldBackground`, `border`
- Button colors: `buttonSave`, `buttonSearch`, `buttonExcel`, `buttonGray`

### Grid/Table Styling
- Header: `AppColors.gridHeader` with white text
- Rows: alternate between `gridRowEven` and `gridRowOdd`
- Selected row: `AppColors.gridSelectedRow`
- Font size: 11-12px for grid content

### Spacing
- Standard padding: 8px, 12px, 16px
- Field height: ~26-28px
- Button height: ~28-32px
- Grid row height: ~26px

## API Service Pattern

### Static Methods
```dart
static Future<List<Map<String, dynamic>>> getFeatureData() async {
  try {
    final response = await http.get(Uri.parse('$baseUrl/endpoint'));
    if (response.statusCode == 200) {
      final List<dynamic> data = json.decode(response.body);
      return data.cast<Map<String, dynamic>>();
    }
    return [];
  } catch (e) {
    print('Error en getFeatureData: $e');
    return [];
  }
}
```

### Error Handling
- Return empty list/map on error for GET requests
- Return `Map<String, dynamic>` with `success` and `error` keys for mutations
- Print errors with descriptive prefix for debugging

## Localization

### Adding Translations
1. Add key to all three locales in `app_translations.dart`: `en`, `es`, `ko`
2. Use `languageProvider.tr('key')` in widgets
3. Keep keys lowercase with underscores: `material_warehousing`, `save_button`

### Translation Access
```dart
// In StatefulWidget
String tr(String key) => widget.languageProvider.tr(key);

// In build method
Text(tr('save'))
```

## Permission Checks

### Before Write Operations
```dart
final canWrite = AuthService.canWriteWarehousing;
if (!canWrite) {
  // Show read-only indicator or disable buttons
}
```

### Department-Based Access
- `Sistemas`, `Gerencia`, `Administración` - Full access
- `Almacén`, `Almacén Supervisor` - Warehousing + Outgoing write
- `Calidad`, `Calidad Supervisor` - IQC write only
