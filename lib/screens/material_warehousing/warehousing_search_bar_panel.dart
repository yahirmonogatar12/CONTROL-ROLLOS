import 'package:flutter/material.dart';
import 'package:material_warehousing_flutter/core/localization/app_translations.dart';
import 'package:material_warehousing_flutter/core/theme/app_colors.dart';
import 'package:material_warehousing_flutter/core/services/excel_export_service.dart';
import 'warehousing_grid_panel.dart';

class WarehousingSearchBarPanel extends StatefulWidget {
  final LanguageProvider languageProvider;
  final void Function(DateTime?, DateTime?, String?)? onSearch;
  final GlobalKey<WarehousingGridPanelState>? gridKey; // Referencia al grid
  
  const WarehousingSearchBarPanel({
    super.key, 
    required this.languageProvider,
    this.onSearch,
    this.gridKey,
  });

  @override
  State<WarehousingSearchBarPanel> createState() => _WarehousingSearchBarPanelState();
}

class _WarehousingSearchBarPanelState extends State<WarehousingSearchBarPanel> {
  DateTime _fechaInicio = DateTime.now();
  DateTime _fechaFin = DateTime.now();
  bool _filterEnabled = true;
  
  final TextEditingController _fechaInicioController = TextEditingController();
  final TextEditingController _fechaFinController = TextEditingController();
  final TextEditingController _lotNoController = TextEditingController();
  
  String tr(String key) => widget.languageProvider.tr(key);

  @override
  void initState() {
    super.initState();
    _updateDateControllers();
  }
  
  void _updateDateControllers() {
    _fechaInicioController.text = _formatDate(_fechaInicio);
    _fechaFinController.text = _formatDate(_fechaFin);
  }
  
  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }

  Future<void> _selectFechaInicio() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _fechaInicio,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() {
        _fechaInicio = picked;
        _fechaInicioController.text = _formatDate(picked);
      });
    }
  }
  
  Future<void> _selectFechaFin() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _fechaFin,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() {
        _fechaFin = picked;
        _fechaFinController.text = _formatDate(picked);
      });
    }
  }
  
  void _onSearchPressed() {
    final texto = _lotNoController.text.isNotEmpty ? _lotNoController.text : null;
    if (_filterEnabled) {
      widget.onSearch?.call(_fechaInicio, _fechaFin, texto);
    } else {
      widget.onSearch?.call(null, null, texto);
    }
  }
  
  Future<void> _onExcelExport() async {
    final gridState = widget.gridKey?.currentState;
    if (gridState == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No hay datos para exportar'), backgroundColor: Colors.red),
      );
      return;
    }
    
    final data = gridState.getDataForExport();
    if (data.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No hay datos para exportar'), backgroundColor: Colors.orange),
      );
      return;
    }
    
    // Headers y mapeo de campos
    final headers = [
      tr('material_warehousing_code'),
      tr('material_code'),
      tr('part_number'),
      tr('material_property'),
      tr('current_qty'),
      tr('packaging_unit'),
      tr('location'),
      tr('warehousing_date'),
      'Hora',
      tr('material_spec'),
      tr('material_consigned'),
      tr('disposal'),
      'Cancelled',
    ];
    
    final fieldMapping = [
      'codigo_material_recibido',
      'codigo_material',
      'numero_parte',
      'propiedad_material',
      'cantidad_actual',
      'cantidad_estandarizada',
      'location',
      'fecha_recibo',
      'fecha_recibo_hora',
      'especificacion',
      'material_importacion_local',
      'estado_desecho',
      'cancelado',
    ];
    
    // Mostrar indicador de carga
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Row(
          children: [
            SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
            SizedBox(width: 12),
            Text('Exportando a Excel...'),
          ],
        ),
        duration: Duration(seconds: 2),
      ),
    );
    
    final success = await ExcelExportService.exportToExcel(
      data: data,
      headers: headers,
      fieldMapping: fieldMapping,
      fileName: 'Material_Warehousing',
    );
    
    if (mounted) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success 
            ? '✓ Excel exportado correctamente' 
            : 'Exportación cancelada'),
          backgroundColor: success ? Colors.green : Colors.grey,
        ),
      );
    }
  }

  InputDecoration _dateDecoration() {
    return const InputDecoration(
      isDense: true,
      contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      filled: true,
      fillColor: AppColors.fieldBackground,
      border: OutlineInputBorder(
        borderSide: BorderSide(color: AppColors.border, width: 1),
      ),
      enabledBorder: OutlineInputBorder(
        borderSide: BorderSide(color: AppColors.border, width: 1),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.panelBackground,
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 4),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.border, width: 1),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Checkbox(
                  value: _filterEnabled,
                  onChanged: (v) => setState(() => _filterEnabled = v ?? true),
                  side: const BorderSide(color: AppColors.border),
                ),
                const SizedBox(width: 4),
                Text(
                  tr('warehousing_date'),
                  style: const TextStyle(fontSize: 11),
                ),
                const SizedBox(width: 4),
                // Fecha inicio
                SizedBox(
                  width: 100,
                  child: InkWell(
                    onTap: _selectFechaInicio,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppColors.fieldBackground,
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(_formatDate(_fechaInicio), style: const TextStyle(fontSize: 11)),
                          const Icon(Icons.calendar_today, size: 14, color: Colors.white70),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                const Text('~', style: TextStyle(fontSize: 12)),
                const SizedBox(width: 4),
                // Fecha fin
                SizedBox(
                  width: 100,
                  child: InkWell(
                    onTap: _selectFechaFin,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppColors.fieldBackground,
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(_formatDate(_fechaFin), style: const TextStyle(fontSize: 11)),
                          const Icon(Icons.calendar_today, size: 14, color: Colors.white70),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(tr('lot_no'), style: const TextStyle(fontSize: 11)),
                const SizedBox(width: 4),
                SizedBox(
                  width: 110,
                  child: TextFormField(
                    controller: _lotNoController,
                    decoration: _dateDecoration(),
                    style: const TextStyle(fontSize: 11),
                    onFieldSubmitted: (_) => _onSearchPressed(),
                  ),
                ),
              ],
            ),
          ),
          const Spacer(),
          SizedBox(
            height: 26,
            child: ElevatedButton(
              onPressed: _onSearchPressed,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                backgroundColor: AppColors.buttonSearch,
              ),
              child: Text(tr('search'), style: const TextStyle(fontSize: 11)),
            ),
          ),
          const SizedBox(width: 6),
          SizedBox(
            height: 26,
            child: ElevatedButton(
              onPressed: _onExcelExport,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                backgroundColor: AppColors.buttonExcel,
              ),
              child: Text(tr('excel_export'), style: const TextStyle(fontSize: 11)),
            ),
          ),
        ],
      ),
    );
  }
}
