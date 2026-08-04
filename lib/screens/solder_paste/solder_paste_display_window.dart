import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_warehousing_flutter/core/models/solder_paste_process.dart';
import 'package:material_warehousing_flutter/core/services/api_service.dart';
import 'package:material_warehousing_flutter/core/theme/app_colors.dart';
import 'package:material_warehousing_flutter/screens/solder_paste/solder_paste_process_board.dart';
import 'package:window_manager/window_manager.dart';

class SolderPasteDisplayApp extends StatelessWidget {
  const SolderPasteDisplayApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Monitor de pasta de soldadura',
      theme: ThemeData(
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.headerTab,
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: AppColors.gridBackground,
      ),
      home: const SolderPasteDisplayWindow(),
    );
  }
}

class SolderPasteDisplayWindow extends StatefulWidget {
  const SolderPasteDisplayWindow({super.key});

  @override
  State<SolderPasteDisplayWindow> createState() =>
      _SolderPasteDisplayWindowState();
}

class _SolderPasteDisplayWindowState extends State<SolderPasteDisplayWindow>
    with WindowListener {
  List<SolderPasteProcess> _processes = [];
  Timer? _clockTimer;
  Timer? _pollTimer;
  bool _loading = false;
  bool _fullScreen = false;
  String? _error;
  DateTime? _lastUpdated;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {});
      if (_hasDueTransition) unawaited(_loadProcesses());
    });
    _pollTimer = Timer.periodic(
      const Duration(seconds: 15),
      (_) => _loadProcesses(),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadProcesses());
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    _clockTimer?.cancel();
    _pollTimer?.cancel();
    super.dispose();
  }

  @override
  void onWindowClose() {
    unawaited(_hideWindow());
  }

  Future<void> _hideWindow() async {
    await windowManager.hide();
  }

  Future<void> _loadProcesses() async {
    if (_loading) return;
    setState(() => _loading = true);
    final result = await ApiService.getSolderPasteProcesses(limit: 500);
    if (!mounted) return;
    if (result['success'] == true) {
      final rows = (result['processes'] as List? ?? const [])
          .whereType<Map>()
          .map((row) => SolderPasteProcess.fromJson(
                Map<String, dynamic>.from(row),
              ))
          .where((process) => process.isActive)
          .toList();
      setState(() {
        _processes = rows;
        _loading = false;
        _error = null;
        _lastUpdated = DateTime.now();
      });
      return;
    }
    setState(() {
      _loading = false;
      _error = result['message']?.toString() ??
          'No fue posible actualizar los procesos';
    });
  }

  bool get _hasDueTransition => _processes.any((process) {
        switch (process.status) {
          case SolderPasteStatus.tempering:
            return process.ambientRemainingSeconds <= 0;
          case SolderPasteStatus.agitating:
            return process.agitationRemainingSeconds <= 0;
          case SolderPasteStatus.inLine:
            return process.lineRemainingSeconds <= 0;
          default:
            return false;
        }
      });

  Future<void> _toggleFullScreen() async {
    final nextValue = !await windowManager.isFullScreen();
    await windowManager.setFullScreen(nextValue);
    if (mounted) setState(() => _fullScreen = nextValue);
  }

  String _formatClock(DateTime value) {
    String d(int number) => number.toString().padLeft(2, '0');
    return '${d(value.day)}/${d(value.month)}/${value.year}  '
        '${d(value.hour)}:${d(value.minute)}:${d(value.second)}';
  }

  String _formatUpdateTime(DateTime? value) {
    if (value == null) return 'Sin actualizar';
    String d(int number) => number.toString().padLeft(2, '0');
    return 'Última actualización: ${d(value.hour)}:${d(value.minute)}:${d(value.second)}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ColoredBox(
        color: AppColors.gridBackground,
        child: Column(
          children: [
            _buildTopBar(),
            if (_error != null)
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                color: Colors.red.shade800,
                child: Text(
                  _error!,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            Expanded(
              child: SolderPasteProcessBoard(
                processes: _processes,
                loading: _loading,
                largeDisplay: true,
                margin: const EdgeInsets.all(12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    final now = DateTime.now();
    return Container(
      height: 82,
      padding: const EdgeInsets.symmetric(horizontal: 18),
      decoration: const BoxDecoration(
        color: AppColors.panelBackground,
        border: Border(
          bottom: BorderSide(color: AppColors.border, width: 1),
        ),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.science_outlined,
            color: AppColors.headerTab,
            size: 42,
          ),
          const SizedBox(width: 14),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'MONITOR DE PASTA DE SOLDADURA',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 23,
                  fontWeight: FontWeight.bold,
                  letterSpacing: .8,
                ),
              ),
              Text(
                _formatUpdateTime(_lastUpdated),
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ],
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.headerTab.withValues(alpha: .15),
              border: Border.all(color: AppColors.headerTab),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              '${_processes.length} ACTIVOS',
              style: const TextStyle(
                color: AppColors.headerTab,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 20),
          Text(
            _formatClock(now),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(width: 16),
          IconButton(
            tooltip: 'Actualizar',
            onPressed: _loading ? null : _loadProcesses,
            icon: _loading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: _fullScreen
                ? 'Salir de pantalla completa'
                : 'Pantalla completa',
            onPressed: _toggleFullScreen,
            icon: Icon(_fullScreen ? Icons.fullscreen_exit : Icons.fullscreen),
          ),
          IconButton(
            tooltip: 'Ocultar monitor',
            onPressed: _hideWindow,
            icon: const Icon(Icons.visibility_off_outlined),
          ),
        ],
      ),
    );
  }
}
