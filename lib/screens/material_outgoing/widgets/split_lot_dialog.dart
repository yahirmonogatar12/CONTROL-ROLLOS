import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_warehousing_flutter/core/localization/app_translations.dart';
import 'package:material_warehousing_flutter/core/theme/app_colors.dart';

/// Resultado de la división de lote
class SplitLotResult {
  final int standardPack;
  final int packsCount;
  final int totalToExtract;

  SplitLotResult({
    required this.standardPack,
    required this.packsCount,
    required this.totalToExtract,
  });
}

/// Diálogo para configurar la división de lote
class SplitLotDialog extends StatefulWidget {
  final LanguageProvider languageProvider;
  final int defaultStandardPack;
  final int currentQty;
  final String materialCode;
  final String partNumber;

  const SplitLotDialog({
    super.key,
    required this.languageProvider,
    required this.defaultStandardPack,
    required this.currentQty,
    required this.materialCode,
    required this.partNumber,
  });

  @override
  State<SplitLotDialog> createState() => _SplitLotDialogState();
}

class _SplitLotDialogState extends State<SplitLotDialog> {
  late TextEditingController _standardPackController;
  late TextEditingController _packsCountController;
  
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
    return AlertDialog(
      backgroundColor: AppColors.panelBackground,
      title: Row(
        children: [
          const Icon(Icons.call_split, color: Colors.purple, size: 24),
          const SizedBox(width: 8),
          Text(
            tr('split_lot_title'),
            style: const TextStyle(color: Colors.white, fontSize: 16),
          ),
        ],
      ),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Info del material
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.gridBackground,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildInfoRow(tr('material_code'), widget.materialCode),
                  const SizedBox(height: 4),
                  _buildInfoRow(tr('part_number'), widget.partNumber),
                  const SizedBox(height: 4),
                  _buildInfoRow(
                    tr('current_qty'),
                    widget.currentQty.toString(),
                    valueColor: Colors.cyan,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            
            // Campo: Standard Pack (editable)
            Text(
              tr('standard_pack'),
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
            const SizedBox(height: 4),
            TextFormField(
              controller: _standardPackController,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              style: const TextStyle(color: Colors.white, fontSize: 14),
              decoration: InputDecoration(
                hintText: tr('qty_per_split'),
                hintStyle: const TextStyle(color: Colors.white38, fontSize: 12),
                filled: true,
                fillColor: AppColors.fieldBackground,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(4),
                  borderSide: const BorderSide(color: AppColors.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(4),
                  borderSide: const BorderSide(color: AppColors.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(4),
                  borderSide: const BorderSide(color: Colors.purple),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            
            // Campo: Cantidad de packs
            Row(
              children: [
                Expanded(
                  child: Text(
                    tr('packs_to_extract'),
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ),
                if (_maxPacks > 0)
                  Text(
                    '(max: $_maxPacks)',
                    style: const TextStyle(color: Colors.white38, fontSize: 11),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            TextFormField(
              controller: _packsCountController,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              style: const TextStyle(color: Colors.white, fontSize: 14),
              decoration: InputDecoration(
                hintText: '1',
                hintStyle: const TextStyle(color: Colors.white38, fontSize: 12),
                filled: true,
                fillColor: AppColors.fieldBackground,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(4),
                  borderSide: const BorderSide(color: AppColors.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(4),
                  borderSide: const BorderSide(color: AppColors.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(4),
                  borderSide: const BorderSide(color: Colors.purple),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 16),
            
            // Preview de la operación
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _isValid ? Colors.purple.withOpacity(0.15) : Colors.red.withOpacity(0.15),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: _isValid ? Colors.purple.withOpacity(0.5) : Colors.red.withOpacity(0.5),
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
                        style: const TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                      Text(
                        '$_packsCount × $_standardPack = $_totalToExtract',
                        style: TextStyle(
                          color: _isValid ? Colors.green : Colors.red,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Divider(color: Colors.white24, height: 1),
                  const SizedBox(height: 8),
                  // Restante en caja
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        tr('remaining_in_box'),
                        style: const TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                      Text(
                        _remaining.toString(),
                        style: TextStyle(
                          color: _remaining >= 0 ? Colors.cyan : Colors.red,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  // Error message
                  if (!_isValid && _packsCount > 0 && _standardPack > 0) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(Icons.error_outline, color: Colors.red, size: 16),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            tr('insufficient_qty'),
                            style: const TextStyle(color: Colors.red, fontSize: 11),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 8),
            
            // Info de etiquetas
            Row(
              children: [
                const Icon(Icons.print, color: Colors.white54, size: 14),
                const SizedBox(width: 4),
                Text(
                  '${tr('labels_to_print')}: $_packsCount',
                  style: const TextStyle(color: Colors.white54, fontSize: 11),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: Text(
            tr('cancel'),
            style: const TextStyle(color: Colors.white70),
          ),
        ),
        ElevatedButton(
          onPressed: _isValid
              ? () => Navigator.of(context).pop(SplitLotResult(
                  standardPack: _standardPack,
                  packsCount: _packsCount,
                  totalToExtract: _totalToExtract,
                ))
              : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.purple,
            disabledBackgroundColor: Colors.grey.shade700,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.call_split, size: 16),
              const SizedBox(width: 4),
              Text(tr('split_and_exit')),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildInfoRow(String label, String value, {Color? valueColor}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: Colors.white54, fontSize: 11)),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            value,
            style: TextStyle(
              color: valueColor ?? Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.end,
          ),
        ),
      ],
    );
  }
}
