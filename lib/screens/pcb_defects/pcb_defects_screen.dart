import 'package:flutter/material.dart';
import 'package:material_warehousing_flutter/core/localization/app_translations.dart';
import 'package:material_warehousing_flutter/core/services/api_service.dart';
import 'package:material_warehousing_flutter/core/services/auth_service.dart';
import 'package:material_warehousing_flutter/core/theme/app_colors.dart';
import 'package:material_warehousing_flutter/core/widgets/field_decoration.dart';

class PcbDefectsScreen extends StatefulWidget {
  final LanguageProvider languageProvider;

  const PcbDefectsScreen({super.key, required this.languageProvider});

  @override
  State<PcbDefectsScreen> createState() => _PcbDefectsScreenState();
}

class _PcbDefectsScreenState extends State<PcbDefectsScreen> {
  final TextEditingController _defectController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();

  List<Map<String, dynamic>> _defects = [];
  bool _isLoading = false;
  String? _statusMessage;
  bool _statusIsError = false;

  String tr(String key) => widget.languageProvider.tr(key);

  @override
  void initState() {
    super.initState();
    _loadDefects();
  }

  @override
  void dispose() {
    _defectController.dispose();
    _descriptionController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> get _filteredDefects {
    final search = _searchController.text.trim().toUpperCase();
    if (search.isEmpty) return _defects;
    return _defects.where((row) {
      final name = (row['defect_name'] ?? '').toString().toUpperCase();
      final description = (row['description'] ?? '').toString().toUpperCase();
      return name.contains(search) || description.contains(search);
    }).toList();
  }

  Future<void> _loadDefects() async {
    setState(() => _isLoading = true);
    final data = await ApiService.getPcbDefects();
    if (!mounted) return;
    setState(() {
      _defects = data;
      _isLoading = false;
    });
  }

  Future<void> _createDefect() async {
    final name = _defectController.text.trim();
    if (name.isEmpty || !AuthService.canWritePcbInventory) return;

    setState(() {
      _isLoading = true;
      _statusMessage = null;
    });

    final result = await ApiService.createPcbDefect(
      defectName: name,
      description: _descriptionController.text.trim().isNotEmpty
          ? _descriptionController.text.trim()
          : null,
      createdBy: AuthService.currentUser?.nombreCompleto,
    );

    if (!mounted) return;
    if (result['success'] == true) {
      _defectController.clear();
      _descriptionController.clear();
      _statusMessage = tr('pcb_defect_saved');
      _statusIsError = false;
      await _loadDefects();
    } else {
      setState(() {
        _statusMessage = result['message'] ?? tr('pcb_scan_error');
        _statusIsError = true;
        _isLoading = false;
      });
    }
  }

  Future<void> _deleteDefect(Map<String, dynamic> row) async {
    if (!AuthService.canWritePcbInventory) return;
    final id = row['id'];
    if (id is! num) return;

    final result = await ApiService.deletePcbDefect(id.toInt());
    if (!mounted) return;
    if (result['success'] == true) {
      setState(() {
        _statusMessage = tr('pcb_defect_deleted');
        _statusIsError = false;
      });
      await _loadDefects();
    } else {
      setState(() {
        _statusMessage = result['message'] ?? tr('pcb_scan_error');
        _statusIsError = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = _filteredDefects;
    return Container(
      color: AppColors.gridBackground,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            color: AppColors.panelBackground,
            child: Column(
              children: [
                Row(
                  children: [
                    SizedBox(
                      width: 260,
                      child: TextFormField(
                        controller: _defectController,
                        decoration: fieldDecoration().copyWith(
                          labelText: tr('pcb_defect_type'),
                          labelStyle: const TextStyle(color: Colors.white54),
                        ),
                        style:
                            const TextStyle(color: Colors.white, fontSize: 13),
                        textCapitalization: TextCapitalization.characters,
                        enabled: AuthService.canWritePcbInventory,
                        onFieldSubmitted: (_) => _createDefect(),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextFormField(
                        controller: _descriptionController,
                        decoration: fieldDecoration().copyWith(
                          labelText: tr('description'),
                          labelStyle: const TextStyle(color: Colors.white54),
                        ),
                        style:
                            const TextStyle(color: Colors.white, fontSize: 13),
                        enabled: AuthService.canWritePcbInventory,
                        onFieldSubmitted: (_) => _createDefect(),
                      ),
                    ),
                    const SizedBox(width: 10),
                    SizedBox(
                      height: 36,
                      child: ElevatedButton.icon(
                        onPressed:
                            AuthService.canWritePcbInventory && !_isLoading
                                ? _createDefect
                                : null,
                        icon: const Icon(Icons.add, size: 16),
                        label: Text(tr('add'),
                            style: const TextStyle(fontSize: 12)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    SizedBox(
                      width: 220,
                      child: TextFormField(
                        controller: _searchController,
                        decoration: fieldDecoration().copyWith(
                          hintText: tr('search'),
                          hintStyle: const TextStyle(color: Colors.white38),
                          prefixIcon: const Icon(Icons.search,
                              size: 16, color: Colors.white54),
                          prefixIconConstraints:
                              const BoxConstraints(minWidth: 30, minHeight: 20),
                        ),
                        style:
                            const TextStyle(color: Colors.white, fontSize: 13),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    IconButton(
                      onPressed: _loadDefects,
                      icon: const Icon(Icons.refresh, color: Colors.white70),
                      tooltip: tr('pcb_refresh'),
                    ),
                  ],
                ),
                if (_statusMessage != null) ...[
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      _statusMessage!,
                      style: TextStyle(
                        color: _statusIsError ? Colors.redAccent : Colors.green,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          Container(
            height: 32,
            color: AppColors.gridHeader,
            child: Row(
              children: [
                _headerCell(tr('pcb_defect_type'), 3),
                _headerCell(tr('description'), 4),
                _headerCell(tr('created_by'), 2),
                _headerCell(tr('created_at'), 2),
                const SizedBox(width: 70),
              ],
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : data.isEmpty
                    ? Center(
                        child: Text(tr('pcb_no_data'),
                            style: const TextStyle(color: Colors.white38)),
                      )
                    : ListView.builder(
                        itemCount: data.length,
                        itemBuilder: (context, index) {
                          final row = data[index];
                          return Container(
                            height: 34,
                            color: index.isEven
                                ? AppColors.gridRowEven
                                : AppColors.gridRowOdd,
                            child: Row(
                              children: [
                                _bodyCell(row['defect_name'], 3),
                                _bodyCell(row['description'], 4),
                                _bodyCell(row['created_by'], 2),
                                _bodyCell(row['created_at_fmt'], 2),
                                SizedBox(
                                  width: 70,
                                  child: IconButton(
                                    onPressed: AuthService.canWritePcbInventory
                                        ? () => _deleteDefect(row)
                                        : null,
                                    icon: const Icon(Icons.delete_outline,
                                        color: Colors.redAccent, size: 18),
                                    tooltip: tr('delete'),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _headerCell(String text, int flex) {
    return Expanded(
      flex: flex,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Text(
          text,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.bold,
          ),
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }

  Widget _bodyCell(dynamic value, int flex) {
    return Expanded(
      flex: flex,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Text(
          '${value ?? ''}',
          style: const TextStyle(color: Colors.white70, fontSize: 12),
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}
