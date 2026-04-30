import 'package:flutter/material.dart';
import 'package:material_warehousing_flutter/core/localization/app_translations.dart';
import 'package:material_warehousing_flutter/core/theme/app_colors.dart';
import 'package:material_warehousing_flutter/core/services/auth_service.dart';
import 'quarantine_pending_grid.dart';
import 'quarantine_history_grid.dart';

// ============================================
// Quarantine Screen - Pantalla de Cuarentena
// ============================================
class QuarantineScreen extends StatefulWidget {
  final LanguageProvider languageProvider;

  const QuarantineScreen({
    super.key,
    required this.languageProvider,
  });

  @override
  State<QuarantineScreen> createState() => _QuarantineScreenState();
}

class _QuarantineScreenState extends State<QuarantineScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  
  final GlobalKey<QuarantinePendingGridState> _pendingGridKey = GlobalKey();
  final GlobalKey<QuarantineHistoryGridState> _historyGridKey = GlobalKey();

  String tr(String key) => widget.languageProvider.tr(key);

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _refreshCurrentTab() {
    if (_tabController.index == 0) {
      _pendingGridKey.currentState?.reloadData();
    } else {
      _historyGridKey.currentState?.reloadData();
    }
  }

  @override
  Widget build(BuildContext context) {
    final canWrite = AuthService.canWriteQuarantine;
    
    return Container(
      color: AppColors.panelBackground,
      child: Column(
        children: [
          // Header con tabs
          Container(
            height: 40,
            color: AppColors.gridHeader,
            child: Row(
              children: [
                const SizedBox(width: 12),
                const Icon(Icons.shield, color: Colors.orange, size: 18),
                const SizedBox(width: 8),
                Text(
                  tr('quarantine'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 24),
                
                // Tabs
                Expanded(
                  child: TabBar(
                    controller: _tabController,
                    isScrollable: true,
                    labelColor: Colors.orange,
                    unselectedLabelColor: Colors.white54,
                    indicatorColor: Colors.orange,
                    indicatorWeight: 2,
                    labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                    unselectedLabelStyle: const TextStyle(fontSize: 12),
                    tabs: [
                      Tab(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.warning_amber, size: 14),
                            const SizedBox(width: 6),
                            Text(tr('in_quarantine')),
                          ],
                        ),
                      ),
                      Tab(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.history, size: 14),
                            const SizedBox(width: 6),
                            Text(tr('history')),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                
                // Indicador de permisos
                if (!canWrite)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    margin: const EdgeInsets.only(right: 8),
                    decoration: BoxDecoration(
                      color: Colors.orange.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.visibility, size: 12, color: Colors.orange),
                        const SizedBox(width: 4),
                        Text(
                          tr('read_only'),
                          style: const TextStyle(fontSize: 10, color: Colors.orange),
                        ),
                      ],
                    ),
                  ),
                
                // Botón refrescar
                IconButton(
                  onPressed: _refreshCurrentTab,
                  icon: const Icon(Icons.refresh, size: 18, color: Colors.white54),
                  tooltip: tr('refresh'),
                ),
                const SizedBox(width: 8),
              ],
            ),
          ),
          
          // Contenido de tabs
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                // Tab 1: En Cuarentena
                QuarantinePendingGrid(
                  key: _pendingGridKey,
                  languageProvider: widget.languageProvider,
                ),
                
                // Tab 2: Historial
                QuarantineHistoryGrid(
                  key: _historyGridKey,
                  languageProvider: widget.languageProvider,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
