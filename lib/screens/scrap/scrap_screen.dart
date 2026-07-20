import 'package:flutter/material.dart';
import 'package:material_warehousing_flutter/core/localization/app_translations.dart';
import 'package:material_warehousing_flutter/core/services/auth_service.dart';
import 'scrap_form_panel.dart';
import 'scrap_search_bar_panel.dart';
import 'scrap_grid_panel.dart';
import 'scrap_edit_panel.dart';

class ScrapScreen extends StatefulWidget {
  final LanguageProvider languageProvider;

  const ScrapScreen({super.key, required this.languageProvider});

  @override
  State<ScrapScreen> createState() => ScrapScreenState();
}

class ScrapScreenState extends State<ScrapScreen>
    with SingleTickerProviderStateMixin {
  final GlobalKey<ScrapGridPanelState> _gridKey = GlobalKey();
  final GlobalKey<ScrapFormPanelState> _formKey = GlobalKey();
  Map<String, dynamic>? _editingRow;

  late final AnimationController _animationController;
  late final Animation<Offset> _slideAnimation;

  String tr(String key) => widget.languageProvider.tr(key);

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(1.0, 0.0),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOutCubic,
    ));
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  void requestScanFocus() {
    _formKey.currentState?.reloadMotivos();
    _formKey.currentState?.requestScanFocus();
  }

  void _onDataSaved() {
    _gridKey.currentState?.reloadData();
  }

  void _onSearch(DateTime? fechaInicio, DateTime? fechaFin, String? area) {
    _gridKey.currentState?.searchByDate(fechaInicio, fechaFin, area: area);
  }

  void _onRowDoubleClick(Map<String, dynamic> rowData) {
    if (!AuthService.canEditScrapHistory) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(tr('scrap_no_edit_permission')),
          backgroundColor: Colors.red.shade700,
        ),
      );
      return;
    }

    setState(() => _editingRow = rowData);
    _animationController.forward(from: 0.0);
  }

  void _closeEditPanel() async {
    await _animationController.reverse();
    if (mounted) {
      setState(() => _editingRow = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            children: [
              ScrapFormPanel(
                key: _formKey,
                languageProvider: widget.languageProvider,
                onDataSaved: _onDataSaved,
              ),
              ScrapSearchBarPanel(
                languageProvider: widget.languageProvider,
                onSearch: _onSearch,
                gridKey: _gridKey,
              ),
              Expanded(
                child: ScrapGridPanel(
                  key: _gridKey,
                  languageProvider: widget.languageProvider,
                  onRowDoubleClick: _onRowDoubleClick,
                ),
              ),
            ],
          ),
        ),
        if (_editingRow != null)
          SlideTransition(
            position: _slideAnimation,
            child: ScrapEditPanel(
              key: ValueKey(_editingRow!['id']),
              languageProvider: widget.languageProvider,
              rowData: _editingRow!,
              onClose: _closeEditPanel,
              onSaved: _onDataSaved,
            ),
          ),
      ],
    );
  }
}
