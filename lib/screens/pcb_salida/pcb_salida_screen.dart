import 'package:flutter/material.dart';
import 'package:material_warehousing_flutter/core/localization/app_translations.dart';
import 'pcb_salida_form_panel.dart';
import 'pcb_salida_search_bar_panel.dart';
import 'pcb_salida_grid_panel.dart';

class PcbSalidaScreen extends StatefulWidget {
  final LanguageProvider languageProvider;

  const PcbSalidaScreen({super.key, required this.languageProvider});

  @override
  State<PcbSalidaScreen> createState() => PcbSalidaScreenState();
}

class PcbSalidaScreenState extends State<PcbSalidaScreen> {
  final GlobalKey<PcbSalidaGridPanelState> _gridKey = GlobalKey();
  final GlobalKey<PcbSalidaFormPanelState> _formKey = GlobalKey();

  String tr(String key) => widget.languageProvider.tr(key);

  void requestScanFocus() {
    _formKey.currentState?.requestScanFocus();
  }

  void _onDataSaved() {
    _gridKey.currentState?.reloadData();
  }

  void _onSearch(DateTime? fechaInicio, DateTime? fechaFin, String? partNumber, String? tipoFilter) {
    _gridKey.currentState?.searchByDate(fechaInicio, fechaFin, partNumber: partNumber, tipoFilter: tipoFilter);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        PcbSalidaFormPanel(
          key: _formKey,
          languageProvider: widget.languageProvider,
          onDataSaved: _onDataSaved,
        ),
        PcbSalidaSearchBarPanel(
          languageProvider: widget.languageProvider,
          onSearch: _onSearch,
          gridKey: _gridKey,
        ),
        Expanded(
          child: PcbSalidaGridPanel(
            key: _gridKey,
            languageProvider: widget.languageProvider,
          ),
        ),
      ],
    );
  }
}
