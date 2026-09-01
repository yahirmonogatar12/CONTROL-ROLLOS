import 'package:flutter/material.dart';

/// Filtro de columna estilo Excel: buscador, (Blanks)/(Non blanks) y la lista
/// de valores únicos de la columna.
///
/// Estaba duplicado en cada grid (Entradas, Salidas, IQC, Retorno...). Aquí vive
/// una sola vez para que todas las pantallas se vean y se comporten igual.
class ColumnFilter {
  /// Filtro especial: solo filas con valor.
  static const nonBlanks = '__NON_BLANKS__';

  /// Filtro especial: solo filas vacías.
  static const blanks = '__BLANKS__';

  /// ¿Pasa `value` el filtro `filter`? `null` = sin filtro, deja pasar todo.
  static bool matches(String value, String? filter) {
    if (filter == null) return true;
    if (filter == nonBlanks) return value.trim().isNotEmpty;
    if (filter == blanks) return value.trim().isEmpty;
    return value == filter;
  }

  /// Abre el desplegable anclado bajo `anchorKey`.
  ///
  /// Devuelve el filtro elegido, [nonBlanks], [blanks], o `null` si se limpió.
  /// Si el usuario cierra sin elegir no resuelve con nada aplicable: el llamador
  /// distingue ese caso porque el Future entrega `_noChange`.
  static Future<ColumnFilterResult> show({
    required BuildContext context,
    GlobalKey? anchorKey,
    Offset? anchorOffset,
    required Iterable<String> values,
    String? currentFilter,
  }) async {
    // Anclado bajo el encabezado; sin ancla se centra, como el dialogo que
    // usaban las pantallas que no llevan GlobalKey por columna.
    final renderBox =
        anchorKey?.currentContext?.findRenderObject() as RenderBox?;
    final screen = MediaQuery.of(context).size;
    final position = renderBox?.localToGlobal(Offset.zero) ??
        anchorOffset ??
        Offset(screen.width / 2 - 100, screen.height / 2 - 150);
    final size = renderBox?.size ?? Size.zero;
    // No dejar que se salga por el borde derecho o inferior.
    final left = position.dx.clamp(0.0, (screen.width - 210).clamp(0.0, screen.width));
    final top = (position.dy + size.height)
        .clamp(0.0, (screen.height - 310).clamp(0.0, screen.height));

    final unique = <String>{};
    var hasBlanks = false;
    for (final raw in values) {
      final value = raw.trim();
      if (value.isEmpty) {
        hasBlanks = true;
      } else {
        unique.add(value);
      }
    }
    final sorted = unique.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    final result = await showDialog<ColumnFilterResult>(
      context: context,
      barrierColor: Colors.transparent,
      builder: (dialogContext) {
        var searchText = '';
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final filtered = sorted
                .where((v) =>
                    v.toLowerCase().contains(searchText.toLowerCase()))
                .toList();
            return Stack(
              children: [
                Positioned(
                  left: left,
                  top: top,
                  child: Material(
                    elevation: 8,
                    color: const Color(0xFF252526),
                    borderRadius: BorderRadius.circular(4),
                    child: Container(
                      width: 200,
                      constraints: const BoxConstraints(maxHeight: 300),
                      decoration: BoxDecoration(
                        border: Border.all(color: const Color(0xFF3C3C3C)),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            child: TextField(
                              autofocus: true,
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 12),
                              decoration: InputDecoration(
                                isDense: true,
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 8),
                                hintText: 'Search...',
                                hintStyle: const TextStyle(
                                    color: Colors.white38, fontSize: 11),
                                prefixIcon: const Icon(Icons.search,
                                    size: 16, color: Colors.white38),
                                prefixIconConstraints:
                                    const BoxConstraints(minWidth: 30),
                                filled: true,
                                fillColor: const Color(0xFF3C3C3C),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(4),
                                  borderSide: BorderSide.none,
                                ),
                              ),
                              onChanged: (value) =>
                                  setDialogState(() => searchText = value),
                            ),
                          ),
                          const Divider(height: 1, color: Color(0xFF3C3C3C)),
                          Flexible(
                            child: SingleChildScrollView(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (currentFilter != null)
                                    _option(
                                      context,
                                      '(Clear Filter)',
                                      false,
                                      Icons.clear,
                                      Colors.orange,
                                      () => Navigator.pop(dialogContext,
                                          const ColumnFilterResult(null)),
                                    ),
                                  if (hasBlanks)
                                    _option(
                                      context,
                                      '(Blanks)',
                                      currentFilter == blanks,
                                      Icons.check_box_outline_blank,
                                      Colors.white70,
                                      () => Navigator.pop(dialogContext,
                                          const ColumnFilterResult(blanks)),
                                    ),
                                  _option(
                                    context,
                                    '(Non blanks)',
                                    currentFilter == nonBlanks,
                                    Icons.check_box,
                                    Colors.white70,
                                    () => Navigator.pop(dialogContext,
                                        const ColumnFilterResult(nonBlanks)),
                                  ),
                                  const Divider(
                                      height: 1, color: Color(0xFF3C3C3C)),
                                  ...filtered.map(
                                    (value) => _option(
                                      context,
                                      value,
                                      currentFilter == value,
                                      null,
                                      null,
                                      () => Navigator.pop(dialogContext,
                                          ColumnFilterResult(value)),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );

    return result ?? const ColumnFilterResult.unchanged();
  }

  static Widget _option(
    BuildContext context,
    String text,
    bool isSelected,
    IconData? icon,
    Color? iconColor,
    VoidCallback onTap,
  ) {
    return InkWell(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        color: isSelected ? Colors.blue.withValues(alpha: 0.3) : null,
        child: Row(
          children: [
            if (icon != null) ...[
              Icon(icon, size: 14, color: iconColor),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: Text(
                text,
                style: TextStyle(
                  fontSize: 11,
                  color: isSelected ? Colors.blue : Colors.white,
                  fontWeight:
                      isSelected ? FontWeight.bold : FontWeight.normal,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (isSelected)
              const Icon(Icons.check, size: 14, color: Colors.blue),
          ],
        ),
      ),
    );
  }
}

/// Resultado del desplegable. Se distingue "no eligió nada" de "eligió limpiar",
/// porque ambos casos son `null` como filtro pero solo uno debe aplicarse.
class ColumnFilterResult {
  final String? filter;
  final bool changed;

  const ColumnFilterResult(this.filter) : changed = true;
  const ColumnFilterResult.unchanged()
      : filter = null,
        changed = false;
}
