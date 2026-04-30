import 'package:flutter/material.dart';
import 'package:material_warehousing_flutter/core/localization/app_translations.dart';
import 'package:material_warehousing_flutter/core/theme/app_colors.dart';
import 'package:material_warehousing_flutter/core/services/auth_service.dart';
import 'package:material_warehousing_flutter/screens/quality_specs/quality_specs_screen.dart';
import 'iqc_pending_grid.dart';
import 'iqc_history_grid.dart';

// ============================================
// IQC Tab Section - Pending / History / Specs tabs
// ============================================
class IqcTabSection extends StatelessWidget {
  final LanguageProvider languageProvider;
  final Function(Map<String, dynamic>)? onLotSelected;
  final GlobalKey<IqcPendingGridState>? pendingGridKey;
  final GlobalKey<IqcHistoryGridState>? historyGridKey;
  
  // Departamentos que pueden ver Quality Specs
  static const _qualitySpecsDepartments = ['Calidad', 'Calidad Supervisor', 'Admin', 'Sistemas'];
  
  const IqcTabSection({
    super.key, 
    required this.languageProvider,
    this.onLotSelected,
    this.pendingGridKey,
    this.historyGridKey,
  });
  
  bool get _canSeeQualitySpecs {
    final dept = AuthService.currentUser?.departamento ?? '';
    return _qualitySpecsDepartments.contains(dept);
  }

  @override
  Widget build(BuildContext context) {
    final tr = languageProvider.tr;
    final showQualitySpecs = _canSeeQualitySpecs;
    
    return DefaultTabController(
      length: showQualitySpecs ? 3 : 2,
      animationDuration: const Duration(milliseconds: 700),
      child: Container(
        color: AppColors.panelBackground,
        child: Column(
          children: [
            Container(
              color: AppColors.gridHeader,
              child: Row(
                children: [
                  SizedBox(
                    width: showQualitySpecs ? 330 : 220,
                    child: TabBar(
                      labelStyle: const TextStyle(fontSize: 11),
                      unselectedLabelColor: Colors.white70,
                      labelColor: Colors.white,
                      indicatorColor: Colors.cyan,
                      labelPadding: const EdgeInsets.symmetric(horizontal: 4),
                      tabs: [
                        Tab(
                          height: 32,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.pending_actions, size: 12),
                              const SizedBox(width: 3),
                              Flexible(child: Text(tr('pending'), overflow: TextOverflow.ellipsis)),
                            ],
                          ),
                        ),
                        Tab(
                          height: 32,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.history, size: 12),
                              const SizedBox(width: 3),
                              Flexible(child: Text(tr('history'), overflow: TextOverflow.ellipsis)),
                            ],
                          ),
                        ),
                        if (showQualitySpecs)
                          Tab(
                            height: 32,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.rule, size: 12),
                                const SizedBox(width: 3),
                                Flexible(child: Text(tr('quality_specs'), overflow: TextOverflow.ellipsis)),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                  const Spacer(),
                ],
              ),
            ),
            Expanded(
              child: TabBarView(
                children: [
                  // Tab Pending - Grid de lotes pendientes
                  IqcPendingGrid(
                    key: pendingGridKey,
                    languageProvider: languageProvider,
                    onLotSelected: onLotSelected,
                  ),
                  // Tab History - Grid con filtros avanzados
                  IqcHistoryGrid(
                    key: historyGridKey,
                    languageProvider: languageProvider,
                  ),
                  // Tab Quality Specs - Solo para Calidad
                  if (showQualitySpecs)
                    QualitySpecsScreen(
                      languageProvider: languageProvider,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
