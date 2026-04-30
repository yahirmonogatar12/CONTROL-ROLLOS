import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

/// Widget para encabezados de tabla con columnas redimensionables estilo Excel
class ResizableColumnHeader extends StatefulWidget {
  final List<String> headers;
  final List<double> columnWidths;
  final Function(int, double) onColumnResize;
  final Function(int)? onColumnSort;
  final Function(int)? onColumnFilter;
  final int? sortedColumn;
  final bool sortAscending;
  final Map<int, bool> activeFilters;
  final bool showCheckbox;
  final bool? selectAllValue;
  final Function(bool?)? onSelectAll;
  final String? storageKey;

  const ResizableColumnHeader({
    super.key,
    required this.headers,
    required this.columnWidths,
    required this.onColumnResize,
    this.onColumnSort,
    this.onColumnFilter,
    this.sortedColumn,
    this.sortAscending = true,
    this.activeFilters = const {},
    this.showCheckbox = true,
    this.selectAllValue,
    this.onSelectAll,
    this.storageKey,
  });

  @override
  State<ResizableColumnHeader> createState() => _ResizableColumnHeaderState();
}

class _ResizableColumnHeaderState extends State<ResizableColumnHeader> {
  int? _resizingColumn;
  double _startX = 0;
  double _startWidth = 0;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 32,
      decoration: const BoxDecoration(
        color: Color(0xFF2D2D30),
        border: Border(bottom: BorderSide(color: Color(0xFF3C3C3C), width: 1)),
      ),
      child: Row(
        children: [
          // Checkbox column
          if (widget.showCheckbox)
            SizedBox(
              width: 30,
              child: Checkbox(
                value: widget.selectAllValue,
                tristate: true,
                onChanged: widget.onSelectAll,
                side: const BorderSide(color: Color(0xFF3C3C3C)),
                activeColor: Colors.blue,
              ),
            ),
          // Column headers with resize handles
          ...List.generate(widget.headers.length, (index) {
            final width = widget.columnWidths[index];
            final isSorted = widget.sortedColumn == index;
            final hasFilter = widget.activeFilters[index] == true;

            return SizedBox(
              width: width,
              child: Row(
                children: [
                  // Header content
                  Expanded(
                    child: GestureDetector(
                      onSecondaryTapDown: (details) {
                        widget.onColumnFilter?.call(index);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        alignment: Alignment.centerLeft,
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                widget.headers[index],
                                style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            // Sort icon
                            if (isSorted)
                              Icon(
                                widget.sortAscending
                                    ? Icons.arrow_upward
                                    : Icons.arrow_downward,
                                size: 10,
                                color: Colors.blue,
                              ),
                            // Filter icon
                            GestureDetector(
                              onTap: () => widget.onColumnFilter?.call(index),
                              child: Padding(
                                padding: const EdgeInsets.only(left: 2),
                                child: Icon(
                                  hasFilter
                                      ? Icons.filter_alt
                                      : Icons.filter_alt_outlined,
                                  size: 12,
                                  color: hasFilter ? Colors.blue : Colors.white38,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  // Resize handle
                  MouseRegion(
                    cursor: SystemMouseCursors.resizeColumn,
                    child: GestureDetector(
                      onHorizontalDragStart: (details) {
                        setState(() {
                          _resizingColumn = index;
                          _startX = details.globalPosition.dx;
                          _startWidth = width;
                        });
                      },
                      onHorizontalDragUpdate: (details) {
                        if (_resizingColumn == index) {
                          final delta = details.globalPosition.dx - _startX;
                          final newWidth = (_startWidth + delta).clamp(50.0, 500.0);
                          widget.onColumnResize(index, newWidth);
                        }
                      },
                      onHorizontalDragEnd: (details) {
                        setState(() {
                          _resizingColumn = null;
                        });
                        // Persist widths
                        _saveColumnWidths();
                      },
                      child: Container(
                        width: 4,
                        height: 32,
                        color: _resizingColumn == index
                            ? Colors.blue
                            : Colors.transparent,
                        child: Center(
                          child: Container(
                            width: 1,
                            height: 16,
                            color: const Color(0xFF555555),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Future<void> _saveColumnWidths() async {
    if (widget.storageKey == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'column_widths_${widget.storageKey}',
        jsonEncode(widget.columnWidths),
      );
    } catch (e) {
      debugPrint('Error saving column widths: $e');
    }
  }
}

/// Helper class for loading column widths
class ColumnWidthsHelper {
  static Future<List<double>> loadColumnWidths(
    String storageKey,
    int columnCount,
    double defaultWidth,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getString('column_widths_$storageKey');
      if (stored != null) {
        final List<dynamic> decoded = jsonDecode(stored);
        if (decoded.length == columnCount) {
          return decoded.map((e) => (e as num).toDouble()).toList();
        }
      }
    } catch (e) {
      debugPrint('Error loading column widths: $e');
    }
    return List.filled(columnCount, defaultWidth);
  }

  static Future<void> saveColumnWidths(
    String storageKey,
    List<double> widths,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('column_widths_$storageKey', jsonEncode(widths));
    } catch (e) {
      debugPrint('Error saving column widths: $e');
    }
  }
}
