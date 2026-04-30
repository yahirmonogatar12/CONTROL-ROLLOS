import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_warehousing_flutter/core/localization/app_translations.dart';
import 'package:material_warehousing_flutter/core/theme/app_colors.dart';

/// Resultado de la división de lote
class MobileSplitLotResult {
  final int standardPack;
  final int packsCount;
  final int totalToExtract;
  final bool printLabels;

  MobileSplitLotResult({
    required this.standardPack,
    required this.packsCount,
    required this.totalToExtract,
    required this.printLabels,
  });
}

/// Diálogo para configurar la división de lote en móvil
class MobileSplitLotDialog extends StatefulWidget {
  final LanguageProvider languageProvider;
  final int defaultStandardPack;
  final int currentQty;
  final String materialCode;
  final String partNumber;

  const MobileSplitLotDialog({
    super.key,
    required this.languageProvider,
    required this.defaultStandardPack,
    required this.currentQty,
    required this.materialCode,
    required this.partNumber,
  });

  @override
  State<MobileSplitLotDialog> createState() => _MobileSplitLotDialogState();
}

class _MobileSplitLotDialogState extends State<MobileSplitLotDialog> {
  late TextEditingController _standardPackController;
  late TextEditingController _packsCountController;
  bool _printLabels = true;
  
  int get _standardPack => int.tryParse(_standardPackController.text) ?? 0;
  int get _packsCount => int.tryParse(_packsCountController.text) ?? 0;
  int get _totalToExtract => _standardPack * _packsCount;
  int get _remaining => widget.currentQty - _totalToExtract;
  int get _maxPacks => _standardPack > 0 ? widget.currentQty ~/ _standardPack : 0;

  String tr(String key) => widget.languageProvider.tr(key);

  @override
  void initState() {
    super.initState();
    _standardPackController = TextEditingController(
      text: widget.defaultStandardPack > 0 ? widget.defaultStandardPack.toString() : '',
    );
    _packsCountController = TextEditingController(text: '1');
  }

  @override
  void dispose() {
    _standardPackController.dispose();
    _packsCountController.dispose();
    super.dispose();
  }

  bool get _isValid {
    return _standardPack > 0 &&
           _packsCount > 0 &&
           _totalToExtract <= widget.currentQty;
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF252A3C),
      insetPadding: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.purple.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.call_split, color: Colors.purple, size: 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      tr('split_lot_title'),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(null),
                    icon: const Icon(Icons.close, color: Colors.white54),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              
              // Info del material
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1E2C),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildInfoRow(tr('material_code'), widget.materialCode),
                    const Divider(color: Colors.white12, height: 16),
                    _buildInfoRow(tr('part_number'), widget.partNumber),
                    const Divider(color: Colors.white12, height: 16),
                    _buildInfoRow(
                      tr('current_qty'),
                      widget.currentQty.toString(),
                      valueColor: Colors.cyan,
                      valueFontSize: 18,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              
              // Campo: Standard Pack (editable)
              Text(
                tr('standard_pack'),
                style: const TextStyle(color: Colors.white70, fontSize: 14),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _standardPackController,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                style: const TextStyle(color: Colors.white, fontSize: 16),
                decoration: InputDecoration(
                  hintText: tr('qty_per_split'),
                  hintStyle: const TextStyle(color: Colors.white38, fontSize: 14),
                  filled: true,
                  fillColor: const Color(0xFF1A1E2C),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Colors.purple, width: 2),
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 16),
              
              // Campo: Cantidad de packs
              Row(
                children: [
                  Expanded(
                    child: Text(
                      tr('packs_to_extract'),
                      style: const TextStyle(color: Colors.white70, fontSize: 14),
                    ),
                  ),
                  if (_maxPacks > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.purple.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        'max: $_maxPacks',
                        style: const TextStyle(color: Colors.purple, fontSize: 12),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _packsCountController,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                style: const TextStyle(color: Colors.white, fontSize: 16),
                decoration: InputDecoration(
                  hintText: '1',
                  hintStyle: const TextStyle(color: Colors.white38, fontSize: 14),
                  filled: true,
                  fillColor: const Color(0xFF1A1E2C),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Colors.purple, width: 2),
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 20),
              
              // Preview de la operación
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _isValid ? Colors.purple.withOpacity(0.15) : Colors.red.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _isValid ? Colors.purple.withOpacity(0.5) : Colors.red.withOpacity(0.5),
                    width: 2,
                  ),
                ),
                child: Column(
                  children: [
                    // Total a extraer
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          tr('total_to_extract'),
                          style: const TextStyle(color: Colors.white70, fontSize: 14),
                        ),
                        Text(
                          '$_packsCount × $_standardPack = $_totalToExtract',
                          style: TextStyle(
                            color: _isValid ? Colors.green : Colors.red,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Divider(color: Colors.white24, height: 1),
                    const SizedBox(height: 12),
                    // Restante en caja
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          tr('remaining_in_box'),
                          style: const TextStyle(color: Colors.white70, fontSize: 14),
                        ),
                        Text(
                          _remaining.toString(),
                          style: TextStyle(
                            color: _remaining >= 0 ? Colors.cyan : Colors.red,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    // Error message
                    if (!_isValid && _packsCount > 0 && _standardPack > 0) ...[
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          const Icon(Icons.error_outline, color: Colors.red, size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              tr('insufficient_qty'),
                              style: const TextStyle(color: Colors.red, fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),
              
              // Checkbox para imprimir etiquetas
              InkWell(
                onTap: () => setState(() => _printLabels = !_printLabels),
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A1E2C),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _printLabels ? Icons.check_box : Icons.check_box_outline_blank,
                        color: _printLabels ? AppColors.headerTab : Colors.white54,
                        size: 24,
                      ),
                      const SizedBox(width: 12),
                      const Icon(Icons.print, color: Colors.white54, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${tr('print_labels')} ($_packsCount)',
                          style: const TextStyle(color: Colors.white70, fontSize: 14),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              
              // Botones de acción
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(null),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white70,
                        side: const BorderSide(color: Colors.white24),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: Text(tr('cancel')),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton.icon(
                      onPressed: _isValid
                          ? () => Navigator.of(context).pop(MobileSplitLotResult(
                              standardPack: _standardPack,
                              packsCount: _packsCount,
                              totalToExtract: _totalToExtract,
                              printLabels: _printLabels,
                            ))
                          : null,
                      icon: const Icon(Icons.call_split, size: 18),
                      label: Text(tr('split_and_exit')),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.purple,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: Colors.grey.shade700,
                        disabledForegroundColor: Colors.white54,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, {Color? valueColor, double? valueFontSize}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: Colors.white54, fontSize: 13)),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            value,
            style: TextStyle(
              color: valueColor ?? Colors.white,
              fontSize: valueFontSize ?? 13,
              fontWeight: FontWeight.w500,
              fontFamily: 'monospace',
            ),
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.end,
          ),
        ),
      ],
    );
  }
}
