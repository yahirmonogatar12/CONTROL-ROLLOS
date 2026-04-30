import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:material_warehousing_flutter/core/localization/app_translations.dart';
import 'package:material_warehousing_flutter/core/services/api_service.dart';
import 'package:material_warehousing_flutter/core/services/auth_service.dart';
import 'package:material_warehousing_flutter/core/services/scanner_config_service.dart';
import 'package:material_warehousing_flutter/core/theme/app_colors.dart';

/// Pantalla de inventario para móvil
/// Permite buscar y ver el inventario por ubicación o número de parte
class MobileInventoryScreen extends StatefulWidget {
  final LanguageProvider languageProvider;

  const MobileInventoryScreen({
    super.key,
    required this.languageProvider,
  });

  @override
  State<MobileInventoryScreen> createState() => _MobileInventoryScreenState();
}

class _MobileInventoryScreenState extends State<MobileInventoryScreen> {
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _readerInputController = TextEditingController();
  final FocusNode _readerFocusNode = FocusNode();
  MobileScannerController? _scannerController;
  
  bool _isScanning = false;
  bool _isLoading = false;
  bool _isLoadingLots = false;
  List<Map<String, dynamic>> _inventoryResults = [];
  List<Map<String, dynamic>> _itemLots = []; // Lotes del item seleccionado
  String? _searchQuery;
  Map<String, dynamic>? _selectedItem;

  String tr(String key) => widget.languageProvider.tr(key);

  @override
  void initState() {
    super.initState();
    _loadInventorySummary();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _readerInputController.dispose();
    _readerFocusNode.dispose();
    _scannerController?.dispose();
    super.dispose();
  }

  void _startScanner() {
    if (ScannerConfigService.isReaderMode) {
      // Modo lector/PDA - mostrar campo de texto
      setState(() {
        _isScanning = true;
      });
      Future.delayed(const Duration(milliseconds: 100), () {
        _readerFocusNode.requestFocus();
      });
      return;
    }
    
    // Modo cámara
    _scannerController?.dispose();
    _scannerController = MobileScannerController(
      detectionSpeed: DetectionSpeed.normal,
      facing: CameraFacing.back,
      torchEnabled: false,
    );
    setState(() {
      _isScanning = true;
    });
  }

  void _stopScanner() {
    _scannerController?.stop();
    _readerInputController.clear();
    setState(() {
      _isScanning = false;
    });
  }
  
  void _onReaderInput(String value) {
    if (value.isEmpty) return;
    final code = value.trim();
    _readerInputController.clear();
    _stopScanner();
    _searchController.text = code;
    _searchInventory(code);
  }

  /// Extrae el número de parte de un código escaneado completo
  /// Ej: EBC36198401-202601120002 → EBC36198401
  String _extractPartNumber(String code) {
    final dashIndex = code.lastIndexOf('-');
    if (dashIndex > 0) {
      final suffix = code.substring(dashIndex + 1);
      // Si el sufijo son solo dígitos y parece fecha+secuencia (8+ dígitos)
      if (suffix.length >= 8 && RegExp(r'^\d+$').hasMatch(suffix)) {
        return code.substring(0, dashIndex);
      }
    }
    return code;
  }

  Future<void> _loadInventorySummary() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final summary = await ApiService.getInventorySummary();
      setState(() {
        _inventoryResults = summary;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      _showMessage('Error al cargar inventario: $e', isError: true);
    }
  }

  Future<void> _searchInventory(String query) async {
    if (query.isEmpty) {
      setState(() {
        _searchQuery = null;
      });
      _loadInventorySummary();
      return;
    }

    setState(() {
      _isLoading = true;
      _searchQuery = query;
    });

    try {
      if (ApiService.isSlowLinkAndroid) {
        final results = await ApiService.searchInventoryMobile(query);
        setState(() {
          _inventoryResults = results;
          _isLoading = false;
        });
      } else {
        final partNumber = _extractPartNumber(query);
        final results = await ApiService.getInventoryLots(
          numeroParte: partNumber,
          codigoMaterialRecibido: query,
        );

        if (results.isEmpty) {
          final summary =
              await ApiService.getInventorySummary(numeroParte: partNumber);
          setState(() {
            _inventoryResults = summary;
            _isLoading = false;
          });
        } else {
          setState(() {
            _inventoryResults = results;
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      _showMessage('Error en búsqueda: $e', isError: true);
    }
  }

  void _onBarcodeDetected(BarcodeCapture capture) {
    if (capture.barcodes.isEmpty) return;
    
    final barcode = capture.barcodes.first;
    if (barcode.rawValue == null) return;
    
    _stopScanner();
    
    _searchController.text = barcode.rawValue!;
    _searchInventory(barcode.rawValue!);
  }

  void _showMessage(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!AuthService.canViewInventory) {
      return _buildNoPermissionScreen();
    }

    if (_isScanning) {
      return _buildScanner();
    }

    if (_selectedItem != null) {
      return _buildItemDetail();
    }

    return Column(
      children: [
        _buildSearchBar(),
        Expanded(
          child: _isLoading 
              ? const Center(child: CircularProgressIndicator())
              : _buildInventoryList(),
        ),
      ],
    );
  }

  Widget _buildNoPermissionScreen() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.lock, size: 64, color: Colors.white.withOpacity(0.3)),
          const SizedBox(height: 16),
          Text(
            tr('no_permission_mobile'),
            style: const TextStyle(color: Colors.white54, fontSize: 16),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      padding: const EdgeInsets.all(16),
      color: const Color(0xFF252A3C),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _searchController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: tr('search_inventory'),
                hintStyle: const TextStyle(color: Colors.white38),
                prefixIcon: const Icon(Icons.search, color: Colors.white54),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, color: Colors.white54),
                        onPressed: () {
                          setState(() {
                            _searchController.clear();
                            _searchQuery = null;
                          });
                          _loadInventorySummary();
                        },
                      )
                    : null,
                filled: true,
                fillColor: const Color(0xFF1A1E2C),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              ),
              onSubmitted: _searchInventory,
            ),
          ),
          const SizedBox(width: 12),
          Container(
            decoration: BoxDecoration(
              color: AppColors.headerTab,
              borderRadius: BorderRadius.circular(12),
            ),
            child: IconButton(
              icon: const Icon(Icons.qr_code_scanner, color: Colors.white),
              onPressed: _startScanner,
              tooltip: tr('scan_code'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScanner() {
    // Modo lector/PDA - mostrar campo de texto
    if (ScannerConfigService.isReaderMode) {
      return Container(
        color: AppColors.panelBackground,
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.barcode_reader,
              size: 80,
              color: Colors.white.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 24),
            Text(
              tr('scan_with_reader'),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              tr('reader_mode_hint'),
              style: const TextStyle(color: Colors.white54, fontSize: 14),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _readerInputController,
              focusNode: _readerFocusNode,
              autofocus: true,
              style: const TextStyle(color: Colors.white, fontSize: 18),
              decoration: InputDecoration(
                labelText: tr('scanned_code'),
                prefixIcon: const Icon(Icons.qr_code_scanner, color: Colors.white54),
                border: const OutlineInputBorder(),
                filled: true,
                fillColor: AppColors.fieldBackground,
              ),
              onSubmitted: _onReaderInput,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _stopScanner,
              icon: const Icon(Icons.close),
              label: Text(tr('cancel')),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red.withValues(alpha: 0.8),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
            ),
          ],
        ),
      );
    }
    
    // Modo cámara
    return Stack(
      children: [
        MobileScanner(
          controller: _scannerController!,
          onDetect: _onBarcodeDetected,
        ),
        Center(
          child: Container(
            width: 280,
            height: 180,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.blue, width: 3),
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        Positioned(
          bottom: 32,
          left: 0,
          right: 0,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              IconButton(
                onPressed: () => _scannerController?.toggleTorch(),
                icon: const Icon(
                  Icons.flash_auto,
                  color: Colors.white,
                  size: 32,
                ),
              ),
              ElevatedButton.icon(
                onPressed: _stopScanner,
                icon: const Icon(Icons.close),
                label: Text(tr('cancel')),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red.withValues(alpha: 0.8),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                ),
              ),
              IconButton(
                onPressed: () => _scannerController?.switchCamera(),
                icon: const Icon(Icons.cameraswitch, color: Colors.white, size: 32),
              ),
            ],
          ),
        ),
        Positioned(
          top: 32,
          left: 0,
          right: 0,
          child: Text(
            tr('scan_to_search_inventory'),
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.9),
              fontSize: 16,
              fontWeight: FontWeight.w500,
              shadows: [Shadow(color: Colors.black.withValues(alpha: 0.5), blurRadius: 4)],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildInventoryList() {
    if (_inventoryResults.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inventory_2, size: 64, color: Colors.white.withOpacity(0.3)),
            const SizedBox(height: 16),
            Text(
              _searchQuery != null 
                  ? '${tr('no_results_for')} "$_searchQuery"'
                  : tr('no_inventory_available'),
              style: const TextStyle(color: Colors.white54, fontSize: 16),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () async {
        if (ApiService.isSlowLinkAndroid &&
            _searchQuery != null &&
            _searchQuery!.isNotEmpty) {
          await _searchInventory(_searchQuery!);
          return;
        }
        await _loadInventorySummary();
      },
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _inventoryResults.length,
        itemBuilder: (context, index) {
          final item = _inventoryResults[index];
          return _buildInventoryCard(item);
        },
      ),
    );
  }

  Widget _buildInventoryCard(Map<String, dynamic> item) {
    final numeroParte = item['numero_parte'] ?? '-';
    // El backend devuelve stock_total desde inventario_lotes
    final cantidad = item['stock_total'] ?? item['stock_actual'] ?? item['cantidad_actual'] ?? 0;
    final ubicacion = item['ubicacion_salida'] ?? item['ubicacion'] ?? '-';
    final lotes = item['lotes_distintos'] ?? item['lotes_con_stock'] ?? item['total_lotes'] ?? 1;

    return Card(
      color: const Color(0xFF252A3C),
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        onTap: () => _showItemDetails(item),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      numeroParte,
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
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: _getQuantityColor(cantidad).withOpacity(0.2),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '$cantidad',
                      style: TextStyle(
                        color: _getQuantityColor(cantidad),
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (item['material_description'] != null)
                Text(
                  item['material_description'],
                  style: const TextStyle(color: Colors.white54, fontSize: 13),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  _buildInfoChip(Icons.location_on, ubicacion),
                  if (lotes > 1)
                    _buildInfoChip(Icons.layers, '$lotes ${tr('lots_count')}'),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoChip(IconData icon, String text) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 200),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.white54),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              text,
              style: const TextStyle(color: Colors.white54, fontSize: 12),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  void _showItemDetails(Map<String, dynamic> item) {
    setState(() {
      _selectedItem = item;
      _itemLots = [];
    });
    _loadItemLots(item['numero_parte']);
  }

  Future<void> _loadItemLots(String? numeroParte) async {
    if (numeroParte == null || numeroParte.isEmpty) return;
    
    setState(() {
      _isLoadingLots = true;
    });
    
    try {
      final lots = await ApiService.getInventoryLots(
        numeroParte: numeroParte,
        includeZeroStock: false,
      );
      setState(() {
        _itemLots = lots;
        _isLoadingLots = false;
      });
    } catch (e) {
      setState(() {
        _isLoadingLots = false;
      });
      _showMessage('Error al cargar lotes: $e', isError: true);
    }
  }

  Widget _buildItemDetail() {
    final item = _selectedItem!;
    
    return Column(
      children: [
        // Header con botón de regreso
        Container(
          padding: const EdgeInsets.all(16),
          color: const Color(0xFF252A3C),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                onPressed: () {
                  setState(() {
                    _selectedItem = null;
                  });
                },
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  item['numero_parte'] ?? tr('detail'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
        
        // Contenido
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Resumen principal
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        AppColors.headerTab.withOpacity(0.3),
                        AppColors.headerTab.withOpacity(0.1),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    children: [
                      Text(
                        tr('total_quantity_label'),
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.7),
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${item['stock_total'] ?? item['stock_actual'] ?? item['cantidad_actual'] ?? 0}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 42,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (item['unidad_medida'] != null)
                        Text(
                          item['unidad_medida'],
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.6),
                            fontSize: 16,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                
                // Detalles
                _buildDetailSection(tr('material_info'), [
                  _buildDetailRow(tr('part_number_label'), item['numero_parte']),
                  _buildDetailRow(tr('description_label'), item['material_description']),
                  _buildDetailRow(tr('customer'), item['customer_name']),
                  _buildDetailRow(tr('unit'), item['unidad_medida']),
                ]),
                
                const SizedBox(height: 16),
                
                _buildDetailSection(tr('location_warehouse'), [
                  _buildDetailRow(tr('main_location'), item['ubicacion_salida'] ?? item['ubicacion']),
                  _buildDetailRow(tr('total_lots'), '${item['lotes_distintos'] ?? item['lotes_con_stock'] ?? _itemLots.length}'),
                ]),
                
                // Lista de lotes con ubicaciones
                const SizedBox(height: 16),
                _buildLotsSection(),
                
                if (item['numero_lote_material'] != null || item['numero_lote'] != null) ...[
                  const SizedBox(height: 16),
                  _buildDetailSection(tr('lot_information'), [
                    _buildDetailRow(tr('internal_lot_label'), item['numero_lote_material'] ?? item['numero_lote']),
                    _buildDetailRow(tr('supplier_lot_label'), item['supplier_lot'] ?? item['numero_lote_proveedor']),
                    _buildDetailRow(tr('entry_date_label'), _formatDate(item['fecha_entrada'])),
                    _buildDetailRow(tr('material_code_label'), item['codigo_material_recibido']),
                  ]),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDetailSection(String title, List<Widget> children) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFF252A3C),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              title,
              style: TextStyle(
                color: Colors.white.withOpacity(0.9),
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const Divider(color: Colors.white12, height: 1),
          ...children,
        ],
      ),
    );
  }

  Widget _buildLotsSection() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFF252A3C),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Icon(Icons.layers, color: AppColors.headerTab, size: 18),
                const SizedBox(width: 8),
                Text(
                  tr('lots_detail'),
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.9),
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                if (_isLoadingLots)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
          ),
          const Divider(color: Colors.white12, height: 1),
          if (_isLoadingLots)
            const Padding(
              padding: EdgeInsets.all(20),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_itemLots.isEmpty)
            Padding(
              padding: const EdgeInsets.all(20),
              child: Center(
                child: Text(
                  tr('no_lots_found'),
                  style: const TextStyle(color: Colors.white54),
                ),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _itemLots.length,
              separatorBuilder: (_, __) => const Divider(color: Colors.white12, height: 1),
              itemBuilder: (context, index) {
                final lot = _itemLots[index];
                return _buildLotRow(lot);
              },
            ),
        ],
      ),
    );
  }

  Widget _buildLotRow(Map<String, dynamic> lot) {
    final code = lot['codigo_material_recibido'] ?? '-';
    final internalLot = lot['numero_lote_material'] ?? '-';
    final supplierLot = lot['numero_lote'] ?? lot['numero_lote_proveedor'] ?? '-';
    final qty = lot['cantidad_actual'] ?? lot['stock_actual'] ?? 0;
    final location = lot['ubicacion_salida'] ?? lot['ubicacion'] ?? '-';
    final fecha = _formatDate(lot['fecha_entrada'] ?? lot['fecha_recibo']);
    
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Primera fila: código y cantidad
          Row(
            children: [
              Expanded(
                child: Text(
                  code,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: _getQuantityColor(qty).withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '$qty',
                  style: TextStyle(
                    color: _getQuantityColor(qty),
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          // Segunda fila: ubicación destacada
          Row(
            children: [
              const Icon(Icons.location_on, size: 14, color: AppColors.headerTab),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  location,
                  style: const TextStyle(
                    color: AppColors.headerTab,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          // Tercera fila: lotes y fecha
          Row(
            children: [
              if (internalLot != '-') ...[
                Flexible(
                  child: Text(
                    '${tr('internal_lot')}: $internalLot',
                    style: const TextStyle(color: Colors.white54, fontSize: 11),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 12),
              ],
              if (supplierLot != '-' && supplierLot != internalLot)
                Flexible(
                  child: Text(
                    '${tr('supplier')}: $supplierLot',
                    style: const TextStyle(color: Colors.white38, fontSize: 11),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              const SizedBox(width: 8),
              Text(
                fecha,
                style: const TextStyle(color: Colors.white38, fontSize: 11),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, dynamic value) {
    final displayValue = value?.toString() ?? '-';
    if (displayValue == '-' || displayValue.isEmpty) {
      return const SizedBox.shrink();
    }
    
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(color: Colors.white54, fontSize: 14),
          ),
          const SizedBox(width: 16),
          Flexible(
            child: Text(
              displayValue,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }

  Color _getQuantityColor(dynamic quantity) {
    final qty = int.tryParse(quantity.toString()) ?? 0;
    if (qty <= 0) return Colors.red;
    if (qty < 100) return Colors.orange;
    return Colors.green;
  }

  String _formatDate(dynamic date) {
    if (date == null) return '-';
    try {
      final dt = DateTime.parse(date.toString());
      return '${dt.day}/${dt.month}/${dt.year}';
    } catch (e) {
      return date.toString();
    }
  }
}
