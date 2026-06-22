import 'package:flutter/material.dart';
import 'package:material_warehousing_flutter/core/theme/app_colors.dart';

const String _containsFilterPrefix = '__CONTAINS__:';

class SearchableColumnFilterResult {
  final String? filterValue;

  const SearchableColumnFilterResult._(this.filterValue);

  const SearchableColumnFilterResult.clear() : this._(null);

  factory SearchableColumnFilterResult.exact(String value) =>
      SearchableColumnFilterResult._(value);

  factory SearchableColumnFilterResult.contains(String value) =>
      SearchableColumnFilterResult._('$_containsFilterPrefix$value');
}

bool isContainsColumnFilter(String? filterValue) {
  return filterValue?.startsWith(_containsFilterPrefix) ?? false;
}

String columnFilterDisplayValue(String? filterValue) {
  if (filterValue == null) return '';
  if (isContainsColumnFilter(filterValue)) {
    return filterValue.substring(_containsFilterPrefix.length);
  }
  return filterValue;
}

bool matchesColumnFilterValue(Object? cellValue, String filterValue) {
  final value = (cellValue ?? '').toString();
  if (isContainsColumnFilter(filterValue)) {
    final query = columnFilterDisplayValue(filterValue).toLowerCase();
    return value.toLowerCase().contains(query);
  }
  return value == filterValue;
}

Future<SearchableColumnFilterResult?> showSearchableColumnFilterDialog({
  required BuildContext context,
  required String title,
  required List<String> values,
  required String allLabel,
  required String searchLabel,
  required String applyLabel,
  required String clearFilterLabel,
  String? currentFilter,
}) {
  return showDialog<SearchableColumnFilterResult>(
    context: context,
    builder: (context) => _SearchableColumnFilterDialog(
      title: title,
      values: values,
      allLabel: allLabel,
      searchLabel: searchLabel,
      applyLabel: applyLabel,
      clearFilterLabel: clearFilterLabel,
      currentFilter: currentFilter,
    ),
  );
}

class _SearchableColumnFilterDialog extends StatefulWidget {
  final String title;
  final List<String> values;
  final String allLabel;
  final String searchLabel;
  final String applyLabel;
  final String clearFilterLabel;
  final String? currentFilter;

  const _SearchableColumnFilterDialog({
    required this.title,
    required this.values,
    required this.allLabel,
    required this.searchLabel,
    required this.applyLabel,
    required this.clearFilterLabel,
    required this.currentFilter,
  });

  @override
  State<_SearchableColumnFilterDialog> createState() =>
      _SearchableColumnFilterDialogState();
}

class _SearchableColumnFilterDialogState
    extends State<_SearchableColumnFilterDialog> {
  late final TextEditingController _searchController;
  String _searchText = '';

  @override
  void initState() {
    super.initState();
    _searchText = isContainsColumnFilter(widget.currentFilter)
        ? columnFilterDisplayValue(widget.currentFilter)
        : '';
    _searchController = TextEditingController(text: _searchText);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _clearFilter() {
    Navigator.pop(context, const SearchableColumnFilterResult.clear());
  }

  void _applySearchText() {
    final query = _searchText.trim();
    if (query.isEmpty) return;
    Navigator.pop(context, SearchableColumnFilterResult.contains(query));
  }

  @override
  Widget build(BuildContext context) {
    final query = _searchText.trim().toLowerCase();
    final filteredValues = query.isEmpty
        ? widget.values
        : widget.values
            .where((value) => value.toLowerCase().contains(query))
            .toList();

    return AlertDialog(
      backgroundColor: AppColors.panelBackground,
      title: Text(
        widget.title,
        style: const TextStyle(color: Colors.white, fontSize: 14),
      ),
      content: SizedBox(
        width: 300,
        height: 360,
        child: Column(
          children: [
            TextField(
              controller: _searchController,
              autofocus: true,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              decoration: InputDecoration(
                isDense: true,
                hintText: widget.searchLabel,
                hintStyle: const TextStyle(color: Colors.white38, fontSize: 12),
                prefixIcon:
                    const Icon(Icons.search, size: 16, color: Colors.white38),
                prefixIconConstraints: const BoxConstraints(minWidth: 30),
                filled: true,
                fillColor: AppColors.fieldBackground,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(4),
                  borderSide: BorderSide.none,
                ),
              ),
              onChanged: (value) => setState(() => _searchText = value),
              onSubmitted: (_) => _applySearchText(),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView(
                children: [
                  ListTile(
                    dense: true,
                    leading: const Icon(Icons.filter_list_off,
                        size: 16, color: Colors.white54),
                    title: Text(
                      widget.allLabel,
                      style: TextStyle(
                        color: widget.currentFilter == null
                            ? Colors.blue
                            : Colors.white70,
                        fontSize: 13,
                        fontWeight: widget.currentFilter == null
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                    onTap: _clearFilter,
                  ),
                  const Divider(color: AppColors.border),
                  ...filteredValues.map((value) {
                    final isSelected = widget.currentFilter == value;
                    return ListTile(
                      dense: true,
                      title: Text(
                        value,
                        style: TextStyle(
                          color: isSelected ? Colors.blue : Colors.white70,
                          fontSize: 13,
                          fontWeight:
                              isSelected ? FontWeight.bold : FontWeight.normal,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      onTap: () => Navigator.pop(
                        context,
                        SearchableColumnFilterResult.exact(value),
                      ),
                    );
                  }),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _clearFilter,
          child: Text(
            widget.clearFilterLabel,
            style: const TextStyle(color: Colors.white70),
          ),
        ),
        ElevatedButton.icon(
          onPressed: _searchText.trim().isEmpty ? null : _applySearchText,
          icon: const Icon(Icons.search, size: 16),
          label: Text(widget.applyLabel),
        ),
      ],
    );
  }
}
