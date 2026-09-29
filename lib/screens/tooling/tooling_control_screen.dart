import 'package:flutter/material.dart';
import 'package:material_warehousing_flutter/core/localization/app_translations.dart';
import 'package:material_warehousing_flutter/core/services/api_service.dart';
import 'package:material_warehousing_flutter/core/theme/app_colors.dart';
import 'package:material_warehousing_flutter/core/widgets/column_filter.dart';

class ToolingControlScreen extends StatefulWidget {
  final LanguageProvider languageProvider;

  const ToolingControlScreen({
    super.key,
    required this.languageProvider,
  });

  @override
  State<ToolingControlScreen> createState() => ToolingControlScreenState();
}

class ToolingControlScreenState extends State<ToolingControlScreen> {
  static const _statuses = ['ACTIVE', 'SCRAP', 'REPAIR', 'RETIRED'];

  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();
  final _locationController = TextEditingController();
  List<Map<String, dynamic>> _assets = [];
  List<Map<String, dynamic>> _assignments = [];
  String _type = '';
  String _status = '';
  String _assetSortColumn = 'control_code';
  String _assignmentSortColumn = 'assigned_at';
  bool _assetSortAscending = true;
  bool _assignmentSortAscending = false;
  /// 0 = Registro y uso (catalogo), 1 = Historial. Mismo selector que
  /// Inventario Actual: una sola tabla a la vez, a pantalla completa.
  int _view = 0;
  final Map<String, GlobalKey> _filterAnchors = {};
  final Map<String, String?> _assetFilters = {};
  final Map<String, String?> _historyFilters = {};
  Map<String, dynamic> _historyTotals = {};
  String? _historyCode;
  String? _selectedAsset;
  String? _selectedAssignment;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocus.dispose();
    _locationController.dispose();
    super.dispose();
  }

  void requestScanFocus() => _searchFocus.requestFocus();

  Future<void> _load() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    // En Historial, "No control" filtra el historial; si hay una fila
    // seleccionada manda la seleccion.
    _historyCode = _selectedAsset ??
        (_searchController.text.trim().isEmpty
            ? null
            : _searchController.text.trim().toUpperCase());
    final results = await Future.wait([
      ApiService.getToolingAssets(
        type: _type.isEmpty ? null : _type,
        search: _searchController.text,
        status: _status.isEmpty ? null : _status,
        location: _locationController.text,
      ),
      // Historial completo, no solo lo reciente: si hay un herramental
      // seleccionado se acota a su vida entera.
      ApiService.getToolingAssignments(code: _historyCode),
    ]);
    if (!mounted) return;
    final assetsResult = results[0];
    final historyResult = results[1];
    setState(() {
      _loading = false;
      if (assetsResult['success'] == true && historyResult['success'] == true) {
        _assets = (assetsResult['assets'] as List? ?? const [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _assignments = (historyResult['assignments'] as List? ?? const [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _historyTotals =
            Map<String, dynamic>.from(historyResult['totals'] as Map? ?? {});
      } else {
        _error = (assetsResult['error'] ??
                historyResult['error'] ??
                'No fue posible cargar datos')
            .toString();
      }
    });
  }

  /// Recarga solo el historial: al elegir otra fila no hace falta releer el
  /// catalogo completo.
  Future<void> _loadHistory(String? code) async {
    setState(() => _historyCode = code);
    final result = await ApiService.getToolingAssignments(code: code);
    if (!mounted) return;
    setState(() {
      if (result['success'] == true) {
        _assignments = (result['assignments'] as List? ?? const [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _historyTotals =
            Map<String, dynamic>.from(result['totals'] as Map? ?? {});
      }
    });
  }

  /// El Squeegee no ocupa PCB, fecha de produccion ni espesor: se marcan N/A
  /// para distinguirlos de una Metal Mask a la que solo le falta el dato.
  static bool _isMask(Map<String, dynamic> row) =>
      row['asset_type'] == 'METAL_MASK';

  static String _maskField(Map<String, dynamic> row, String key) {
    if (!_isMask(row)) return 'N/A';
    final value = '${row[key] ?? ''}'.trim();
    return value.isEmpty || value == 'null' ? '-' : value;
  }

  /// Barra de uso contra el limite, al estilo de la cuenta regresiva de pasta.
  /// Sin limite no hay porcentaje que mostrar: se deja un guion.
  Widget _useBar(Map<String, dynamic> row) {
    final limit = int.tryParse('${row['use_limit'] ?? 0}') ?? 0;
    final used = int.tryParse('${row['use_count'] ?? 0}') ?? 0;
    if (limit <= 0) {
      return const Text(
        '-',
        style: TextStyle(color: Colors.white38, fontSize: 11),
      );
    }
    final ratio = used / limit;
    final color = ratio >= 1
        ? Colors.redAccent
        : ratio >= 0.8
            ? Colors.orangeAccent
            : Colors.greenAccent;
    return Stack(
      alignment: Alignment.center,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: ratio.clamp(0.0, 1.0),
            minHeight: 14,
            backgroundColor: Colors.white12,
            valueColor: AlwaysStoppedAnimation(color),
          ),
        ),
        Text(
          '$used / $limit  (${(ratio * 100).toStringAsFixed(0)}%)',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  // Limite 0/null = sin limite; los usos suben por plan_count al autorizar.
  static bool _limitReached(Map<String, dynamic> row) {
    final limit = int.tryParse('${row['use_limit'] ?? 0}') ?? 0;
    final used = int.tryParse('${row['use_count'] ?? 0}') ?? 0;
    return limit > 0 && used >= limit;
  }

  Widget _viewTab(int index, String label) {
    final selected = _view == index;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          if (_view == index) return;
          setState(() => _view = index);
          if (index == 1) _loadHistory(_historyCode);
        },
        child: Container(
          decoration: BoxDecoration(
            color: selected ? AppColors.headerTab : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: AppColors.headerTab.withValues(alpha: 0.5),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
              color: selected ? Colors.white : Colors.white54,
            ),
          ),
        ),
      ),
    );
  }

  Widget _viewSelector() {
    return Container(
      width: 260,
      height: 32,
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(6),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 6,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          _viewTab(0, 'Registro y uso'),
          _viewTab(1, 'Historial'),
        ],
      ),
    );
  }

  static InputDecoration _fieldDecoration() => const InputDecoration(
        isDense: true,
        filled: true,
        fillColor: AppColors.fieldBackground,
        contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        border: OutlineInputBorder(
          borderSide: BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderSide: BorderSide(color: AppColors.border),
        ),
      );

  Future<void> _editSelectedAsset() async {
    Map<String, dynamic>? row;
    for (final item in _assets) {
      if ('${item['control_code'] ?? ''}' == _selectedAsset) row = item;
    }
    if (row == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Seleccione un herramental de la lista'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    await _assetDialog(row);
  }

  /// Un solo formulario para alta y edicion: en alta el tipo y el "No control"
  /// son editables, en edicion identifican la fila y quedan fijos.
  Future<void> _assetDialog(Map<String, dynamic>? asset) async {
    final creating = asset == null;
    final controlCode =
        TextEditingController(text: '${asset?['control_code'] ?? ''}');
    final location =
        TextEditingController(text: '${asset?['location_code'] ?? ''}');
    final rawLimit = '${asset?['use_limit'] ?? ''}';
    final useLimit =
        TextEditingController(text: rawLimit == 'null' ? '' : rawLimit);
    final pcbNo = TextEditingController(text: '${asset?['pcb_no'] ?? ''}');
    final prodDate =
        TextEditingController(text: '${asset?['production_date_raw'] ?? ''}');
    final thickness =
        TextEditingController(text: '${asset?['thickness_mm'] ?? ''}');
    final arraySize =
        TextEditingController(text: '${asset?['array_size'] ?? 1}');
    for (final c in [pcbNo, prodDate, thickness, arraySize]) {
      if (c.text == 'null') c.clear();
    }
    if (arraySize.text.trim().isEmpty) arraySize.text = '1';
    var type = '${asset?['asset_type'] ?? 'METAL_MASK'}';
    var status = '${asset?['lifecycle_status'] ?? 'ACTIVE'}';
    if (!_statuses.contains(status)) status = 'ACTIVE';
    // '' = sin definir: la estacion no verifica el lado de esa mask.
    var side = '${asset?['side'] ?? ''}'.trim().toUpperCase();
    if (side == 'BOTTOM') side = 'BOT';
    if (side != 'TOP' && side != 'BOT') side = '';

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: AppColors.panelBackground,
          title: Text(
            creating
                ? 'Registrar herramental'
                : 'Editar ${asset['control_code']}',
            style: const TextStyle(color: Colors.white, fontSize: 14),
          ),
          content: SizedBox(
            width: 320,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (creating) ...[
                    const Text('Tipo',
                        style: TextStyle(color: Colors.white70, fontSize: 11)),
                    DropdownButtonFormField<String>(
                      initialValue: type,
                      dropdownColor: AppColors.panelBackground,
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                      decoration: _fieldDecoration(),
                      items: const [
                        DropdownMenuItem(
                            value: 'METAL_MASK', child: Text('Metal Mask')),
                        DropdownMenuItem(
                            value: 'SQUEEGEE', child: Text('Squeegee')),
                      ],
                      onChanged: (value) =>
                          setDialogState(() => type = value ?? type),
                    ),
                    const SizedBox(height: 10),
                    const Text('No control (código a escanear)',
                        style: TextStyle(color: Colors.white70, fontSize: 11)),
                    TextField(
                      controller: controlCode,
                      autofocus: true,
                      textCapitalization: TextCapitalization.characters,
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                      decoration: _fieldDecoration(),
                    ),
                    const SizedBox(height: 10),
                  ],
                  const Text('Ubicacion',
                      style: TextStyle(color: Colors.white70, fontSize: 11)),
                  TextField(
                    controller: location,
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                    decoration: _fieldDecoration(),
                  ),
                  const SizedBox(height: 10),
                  if (type == 'METAL_MASK') ...[
                    const Text('No PCB (se guarda sin versión)',
                        style: TextStyle(color: Colors.white70, fontSize: 11)),
                    TextField(
                      controller: pcbNo,
                      textCapitalization: TextCapitalization.characters,
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                      decoration: _fieldDecoration(),
                    ),
                    const SizedBox(height: 10),
                    const Text('Fecha de producción',
                        style: TextStyle(color: Colors.white70, fontSize: 11)),
                    TextField(
                      controller: prodDate,
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                      decoration: _fieldDecoration(),
                    ),
                    const SizedBox(height: 10),
                    const Text('Espesor (mm)',
                        style: TextStyle(color: Colors.white70, fontSize: 11)),
                    TextField(
                      controller: thickness,
                      keyboardType: TextInputType.number,
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                      decoration: _fieldDecoration(),
                    ),
                    const SizedBox(height: 10),
                    const Text('Array (piezas por impresión)',
                        style: TextStyle(color: Colors.white70, fontSize: 11)),
                    TextField(
                      controller: arraySize,
                      keyboardType: TextInputType.number,
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                      decoration: _fieldDecoration(),
                    ),
                    const Padding(
                      padding: EdgeInsets.only(top: 4),
                      child: Text(
                        'El plan se divide entre el array: 100 piezas con array 4 '
                        'son 25 impresiones. Los squeegees se reparten esas 25.',
                        style: TextStyle(color: Colors.white38, fontSize: 10),
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text('Lado',
                        style: TextStyle(color: Colors.white70, fontSize: 11)),
                    DropdownButtonFormField<String>(
                      initialValue: side,
                      dropdownColor: AppColors.panelBackground,
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                      decoration: _fieldDecoration(),
                      items: const [
                        DropdownMenuItem(value: '', child: Text('Sin definir')),
                        DropdownMenuItem(value: 'TOP', child: Text('TOP')),
                        DropdownMenuItem(value: 'BOT', child: Text('BOT')),
                      ],
                      onChanged: (value) =>
                          setDialogState(() => side = value ?? side),
                    ),
                    const Padding(
                      padding: EdgeInsets.only(top: 4),
                      child: Text(
                        'En doble cara la estación rechaza la mask del otro lado. '
                        'Sin definir = no se verifica.',
                        style: TextStyle(color: Colors.white38, fontSize: 10),
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
                  const Text('Estado',
                      style: TextStyle(color: Colors.white70, fontSize: 11)),
                  DropdownButtonFormField<String>(
                    initialValue: status,
                    dropdownColor: AppColors.panelBackground,
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                    decoration: _fieldDecoration(),
                    items: _statuses
                        .map((value) =>
                            DropdownMenuItem(value: value, child: Text(value)))
                        .toList(),
                    onChanged: (value) =>
                        setDialogState(() => status = value ?? status),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    creating
                        ? 'Límite de uso (vacío = sin límite)'
                        : 'Límite de uso (vacío = sin límite). Usos actuales: ${asset['use_count'] ?? 0}',
                    style:
                        const TextStyle(color: Colors.white70, fontSize: 11),
                  ),
                  TextField(
                    controller: useLimit,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                    decoration: _fieldDecoration(),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.buttonSearch),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(creating ? 'Registrar' : 'Guardar',
                  style: const TextStyle(fontSize: 12)),
            ),
          ],
        ),
      ),
    );

    if (saved != true || !mounted) return;
    if (creating && controlCode.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('El No control es obligatorio'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    final result = creating
        ? await ApiService.createToolingAsset(
            assetType: type,
            controlCode: controlCode.text.trim().toUpperCase(),
            locationCode: location.text,
            lifecycleStatus: status,
            useLimit: useLimit.text.trim(),
            pcbNo: type == 'METAL_MASK' ? pcbNo.text : null,
            productionDateRaw: type == 'METAL_MASK' ? prodDate.text : null,
            thicknessMm: type == 'METAL_MASK' ? thickness.text.trim() : null,
            arraySize: type == 'METAL_MASK' ? arraySize.text.trim() : null,
            side: type == 'METAL_MASK' ? side : null,
          )
        : await ApiService.updateToolingAsset(
            '${asset['control_code']}',
            locationCode: location.text,
            lifecycleStatus: status,
            useLimit: useLimit.text.trim(),
            pcbNo: type == 'METAL_MASK' ? pcbNo.text : null,
            productionDateRaw: type == 'METAL_MASK' ? prodDate.text : null,
            thicknessMm: type == 'METAL_MASK' ? thickness.text.trim() : null,
            arraySize: type == 'METAL_MASK' ? arraySize.text.trim() : null,
            side: type == 'METAL_MASK' ? side : null,
          );
    if (!mounted) return;
    final ok = result['success'] == true;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok
            ? (creating ? 'Herramental registrado' : 'Herramental actualizado')
            : '${result['error'] ?? 'No fue posible guardar'}'),
        backgroundColor: ok ? Colors.green : Colors.red,
      ),
    );
    if (ok) _load();
  }

  String _formatDate(dynamic value) {
    final raw = '${value ?? ''}'.trim();
    if (raw.isEmpty || raw == 'null') return '-';
    final parsed = DateTime.tryParse(raw.replaceFirst(' ', 'T'));
    if (parsed == null) return raw;
    final date = parsed.isUtc ? parsed.toLocal() : parsed;
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    final hour = date.hour.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');
    return '$day/$month/${date.year} $hour:$minute';
  }

  /// Deja solo las filas que pasan todos los filtros de columna activos.
  List<Map<String, dynamic>> _applyColumnFilters(
    List<Map<String, dynamic>> rows,
    List<_ToolingColumn> columns,
    Map<String, String?> filters,
  ) {
    if (filters.isEmpty) return rows;
    return rows.where((row) {
      for (final entry in filters.entries) {
        if (entry.value == null) continue;
        final column = columns.firstWhere(
          (c) => c.key == entry.key,
          orElse: () => columns.first,
        );
        if (!ColumnFilter.matches(column.value(row).trim(), entry.value)) {
          return false;
        }
      }
      return true;
    }).toList();
  }

  List<Map<String, dynamic>> _sortedRows(
    List<Map<String, dynamic>> rows,
    List<_ToolingColumn> columns,
    String sortColumn,
    bool ascending,
  ) {
    final sorted = List<Map<String, dynamic>>.from(rows);
    final column = columns.firstWhere(
      (item) => item.key == sortColumn,
      orElse: () => columns.first,
    );
    sorted.sort((a, b) {
      final aValue = '${a[sortColumn] ?? column.value(a)}'.trim();
      final bValue = '${b[sortColumn] ?? column.value(b)}'.trim();
      final aNumber = num.tryParse(aValue);
      final bNumber = num.tryParse(bValue);
      final aDate = DateTime.tryParse(aValue.replaceFirst(' ', 'T'));
      final bDate = DateTime.tryParse(bValue.replaceFirst(' ', 'T'));
      final result = aNumber != null && bNumber != null
          ? aNumber.compareTo(bNumber)
          : aDate != null && bDate != null
              ? aDate.compareTo(bDate)
              : aValue.toLowerCase().compareTo(bValue.toLowerCase());
      return ascending ? result : -result;
    });
    return sorted;
  }

  Widget _buildSection({
    required String title,
    required IconData icon,
    required List<Map<String, dynamic>> rows,
    required List<_ToolingColumn> columns,
    required String sortColumn,
    required bool sortAscending,
    required String Function(Map<String, dynamic>) rowKey,
    required String? selectedKey,
    required ValueChanged<String> onSelected,
    required void Function(String key) onSort,
    required Map<String, String?> filters,
  }) {
    final visibleRows = _applyColumnFilters(rows, columns, filters);
    final sortedRows =
        _sortedRows(visibleRows, columns, sortColumn, sortAscending);
    final hasSelection = selectedKey != null &&
        visibleRows.any((row) => rowKey(row) == selectedKey);
    return Container(
      decoration: BoxDecoration(
        color: AppColors.gridBackground,
        border: Border.all(color: AppColors.border, width: 0.8),
      ),
      child: Column(
        children: [
          Container(
            height: 30,
            color: AppColors.panelBackground,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                Icon(icon, size: 15, color: Colors.white70),
                const SizedBox(width: 6),
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                Text(
                  '${rows.length} registros',
                  style: const TextStyle(color: Colors.white54, fontSize: 10),
                ),
              ],
            ),
          ),
          Container(
            height: 32,
            decoration: const BoxDecoration(
              color: AppColors.gridHeader,
              border: Border(
                bottom: BorderSide(color: AppColors.border, width: 1),
              ),
            ),
            child: Row(
              children: columns.map((column) {
                final isSorted = sortColumn == column.key;
                final isFiltered = filters[column.key] != null;
                final anchorKey =
                    _filterAnchors.putIfAbsent('$title|${column.key}', GlobalKey.new);
                return Expanded(
                  flex: column.flex,
                  child: InkWell(
                    onTap: () => onSort(column.key),
                    child: Container(
                      key: anchorKey,
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      alignment: column.alignment,
                      decoration: const BoxDecoration(
                        border: Border(
                          right:
                              BorderSide(color: Color(0xFF315D73), width: 0.5),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: column.alignment == Alignment.center
                            ? MainAxisAlignment.center
                            : MainAxisAlignment.start,
                        children: [
                          Flexible(
                            child: Text(
                              column.label,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          if (isSorted) ...[
                            const SizedBox(width: 3),
                            Icon(
                              sortAscending
                                  ? Icons.arrow_upward
                                  : Icons.arrow_downward,
                              size: 10,
                              color: Colors.lightBlueAccent,
                            ),
                          ],
                          // Embudo igual que en Entradas: se pinta en azul
                          // cuando la columna tiene filtro puesto.
                          InkWell(
                            onTap: () async {
                              final result = await ColumnFilter.show(
                                context: context,
                                anchorKey: anchorKey,
                                values: rows.map((r) => column.value(r).trim()),
                                currentFilter: filters[column.key],
                              );
                              if (!result.changed) return;
                              setState(() {
                                if (result.filter == null) {
                                  filters.remove(column.key);
                                } else {
                                  filters[column.key] = result.filter;
                                }
                              });
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 2),
                              child: Icon(
                                Icons.filter_alt,
                                size: 11,
                                color: isFiltered
                                    ? Colors.lightBlueAccent
                                    : Colors.white38,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          Expanded(
            child: _loading && rows.isEmpty
                ? const Center(
                    child: CircularProgressIndicator(color: Colors.white70),
                  )
                : sortedRows.isEmpty
                    ? const Center(
                        child: Text(
                          'No hay datos para mostrar',
                          style: TextStyle(color: Colors.white70, fontSize: 11),
                        ),
                      )
                    : SelectionArea(
                        child: ListView.builder(
                          primary: false,
                          itemCount: sortedRows.length,
                          itemExtent: 29,
                          itemBuilder: (context, index) {
                            final row = sortedRows[index];
                            final key = rowKey(row);
                            final selected = selectedKey == key;
                            return InkWell(
                              onTap: () => onSelected(key),
                              child: Container(
                                decoration: BoxDecoration(
                                  color: selected
                                      ? AppColors.gridSelectedRow
                                      : index.isEven
                                          ? AppColors.gridBackground
                                          : AppColors.gridRowAlt,
                                  border: Border(
                                    bottom: const BorderSide(
                                      color: AppColors.border,
                                      width: 0.35,
                                    ),
                                    left: selected
                                        ? const BorderSide(
                                            color: Colors.lightBlueAccent,
                                            width: 3,
                                          )
                                        : BorderSide.none,
                                  ),
                                ),
                                child: Row(
                                  children: columns.map((column) {
                                    return Expanded(
                                      flex: column.flex,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 6),
                                        alignment: column.alignment,
                                        decoration: const BoxDecoration(
                                          border: Border(
                                            right: BorderSide(
                                              color: Color(0xFF465064),
                                              width: 0.35,
                                            ),
                                          ),
                                        ),
                                        child: column.builder?.call(row) ??
                                            Text(
                                              column.value(row),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: column.style?.call(row) ??
                                                  const TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 11,
                                                  ),
                                            ),
                                      ),
                                    );
                                  }).toList(),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
          ),
          Container(
            height: 24,
            color: AppColors.gridHeader,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            alignment: Alignment.centerLeft,
            child: Text(
              !hasSelection
                  ? 'Total filas: ${rows.length}'
                  : 'Seleccionado: 1 / Total filas: ${rows.length}',
              style: const TextStyle(fontSize: 10, color: Colors.white70),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final assetColumns = <_ToolingColumn>[
      _ToolingColumn(
        label: 'Tipo',
        key: 'asset_type',
        flex: 16,
        value: (row) =>
            row['asset_type'] == 'METAL_MASK' ? 'Metal Mask' : 'Squeegee',
      ),
      _ToolingColumn(
        label: 'No control',
        key: 'control_code',
        flex: 20,
        value: (row) => '${row['control_code'] ?? ''}',
        style: (_) => const TextStyle(
          color: Colors.lightBlueAccent,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
      _ToolingColumn(
        label: 'Ubicación',
        key: 'location_code',
        flex: 17,
        value: (row) => '${row['location_code'] ?? '-'}',
      ),
      _ToolingColumn(
        label: 'No PCB',
        key: 'pcb_no',
        flex: 18,
        value: (row) => _maskField(row, 'pcb_no'),
        style: (row) => TextStyle(
          color: _isMask(row) ? Colors.white : Colors.white38,
          fontSize: 11,
        ),
      ),
      _ToolingColumn(
        label: 'Lado',
        key: 'side',
        flex: 8,
        alignment: Alignment.center,
        value: (row) => _maskField(row, 'side'),
        style: (row) => TextStyle(
          color: !_isMask(row)
              ? Colors.white38
              : '${row['side'] ?? ''}'.toUpperCase() == 'BOT'
                  ? Colors.orangeAccent
                  : Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
      _ToolingColumn(
        label: 'Fecha prod.',
        key: 'production_date_raw',
        flex: 13,
        alignment: Alignment.center,
        value: (row) => _maskField(row, 'production_date_raw'),
        style: (row) => TextStyle(
          color: _isMask(row) ? Colors.white : Colors.white38,
          fontSize: 11,
        ),
      ),
      _ToolingColumn(
        label: 'Array',
        key: 'array_size',
        flex: 8,
        alignment: Alignment.center,
        value: (row) => _maskField(row, 'array_size'),
      ),
      _ToolingColumn(
        label: 'Espesor',
        key: 'thickness_mm',
        flex: 11,
        alignment: Alignment.center,
        value: (row) => _maskField(row, 'thickness_mm'),
        style: (row) => TextStyle(
          color: _isMask(row) ? Colors.white : Colors.white38,
          fontSize: 11,
        ),
      ),
      _ToolingColumn(
        label: 'Estado',
        key: 'lifecycle_status',
        flex: 13,
        alignment: Alignment.center,
        value: (row) => _limitReached(row)
            ? 'BLOQUEADO'
            : '${row['lifecycle_status'] ?? ''}',
        style: (row) {
          final blocked =
              row['lifecycle_status'] != 'ACTIVE' || _limitReached(row);
          return TextStyle(
            color: blocked ? Colors.redAccent : Colors.greenAccent,
            fontSize: 11,
            fontWeight: FontWeight.bold,
          );
        },
      ),
      _ToolingColumn(
        label: 'Usos',
        key: 'use_count',
        flex: 9,
        alignment: Alignment.center,
        value: (row) => '${row['use_count'] ?? 0}',
        style: (row) => TextStyle(
          color: _limitReached(row) ? Colors.orangeAccent : Colors.white,
          fontSize: 11,
          fontWeight: _limitReached(row) ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      _ToolingColumn(
        label: 'Límite',
        key: 'use_limit',
        flex: 9,
        alignment: Alignment.center,
        value: (row) {
          final limit = '${row['use_limit'] ?? ''}';
          return limit.isEmpty || limit == 'null' || limit == '0' ? '-' : limit;
        },
      ),
      _ToolingColumn(
        label: '% Uso',
        key: 'use_ratio',
        flex: 20,
        alignment: Alignment.center,
        value: (row) {
          final limit = int.tryParse('${row['use_limit'] ?? 0}') ?? 0;
          if (limit <= 0) return '-1';
          final used = int.tryParse('${row['use_count'] ?? 0}') ?? 0;
          return (used * 100 / limit).toStringAsFixed(0);
        },
        builder: _useBar,
      ),
      _ToolingColumn(
        label: 'Planes',
        key: 'assignment_count',
        flex: 9,
        alignment: Alignment.center,
        value: (row) => '${row['assignment_count'] ?? 0}',
      ),
      _ToolingColumn(
        label: 'Último uso',
        key: 'last_used_at',
        flex: 19,
        value: (row) => _formatDate(row['last_used_at']),
      ),
    ];

    final assignmentColumns = <_ToolingColumn>[
      _ToolingColumn(
        label: 'Fecha',
        key: 'assigned_at',
        flex: 18,
        value: (row) => _formatDate(row['assigned_at'] ?? row['working_date']),
      ),
      _ToolingColumn(
        label: 'Línea',
        key: 'line_code',
        flex: 8,
        alignment: Alignment.center,
        value: (row) => '${row['line_code'] ?? ''}',
      ),
      _ToolingColumn(
        label: 'Plan / Lote',
        key: 'plan_id',
        flex: 21,
        value: (row) => '${row['plan_id'] ?? ''} / ${row['lot_no'] ?? ''}',
      ),
      _ToolingColumn(
        label: 'Modelo',
        key: 'model_code',
        flex: 17,
        value: (row) => '${row['model_code'] ?? row['part_no'] ?? ''}',
      ),
      _ToolingColumn(
        label: 'Metal Mask',
        key: 'metal_mask_code',
        flex: 16,
        value: (row) => '${row['metal_mask_code'] ?? ''}',
        style: (_) => const TextStyle(
          color: Colors.lightBlueAccent,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
      _ToolingColumn(
        label: 'Squeegee',
        key: 'squeegee_code',
        flex: 16,
        value: (row) => '${row['squeegee_code'] ?? ''}',
      ),
      _ToolingColumn(
        label: 'Usos (PLAN)',
        key: 'planned_uses',
        flex: 12,
        alignment: Alignment.center,
        value: (row) => '${row['planned_uses'] ?? 0}',
      ),
    ];

    return ColoredBox(
      color: AppColors.panelBackground,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          children: [
            Container(
              color: AppColors.panelBackground,
              padding: const EdgeInsets.fromLTRB(0, 0, 0, 4),
              child: Row(
                children: [
                  _viewSelector(),
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                    decoration: BoxDecoration(
                      border: Border.all(color: AppColors.border, width: 1),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('Tipo', style: TextStyle(fontSize: 11)),
                        const SizedBox(width: 4),
                        SizedBox(
                          width: 130,
                          child: DropdownButtonFormField<String>(
                            initialValue: _type,
                            dropdownColor: AppColors.panelBackground,
                            style: const TextStyle(
                                color: Colors.white, fontSize: 11),
                            decoration: _fieldDecoration(),
                            items: const [
                              DropdownMenuItem(value: '', child: Text('Todos')),
                              DropdownMenuItem(
                                value: 'METAL_MASK',
                                child: Text('Metal Mask'),
                              ),
                              DropdownMenuItem(
                                value: 'SQUEEGEE',
                                child: Text('Squeegee'),
                              ),
                            ],
                            onChanged: (value) {
                              setState(() => _type = value ?? '');
                              _load();
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Text('Estado', style: TextStyle(fontSize: 11)),
                        const SizedBox(width: 4),
                        SizedBox(
                          width: 140,
                          child: DropdownButtonFormField<String>(
                            initialValue: _status,
                            dropdownColor: AppColors.panelBackground,
                            style: const TextStyle(
                                color: Colors.white, fontSize: 11),
                            decoration: _fieldDecoration(),
                            items: [
                              const DropdownMenuItem(
                                  value: '', child: Text('Todos')),
                              ..._statuses.map(
                                (value) => DropdownMenuItem(
                                    value: value, child: Text(value)),
                              ),
                              const DropdownMenuItem(
                                value: 'BLOCKED',
                                child: Text('Límite alcanzado'),
                              ),
                            ],
                            onChanged: (value) {
                              setState(() => _status = value ?? '');
                              _load();
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Text('Ubicación', style: TextStyle(fontSize: 11)),
                        const SizedBox(width: 4),
                        SizedBox(
                          width: 120,
                          child: TextField(
                            controller: _locationController,
                            onSubmitted: (_) => _load(),
                            style: const TextStyle(
                                color: Colors.white, fontSize: 11),
                            decoration: _fieldDecoration(),
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Text('No control', style: TextStyle(fontSize: 11)),
                        const SizedBox(width: 4),
                        SizedBox(
                          width: 180,
                          child: TextField(
                            controller: _searchController,
                            focusNode: _searchFocus,
                            onSubmitted: (_) => _load(),
                            style: const TextStyle(
                                color: Colors.white, fontSize: 11),
                            decoration: _fieldDecoration(),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  SizedBox(
                    height: 26,
                    child: ElevatedButton(
                      onPressed: _load,
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 18),
                        backgroundColor: AppColors.buttonSearch,
                      ),
                      child: const Text('Buscar',
                          style: TextStyle(fontSize: 11)),
                    ),
                  ),
                  const SizedBox(width: 6),
                  SizedBox(
                    height: 26,
                    child: ElevatedButton(
                      onPressed: () => _assetDialog(null),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 18),
                        backgroundColor: AppColors.buttonExcel,
                      ),
                      child: const Text('Nuevo',
                          style: TextStyle(fontSize: 11)),
                    ),
                  ),
                  const SizedBox(width: 6),
                  SizedBox(
                    height: 26,
                    child: ElevatedButton(
                      onPressed: _editSelectedAsset,
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 18),
                        backgroundColor: AppColors.buttonSearch,
                      ),
                      child: const Text('Editar',
                          style: TextStyle(fontSize: 11)),
                    ),
                  ),
                  if (_view == 1 && _historyCode != null) ...[
                    const SizedBox(width: 6),
                    SizedBox(
                      height: 26,
                      child: ElevatedButton.icon(
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _selectedAsset = null);
                          _loadHistory(null);
                        },
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          backgroundColor: AppColors.buttonExcel,
                        ),
                        icon: const Icon(Icons.clear, size: 14),
                        label: const Text('Ver todo',
                            style: TextStyle(fontSize: 11)),
                      ),
                    ),
                  ],
                  const SizedBox(width: 4),
                  IconButton(
                    onPressed: _load,
                    icon: const Icon(Icons.refresh, color: Colors.white70),
                    tooltip: 'Actualizar',
                  ),
                ],
              ),
            ),
            if (_error != null)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(top: 6),
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                color: Colors.red.withValues(alpha: 0.18),
                child: Text(
                  _error!,
                  style: const TextStyle(color: Colors.redAccent, fontSize: 11),
                ),
              ),
            if (_loading)
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: LinearProgressIndicator(minHeight: 2),
              ),
            const SizedBox(height: 6),
            if (_view == 0)
              Expanded(
                child: _buildSection(
                  title: 'Herramentales registrados',
                icon: Icons.inventory_2_outlined,
                rows: _assets,
                columns: assetColumns,
                sortColumn: _assetSortColumn,
                sortAscending: _assetSortAscending,
                rowKey: (row) => '${row['control_code'] ?? ''}',
                selectedKey: _selectedAsset,
                onSelected: (key) {
                  final next = _selectedAsset == key ? null : key;
                  setState(() => _selectedAsset = next);
                  _loadHistory(next);
                },
                  filters: _assetFilters,
                  onSort: (key) {
                    setState(() {
                      if (_assetSortColumn == key) {
                        _assetSortAscending = !_assetSortAscending;
                      } else {
                        _assetSortColumn = key;
                        _assetSortAscending = true;
                      }
                    });
                  },
                ),
              ),
            if (_view == 1)
              Expanded(
                child: _buildSection(
                title: _historyCode == null
                    ? 'Historial de uso — todos los herramentales'
                    : 'Historial de uso — $_historyCode'
                        '  ·  ${_historyTotals['eventos'] ?? 0} usos'
                        '  ·  ${_historyTotals['usos'] ?? 0} impresiones'
                        '${_historyTotals['desde'] == null ? '' : '  ·  desde ${_formatDate(_historyTotals['desde']).split(' ').first}'}',
                icon: Icons.history,
                rows: _assignments,
                columns: assignmentColumns,
                sortColumn: _assignmentSortColumn,
                sortAscending: _assignmentSortAscending,
                rowKey: (row) => '${row['event_id'] ?? row['id'] ?? ''}',
                selectedKey: _selectedAssignment,
                onSelected: (key) => setState(() => _selectedAssignment = key),
                  filters: _historyFilters,
                  onSort: (key) {
                    setState(() {
                      if (_assignmentSortColumn == key) {
                        _assignmentSortAscending = !_assignmentSortAscending;
                      } else {
                        _assignmentSortColumn = key;
                        _assignmentSortAscending = true;
                      }
                    });
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ToolingColumn {
  final String label;
  final String key;
  final int flex;
  final String Function(Map<String, dynamic>) value;
  final Alignment alignment;
  final TextStyle Function(Map<String, dynamic>)? style;

  /// Cuando se define, la celda dibuja este widget en lugar del texto plano.
  /// `value` se sigue usando para ordenar la columna.
  final Widget Function(Map<String, dynamic>)? builder;

  const _ToolingColumn({
    required this.label,
    required this.key,
    required this.flex,
    required this.value,
    this.alignment = Alignment.centerLeft,
    this.style,
    this.builder,
  });
}
