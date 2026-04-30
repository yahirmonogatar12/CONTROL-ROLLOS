import 'package:flutter/material.dart';
import 'package:material_warehousing_flutter/core/localization/app_translations.dart';
import 'package:material_warehousing_flutter/core/theme/app_colors.dart';
import 'package:material_warehousing_flutter/core/services/api_service.dart';
import 'package:material_warehousing_flutter/core/widgets/resizable_grid_header.dart';

class IqcPendingGrid extends StatefulWidget {
  final LanguageProvider languageProvider;
  final Function(Map<String, dynamic>)? onLotSelected;
  
  const IqcPendingGrid({
    super.key,
    required this.languageProvider,
    this.onLotSelected,
  });

  @override
  State<IqcPendingGrid> createState() => IqcPendingGridState();
}

class IqcPendingGridState extends State<IqcPendingGrid> with ResizableColumnsMixin {
  List<Map<String, dynamic>> _pendingLots = [];
  bool _isLoading = true;
  int _selectedIndex = -1;
  
  String tr(String key) => widget.languageProvider.tr(key);
  
  @override
  void initState() {
    super.initState();
    initColumnFlex(9, 'iqc_pending_grid', defaultFlexValues: [3.0, 1.0, 2.0, 2.0, 2.0, 2.0, 1.0, 1.0, 2.0]);
    _loadPendingLots();
  }
  
  Future<void> _loadPendingLots() async {
    setState(() => _isLoading = true);
    
    try {
      final lots = await ApiService.getIqcPending();
      if (mounted) {
        setState(() {
          _pendingLots = lots;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }
  
  // Método público para recargar datos
  Future<void> reloadData() async {
    await _loadPendingLots();
  }
  
  Widget _buildStatusBadge(String status) {
    Color bgColor;
    Color textColor;
    IconData icon;
    String displayText;
    
    switch (status.toLowerCase()) {
      case 'pending':
        bgColor = Colors.orange.withOpacity(0.3);
        textColor = Colors.orange;
        icon = Icons.hourglass_empty;
        displayText = tr('pending');
        break;
      case 'inprogress':
        bgColor = Colors.blue.withOpacity(0.3);
        textColor = Colors.blue;
        icon = Icons.play_circle_outline;
        displayText = tr('iqc_in_progress');
        break;
      default:
        bgColor = Colors.grey.withOpacity(0.3);
        textColor = Colors.grey;
        icon = Icons.help_outline;
        displayText = status;
    }
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: textColor),
          const SizedBox(width: 4),
          Text(
            displayText,
            style: TextStyle(fontSize: 10, color: textColor, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.gridBackground,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Título
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                const Icon(Icons.pending_actions, color: Colors.orange, size: 20),
                const SizedBox(width: 8),
                Text(
                  tr('iqc_pending_lots'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${_pendingLots.length}',
                    style: const TextStyle(
                      color: Colors.orange,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const Spacer(),
                IconButton(
                  onPressed: _loadPendingLots,
                  icon: const Icon(Icons.refresh, color: Colors.white70, size: 20),
                  tooltip: tr('refresh'),
                ),
              ],
            ),
          ),
          
          // Header con columnas redimensionables
          buildResizableHeader(
            headers: [
              tr('receiving_lot'),
              tr('lot_sequence'),
              tr('material_code'),
              tr('part_number'),
              tr('customer'),
              tr('arrival_date'),
              tr('total_labels'),
              tr('total_qty'),
              tr('status'),
            ],
            showCheckbox: false,
          ),
          
          // Lista de lotes pendientes
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _pendingLots.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.check_circle_outline, size: 64, color: Colors.green.withOpacity(0.5)),
                            const SizedBox(height: 16),
                            Text(
                              tr('no_pending_inspections'),
                              style: const TextStyle(color: Colors.white70, fontSize: 16),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        itemCount: _pendingLots.length,
                        itemBuilder: (context, index) {
                          final lot = _pendingLots[index];
                          final isSelected = index == _selectedIndex;
                          final isEven = index % 2 == 0;
                          
                          return GestureDetector(
                            onTap: () {
                              setState(() => _selectedIndex = index);
                            },
                            onDoubleTap: () {
                              widget.onLotSelected?.call(lot);
                            },
                            child: Container(
                              height: 36,
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? Colors.blue.withOpacity(0.3)
                                    : isEven
                                        ? AppColors.gridBackground
                                        : AppColors.gridBackground.withOpacity(0.7),
                                border: Border(
                                  bottom: const BorderSide(color: AppColors.border, width: 0.5),
                                  left: isSelected
                                      ? const BorderSide(color: Colors.blue, width: 3)
                                      : BorderSide.none,
                                ),
                              ),
                              child: Row(
                                children: [
                                  _buildDataCell(lot['receiving_lot_code']?.toString() ?? '', flex: getColumnFlex(0)),
                                  _buildLotSequenceBadge(lot['lot_sequence'], flex: getColumnFlex(1)),
                                  _buildDataCell(lot['material_code']?.toString() ?? '', flex: getColumnFlex(2)),
                                  _buildDataCell(lot['part_number']?.toString() ?? '', flex: getColumnFlex(3)),
                                  _buildDataCell(lot['customer']?.toString() ?? '', flex: getColumnFlex(4)),
                                  _buildDataCell(_formatDate(lot['arrival_date']?.toString() ?? ''), flex: getColumnFlex(5)),
                                  _buildDataCell(lot['total_labels']?.toString() ?? '0', flex: getColumnFlex(6), align: TextAlign.center),
                                  _buildDataCell(lot['total_qty_received']?.toString() ?? '0', flex: getColumnFlex(7), align: TextAlign.center),
                                  Expanded(
                                    flex: getColumnFlex(8),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 4),
                                      alignment: Alignment.centerLeft,
                                      child: _buildStatusBadge(lot['status']?.toString() ?? 'Pending'),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
          ),
          
          // Footer
          Container(
            height: 28,
            color: AppColors.gridHeader,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            alignment: Alignment.centerLeft,
            child: Text(
              '${tr('total_rows')}: ${_pendingLots.length}',
              style: const TextStyle(color: Colors.white70, fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildHeaderCell(String text, {int flex = 1}) {
    return Expanded(
      flex: flex,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        alignment: Alignment.centerLeft,
        child: Text(
          text,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
  
  Widget _buildDataCell(String text, {int flex = 1, TextAlign align = TextAlign.left}) {
    return Expanded(
      flex: flex,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        alignment: align == TextAlign.center ? Alignment.center : Alignment.centerLeft,
        child: Text(
          text,
          style: const TextStyle(fontSize: 11, color: Colors.white),
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
  
  Widget _buildLotSequenceBadge(dynamic lotSequence, {int flex = 1}) {
    final seq = int.tryParse(lotSequence?.toString() ?? '1') ?? 1;
    final isFirst = seq == 1;
    
    return Expanded(
      flex: flex,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        alignment: Alignment.center,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: isFirst 
                ? Colors.grey.withOpacity(0.3) 
                : Colors.cyan.withOpacity(0.3),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: isFirst ? Colors.grey.withOpacity(0.5) : Colors.cyan.withOpacity(0.5),
              width: 1,
            ),
          ),
          child: Text(
            '#$seq',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: isFirst ? Colors.grey : Colors.cyan,
            ),
          ),
        ),
      ),
    );
  }
  
  String _formatDate(String dateStr) {
    if (dateStr.isEmpty) return '';
    try {
      final date = DateTime.parse(dateStr);
      return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
    } catch (_) {
      return dateStr;
    }
  }
}
