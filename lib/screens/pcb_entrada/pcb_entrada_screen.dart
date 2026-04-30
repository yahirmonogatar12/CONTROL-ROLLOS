import 'package:flutter/material.dart';
import 'package:material_warehousing_flutter/core/localization/app_translations.dart';
import 'package:material_warehousing_flutter/core/theme/app_colors.dart';
import 'pcb_entrada_form_panel.dart';
import 'pcb_entrada_search_bar_panel.dart';
import 'pcb_entrada_grid_panel.dart';

class PcbEntradaScreen extends StatefulWidget {
  final LanguageProvider languageProvider;

  const PcbEntradaScreen({super.key, required this.languageProvider});

  @override
  State<PcbEntradaScreen> createState() => PcbEntradaScreenState();
}

class PcbEntradaScreenState extends State<PcbEntradaScreen> {
  final GlobalKey<PcbEntradaGridPanelState> _gridKey = GlobalKey();
  final GlobalKey<PcbEntradaFormPanelState> _formKey = GlobalKey();

  String tr(String key) => widget.languageProvider.tr(key);

  void requestScanFocus() {
    _formKey.currentState?.requestScanFocus();
  }

  void _onDataSaved() {
    _gridKey.currentState?.reloadData();
  }

  void _onSearch(DateTime? fechaInicio, DateTime? fechaFin, String? partNumber) {
    _gridKey.currentState?.searchByDate(fechaInicio, fechaFin, partNumber: partNumber);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Panel de escaneo
        PcbEntradaFormPanel(
          key: _formKey,
          languageProvider: widget.languageProvider,
          onDataSaved: _onDataSaved,
        ),
        // Barra de busqueda
        PcbEntradaSearchBarPanel(
          languageProvider: widget.languageProvider,
          onSearch: _onSearch,
          gridKey: _gridKey,
        ),
        // Grid de entradas
        Expanded(
          child: PcbEntradaGridPanel(
            key: _gridKey,
            languageProvider: widget.languageProvider,
          ),
        ),
      ],
    );
  }
}
