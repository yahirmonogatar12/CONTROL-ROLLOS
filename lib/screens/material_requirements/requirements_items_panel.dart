import 'dart:io';
import 'package:flutter/material.dart';
import 'package:material_warehousing_flutter/core/widgets/column_filter.dart';
import 'package:flutter/services.dart';
import 'package:excel/excel.dart' as xl;
import 'package:file_picker/file_picker.dart';
import 'package:material_warehousing_flutter/core/localization/app_translations.dart';
import 'package:material_warehousing_flutter/core/theme/app_colors.dart';
import 'package:material_warehousing_flutter/core/services/api_service.dart';
import 'package:material_warehousing_flutter/core/services/auth_service.dart';
import 'package:material_warehousing_flutter/core/services/file_opener.dart';
import 'package:material_warehousing_flutter/core/widgets/grid_footer.dart';

int _asRequirementInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

int? _parsePositiveRequirementInt(dynamic value) {
  final parsed = int.tryParse(value?.toString().trim() ?? '');
  return parsed != null && parsed > 0 ? parsed : null;
}

// ============================================
// Requirements Items Panel - Detalle de Items
// ============================================
class RequirementsItemsPanel extends StatefulWidget {
  final LanguageProvider languageProvider;
  final Map<String, dynamic>? requirement;
  final VoidCallback? onItemsChanged;

  const RequirementsItemsPanel({
    super.key,
    required this.languageProvider,
    this.requirement,
    this.onItemsChanged,
  });

  @override
  State<RequirementsItemsPanel> createState() => RequirementsItemsPanelState();
}

class RequirementsItemsPanelState extends State<RequirementsItemsPanel> {
  List<Map<String, dynamic>> _allItems = [];
  final Map<String, String?> _columnFilters = {};
  List<Map<String, dynamic>> _items = [];

  /// Texto de la fila para una columna filtrable. Lo comparten el desplegable y
  /// el filtrado para que la lista ofrecida sea exactamente lo que se ve.
  static String _itemValue(Map<String, dynamic> item, String field) {
    switch (field) {
      case 'descripcion':
        return (item['descripcion'] ??
                item['especificacion_material'] ??
                '')
            .toString();
      case 'status':
        return (item['status'] ?? 'Pendiente').toString();
      case 'ubicaciones_disponibles':
        return (item['ubicaciones_disponibles'] ?? '').toString();
      default:
        return (item[field] ?? '').toString();
    }
  }

  void _applyItemFilters() {
    if (_columnFilters.isEmpty) {
      _items = List<Map<String, dynamic>>.from(_allItems);
      return;
    }
    _items = _allItems.where((item) {
      for (final entry in _columnFilters.entries) {
        if (!ColumnFilter.matches(
            _itemValue(item, entry.key).trim(), entry.value)) {
          return false;
        }
      }
      return true;
    }).toList();
  }

  Future<void> _onFilterColumn(String field, Offset position) async {
    final result = await ColumnFilter.show(
      context: context,
      anchorOffset: position,
      values: _allItems.map((item) => _itemValue(item, field)),
      currentFilter: _columnFilters[field],
    );
    if (!mounted || !result.changed) return;
    setState(() {
      if (result.filter == null) {
        _columnFilters.remove(field);
      } else {
        _columnFilters[field] = result.filter;
      }
      _selectedItems.clear();
      _applyItemFilters();
    });
  }
  bool _isLoading = false;
  int _selectedIndex = -1;
  Set<int> _selectedItems = {}; // Items seleccionados para eliminar

  String tr(String key) => widget.languageProvider.tr(key);

  bool get _canModifyRequirement =>
      AuthService.canWriteRequirements &&
      widget.requirement?['status']?.toString() == 'Pendiente';

  @override
  void initState() {
    super.initState();
    if (widget.requirement != null) {
      loadItems(widget.requirement!['id']);
    }
  }

  @override
  void didUpdateWidget(RequirementsItemsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.requirement?['id'] != oldWidget.requirement?['id']) {
      if (widget.requirement != null) {
        loadItems(widget.requirement!['id']);
      } else {
        setState(() {
          _allItems = [];
          _applyItemFilters();
          _selectedIndex = -1;
        });
      }
    }
  }

  Future<void> loadItems(int? requirementId) async {
    if (requirementId == null) {
      setState(() {
        _allItems = [];
        _applyItemFilters();
        _selectedIndex = -1;
      });
      return;
    }

    setState(() => _isLoading = true);

    try {
      final items = await ApiService.getRequirementItems(requirementId);
      if (mounted) {
        setState(() {
          _allItems = items;
          _applyItemFilters();
          _selectedIndex = -1;
          _selectedItems.clear(); // Limpiar selección al recargar
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  /// Eliminar items seleccionados (solo el creador puede eliminar)
  Future<void> _deleteSelectedItems() async {
    if (widget.requirement == null || _selectedItems.isEmpty) return;

    // Mostrar diálogo de confirmación
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.panelBackground,
        title: Row(
          children: [
            const Icon(Icons.warning_amber, color: Colors.orange, size: 24),
            const SizedBox(width: 8),
            Text(tr('confirm_delete'),
                style: const TextStyle(color: Colors.white, fontSize: 14)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${tr('items_to_delete')}: ${_selectedItems.length}',
              style: const TextStyle(
                  color: Colors.red, fontSize: 12, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              tr('delete_items_warning'),
              style: const TextStyle(color: Colors.white70, fontSize: 11),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(tr('cancel'),
                style: const TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: Text(tr('delete')),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    // Obtener usuario actual
    final currentUser = AuthService.currentUser?.nombreCompleto ?? '';

    // Llamar API para eliminar
    final result = await ApiService.removeMultipleRequirementItems(
      widget.requirement!['id'],
      _selectedItems.toList(),
      currentUser,
    );

    if (result['success'] == true) {
      setState(() => _selectedItems.clear());
      loadItems(widget.requirement!['id']);
      widget.onItemsChanged?.call();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result['message'] ?? tr('items_deleted')),
            backgroundColor: Colors.green,
          ),
        );
      }
    } else {
      if (mounted) {
        final errorMsg = result['error'] ?? 'Error';
        final creadorMsg = result['creador'] != null
            ? '\n${tr('created_by')}: ${result['creador']}'
            : '';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$errorMsg$creadorMsg'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
  }

  Future<void> _addMaterial() async {
    if (widget.requirement == null) return;

    // Mostrar diálogo para agregar material
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) =>
          _AddMaterialDialog(languageProvider: widget.languageProvider),
    );

    if (result != null) {
      try {
        final response = await ApiService.addRequirementItemsDetailed(
          widget.requirement!['id'],
          [result],
        );
        if (response['success'] != true) {
          throw Exception(
            response['error']?.toString() ?? 'No se pudo agregar el material',
          );
        }
        loadItems(widget.requirement!['id']);
        widget.onItemsChanged?.call();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  Future<void> _importFromBom() async {
    if (widget.requirement == null) return;

    // Mostrar diálogo para seleccionar modelo
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) =>
          _ImportBomDialog(languageProvider: widget.languageProvider),
    );

    if (result != null && result['items'] != null) {
      try {
        final added = await ApiService.addRequirementItems(
          widget.requirement!['id'],
          List<Map<String, dynamic>>.from(result['items']),
        );
        if (!added) throw Exception('No se pudieron importar los materiales');
        loadItems(widget.requirement!['id']);
        widget.onItemsChanged?.call();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  /// Excel: NParte TAB SPEC TAB cantidad, o NParte TAB SPEC TAB empaque TAB unidades.
  Future<void> _pasteFromClipboard() async {
    if (widget.requirement == null) return;

    try {
      final clipboardData = await Clipboard.getData(Clipboard.kTextPlain);
      if (clipboardData == null ||
          clipboardData.text == null ||
          clipboardData.text!.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text(tr('clipboard_empty')),
                backgroundColor: Colors.orange),
          );
        }
        return;
      }

      final text = clipboardData.text!;
      final lines = text
          .split(RegExp(r'[\r\n]+'))
          .where((line) => line.trim().isNotEmpty)
          .toList();

      if (lines.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text(tr('no_data_to_paste')),
                backgroundColor: Colors.orange),
          );
        }
        return;
      }

      final items = <Map<String, dynamic>>[];
      final partNumbers = <String>{};

      for (final line in lines) {
        // Split by tab (Excel copies with tabs)
        final parts = line.split('\t');

        if (parts.isEmpty) continue;

        // Parse: NParte, SPEC, cantidad directa; o empaque y unidades.
        final partNumber = parts.isNotEmpty ? parts[0].trim() : '';
        final spec = parts.length > 1 ? parts[1].trim() : '';
        final standardQuantity = parts.length > 2
            ? _parsePositiveRequirementInt(
                parts[2].replaceAll(',', '').replaceAll(' ', ''),
              )
            : null;
        final units = parts.length > 3
            ? _parsePositiveRequirementInt(
                parts[3].replaceAll(',', '').replaceAll(' ', ''),
              )
            : null;
        final usesUnits = standardQuantity != null && units != null;
        final qty =
            usesUnits ? standardQuantity * units : standardQuantity ?? 1;

        if (partNumber.isNotEmpty) {
          partNumbers.add(partNumber);
          final item = <String, dynamic>{
            'numero_parte': partNumber,
            'descripcion': spec,
            'cantidad_requerida': qty,
            'ubicacion': '', // Will be filled after location lookup
          };
          if (usesUnits) {
            item['cantidad_estandarizada'] = standardQuantity;
            item['cantidad_unidades'] = units;
            item['unidad_empaque'] = standardQuantity.toString();
          }
          items.add(item);
        }
      }

      if (items.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text(tr('no_valid_items')),
                backgroundColor: Colors.orange),
          );
        }
        return;
      }

      // Fetch locations for all part numbers
      final locations =
          await ApiService.getLocationsByPartNumbers(partNumbers.toList());

      // Update items with locations
      for (final item in items) {
        final pn = item['numero_parte']?.toString() ?? '';
        final locationList = locations[pn] ?? [];
        item['ubicacion'] =
            locationList.isNotEmpty ? locationList.join(', ') : '-';
      }

      // Show confirmation dialog
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: AppColors.panelBackground,
          title: Text(tr('confirm_paste'),
              style: const TextStyle(color: Colors.white, fontSize: 14)),
          content: SizedBox(
            width: 550,
            height: 350,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${tr('items_to_add')}: ${items.length}',
                  style: const TextStyle(
                      color: Colors.teal,
                      fontSize: 12,
                      fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                // Header row
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.gridHeader,
                    borderRadius:
                        const BorderRadius.vertical(top: Radius.circular(4)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: Text(
                          tr('part_number'),
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold),
                        ),
                      ),
                      Expanded(
                        flex: 2,
                        child: Text(
                          tr('description'),
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold),
                        ),
                      ),
                      Expanded(
                        flex: 2,
                        child: Text(
                          tr('location'),
                          style: const TextStyle(
                              color: Colors.amber,
                              fontSize: 10,
                              fontWeight: FontWeight.bold),
                        ),
                      ),
                      SizedBox(
                        width: 60,
                        child: Text(
                          tr('quantity'),
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold),
                          textAlign: TextAlign.right,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppColors.gridBackground,
                      borderRadius: const BorderRadius.vertical(
                          bottom: Radius.circular(4)),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: ListView.builder(
                      itemCount: items.length,
                      itemBuilder: (context, index) {
                        final item = items[index];
                        final hasLocation = item['ubicacion'] != null &&
                            item['ubicacion'] != '-' &&
                            item['ubicacion'].toString().isNotEmpty;
                        return Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            border: Border(
                                bottom: BorderSide(
                                    color: AppColors.border
                                        .withValues(alpha: 0.5))),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                flex: 2,
                                child: Text(
                                  item['numero_parte'] ?? '',
                                  style: const TextStyle(
                                      color: Colors.white, fontSize: 10),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              Expanded(
                                flex: 2,
                                child: Text(
                                  item['descripcion'] ?? '',
                                  style: const TextStyle(
                                      color: Colors.white54, fontSize: 10),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              Expanded(
                                flex: 2,
                                child: Text(
                                  item['ubicacion'] ?? '-',
                                  style: TextStyle(
                                    color:
                                        hasLocation ? Colors.amber : Colors.red,
                                    fontSize: 10,
                                    fontWeight: hasLocation
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              SizedBox(
                                width: 60,
                                child: Text(
                                  '${item['cantidad_requerida']}',
                                  style: const TextStyle(
                                      color: Colors.teal, fontSize: 10),
                                  textAlign: TextAlign.right,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(tr('cancel'),
                  style: const TextStyle(color: Colors.white54)),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.teal),
              child: Text('${tr('add')} ${items.length} ${tr('items')}'),
            ),
          ],
        ),
      );

      if (confirmed == true) {
        // Show loading dialog
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            backgroundColor: AppColors.panelBackground,
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(color: Colors.teal),
                const SizedBox(height: 16),
                Text(
                  '${tr('uploading')} ${items.length} ${tr('items')}...',
                  style: const TextStyle(color: Colors.white),
                ),
              ],
            ),
          ),
        );

        try {
          final added = await ApiService.addRequirementItems(
              widget.requirement!['id'], items);
          if (!added) throw Exception('No se pudieron agregar los materiales');

          // Close loading dialog
          if (mounted) Navigator.pop(context);

          loadItems(widget.requirement!['id']);
          widget.onItemsChanged?.call();

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('${items.length} ${tr('items_added')}'),
                backgroundColor: Colors.green,
              ),
            );
          }
        } catch (e) {
          // Close loading dialog on error
          if (mounted) Navigator.pop(context);
          rethrow;
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _updateItemQty(
      Map<String, dynamic> item, String field, int newValue) async {
    if (widget.requirement == null) return;

    try {
      final payload = <String, dynamic>{field: newValue};
      if (field == 'cantidad_requerida') {
        payload.addAll({
          'cantidad_estandarizada': null,
          'cantidad_unidades': null,
          'unidad_empaque': null,
        });
      }
      final updated = await ApiService.updateRequirementItem(
        widget.requirement!['id'],
        item['id'],
        payload,
      );
      if (!updated) {
        throw Exception('No se pudo actualizar la cantidad');
      }
      loadItems(widget.requirement!['id']);
      widget.onItemsChanged?.call();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  /// Export items to Excel with file picker
  Future<void> _exportToExcel() async {
    if (_items.isEmpty || widget.requirement == null) return;

    try {
      // Show file picker to select save location
      final result = await FilePicker.saveFile(
        dialogTitle: tr('save_excel_file'),
        fileName:
            'Requirement_${widget.requirement!['codigo_requerimiento'] ?? widget.requirement!['id']}.xlsx',
        type: FileType.custom,
        allowedExtensions: ['xlsx'],
      );

      if (result == null) return; // User cancelled

      final excel = xl.Excel.createExcel();
      final sheet = excel['Requirements'];

      // Header info
      sheet
              .cell(xl.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0))
              .value =
          xl.TextCellValue(
              '${tr('requirement')}: ${widget.requirement!['codigo_requerimiento'] ?? 'REQ-${widget.requirement!['id']}'}');
      sheet
              .cell(xl.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 1))
              .value =
          xl.TextCellValue(
              '${tr('target_area')}: ${widget.requirement!['area_destino'] ?? '-'}');
      sheet
              .cell(xl.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 2))
              .value =
          xl.TextCellValue(
              '${tr('required_date')}: ${widget.requirement!['fecha_requerida'] ?? '-'}');
      sheet
              .cell(xl.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 3))
              .value =
          xl.TextCellValue(
              '${tr('exported')}: ${DateTime.now().toString().split('.')[0]}');

      // Column headers (row 5)
      final headers = [
        tr('part_number'),
        tr('description'),
        'Cant. por empaque',
        'Unidades',
        tr('qty_required'),
        tr('qty_prepared'),
        tr('qty_delivered'),
        tr('status'),
        tr('location'),
        'Ubicación entrega',
      ];
      for (var i = 0; i < headers.length; i++) {
        sheet
            .cell(xl.CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 5))
            .value = xl.TextCellValue(headers[i]);
      }

      // Data rows
      for (var rowIdx = 0; rowIdx < _items.length; rowIdx++) {
        final item = _items[rowIdx];
        sheet
            .cell(xl.CellIndex.indexByColumnRow(
                columnIndex: 0, rowIndex: rowIdx + 6))
            .value = xl.TextCellValue(item['numero_parte']?.toString() ?? '');
        sheet
                .cell(xl.CellIndex.indexByColumnRow(
                    columnIndex: 1, rowIndex: rowIdx + 6))
                .value =
            xl.TextCellValue(item['descripcion']?.toString() ??
                item['especificacion_material']?.toString() ??
                '-');
        sheet
                .cell(xl.CellIndex.indexByColumnRow(
                    columnIndex: 2, rowIndex: rowIdx + 6))
                .value =
            xl.IntCellValue(_asRequirementInt(item['cantidad_estandarizada']));
        sheet
                .cell(xl.CellIndex.indexByColumnRow(
                    columnIndex: 3, rowIndex: rowIdx + 6))
                .value =
            xl.IntCellValue(_asRequirementInt(item['cantidad_unidades']));
        sheet
                .cell(xl.CellIndex.indexByColumnRow(
                    columnIndex: 4, rowIndex: rowIdx + 6))
                .value =
            xl.IntCellValue(_asRequirementInt(item['cantidad_requerida']));
        sheet
                .cell(xl.CellIndex.indexByColumnRow(
                    columnIndex: 5, rowIndex: rowIdx + 6))
                .value =
            xl.IntCellValue(_asRequirementInt(item['cantidad_preparada']));
        sheet
                .cell(xl.CellIndex.indexByColumnRow(
                    columnIndex: 6, rowIndex: rowIdx + 6))
                .value =
            xl.IntCellValue(_asRequirementInt(item['cantidad_entregada']));
        sheet
                .cell(xl.CellIndex.indexByColumnRow(
                    columnIndex: 7, rowIndex: rowIdx + 6))
                .value =
            xl.TextCellValue(item['status']?.toString() ?? 'Pendiente');
        sheet
                .cell(xl.CellIndex.indexByColumnRow(
                    columnIndex: 8, rowIndex: rowIdx + 6))
                .value =
            xl.TextCellValue(
                item['ubicaciones_disponibles']?.toString() ?? '-');
        sheet
                .cell(xl.CellIndex.indexByColumnRow(
                    columnIndex: 9, rowIndex: rowIdx + 6))
                .value =
            xl.TextCellValue(item['ubicacion_destino']?.toString() ?? '-');
      }

      // Remove default sheet
      if (excel.tables.containsKey('Sheet1')) {
        excel.delete('Sheet1');
      }

      // Save file
      final bytes = excel.encode();
      if (bytes != null) {
        final file = File(result);
        await file.writeAsBytes(bytes);
        await FileOpener.openInDefaultApp(result);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${tr('exported_to')}: $result'),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Export error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.gridBackground,
      child: Column(
        children: [
          // Header con título y botones
          _buildToolbar(),
          // Grid header
          _buildHeader(),
          // Data rows
          Expanded(child: _buildDataRows()),
          // Footer
          GridFooter(
            text: '${tr('total_items')}: ${_items.length}',
          ),
        ],
      ),
    );
  }

  Widget _buildToolbar() {
    final hasRequirement = widget.requirement != null;

    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: const BoxDecoration(
        color: AppColors.gridHeader,
        border: Border(bottom: BorderSide(color: AppColors.border, width: 1)),
      ),
      child: Row(
        children: [
          const Icon(Icons.list_alt, size: 14, color: Colors.teal),
          const SizedBox(width: 8),
          Text(
            hasRequirement
                ? '${tr('items')} - #${widget.requirement!['id']}'
                : tr('items'),
            style: const TextStyle(
                color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
          ),
          const Spacer(),
          if (hasRequirement) ...[
            if (_canModifyRequirement) ...[
              _buildToolbarButton(
                icon: Icons.add,
                label: tr('add_material'),
                color: Colors.teal,
                onPressed: _addMaterial,
              ),
              const SizedBox(width: 8),
              _buildToolbarButton(
                icon: Icons.upload_file,
                label: tr('import_from_bom'),
                color: Colors.purple,
                onPressed: _importFromBom,
              ),
              const SizedBox(width: 8),
              _buildToolbarButton(
                icon: Icons.content_paste,
                label: tr('paste_from_excel'),
                color: Colors.orange,
                onPressed: _pasteFromClipboard,
              ),
              const SizedBox(width: 8),
            ],
            _buildToolbarButton(
              icon: Icons.download,
              label: tr('export_excel'),
              color: AppColors.buttonExcel,
              onPressed: _items.isNotEmpty ? _exportToExcel : null,
            ),
            if (_selectedItems.isNotEmpty && _canModifyRequirement) ...[
              const SizedBox(width: 8),
              _buildToolbarButton(
                icon: Icons.delete_sweep,
                label: '${tr('delete')} (${_selectedItems.length})',
                color: Colors.red,
                onPressed: _deleteSelectedItems,
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildToolbarButton({
    required IconData icon,
    required String label,
    required Color color,
    VoidCallback? onPressed,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: color.withValues(alpha: 0.5)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 12, color: color),
              const SizedBox(width: 4),
              Text(label, style: TextStyle(fontSize: 10, color: color)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final allSelected =
        _items.isNotEmpty && _selectedItems.length == _items.length;
    return Container(
      height: 26,
      decoration: const BoxDecoration(
        color: AppColors.gridHeader,
        border: Border(bottom: BorderSide(color: AppColors.border, width: 1)),
      ),
      child: Row(
        children: [
          // Checkbox para seleccionar todos
          SizedBox(
            width: 30,
            child: Checkbox(
              value: allSelected,
              tristate: _selectedItems.isNotEmpty && !allSelected,
              onChanged: (value) {
                setState(() {
                  if (value == true) {
                    _selectedItems =
                        _items.map((item) => item['id'] as int).toSet();
                  } else {
                    _selectedItems.clear();
                  }
                });
              },
              activeColor: Colors.teal,
              checkColor: Colors.white,
              side: const BorderSide(color: Colors.white54),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
            ),
          ),
          _buildHeaderCell(tr('part_number'), 'numero_parte', flex: 2),
          _buildHeaderCell(tr('description'), 'descripcion', flex: 3),
          _buildHeaderCell(tr('qty_required'), 'cantidad_requerida', flex: 1),
          _buildHeaderCell(tr('qty_prepared'), 'cantidad_preparada', flex: 1),
          _buildHeaderCell(tr('qty_delivered'), 'cantidad_entregada', flex: 1),
          _buildHeaderCell(tr('status'), 'status', flex: 2),
          _buildHeaderCell(tr('location'), 'ubicaciones_disponibles', flex: 2),
          _buildHeaderCell('Ubicación entrega', 'ubicacion_entrega', flex: 2),
        ],
      ),
    );
  }

  Widget _buildHeaderCell(String text, String field, {int flex = 1}) {
    final hasFilter = _columnFilters[field] != null;
    return Expanded(
      flex: flex,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        decoration: const BoxDecoration(
          border:
              Border(right: BorderSide(color: AppColors.border, width: 0.5)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                text,
                style: const TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                    color: Colors.white),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            GestureDetector(
              onTapDown: (details) =>
                  _onFilterColumn(field, details.globalPosition),
              child: Icon(
                hasFilter ? Icons.filter_alt : Icons.filter_alt_outlined,
                size: 11,
                color: hasFilter ? Colors.blue : Colors.white38,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDataRows() {
    if (widget.requirement == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.touch_app,
                size: 32, color: Colors.white.withValues(alpha: 0.1)),
            const SizedBox(height: 8),
            Text(
              tr('select_requirement_to_view_items'),
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.3), fontSize: 11),
            ),
          ],
        ),
      );
    }

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: Colors.teal));
    }

    if (_items.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inventory_2_outlined,
                size: 32, color: Colors.white.withValues(alpha: 0.1)),
            const SizedBox(height: 8),
            Text(tr('no_items'),
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.3), fontSize: 11)),
            const SizedBox(height: 12),
            if (_canModifyRequirement)
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildToolbarButton(
                    icon: Icons.add,
                    label: tr('add_material'),
                    color: Colors.teal,
                    onPressed: _addMaterial,
                  ),
                  const SizedBox(width: 8),
                  _buildToolbarButton(
                    icon: Icons.upload_file,
                    label: tr('import_from_bom'),
                    color: Colors.purple,
                    onPressed: _importFromBom,
                  ),
                ],
              ),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: _items.length,
      itemBuilder: (context, index) {
        final item = _items[index];
        final itemId = item['id'] as int;
        final isSelected = index == _selectedIndex;
        final isChecked = _selectedItems.contains(itemId);
        final isEven = index % 2 == 0;

        // Calcular progreso
        final qtyReq = item['cantidad_requerida'] ?? 0;
        final qtyDel = item['cantidad_entregada'] ?? 0;
        final progress = qtyReq > 0 ? (qtyDel / qtyReq).clamp(0.0, 1.0) : 0.0;

        return GestureDetector(
          onTap: () => setState(() => _selectedIndex = isSelected ? -1 : index),
          child: Container(
            height: 26,
            decoration: BoxDecoration(
              color: isChecked
                  ? Colors.red.withValues(alpha: 0.15)
                  : isSelected
                      ? AppColors.gridSelectedRow
                      : isEven
                          ? AppColors.gridBackground
                          : AppColors.gridRowAlt,
              border: Border(
                bottom: const BorderSide(color: AppColors.border, width: 0.5),
                left: isSelected
                    ? const BorderSide(color: Colors.teal, width: 3)
                    : BorderSide.none,
              ),
            ),
            child: Row(
              children: [
                // Checkbox para seleccionar item
                SizedBox(
                  width: 30,
                  child: Checkbox(
                    value: isChecked,
                    onChanged: (value) {
                      setState(() {
                        if (value == true) {
                          _selectedItems.add(itemId);
                        } else {
                          _selectedItems.remove(itemId);
                        }
                      });
                    },
                    activeColor: Colors.red,
                    checkColor: Colors.white,
                    side: const BorderSide(color: Colors.white38),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                  ),
                ),
                _buildDataCell(item['numero_parte'] ?? '', flex: 2),
                _buildDataCell(
                    item['descripcion'] ??
                        item['especificacion_material'] ??
                        '-',
                    flex: 3),
                _buildQtyCell(item, 'cantidad_requerida',
                    flex: 1, editable: true),
                _buildDataCell('${item['cantidad_preparada'] ?? 0}', flex: 1),
                _buildDataCell('${item['cantidad_entregada'] ?? 0}', flex: 1),
                _buildStatusCell(item['status'] ?? 'Pendiente', progress,
                    flex: 2),
                _buildLocationCell(
                    item['ubicaciones_disponibles']?.toString() ?? '-',
                    flex: 2,
                    pendingInvoice: _pendingInvoiceNotice(item)),
                _buildDeliveryLocationCell(item, flex: 2),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildDataCell(String text, {int flex = 1}) {
    return Expanded(
      flex: flex,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        alignment: Alignment.centerLeft,
        decoration: const BoxDecoration(
          border:
              Border(right: BorderSide(color: AppColors.border, width: 0.5)),
        ),
        child: Text(
          text,
          style: const TextStyle(fontSize: 9, color: Colors.white),
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }

  Widget _buildQtyCell(Map<String, dynamic> item, String field,
      {int flex = 1, bool editable = false}) {
    final value = item[field] ?? 0;
    final standard = _parsePositiveRequirementInt(
      item['cantidad_estandarizada'],
    );
    final units = _parsePositiveRequirementInt(item['cantidad_unidades']);
    final quantityText = standard != null && units != null
        ? '$value ($standard×$units)'
        : '$value';

    return Expanded(
      flex: flex,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        alignment: Alignment.centerLeft,
        decoration: const BoxDecoration(
          border:
              Border(right: BorderSide(color: AppColors.border, width: 0.5)),
        ),
        child: editable
            ? Tooltip(
                message: standard != null && units != null
                    ? '$standard por empaque × $units unidades = $value'
                    : 'Cantidad requerida: $value',
                child: InkWell(
                  onTap: _canModifyRequirement
                      ? () => _showEditQtyDialog(item, field, value)
                      : null,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          quantityText,
                          style:
                              const TextStyle(fontSize: 9, color: Colors.white),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (_canModifyRequirement) ...[
                        const SizedBox(width: 2),
                        const Icon(Icons.edit, size: 8, color: Colors.white38),
                      ],
                    ],
                  ),
                ),
              )
            : Text('$value',
                style: const TextStyle(fontSize: 9, color: Colors.white)),
      ),
    );
  }

  Widget _buildStatusCell(String status, double progress, {int flex = 1}) {
    Color color;
    switch (status) {
      case 'Pendiente':
        color = Colors.orange;
        break;
      case 'Parcial':
        color = Colors.blue;
        break;
      case 'Preparado':
        color = Colors.cyan;
        break;
      case 'Entregado':
        color = Colors.green;
        break;
      default:
        color = Colors.grey;
    }

    return Expanded(
      flex: flex,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        alignment: Alignment.centerLeft,
        decoration: const BoxDecoration(
          border:
              Border(right: BorderSide(color: AppColors.border, width: 0.5)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(3),
              ),
              child: Text(status, style: TextStyle(fontSize: 8, color: color)),
            ),
            if (progress > 0 && progress < 1) ...[
              const SizedBox(height: 2),
              SizedBox(
                height: 3,
                child: LinearProgressIndicator(
                  value: progress,
                  backgroundColor: Colors.white12,
                  valueColor: AlwaysStoppedAnimation(color),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _pendingInvoiceNotice(Map<String, dynamic> item) {
    final available = _asRequirementInt(item['cantidad_disponible']);
    final pending = _asRequirementInt(item['cantidad_pendiente_entrada']);
    if (available > 0 || pending <= 0) return '';
    final invoices = (item['invoices_pendientes'] ?? '').toString().trim();
    return invoices.isEmpty
        ? '$pending pendiente por invoice'
        : '$pending pendiente · $invoices';
  }

  Widget _buildLocationCell(String location,
      {int flex = 1, String pendingInvoice = ''}) {
    final hasLocation =
        location.isNotEmpty && location != '-' && location != 'null';
    final showPendingInvoice = !hasLocation && pendingInvoice.isNotEmpty;

    return Expanded(
      flex: flex,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        alignment: Alignment.centerLeft,
        decoration: const BoxDecoration(
          border:
              Border(right: BorderSide(color: AppColors.border, width: 0.5)),
        ),
        child: showPendingInvoice
            ? Tooltip(
                message: 'Sin existencia en almacén. $pendingInvoice',
                child: Text(
                  '⏳ $pendingInvoice',
                  style: const TextStyle(
                    fontSize: 9,
                    color: Colors.orangeAccent,
                    fontWeight: FontWeight.bold,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              )
            : Text(
                hasLocation ? location : '-',
                style: TextStyle(
                  fontSize: 9,
                  color: hasLocation ? Colors.amber : Colors.red.shade300,
                  fontWeight: hasLocation ? FontWeight.bold : FontWeight.normal,
                ),
                overflow: TextOverflow.ellipsis,
              ),
      ),
    );
  }

  Widget _buildDeliveryLocationCell(Map<String, dynamic> item, {int flex = 1}) {
    final location = item['ubicacion_destino']?.toString().trim() ?? '';
    return Expanded(
      flex: flex,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        alignment: Alignment.centerLeft,
        decoration: const BoxDecoration(
          border:
              Border(right: BorderSide(color: AppColors.border, width: 0.5)),
        ),
        child: InkWell(
          onTap: _canModifyRequirement
              ? () => _showEditDeliveryLocationDialog(item)
              : null,
          child: Row(
            children: [
              Expanded(
                child: Text(
                  location.isEmpty ? '-' : location,
                  style: TextStyle(
                    fontSize: 9,
                    color: location.isEmpty ? Colors.white38 : Colors.amber,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (_canModifyRequirement)
                const Icon(Icons.edit_location_alt,
                    size: 10, color: Colors.white38),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showEditDeliveryLocationDialog(
      Map<String, dynamic> item) async {
    final controller = TextEditingController(
      text: item['ubicacion_destino']?.toString() ?? '',
    );
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.panelBackground,
        title: const Text(
          'Ubicación de entrega',
          style: TextStyle(color: Colors.white, fontSize: 14),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'Ej. Línea 3, Rack B...',
            prefixIcon: Icon(Icons.pin_drop),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(tr('cancel')),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: Text(tr('save')),
          ),
        ],
      ),
    );
    controller.dispose();
    if (result == null || widget.requirement == null) return;

    final updated = await ApiService.updateRequirementItem(
      widget.requirement!['id'],
      item['id'],
      {'ubicacion_destino': result},
    );
    if (!mounted) return;
    if (updated) {
      await loadItems(widget.requirement!['id']);
      widget.onItemsChanged?.call();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se pudo actualizar la ubicación de entrega.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _showEditQtyDialog(
      Map<String, dynamic> item, String field, int currentValue) async {
    final controller = TextEditingController(text: currentValue.toString());

    final result = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.panelBackground,
        title: Text(tr('edit_qty'),
            style: const TextStyle(color: Colors.white, fontSize: 14)),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            labelText:
                field == 'cantidad_preparada' ? tr('qty_prepared') : tr('qty'),
            labelStyle: const TextStyle(color: Colors.white54),
            border: const OutlineInputBorder(),
            enabledBorder: const OutlineInputBorder(
                borderSide: BorderSide(color: Colors.white24)),
            focusedBorder: const OutlineInputBorder(
                borderSide: BorderSide(color: Colors.teal)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(tr('cancel'),
                style: const TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () {
              final newValue = int.tryParse(controller.text) ?? currentValue;
              Navigator.pop(context, newValue);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.teal),
            child: Text(tr('save')),
          ),
        ],
      ),
    );

    if (result != null && result != currentValue) {
      _updateItemQty(item, field, result);
    }
  }
}

// ============================================
// Diálogo para agregar material manualmente
// ============================================
class _AddMaterialDialog extends StatefulWidget {
  final LanguageProvider languageProvider;

  const _AddMaterialDialog({required this.languageProvider});

  @override
  State<_AddMaterialDialog> createState() => _AddMaterialDialogState();
}

class _AddMaterialDialogState extends State<_AddMaterialDialog> {
  final _searchController = TextEditingController();
  final _cantidadController = TextEditingController(text: '1');
  final _standardQuantityController = TextEditingController();
  final _unitsController = TextEditingController(text: '1');
  final _deliveryLocationController = TextEditingController();
  List<Map<String, dynamic>> _materials = [];
  List<Map<String, dynamic>> _filteredMaterials = [];
  Map<String, dynamic>? _selectedMaterial;
  bool _isLoading = true;

  String tr(String key) => widget.languageProvider.tr(key);

  @override
  void initState() {
    super.initState();
    _loadMaterials();
  }

  Future<void> _loadMaterials() async {
    try {
      final materials = await ApiService.getMateriales();
      if (mounted) {
        setState(() {
          _materials = materials;
          _filteredMaterials = materials;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _onSearch(String query) {
    setState(() {
      if (query.isEmpty) {
        _filteredMaterials = _materials;
      } else {
        _filteredMaterials = _materials.where((m) {
          final partNumber = (m['numero_parte'] ?? '').toString().toLowerCase();
          final spec =
              (m['especificacion_material'] ?? '').toString().toLowerCase();
          return partNumber.contains(query.toLowerCase()) ||
              spec.contains(query.toLowerCase());
        }).toList();
      }
    });
  }

  int? get _standardQuantity =>
      _parsePositiveRequirementInt(_standardQuantityController.text);

  int get _units => _parsePositiveRequirementInt(_unitsController.text) ?? 1;

  bool get _usesUnits => _standardQuantity != null;

  int get _selectedAvailableQuantity =>
      _asRequirementInt(_selectedMaterial?['cantidad_disponible']);

  int get _selectedPendingInvoiceQuantity =>
      _asRequirementInt(_selectedMaterial?['cantidad_pendiente_entrada']);

  String get _selectedPendingInvoices {
    final invoices =
        (_selectedMaterial?['pendiente_entrada_en'] ?? '').toString().trim();
    return invoices == 'null' ? '' : invoices;
  }

  bool get _selectedIsPendingInvoiceOnly =>
      _selectedAvailableQuantity <= 0 && _selectedPendingInvoiceQuantity > 0;

  int get _requestedQuantity => _usesUnits
      ? _standardQuantity! * _units
      : (_parsePositiveRequirementInt(_cantidadController.text) ?? 0);

  void _syncCalculatedQuantity() {
    if (_usesUnits) {
      _cantidadController.text = '${_standardQuantity! * _units}';
    }
  }

  void _onUnitValueChanged(String _) {
    _syncCalculatedQuantity();
    setState(() {});
  }

  void _selectMaterial(Map<String, dynamic> material) {
    final standardPack =
        _parsePositiveRequirementInt(material['standard_pack']) ??
            _parsePositiveRequirementInt(material['unidad_empaque']);
    setState(() {
      _selectedMaterial = material;
      _standardQuantityController.text =
          standardPack == null ? '' : '$standardPack';
      _unitsController.text = '1';
      _syncCalculatedQuantity();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _cantidadController.dispose();
    _standardQuantityController.dispose();
    _unitsController.dispose();
    _deliveryLocationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.panelBackground,
      child: Container(
        width: 650,
        height: 550,
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Header
            Row(
              children: [
                const Icon(Icons.add, color: Colors.teal, size: 20),
                const SizedBox(width: 8),
                Text(tr('add_material'),
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600)),
                const Spacer(),
                IconButton(
                  icon:
                      const Icon(Icons.close, color: Colors.white54, size: 18),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Search bar and quantity
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: _searchController,
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                    decoration: InputDecoration(
                      hintText:
                          '${tr('search')} ${tr('part_number')} / ${tr('spec')}...',
                      hintStyle:
                          const TextStyle(color: Colors.white38, fontSize: 11),
                      prefixIcon: const Icon(Icons.search,
                          size: 18, color: Colors.white54),
                      filled: true,
                      fillColor: AppColors.gridBackground,
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(4),
                          borderSide: BorderSide.none),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                    ),
                    onChanged: _onSearch,
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 120,
                  child: TextField(
                    controller: _standardQuantityController,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                    onChanged: _onUnitValueChanged,
                    decoration: InputDecoration(
                      labelText: 'Cant. por empaque',
                      labelStyle:
                          const TextStyle(color: Colors.white54, fontSize: 10),
                      filled: true,
                      fillColor: AppColors.gridBackground,
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(4),
                          borderSide: BorderSide.none),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 75,
                  child: TextField(
                    controller: _unitsController,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                    onChanged: _onUnitValueChanged,
                    decoration: InputDecoration(
                      labelText: 'Unidades',
                      labelStyle:
                          const TextStyle(color: Colors.white54, fontSize: 10),
                      filled: true,
                      fillColor: AppColors.gridBackground,
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(4),
                          borderSide: BorderSide.none),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 100,
                  child: TextField(
                    controller: _cantidadController,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    readOnly: _usesUnits,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      labelText: 'Total',
                      labelStyle:
                          const TextStyle(color: Colors.white54, fontSize: 10),
                      filled: true,
                      fillColor: AppColors.gridBackground,
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(4),
                          borderSide: BorderSide.none),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 10),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Table header
            Container(
              height: 28,
              decoration: const BoxDecoration(
                color: AppColors.gridHeader,
                borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(4), topRight: Radius.circular(4)),
              ),
              child: Row(
                children: [
                  _buildHeaderCell(tr('part_number'), flex: 2),
                  _buildHeaderCell(tr('spec'), flex: 3),
                  _buildHeaderCell('Almacén / invoice', flex: 1),
                  _buildHeaderCell(tr('location'), flex: 2),
                ],
              ),
            ),

            // Table data
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(color: Colors.teal))
                  : _filteredMaterials.isEmpty
                      ? Center(
                          child: Text(tr('no_materials_found'),
                              style: const TextStyle(
                                  color: Colors.white38, fontSize: 11)))
                      : ListView.builder(
                          itemCount: _filteredMaterials.length,
                          itemBuilder: (context, index) {
                            final m = _filteredMaterials[index];
                            final isSelected = _selectedMaterial != null &&
                                _selectedMaterial!['numero_parte'] ==
                                    m['numero_parte'];

                            return GestureDetector(
                              onTap: () => _selectMaterial(m),
                              onDoubleTap: () {
                                _selectMaterial(m);
                                _confirmSelection();
                              },
                              child: Container(
                                height: 28,
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? Colors.teal.withValues(alpha: 0.3)
                                      : index.isEven
                                          ? AppColors.gridBackground
                                          : AppColors.gridRowAlt,
                                  border: Border(
                                    left: isSelected
                                        ? const BorderSide(
                                            color: Colors.teal, width: 3)
                                        : BorderSide.none,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    _buildDataCell(m['numero_parte'] ?? '',
                                        flex: 2),
                                    _buildDataCell(
                                        m['especificacion_material'] ?? '-',
                                        flex: 3),
                                    _buildAvailabilityCell(m, flex: 1),
                                    _buildDataCell(
                                        m['ubicacion_material'] ?? '-',
                                        flex: 2),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
            ),

            // Selected material info & buttons
            const SizedBox(height: 12),
            if (_selectedMaterial != null)
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: (_selectedIsPendingInvoiceOnly
                          ? Colors.orange
                          : Colors.teal)
                      .withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: (_selectedIsPendingInvoiceOnly
                            ? Colors.orange
                            : Colors.teal)
                        .withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      _selectedIsPendingInvoiceOnly
                          ? Icons.pending_actions
                          : Icons.check_circle,
                      color: _selectedIsPendingInvoiceOnly
                          ? Colors.orangeAccent
                          : Colors.teal,
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _selectedMaterial!['numero_parte'] ?? '',
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w600),
                          ),
                          Text(
                            '${_selectedMaterial!['especificacion_material'] ?? '-'} · Existencia: $_selectedAvailableQuantity${_selectedPendingInvoiceQuantity > 0 ? ' · Pendiente por invoice: $_selectedPendingInvoiceQuantity' : ''}',
                            style: const TextStyle(
                                color: Colors.white70, fontSize: 9),
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (_selectedIsPendingInvoiceOnly)
                            Text(
                              _selectedPendingInvoices.isEmpty
                                  ? 'Sin material en almacén; hay material pendiente por invoice.'
                                  : 'Sin material en almacén; pendiente en: $_selectedPendingInvoices',
                              style: const TextStyle(
                                color: Colors.orangeAccent,
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                        ],
                      ),
                    ),
                    Text(
                      _usesUnits
                          ? '${_standardQuantity ?? 0} × $_units = $_requestedQuantity'
                          : 'Total: $_requestedQuantity',
                      style: const TextStyle(
                          color: Colors.teal,
                          fontSize: 14,
                          fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 8),
            TextField(
              controller: _deliveryLocationController,
              style: const TextStyle(color: Colors.white, fontSize: 12),
              decoration: InputDecoration(
                labelText: 'Ubicación de entrega',
                hintText: 'Ej. Línea 3, Rack B...',
                prefixIcon:
                    const Icon(Icons.pin_drop, size: 16, color: Colors.amber),
                filled: true,
                fillColor: AppColors.gridBackground,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(4),
                    borderSide: BorderSide.none),
                isDense: true,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${_filteredMaterials.length} ${tr('materials')}',
                  style: const TextStyle(color: Colors.white54, fontSize: 10),
                ),
                Row(
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text(tr('cancel'),
                          style: const TextStyle(color: Colors.white54)),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed:
                          _selectedMaterial == null || _requestedQuantity <= 0
                              ? null
                              : _confirmSelection,
                      style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.teal),
                      child: Text(tr('add')),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _confirmSelection() {
    if (_selectedMaterial == null || _requestedQuantity <= 0) return;
    final standardQuantity = _standardQuantity;
    Navigator.pop(context, {
      'numero_parte': _selectedMaterial!['numero_parte'],
      'descripcion': _selectedMaterial!['especificacion_material'] ?? '',
      'cantidad_requerida': _requestedQuantity,
      'cantidad_estandarizada': standardQuantity,
      'cantidad_unidades': standardQuantity == null ? null : _units,
      'unidad_empaque': standardQuantity?.toString(),
      'ubicacion_destino': _deliveryLocationController.text.trim().isEmpty
          ? null
          : _deliveryLocationController.text.trim(),
      'ubicacion_material': _selectedMaterial!['ubicacion_material'],
    });
  }

  Widget _buildHeaderCell(String text, {int flex = 1}) {
    return Expanded(
      flex: flex,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        alignment: Alignment.centerLeft,
        child: Text(text,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.w600)),
      ),
    );
  }

  Widget _buildDataCell(String text, {int flex = 1}) {
    return Expanded(
      flex: flex,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        alignment: Alignment.centerLeft,
        child: Text(text,
            style: const TextStyle(color: Colors.white70, fontSize: 10),
            overflow: TextOverflow.ellipsis),
      ),
    );
  }

  Widget _buildAvailabilityCell(Map<String, dynamic> material, {int flex = 1}) {
    final available = _asRequirementInt(material['cantidad_disponible']);
    final pending = _asRequirementInt(material['cantidad_pendiente_entrada']);
    final invoices = (material['pendiente_entrada_en'] ?? '').toString().trim();
    final pendingOnly = available <= 0 && pending > 0;

    return Expanded(
      flex: flex,
      child: Tooltip(
        message: pendingOnly
            ? 'Sin existencia. Pendiente por recibir: $pending${invoices.isEmpty || invoices == 'null' ? '' : ' · $invoices'}'
            : 'Existencia en almacén: $available',
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          alignment: Alignment.centerLeft,
          child: Text(
            pendingOnly ? '⏳ +$pending' : '$available',
            style: TextStyle(
              color: pendingOnly
                  ? Colors.orangeAccent
                  : available > 0
                      ? Colors.greenAccent
                      : Colors.red.shade300,
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    );
  }
}

// ============================================
// Diálogo para importar desde BOM
// ============================================
class _ImportBomDialog extends StatefulWidget {
  final LanguageProvider languageProvider;

  const _ImportBomDialog({required this.languageProvider});

  @override
  State<_ImportBomDialog> createState() => _ImportBomDialogState();
}

class _ImportBomDialogState extends State<_ImportBomDialog> {
  final _modeloController = TextEditingController();
  final _cantidadController = TextEditingController(text: '1');
  List<Map<String, dynamic>> _bomItems = [];
  bool _isLoading = false;
  bool _bomLoaded = false;

  String tr(String key) => widget.languageProvider.tr(key);

  Future<void> _loadBom() async {
    if (_modeloController.text.isEmpty) return;

    setState(() => _isLoading = true);

    try {
      final items = await ApiService.importRequirementsBom(
        _modeloController.text.trim(),
        cantidad: int.tryParse(_cantidadController.text) ?? 1,
      );
      setState(() {
        _bomItems = items;
        _bomLoaded = true;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  void dispose() {
    _modeloController.dispose();
    _cantidadController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.panelBackground,
      title: Row(
        children: [
          const Icon(Icons.upload_file, color: Colors.purple, size: 20),
          const SizedBox(width: 8),
          Text(tr('import_from_bom'),
              style: const TextStyle(color: Colors.white, fontSize: 14)),
        ],
      ),
      content: SizedBox(
        width: 500,
        height: 400,
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: _modeloController,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: '${tr('model')} *',
                      labelStyle: const TextStyle(color: Colors.white54),
                      border: const OutlineInputBorder(),
                      enabledBorder: const OutlineInputBorder(
                          borderSide: BorderSide(color: Colors.white24)),
                      focusedBorder: const OutlineInputBorder(
                          borderSide: BorderSide(color: Colors.purple)),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _cantidadController,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: tr('multiplier'),
                      labelStyle: const TextStyle(color: Colors.white54),
                      border: const OutlineInputBorder(),
                      enabledBorder: const OutlineInputBorder(
                          borderSide: BorderSide(color: Colors.white24)),
                      focusedBorder: const OutlineInputBorder(
                          borderSide: BorderSide(color: Colors.purple)),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _isLoading ? null : _loadBom,
                  style:
                      ElevatedButton.styleFrom(backgroundColor: Colors.purple),
                  child: _isLoading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : Text(tr('load')),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: _bomLoaded
                  ? _bomItems.isEmpty
                      ? Center(
                          child: Text(tr('no_bom_found'),
                              style: const TextStyle(color: Colors.white54)))
                      : ListView.builder(
                          itemCount: _bomItems.length,
                          itemBuilder: (context, index) {
                            final item = _bomItems[index];
                            return Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 6),
                              decoration: BoxDecoration(
                                color: index.isEven
                                    ? AppColors.gridBackground
                                    : AppColors.gridRowAlt,
                                border: const Border(
                                    bottom: BorderSide(
                                        color: AppColors.border, width: 0.5)),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    flex: 2,
                                    child: Text(item['numero_parte'] ?? '',
                                        style: const TextStyle(
                                            color: Colors.white, fontSize: 11)),
                                  ),
                                  Expanded(
                                    flex: 3,
                                    child: Text(item['descripcion'] ?? '-',
                                        style: const TextStyle(
                                            color: Colors.white70,
                                            fontSize: 10)),
                                  ),
                                  SizedBox(
                                    width: 60,
                                    child: Text(
                                        'x ${item['cantidad_requerida']}',
                                        style: const TextStyle(
                                            color: Colors.teal, fontSize: 11)),
                                  ),
                                ],
                              ),
                            );
                          },
                        )
                  : Center(
                      child: Text(
                        tr('enter_model_to_load_bom'),
                        style: const TextStyle(
                            color: Colors.white38, fontSize: 11),
                      ),
                    ),
            ),
            if (_bomLoaded && _bomItems.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  '${_bomItems.length} ${tr('items')}',
                  style: const TextStyle(color: Colors.white54, fontSize: 10),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child:
              Text(tr('cancel'), style: const TextStyle(color: Colors.white54)),
        ),
        ElevatedButton(
          onPressed: _bomItems.isEmpty
              ? null
              : () {
                  Navigator.pop(context, {'items': _bomItems});
                },
          style: ElevatedButton.styleFrom(backgroundColor: Colors.purple),
          child: Text(tr('import')),
        ),
      ],
    );
  }
}
