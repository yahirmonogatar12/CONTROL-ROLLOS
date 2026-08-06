import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:material_warehousing_flutter/core/localization/app_translations.dart';
import 'package:material_warehousing_flutter/core/models/solder_paste_process.dart';
import 'package:material_warehousing_flutter/core/services/api_service.dart';
import 'package:material_warehousing_flutter/core/services/auth_service.dart';
import 'package:material_warehousing_flutter/core/services/desktop_window_service.dart';
import 'package:material_warehousing_flutter/core/theme/app_colors.dart';
import 'package:material_warehousing_flutter/core/widgets/field_decoration.dart';
import 'package:material_warehousing_flutter/core/widgets/solder_paste_notification_overlay.dart';
import 'package:material_warehousing_flutter/screens/solder_paste/solder_paste_process_board.dart';

class SolderPasteScreen extends StatefulWidget {
  final LanguageProvider languageProvider;
  final bool enableBackgroundTasks;

  const SolderPasteScreen({
    super.key,
    required this.languageProvider,
    this.enableBackgroundTasks = true,
  });

  @override
  State<SolderPasteScreen> createState() => SolderPasteScreenState();
}

class SolderPasteScreenState extends State<SolderPasteScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final _processScanController = TextEditingController();
  final _statusScanController = TextEditingController();
  final _historySearchController = TextEditingController();
  final _processScanFocus = FocusNode();
  final _statusScanFocus = FocusNode();

  List<SolderPasteProcess> _processes = [];
  Map<String, dynamic>? _statusResult;
  SolderPasteProcess? _statusProcess;
  bool _loadingProcesses = false;
  bool _processingScan = false;
  bool _loadingStatus = false;
  bool _refreshingDueTransition = false;
  bool _enforceFifo = true;
  String _processFilter = 'active';
  int _lastEventId = 0;
  final Set<int> _notifiedProcesses = {};
  Timer? _clockTimer;
  Timer? _pollTimer;

  String get _username =>
      AuthService.currentUser?.username ??
      AuthService.currentUser?.nombreCompleto ??
      'Sistema';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(_handleTabChanged);
    if (widget.enableBackgroundTasks) {
      _clockTimer = Timer.periodic(
        const Duration(seconds: 1),
        (_) => _tickClock(),
      );
      _pollTimer = Timer.periodic(
        const Duration(seconds: 15),
        (_) => _pollEvents(),
      );
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await _loadProcesses(notifyCurrentReady: true);
        await _initializeEventCursor();
        requestScanFocus();
      });
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) => requestScanFocus());
    }
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    _pollTimer?.cancel();
    _tabController.removeListener(_handleTabChanged);
    _tabController.dispose();
    _processScanController.dispose();
    _statusScanController.dispose();
    _historySearchController.dispose();
    _processScanFocus.dispose();
    _statusScanFocus.dispose();
    super.dispose();
  }

  void _handleTabChanged() {
    if (_tabController.indexIsChanging) return;
    requestScanFocus();
  }

  void _tickClock() {
    if (!mounted) return;
    setState(() {});
    if (_hasDueTransition && !_refreshingDueTransition) {
      unawaited(_refreshDueTransitions());
    }
  }

  bool get _hasDueTransition => _processes.any((process) {
        switch (process.status) {
          case SolderPasteStatus.tempering:
            return process.ambientRemainingSeconds <= 0;
          case SolderPasteStatus.readyForAgitation:
            return process.readyForAgitationRemainingSeconds <= 0;
          case SolderPasteStatus.agitating:
            return process.agitationRemainingSeconds <= 0;
          case SolderPasteStatus.readyForLine:
          case SolderPasteStatus.inLine:
            return process.lineRemainingSeconds <= 0;
          default:
            return false;
        }
      });

  Future<void> _refreshDueTransitions() async {
    _refreshingDueTransition = true;
    try {
      await _loadProcesses(notifyCurrentReady: true);
    } finally {
      _refreshingDueTransition = false;
    }
  }

  void requestScanFocus() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_tabController.index == 0) {
        _processScanFocus.requestFocus();
      } else {
        _statusScanFocus.requestFocus();
      }
    });
  }

  void _showMessage(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? Colors.red.shade700 : Colors.green.shade700,
      ),
    );
  }

  Future<void> _openLargeDisplay() async {
    try {
      final openedOnSecondary =
          await DesktopWindowService.openSolderPasteDisplay();
      _showMessage(
        openedOnSecondary
            ? 'Monitor abierto en pantalla completa en la segunda pantalla'
            : 'No se detectó una segunda pantalla; monitor abierto en la pantalla principal',
      );
    } catch (error) {
      _showMessage(
        'No fue posible abrir el monitor: $error',
        error: true,
      );
    }
  }

  Future<void> _loadProcesses({bool notifyCurrentReady = false}) async {
    if (_loadingProcesses) return;
    setState(() => _loadingProcesses = true);
    final result = await ApiService.getSolderPasteProcesses(limit: 500);
    if (!mounted) return;
    if (result['success'] == true) {
      final rows = (result['processes'] as List? ?? const [])
          .whereType<Map>()
          .map((row) =>
              SolderPasteProcess.fromJson(Map<String, dynamic>.from(row)))
          .toList();
      setState(() => _processes = rows);
      if (notifyCurrentReady) {
        for (final process in rows.where(
            (item) => item.status == SolderPasteStatus.readyForAgitation)) {
          _notifyReady(process);
        }
      }
    } else {
      _showMessage(
          result['message']?.toString() ?? 'No se pudieron cargar los procesos',
          error: true);
    }
    if (mounted) setState(() => _loadingProcesses = false);
  }

  Future<void> _initializeEventCursor() async {
    final result = await ApiService.getSolderPasteEvents(limit: 1000);
    if (!mounted || result['success'] != true) return;
    final events = result['events'] as List? ?? const [];
    for (final event in events.whereType<Map>()) {
      final id = int.tryParse(event['id']?.toString() ?? '') ?? 0;
      if (id > _lastEventId) _lastEventId = id;
    }
  }

  Future<void> _pollEvents() async {
    final result = await ApiService.getSolderPasteEvents(
      afterId: _lastEventId,
      limit: 500,
    );
    if (!mounted || result['success'] != true) return;
    final events = result['events'] as List? ?? const [];
    var refresh = false;
    for (final raw in events.whereType<Map>()) {
      final event = Map<String, dynamic>.from(raw);
      final id = int.tryParse(event['id']?.toString() ?? '') ?? 0;
      if (id > _lastEventId) _lastEventId = id;
      refresh = true;
      if (event['event_type']?.toString() == 'AMBIENT_READY') {
        final processId =
            int.tryParse(event['process_id']?.toString() ?? '') ?? 0;
        final process =
            _processes.where((item) => item.id == processId).firstOrNull;
        if (process != null) _notifyReady(process);
      }
    }
    if (refresh) await _loadProcesses();
  }

  void _notifyReady(SolderPasteProcess process) {
    if (!_notifiedProcesses.add(process.id)) return;
    SolderPasteNotificationOverlay.instance.show(
      code: process.code,
      partNumber: process.partNumber,
    );
  }

  void _upsertProcess(SolderPasteProcess process) {
    final index = _processes.indexWhere((item) => item.id == process.id);
    setState(() {
      if (index >= 0) {
        _processes[index] = process;
      } else {
        _processes.insert(0, process);
      }
    });
  }

  Future<void> _scanProcess() async {
    if (!AuthService.canWriteSolderPaste) {
      _showMessage('No tiene permiso para operar pasta de soldadura',
          error: true);
      return;
    }
    final code = _processScanController.text.trim();
    if (code.isEmpty || _processingScan) return;
    setState(() => _processingScan = true);
    final result = await ApiService.scanSolderPaste(
      code: code,
      usuario: _username,
      usuarioId: AuthService.currentUser?.id,
      enforceFifo: _enforceFifo,
    );
    if (!mounted) return;
    setState(() => _processingScan = false);
    _processScanController.clear();
    requestScanFocus();
    if (result['success'] != true || result['process'] is! Map) {
      _showMessage(
          result['message']?.toString() ??
              result['error']?.toString() ??
              'No fue posible procesar la etiqueta',
          error: true);
      return;
    }
    final process = SolderPasteProcess.fromJson(
      Map<String, dynamic>.from(result['process'] as Map),
    );
    _upsertProcess(process);
    await _openActionForProcess(process);
  }

  Future<void> _openActionForProcess(SolderPasteProcess process) async {
    switch (process.status) {
      case SolderPasteStatus.tempering:
        await showDialog<void>(
          context: context,
          builder: (_) => _TemperingDialog(process: process),
        );
        break;
      case SolderPasteStatus.readyForAgitation:
        await _startOrResumeAgitation(process, startImmediately: false);
        break;
      case SolderPasteStatus.agitating:
        await _startOrResumeAgitation(process, startImmediately: true);
        break;
      case SolderPasteStatus.readyForLine:
        await _chooseLine(process);
        break;
      case SolderPasteStatus.inLine:
        _showMessage(
            'Material en ${process.lineCode}; restan ${_formatDuration(process.lineRemainingSeconds)}. Puede marcarlo como consumido o retornarlo al almacén.');
        break;
      case SolderPasteStatus.consumed:
        _showMessage('El material ya fue marcado como consumido');
        break;
      case SolderPasteStatus.scrap:
        _showMessage('El material venció y está registrado como scrap',
            error: true);
        break;
      case SolderPasteStatus.cancelled:
        _showMessage(
            'El proceso está cancelado; vuelva a escanear para iniciar un ciclo nuevo');
        break;
      case SolderPasteStatus.returnedToCold:
        _showMessage(
            'El material retornó al almacén/refrigerador y puede iniciar un ciclo nuevo respetando FIFO');
        break;
      case SolderPasteStatus.unknown:
        break;
    }
  }

  Future<void> _startOrResumeAgitation(
    SolderPasteProcess process, {
    required bool startImmediately,
  }) async {
    var current = process;
    if (!startImmediately) {
      final start = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          backgroundColor: AppColors.panelBackground,
          shape: RoundedRectangleBorder(
            side: const BorderSide(color: AppColors.border),
            borderRadius: BorderRadius.circular(4),
          ),
          title: const Row(
            children: [
              Icon(Icons.cyclone, color: AppColors.headerTab),
              SizedBox(width: 10),
              Text('Agitación', style: TextStyle(color: Colors.white)),
            ],
          ),
          content: Text(
            'Coloque ${process.code} en el agitador. El temporizador de 60 segundos inicia al presionar el botón.',
            style: const TextStyle(color: Colors.white70),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cerrar'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.pop(dialogContext, true),
              icon: const Icon(Icons.play_arrow),
              label: const Text('Iniciar'),
            ),
          ],
        ),
      );
      if (start != true || !mounted) return;
      final result = await ApiService.startSolderPasteAgitation(
        process.id,
        usuario: _username,
      );
      if (!mounted || result['success'] != true || result['process'] is! Map) {
        _showMessage(
            result['message']?.toString() ??
                'No fue posible iniciar la agitación',
            error: true);
        return;
      }
      current = SolderPasteProcess.fromJson(
        Map<String, dynamic>.from(result['process'] as Map),
      );
      _upsertProcess(current);
      if (current.status == SolderPasteStatus.scrap) {
        _showMessage(
          'La ventana de 8 horas venció; el material fue enviado a scrap',
          error: true,
        );
        return;
      }
    }

    var completed = false;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _AgitationCountdownDialog(
        process: current,
        onCompleted: () => completed = true,
      ),
    );
    if (completed && mounted) {
      await _loadProcesses();
      final refreshed =
          _processes.where((item) => item.id == current.id).firstOrNull ??
              current;
      await _chooseLine(refreshed);
    }
  }

  Future<void> _chooseLine(SolderPasteProcess process) async {
    final line = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _LineSelectionDialog(process: process),
    );
    if (line == null || !mounted) return;
    final result = await ApiService.assignSolderPasteLine(
      process.id,
      line: line,
      usuario: _username,
    );
    if (!mounted || result['success'] != true || result['process'] is! Map) {
      _showMessage(
          result['message']?.toString() ?? 'No fue posible asignar la línea',
          error: true);
      return;
    }
    final updated = SolderPasteProcess.fromJson(
      Map<String, dynamic>.from(result['process'] as Map),
    );
    _upsertProcess(updated);
    _showMessage('Línea actualizada. ${updated.code} enviado a $line');
  }

  Future<void> _consume(SolderPasteProcess process) async {
    final confirmed = await _confirm(
      'Material consumido',
      '¿Confirma que ${process.code} fue consumido por completo?',
    );
    if (!confirmed) return;
    final result =
        await ApiService.consumeSolderPaste(process.id, usuario: _username);
    if (!mounted || result['success'] != true || result['process'] is! Map) {
      _showMessage(
          result['message']?.toString() ?? 'No fue posible cerrar el proceso',
          error: true);
      return;
    }
    _upsertProcess(SolderPasteProcess.fromJson(
      Map<String, dynamic>.from(result['process'] as Map),
    ));
    _showMessage('Material marcado como consumido');
  }

  Future<void> _returnToCold(SolderPasteProcess process) async {
    final returningFromLine = process.status == SolderPasteStatus.inLine;
    final recoveringScrap = process.status == SolderPasteStatus.scrap;
    final confirmed = await _confirm(
      recoveringScrap
          ? 'Autorizar retorno de Scrap'
          : returningFromLine
              ? 'Retornar de línea al almacén'
              : 'Regresar al refrigerador',
      recoveringScrap
          ? 'Esta acción confirma que ${process.code} nunca fue abierto ni llegó a línea. Se revertirá el registro automático de scrap, se devolverá al refrigerador y el próximo escaneo iniciará un ciclo nuevo. ¿Autorizar retorno?'
          : returningFromLine
              ? 'Se retirará ${process.code} de ${process.lineCode ?? 'la línea'}, se registrará la devolución en Almacén, la salida quedará en cero y el próximo escaneo iniciará un ciclo nuevo. ¿Confirmar retorno al refrigerador?'
              : 'Se registrará la devolución en Almacén, la salida quedará en cero y el próximo escaneo iniciará un ciclo nuevo automáticamente. ¿Confirmar retorno?',
    );
    if (!confirmed) return;
    final result = await ApiService.returnSolderPasteToCold(
      process.id,
      usuario: _username,
      usuarioId: AuthService.currentUser?.id,
    );
    if (!mounted || result['success'] != true || result['process'] is! Map) {
      _showMessage(
        result['message']?.toString() ??
            'No fue posible regresar el material al refrigerador',
        error: true,
      );
      return;
    }
    final updated = SolderPasteProcess.fromJson(
      Map<String, dynamic>.from(result['process'] as Map),
    );
    _upsertProcess(updated);
    if (updated.status == SolderPasteStatus.scrap) {
      _showMessage(
        'La ventana de 8 horas ya venció; el material fue enviado a scrap',
        error: true,
      );
      return;
    }
    _showMessage(recoveringScrap
        ? 'Scrap revertido con autorización; el próximo escaneo iniciará un ciclo nuevo'
        : 'Material retornado al refrigerador; el próximo escaneo iniciará un ciclo nuevo automáticamente');
  }

  Future<void> _cancel(SolderPasteProcess process) async {
    final confirmed = await _confirm(
      'Cancelar proceso',
      'La salida se marcará como cancelada, la etiqueta volverá a quedar disponible y la cancelación se conservará en el historial. ¿Continuar?',
    );
    if (!confirmed) return;
    final result =
        await ApiService.cancelSolderPaste(process.id, usuario: _username);
    if (!mounted || result['success'] != true || result['process'] is! Map) {
      _showMessage(result['message']?.toString() ?? 'No fue posible cancelar',
          error: true);
      return;
    }
    _upsertProcess(SolderPasteProcess.fromJson(
      Map<String, dynamic>.from(result['process'] as Map),
    ));
    _showMessage('Proceso y salida cancelados; etiqueta liberada');
  }

  Future<bool> _confirm(String title, String body) async {
    return await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            backgroundColor: AppColors.panelBackground,
            shape: RoundedRectangleBorder(
              side: const BorderSide(color: AppColors.border),
              borderRadius: BorderRadius.circular(4),
            ),
            title: Text(title, style: const TextStyle(color: Colors.white)),
            content: Text(body, style: const TextStyle(color: Colors.white70)),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('No'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Sí, confirmar'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _queryStatus() async {
    final code = _statusScanController.text.trim();
    if (code.isEmpty || _loadingStatus) return;
    setState(() => _loadingStatus = true);
    final result = await ApiService.getSolderPasteStatus(code);
    if (!mounted) return;
    setState(() {
      _loadingStatus = false;
      _statusResult = result['success'] == true ? result : null;
      final rawProcess = result['process'];
      _statusProcess = result['success'] == true && rawProcess is Map
          ? SolderPasteProcess.fromJson(
              Map<String, dynamic>.from(rawProcess),
            )
          : null;
    });
    if (result['success'] != true) {
      _showMessage(result['message']?.toString() ?? 'No fue posible consultar',
          error: true);
    }
    _statusScanController.clear();
    requestScanFocus();
  }

  Color _statusColor(SolderPasteStatus status) {
    switch (status) {
      case SolderPasteStatus.readyForAgitation:
      case SolderPasteStatus.readyForLine:
        return Colors.orangeAccent;
      case SolderPasteStatus.consumed:
        return Colors.greenAccent;
      case SolderPasteStatus.scrap:
        return Colors.redAccent;
      case SolderPasteStatus.cancelled:
      case SolderPasteStatus.returnedToCold:
        return Colors.grey;
      case SolderPasteStatus.inLine:
        return Colors.purpleAccent;
      default:
        return AppColors.headerTab;
    }
  }

  String _formatDuration(int seconds) {
    final safe = seconds < 0 ? 0 : seconds;
    final hours = safe ~/ 3600;
    final minutes = (safe % 3600) ~/ 60;
    final secs = safe % 60;
    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  String _formatDate(DateTime? value) {
    if (value == null) return '—';
    final v = value.toLocal();
    String d(int n) => n.toString().padLeft(2, '0');
    return '${d(v.day)}/${d(v.month)}/${v.year} ${d(v.hour)}:${d(v.minute)}:${d(v.second)}';
  }

  List<SolderPasteProcess> get _filteredProcesses {
    final search = _historySearchController.text.trim().toLowerCase();
    return _processes.where((item) {
      if (_processFilter == 'active' && !item.isActive) return false;
      if (_processFilter == 'history' && item.isActive) return false;
      if (search.isEmpty) return true;
      return item.code.toLowerCase().contains(search) ||
          item.partNumber.toLowerCase().contains(search) ||
          (item.lineCode ?? '').toLowerCase().contains(search);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.gridBackground,
      child: Column(
        children: [
          Container(
            height: 52,
            decoration: const BoxDecoration(
              color: AppColors.panelBackground,
              border: Border(
                bottom: BorderSide(color: AppColors.border, width: 1),
              ),
            ),
            child: TabBar(
              controller: _tabController,
              indicatorColor: AppColors.headerTab,
              indicatorWeight: 3,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white54,
              tabs: const [
                Tab(
                    icon: Icon(Icons.science_outlined),
                    text: 'Proceso y seguimiento'),
                Tab(icon: Icon(Icons.manage_search), text: 'Consultar estatus'),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildProcessTab(),
                _buildStatusTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProcessTab() {
    return Column(
      children: [
        _ScanPanel(
          title: 'Escanear pasta de soldadura',
          subtitle: _enforceFifo
              ? 'Salida FIFO · 2 h a temperatura ambiente · Agitar o retornar antes de 8 h'
              : 'FIFO desactivado · 2 h a temperatura ambiente · Agitar o retornar antes de 8 h',
          controller: _processScanController,
          focusNode: _processScanFocus,
          busy: _processingScan,
          enabled: AuthService.canWriteSolderPaste,
          onSubmit: _scanProcess,
          checkboxValue: _enforceFifo,
          checkboxTooltip: _enforceFifo
              ? 'FIFO de Almacén activado'
              : 'FIFO de Almacén desactivado',
          onCheckboxChanged: AuthService.canWriteSolderPaste && !_processingScan
              ? (value) => setState(() => _enforceFifo = value ?? false)
              : null,
        ),
        Container(
          color: AppColors.panelBackground,
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 1000;
              return Row(
                children: [
                  SizedBox(
                    width: compact ? 220 : 320,
                    height: 32,
                    child: TextField(
                      controller: _historySearchController,
                      onChanged: (_) => setState(() {}),
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                      decoration: fieldDecoration(
                        hintText: 'Buscar etiqueta, parte o línea',
                      ).copyWith(
                        prefixIcon: const Icon(
                          Icons.search,
                          color: Colors.white70,
                          size: 17,
                        ),
                        prefixIconConstraints:
                            const BoxConstraints(minWidth: 34, minHeight: 24),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: compact ? 150 : 170,
                    height: 32,
                    child: DropdownButtonFormField<String>(
                      initialValue: _processFilter,
                      isExpanded: true,
                      dropdownColor: AppColors.fieldBackground,
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                      decoration: fieldDecoration(),
                      items: const [
                        DropdownMenuItem(
                            value: 'active', child: Text('Procesos activos')),
                        DropdownMenuItem(
                            value: 'history', child: Text('Historial')),
                        DropdownMenuItem(value: 'all', child: Text('Todos')),
                      ],
                      onChanged: (value) =>
                          setState(() => _processFilter = value ?? 'active'),
                    ),
                  ),
                  const Spacer(),
                  if (DesktopWindowService.isSupported) ...[
                    Tooltip(
                      message: 'Abrir en pantalla grande',
                      child: SizedBox(
                        width: compact ? 36 : null,
                        height: 30,
                        child: ElevatedButton(
                          onPressed: _openLargeDisplay,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.buttonSearch,
                            foregroundColor: Colors.white,
                            padding: EdgeInsets.symmetric(
                              horizontal: compact ? 0 : 12,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.open_in_new, size: 16),
                              if (!compact) ...[
                                const SizedBox(width: 8),
                                const Text(
                                  'Abrir en pantalla grande',
                                  style: TextStyle(fontSize: 11),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  SizedBox(
                    height: 30,
                    child: ElevatedButton.icon(
                      onPressed: _loadProcesses,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.buttonSearch,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      icon: const Icon(Icons.refresh, size: 16),
                      label: const Text('Actualizar',
                          style: TextStyle(fontSize: 11)),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
        Expanded(child: _buildProcessGrid()),
      ],
    );
  }

  Widget _buildProcessGrid() {
    return SolderPasteProcessBoard(
      processes: _filteredProcesses,
      loading: _loadingProcesses,
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      actionBuilder: _buildProcessActions,
    );
  }

  Widget _buildProcessActions(SolderPasteProcess process) {
    final actions = <PopupMenuEntry<String>>[];
    final canRecoverScrap = process.canRecoverUnopenedScrapToCold &&
        AuthService.canAuthorizeSolderPasteScrapReturn;
    if (process.status == SolderPasteStatus.tempering) {
      actions.add(
          const PopupMenuItem(value: 'open', child: Text('Ver temporizador')));
    }
    if (process.status == SolderPasteStatus.readyForAgitation ||
        process.status == SolderPasteStatus.agitating) {
      actions.add(
          const PopupMenuItem(value: 'open', child: Text('Abrir agitación')));
    }
    if ((process.canReturnToCold && AuthService.canWriteSolderPaste) ||
        canRecoverScrap) {
      actions.add(PopupMenuItem(
        value: 'return-to-cold',
        child: Text(canRecoverScrap
            ? 'Autorizar retorno de Scrap al refrigerador'
            : 'Retornar al almacén (refrigerador)'),
      ));
    }
    if (process.status == SolderPasteStatus.readyForLine) {
      actions.add(
          const PopupMenuItem(value: 'open', child: Text('Seleccionar línea')));
    }
    if (process.status == SolderPasteStatus.inLine) {
      actions.add(const PopupMenuItem(
          value: 'consume', child: Text('Material consumido')));
    }
    if (process.canCancel) {
      actions.add(const PopupMenuItem(
          value: 'cancel', child: Text('Cancelar proceso')));
    }
    if (actions.isEmpty) return const SizedBox.shrink();
    return PopupMenuButton<String>(
      tooltip: 'Acciones',
      color: AppColors.panelBackground,
      iconColor: Colors.white70,
      itemBuilder: (_) => actions,
      onSelected: (value) {
        if (value == 'open') _openActionForProcess(process);
        if (value == 'consume') _consume(process);
        if (value == 'return-to-cold') _returnToCold(process);
        if (value == 'cancel') _cancel(process);
      },
    );
  }

  Widget _buildStatusTab() {
    return Column(
      children: [
        _ScanPanel(
          title: 'Consultar estatus por etiqueta',
          subtitle:
              'Consulta de solo lectura: no inicia ni modifica el proceso',
          controller: _statusScanController,
          focusNode: _statusScanFocus,
          busy: _loadingStatus,
          enabled: AuthService.canViewSolderPaste,
          onSubmit: _queryStatus,
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: _statusResult == null
                ? const Center(
                    child: Text(
                      'Escanee una etiqueta para consultar su estado',
                      style: TextStyle(color: Colors.white54, fontSize: 14),
                    ),
                  )
                : _buildStatusResult(),
          ),
        ),
      ],
    );
  }

  Widget _buildStatusResult() {
    final process = _statusProcess;
    if (process == null) {
      final severity = _statusResult!['severity']?.toString() ?? 'info';
      final color = severity == 'danger'
          ? Colors.redAccent
          : severity == 'warning'
              ? Colors.orangeAccent
              : AppColors.headerTab;
      final inventory = _statusResult!['inventory'] is Map
          ? Map<String, dynamic>.from(_statusResult!['inventory'] as Map)
          : <String, dynamic>{};
      return _StatusShell(
        color: color,
        title: _statusResult!['message']?.toString() ?? 'Sin proceso',
        code: inventory['codigo_material_recibido']?.toString() ?? '',
        nextAction: _statusResult!['next_action']?.toString() ?? '',
        child: _InfoGrid(items: [
          ('Número de parte', inventory['numero_parte']?.toString() ?? '—'),
          ('Stock actual', inventory['stock_actual']?.toString() ?? '—'),
          (
            'Estado de inventario',
            _statusResult!['inventory_status']?.toString() ?? '—'
          ),
        ]),
      );
    }

    final color = _statusColor(process.status);
    final events = (_statusResult!['events'] as List? ?? const [])
        .whereType<Map>()
        .toList();
    final latestEvent = events.isEmpty
        ? '—'
        : '${events.first['event_type'] ?? 'Evento'} · ${events.first['created_at'] ?? ''}';
    return SingleChildScrollView(
      child: _StatusShell(
        color: color,
        title: process.status.displayName,
        code: process.code,
        nextAction: process.nextAction,
        child: Column(
          children: [
            _InfoGrid(items: [
              (
                'Número de parte',
                process.partNumber.isEmpty ? '—' : process.partNumber
              ),
              ('Usuario inicial', process.startedBy),
              (
                'Salida del refrigerador',
                _formatDate(process.removedFromColdAt)
              ),
              (
                'Listo a temperatura ambiente',
                _formatDate(process.ambientReadyAt)
              ),
              (
                'Tiempo ambiente transcurrido',
                _formatDuration(process.ambientElapsedSeconds)
              ),
              (
                'Tiempo ambiente restante',
                _formatDuration(process.ambientRemainingSeconds)
              ),
              (
                'Límite para iniciar agitación',
                _formatDate(process.agitationDeadlineAt)
              ),
              (
                'Tiempo restante para agitar o retornar',
                _formatDuration(process.readyForAgitationRemainingSeconds)
              ),
              ('Inicio de agitación', _formatDate(process.agitationStartedAt)),
              (
                'Fin de agitación',
                _formatDate(
                    process.agitationCompletedAt ?? process.agitationReadyAt)
              ),
              ('Línea asignada', process.lineCode ?? '—'),
              ('Inicio en línea', _formatDate(process.lineStartedAt)),
              (
                'Retorno al refrigerador',
                _formatDate(process.returnedToColdAt)
              ),
              (
                'Vida en línea restante',
                _formatDuration(process.lineRemainingSeconds)
              ),
              (
                'Cantidad retirada',
                process.issuedQuantity == null
                    ? '—'
                    : '${process.issuedQuantity} ${process.unit ?? ''}'
              ),
              ('Último evento registrado', latestEvent),
            ]),
            const SizedBox(height: 18),
            Align(
              alignment: Alignment.centerLeft,
              child: Text('Línea de tiempo (${events.length})',
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16)),
            ),
            const SizedBox(height: 8),
            ...events.map((event) => ListTile(
                  dense: true,
                  leading: Icon(Icons.circle, size: 12, color: color),
                  title: Text(event['event_type']?.toString() ?? 'Evento',
                      style: const TextStyle(color: Colors.white)),
                  subtitle: Text(
                    '${event['usuario'] ?? 'Sistema'} · ${event['created_at'] ?? ''}',
                    style: const TextStyle(color: Colors.white54),
                  ),
                )),
          ],
        ),
      ),
    );
  }
}

class _ScanPanel extends StatelessWidget {
  final String title;
  final String subtitle;
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool busy;
  final bool enabled;
  final VoidCallback onSubmit;
  final bool? checkboxValue;
  final String? checkboxTooltip;
  final ValueChanged<bool?>? onCheckboxChanged;

  const _ScanPanel({
    required this.title,
    required this.subtitle,
    required this.controller,
    required this.focusNode,
    required this.busy,
    required this.enabled,
    required this.onSubmit,
    this.checkboxValue,
    this.checkboxTooltip,
    this.onCheckboxChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.panelBackground,
      child: Column(
        children: [
          Container(
            height: 32,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: const BoxDecoration(
              color: AppColors.gridHeader,
              border: Border(
                bottom: BorderSide(color: AppColors.border, width: 1),
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.qr_code_scanner,
                    color: Colors.white, size: 17),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(
                  width: 160,
                  height: 34,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Código de etiqueta',
                      style: TextStyle(color: Colors.white, fontSize: 13),
                    ),
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        height: 34,
                        child: TextField(
                          controller: controller,
                          focusNode: focusNode,
                          enabled: enabled && !busy,
                          autofocus: true,
                          onSubmitted: (_) => onSubmit(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontFamily: 'monospace',
                            fontSize: 13,
                          ),
                          decoration: fieldDecoration(
                            hintText: '49111007000-202607060055',
                          ).copyWith(
                            prefixIcon: const Icon(
                              Icons.qr_code_2,
                              color: Colors.white70,
                              size: 18,
                            ),
                            prefixIconConstraints: const BoxConstraints(
                              minWidth: 36,
                              minHeight: 24,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                if (checkboxValue != null) ...[
                  const SizedBox(width: 6),
                  Tooltip(
                    message: checkboxTooltip ?? 'FIFO de Almacén',
                    child: SizedBox(
                      width: 34,
                      height: 34,
                      child: Center(
                        child: Transform.scale(
                          scale: 0.85,
                          child: Checkbox(
                            key: const ValueKey('solderPasteFifoCheckbox'),
                            value: checkboxValue,
                            onChanged: onCheckboxChanged,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
                const SizedBox(width: 10),
                SizedBox(
                  width: 112,
                  height: 34,
                  child: ElevatedButton.icon(
                    onPressed: enabled && !busy ? onSubmit : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.buttonSearch,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: AppColors.buttonGray,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    icon: busy
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.search, size: 16),
                    label: Text(
                      title.startsWith('Consultar') ? 'Consultar' : 'Procesar',
                      style: const TextStyle(fontSize: 11),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LineSelectionDialog extends StatelessWidget {
  final SolderPasteProcess process;

  const _LineSelectionDialog({required this.process});

  @override
  Widget build(BuildContext context) {
    const options = <(String, String, Color)>[
      ('SMT A', 'A', Color(0xFF42A5F5)),
      ('SMT B', 'B', Color(0xFF26A69A)),
      ('SMT C', 'C', Color(0xFFFFB74D)),
      ('SMT D', 'D', Color(0xFFAB47BC)),
      ('SMT E', 'E', Color(0xFFEF5350)),
    ];

    return Dialog(
      backgroundColor: AppColors.panelBackground,
      shape: RoundedRectangleBorder(
        side: const BorderSide(color: AppColors.border),
        borderRadius: BorderRadius.circular(4),
      ),
      child: SizedBox(
        width: 620,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: 58,
              padding: const EdgeInsets.only(left: 16, right: 8),
              decoration: const BoxDecoration(
                color: AppColors.gridHeader,
                border: Border(
                  bottom: BorderSide(color: AppColors.border),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.precision_manufacturing_outlined,
                    color: Colors.white,
                    size: 25,
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Seleccionar línea SMT',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          'Elige el destino del material',
                          style: TextStyle(
                            color: Colors.white60,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Cerrar',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, color: Colors.white70),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.gridRowEven,
                      border: Border.all(color: Colors.white12),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.science_outlined,
                          color: AppColors.headerTab,
                          size: 24,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                process.code,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                process.partNumber.isEmpty
                                    ? 'Sin número de parte'
                                    : process.partNumber,
                                style: const TextStyle(
                                  color: Colors.white54,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Text(
                          'LISTO PARA LÍNEA',
                          style: TextStyle(
                            color: Colors.orangeAccent,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Selecciona una línea',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  GridView.count(
                    crossAxisCount: 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    childAspectRatio: 3.2,
                    children: options
                        .map((option) => _buildLineCard(
                              context,
                              line: option.$1,
                              letter: option.$2,
                              color: option.$3,
                            ))
                        .toList(),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 9,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.orange.withValues(alpha: .10),
                      border: const Border(
                        left: BorderSide(color: Colors.orangeAccent, width: 4),
                      ),
                    ),
                    child: const Row(
                      children: [
                        Icon(
                          Icons.info_outline,
                          color: Colors.orangeAccent,
                          size: 18,
                        ),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'La asignación registra la salida total del material y la línea ya no podrá cambiarse.',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLineCard(
    BuildContext context, {
    required String line,
    required String letter,
    required Color color,
  }) {
    return Material(
      color: Colors.transparent,
      child: Ink(
        decoration: BoxDecoration(
          color: AppColors.gridRowOdd,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: color.withValues(alpha: .75)),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(4),
          onTap: () => Navigator.pop(context, line),
          child: Row(
            children: [
              Container(
                width: 62,
                height: double.infinity,
                alignment: Alignment.center,
                color: color.withValues(alpha: .18),
                child: Text(
                  letter,
                  style: TextStyle(
                    color: color,
                    fontSize: 27,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      line,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Text(
                      'Asignar material',
                      style: TextStyle(color: Colors.white54, fontSize: 10),
                    ),
                  ],
                ),
              ),
              Icon(Icons.arrow_forward_ios, color: color, size: 15),
              const SizedBox(width: 12),
            ],
          ),
        ),
      ),
    );
  }
}

class _TemperingDialog extends StatefulWidget {
  final SolderPasteProcess process;
  const _TemperingDialog({required this.process});

  @override
  State<_TemperingDialog> createState() => _TemperingDialogState();
}

class _TemperingDialogState extends State<_TemperingDialog> {
  Timer? _timer;
  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final remaining = widget.process.ambientRemainingSeconds;
    return AlertDialog(
      backgroundColor: AppColors.panelBackground,
      shape: RoundedRectangleBorder(
        side: const BorderSide(color: AppColors.border),
        borderRadius: BorderRadius.circular(4),
      ),
      title: const Row(
        children: [
          Icon(Icons.science_outlined, color: AppColors.headerTab, size: 34),
          SizedBox(width: 12),
          Text('Temperatura ambiente', style: TextStyle(color: Colors.white)),
        ],
      ),
      content: SizedBox(
        width: 500,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(widget.process.code,
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'monospace')),
            const SizedBox(height: 14),
            const Text('Dejar el bote a temperatura ambiente durante 2 horas.',
                style: TextStyle(color: Colors.white70)),
            const SizedBox(height: 18),
            Text(_durationText(remaining),
                style: const TextStyle(
                    color: AppColors.headerTab,
                    fontSize: 34,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            LinearProgressIndicator(
              value: widget.process.ambientProgress,
              minHeight: 12,
              borderRadius: BorderRadius.circular(3),
              backgroundColor: Colors.white12,
              valueColor: const AlwaysStoppedAnimation(AppColors.headerTab),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cerrar')),
      ],
    );
  }
}

class _AgitationCountdownDialog extends StatefulWidget {
  final SolderPasteProcess process;
  final VoidCallback onCompleted;
  const _AgitationCountdownDialog(
      {required this.process, required this.onCompleted});

  @override
  State<_AgitationCountdownDialog> createState() =>
      _AgitationCountdownDialogState();
}

class _AgitationCountdownDialogState extends State<_AgitationCountdownDialog>
    with SingleTickerProviderStateMixin {
  Timer? _timer;
  late final AnimationController _shakeController;
  bool _completed = false;

  @override
  void initState() {
    super.initState();
    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 360),
    )..repeat();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    WidgetsBinding.instance.addPostFrameCallback((_) => _tick());
  }

  void _tick() {
    if (!mounted || _completed) return;
    if (widget.process.agitationRemainingSeconds <= 0) {
      _completed = true;
      widget.onCompleted();
      Navigator.pop(context);
      return;
    }
    setState(() {});
  }

  @override
  void dispose() {
    _timer?.cancel();
    _shakeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final remaining = widget.process.agitationRemainingSeconds;
    return PopScope(
      canPop: false,
      child: AlertDialog(
        backgroundColor: AppColors.panelBackground,
        shape: RoundedRectangleBorder(
          side: const BorderSide(color: AppColors.border),
          borderRadius: BorderRadius.circular(4),
        ),
        title: const Text('Agitación en proceso',
            style: TextStyle(color: Colors.white)),
        content: SizedBox(
          width: 430,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedBuilder(
                animation: _shakeController,
                child: const _SolderPasteJar(),
                builder: (context, child) {
                  final wave = math.sin(
                    _shakeController.value * math.pi * 2,
                  );
                  return Transform.translate(
                    offset: Offset(wave * 11, 0),
                    child: Transform.rotate(
                      angle: wave * .13,
                      child: child,
                    ),
                  );
                },
              ),
              const SizedBox(height: 5),
              const Text(
                'Agitando bote de pasta',
                style: TextStyle(
                  color: AppColors.headerTab,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text('$remaining',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 56,
                      fontWeight: FontWeight.bold)),
              const Text('segundos', style: TextStyle(color: Colors.white54)),
              const SizedBox(height: 14),
              _ConsumptionProgressBar(
                consumed: widget.process.agitationProgress,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SolderPasteJar extends StatelessWidget {
  const _SolderPasteJar();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Bote de pasta de soldadura agitándose',
      child: SizedBox(
        width: 108,
        height: 96,
        child: Stack(
          alignment: Alignment.topCenter,
          children: [
            Positioned(
              top: 15,
              left: 12,
              right: 12,
              bottom: 2,
              child: Container(
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xFFD8E0E4), Color(0xFF8C9AA1)],
                  ),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.headerTab, width: 3),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black38,
                      blurRadius: 5,
                      offset: Offset(0, 3),
                    ),
                  ],
                ),
                child: Center(
                  child: Container(
                    width: 58,
                    height: 34,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF4F6F7),
                      border: Border.all(color: AppColors.gridHeader),
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: const Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'PASTA',
                          style: TextStyle(
                            color: AppColors.gridHeader,
                            fontSize: 11,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.2,
                          ),
                        ),
                        Text(
                          'SOLDADURA',
                          style: TextStyle(
                            color: AppColors.gridHeader,
                            fontSize: 7,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 2,
              width: 70,
              height: 22,
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.buttonGray,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.white54),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: List.generate(
                    3,
                    (_) => Container(height: 1, color: Colors.white38),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 28,
              left: 24,
              width: 8,
              height: 38,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .35),
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConsumptionProgressBar extends StatelessWidget {
  final double consumed;

  const _ConsumptionProgressBar({required this.consumed});

  @override
  Widget build(BuildContext context) {
    final consumedValue = consumed.clamp(0.0, 1.0);
    final remainingValue = 1 - consumedValue;
    return LayoutBuilder(
      builder: (context, constraints) => ClipRRect(
        borderRadius: BorderRadius.circular(7),
        child: SizedBox(
          height: 28,
          child: Stack(
            children: [
              const Positioned.fill(
                child: ColoredBox(color: Color(0xFFD95C60)),
              ),
              AnimatedContainer(
                duration: const Duration(milliseconds: 450),
                curve: Curves.easeOut,
                width: constraints.maxWidth * remainingValue,
                color: const Color(0xFF59A96B),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusShell extends StatelessWidget {
  final Color color;
  final String title;
  final String code;
  final String nextAction;
  final Widget child;
  const _StatusShell(
      {required this.color,
      required this.title,
      required this.code,
      required this.nextAction,
      required this.child});
  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: AppColors.gridBackground,
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          children: [
            Container(
              constraints: const BoxConstraints(minHeight: 48),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: const BoxDecoration(
                color: AppColors.gridHeader,
                border: Border(
                  bottom: BorderSide(color: AppColors.border, width: 1),
                ),
              ),
              child: Row(
                children: [
                  Container(width: 4, height: 30, color: color),
                  const SizedBox(width: 10),
                  Icon(Icons.science_outlined, color: color, size: 24),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            color: color,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (code.isNotEmpty)
                          Text(
                            code,
                            style: const TextStyle(
                              color: Colors.white,
                              fontFamily: 'monospace',
                              fontSize: 12,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: .10),
                      border: Border(
                        left: BorderSide(color: color, width: 4),
                      ),
                    ),
                    child: Text(
                      'Siguiente paso: $nextAction',
                      style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  child,
                ],
              ),
            ),
          ],
        ),
      );
}

class _InfoGrid extends StatelessWidget {
  final List<(String, String)> items;
  const _InfoGrid({required this.items});
  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth > 900
              ? (constraints.maxWidth - 24) / 3
              : (constraints.maxWidth - 12) / 2;
          return Wrap(
            spacing: 8,
            runSpacing: 8,
            children: items.indexed
                .map((entry) => SizedBox(
                      width: width,
                      child: Container(
                        constraints: const BoxConstraints(minHeight: 52),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 7),
                        decoration: BoxDecoration(
                          color: entry.$1.isEven
                              ? AppColors.gridRowEven
                              : AppColors.gridRowOdd,
                          border: Border.all(color: Colors.white12, width: .5),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(entry.$2.$1,
                                style: const TextStyle(
                                    color: Colors.white54, fontSize: 10)),
                            const SizedBox(height: 3),
                            Text(entry.$2.$2,
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 12)),
                          ],
                        ),
                      ),
                    ))
                .toList(),
          );
        },
      );
}

String _durationText(int seconds) {
  final safe = seconds < 0 ? 0 : seconds;
  final hours = safe ~/ 3600;
  final minutes = (safe % 3600) ~/ 60;
  final secs = safe % 60;
  return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
