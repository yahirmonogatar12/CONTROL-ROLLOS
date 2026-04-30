import 'package:flutter/material.dart';
import 'package:material_warehousing_flutter/core/localization/app_translations.dart';
import 'package:material_warehousing_flutter/core/theme/app_colors.dart';
import 'return_grid_panel.dart';

class ReturnSearchBarPanel extends StatefulWidget {
  final LanguageProvider languageProvider;
  final Function(DateTime?, DateTime?, String?)? onSearch;
  final GlobalKey<ReturnGridPanelState>? gridKey;

  const ReturnSearchBarPanel({
    super.key,
    required this.languageProvider,
    this.onSearch,
    this.gridKey,
  });

  @override
  State<ReturnSearchBarPanel> createState() => _ReturnSearchBarPanelState();
}

class _ReturnSearchBarPanelState extends State<ReturnSearchBarPanel> {
  DateTime _fechaInicio = DateTime.now();
  DateTime _fechaFin = DateTime.now();
  bool _filterEnabled = true;
  final TextEditingController _lotNoController = TextEditingController();

  String tr(String key) => widget.languageProvider.tr(key);

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }

  Future<void> _selectFechaInicio() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _fechaInicio,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() => _fechaInicio = picked);
    }
  }

  Future<void> _selectFechaFin() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _fechaFin,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() => _fechaFin = picked);
    }
  }

  void _search() {
    final texto = _lotNoController.text.isNotEmpty ? _lotNoController.text : null;
    if (_filterEnabled) {
      widget.onSearch?.call(_fechaInicio, _fechaFin, texto);
    } else {
      widget.onSearch?.call(null, null, texto);
    }
  }

  Future<void> _exportToExcel() async {
    await widget.gridKey?.currentState?.exportToExcel();
  }

  void _reprint() {
    widget.gridKey?.currentState?.reprintSelected();
  }

  @override
  void dispose() {
    _lotNoController.dispose();
    super.dispose();
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
                Text(tr('warehousing_date'), style: const TextStyle(fontSize: 11)),
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
                    onFieldSubmitted: (_) => _search(),
                  ),
                ),
              ],
            ),
          ),
          const Spacer(),
          SizedBox(
            height: 26,
            child: ElevatedButton(
              onPressed: _search,
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
              onPressed: _exportToExcel,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                backgroundColor: AppColors.buttonExcel,
              ),
              child: Text(tr('excel_export'), style: const TextStyle(fontSize: 11)),
            ),
          ),
          const SizedBox(width: 6),
          SizedBox(
            height: 26,
            child: ElevatedButton(
              onPressed: _reprint,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                backgroundColor: AppColors.buttonSearch,
              ),
              child: Text(tr('reprint'), style: const TextStyle(fontSize: 11)),
            ),
          ),
        ],
      ),
    );
  }
}
