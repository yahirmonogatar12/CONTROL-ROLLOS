import 'package:flutter/material.dart';
import 'package:material_warehousing_flutter/core/theme/app_colors.dart';

enum ExcelColumnFilterAction {
  apply,
  clearFilter,
  sortAscending,
  sortDescending,
}

class ExcelColumnFilterResult {
  final ExcelColumnFilterAction action;
  final Set<String> selectedValues;

  const ExcelColumnFilterResult({
    required this.action,
    this.selectedValues = const {},
  });
}

class ExcelColumnFilterDialog extends StatefulWidget {
  final String columnLabel;
  final List<String> values;
  final Set<String> selectedValues;
  final bool hasActiveFilter;
  final bool? currentSortAscending;
  final String sortAscendingLabel;
  final String sortDescendingLabel;
  final String clearFilterLabel;
  final String searchLabel;
  final String selectAllLabel;
  final String emptyValueLabel;
  final String applyLabel;
  final String cancelLabel;
  final String noValuesLabel;

  const ExcelColumnFilterDialog({
    super.key,
    required this.columnLabel,
    required this.values,
    required this.selectedValues,
    required this.hasActiveFilter,
    required this.currentSortAscending,
    required this.sortAscendingLabel,
    required this.sortDescendingLabel,
    required this.clearFilterLabel,
    required this.searchLabel,
    required this.selectAllLabel,
    required this.emptyValueLabel,
    required this.applyLabel,
    required this.cancelLabel,
    required this.noValuesLabel,
  });

  @override
  State<ExcelColumnFilterDialog> createState() =>
      _ExcelColumnFilterDialogState();
}

class _ExcelColumnFilterDialogState extends State<ExcelColumnFilterDialog> {
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _valuesScrollController = ScrollController();
  late Set<String> _selectedValues;

  @override
  void initState() {
    super.initState();
    _selectedValues = Set<String>.from(widget.selectedValues);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _valuesScrollController.dispose();
    super.dispose();
  }

  List<String> get _visibleValues {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) return widget.values;
    return widget.values.where((value) {
      final displayValue = value.isEmpty ? widget.emptyValueLabel : value;
      return displayValue.toLowerCase().contains(query);
    }).toList();
  }

  bool? get _selectAllValue {
    final visibleValues = _visibleValues;
    if (visibleValues.isEmpty) return false;
    final selectedCount = visibleValues.where(_selectedValues.contains).length;
    if (selectedCount == 0) return false;
    if (selectedCount == visibleValues.length) return true;
    return null;
  }

  void _toggleAllVisible(bool? value) {
    final visibleValues = _visibleValues;
    setState(() {
      if (value == true) {
        _selectedValues.addAll(visibleValues);
      } else {
        _selectedValues.removeAll(visibleValues);
      }
    });
  }

  void _closeWith(ExcelColumnFilterResult result) {
    Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    final visibleValues = _visibleValues;

    return Dialog(
      backgroundColor: const Color(0xFF2D2D30),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          minWidth: 320,
          maxWidth: 380,
          maxHeight: 560,
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.columnLabel,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    tooltip: widget.cancelLabel,
                    visualDensity: VisualDensity.compact,
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close,
                        size: 18, color: Colors.white54),
                  ),
                ],
              ),
              _ActionRow(
                icon: Icons.sort_by_alpha,
                label: widget.sortAscendingLabel,
                selected: widget.currentSortAscending == true,
                onTap: () => _closeWith(
                  const ExcelColumnFilterResult(
                    action: ExcelColumnFilterAction.sortAscending,
                  ),
                ),
              ),
              _ActionRow(
                icon: Icons.sort_by_alpha,
                iconQuarterTurns: 2,
                label: widget.sortDescendingLabel,
                selected: widget.currentSortAscending == false,
                onTap: () => _closeWith(
                  const ExcelColumnFilterResult(
                    action: ExcelColumnFilterAction.sortDescending,
                  ),
                ),
              ),
              _ActionRow(
                icon: Icons.filter_list_off,
                label: '${widget.clearFilterLabel} "${widget.columnLabel}"',
                enabled: widget.hasActiveFilter,
                onTap: () => _closeWith(
                  const ExcelColumnFilterResult(
                    action: ExcelColumnFilterAction.clearFilter,
                  ),
                ),
              ),
              const Divider(color: AppColors.border, height: 16),
              TextField(
                controller: _searchController,
                autofocus: true,
                onChanged: (_) => setState(() {}),
                style: const TextStyle(color: Colors.white, fontSize: 12),
                decoration: InputDecoration(
                  hintText: widget.searchLabel,
                  hintStyle:
                      const TextStyle(color: Colors.white38, fontSize: 12),
                  prefixIcon:
                      const Icon(Icons.search, size: 18, color: Colors.white54),
                  suffixIcon: _searchController.text.isEmpty
                      ? null
                      : IconButton(
                          onPressed: () {
                            _searchController.clear();
                            setState(() {});
                          },
                          icon: const Icon(Icons.close,
                              size: 16, color: Colors.white54),
                        ),
                  isDense: true,
                  filled: true,
                  fillColor: AppColors.fieldBackground,
                  border: const OutlineInputBorder(
                    borderSide: BorderSide(color: AppColors.border),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              CheckboxListTile(
                value: _selectAllValue,
                tristate: true,
                onChanged: visibleValues.isEmpty ? null : _toggleAllVisible,
                dense: true,
                visualDensity: VisualDensity.compact,
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
                activeColor: Colors.blue,
                side: const BorderSide(color: Colors.white54),
                title: Text(
                  '(${widget.selectAllLabel})',
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
              ),
              Flexible(
                child: Container(
                  constraints: const BoxConstraints(minHeight: 120),
                  decoration: BoxDecoration(
                    color: AppColors.fieldBackground,
                    border: Border.all(color: AppColors.border),
                  ),
                  child: visibleValues.isEmpty
                      ? Center(
                          child: Text(
                            widget.noValuesLabel,
                            style: const TextStyle(
                                color: Colors.white54, fontSize: 12),
                          ),
                        )
                      : Scrollbar(
                          controller: _valuesScrollController,
                          thumbVisibility: visibleValues.length > 10,
                          child: ListView.builder(
                            controller: _valuesScrollController,
                            shrinkWrap: true,
                            itemCount: visibleValues.length,
                            itemBuilder: (context, index) {
                              final value = visibleValues[index];
                              final displayValue = value.isEmpty
                                  ? widget.emptyValueLabel
                                  : value;
                              return CheckboxListTile(
                                value: _selectedValues.contains(value),
                                onChanged: (selected) {
                                  setState(() {
                                    if (selected == true) {
                                      _selectedValues.add(value);
                                    } else {
                                      _selectedValues.remove(value);
                                    }
                                  });
                                },
                                dense: true,
                                visualDensity: VisualDensity.compact,
                                controlAffinity:
                                    ListTileControlAffinity.leading,
                                contentPadding:
                                    const EdgeInsets.symmetric(horizontal: 4),
                                activeColor: Colors.blue,
                                side: const BorderSide(color: Colors.white54),
                                title: Tooltip(
                                  message: displayValue,
                                  child: Text(
                                    displayValue,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        color: Colors.white, fontSize: 12),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(widget.cancelLabel),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: widget.values.isEmpty
                        ? null
                        : () => _closeWith(
                              ExcelColumnFilterResult(
                                action: ExcelColumnFilterAction.apply,
                                selectedValues:
                                    Set<String>.from(_selectedValues),
                              ),
                            ),
                    child: Text(widget.applyLabel),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  final IconData icon;
  final int iconQuarterTurns;
  final String label;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  const _ActionRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.iconQuarterTurns = 0,
    this.selected = false,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final color = !enabled
        ? Colors.white24
        : selected
            ? Colors.blue
            : Colors.white70;
    return InkWell(
      onTap: enabled ? onTap : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        child: Row(
          children: [
            RotatedBox(
              quarterTurns: iconQuarterTurns,
              child: Icon(icon, size: 18, color: color),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
