import 'package:flutter/material.dart';
import 'package:material_warehousing_flutter/core/constants/pcb_areas.dart';
import 'package:material_warehousing_flutter/core/services/api_service.dart';
import 'package:material_warehousing_flutter/core/theme/app_colors.dart';
import 'package:material_warehousing_flutter/core/widgets/field_decoration.dart';

/// Consulta el historial completo de una PCB escaneando su QR (;) o barcode EBR.
class PcbHistoryDialog extends StatefulWidget {
  final String Function(String) tr;

  const PcbHistoryDialog({super.key, required this.tr});

  @override
  State<PcbHistoryDialog> createState() => _PcbHistoryDialogState();
}

class _PcbHistoryDialogState extends State<PcbHistoryDialog> {
  final TextEditingController _scanController = TextEditingController();
  final FocusNode _scanFocusNode = FocusNode();
  bool _isLoading = false;
  String? _error;
  Map<String, dynamic>? _data;

  String tr(String key) => widget.tr(key);

  @override
  void dispose() {
    _scanController.dispose();
    _scanFocusNode.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final code = _scanController.text.trim();
    if (code.isEmpty || _isLoading) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });

    final result = await ApiService.getPcbHistory(code);
    if (!mounted) return;
    final data = result['data'];
    setState(() {
      _isLoading = false;
      if (result['success'] == true && data is Map) {
        final movements = data['movements'];
        if (movements is List && movements.isNotEmpty) {
          _data = Map<String, dynamic>.from(data);
        } else {
          _data = null;
          _error = '${tr('pcb_history_not_found')}: $code';
        }
      } else {
        _data = null;
        _error = result['code'] == 'INVALID_PCB_PART_NO'
            ? tr('pcb_invalid_part_no')
            : (result['message']?.toString() ?? tr('pcb_history_not_found'));
      }
    });
    _scanController.clear();
    _scanFocusNode.requestFocus();
  }

  String _tipoLabel(Object? tipo) {
    switch (tipo?.toString()) {
      case 'ENTRADA':
        return tr('pcb_history_entry');
      case 'SALIDA':
        return tr('pcb_history_exit');
      case 'SCRAP':
        return tr('pcb_history_scrap');
      default:
        return tipo?.toString() ?? '';
    }
  }

  Color _tipoColor(Object? tipo) {
    switch (tipo?.toString()) {
      case 'ENTRADA':
        return Colors.greenAccent;
      case 'SALIDA':
        return Colors.lightBlueAccent;
      case 'SCRAP':
        return Colors.redAccent;
      default:
        return Colors.white54;
    }
  }

  (String, Color)? _repairStatus(Object? status) {
    switch (status?.toString()) {
      case 'REPAIRED':
        return (tr('pcb_history_status_repaired'), Colors.greenAccent);
      case 'SCRAPPED':
        return (tr('pcb_history_status_scrapped'), Colors.redAccent);
      case 'PENDING':
        return (tr('pcb_history_status_pending'), Colors.orangeAccent);
      default:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.panelBackground,
      child: SizedBox(
        width: 960,
        height: 680,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.history, color: Colors.cyan, size: 22),
                  const SizedBox(width: 8),
                  Text(tr('pcb_history_title'),
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600)),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, color: Colors.white70),
                    tooltip: tr('close'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _scanController,
                focusNode: _scanFocusNode,
                autofocus: true,
                style: const TextStyle(
                    fontSize: 14,
                    color: Colors.cyan,
                    fontWeight: FontWeight.w600),
                decoration: fieldDecoration().copyWith(
                  hintText: tr('pcb_history_scan_hint'),
                  hintStyle:
                      const TextStyle(fontSize: 12, color: Colors.white38),
                  prefixIcon: const Icon(Icons.qr_code_scanner,
                      color: Colors.cyan, size: 18),
                  suffixIcon: _isLoading
                      ? const Padding(
                          padding: EdgeInsets.all(8),
                          child: SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2)),
                        )
                      : IconButton(
                          onPressed: _search,
                          icon: const Icon(Icons.search,
                              color: Colors.white70, size: 18),
                        ),
                ),
                onSubmitted: (_) => _search(),
              ),
              const SizedBox(height: 12),
              if (_error != null)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                    border:
                        Border.all(color: Colors.red.withValues(alpha: 0.3)),
                  ),
                  child: Text(_error!,
                      style: const TextStyle(
                          color: Colors.redAccent, fontSize: 13)),
                ),
              if (_data != null)
                Expanded(child: SelectionArea(child: _buildHistory(_data!))),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHistory(Map<String, dynamic> data) {
    final summary = Map<String, dynamic>.from(data['summary'] as Map? ?? {});
    final last = summary['last_movement'] as Map?;
    // Mas reciente primero.
    final movements = (data['movements'] as List? ?? const [])
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList()
        .reversed
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${data['scanned_code'] ?? ''}',
          style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w600,
              fontFamily: 'Consolas'),
        ),
        const SizedBox(height: 4),
        Text(
          '${data['pcb_part_no'] ?? ''}  |  ${data['modelo'] ?? 'N/A'}',
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _stat(tr('pcb_total_entrada'), summary['total_entradas'],
                Colors.greenAccent),
            _stat(tr('pcb_total_salida'), summary['total_salidas'],
                Colors.lightBlueAccent),
            _stat(tr('pcb_total_scrap'), summary['total_scrap'],
                Colors.redAccent),
            _stat(tr('pcb_history_repairs'), summary['repair_cycles'],
                Colors.orangeAccent),
            _stat(tr('pcb_history_defects'), summary['total_defects'],
                Colors.amber),
            if (last != null)
              _stat(
                tr('pcb_history_current'),
                '${_tipoLabel(last['tipo_movimiento'])} · ${PcbAreas.label(last['area'])}',
                _tipoColor(last['tipo_movimiento']),
              ),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(
          child: ListView.separated(
            itemCount: movements.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (_, index) => _movementCard(movements[index]),
          ),
        ),
      ],
    );
  }

  Widget _stat(String label, Object? value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text('$label: ${value ?? 0}',
          style: TextStyle(
              color: color, fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }

  Widget _movementCard(Map<String, dynamic> movement) {
    final tipo = movement['tipo_movimiento'];
    final color = _tipoColor(tipo);
    final defects =
        (movement['defects'] as List? ?? const []).whereType<Map>().toList();
    final arrayCount = int.tryParse('${movement['array_count'] ?? 1}') ?? 1;
    final comentarios = movement['comentarios']?.toString() ?? '';
    final details = <String>[
      '${tr('pcb_proceso')}: ${movement['proceso'] ?? ''}',
      '${tr('pcb_scanned_by')}: ${movement['scanned_by'] ?? '-'}',
      if (arrayCount > 1)
        '${tr('pcb_array_count')}: $arrayCount (${movement['array_role'] ?? ''})',
      if (comentarios.isNotEmpty) '${tr('pcb_comentarios')}: $comentarios',
    ];

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.gridBackground,
        borderRadius: BorderRadius.circular(6),
        border: Border(left: BorderSide(color: color, width: 3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Text(_tipoLabel(tipo),
                    style: TextStyle(
                        color: color,
                        fontSize: 11,
                        fontWeight: FontWeight.w700)),
              ),
              const SizedBox(width: 10),
              Text(PcbAreas.label(movement['area']),
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600)),
              const Spacer(),
              Text('${movement['created_at'] ?? ''}',
                  style: const TextStyle(color: Colors.white70, fontSize: 12)),
            ],
          ),
          const SizedBox(height: 4),
          Text(details.join('  |  '),
              style: const TextStyle(color: Colors.white60, fontSize: 11)),
          for (final defect in defects) ...[
            const SizedBox(height: 6),
            _defectRow(Map<String, dynamic>.from(defect)),
          ],
        ],
      ),
    );
  }

  Widget _defectRow(Map<String, dynamic> defect) {
    final status = _repairStatus(defect['repair_status']);
    final location = defect['component_location']?.toString() ?? '';
    final etapa = defect['etapa_deteccion']?.toString() ?? '';
    final sourceArea = defect['defect_source_area']?.toString() ?? '';
    final repairedAt = defect['repaired_at']?.toString() ?? '';
    final details = <String>[
      if (location.isNotEmpty) '${tr('pcb_component_location')}: $location',
      if (etapa.isNotEmpty) '${tr('pcb_etapa_deteccion')}: $etapa',
      if (sourceArea.isNotEmpty) '${tr('pcb_source_area')}: $sourceArea',
    ];

    return Padding(
      padding: const EdgeInsets.only(left: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${defect['sort_order'] ?? '-'}. ',
              style: const TextStyle(color: Colors.amber, fontSize: 12)),
          Expanded(
            child: Text.rich(
              TextSpan(children: [
                TextSpan(
                  text: '${defect['defect_type'] ?? ''}',
                  style: const TextStyle(
                      color: Colors.amber,
                      fontSize: 12,
                      fontWeight: FontWeight.w600),
                ),
                if (details.isNotEmpty)
                  TextSpan(
                    text: '   ${details.join('  |  ')}',
                    style: const TextStyle(color: Colors.white60, fontSize: 11),
                  ),
              ]),
            ),
          ),
          if (status != null)
            Text(
              repairedAt.isEmpty ? status.$1 : '${status.$1} $repairedAt',
              style: TextStyle(
                  color: status.$2, fontSize: 11, fontWeight: FontWeight.w600),
            ),
        ],
      ),
    );
  }
}
