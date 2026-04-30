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

  String _getTitle() {
    switch (_selectedIndex) {
      case 0:
        return tr('nav_entry');
      case 1:
        return tr('nav_inventory');
      case 2:
        return tr('material_return');
      case 3:
        return tr('nav_reentry');
      case 4:
        return tr('audit_inventory');
      case 5:
        return 'Solicitudes SMT';
      default:
        return 'Material Control';
    }
  }

  Widget _buildBody() {
    switch (_selectedIndex) {
      case 0:
        return MobileEntryScreen(languageProvider: widget.languageProvider);
      case 1:
        return MobileInventoryScreen(languageProvider: widget.languageProvider);
      case 2:
        return MobileReturnScreen(languageProvider: widget.languageProvider);
      case 3:
        return MobileReentryScreen(languageProvider: widget.languageProvider);
      case 4:
        return MobileAuditScreen(languageProvider: widget.languageProvider);
      case 5:
        return MobileSMTRequestsScreen(languageProvider: widget.languageProvider);
      default:
        return const Center(child: Text('Pantalla no encontrada'));
    }
  }

  Widget _buildBottomNav() {
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
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildNavItem(0, Icons.input, tr('nav_entry')),
              _buildNavItem(1, Icons.inventory_2, tr('nav_inventory')),
              _buildNavItem(2, Icons.assignment_return, tr('nav_return')),
              _buildNavItem(3, Icons.move_to_inbox, tr('nav_reentry')),
              _buildNavItem(4, Icons.fact_check, tr('audit_inventory')),
              _buildNavItem(5, Icons.notifications_active, 'SMT'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(int index, IconData icon, String label) {
    final isSelected = _selectedIndex == index;

    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _selectedIndex = index),
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.headerTab.withOpacity(0.2) : Colors.transparent,
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
                  _buildDrawerItem(
                    icon: Icons.input,
                    label: tr('nav_entry'),
                    selected: _selectedIndex == 0,
                    onTap: () {
                      setState(() => _selectedIndex = 0);
                      Navigator.pop(context);
                    },
                  ),
                  _buildDrawerItem(
                    icon: Icons.inventory_2,
                    label: tr('nav_inventory'),
                    selected: _selectedIndex == 1,
                    onTap: () {
                      setState(() => _selectedIndex = 1);
                      Navigator.pop(context);
                    },
                  ),
                  _buildDrawerItem(
                    icon: Icons.assignment_return,
                    label: tr('nav_return'),
                    selected: _selectedIndex == 2,
                    onTap: () {
                      setState(() => _selectedIndex = 2);
                      Navigator.pop(context);
                    },
                  ),
                  _buildDrawerItem(
                    icon: Icons.move_to_inbox,
                    label: tr('nav_reentry'),
                    selected: _selectedIndex == 3,
                    onTap: () {
                      setState(() => _selectedIndex = 3);
                      Navigator.pop(context);
                    },
                  ),
                  _buildDrawerItem(
                    icon: Icons.fact_check,
                    label: tr('audit_inventory'),
                    selected: _selectedIndex == 4,
                    onTap: () {
                      setState(() => _selectedIndex = 4);
                      Navigator.pop(context);
                    },
                  ),
                  _buildDrawerItem(
                    icon: Icons.notifications_active,
                    label: 'Solicitudes SMT',
                    selected: _selectedIndex == 5,
                    onTap: () {
                      setState(() => _selectedIndex = 5);
                      Navigator.pop(context);
                    },
                  ),
                  const Divider(color: Colors.white24),

                  // Configuración de modo de escaneo
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Text(
                      tr('scanner_settings'),
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.5),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  _buildScannerModeSelector(),
                  const Divider(color: Colors.white24),
                  
                  // Selector de idioma
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Text(
                      tr('language'),
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.5),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  _buildLanguageSelector(),
                  const Divider(color: Colors.white24),
                  
                  // Configuración de servidor
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Text(
                      tr('server'),
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.5),
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
            color: isSelected ? AppColors.headerTab.withOpacity(0.2) : const Color(0xFF252A3C),
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
      selectedTileColor: AppColors.headerTab.withOpacity(0.1),
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
