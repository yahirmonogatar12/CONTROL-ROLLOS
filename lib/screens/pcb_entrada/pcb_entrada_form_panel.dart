import 'package:flutter/material.dart';
import 'package:dropdown_button2/dropdown_button2.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:material_warehousing_flutter/core/localization/app_translations.dart';
import 'package:material_warehousing_flutter/core/theme/app_colors.dart';
import 'package:material_warehousing_flutter/core/widgets/field_decoration.dart';
import 'package:material_warehousing_flutter/core/widgets/table_dropdown_field.dart';
import 'package:material_warehousing_flutter/core/services/api_service.dart';
import 'package:material_warehousing_flutter/core/services/auth_service.dart';
import 'package:material_warehousing_flutter/core/constants/pcb_areas.dart';
import 'package:material_warehousing_flutter/screens/pcb_common/pcb_user_selection_mixin.dart';

class _PcbDefectDraft {
  String? defectType;
  String componentLocation;
  String? etapaDeteccion;
  String? defectSourceArea;
  String? defectDataId;

  _PcbDefectDraft({
    this.defectType,
    this.componentLocation = '',
    this.etapaDeteccion,
    this.defectSourceArea,
    this.defectDataId,
  });

  _PcbDefectDraft copy() => _PcbDefectDraft(
        defectType: defectType,
        componentLocation: componentLocation,
        etapaDeteccion: etapaDeteccion,
        defectSourceArea: defectSourceArea,
        defectDataId: defectDataId,
      );

  Map<String, dynamic> toJson() => {
        'defect_type': defectType,
        'component_location':
            componentLocation.trim().isEmpty ? null : componentLocation.trim(),
        'etapa_deteccion': etapaDeteccion,
        'defect_source_area': defectSourceArea,
        'defect_data_id': defectDataId,
      };
}

class PcbEntradaFormPanel extends StatefulWidget {
  final LanguageProvider languageProvider;
  final VoidCallback onDataSaved;

  const PcbEntradaFormPanel({
    super.key,
    required this.languageProvider,
    required this.onDataSaved,
  });

  @override
  State<PcbEntradaFormPanel> createState() => PcbEntradaFormPanelState();
}

class PcbEntradaFormPanelState extends State<PcbEntradaFormPanel>
    with PcbUserSelectionMixin<PcbEntradaFormPanel> {
  final TextEditingController _scanController = TextEditingController();
  final TextEditingController _commentController = TextEditingController();
  final TextEditingController _dateController = TextEditingController();
  final TextEditingController _arrayCountController =
      TextEditingController(text: '1');
  final TextEditingController _repairCountController =
      TextEditingController(text: '1');
  final TextEditingController _defectCountController =
      TextEditingController(text: '1');
  final TextEditingController _componentLocationController =
      TextEditingController();
  final FocusNode _scanFocusNode = FocusNode();

  String _selectedProceso = 'SMD';
  String _selectedArea = PcbAreas.inventory;
  String? _selectedDefectType;
  String? _detectedEtapa; // 'LQC' | 'OQC' | 'AIS' | null
  String? _detectedSourceArea;
  String? _detectedDefectDataId;
  List<Map<String, dynamic>> _defects = [];
  int _defectCount = 1;
  List<_PcbDefectDraft> _configuredDefects = [];
  bool _isDefectDialogOpen = false;
  DateTime _inventoryDate = DateTime.now();
  bool _isLoading = false;
  String? _statusMessage;
  bool _statusIsError = false;
  List<int> _lastInsertedIds = [];
  int _pendingArrayRemaining = 0;
  int _pendingArrayCount = 1;
  int _pendingRepairRemaining = 0;
  int _pendingInventoryRemaining = 0;
  String? _pendingArrayGroupCode;
  String? _pendingArrayParentCode;
  String _pendingArrayTargetArea = PcbAreas.inventory;
  String _pendingRepairArea = PcbAreas.repair;

  static const List<String> _procesos = ['SMD', 'IMD', 'ASSY'];
  static const List<String> _areas = PcbAreas.values;

  String tr(String key) => widget.languageProvider.tr(key);

  String get _formattedDate =>
      '${_inventoryDate.year}-${_inventoryDate.month.toString().padLeft(2, '0')}-${_inventoryDate.day.toString().padLeft(2, '0')}';

  bool get _hasPendingArrayScans => _pendingArrayRemaining > 0;

  @override
  void initState() {
    super.initState();
    _dateController.text = _formattedDate;
    setDefaultPcbUser();
    _loadLocalPrefs();
    _loadDefects();
    loadPcbUsers();
  }

  @override
  void dispose() {
    _scanController.dispose();
    _commentController.dispose();
    _dateController.dispose();
    _arrayCountController.dispose();
    _repairCountController.dispose();
    _defectCountController.dispose();
    _componentLocationController.dispose();
    _scanFocusNode.dispose();
    super.dispose();
  }

  void requestScanFocus() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _scanFocusNode.requestFocus();
    });
  }

  Future<void> _loadLocalPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedProcess = prefs.getString('pcb_entrada_last_process');
      final savedArea = prefs.getString('pcb_entrada_last_area');
      final savedComment = prefs.getString('pcb_entrada_last_comment');
      final savedRepairCount = prefs.getString('pcb_entrada_last_repair_count');
      final savedDefectType = prefs.getString('pcb_entrada_last_defect_type');
      final savedComponentLocation =
          prefs.getString('pcb_entrada_last_component_location');
      if (mounted) {
        setState(() {
          if (savedProcess != null && _procesos.contains(savedProcess)) {
            _selectedProceso = savedProcess;
          }
          if (savedArea != null && _areas.contains(savedArea)) {
            _selectedArea = savedArea;
          }
          if (savedComment != null) _commentController.text = savedComment;
          if (savedRepairCount != null &&
              (int.tryParse(savedRepairCount) ?? 0) > 0) {
            _repairCountController.text = savedRepairCount;
          }
          if (savedDefectType != null && savedDefectType.isNotEmpty) {
            _selectedDefectType = savedDefectType;
          }
          if (savedComponentLocation != null) {
            _componentLocationController.text = savedComponentLocation;
          }
        });
      }
    } catch (_) {}
  }

  Future<void> _loadDefects() async {
    final defects = await ApiService.getPcbDefects();
    if (!mounted) return;
    setState(() {
      _defects = defects;
      final names = _defects.map((d) => d['defect_name']?.toString()).toSet();
      if (_selectedDefectType != null && !names.contains(_selectedDefectType)) {
        _selectedDefectType = null;
      }
    });
  }

  Future<void> _saveLocalPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('pcb_entrada_last_process', _selectedProceso);
      await prefs.setString('pcb_entrada_last_area', _selectedArea);
      await prefs.setString(
          'pcb_entrada_last_comment', _commentController.text);
      await prefs.remove('pcb_entrada_last_array_count');
      await prefs.setString(
          'pcb_entrada_last_repair_count', _repairCountController.text);
      if (_selectedDefectType != null) {
        await prefs.setString(
            'pcb_entrada_last_defect_type', _selectedDefectType!);
      }
      await prefs.setString('pcb_entrada_last_component_location',
          _componentLocationController.text);
    } catch (_) {}
  }

  int _getArrayCount() {
    final value = int.tryParse(_arrayCountController.text.trim()) ?? 1;
    return value < 1 ? 1 : value;
  }

  int _getRepairCount() {
    if (!PcbAreas.isRepair(_selectedArea)) return 0;
    final value = int.tryParse(_repairCountController.text.trim()) ?? 1;
    return value < 1 ? 1 : value;
  }

  void _updatePendingArrayTargetArea() {
    _pendingArrayTargetArea =
        _pendingRepairRemaining > 0 ? _pendingRepairArea : PcbAreas.inventory;
  }

  String _normalizePcbCode(String code) =>
      code.trim().toUpperCase().replaceAll(RegExp(r'\s+'), '');

  List<List<String>> get _defectRows {
    return _defects.map((defect) {
      return [
        defect['defect_name']?.toString() ?? '',
        defect['description']?.toString() ?? '',
      ];
    }).toList();
  }

  _PcbDefectDraft _primaryDefectDraft() => _PcbDefectDraft(
        defectType: _selectedDefectType,
        componentLocation: _componentLocationController.text,
        etapaDeteccion: _detectedEtapa ?? 'AIS',
        defectSourceArea: _detectedSourceArea,
        defectDataId: _detectedDefectDataId,
      );

  void _resetDefectConfiguration({bool keepPrimary = true}) {
    _defectCount = 1;
    _defectCountController.text = '1';
    _configuredDefects = keepPrimary ? [_primaryDefectDraft()] : [];
  }

  bool _configuredDefectsMatchPrimary() {
    if (_configuredDefects.length != _defectCount ||
        _configuredDefects.isEmpty) {
      return false;
    }
    final first = _configuredDefects.first;
    final primary = _primaryDefectDraft();
    return first.defectType == primary.defectType &&
        first.componentLocation.trim() == primary.componentLocation.trim() &&
        first.defectDataId == primary.defectDataId;
  }

  List<Map<String, dynamic>> _defectsPayload() {
    if (_defectCount <= 1) return [_primaryDefectDraft().toJson()];
    if (_configuredDefects.length != _defectCount) return const [];
    final drafts = _configuredDefects.map((draft) => draft.copy()).toList();
    drafts[0] = _primaryDefectDraft();
    return drafts.map((draft) => draft.toJson()).toList();
  }

  void _syncPrimaryDefectIntoConfiguration() {
    if (_configuredDefects.isEmpty) {
      _configuredDefects = [_primaryDefectDraft()];
    } else {
      _configuredDefects[0] = _primaryDefectDraft();
    }
  }

  void _onDefectCountChanged(String value) {
    final count = int.tryParse(value.trim());
    if (count == null || count < 1) return;
    final previousCount = _defectCount;
    setState(() {
      _defectCount = count;
      if (count == 1) {
        _configuredDefects = [_primaryDefectDraft()];
      }
    });
    if (count < 2) return;

    Future<void>.delayed(const Duration(milliseconds: 350), () async {
      if (!mounted ||
          _isDefectDialogOpen ||
          _defectCountController.text.trim() != value.trim() ||
          _defectCount != count) {
        return;
      }
      await _configureDefects(count, cancelCount: previousCount);
    });
  }

  Future<bool> _configureDefects(int count, {int? cancelCount}) async {
    if (_isDefectDialogOpen || count < 2) return count < 2;
    _isDefectDialogOpen = true;

    final drafts = <_PcbDefectDraft>[];
    for (var i = 0; i < count; i++) {
      if (i == 0) {
        drafts.add(_primaryDefectDraft());
      } else if (i < _configuredDefects.length) {
        drafts.add(_configuredDefects[i].copy());
      } else {
        drafts.add(_PcbDefectDraft(etapaDeteccion: 'AIS'));
      }
    }
    final locationControllers = drafts
        .map((draft) => TextEditingController(text: draft.componentLocation))
        .toList();
    String? validationMessage;

    final result = await showDialog<List<_PcbDefectDraft>>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            backgroundColor: AppColors.panelBackground,
            title: Text(
              '${tr('pcb_configure_defects')} ($count)',
              style: const TextStyle(color: Colors.white, fontSize: 16),
            ),
            content: SizedBox(
              width: 760,
              height: (count * 70.0 + 65).clamp(210.0, 520.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tr('pcb_first_defect_hint'),
                    style: const TextStyle(color: Colors.white60, fontSize: 12),
                  ),
                  const SizedBox(height: 10),
                  if (validationMessage != null) ...[
                    Text(validationMessage!,
                        style: const TextStyle(
                            color: Colors.redAccent, fontSize: 12)),
                    const SizedBox(height: 6),
                  ],
                  Expanded(
                    child: ListView.separated(
                      itemCount: drafts.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (_, index) {
                        final draft = drafts[index];
                        final defectNames = _defects
                            .map(
                                (item) => item['defect_name']?.toString() ?? '')
                            .where((name) => name.isNotEmpty)
                            .toSet()
                            .toList();
                        if (draft.defectType != null &&
                            draft.defectType!.isNotEmpty &&
                            !defectNames.contains(draft.defectType)) {
                          defectNames.insert(0, draft.defectType!);
                        }
                        return Row(
                          children: [
                            SizedBox(
                              width: 78,
                              child: Text(
                                '${tr('pcb_defect_type')} ${index + 1}',
                                style: TextStyle(
                                  color:
                                      index == 0 ? Colors.cyan : Colors.white70,
                                  fontSize: 12,
                                  fontWeight: index == 0
                                      ? FontWeight.w600
                                      : FontWeight.normal,
                                ),
                              ),
                            ),
                            Expanded(
                              flex: 3,
                              child: DropdownButtonFormField2<String>(
                                decoration: fieldDecoration(),
                                value: draft.defectType,
                                isExpanded: true,
                                items: defectNames
                                    .map((name) => DropdownMenuItem<String>(
                                          value: name,
                                          child: Text(name,
                                              style: const TextStyle(
                                                  fontSize: 12)),
                                        ))
                                    .toList(),
                                onChanged: (selected) {
                                  if (selected == null) return;
                                  setDialogState(() {
                                    if (draft.defectType != selected) {
                                      draft.defectType = selected;
                                      draft.etapaDeteccion = 'AIS';
                                      draft.defectSourceArea = null;
                                      draft.defectDataId = null;
                                    }
                                  });
                                },
                                dropdownStyleData: DropdownStyleData(
                                  maxHeight: 260,
                                  decoration: BoxDecoration(
                                    color: AppColors.fieldBackground,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              flex: 2,
                              child: TextFormField(
                                controller: locationControllers[index],
                                decoration: fieldDecoration().copyWith(
                                  labelText: tr('pcb_component_location'),
                                  labelStyle: const TextStyle(
                                      color: Colors.white60, fontSize: 11),
                                ),
                                style: const TextStyle(fontSize: 12),
                                textCapitalization:
                                    TextCapitalization.characters,
                                onChanged: (text) =>
                                    draft.componentLocation = text,
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(tr('cancel'),
                    style: const TextStyle(color: Colors.white70)),
              ),
              ElevatedButton(
                onPressed: () {
                  for (var i = 0; i < drafts.length; i++) {
                    drafts[i].componentLocation =
                        locationControllers[i].text.trim();
                  }
                  if (drafts.any((draft) =>
                      draft.defectType == null ||
                      draft.defectType!.trim().isEmpty)) {
                    setDialogState(() =>
                        validationMessage = tr('pcb_complete_all_defects'));
                    return;
                  }
                  Navigator.pop(ctx, drafts);
                },
                child: Text(tr('apply')),
              ),
            ],
          );
        },
      ),
    );

    for (final controller in locationControllers) {
      controller.dispose();
    }
    _isDefectDialogOpen = false;
    if (!mounted) return false;

    if (result == null) {
      if (cancelCount != null) {
        setState(() {
          _defectCount = cancelCount;
          _defectCountController.text = cancelCount.toString();
        });
      }
      return false;
    }

    final first = result.first;
    setState(() {
      _defectCount = count;
      _defectCountController.text = count.toString();
      _configuredDefects = result;
      _selectedDefectType = first.defectType;
      _componentLocationController.text = first.componentLocation;
      _detectedEtapa = first.etapaDeteccion;
      _detectedSourceArea = first.defectSourceArea;
      _detectedDefectDataId = first.defectDataId;
    });
    _saveLocalPrefs();
    return true;
  }

  String? _buildComments({required bool isArrayItem}) {
    final parts = <String>[];
    final comment = _commentController.text.trim();
    if (comment.isNotEmpty) parts.add(comment);
    if (isArrayItem && _pendingArrayParentCode != null) {
      parts.add('${tr('pcb_same_array_as')}: $_pendingArrayParentCode');
    }
    return parts.isEmpty ? null : parts.join(' | ');
  }

  void _clearPendingArray() {
    _arrayCountController.text = '1';
    _pendingArrayRemaining = 0;
    _pendingArrayCount = 1;
    _pendingRepairRemaining = 0;
    _pendingInventoryRemaining = 0;
    _pendingArrayGroupCode = null;
    _pendingArrayParentCode = null;
    _pendingArrayTargetArea = PcbAreas.inventory;
    _pendingRepairArea = PcbAreas.repair;
  }

  void _cancelPendingArray() {
    setState(() {
      _clearPendingArray();
      _statusMessage = tr('pcb_array_cancelled');
      _statusIsError = false;
    });
    requestScanFocus();
  }

  Future<void> _onScan() async {
    final code = _scanController.text.trim();
    if (code.isEmpty) return;
    final isArrayItem = _hasPendingArrayScans;

    final previousRepair = await ApiService.getPcbPreviousRepair(code);
    if (!mounted) return;
    if (previousRepair != null) {
      final repairedDefects = previousRepair['defects'];
      if (repairedDefects is List && repairedDefects.isNotEmpty) {
        await _showPreviousRepairDialog(previousRepair);
        if (!mounted) return;
      }
    }

    // Detectar defectos LQC/OQC solo en el primer PCB del array.
    if (!isArrayItem) {
      final matches = await ApiService.lookupDefectData(code);
      if (!mounted) return;

      Map<String, dynamic>? selected;
      if (matches.isEmpty) {
        setState(() {
          _detectedEtapa = 'AIS';
          _detectedSourceArea = null;
          _detectedDefectDataId = null;
        });
      } else if (matches.length == 1) {
        selected = matches.first;
      } else {
        selected = await _showDefectVerificationDialog(matches);
        if (!mounted) return;
        if (selected == null) {
          requestScanFocus();
          return;
        }
      }

      if (selected != null) {
        final etapa = selected['etapa_deteccion']?.toString().toUpperCase();
        setState(() {
          if (!PcbAreas.isRepair(_selectedArea)) {
            _selectedArea = PcbAreas.repair;
          }
          _selectedDefectType = selected!['defecto']?.toString();
          _componentLocationController.text =
              selected['ubicacion']?.toString() ?? '';
          _detectedEtapa = (etapa == 'LQC' || etapa == 'OQC') ? etapa : 'AIS';
          _detectedSourceArea = selected['area']?.toString();
          _detectedDefectDataId = selected['id']?.toString();
        });
      }
    }

    final arrayCount = isArrayItem ? _pendingArrayCount : _getArrayCount();
    final repairCount = isArrayItem ? 0 : _getRepairCount();
    final effectiveArea = isArrayItem ? _pendingArrayTargetArea : _selectedArea;
    final isRepairEntry = PcbAreas.isRepair(effectiveArea);
    final requestedDefectCount =
        int.tryParse(_defectCountController.text.trim()) ?? 1;
    if (isRepairEntry && requestedDefectCount < 1) {
      setState(() {
        _statusMessage = tr('pcb_invalid_defect_count');
        _statusIsError = true;
      });
      requestScanFocus();
      return;
    }
    _defectCount = requestedDefectCount;
    if (isRepairEntry &&
        _defectCount >= 2 &&
        !_configuredDefectsMatchPrimary()) {
      final configured = await _configureDefects(_defectCount);
      if (!configured || !mounted) {
        requestScanFocus();
        return;
      }
    }
    final List<Map<String, dynamic>> selectedDefects =
        isRepairEntry ? _defectsPayload() : <Map<String, dynamic>>[];
    final arrayGroupCode =
        isArrayItem ? _pendingArrayGroupCode : _normalizePcbCode(code);
    final arrayRole =
        arrayCount > 1 ? (isRepairEntry ? 'DEFECT' : 'ARRAY_ITEM') : 'SINGLE';

    if (arrayCount > 99) {
      setState(() {
        _statusMessage = tr('pcb_invalid_array_count');
        _statusIsError = true;
      });
      requestScanFocus();
      return;
    }

    if (!isArrayItem &&
        PcbAreas.isRepair(_selectedArea) &&
        (repairCount > arrayCount || repairCount < 1)) {
      setState(() {
        _statusMessage = tr('pcb_invalid_repair_count');
        _statusIsError = true;
      });
      requestScanFocus();
      return;
    }

    if (isRepairEntry &&
        (selectedDefects.length != _defectCount ||
            selectedDefects.any((defect) =>
                defect['defect_type'] == null ||
                defect['defect_type'].toString().trim().isEmpty))) {
      setState(() {
        _statusMessage = tr('pcb_defect_required');
        _statusIsError = true;
      });
      requestScanFocus();
      return;
    }

    if (!AuthService.canWritePcbInventory) {
      setState(() {
        _statusMessage = tr('pcb_no_write_permission');
        _statusIsError = true;
      });
      _scanController.clear();
      requestScanFocus();
      return;
    }

    setState(() {
      _isLoading = true;
      _statusMessage = null;
    });

    final result = await ApiService.scanPcbInventory(
      scannedCode: code,
      inventoryDate: _formattedDate,
      proceso: _selectedProceso,
      area: effectiveArea,
      tipoMovimiento: 'ENTRADA',
      arrayCount: arrayCount,
      qty: 1,
      arrayGroupCode: arrayGroupCode,
      arrayRole: arrayRole,
      defectType: isRepairEntry ? _selectedDefectType : null,
      componentLocation:
          isRepairEntry && _componentLocationController.text.trim().isNotEmpty
              ? _componentLocationController.text.trim()
              : null,
      etapaDeteccion: isRepairEntry ? _detectedEtapa : null,
      defectSourceArea: isRepairEntry ? _detectedSourceArea : null,
      defectDataId: isRepairEntry ? _detectedDefectDataId : null,
      defects: isRepairEntry ? selectedDefects : null,
      comentarios: _buildComments(isArrayItem: isArrayItem),
      scannedBy: selectedPcbScannedBy,
    );

    if (mounted) {
      if (result['success'] == true) {
        final data = result['data'];
        final ids = (result['inserted_ids'] as List?)
            ?.map((id) => (id as num).toInt())
            .toList();
        final fallbackId = data?['id'] is num ? (data['id'] as num).toInt() : 0;
        _lastInsertedIds = ids?.isNotEmpty == true
            ? ids!
            : (fallbackId > 0 ? [fallbackId] : []);
        String nextMessage;
        if (isArrayItem) {
          if (PcbAreas.isRepair(effectiveArea) && _pendingRepairRemaining > 0) {
            _pendingRepairRemaining -= 1;
          } else if (_pendingInventoryRemaining > 0) {
            _pendingInventoryRemaining -= 1;
          }
          _pendingArrayRemaining =
              _pendingRepairRemaining + _pendingInventoryRemaining;
          if (_pendingArrayRemaining <= 0) {
            _clearPendingArray();
            _clearDetectedDefect();
            _resetDefectConfiguration();
            nextMessage =
                '${tr('pcb_array_complete')}: ${data?['pcb_part_no'] ?? ''} - ${data?['modelo'] ?? 'N/A'}';
          } else {
            _updatePendingArrayTargetArea();
            nextMessage =
                '${tr('pcb_scan_saved')}: ${data?['pcb_part_no'] ?? ''} | ${tr('pcb_array_remaining')}: $_pendingArrayRemaining (${PcbAreas.label(_pendingArrayTargetArea)})';
          }
        } else if (arrayCount > 1) {
          _pendingArrayCount = arrayCount;
          _pendingArrayGroupCode = _normalizePcbCode(code);
          _pendingArrayParentCode = code;
          if (PcbAreas.isRepair(_selectedArea)) {
            _pendingRepairArea = _selectedArea;
            _pendingRepairRemaining = repairCount - 1;
            _pendingInventoryRemaining = arrayCount - repairCount;
          } else {
            _pendingRepairRemaining = 0;
            _pendingInventoryRemaining = arrayCount - 1;
          }
          _pendingArrayRemaining =
              _pendingRepairRemaining + _pendingInventoryRemaining;
          _updatePendingArrayTargetArea();
          nextMessage =
              '${tr('pcb_scan_saved')}: ${data?['pcb_part_no'] ?? ''} | ${tr('pcb_array_remaining')}: $_pendingArrayRemaining (${PcbAreas.label(_pendingArrayTargetArea)})';
        } else {
          _clearDetectedDefect();
          _resetDefectConfiguration();
          nextMessage =
              '${tr('pcb_scan_saved')}: ${data?['pcb_part_no'] ?? ''} - ${data?['modelo'] ?? 'N/A'} (${data?['proceso'] ?? ''})';
        }
        setState(() {
          _statusMessage = nextMessage;
          _statusIsError = false;
        });
        _scanController.clear();
        _saveLocalPrefs();
        widget.onDataSaved();
      } else {
        final errorCode = result['code'] ?? '';
        String msg = result['message'] ?? tr('pcb_scan_error');
        if (errorCode == 'DUPLICATE_SCAN')
          msg = tr('pcb_duplicate_scan');
        else if (errorCode == 'INVALID_PCB_PART_NO')
          msg = tr('pcb_invalid_part_no');
        else if (errorCode == 'INVALID_PROCESO')
          msg = tr('pcb_invalid_proceso');
        else if (errorCode == 'INVALID_ARRAY_COUNT')
          msg = tr('pcb_invalid_array_count');
        else if (errorCode == 'MISSING_DEFECT_TYPE' ||
            errorCode == 'INVALID_DEFECT_TYPE') msg = tr('pcb_defect_required');
        setState(() {
          _statusMessage = msg;
          _statusIsError = true;
        });
        _scanController.clear();
      }
      setState(() => _isLoading = false);
      requestScanFocus();
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _inventoryDate,
      firstDate: DateTime(2024),
      lastDate: DateTime(2030),
    );
    if (picked != null && mounted) {
      setState(() {
        _inventoryDate = picked;
        _dateController.text = _formattedDate;
      });
    }
  }

  Future<void> _undoLastScan() async {
    if (_lastInsertedIds.isEmpty) return;
    var ok = true;
    for (final id in _lastInsertedIds.reversed) {
      final result = await ApiService.deletePcbInventoryScan(id);
      ok = ok && result['success'] == true;
    }
    if (ok) {
      setState(() {
        _statusMessage = tr('pcb_scan_deleted');
        _statusIsError = false;
        _lastInsertedIds = [];
        if (_hasPendingArrayScans) _clearPendingArray();
        _clearDetectedDefect();
      });
      widget.onDataSaved();
    }
  }

  void _clearDetectedDefect() {
    _detectedEtapa = null;
    _detectedSourceArea = null;
    _detectedDefectDataId = null;
  }

  Color _etapaColor(String? etapa) {
    switch (etapa) {
      case 'LQC':
        return Colors.orange;
      case 'OQC':
        return Colors.purpleAccent;
      case 'AIS':
        return Colors.cyan;
      default:
        return Colors.white38;
    }
  }

  Future<void> _showPreviousRepairDialog(
      Map<String, dynamic> previousRepair) async {
    final defects = (previousRepair['defects'] as List? ?? const [])
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
    final repairedAt = previousRepair['repaired_at']?.toString() ?? '';

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.panelBackground,
        title: Row(
          children: [
            const Icon(Icons.history_rounded, color: Colors.amber, size: 24),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                tr('pcb_previous_repair_title'),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 560,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                tr('pcb_previous_repair_hint'),
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
              if (repairedAt.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  '${tr('pcb_repaired_on')}: $repairedAt',
                  style: const TextStyle(color: Colors.white54, fontSize: 11),
                ),
              ],
              const SizedBox(height: 14),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: defects.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, index) {
                    final defect = defects[index];
                    final defectType = defect['defect_type']?.toString() ?? '';
                    final location =
                        defect['component_location']?.toString() ?? '';
                    final etapa = defect['etapa_deteccion']?.toString() ?? '';
                    final sourceArea =
                        defect['defect_source_area']?.toString() ?? '';
                    final details = <String>[
                      if (location.isNotEmpty)
                        '${tr('pcb_component_location')}: $location',
                      if (etapa.isNotEmpty)
                        '${tr('pcb_etapa_deteccion')}: $etapa',
                      if (sourceArea.isNotEmpty)
                        '${tr('pcb_source_area')}: $sourceArea',
                    ];

                    return Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.greenAccent.shade700),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 24,
                            height: 24,
                            alignment: Alignment.center,
                            decoration: const BoxDecoration(
                              color: Colors.green,
                              shape: BoxShape.circle,
                            ),
                            child: Text(
                              '${index + 1}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  defectType,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                if (details.isNotEmpty) ...[
                                  const SizedBox(height: 3),
                                  Text(
                                    details.join('  |  '),
                                    style: const TextStyle(
                                        color: Colors.white60, fontSize: 11),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          const Icon(Icons.check_circle,
                              color: Colors.greenAccent, size: 18),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        actions: [
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(ctx),
            icon: const Icon(Icons.arrow_forward, size: 16),
            label: Text(tr('continue')),
          ),
        ],
      ),
    );
  }

  Future<Map<String, dynamic>?> _showDefectVerificationDialog(
      List<Map<String, dynamic>> matches) async {
    return showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.panelBackground,
        title: Row(
          children: [
            const Icon(Icons.warning_amber_rounded,
                color: Colors.orange, size: 24),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                tr('pcb_verify_defect_title'),
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 560,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                tr('pcb_multiple_defects_hint'),
                style: const TextStyle(color: Colors.white60, fontSize: 12),
              ),
              const SizedBox(height: 10),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: matches.length,
                  separatorBuilder: (_, __) =>
                      const Divider(color: Colors.white12, height: 1),
                  itemBuilder: (_, i) {
                    final match = matches[i];
                    final etapa =
                        match['etapa_deteccion']?.toString().toUpperCase() ??
                            '';
                    final defecto = match['defecto']?.toString() ?? '';
                    final ubicacion = match['ubicacion']?.toString() ?? '';
                    final area = match['area']?.toString() ?? '';
                    final tipo = match['tipo_inspeccion']?.toString() ?? '';
                    final linea = match['linea']?.toString() ?? '';
                    final fecha = match['fecha']?.toString() ?? '';
                    return InkWell(
                      onTap: () => Navigator.pop(ctx, match),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: _etapaColor(etapa)
                                        .withValues(alpha: 0.2),
                                    borderRadius: BorderRadius.circular(3),
                                    border: Border.all(
                                        color: _etapaColor(etapa), width: 1),
                                  ),
                                  child: Text(
                                    etapa.isEmpty ? '?' : etapa,
                                    style: TextStyle(
                                      color: _etapaColor(etapa),
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    defecto,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                Text(
                                  fecha,
                                  style: const TextStyle(
                                      color: Colors.white54, fontSize: 11),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${tr('pcb_component_location')}: $ubicacion | ${tr('pcb_source_area')}: $area | $tipo | $linea',
                              style: const TextStyle(
                                  color: Colors.white60, fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, null),
            child: Text(tr('cancel'),
                style: const TextStyle(color: Colors.white70)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isRepairContext = _hasPendingArrayScans
        ? PcbAreas.isRepair(_pendingArrayTargetArea)
        : PcbAreas.isRepair(_selectedArea);
    final defectRows = _defectRows;
    final userRows = pcbUserRows;
    // defect_data can provide defect text not present in pcb_defect_catalog.
    final selectedDefectValue = _selectedDefectType;

    return Container(
      color: AppColors.subPanelBackground,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Persona que captura el escaneo
          Row(
            children: [
              SizedBox(
                width: 100,
                child: Text(tr('pcb_scanned_by'),
                    style: const TextStyle(fontSize: 14, color: Colors.white)),
              ),
              SizedBox(
                width: 260,
                child: TableDropdownField(
                  value: selectedPcbUserDisplay,
                  headers: ['ID', tr('full_name')],
                  rows: userRows,
                  tableWidth: 420,
                  tableHeight: 320,
                  onRowSelected: (index) {
                    if (selectPcbUserByIndex(index)) requestScanFocus();
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Fila 1: Area + Proceso + Fecha
          Row(
            children: [
              SizedBox(
                width: 60,
                child: Text(tr('pcb_area'),
                    style: const TextStyle(fontSize: 14, color: Colors.white)),
              ),
              SizedBox(
                width: 220,
                child: DropdownButtonFormField2<String>(
                  decoration: fieldDecoration(),
                  value: _selectedArea,
                  isExpanded: true,
                  style: const TextStyle(fontSize: 14, color: Colors.white),
                  items: _areas
                      .map((a) => DropdownMenuItem<String>(
                            value: a,
                            child: Text(PcbAreas.label(a),
                                style: const TextStyle(fontSize: 14)),
                          ))
                      .toList(),
                  onChanged: _hasPendingArrayScans
                      ? null
                      : (val) {
                          if (val != null) {
                            setState(() {
                              _selectedArea = val;
                              if (!PcbAreas.isRepair(val)) {
                                _resetDefectConfiguration();
                              }
                            });
                            _saveLocalPrefs();
                          }
                        },
                  iconStyleData: const IconStyleData(
                    icon: Icon(Icons.arrow_drop_down,
                        color: Colors.white70, size: 20),
                  ),
                  dropdownStyleData: DropdownStyleData(
                    maxHeight: 200,
                    decoration: BoxDecoration(
                      color: AppColors.fieldBackground,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    padding: EdgeInsets.zero,
                  ),
                  menuItemStyleData: const MenuItemStyleData(
                    height: 32,
                    padding: EdgeInsets.symmetric(horizontal: 10),
                  ),
                ),
              ),
              const SizedBox(width: 24),
              SizedBox(
                width: 80,
                child: Text(tr('pcb_proceso'),
                    style: const TextStyle(fontSize: 14, color: Colors.white)),
              ),
              SizedBox(
                width: 160,
                child: DropdownButtonFormField2<String>(
                  decoration: fieldDecoration(),
                  value: _selectedProceso,
                  isExpanded: true,
                  style: const TextStyle(fontSize: 14, color: Colors.white),
                  items: _procesos
                      .map((p) => DropdownMenuItem<String>(
                            value: p,
                            child:
                                Text(p, style: const TextStyle(fontSize: 14)),
                          ))
                      .toList(),
                  onChanged: _hasPendingArrayScans
                      ? null
                      : (val) {
                          if (val != null) {
                            setState(() => _selectedProceso = val);
                            _saveLocalPrefs();
                          }
                        },
                  iconStyleData: const IconStyleData(
                    icon: Icon(Icons.arrow_drop_down,
                        color: Colors.white70, size: 20),
                  ),
                  dropdownStyleData: DropdownStyleData(
                    maxHeight: 200,
                    decoration: BoxDecoration(
                      color: AppColors.fieldBackground,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    padding: EdgeInsets.zero,
                  ),
                  menuItemStyleData: const MenuItemStyleData(
                    height: 32,
                    padding: EdgeInsets.symmetric(horizontal: 10),
                  ),
                ),
              ),
              const SizedBox(width: 24),
              SizedBox(
                width: 90,
                child: Text(tr('pcb_array_count'),
                    style: const TextStyle(fontSize: 14, color: Colors.white)),
              ),
              SizedBox(
                width: 80,
                child: TextFormField(
                  controller: _arrayCountController,
                  decoration: fieldDecoration(),
                  style: const TextStyle(fontSize: 14),
                  enabled: !_hasPendingArrayScans,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  onChanged: (_) => _saveLocalPrefs(),
                ),
              ),
              const SizedBox(width: 24),
              SizedBox(
                width: 90,
                child: Text(tr('pcb_repair_count'),
                    style: const TextStyle(fontSize: 14, color: Colors.white)),
              ),
              SizedBox(
                width: 70,
                child: TextFormField(
                  controller: _repairCountController,
                  decoration: fieldDecoration(),
                  style: const TextStyle(fontSize: 14),
                  enabled: !_hasPendingArrayScans &&
                      PcbAreas.isRepair(_selectedArea),
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  onChanged: (_) => _saveLocalPrefs(),
                ),
              ),
              const SizedBox(width: 24),
              SizedBox(
                width: 60,
                child: Text(tr('pcb_date'),
                    style: const TextStyle(fontSize: 14, color: Colors.white)),
              ),
              Expanded(
                child: TextFormField(
                  controller: _dateController,
                  decoration: fieldDecoration().copyWith(
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.calendar_today,
                          color: Colors.white70, size: 18),
                      onPressed: _hasPendingArrayScans ? null : _pickDate,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                    suffixIconConstraints:
                        const BoxConstraints(minWidth: 30, minHeight: 20),
                  ),
                  style: const TextStyle(fontSize: 14),
                  readOnly: true,
                ),
              ),
            ],
          ),
          if (_hasPendingArrayScans) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.cyan.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: Colors.cyan.withValues(alpha: 0.30)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.qr_code_scanner,
                      color: Colors.cyan, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${tr('pcb_scan_remaining_array')}: $_pendingArrayRemaining / ${_pendingArrayCount - 1} (${PcbAreas.label(_pendingArrayTargetArea)}) | ${tr('pcb_area_repair_short')}: $_pendingRepairRemaining, ${tr('pcb_area_inventory_short')}: $_pendingInventoryRemaining',
                      style: const TextStyle(
                          color: Colors.cyan,
                          fontSize: 12,
                          fontWeight: FontWeight.w600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _cancelPendingArray,
                    icon: const Icon(Icons.close, size: 14),
                    label: Text(tr('pcb_cancel_array'),
                        style: const TextStyle(fontSize: 11)),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.white70,
                      minimumSize: const Size(0, 28),
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          // Fila 2: Defecto + Ubicacion de componente (solo reparacion)
          Row(
            children: [
              SizedBox(
                width: 110,
                child: Text(tr('pcb_defect_count'),
                    style: const TextStyle(fontSize: 14, color: Colors.white)),
              ),
              SizedBox(
                width: 60,
                child: TextFormField(
                  controller: _defectCountController,
                  decoration: fieldDecoration(),
                  style: const TextStyle(fontSize: 14),
                  enabled: isRepairContext && !_hasPendingArrayScans,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  onChanged: _onDefectCountChanged,
                  onFieldSubmitted: (_) async {
                    if (_defectCount >= 2 && !_isDefectDialogOpen) {
                      await _configureDefects(_defectCount);
                    }
                  },
                ),
              ),
              SizedBox(
                height: 36,
                width: 36,
                child: IconButton(
                  onPressed: isRepairContext && _defectCount >= 2
                      ? () => _configureDefects(_defectCount)
                      : null,
                  icon: const Icon(Icons.edit_note,
                      color: Colors.white70, size: 18),
                  tooltip: tr('pcb_configure_defects'),
                  padding: EdgeInsets.zero,
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 90,
                child: Text(tr('pcb_defect_type'),
                    style: const TextStyle(fontSize: 14, color: Colors.white)),
              ),
              SizedBox(
                width: 220,
                child: Opacity(
                  opacity: isRepairContext ? 1 : 0.55,
                  child: IgnorePointer(
                    ignoring: !isRepairContext,
                    child: TableDropdownField(
                      value: selectedDefectValue ?? '',
                      headers: [tr('pcb_defect_type'), tr('description')],
                      rows: defectRows,
                      tableWidth: 520,
                      tableHeight: 300,
                      onRowSelected: (index) {
                        if (index < 0 || index >= defectRows.length) return;
                        final defectName = defectRows[index].isNotEmpty
                            ? defectRows[index][0]
                            : '';
                        if (defectName.isEmpty) return;
                        setState(() {
                          _selectedDefectType = defectName;
                          _syncPrimaryDefectIntoConfiguration();
                        });
                        _saveLocalPrefs();
                      },
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                height: 36,
                width: 36,
                child: IconButton(
                  onPressed: _loadDefects,
                  icon: const Icon(Icons.refresh,
                      color: Colors.white70, size: 18),
                  tooltip: tr('pcb_refresh_defects'),
                  padding: EdgeInsets.zero,
                ),
              ),
              const SizedBox(width: 12),
              Container(
                height: 28,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: _etapaColor(_detectedEtapa).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                  border:
                      Border.all(color: _etapaColor(_detectedEtapa), width: 1),
                ),
                alignment: Alignment.center,
                child: Text(
                  _detectedEtapa ?? '-',
                  style: TextStyle(
                    color: _etapaColor(_detectedEtapa),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (_detectedSourceArea != null &&
                  _detectedSourceArea!.isNotEmpty) ...[
                const SizedBox(width: 6),
                Container(
                  height: 28,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    color: AppColors.gridBackground,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: Colors.white24, width: 1),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    '${tr('pcb_source_area')}: ${_detectedSourceArea!}',
                    style: const TextStyle(color: Colors.white70, fontSize: 11),
                  ),
                ),
              ],
              const SizedBox(width: 12),
              SizedBox(
                width: 150,
                child: Text(tr('pcb_component_location'),
                    style: const TextStyle(fontSize: 14, color: Colors.white)),
              ),
              Expanded(
                child: TextFormField(
                  controller: _componentLocationController,
                  decoration: fieldDecoration().copyWith(
                    hintText: tr('pcb_component_location_hint'),
                    hintStyle:
                        const TextStyle(fontSize: 12, color: Colors.white38),
                  ),
                  style: const TextStyle(fontSize: 14),
                  enabled: isRepairContext,
                  textCapitalization: TextCapitalization.characters,
                  onChanged: (_) {
                    _syncPrimaryDefectIntoConfiguration();
                    _saveLocalPrefs();
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Fila 2: Comentarios
          Row(
            children: [
              SizedBox(
                width: 100,
                child: Text(tr('pcb_comentarios'),
                    style: const TextStyle(fontSize: 14, color: Colors.white)),
              ),
              Expanded(
                child: TextFormField(
                  controller: _commentController,
                  decoration: fieldDecoration(),
                  style: const TextStyle(fontSize: 14),
                  onChanged: (_) => _saveLocalPrefs(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Fila 2: Scan field principal + Undo + Status
          Row(
            children: [
              SizedBox(
                width: 100,
                child: Text(tr('pcb_scan_field'),
                    style: const TextStyle(fontSize: 14, color: Colors.white)),
              ),
              Expanded(
                flex: 3,
                child: TextField(
                  controller: _scanController,
                  focusNode: _scanFocusNode,
                  style: const TextStyle(
                      fontSize: 14,
                      color: Colors.cyan,
                      fontWeight: FontWeight.w600),
                  decoration: fieldDecoration().copyWith(
                    hintText: tr('pcb_scan_field'),
                    hintStyle:
                        const TextStyle(fontSize: 12, color: Colors.white38),
                    prefixIcon: const Icon(Icons.qr_code_scanner,
                        color: Colors.cyan, size: 18),
                    prefixIconConstraints:
                        const BoxConstraints(minWidth: 32, minHeight: 20),
                    suffixIcon: _isLoading
                        ? const Padding(
                            padding: EdgeInsets.all(8),
                            child: SizedBox(
                                width: 16,
                                height: 16,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2)),
                          )
                        : null,
                  ),
                  onSubmitted: (_) => _onScan(),
                ),
              ),
              if (_lastInsertedIds.isNotEmpty) ...[
                const SizedBox(width: 8),
                SizedBox(
                  height: 36,
                  width: 36,
                  child: IconButton(
                    onPressed: _undoLastScan,
                    icon:
                        const Icon(Icons.undo, color: Colors.orange, size: 20),
                    tooltip: tr('pcb_undo_last'),
                    padding: EdgeInsets.zero,
                  ),
                ),
              ],
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: _statusMessage != null
                    ? Container(
                        height: 36,
                        alignment: Alignment.centerLeft,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        decoration: BoxDecoration(
                          color: _statusIsError
                              ? Colors.red.withValues(alpha: 0.15)
                              : Colors.green.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                              color: _statusIsError
                                  ? Colors.red.withValues(alpha: 0.3)
                                  : Colors.green.withValues(alpha: 0.3)),
                        ),
                        child: Text(
                          _statusMessage!,
                          style: TextStyle(
                              color: _statusIsError
                                  ? Colors.redAccent
                                  : Colors.green,
                              fontSize: 13),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      )
                    : const SizedBox(),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
