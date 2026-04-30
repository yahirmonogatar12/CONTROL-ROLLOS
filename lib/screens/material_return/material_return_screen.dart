import 'package:flutter/material.dart';
import 'package:material_warehousing_flutter/core/localization/app_translations.dart';
import 'package:material_warehousing_flutter/core/theme/app_colors.dart';
import 'return_form_panel.dart';
import 'return_search_bar_panel.dart';
import 'return_grid_panel.dart';

class MaterialReturnScreen extends StatefulWidget {
  final LanguageProvider languageProvider;
  
  const MaterialReturnScreen({super.key, required this.languageProvider});

  @override
  State<MaterialReturnScreen> createState() => MaterialReturnScreenState();
}

class MaterialReturnScreenState extends State<MaterialReturnScreen> {
  final GlobalKey<ReturnGridPanelState> _gridKey = GlobalKey();
  final GlobalKey<ReturnFormPanelState> _formKey = GlobalKey();
  
  /// Método público para solicitar focus en el campo de escaneo
  void requestScanFocus() {
    _formKey.currentState?.requestScanFocus();
  }
  
  void _onSearch(DateTime? fechaInicio, DateTime? fechaFin, String? texto) {
    _gridKey.currentState?.searchByDate(fechaInicio, fechaFin, texto: texto);
  }
  
  void _onDataSaved() {
    // Recargar la tabla cuando se guardan nuevos datos
    _gridKey.currentState?.reloadData();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Panel superior morado (solo formulario)
        Container(
          color: AppColors.subPanelBackground,
          child: ReturnFormPanel(
            key: _formKey,
            languageProvider: widget.languageProvider,
            onDataSaved: _onDataSaved,
            gridKey: _gridKey,
          ),
        ),
        // Barra de búsqueda con color diferente
        Container(
          color: AppColors.panelBackground,
          child: ReturnSearchBarPanel(
            languageProvider: widget.languageProvider,
            onSearch: _onSearch,
            gridKey: _gridKey,
          ),
        ),
        // Tabla de datos
        Expanded(child: ReturnGridPanel(
          key: _gridKey,
          languageProvider: widget.languageProvider,
        )),
      ],
    );
  }
}
