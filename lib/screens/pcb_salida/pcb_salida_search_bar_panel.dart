import 'package:flutter/material.dart';
import 'package:material_warehousing_flutter/core/localization/app_translations.dart';
import 'package:material_warehousing_flutter/core/theme/app_colors.dart';
import 'package:material_warehousing_flutter/core/services/excel_export_service.dart';
import 'pcb_salida_grid_panel.dart';

class PcbSalidaSearchBarPanel extends StatefulWidget {
  final LanguageProvider languageProvider;
  final void Function(DateTime?, DateTime?, String?, String?) onSearch;
  final GlobalKey<PcbSalidaGridPanelState> gridKey;

  const PcbSalidaSearchBarPanel({
    super.key,
    required this.languageProvider,
    required this.onSearch,
    required this.gridKey,
  });

  @override
  State<PcbSalidaSearchBarPanel> createState() =>
      _PcbSalidaSearchBarPanelState();
}

class _PcbSalidaSearchBarPanelState extends State<PcbSalidaSearchBarPanel> {
  final TextEditingController _startDateCtrl = TextEditingController();
  final TextEditingController _endDateCtrl = TextEditingController();
  final TextEditingController _partNumberCtrl = TextEditingController();
  bool _useDateFilter = false;
  DateTime? _startDate;
  DateTime? _endDate;
  String _tipoFilter = 'ALL'; // ALL, SALIDA, SCRAP

  String tr(String key) => widget.languageProvider.tr(key);

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _startDate = now;
    _endDate = now;
    _startDateCtrl.text = _fmt(now);
    _endDateCtrl.text = _fmt(now);
  }

  @override
  void dispose() {
    _startDateCtrl.dispose();
    _endDateCtrl.dispose();
    _partNumberCtrl.dispose();
    super.dispose();
  }

  String _fmt(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _pickDate(bool isStart) async {
    final initial =
        isStart ? (_startDate ?? DateTime.now()) : (_endDate ?? DateTime.now());
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2024),
      lastDate: DateTime(2030),
    );
    if (picked != null && mounted) {
      setState(() {
        if (isStart) {
          _startDate = picked;
          _startDateCtrl.text = _fmt(picked);
        } else {
          _endDate = picked;
          _endDateCtrl.text = _fmt(picked);
        }
      });
    }
  }

  void _doSearch() {
    widget.onSearch(
      _useDateFilter ? _startDate : null,
      _useDateFilter ? _endDate : null,
      _partNumberCtrl.text.trim().isNotEmpty
          ? _partNumberCtrl.text.trim()
          : null,
      _tipoFilter == 'ALL' ? null : _tipoFilter,
    );
  }

  Future<void> _exportExcel() async {
    final data = widget.gridKey.currentState?.getDataForExport() ?? [];
    if (data.isEmpty) return;

    final headers = [
      tr('pcb_tipo_movimiento'),
      tr('pcb_scanned_code'),
      tr('pcb_area'),
      tr('pcb_part_no'),
      tr('pcb_modelo'),
      tr('pcb_proceso'),
      tr('pcb_date'),
      tr('pcb_hora'),
      tr('pcb_comentarios'),
      tr('pcb_scanned_by'),
    ];
    final fields = [
      'tipo_movimiento',
      'scanned_original',
      'area',
      'pcb_part_no',
      'modelo',
      'proceso',
      'inventory_date',
      'hora',
      'comentarios',
      'scanned_by',
    ];

    await ExcelExportService.exportToExcel(
      data: data,
      headers: headers,
      fieldMapping: fields,
      fileName: 'PCB_Salidas',
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
          // Checkbox rango fecha
          SizedBox(
            width: 20,
            height: 20,
            child: Checkbox(
              value: _useDateFilter,
              onChanged: (v) => setState(() => _useDateFilter = v ?? false),
              side: const BorderSide(color: AppColors.border),
              activeColor: Colors.blue,
            ),
          ),
          const SizedBox(width: 6),
          Text(tr('pcb_date_range'),
              style: const TextStyle(color: Colors.white54, fontSize: 12)),
          const SizedBox(width: 6),
          SizedBox(
            width: 110,
            height: 32,
            child: TextField(
              controller: _startDateCtrl,
              readOnly: true,
              enabled: _useDateFilter,
              onTap: () => _pickDate(true),
              style: const TextStyle(color: Colors.white, fontSize: 12),
              decoration: InputDecoration(
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(4),
                    borderSide: BorderSide(color: AppColors.border)),
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(4),
                    borderSide: BorderSide(color: AppColors.border)),
                disabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(4),
                    borderSide:
                        BorderSide(color: AppColors.border.withOpacity(0.3))),
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 4),
            child: Text('-', style: TextStyle(color: Colors.white54)),
          ),
          SizedBox(
            width: 110,
            height: 32,
            child: TextField(
              controller: _endDateCtrl,
              readOnly: true,
              enabled: _useDateFilter,
              onTap: () => _pickDate(false),
              style: const TextStyle(color: Colors.white, fontSize: 12),
              decoration: InputDecoration(
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(4),
                    borderSide: BorderSide(color: AppColors.border)),
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(4),
                    borderSide: BorderSide(color: AppColors.border)),
                disabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(4),
                    borderSide:
                        BorderSide(color: AppColors.border.withOpacity(0.3))),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Tipo filter: ALL / SALIDA / SCRAP
          SizedBox(
            width: 120,
            height: 32,
            child: DropdownButtonFormField<String>(
              value: _tipoFilter,
              isDense: true,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: tr('pcb_tipo_movimiento'),
                labelStyle:
                    const TextStyle(color: Colors.white54, fontSize: 10),
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
                DropdownMenuItem(value: 'ALL', child: Text(tr('pcb_all'))),
                DropdownMenuItem(
                    value: 'SALIDA', child: Text(tr('pcb_tab_salida'))),
                DropdownMenuItem(
                    value: 'SCRAP', child: Text(tr('pcb_tab_scrap'))),
              ],
              onChanged: (v) {
                if (v != null) setState(() => _tipoFilter = v);
              },
            ),
          ),
          const SizedBox(width: 8),
          // Part number
          SizedBox(
            width: 140,
            height: 32,
            child: TextField(
              controller: _partNumberCtrl,
              style: const TextStyle(color: Colors.white, fontSize: 12),
              decoration: InputDecoration(
                labelText: tr('pcb_search_part'),
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
              onSubmitted: (_) => _doSearch(),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            height: 32,
            child: ElevatedButton.icon(
              onPressed: _doSearch,
              icon: const Icon(Icons.search, size: 14),
              label:
                  Text(tr('pcb_search'), style: const TextStyle(fontSize: 12)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 12),
              ),
            ),
          ),
          const SizedBox(width: 8),
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
