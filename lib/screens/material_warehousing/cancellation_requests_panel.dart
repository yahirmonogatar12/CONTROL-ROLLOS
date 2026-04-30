import 'dart:io';
import 'package:flutter/material.dart';
import 'package:material_warehousing_flutter/core/localization/app_translations.dart';
import 'package:material_warehousing_flutter/core/theme/app_colors.dart';
import 'package:material_warehousing_flutter/core/services/api_service.dart';
import 'package:material_warehousing_flutter/core/services/auth_service.dart';
import 'package:intl/intl.dart';
import 'package:excel/excel.dart' as excel_lib;
import 'package:file_picker/file_picker.dart';

/// Panel para que supervisores vean y aprueben/rechacen solicitudes de cancelación
class CancellationRequestsPanel extends StatefulWidget {
  final LanguageProvider languageProvider;
  final VoidCallback? onRequestProcessed;
  
  const CancellationRequestsPanel({
    super.key,
    required this.languageProvider,
    this.onRequestProcessed,
  });

  @override
  State<CancellationRequestsPanel> createState() => CancellationRequestsPanelState();
}

class CancellationRequestsPanelState extends State<CancellationRequestsPanel> {
  List<Map<String, dynamic>> _pendingRequests = [];
  List<Map<String, dynamic>> _historyRequests = [];
  bool _isLoading = true;
  bool _isLoadingHistory = false;
  bool _isExpanded = true;
  int _selectedTab = 0; // 0 = Pendientes, 1 = Historial

  String tr(String key) => widget.languageProvider.tr(key);

  @override
  void initState() {
    super.initState();
    loadPendingRequests();
  }

  Future<void> loadPendingRequests() async {
    setState(() => _isLoading = true);
    
    final requests = await ApiService.getPendingCancellations();
    
    if (mounted) {
      setState(() {
        _pendingRequests = requests;
        _isLoading = false;
      });
    }
  }

  Future<void> _loadHistory() async {
    if (_historyRequests.isNotEmpty) return; // Ya cargado
    
    setState(() => _isLoadingHistory = true);
    
    final history = await ApiService.getAllCancellationRequests();
    
    if (mounted) {
      setState(() {
        _historyRequests = history;
        _isLoadingHistory = false;
      });
    }
  }

  Future<void> _refreshHistory() async {
    setState(() => _isLoadingHistory = true);
    
    final history = await ApiService.getAllCancellationRequests();
    
    if (mounted) {
      setState(() {
        _historyRequests = history;
        _isLoadingHistory = false;
      });
    }
  }

  Future<void> _approveRequest(Map<String, dynamic> request) async {
    final currentUser = AuthService.currentUser;
    
    final result = await ApiService.approveCancellation(
      requestId: request['id'],
      reviewedBy: currentUser?.nombreCompleto ?? currentUser?.username ?? 'Unknown',
      reviewedById: currentUser?.id,
    );
    
    if (mounted) {
      if (result['success'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✓ ${tr('cancellation_approved')}'),
            backgroundColor: Colors.green,
          ),
        );
        loadPendingRequests();
        _historyRequests = []; // Forzar recarga del historial
        widget.onRequestProcessed?.call();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✗ ${result['error']}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _rejectRequest(Map<String, dynamic> request) async {
    final reasonController = TextEditingController();
    
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.panelBackground,
        title: Row(
          children: [
            const Icon(Icons.cancel, color: Colors.red, size: 24),
            const SizedBox(width: 8),
            Text(tr('reject_cancellation'), style: const TextStyle(color: Colors.white)),
          ],
        ),
        content: SizedBox(
          width: 350,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                tr('rejection_reason_prompt'),
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: reasonController,
                maxLines: 3,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: tr('enter_rejection_reason'),
                  hintStyle: const TextStyle(color: Colors.white38),
                  filled: true,
                  fillColor: AppColors.fieldBackground,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(4),
                    borderSide: const BorderSide(color: AppColors.border),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(tr('cancel'), style: const TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () {
              if (reasonController.text.trim().isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(tr('reason_required')), backgroundColor: Colors.orange),
                );
                return;
              }
              Navigator.pop(context, true);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: Text(tr('reject')),
          ),
        ],
      ),
    );

    if (result == true && reasonController.text.trim().isNotEmpty) {
      final currentUser = AuthService.currentUser;
      
      final response = await ApiService.rejectCancellation(
        requestId: request['id'],
        reviewedBy: currentUser?.nombreCompleto ?? currentUser?.username ?? 'Unknown',
        reviewedById: currentUser?.id,
        reviewNotes: reasonController.text.trim(),
      );
      
      if (mounted) {
        if (response['success'] == true) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('✓ ${tr('cancellation_rejected')}'),
              backgroundColor: Colors.orange,
            ),
          );
          loadPendingRequests();
          _historyRequests = []; // Forzar recarga del historial
          widget.onRequestProcessed?.call();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('✗ ${response['error']}'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  String _formatDate(String? dateStr) {
    if (dateStr == null) return '-';
    try {
      final date = DateTime.parse(dateStr);
      return DateFormat('dd/MM/yyyy HH:mm').format(date);
    } catch (_) {
      return dateStr;
    }
  }

  Color _getStatusColor(String? status) {
    switch (status) {
      case 'Approved':
        return Colors.green;
      case 'Rejected':
        return Colors.red;
      case 'Pending':
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }

  String _getStatusText(String? status) {
    switch (status) {
      case 'Approved':
        return tr('approved');
      case 'Rejected':
        return tr('rejected');
      case 'Pending':
        return tr('pending');
      default:
        return status ?? '-';
    }
  }

  Future<void> _exportToExcel() async {
    if (_historyRequests.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr('no_data_to_export')), backgroundColor: Colors.orange),
      );
      return;
    }

    try {
      final excel = excel_lib.Excel.createExcel();
      final sheet = excel['Cancellation History'];
      
      // Headers
      final headers = [
        tr('code'),
        tr('part_number'),
        tr('status'),
        tr('requested_by'),
        tr('request_date'),
        tr('reason'),
        tr('reviewed_by'),
        tr('review_date'),
        tr('notes'),
      ];
      
      // Add header row
      for (var i = 0; i < headers.length; i++) {
        sheet.cell(excel_lib.CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0)).value = excel_lib.TextCellValue(headers[i]);
      }
      
      // Add data rows
      for (var rowIndex = 0; rowIndex < _historyRequests.length; rowIndex++) {
        final request = _historyRequests[rowIndex];
        final row = rowIndex + 1;
        
        sheet.cell(excel_lib.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row)).value = 
            excel_lib.TextCellValue(request['warehousing_code']?.toString() ?? '-');
        sheet.cell(excel_lib.CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: row)).value = 
            excel_lib.TextCellValue(request['numero_parte']?.toString() ?? '-');
        sheet.cell(excel_lib.CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: row)).value = 
            excel_lib.TextCellValue(_getStatusText(request['status']?.toString()));
        sheet.cell(excel_lib.CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: row)).value = 
            excel_lib.TextCellValue(request['requested_by']?.toString() ?? '-');
        sheet.cell(excel_lib.CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: row)).value = 
            excel_lib.TextCellValue(_formatDate(request['requested_at']?.toString()));
        sheet.cell(excel_lib.CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: row)).value = 
            excel_lib.TextCellValue(request['reason']?.toString() ?? '-');
        sheet.cell(excel_lib.CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: row)).value = 
            excel_lib.TextCellValue(request['reviewed_by']?.toString() ?? '-');
        sheet.cell(excel_lib.CellIndex.indexByColumnRow(columnIndex: 7, rowIndex: row)).value = 
            excel_lib.TextCellValue(_formatDate(request['reviewed_at']?.toString()));
        sheet.cell(excel_lib.CellIndex.indexByColumnRow(columnIndex: 8, rowIndex: row)).value = 
            excel_lib.TextCellValue(request['review_notes']?.toString() ?? '-');
      }
      
      // Remove default sheet
      excel.delete('Sheet1');
      
      // Save file
      final fileName = 'Cancellation_History_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.xlsx';
      
      final result = await FilePicker.platform.saveFile(
        dialogTitle: tr('save_excel_file'),
        fileName: fileName,
        type: FileType.custom,
        allowedExtensions: ['xlsx'],
      );
      
      if (result != null) {
        final fileBytes = excel.save();
        if (fileBytes != null) {
          final file = File(result);
          await file.writeAsBytes(fileBytes);
          
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('✓ ${tr('export_success')}'),
                backgroundColor: Colors.green,
              ),
            );
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${tr('export_error')}: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // No mostrar si el usuario no puede aprobar
    if (!AuthService.canApproveCancellation) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      constraints: const BoxConstraints(maxHeight: 350),
      decoration: BoxDecoration(
        color: AppColors.panelBackground,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.orange.withOpacity(0.5)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          InkWell(
            onTap: () => setState(() => _isExpanded = !_isExpanded),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.2),
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(4),
                  topRight: const Radius.circular(4),
                  bottomLeft: Radius.circular(_isExpanded ? 0 : 4),
                  bottomRight: Radius.circular(_isExpanded ? 0 : 4),
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.pending_actions, color: Colors.orange, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    tr('cancellation_requests'),
                    style: const TextStyle(
                      color: Colors.orange,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                  if (_pendingRequests.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.orange,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${_pendingRequests.length}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ],
                  const Spacer(),
                  Icon(
                    _isExpanded ? Icons.expand_less : Icons.expand_more,
                    color: Colors.orange,
                    size: 20,
                  ),
                ],
              ),
            ),
          ),
          // Content
          if (_isExpanded) ...[
            // Tabs
            Container(
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: AppColors.border)),
              ),
              child: Row(
                children: [
                  _buildTab(0, tr('pending_cancellations'), _pendingRequests.length),
                  _buildTab(1, tr('history'), null),
                  const Spacer(),
                  // Botón de exportar Excel (solo en historial)
                  if (_selectedTab == 1) ...[
                    IconButton(
                      icon: const Icon(Icons.download, size: 16, color: Colors.green),
                      onPressed: _historyRequests.isEmpty ? null : _exportToExcel,
                      padding: const EdgeInsets.all(8),
                      constraints: const BoxConstraints(),
                      tooltip: tr('export_to_excel'),
                    ),
                    const SizedBox(width: 4),
                  ],
                  IconButton(
                    icon: const Icon(Icons.refresh, size: 16, color: Colors.white54),
                    onPressed: _selectedTab == 0 ? loadPendingRequests : _refreshHistory,
                    padding: const EdgeInsets.all(8),
                    constraints: const BoxConstraints(),
                    tooltip: tr('refresh'),
                  ),
                  const SizedBox(width: 8),
                ],
              ),
            ),
            // Content based on selected tab
            Flexible(
              child: _selectedTab == 0 ? _buildPendingList() : _buildHistoryList(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTab(int index, String title, int? count) {
    final isSelected = _selectedTab == index;
    return InkWell(
      onTap: () {
        setState(() => _selectedTab = index);
        if (index == 1) {
          _loadHistory();
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: isSelected ? Colors.orange : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              style: TextStyle(
                color: isSelected ? Colors.orange : Colors.white54,
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
            if (count != null && count > 0) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: isSelected ? Colors.orange : Colors.white24,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 10,
                    color: isSelected ? Colors.white : Colors.white70,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildPendingList() {
    if (_isLoading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    if (_pendingRequests.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.check_circle_outline, color: Colors.green, size: 32),
              const SizedBox(height: 8),
              Text(
                tr('no_pending_requests'),
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      shrinkWrap: true,
      padding: EdgeInsets.zero,
      itemCount: _pendingRequests.length,
      separatorBuilder: (_, __) => const Divider(color: AppColors.border, height: 1),
      itemBuilder: (context, index) {
        final request = _pendingRequests[index];
        return _buildPendingItem(request);
      },
    );
  }

  Widget _buildHistoryList() {
    if (_isLoadingHistory) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    if (_historyRequests.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.history, color: Colors.white24, size: 32),
              const SizedBox(height: 8),
              Text(
                tr('no_cancellation_history'),
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ],
          ),
        ),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SingleChildScrollView(
        child: DataTable(
          headingRowColor: WidgetStateProperty.all(Colors.orange.withOpacity(0.15)),
          dataRowColor: WidgetStateProperty.resolveWith<Color?>((states) {
            return states.contains(WidgetState.hovered)
                ? Colors.white.withOpacity(0.05)
                : null;
          }),
          columnSpacing: 16,
          horizontalMargin: 12,
          headingRowHeight: 40,
          dataRowMinHeight: 36,
          dataRowMaxHeight: 50,
          columns: [
            DataColumn(label: Text(tr('code'), style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold, fontSize: 11))),
            DataColumn(label: Text(tr('part_number'), style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold, fontSize: 11))),
            DataColumn(label: Text(tr('status'), style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold, fontSize: 11))),
            DataColumn(label: Text(tr('requested_by'), style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold, fontSize: 11))),
            DataColumn(label: Text(tr('request_date'), style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold, fontSize: 11))),
            DataColumn(label: Text(tr('reason'), style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold, fontSize: 11))),
            DataColumn(label: Text(tr('reviewed_by'), style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold, fontSize: 11))),
            DataColumn(label: Text(tr('review_date'), style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold, fontSize: 11))),
            DataColumn(label: Text(tr('notes'), style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold, fontSize: 11))),
          ],
          rows: _historyRequests.map((request) {
            final status = request['status']?.toString();
            final statusColor = _getStatusColor(status);
            
            return DataRow(
              cells: [
                DataCell(Text(
                  request['warehousing_code']?.toString() ?? '-',
                  style: const TextStyle(color: Colors.white, fontSize: 11),
                )),
                DataCell(Text(
                  request['numero_parte']?.toString() ?? '-',
                  style: const TextStyle(color: Colors.white70, fontSize: 11),
                )),
                DataCell(
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: statusColor.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: statusColor, width: 0.5),
                    ),
                    child: Text(
                      _getStatusText(status),
                      style: TextStyle(color: statusColor, fontSize: 10, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                DataCell(Text(
                  request['requested_by']?.toString() ?? '-',
                  style: const TextStyle(color: Colors.white70, fontSize: 11),
                )),
                DataCell(Text(
                  _formatDate(request['requested_at']?.toString()),
                  style: const TextStyle(color: Colors.white54, fontSize: 10),
                )),
                DataCell(
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 150),
                    child: Tooltip(
                      message: request['reason']?.toString() ?? '-',
                      child: Text(
                        request['reason']?.toString() ?? '-',
                        style: const TextStyle(color: Colors.white54, fontSize: 11),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 2,
                      ),
                    ),
                  ),
                ),
                DataCell(Text(
                  request['reviewed_by']?.toString() ?? '-',
                  style: TextStyle(color: statusColor, fontSize: 11, fontWeight: FontWeight.w500),
                )),
                DataCell(Text(
                  _formatDate(request['reviewed_at']?.toString()),
                  style: const TextStyle(color: Colors.white54, fontSize: 10),
                )),
                DataCell(
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 120),
                    child: Tooltip(
                      message: request['review_notes']?.toString() ?? '-',
                      child: Text(
                        request['review_notes']?.toString() ?? '-',
                        style: const TextStyle(color: Colors.white54, fontSize: 11),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 2,
                      ),
                    ),
                  ),
                ),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildPendingItem(Map<String, dynamic> request) {
    return Container(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Código y Part Number
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      request['warehousing_code'] ?? '-',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'PN: ${request['numero_parte'] ?? '-'} | Lot: ${request['numero_lote_material'] ?? '-'}',
                      style: const TextStyle(color: Colors.white54, fontSize: 11),
                    ),
                  ],
                ),
              ),
              Text(
                'Qty: ${request['cantidad_actual'] ?? 0}',
                style: const TextStyle(color: Colors.white70, fontSize: 11),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Solicitado por y fecha
          Row(
            children: [
              const Icon(Icons.person_outline, size: 14, color: Colors.white54),
              const SizedBox(width: 4),
              Text(
                request['requested_by'] ?? '-',
                style: const TextStyle(color: Colors.white70, fontSize: 11),
              ),
              const SizedBox(width: 12),
              const Icon(Icons.access_time, size: 14, color: Colors.white54),
              const SizedBox(width: 4),
              Text(
                _formatDate(request['requested_at']),
                style: const TextStyle(color: Colors.white54, fontSize: 11),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Motivo
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.fieldBackground,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tr('reason'),
                  style: const TextStyle(color: Colors.white54, fontSize: 10),
                ),
                const SizedBox(height: 4),
                Text(
                  request['reason'] ?? '-',
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          // Botones
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton.icon(
                onPressed: () => _rejectRequest(request),
                icon: const Icon(Icons.close, size: 16),
                label: Text(tr('reject'), style: const TextStyle(fontSize: 12)),
                style: TextButton.styleFrom(
                  foregroundColor: Colors.red,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: () => _approveRequest(request),
                icon: const Icon(Icons.check, size: 16),
                label: Text(tr('approve'), style: const TextStyle(fontSize: 12)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
