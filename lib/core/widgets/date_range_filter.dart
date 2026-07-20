import 'package:flutter/material.dart';
import 'package:material_warehousing_flutter/core/theme/app_colors.dart';

/// Filtro de rango de fechas reutilizable.
///
/// Diseno alineado con Material Entry (warehousing): contenedor con borde,
/// checkbox para habilitar/deshabilitar, etiqueta, dos cajas de fecha
/// formato dd/mm/yyyy separadas por '~'.
///
/// El widget es stateless — el padre es dueno del estado y recibe los
/// cambios via callbacks.
class DateRangeFilter extends StatelessWidget {
  final DateTime startDate;
  final DateTime endDate;
  final bool enabled;
  final String label;
  final ValueChanged<bool> onEnabledChanged;
  final ValueChanged<DateTime> onStartChanged;
  final ValueChanged<DateTime> onEndChanged;
  final DateTime? firstDate;
  final DateTime? lastDate;

  const DateRangeFilter({
    super.key,
    required this.startDate,
    required this.endDate,
    required this.enabled,
    required this.label,
    required this.onEnabledChanged,
    required this.onStartChanged,
    required this.onEndChanged,
    this.firstDate,
    this.lastDate,
  });

  String _fmt(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  Future<void> _pick(BuildContext context, bool isStart) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: isStart ? startDate : endDate,
      firstDate: firstDate ?? DateTime(2000),
      lastDate: lastDate ?? DateTime(2100),
    );
    if (picked != null) {
      if (isStart) {
        onStartChanged(picked);
      } else {
        onEndChanged(picked);
      }
    }
  }

  Widget _dateBox(BuildContext context, DateTime date, bool isStart) {
    return SizedBox(
      width: 132,
      child: InkWell(
        onTap: enabled ? () => _pick(context, isStart) : null,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: AppColors.fieldBackground,
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  _fmt(date),
                  maxLines: 1,
                  overflow: TextOverflow.visible,
                  softWrap: false,
                  style: const TextStyle(fontSize: 11),
                ),
              ),
              const SizedBox(width: 6),
              const Icon(Icons.calendar_today, size: 14, color: Colors.white70),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.border, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Checkbox(
            value: enabled,
            onChanged: (v) => onEnabledChanged(v ?? false),
            side: const BorderSide(color: AppColors.border),
          ),
          const SizedBox(width: 4),
          Text(label, style: const TextStyle(fontSize: 11)),
          const SizedBox(width: 4),
          _dateBox(context, startDate, true),
          const SizedBox(width: 4),
          const Text('~', style: TextStyle(fontSize: 12)),
          const SizedBox(width: 4),
          _dateBox(context, endDate, false),
        ],
      ),
    );
  }
}
