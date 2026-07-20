import 'package:flutter/material.dart';
import 'package:material_warehousing_flutter/core/localization/app_translations.dart';
import 'package:material_warehousing_flutter/core/theme/app_colors.dart';
import 'package:material_warehousing_flutter/core/services/excel_export_service.dart';
import 'package:material_warehousing_flutter/core/widgets/date_range_filter.dart';
import 'scrap_grid_panel.dart';

class ScrapSearchBarPanel extends StatefulWidget {
  final LanguageProvider languageProvider;
  final void Function(DateTime?, DateTime?, String?) onSearch;
  final GlobalKey<ScrapGridPanelState> gridKey;

  const ScrapSearchBarPanel({
    super.key,
    required this.languageProvider,
    required this.onSearch,
    required this.gridKey,
  });

  @override
  State<ScrapSearchBarPanel> createState() => _ScrapSearchBarPanelState();
}

class _ScrapSearchBarPanelState extends State<ScrapSearchBarPanel> {
  bool _useDateFilter = true;
  DateTime _startDate = DateTime.now();
  DateTime _endDate = DateTime.now();
  String? _selectedArea;

  static const List<String> _areas = [
    'M1',
    'M2',
    'M3',
    'M4',
    'D1',
    'D2',
    'D3',
    'CALIDAD',
    'MANTENIMIENTO',
    'SMD',
    'IMD',
    'IPM',
    'COATING',
    'PROVEEDOR',
    'COMPONENTE'
  ];

  String tr(String key) => widget.languageProvider.tr(key);

  void _doSearch() {
    widget.onSearch(
      _useDateFilter ? _startDate : null,
      _useDateFilter ? _endDate : null,
      _selectedArea,
    );
  }

  Future<void> _exportExcel() async {
    final data = widget.gridKey.currentState?.getDataForExport() ?? [];
    if (data.isEmpty) return;

    final headers = [
      tr('scrap_scanned_code'),
      tr('scrap_raw_barcode'),
      tr('scrap_part_no'),
      tr('scrap_modelo'),
      tr('scrap_area'),
      tr('scrap_proceso'),
      tr('scrap_motivo'),
      tr('scrap_comentarios'),
      'Cantidad',
      tr('scrap_registered_by'),
      tr('scrap_date'),
      tr('scrap_time'),
    ];
    final fields = [
      'scanned_original',
      'raw_barcode',
      'part_no',
      'modelo',
      'area',
      'proceso',
      'motivo_scrap_texto',
      'comentarios',
      'cantidad',
      'usuario_registro',
      'fecha',
      'hora',
    ];

    await ExcelExportService.exportToExcel(
      data: data,
      headers: headers,
      fieldMapping: fields,
      fileName: 'Scrap_Records',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.panelBackground,
        border: Border(bottom: BorderSide(color: AppColors.border, width: 1)),
      ),
      child: Row(
        children: [
          DateRangeFilter(
            startDate: _startDate,
            endDate: _endDate,
            enabled: _useDateFilter,
            label: tr('scrap_date_range'),
            onEnabledChanged: (v) => setState(() => _useDateFilter = v),
            onStartChanged: (d) => setState(() => _startDate = d),
            onEndChanged: (d) => setState(() => _endDate = d),
          ),
          const SizedBox(width: 12),
          // Area filter
          SizedBox(
            width: 150,
            height: 32,
            child: DropdownButtonFormField<String>(
              value: _selectedArea,
              isDense: true,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: tr('scrap_area'),
                labelStyle:
                    const TextStyle(color: Colors.white54, fontSize: 11),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(4),
                    borderSide: BorderSide(color: AppColors.border)),
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(4),
                    borderSide: BorderSide(color: AppColors.border)),
              ),
              dropdownColor: AppColors.panelBackground,
              style: const TextStyle(color: Colors.white, fontSize: 12),
              items: [
                DropdownMenuItem<String>(
                  value: null,
                  child: Text(tr('scrap_all'),
                      style: const TextStyle(fontSize: 12)),
                ),
                ..._areas.map((a) => DropdownMenuItem(
                    value: a,
                    child: Text(a, style: const TextStyle(fontSize: 12)))),
              ],
              onChanged: (val) => setState(() => _selectedArea = val),
            ),
          ),
          const SizedBox(width: 8),
          // Buscar
          SizedBox(
            height: 32,
            child: ElevatedButton.icon(
              onPressed: _doSearch,
              icon: const Icon(Icons.search, size: 14),
              label: Text(tr('scrap_search'),
                  style: const TextStyle(fontSize: 12)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 12),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Excel export
          SizedBox(
            height: 32,
            child: OutlinedButton.icon(
              onPressed: _exportExcel,
              icon: const Icon(Icons.download, size: 14, color: Colors.green),
              label: Text('Excel',
                  style: const TextStyle(fontSize: 12, color: Colors.green)),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Colors.green),
                padding: const EdgeInsets.symmetric(horizontal: 12),
              ),
            ),
          ),
          const Spacer(),
        ],
      ),
    );
  }
}
