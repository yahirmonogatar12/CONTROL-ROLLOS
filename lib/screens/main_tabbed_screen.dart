import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_warehousing_flutter/core/localization/app_translations.dart';
import 'package:material_warehousing_flutter/core/widgets/language_selector.dart';
import 'package:material_warehousing_flutter/core/services/auth_service.dart';
import 'package:material_warehousing_flutter/core/services/api_service.dart';
import 'package:material_warehousing_flutter/core/services/update_service.dart';
import 'package:material_warehousing_flutter/core/theme/app_colors.dart';
import 'package:material_warehousing_flutter/screens/material_warehousing/material_warehousing_screen.dart';
import 'package:material_warehousing_flutter/screens/material_outgoing/material_outgoing_screen.dart';
import 'package:material_warehousing_flutter/screens/long_term_inventory/long_term_inventory_screen.dart';
import 'package:material_warehousing_flutter/screens/material_control/material_control_screen.dart';
import 'package:material_warehousing_flutter/screens/user_management/user_management_screen.dart';
import 'package:material_warehousing_flutter/screens/material_return/material_return_screen.dart';
import 'package:material_warehousing_flutter/screens/material_requirements/material_requirements_screen.dart';
import 'package:material_warehousing_flutter/screens/reentry/reentry_screen.dart';
import 'package:material_warehousing_flutter/screens/location_search/location_search_screen.dart';
import 'package:material_warehousing_flutter/screens/inventory_audit/inventory_audit_screen.dart';
import 'package:material_warehousing_flutter/screens/material_shortage/material_shortage_screen.dart';
import 'package:material_warehousing_flutter/screens/pcb_entrada/pcb_entrada_screen.dart';
import 'package:material_warehousing_flutter/screens/pcb_salida/pcb_salida_screen.dart';
import 'package:material_warehousing_flutter/screens/pcb_inventario/pcb_inventario_screen.dart';
import 'package:material_warehousing_flutter/screens/smt_requests/smt_requests_screen.dart';
import 'package:material_warehousing_flutter/core/widgets/smt_notification_overlay.dart';
import 'dart:async';

/// Información de cada tab visible
class _TabInfo {
  final String key;
  final String titleKey;
  final int Function()? getBadgeCount;
  
  _TabInfo({
    required this.key,
    required this.titleKey,
    this.getBadgeCount,
  });
}

class MainTabbedScreen extends StatefulWidget {
  final LanguageProvider languageProvider;
  final VoidCallback? onLogout;
  
  const MainTabbedScreen({
    super.key, 
    required this.languageProvider,
    this.onLogout,
  });

  @override
  State<MainTabbedScreen> createState() => _MainTabbedScreenState();
}

class _MainTabbedScreenState extends State<MainTabbedScreen> {
  int _activeTab = 0;
  
  // Contadores de badges
  int _requirementsPendingCount = 0;
  int _smtPendingCount = 0;
  bool _smtFirstLoad = true; // No mostrar notificaciones en la primera carga
  Timer? _badgeTimer;
  
  // Keys para acceder a los screens y refrescar datos
  final GlobalKey<MaterialWarehousingScreenState> _warehousingScreenKey = GlobalKey();
  final GlobalKey<MaterialOutgoingScreenState> _outgoingScreenKey = GlobalKey();
  final GlobalKey<MaterialReturnScreenState> _returnScreenKey = GlobalKey();
  final GlobalKey<LocationSearchScreenState> _locationSearchScreenKey = GlobalKey();
  final GlobalKey<LongTermInventoryScreenState> _inventoryScreenKey = GlobalKey();
  final GlobalKey<SMTRequestsScreenState> _smtRequestsScreenKey = GlobalKey();
  
  // Lista de tabs visibles según permisos
  List<_TabInfo> _visibleTabs = [];

  @override
  void initState() {
    super.initState();
    widget.languageProvider.addListener(_onLanguageChanged);
    _buildVisibleTabs();
    _loadBadgeCounts();
    _badgeTimer = Timer.periodic(const Duration(seconds: 30), (_) => _loadBadgeCounts());
    HardwareKeyboard.instance.addHandler(_handleKeyEvent);
  }

  bool _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return false;
    if (_visibleTabs.isEmpty) return false;

    final isCtrl = HardwareKeyboard.instance.isControlPressed;
    final isShift = HardwareKeyboard.instance.isShiftPressed;
    if (!isCtrl) return false;

    // Ctrl+Tab → tab siguiente
    if (!isShift && event.logicalKey == LogicalKeyboardKey.tab) {
      setState(() => _activeTab = (_activeTab + 1) % _visibleTabs.length);
      _loadBadgeCounts();
      _requestScanFocusForActiveTab();
      return true;
    }

    // Ctrl+Shift+Tab → tab anterior
    if (isShift && event.logicalKey == LogicalKeyboardKey.tab) {
      setState(() => _activeTab = (_activeTab - 1 + _visibleTabs.length) % _visibleTabs.length);
      _loadBadgeCounts();
      _requestScanFocusForActiveTab();
      return true;
    }

    // Ctrl+1..9 → saltar a tab específico
    const digitKeys = [
      LogicalKeyboardKey.digit1,
      LogicalKeyboardKey.digit2,
      LogicalKeyboardKey.digit3,
      LogicalKeyboardKey.digit4,
      LogicalKeyboardKey.digit5,
      LogicalKeyboardKey.digit6,
      LogicalKeyboardKey.digit7,
      LogicalKeyboardKey.digit8,
      LogicalKeyboardKey.digit9,
    ];
    final tabIndex = digitKeys.indexOf(event.logicalKey);
    if (tabIndex >= 0 && tabIndex < _visibleTabs.length) {
      setState(() => _activeTab = tabIndex);
      _loadBadgeCounts();
      _requestScanFocusForActiveTab();
      return true;
    }

    return false;
  }
  
  /// Construye la lista de tabs visibles según los permisos del usuario
  void _buildVisibleTabs() {
    _visibleTabs = [];
    
    print('========================================');
    print('CONSTRUYENDO TABS VISIBLES');
    print('canViewWarehousing: ${AuthService.canViewWarehousing}');
    print('canViewOutgoing: ${AuthService.canViewOutgoing}');
    print('canViewInventory: ${AuthService.canViewInventory}');
    print('canManageUsers: ${AuthService.canManageUsers}');
    print('========================================');
    
    // Material Warehousing - requiere view_warehousing
    if (AuthService.canViewWarehousing) {
      _visibleTabs.add(_TabInfo(
        key: 'warehousing',
        titleKey: 'material_warehousing',
      ));
    }
    
    // Material Outgoing - requiere view_outgoing
    if (AuthService.canViewOutgoing) {
      _visibleTabs.add(_TabInfo(
        key: 'outgoing',
        titleKey: 'material_outgoing',
      ));
    }
    
    // Material Return - requiere view_material_return
    if (AuthService.canViewMaterialReturn) {
      _visibleTabs.add(_TabInfo(
        key: 'material_return',
        titleKey: 'material_return',
      ));
    }
    
    // Long Term Inventory - requiere view_inventory
    if (AuthService.canViewInventory) {
      _visibleTabs.add(_TabInfo(
        key: 'longterm',
        titleKey: 'long_term_inventory',
      ));
    }
    
    // Reentry (Reingreso) - requiere view_reentry
    if (AuthService.canViewReentry) {
      _visibleTabs.add(_TabInfo(
        key: 'reentry',
        titleKey: 'nav_reentry',
      ));
    }
    
    // Location Search (Búsqueda de Ubicación) - requiere view_location_search
    if (AuthService.canViewLocationSearch) {
      _visibleTabs.add(_TabInfo(
        key: 'location_search',
        titleKey: 'nav_location_search',
      ));
    }
    
    // Material Control - requiere view_inventory
    if (AuthService.canViewInventory) {
      _visibleTabs.add(_TabInfo(
        key: 'material_control',
        titleKey: 'material_control',
      ));
    }
    
    // Material Requirements - requiere view_requirements
    if (AuthService.canViewRequirements) {
      _visibleTabs.add(_TabInfo(
        key: 'requirements',
        titleKey: 'material_requirements',
        getBadgeCount: () => _requirementsPendingCount,
      ));
    }
    
    // Material Shortage - requiere view_inventory
    if (AuthService.canViewInventory) {
      _visibleTabs.add(_TabInfo(
        key: 'material_shortage',
        titleKey: 'material_shortage',
      ));
    }

    // PCB Entrada - requiere view_pcb_entrada
    if (AuthService.canViewPcbEntrada) {
      _visibleTabs.add(_TabInfo(
        key: 'pcb_entrada',
        titleKey: 'pcb_entrada_title',
      ));
    }

    // PCB Salida - requiere view_pcb_salida
    if (AuthService.canViewPcbSalida) {
      _visibleTabs.add(_TabInfo(
        key: 'pcb_salida',
        titleKey: 'pcb_salida_title',
      ));
    }

    // PCB Inventario actual - requiere view_pcb_inventario
    if (AuthService.canViewPcbInventario) {
      _visibleTabs.add(_TabInfo(
        key: 'pcb_inventario',
        titleKey: 'pcb_inventario_title',
      ));
    }

    // Inventory Audit - requiere view_audit
    if (AuthService.canViewAudit) {
      _visibleTabs.add(_TabInfo(
        key: 'inventory_audit',
        titleKey: 'audit_inventory',
      ));
    }

    // SMT Requests - requiere view_smt_requests
    if (AuthService.canViewSMTRequests) {
      _visibleTabs.add(_TabInfo(
        key: 'smt_requests',
        titleKey: 'nav_smt_requests',
        getBadgeCount: () => _smtPendingCount,
      ));
    }

    // User Management - requiere manage_users
    if (AuthService.canManageUsers) {
      _visibleTabs.add(_TabInfo(
        key: 'user_management',
        titleKey: 'user_management',
      ));
    }
    
    print('TABS VISIBLES: ${_visibleTabs.map((t) => t.key).toList()}');
    
    // Fallback: si no hay tabs, mostrar mensaje vacío
    if (_visibleTabs.isEmpty) {
      print('ADVERTENCIA: Usuario sin permisos para ningún módulo');
    }
  }
  
  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    widget.languageProvider.removeListener(_onLanguageChanged);
    _badgeTimer?.cancel();
    super.dispose();
  }
  
  void _onLanguageChanged() {
    if (mounted) setState(() {});
  }
  
  Future<void> _loadBadgeCounts() async {
    try {
      final requirementsCount = await ApiService.getRequirementsPendingCount();
      if (mounted) {
        setState(() {
          _requirementsPendingCount = requirementsCount;
        });
      }
    } catch (e) {
      // Ignorar errores
    }

    // Polling SMT: detectar nuevas solicitudes y mostrar notificación overlay
    if (AuthService.canViewSMTRequests) {
      try {
        final smtCount = await ApiService.getSMTRequestsPendingCount();
        if (mounted) {
          // En la primera carga solo guardamos el count base (sin notificaciones)
          if (_smtFirstLoad) {
            _smtFirstLoad = false;
            setState(() => _smtPendingCount = smtCount);
          } else if (smtCount > _smtPendingCount) {
            // Hay nuevas solicitudes — obtener la(s) nueva(s) para mostrar en overlay
            final diff = smtCount - _smtPendingCount;
            final newRequests = await ApiService.getSMTRequests(
              status: 'pending',
              limit: diff,
            );
            for (final req in newRequests) {
              final lineId = req['line_id']?.toString() ?? '';
              final reelCode = req['reel_code']?.toString() ?? '';
              final partNumber =
                  req['numero_parte']?.toString().trim().isNotEmpty == true
                      ? req['numero_parte'].toString().trim()
                      : reelCode.split('-').first.trim();
              final ubicacion = req['ubicacion_rollos']?.toString().trim();

              SMTNotificationOverlay.instance.show(
                lineId: lineId,
                numeroParte: partNumber,
                ubicacion: ubicacion,
              );
            }
            setState(() => _smtPendingCount = smtCount);
          } else {
            setState(() => _smtPendingCount = smtCount);
          }
        }
      } catch (e) {
        // Ignorar errores de polling SMT
      }
    }
  }
  
  /// Refrescar datos maestros (materiales, clientes, etc.)
  Future<void> _refreshMasterData() async {
    // Mostrar indicador de carga
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              ),
              const SizedBox(width: 12),
              Text(widget.languageProvider.tr('refreshing_data')),
            ],
          ),
          duration: const Duration(seconds: 1),
          backgroundColor: Colors.blue,
        ),
      );
    }
    
    try {
      // Recargar materiales (esto actualiza el cache en api_service)
      await ApiService.getMateriales();
      // Recargar contadores de badges
      await _loadBadgeCounts();
      
      // Recargar materiales en el formulario de Warehousing (actualiza checkboxes IQC/Lote)
      await _warehousingScreenKey.currentState?.reloadFormMateriales();
      
      // Recargar materiales en búsqueda de ubicación
      await _locationSearchScreenKey.currentState?.reloadMateriales();

      // Recargar inventario actual (para reflejar cambios de ubicación por reentry, etc.)
      await _inventoryScreenKey.currentState?.reloadData();

      if (mounted) {
        // Forzar rebuild de la UI
        setState(() {});
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ ${widget.languageProvider.tr('data_refreshed')}'),
            duration: const Duration(seconds: 2),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Error: $e'),
            duration: const Duration(seconds: 3),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
  
  /// Solicita focus en el campo de escaneo del tab activo
  void _requestScanFocusForActiveTab() {
    if (_visibleTabs.isEmpty) return;
    
    final activeTabKey = _visibleTabs[_activeTab].key;
    
    // Solicitar focus con un pequeño delay para asegurar que el widget esté montado
    WidgetsBinding.instance.addPostFrameCallback((_) {
      switch (activeTabKey) {
        case 'warehousing':
          _warehousingScreenKey.currentState?.requestScanFocus();
          break;
        case 'outgoing':
          _outgoingScreenKey.currentState?.requestScanFocus();
          break;
        case 'material_return':
          _returnScreenKey.currentState?.requestScanFocus();
          break;
      }
    });
  }
  
  /// Construye el widget correspondiente a cada tab
  Widget _buildTabContent(String key, String currentLocale) {
    switch (key) {
      case 'warehousing':
        return MaterialWarehousingScreen(
          key: _warehousingScreenKey,
          languageProvider: widget.languageProvider,
        );
      case 'outgoing':
        return MaterialOutgoingScreen(
          key: _outgoingScreenKey,
          languageProvider: widget.languageProvider,
        );
      case 'material_return':
        return MaterialReturnScreen(
          key: _returnScreenKey,
          languageProvider: widget.languageProvider,
        );
      case 'longterm':
        return LongTermInventoryScreen(
          key: _inventoryScreenKey,
          languageProvider: widget.languageProvider,
        );
      case 'reentry':
        return ReentryScreen(
          key: ValueKey('reentry_$currentLocale'),
          languageProvider: widget.languageProvider,
        );
      case 'location_search':
        return LocationSearchScreen(
          key: _locationSearchScreenKey,
          languageProvider: widget.languageProvider,
        );
      case 'material_control':
        return MaterialControlScreen(
          key: ValueKey('material_control_$currentLocale'),
          languageProvider: widget.languageProvider,
        );
      case 'requirements':
        return MaterialRequirementsScreen(
          key: ValueKey('requirements_$currentLocale'),
          languageProvider: widget.languageProvider,
        );
      case 'material_shortage':
        return MaterialShortageScreen(
          key: ValueKey('material_shortage_$currentLocale'),
          languageProvider: widget.languageProvider,
        );
      case 'pcb_entrada':
        return PcbEntradaScreen(
          key: ValueKey('pcb_entrada_$currentLocale'),
          languageProvider: widget.languageProvider,
        );
      case 'pcb_salida':
        return PcbSalidaScreen(
          key: ValueKey('pcb_salida_$currentLocale'),
          languageProvider: widget.languageProvider,
        );
      case 'pcb_inventario':
        return PcbInventarioScreen(
          key: ValueKey('pcb_inventario_$currentLocale'),
          languageProvider: widget.languageProvider,
        );
      case 'inventory_audit':
        return InventoryAuditScreen(
          key: ValueKey('inventory_audit_$currentLocale'),
          languageProvider: widget.languageProvider,
        );
      case 'smt_requests':
        return SMTRequestsScreen(
          key: _smtRequestsScreenKey,
          languageProvider: widget.languageProvider,
        );
      case 'user_management':
        return UserManagementScreen(
          key: ValueKey('user_management_$currentLocale'),
          languageProvider: widget.languageProvider,
        );
      default:
        return const Center(child: Text('Módulo no disponible'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentLocale = widget.languageProvider.currentLocale;
    
    // Si no hay tabs visibles, mostrar mensaje
    if (_visibleTabs.isEmpty) {
      return Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              _TopTabBarSimple(
                languageProvider: widget.languageProvider,
                onLogout: widget.onLogout,
              ),
              const Expanded(
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.lock_outline, size: 64, color: Colors.white24),
                      SizedBox(height: 16),
                      Text(
                        'No tienes permisos para acceder a ningún módulo',
                        style: TextStyle(color: Colors.white54, fontSize: 16),
                      ),
                      SizedBox(height: 8),
                      Text(
                        'Contacta al administrador del sistema',
                        style: TextStyle(color: Colors.white38, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }
    
    // Asegurar que el índice activo sea válido
    if (_activeTab >= _visibleTabs.length) {
      _activeTab = 0;
    }
    
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _TopTabBarDynamic(
              tabs: _visibleTabs,
              activeIndex: _activeTab,
              onChanged: (i) {
                setState(() => _activeTab = i);
                _loadBadgeCounts();
                // Solicitar focus en el campo de escaneo del nuevo tab
                _requestScanFocusForActiveTab();
              },
              languageProvider: widget.languageProvider,
              onLogout: widget.onLogout,
              onRefresh: _refreshMasterData,
            ),
            Expanded(
              child: IndexedStack(
                key: ValueKey('tabs_$currentLocale'),
                index: _activeTab,
                children: _visibleTabs.map((tab) => 
                  _buildTabContent(tab.key, currentLocale)
                ).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// TopTabBar simple para cuando no hay tabs
class _TopTabBarSimple extends StatelessWidget {
  final LanguageProvider languageProvider;
  final VoidCallback? onLogout;

  const _TopTabBarSimple({
    required this.languageProvider,
    this.onLogout,
  });

  @override
  Widget build(BuildContext context) {
    final currentUser = AuthService.currentUser;
    final tr = languageProvider.tr;
    
    return Container(
      height: 28,
      color: const Color(0xFF1E2228),
      child: Row(
        children: [
          const Spacer(),
          if (currentUser != null) ...[
            const Icon(Icons.person, size: 14, color: Colors.white54),
            const SizedBox(width: 4),
            Text(
              currentUser.nombreCompleto.isNotEmpty 
                ? currentUser.nombreCompleto 
                : currentUser.username,
              style: const TextStyle(fontSize: 11, color: Colors.white70),
            ),
            const SizedBox(width: 8),
            InkWell(
              onTap: () => _showLogoutConfirmation(context, tr, onLogout),
              borderRadius: BorderRadius.circular(4),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.red.withOpacity(0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.logout, size: 12, color: Colors.red),
                    const SizedBox(width: 4),
                    Text(tr('logout'), style: const TextStyle(fontSize: 10, color: Colors.red)),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),
          ],
          LanguageSelector(languageProvider: languageProvider),
          const SizedBox(width: 12),
        ],
      ),
    );
  }
}

/// TopTabBar dinámico que muestra solo los tabs permitidos
class _TopTabBarDynamic extends StatefulWidget {
  final List<_TabInfo> tabs;
  final int activeIndex;
  final ValueChanged<int> onChanged;
  final LanguageProvider languageProvider;
  final VoidCallback? onLogout;
  final VoidCallback? onRefresh;

  const _TopTabBarDynamic({
    required this.tabs,
    required this.activeIndex,
    required this.onChanged,
    required this.languageProvider,
    this.onLogout,
    this.onRefresh,
  });

  @override
  State<_TopTabBarDynamic> createState() => _TopTabBarDynamicState();
}

class _TopTabBarDynamicState extends State<_TopTabBarDynamic> {
  final ScrollController _scrollController = ScrollController();
  bool _canScrollLeft = false;
  bool _canScrollRight = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_updateScrollState);
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateScrollState());
  }

  @override
  void didUpdateWidget(_TopTabBarDynamic oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.activeIndex != widget.activeIndex) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToActiveTab());
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _updateScrollState() {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    final newLeft = pos.pixels > 0;
    final newRight = pos.maxScrollExtent > 0 && pos.pixels < pos.maxScrollExtent - 0.5;
    if (newLeft != _canScrollLeft || newRight != _canScrollRight) {
      setState(() {
        _canScrollLeft = newLeft;
        _canScrollRight = newRight;
      });
    }
  }

  void _scrollLeft() {
    if (!_scrollController.hasClients) return;
    final target = (_scrollController.offset - 200).clamp(0.0, _scrollController.position.maxScrollExtent);
    _scrollController.animateTo(target, duration: const Duration(milliseconds: 180), curve: Curves.easeOut);
  }

  void _scrollRight() {
    if (!_scrollController.hasClients) return;
    final target = (_scrollController.offset + 200).clamp(0.0, _scrollController.position.maxScrollExtent);
    _scrollController.animateTo(target, duration: const Duration(milliseconds: 180), curve: Curves.easeOut);
  }

  void _scrollToActiveTab() {
    if (!_scrollController.hasClients) return;
    // Aproximación: cada tab ~115px de ancho promedio
    const avgTabWidth = 115.0;
    final targetOffset = (widget.activeIndex * avgTabWidth - 60.0)
        .clamp(0.0, _scrollController.position.maxScrollExtent);
    _scrollController.animateTo(
      targetOffset,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
    );
  }

  Widget _buildTab(String title, int index, {int badgeCount = 0}) {
    final bool isActive = index == widget.activeIndex;
    return GestureDetector(
      onTap: () => widget.onChanged(index),
      child: Container(
        height: 26,
        margin: const EdgeInsets.only(right: 1),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: isActive
              ? const Color(0xFF3C4654)
              : const Color(0xFF2D333B),
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(3),
            topRight: Radius.circular(3),
          ),
        ),
        child: Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 12,
                  color: Colors.white,
                  fontWeight: FontWeight.w400,
                ),
              ),
              if (badgeCount > 0) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.orange,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    badgeCount > 99 ? '99+' : '$badgeCount',
                    style: const TextStyle(
                      fontSize: 9,
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _scrollArrow({required IconData icon, required VoidCallback onTap}) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          width: 22,
          height: 26,
          color: const Color(0xFF1E2228),
          alignment: Alignment.center,
          child: Icon(icon, size: 16, color: Colors.white60),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tr = widget.languageProvider.tr;
    final currentUser = AuthService.currentUser;

    return Container(
      height: 26,
      color: const Color(0xFF1E2228),
      child: Row(
        children: [
          // Flecha izquierda
          _scrollArrow(icon: Icons.chevron_left, onTap: _scrollLeft),
          // Tabs dinámicos scrollables
          Expanded(
            child: SingleChildScrollView(
              controller: _scrollController,
              scrollDirection: Axis.horizontal,
              physics: const ClampingScrollPhysics(),
              child: Row(
                children: widget.tabs.asMap().entries.map((entry) {
                  final index = entry.key;
                  final tab = entry.value;
                  final badgeCount = tab.getBadgeCount?.call() ?? 0;
                  return _buildTab(tr(tab.titleKey), index, badgeCount: badgeCount);
                }).toList(),
              ),
            ),
          ),
          // Flecha derecha
          _scrollArrow(icon: Icons.chevron_right, onTap: _scrollRight),
          const SizedBox(width: 4),
          // Botón de refrescar datos maestros
          Tooltip(
            message: tr('refresh_data'),
            child: InkWell(
              onTap: widget.onRefresh,
              borderRadius: BorderRadius.circular(4),
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Icon(Icons.refresh, size: 16, color: Colors.white70),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Usuario actual con menú dropdown
          if (currentUser != null) ...[
            PopupMenuButton<String>(
              offset: const Offset(0, 28),
              color: const Color(0xFF2D333B),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              onSelected: (value) {
                if (value == 'change_password') {
                  _showChangePasswordDialog(context, tr, currentUser.id);
                } else if (value == 'check_updates') {
                  UpdateService.checkAndPrompt(context, showNoUpdateMessage: true);
                } else if (value == 'logout') {
                  _showLogoutConfirmation(context, tr, widget.onLogout);
                }
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'change_password',
                  child: Row(
                    children: [
                      const Icon(Icons.lock_outline, size: 16, color: Colors.white70),
                      const SizedBox(width: 8),
                      Text(tr('change_password'), style: const TextStyle(color: Colors.white70, fontSize: 12)),
                    ],
                  ),
                ),
                const PopupMenuDivider(),
                PopupMenuItem(
                  value: 'check_updates',
                  child: Row(
                    children: [
                      const Icon(Icons.system_update, size: 16, color: Colors.blue),
                      const SizedBox(width: 8),
                      Text('Buscar actualizaciones', style: const TextStyle(color: Colors.white70, fontSize: 12)),
                    ],
                  ),
                ),
                PopupMenuItem(
                  enabled: false,
                  height: 24,
                  child: Text(
                    'v${UpdateService.currentVersion}',
                    style: const TextStyle(color: Colors.white38, fontSize: 10),
                  ),
                ),
                const PopupMenuDivider(),
                PopupMenuItem(
                  value: 'logout',
                  child: Row(
                    children: [
                      const Icon(Icons.logout, size: 16, color: Colors.red),
                      const SizedBox(width: 8),
                      Text(tr('logout'), style: const TextStyle(color: Colors.red, fontSize: 12)),
                    ],
                  ),
                ),
              ],
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.person, size: 14, color: Colors.white54),
                    const SizedBox(width: 4),
                    Text(
                      currentUser.nombreCompleto.isNotEmpty 
                        ? currentUser.nombreCompleto 
                        : currentUser.username,
                      style: const TextStyle(fontSize: 11, color: Colors.white70),
                    ),
                    const SizedBox(width: 4),
                    const Icon(Icons.arrow_drop_down, size: 16, color: Colors.white54),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),
          ],
          LanguageSelector(languageProvider: widget.languageProvider),
          const SizedBox(width: 12),
        ],
      ),
    );
  }
}

void _showChangePasswordDialog(BuildContext context, String Function(String) tr, int userId) {
  final currentPasswordController = TextEditingController();
  final newPasswordController = TextEditingController();
  final confirmPasswordController = TextEditingController();
  bool isLoading = false;
  String? errorMessage;
  bool obscureCurrentPassword = true;
  bool obscureNewPassword = true;
  bool obscureConfirmPassword = true;

  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        backgroundColor: AppColors.panelBackground,
        title: Row(
          children: [
            const Icon(Icons.lock_outline, color: Colors.white70, size: 20),
            const SizedBox(width: 8),
            Text(tr('change_password'), style: const TextStyle(color: Colors.white)),
          ],
        ),
        content: SizedBox(
          width: 350,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: currentPasswordController,
                obscureText: obscureCurrentPassword,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: tr('current_password'),
                  labelStyle: const TextStyle(color: Colors.white54),
                  enabledBorder: const OutlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                  focusedBorder: const OutlineInputBorder(borderSide: BorderSide(color: Colors.blue)),
                  suffixIcon: IconButton(
                    icon: Icon(obscureCurrentPassword ? Icons.visibility_off : Icons.visibility, color: Colors.white54, size: 20),
                    onPressed: () => setState(() => obscureCurrentPassword = !obscureCurrentPassword),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: newPasswordController,
                obscureText: obscureNewPassword,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: tr('new_password'),
                  labelStyle: const TextStyle(color: Colors.white54),
                  enabledBorder: const OutlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                  focusedBorder: const OutlineInputBorder(borderSide: BorderSide(color: Colors.blue)),
                  suffixIcon: IconButton(
                    icon: Icon(obscureNewPassword ? Icons.visibility_off : Icons.visibility, color: Colors.white54, size: 20),
                    onPressed: () => setState(() => obscureNewPassword = !obscureNewPassword),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: confirmPasswordController,
                obscureText: obscureConfirmPassword,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: tr('confirm_password'),
                  labelStyle: const TextStyle(color: Colors.white54),
                  enabledBorder: const OutlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                  focusedBorder: const OutlineInputBorder(borderSide: BorderSide(color: Colors.blue)),
                  suffixIcon: IconButton(
                    icon: Icon(obscureConfirmPassword ? Icons.visibility_off : Icons.visibility, color: Colors.white54, size: 20),
                    onPressed: () => setState(() => obscureConfirmPassword = !obscureConfirmPassword),
                  ),
                ),
              ),
              if (errorMessage != null) ...[
                const SizedBox(height: 12),
                Text(errorMessage!, style: const TextStyle(color: Colors.red, fontSize: 12)),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: isLoading ? null : () => Navigator.pop(context),
            child: Text(tr('cancel'), style: const TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: isLoading ? null : () async {
              // Validaciones
              if (currentPasswordController.text.isEmpty || 
                  newPasswordController.text.isEmpty || 
                  confirmPasswordController.text.isEmpty) {
                setState(() => errorMessage = tr('all_fields_required'));
                return;
              }
              if (newPasswordController.text != confirmPasswordController.text) {
                setState(() => errorMessage = tr('passwords_not_match'));
                return;
              }
              if (newPasswordController.text.length < 4) {
                setState(() => errorMessage = tr('password_min_length'));
                return;
              }
              
              setState(() {
                isLoading = true;
                errorMessage = null;
              });
              
              final result = await ApiService.changeOwnPassword(
                userId: userId,
                currentPassword: currentPasswordController.text,
                newPassword: newPasswordController.text,
              );
              
              if (result['success'] == true) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(tr('password_changed_success')),
                    backgroundColor: Colors.green,
                  ),
                );
              } else {
                setState(() {
                  isLoading = false;
                  errorMessage = result['error'] ?? tr('password_change_error');
                });
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
            child: isLoading 
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : Text(tr('save')),
          ),
        ],
      ),
    ),
  );
}

void _showLogoutConfirmation(BuildContext context, String Function(String) tr, VoidCallback? onLogout) {
  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: AppColors.panelBackground,
      title: Text(tr('logout'), style: const TextStyle(color: Colors.white)),
      content: Text(tr('logout_confirm'), style: const TextStyle(color: Colors.white70)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(tr('cancel'), style: const TextStyle(color: Colors.white54)),
        ),
        ElevatedButton(
          onPressed: () {
            Navigator.pop(context);
            onLogout?.call();
          },
          style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
          child: Text(tr('logout')),
        ),
      ],
    ),
  );
}
