import 'package:flutter/material.dart';
import 'package:material_warehousing_flutter/core/localization/app_translations.dart';
import 'package:material_warehousing_flutter/core/services/api_service.dart';
import 'package:material_warehousing_flutter/core/services/auth_service.dart';
import 'package:material_warehousing_flutter/core/theme/app_colors.dart';

class MobilePcbInventoryScreen extends StatefulWidget {
  final LanguageProvider languageProvider;

  const MobilePcbInventoryScreen({
    super.key,
    required this.languageProvider,
  });

  @override
  State<MobilePcbInventoryScreen> createState() =>
      _MobilePcbInventoryScreenState();
}

class _MobilePcbInventoryScreenState extends State<MobilePcbInventoryScreen> {
  final TextEditingController _searchController = TextEditingController();

  bool _isLoading = false;
  String _selectedProceso = 'ALL';
  String _selectedArea = 'ALL';
  List<Map<String, dynamic>> _rows = [];
  int _totalStock = 0;

  static const List<String> _procesos = ['ALL', 'SMD', 'IMD', 'ASSY'];
  static const List<String> _areas = ['ALL', 'INVENTARIO', 'REPARACION'];

  String tr(String key) => widget.languageProvider.tr(key);

  @override
  void initState() {
    super.initState();
    _loadStock();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadStock() async {
    setState(() => _isLoading = true);
    final result = await ApiService.getPcbStockSummary(
      numeroParte: _searchController.text.trim(),
      proceso: _selectedProceso,
      area: _selectedArea,
      includeZeroStock: false,
    );
    if (!mounted) return;
    final data = (result['data'] as List? ?? [])
        .whereType<Map<String, dynamic>>()
        .toList();
    setState(() {
      _rows = data;
      _totalStock = NumberParser.toInt(result['total_stock']);
      _isLoading = false;
    });
  }

  void _clearSearch() {
    _searchController.clear();
    _loadStock();
  }

  @override
  Widget build(BuildContext context) {
    if (!AuthService.canViewPcbInventario) {
      return _buildNoPermissionScreen();
    }

    return Column(
      children: [
        _buildSearchAndFilters(),
        _buildSummaryBar(),
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _buildList(),
        ),
      ],
    );
  }

  Widget _buildNoPermissionScreen() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.lock,
              size: 64, color: Colors.white.withValues(alpha: 0.3)),
          const SizedBox(height: 16),
          Text(
            tr('no_permission_mobile'),
            style: const TextStyle(color: Colors.white54, fontSize: 16),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchAndFilters() {
    return Container(
      padding: const EdgeInsets.all(12),
      color: const Color(0xFF252A3C),
      child: Column(
        children: [
          TextField(
            controller: _searchController,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: tr('pcb_search_part'),
              hintStyle: const TextStyle(color: Colors.white38),
              prefixIcon: const Icon(Icons.search, color: Colors.white54),
              suffixIcon: _searchController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, color: Colors.white54),
                      onPressed: _clearSearch,
                    )
                  : null,
              filled: true,
              fillColor: const Color(0xFF1A1E2C),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            ),
            textCapitalization: TextCapitalization.characters,
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _loadStock(),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _buildFilterDropdown(
                  value: _selectedProceso,
                  items: _procesos,
                  icon: Icons.precision_manufacturing,
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() => _selectedProceso = value);
                    _loadStock();
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildFilterDropdown(
                  value: _selectedArea,
                  items: _areas,
                  icon: Icons.category,
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() => _selectedArea = value);
                    _loadStock();
                  },
                ),
              ),
              const SizedBox(width: 8),
              Container(
                decoration: BoxDecoration(
                  color: AppColors.headerTab,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: IconButton(
                  icon: const Icon(Icons.refresh, color: Colors.white),
                  onPressed: _loadStock,
                  tooltip: tr('refresh'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFilterDropdown({
    required String value,
    required List<String> items,
    required IconData icon,
    required ValueChanged<String?> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1E2C),
        borderRadius: BorderRadius.circular(12),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          dropdownColor: const Color(0xFF252A3C),
          isExpanded: true,
          iconEnabledColor: Colors.white70,
          style: const TextStyle(color: Colors.white, fontSize: 13),
          items: items
              .map(
                (item) => DropdownMenuItem(
                  value: item,
                  child: Row(
                    children: [
                      Icon(icon, color: Colors.white54, size: 16),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          item == 'ALL' ? tr('pcb_all') : item,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              )
              .toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }

  Widget _buildSummaryBar() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: const Color(0xFF1A1E2C),
      child: Row(
        children: [
          const Icon(Icons.developer_board, color: Colors.cyan, size: 18),
          const SizedBox(width: 8),
          Text(
            '${tr('pcb_stock_actual')}: $_totalStock',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          Text(
            '${_rows.length} ${tr('records')}',
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildList() {
    if (_rows.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.developer_board_off,
              size: 64,
              color: Colors.white.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 16),
            Text(
              tr('no_inventory_available'),
              style: const TextStyle(color: Colors.white54, fontSize: 16),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadStock,
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: _rows.length,
        itemBuilder: (context, index) => _buildCard(_rows[index]),
      ),
    );
  }

  Widget _buildCard(Map<String, dynamic> row) {
    final partNo = row['pcb_part_no']?.toString() ?? '-';
    final modelo = row['modelo']?.toString() ?? 'N/A';
    final proceso = row['proceso']?.toString() ?? '-';
    final area = row['area']?.toString() ?? '-';
    final entrada = NumberParser.toInt(row['total_entrada']);
    final salida = NumberParser.toInt(row['total_salida']);
    final scrap = NumberParser.toInt(row['total_scrap']);
    final stock = NumberParser.toInt(row['stock_actual']);

    return Card(
      color: const Color(0xFF252A3C),
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    partNo,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: _stockColor(stock).withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '$stock',
                    style: TextStyle(
                      color: _stockColor(stock),
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              modelo,
              style: const TextStyle(color: Colors.white60, fontSize: 13),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                _buildChip(Icons.precision_manufacturing, proceso),
                _buildChip(Icons.category, area),
                _buildChip(Icons.login, '${tr('pcb_tab_entrada')}: $entrada'),
                _buildChip(Icons.logout, '${tr('pcb_tab_salida')}: $salida'),
                if (scrap > 0)
                  _buildChip(
                      Icons.delete_outline, '${tr('pcb_tab_scrap')}: $scrap'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChip(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white54, size: 14),
          const SizedBox(width: 4),
          Text(
            text,
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Color _stockColor(int stock) {
    if (stock <= 0) return Colors.redAccent;
    if (stock <= 5) return Colors.orangeAccent;
    return Colors.greenAccent;
  }
}

class NumberParser {
  static int toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.round();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }
}
