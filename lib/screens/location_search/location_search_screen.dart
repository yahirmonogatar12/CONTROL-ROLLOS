import 'package:flutter/material.dart';
import 'package:material_warehousing_flutter/core/localization/app_translations.dart';
import 'package:material_warehousing_flutter/core/services/api_service.dart';
import 'package:material_warehousing_flutter/core/theme/app_colors.dart';
import 'package:material_warehousing_flutter/core/widgets/field_decoration.dart';

/// Pantalla de Busqueda de Ubicacion para PC
/// - Carga TODOS los materiales al inicio
/// - Autocomplete local: filtra conforme escribes
/// - Click en sugerencia → busca ubicaciones en servidor
/// - Muestra ubicacion_rollos como ubicacion principal
class LocationSearchScreen extends StatefulWidget {
  final LanguageProvider languageProvider;

  const LocationSearchScreen({
    super.key,
    required this.languageProvider,
  });

  @override
  State<LocationSearchScreen> createState() => LocationSearchScreenState();
}

class LocationSearchScreenState extends State<LocationSearchScreen> {
  final TextEditingController _scanController = TextEditingController();
  final FocusNode _scanFocusNode = FocusNode();
  final GlobalKey _fieldKey = GlobalKey();

  // Lista completa de materiales cargados al inicio
  List<Map<String, dynamic>> _allMateriales = [];
  bool _materialesLoaded = false;

  // Sugerencias filtradas localmente
  List<Map<String, dynamic>> _filtered = [];
  bool _showDropdown = false;

  bool _isSearching = false;
  String? _lastSearchTerm;

  // Resultados confirmados y seleccion
  List<Map<String, dynamic>> _results = [];
  Map<String, dynamic>? _selectedResult;

  String tr(String key) => widget.languageProvider.tr(key);

  @override
  void initState() {
    super.initState();
    _loadMateriales();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scanFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _scanController.dispose();
    _scanFocusNode.dispose();
    super.dispose();
  }

  void requestScanFocus() {
    _scanFocusNode.requestFocus();
  }

  /// Recargar materiales desde el botón de refresh del tab principal
  Future<void> reloadMateriales() async {
    await _loadMateriales();
  }

  /// Cargar todos los materiales una sola vez al inicio
  Future<void> _loadMateriales() async {
    try {
      final data = await ApiService.getMateriales();
      if (!mounted) return;
      setState(() {
        _allMateriales = data;
        _materialesLoaded = true;
      });
    } catch (e) {
      debugPrint('Error cargando materiales: $e');
    }
  }

  /// Filtrar localmente conforme escribe el usuario
  void _onTextChanged(String text) {
    final query = text.trim().toUpperCase();

    if (query.length < 2) {
      setState(() {
        _filtered = [];
        _showDropdown = false;
      });
      return;
    }

    // Si tiene '-' es barcode, no filtrar
    if (query.contains('-')) {
      setState(() {
        _filtered = [];
        _showDropdown = false;
      });
      return;
    }

    // Filtrar localmente
    final matches = _allMateriales.where((m) {
      final np = (m['numero_parte'] ?? '').toString().toUpperCase();
      return np.contains(query);
    }).take(25).toList();

    setState(() {
      _filtered = matches;
      _showDropdown = matches.isNotEmpty;
    });
  }

  /// Click en una sugerencia del dropdown → buscar ubicaciones en servidor
  Future<void> _selectSuggestion(Map<String, dynamic> item) async {
    final np = item['numero_parte']?.toString() ?? '';
    _scanController.clear();

    setState(() {
      _showDropdown = false;
      _filtered = [];
      _isSearching = true;
      _lastSearchTerm = np;
    });

    try {
      final results = await ApiService.getLocationByPartNumber(np);
      setState(() {
        _results = results;
        _selectedResult = results.isNotEmpty ? results[0] : null;
      });
    } catch (e) {
      // Fallback: usar datos del catalogo local
      setState(() {
        _results = [item];
        _selectedResult = item;
      });
    } finally {
      setState(() => _isSearching = false);
      _scanFocusNode.requestFocus();
    }
  }

  /// Busqueda al presionar Enter (barcode scanner o texto completo)
  Future<void> _onScan(String code) async {
    final input = code.trim().toUpperCase();
    if (input.isEmpty) return;

    _scanController.clear();

    String nparte = input;
    if (input.contains('-')) {
      nparte = input.split('-')[0];
    }

    setState(() {
      _isSearching = true;
      _showDropdown = false;
      _filtered = [];
      _lastSearchTerm = nparte;
    });

    try {
      final results = await ApiService.getLocationByPartNumber(input);
      setState(() {
        _results = results;
        _selectedResult = results.isNotEmpty ? results[0] : null;
      });
    } catch (e) {
      setState(() {
        _results = [];
        _selectedResult = null;
      });
    } finally {
      setState(() => _isSearching = false);
      _scanFocusNode.requestFocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Column(
          children: [
            _buildTopSection(),
            Expanded(child: _buildResultsGrid()),
          ],
        ),
        // ===== DROPDOWN AUTOCOMPLETE encima de todo =====
        if (_showDropdown && _filtered.isNotEmpty) _buildAutocompleteDropdown(),
      ],
    );
  }

  /// Dropdown posicionado debajo del TextField
  Widget _buildAutocompleteDropdown() {
    final renderBox = _fieldKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return const SizedBox.shrink();

    final fieldPos = renderBox.localToGlobal(Offset.zero);
    final stackRenderBox = context.findRenderObject() as RenderBox?;
    if (stackRenderBox == null) return const SizedBox.shrink();

    final stackPos = stackRenderBox.localToGlobal(Offset.zero);
    final relativeTop = fieldPos.dy - stackPos.dy + renderBox.size.height + 4;
    final relativeLeft = fieldPos.dx - stackPos.dx;
    final fieldWidth = renderBox.size.width;

    return Positioned(
      top: relativeTop,
      left: relativeLeft,
      width: fieldWidth,
      child: Material(
        elevation: 12,
        borderRadius: BorderRadius.circular(6),
        color: const Color(0xFF1A2640),
        child: Container(
          constraints: const BoxConstraints(maxHeight: 320),
          decoration: BoxDecoration(
            border: Border.all(
                color: AppColors.headerTab.withValues(alpha: 0.6), width: 1.5),
            borderRadius: BorderRadius.circular(6),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(5),
            child: ListView.builder(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              itemCount: _filtered.length,
              itemBuilder: (context, index) {
                final item = _filtered[index];
                final np = item['numero_parte']?.toString() ?? '';
                final spec = (item['especificacion_material'] ?? item['especificacion'] ?? '').toString();
                final ubic = (item['ubicacion_rollos'] ?? '').toString();
                final isOdd = index % 2 == 1;

                return InkWell(
                  onTap: () => _selectSuggestion(item),
                  hoverColor: AppColors.headerTab.withValues(alpha: 0.15),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                    color: isOdd
                        ? Colors.white.withValues(alpha: 0.04)
                        : Colors.transparent,
                    child: Row(
                      children: [
                        // Numero de parte
                        SizedBox(
                          width: 150,
                          child: Text(
                            np,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              fontFamily: 'Consolas',
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        // Especificacion
                        Expanded(
                          child: Text(
                            spec,
                            style: const TextStyle(
                                color: Colors.white54, fontSize: 12),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 10),
                        // Ubicacion rollos badge
                        if (ubic.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: AppColors.headerTab.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                  color:
                                      AppColors.headerTab.withValues(alpha: 0.4)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.location_on,
                                    size: 12, color: AppColors.headerTab),
                                const SizedBox(width: 4),
                                Text(
                                  ubic,
                                  style: const TextStyle(
                                    color: AppColors.headerTab,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTopSection() {
    final hasResult = _selectedResult != null;
    final ubicacionRollos =
        _selectedResult?['ubicacion_rollos']?.toString() ?? '';
    final ubicacionesRegistradas =
        (_selectedResult?['ubicaciones_registradas'] as List?)?.cast<String>() ??
            [];
    final numeroParte =
        _selectedResult?['numero_parte']?.toString() ?? '';
    final especificacion =
        (_selectedResult?['especificacion'] ?? _selectedResult?['especificacion_material'] ?? '')
            .toString();
    final vendedor = _selectedResult?['vendedor']?.toString() ?? '';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A2332),
        border: Border(bottom: BorderSide(color: AppColors.border, width: 1)),
      ),
      child: Column(
        children: [
          // ---- Campo de escaneo ----
          Row(
            children: [
              const Icon(Icons.qr_code_scanner,
                  color: AppColors.headerTab, size: 28),
              const SizedBox(width: 12),
              Expanded(
                child: SizedBox(
                  key: _fieldKey,
                  height: 44,
                  child: TextField(
                    controller: _scanController,
                    focusNode: _scanFocusNode,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                    decoration: fieldDecoration(
                      hintText: _materialesLoaded
                          ? tr('scan_or_enter_part_number')
                          : 'Cargando materiales...',
                    ).copyWith(
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      hintStyle:
                          const TextStyle(color: Colors.white30, fontSize: 14),
                      suffixIcon: _isSearching || !_materialesLoaded
                          ? const Padding(
                              padding: EdgeInsets.all(10),
                              child: SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: AppColors.headerTab,
                                ),
                              ),
                            )
                          : null,
                    ),
                    onChanged: _onTextChanged,
                    onSubmitted: _onScan,
                  ),
                ),
              ),
              if (_results.isNotEmpty) ...[
                const SizedBox(width: 12),
                SizedBox(
                  height: 44,
                  child: ElevatedButton.icon(
                    onPressed: () => setState(() {
                      _results = [];
                      _selectedResult = null;
                      _lastSearchTerm = null;
                    }),
                    icon: const Icon(Icons.clear_all, size: 18),
                    label: Text(tr('clear_all'),
                        style: const TextStyle(fontSize: 13)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange.withValues(alpha: 0.8),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 16),
          // ---- Resultado grande ----
          if (!hasResult &&
              !_isSearching &&
              _results.isEmpty &&
              _lastSearchTerm == null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 32),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.03),
                borderRadius: BorderRadius.circular(8),
                border:
                    Border.all(color: Colors.white.withValues(alpha: 0.08)),
              ),
              child: Column(
                children: [
                  const Icon(Icons.location_searching,
                      color: Colors.white24, size: 48),
                  const SizedBox(height: 12),
                  Text(
                    tr('scan_part_number_to_search'),
                    style:
                        const TextStyle(color: Colors.white38, fontSize: 14),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'EAE63746601  o  EAE63746601-202601230002',
                    style: TextStyle(
                      color: AppColors.headerTab.withValues(alpha: 0.5),
                      fontSize: 12,
                      fontFamily: 'Consolas',
                    ),
                  ),
                ],
              ),
            )
          else if (!hasResult &&
              _results.isEmpty &&
              !_isSearching &&
              _lastSearchTerm != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 24),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
                border:
                    Border.all(color: Colors.red.withValues(alpha: 0.3)),
              ),
              child: Column(
                children: [
                  const Icon(Icons.search_off, color: Colors.red, size: 36),
                  const SizedBox(height: 8),
                  Text(
                    '${tr('part_not_found')}: $_lastSearchTerm',
                    style: const TextStyle(
                      color: Colors.red,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            )
          else if (hasResult)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // === UBICACION DE ROLLOS (principal, grande) ===
                Expanded(
                  flex: 2,
                  child: Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: ubicacionRollos.isNotEmpty
                            ? [
                                AppColors.headerTab.withValues(alpha: 0.25),
                                AppColors.headerTab.withValues(alpha: 0.1),
                              ]
                            : [
                                Colors.grey.withValues(alpha: 0.15),
                                Colors.grey.withValues(alpha: 0.05),
                              ],
                      ),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: ubicacionRollos.isNotEmpty
                            ? AppColors.headerTab.withValues(alpha: 0.6)
                            : Colors.grey.withValues(alpha: 0.3),
                        width: 2,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Header info
                        Row(
                          children: [
                            Icon(Icons.inventory_2,
                                color:
                                    AppColors.headerTab.withValues(alpha: 0.7),
                                size: 18),
                            const SizedBox(width: 8),
                            Text(
                              numeroParte,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            if (especificacion.isNotEmpty) ...[
                              const SizedBox(width: 12),
                              Flexible(
                                child: Text(
                                  especificacion,
                                  style: const TextStyle(
                                      color: Colors.white54,
                                      fontSize: 12),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                            if (vendedor.isNotEmpty) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.blue.withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(vendedor,
                                    style: const TextStyle(
                                        color: Colors.blue, fontSize: 11)),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          tr('loc_search_rollos'),
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.5),
                            fontSize: 11,
                          ),
                        ),
                        const SizedBox(height: 4),
                        // UBICACION ROLLOS en grande
                        Row(
                          children: [
                            Icon(
                              Icons.location_on,
                              color: ubicacionRollos.isNotEmpty
                                  ? AppColors.headerTab
                                  : Colors.white24,
                              size: 36,
                            ),
                            const SizedBox(width: 10),
                            Text(
                              ubicacionRollos.isNotEmpty
                                  ? ubicacionRollos
                                  : tr('no_location'),
                              style: TextStyle(
                                color: ubicacionRollos.isNotEmpty
                                    ? Colors.white
                                    : Colors.white38,
                                fontSize:
                                    ubicacionRollos.isNotEmpty ? 40 : 18,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 2,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // === UBICACIONES REGISTRADAS ===
                Expanded(
                  flex: 2,
                  child: Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: ubicacionesRegistradas.isNotEmpty
                          ? Colors.purple.withValues(alpha: 0.15)
                          : Colors.white.withValues(alpha: 0.03),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: ubicacionesRegistradas.isNotEmpty
                            ? Colors.purple.withValues(alpha: 0.5)
                            : Colors.white.withValues(alpha: 0.1),
                        width: 2,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.history,
                              color: ubicacionesRegistradas.isNotEmpty
                                  ? const Color(0xFFCE93D8)
                                  : Colors.white38,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              tr('registered_locations'),
                              style: TextStyle(
                                color: ubicacionesRegistradas.isNotEmpty
                                    ? Colors.white70
                                    : Colors.white38,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        if (ubicacionesRegistradas.isEmpty)
                          Row(
                            children: [
                              Icon(
                                Icons.location_off,
                                color: Colors.white24,
                                size: 36,
                              ),
                              const SizedBox(width: 10),
                              Text(tr('no_location'),
                                  style: const TextStyle(
                                      color: Colors.white38, fontSize: 18)),
                            ],
                          )
                        else
                          Wrap(
                            spacing: 8,
                            runSpacing: 6,
                            children: ubicacionesRegistradas
                                .map((loc) => Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 14, vertical: 8),
                                      decoration: BoxDecoration(
                                        color: Colors.purple
                                            .withValues(alpha: 0.2),
                                        borderRadius:
                                            BorderRadius.circular(6),
                                        border: Border.all(
                                            color: Colors.purple
                                                .withValues(alpha: 0.4)),
                                      ),
                                      child: Text(
                                        loc,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 28,
                                          fontWeight: FontWeight.bold,
                                          letterSpacing: 1,
                                        ),
                                      ),
                                    ))
                                .toList(),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  /// Grid inferior con coincidencias
  Widget _buildResultsGrid() {
    return Container(
      color: AppColors.panelBackground,
      child: Column(
        children: [
          // Tab header
          Container(
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.subPanelBackground,
              border: Border(bottom: BorderSide(color: AppColors.border)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: AppColors.headerTab.withValues(alpha: 0.2),
                    border: Border(
                        bottom: BorderSide(
                            color: AppColors.headerTab, width: 2)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.list,
                          size: 16, color: AppColors.headerTab),
                      const SizedBox(width: 6),
                      Text(
                        _results.isEmpty
                            ? tr('search_history')
                            : '${tr('result_for')}: $_lastSearchTerm',
                        style: const TextStyle(
                          color: AppColors.headerTab,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (_results.isNotEmpty) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.headerTab,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '${_results.length}',
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const Spacer(),
              ],
            ),
          ),
          // Grid header
          Container(
            height: 30,
            color: AppColors.gridHeader,
            child: Row(
              children: [
                _gridHeaderCell(tr('part_number'), flex: 3),
                _gridHeaderCell(tr('loc_search_rollos'), flex: 2),
                _gridHeaderCell(tr('loc_search_material'), flex: 2),
                _gridHeaderCell(tr('registered_locations'), flex: 3),
                _gridHeaderCell(tr('vendor'), flex: 2),
              ],
            ),
          ),
          // Grid body
          Expanded(
            child: _results.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.search_off,
                            color: Colors.white24, size: 40),
                        const SizedBox(height: 10),
                        Text(
                          tr('no_search_history'),
                          style: const TextStyle(
                              color: Colors.white38, fontSize: 13),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    itemCount: _results.length,
                    itemBuilder: (context, index) {
                      final item = _results[index];
                      final isOdd = index % 2 == 1;
                      final isSelected = _selectedResult != null &&
                          _selectedResult!['numero_parte'] ==
                              item['numero_parte'];

                      return InkWell(
                        onTap: () {
                          setState(() => _selectedResult = item);
                          _scanFocusNode.requestFocus();
                        },
                        child: Container(
                          height: 32,
                          decoration: BoxDecoration(
                            color: isSelected
                                ? AppColors.gridSelectedRow
                                : isOdd
                                    ? AppColors.gridRowOdd
                                    : AppColors.gridRowEven,
                            border: Border(
                              left: BorderSide(
                                color: isSelected
                                    ? AppColors.headerTab
                                    : Colors.transparent,
                                width: 3,
                              ),
                            ),
                          ),
                          child: Row(
                            children: [
                              _gridCell(
                                  item['numero_parte']?.toString() ?? '',
                                  flex: 3,
                                  bold: true),
                              _gridCell(
                                item['ubicacion_rollos']?.toString() ?? '-',
                                flex: 2,
                                color: (item['ubicacion_rollos']
                                                ?.toString() ??
                                            '')
                                        .isNotEmpty
                                    ? AppColors.headerTab
                                    : Colors.white38,
                              ),
                              _gridCell(
                                item['ubicacion_material']?.toString() ??
                                    '-',
                                flex: 2,
                                color: (item['ubicacion_material']
                                                ?.toString() ??
                                            '')
                                        .isNotEmpty
                                    ? Colors.blue
                                    : Colors.white38,
                              ),
                              _gridCell(
                                (item['ubicaciones_registradas'] as List?)
                                        ?.join(', ') ??
                                    '-',
                                flex: 3,
                                color: (item['ubicaciones_registradas']
                                                as List?)
                                            ?.isNotEmpty ==
                                        true
                                    ? const Color(0xFFCE93D8)
                                    : Colors.white38,
                              ),
                              _gridCell(
                                  item['vendedor']?.toString() ?? '-',
                                  flex: 2),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _gridHeaderCell(String text, {int flex = 1}) {
    return Expanded(
      flex: flex,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        alignment: Alignment.centerLeft,
        child: Text(
          text,
          style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.bold),
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }

  Widget _gridCell(String text,
      {int flex = 1, bool bold = false, Color? color}) {
    return Expanded(
      flex: flex,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        alignment: Alignment.centerLeft,
        child: Text(
          text,
          style: TextStyle(
            color: color ?? Colors.white70,
            fontSize: 11,
            fontWeight: bold ? FontWeight.bold : FontWeight.normal,
          ),
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}
