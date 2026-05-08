import 'package:flutter/material.dart';
import 'package:material_warehousing_flutter/core/services/auth_service.dart';
import 'package:material_warehousing_flutter/core/services/scanner_config_service.dart';
import 'package:material_warehousing_flutter/core/localization/app_translations.dart';
import 'package:material_warehousing_flutter/core/theme/app_colors.dart';
import 'package:material_warehousing_flutter/core/widgets/server_config_widget.dart';
import 'package:material_warehousing_flutter/screens/mobile/mobile_entry_screen.dart';
import 'package:material_warehousing_flutter/screens/mobile/mobile_inventory_screen.dart';
import 'package:material_warehousing_flutter/screens/mobile/mobile_reentry_screen.dart';
import 'package:material_warehousing_flutter/screens/mobile/mobile_return_screen.dart';
import 'package:material_warehousing_flutter/screens/mobile/mobile_audit_screen.dart';
import 'package:material_warehousing_flutter/screens/mobile/mobile_smt_requests_screen.dart';
import 'package:material_warehousing_flutter/screens/mobile/mobile_pcb_entry_screen.dart';
import 'package:material_warehousing_flutter/screens/mobile/mobile_pcb_exit_screen.dart';
import 'package:material_warehousing_flutter/screens/mobile/mobile_pcb_inventory_screen.dart';

/// Scaffold principal para la app móvil
/// Navegación: Entry, Inventory, Return, Reentry, Audit
class MobileHomeScaffold extends StatefulWidget {
  final LanguageProvider languageProvider;
  final VoidCallback onLogout;

  const MobileHomeScaffold({
    super.key,
    required this.languageProvider,
    required this.onLogout,
  });

  @override
  State<MobileHomeScaffold> createState() => _MobileHomeScaffoldState();
}

class _MobileHomeScaffoldState extends State<MobileHomeScaffold> {
  int _selectedIndex = 0;

  String tr(String key) => widget.languageProvider.tr(key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A1E2C),
      resizeToAvoidBottomInset: false,
      appBar: _buildAppBar(),
      body: _buildBody(),
      bottomNavigationBar: _buildBottomNav(),
      drawer: _buildDrawer(),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: const Color(0xFF252A3C),
      title: Row(
        children: [
          Expanded(
            child: Text(
              _getTitle(),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      leading: Builder(
        builder: (context) => IconButton(
          icon: const Icon(Icons.menu, color: Colors.white),
          onPressed: () => Scaffold.of(context).openDrawer(),
        ),
      ),
      actions: [
        // Indicador de servidor
        const Padding(
          padding: EdgeInsets.only(right: 8),
          child: ServerStatusBadge(compact: true),
        ),
      ],
    );
  }

  /// Definición de un tab del navbar inferior, con su permiso.
  /// El [index] es estable: aunque se oculten tabs por permiso,
  /// los demás conservan su index original.
  List<_TabDef> get _allTabs => [
        _TabDef(
          index: 0,
          icon: Icons.input,
          label: tr('nav_entry'),
          title: tr('nav_entry'),
          builder: () =>
              MobileEntryScreen(languageProvider: widget.languageProvider),
          isAllowed: () => AuthService.canWriteWarehousing,
        ),
        _TabDef(
          index: 1,
          icon: Icons.inventory_2,
          label: tr('nav_inventory'),
          title: tr('nav_inventory'),
          builder: () =>
              MobileInventoryScreen(languageProvider: widget.languageProvider),
          isAllowed: () => AuthService.canViewInventory,
        ),
        _TabDef(
          index: 2,
          icon: Icons.assignment_return,
          label: tr('nav_return'),
          title: tr('material_return'),
          builder: () =>
              MobileReturnScreen(languageProvider: widget.languageProvider),
          isAllowed: () => AuthService.canWriteMaterialReturn,
        ),
        _TabDef(
          index: 3,
          icon: Icons.move_to_inbox,
          label: tr('nav_reentry'),
          title: tr('nav_reentry'),
          builder: () =>
              MobileReentryScreen(languageProvider: widget.languageProvider),
          isAllowed: () => AuthService.canWriteReentry,
        ),
        _TabDef(
          index: 4,
          icon: Icons.fact_check,
          label: tr('audit_inventory'),
          title: tr('audit_inventory'),
          builder: () =>
              MobileAuditScreen(languageProvider: widget.languageProvider),
          isAllowed: () => AuthService.canScanAudit,
        ),
        _TabDef(
          index: 5,
          icon: Icons.notifications_active,
          label: 'SMT',
          title: 'Solicitudes SMT',
          builder: () => MobileSMTRequestsScreen(
              languageProvider: widget.languageProvider),
          isAllowed: () => AuthService.canViewSMTRequests,
        ),
        _TabDef(
          index: 6,
          icon: Icons.developer_board,
          label: 'PCB In',
          title: 'PCB In',
          builder: () =>
              MobilePcbEntryScreen(languageProvider: widget.languageProvider),
          isAllowed: () => AuthService.canViewPcbEntrada,
        ),
        _TabDef(
          index: 7,
          icon: Icons.developer_board_off,
          label: 'PCB Out',
          title: 'PCB Out',
          builder: () =>
              MobilePcbExitScreen(languageProvider: widget.languageProvider),
          isAllowed: () => AuthService.canViewPcbSalida,
        ),
        _TabDef(
          index: 8,
          icon: Icons.inventory,
          label: 'PCB Inv',
          title: tr('pcb_inventario_title'),
          builder: () => MobilePcbInventoryScreen(
              languageProvider: widget.languageProvider),
          isAllowed: () => AuthService.canViewPcbInventario,
        ),
      ];

  List<_TabDef> get _visibleTabs =>
      _allTabs.where((t) => t.isAllowed()).toList();

  /// Devuelve el tab actualmente seleccionado si está visible;
  /// si no, el primer visible. Retorna null si no hay ninguno visible.
  _TabDef? _activeTab(List<_TabDef> visible) {
    if (visible.isEmpty) return null;
    return visible.firstWhere(
      (t) => t.index == _selectedIndex,
      orElse: () => visible.first,
    );
  }

  String _getTitle() {
    final visible = _visibleTabs;
    final active = _activeTab(visible);
    return active?.title ?? 'Material Control';
  }

  Widget _buildBody() {
    final visible = _visibleTabs;
    if (visible.isEmpty) return _buildNoAccessBody();
    final active = _activeTab(visible)!;
    return active.builder();
  }

  Widget _buildNoAccessBody() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.lock_outline, color: Colors.white38, size: 64),
            const SizedBox(height: 16),
            const Text(
              'Sin acceso',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'No tienes permisos para acceder a ningún módulo.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70, fontSize: 14),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () async {
                await AuthService.logout();
                if (mounted) widget.onLogout();
              },
              icon: const Icon(Icons.logout),
              label: const Text('Cerrar sesión'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.headerTab,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget? _buildBottomNav() {
    final visible = _visibleTabs;
    if (visible.isEmpty) return null;
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF252A3C),
        boxShadow: [
          BoxShadow(
            color: Colors.black26,
            blurRadius: 8,
            offset: Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: visible
                  .map((t) => _buildNavItem(t.index, t.icon, t.label))
                  .toList(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(int index, IconData icon, String label) {
    final isSelected = _selectedIndex == index;

    return SizedBox(
      width: 72,
      child: InkWell(
        onTap: () => setState(() => _selectedIndex = index),
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          decoration: BoxDecoration(
            color: isSelected
                ? AppColors.headerTab.withValues(alpha: 0.2)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                color: isSelected ? AppColors.headerTab : Colors.white54,
                size: 24,
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: TextStyle(
                  color: isSelected ? AppColors.headerTab : Colors.white54,
                  fontSize: 10,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDrawer() {
    final user = AuthService.currentUser;

    return Drawer(
      backgroundColor: const Color(0xFF1A1E2C),
      child: SafeArea(
        child: Column(
          children: [
            // Header con info de usuario
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(
                color: Color(0xFF252A3C),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Logo de la empresa
                  Image.asset(
                    'assets/logo.png',
                    width: 80,
                    height: 80,
                    fit: BoxFit.contain,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    user?.nombreCompleto ?? 'Usuario',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    user?.departamento ?? '',
                    style: const TextStyle(
                      color: Colors.white54,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),

            // Menu items
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  const SizedBox(height: 8),
                  ..._visibleTabs.map(
                    (tab) => _buildDrawerItem(
                      icon: tab.icon,
                      label: tab.title,
                      selected: _selectedIndex == tab.index,
                      onTap: () {
                        setState(() => _selectedIndex = tab.index);
                        Navigator.pop(context);
                      },
                    ),
                  ),
                  const Divider(color: Colors.white24),

                  // Configuración de modo de escaneo
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Text(
                      tr('scanner_settings'),
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.5),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  _buildScannerModeSelector(),
                  const Divider(color: Colors.white24),

                  // Selector de idioma
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Text(
                      tr('language'),
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.5),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  _buildLanguageSelector(),
                  const Divider(color: Colors.white24),

                  // Configuración de servidor
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Text(
                      tr('server'),
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.5),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: ServerConfigWidget(
                      onServerChanged: () {
                        setState(() {});
                      },
                    ),
                  ),
                ],
              ),
            ),

            // Footer con logout
            Container(
              decoration: const BoxDecoration(
                border: Border(
                  top: BorderSide(color: Colors.white24),
                ),
              ),
              child: ListTile(
                leading: const Icon(Icons.logout, color: Colors.red),
                title: Text(
                  tr('logout'),
                  style: const TextStyle(color: Colors.red),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _showLogoutDialog();
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLanguageSelector() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          _buildLanguageOption('🇺🇸', 'EN', 'en'),
          const SizedBox(width: 8),
          _buildLanguageOption('🇪🇸', 'ES', 'es'),
          const SizedBox(width: 8),
          _buildLanguageOption('🇰🇷', 'KO', 'ko'),
        ],
      ),
    );
  }

  Widget _buildLanguageOption(String flag, String label, String locale) {
    final isSelected = widget.languageProvider.currentLocale == locale;
    return Expanded(
      child: InkWell(
        onTap: () {
          widget.languageProvider.setLocale(locale);
          setState(() {});
        },
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected
                ? AppColors.headerTab.withValues(alpha: 0.2)
                : const Color(0xFF252A3C),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isSelected ? AppColors.headerTab : Colors.white24,
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Column(
            children: [
              Text(flag, style: const TextStyle(fontSize: 20)),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  color: isSelected ? AppColors.headerTab : Colors.white54,
                  fontSize: 11,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDrawerItem({
    required IconData icon,
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Icon(
        icon,
        color: selected ? AppColors.headerTab : Colors.white70,
      ),
      title: Text(
        label,
        style: TextStyle(
          color: selected ? AppColors.headerTab : Colors.white,
          fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
        ),
      ),
      selected: selected,
      selectedTileColor: AppColors.headerTab.withValues(alpha: 0.1),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
      ),
      onTap: onTap,
    );
  }

  Widget _buildScannerModeSelector() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF1A1E2C),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            // Modo Cámara
            Expanded(
              child: GestureDetector(
                onTap: () async {
                  await ScannerConfigService.setMode(ScannerMode.camera);
                  setState(() {});
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: ScannerConfigService.isCameraMode
                        ? AppColors.headerTab
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.camera_alt,
                        color: ScannerConfigService.isCameraMode
                            ? Colors.white
                            : Colors.white54,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          tr('camera_mode'),
                          style: TextStyle(
                            color: ScannerConfigService.isCameraMode
                                ? Colors.white
                                : Colors.white54,
                            fontWeight: ScannerConfigService.isCameraMode
                                ? FontWeight.bold
                                : FontWeight.normal,
                            fontSize: 13,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            // Modo Lector/PDA
            Expanded(
              child: GestureDetector(
                onTap: () async {
                  await ScannerConfigService.setMode(ScannerMode.reader);
                  setState(() {});
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: ScannerConfigService.isReaderMode
                        ? AppColors.headerTab
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.barcode_reader,
                        color: ScannerConfigService.isReaderMode
                            ? Colors.white
                            : Colors.white54,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          tr('reader_mode'),
                          style: TextStyle(
                            color: ScannerConfigService.isReaderMode
                                ? Colors.white
                                : Colors.white54,
                            fontWeight: ScannerConfigService.isReaderMode
                                ? FontWeight.bold
                                : FontWeight.normal,
                            fontSize: 13,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showLogoutDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF252A3C),
        title: Text(
          tr('logout'),
          style: const TextStyle(color: Colors.white),
        ),
        content: Text(
          tr('logout_confirm'),
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(tr('cancel')),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            onPressed: () async {
              Navigator.pop(context);
              await AuthService.logout();
              widget.onLogout();
            },
            child: Text(tr('logout')),
          ),
        ],
      ),
    );
  }
}

class _TabDef {
  final int index;
  final IconData icon;
  final String label;
  final String title;
  final Widget Function() builder;
  final bool Function() isAllowed;

  const _TabDef({
    required this.index,
    required this.icon,
    required this.label,
    required this.title,
    required this.builder,
    required this.isAllowed,
  });
}
