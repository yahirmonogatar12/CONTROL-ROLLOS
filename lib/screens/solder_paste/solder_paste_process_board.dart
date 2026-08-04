import 'package:flutter/material.dart';
import 'package:material_warehousing_flutter/core/models/solder_paste_process.dart';
import 'package:material_warehousing_flutter/core/theme/app_colors.dart';

typedef SolderPasteActionBuilder = Widget Function(
  SolderPasteProcess process,
);

class SolderPasteProcessBoard extends StatelessWidget {
  final List<SolderPasteProcess> processes;
  final bool loading;
  final bool largeDisplay;
  final EdgeInsetsGeometry margin;
  final SolderPasteActionBuilder? actionBuilder;

  const SolderPasteProcessBoard({
    super.key,
    required this.processes,
    this.loading = false,
    this.largeDisplay = false,
    this.margin = EdgeInsets.zero,
    this.actionBuilder,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin,
      decoration: BoxDecoration(
        color: AppColors.gridBackground,
        border: Border.all(color: AppColors.border),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final minimumWidth = largeDisplay ? 1500.0 : 1330.0;
          final gridWidth = constraints.maxWidth < minimumWidth
              ? minimumWidth
              : constraints.maxWidth;
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: gridWidth,
              height: constraints.maxHeight,
              child: Column(
                children: [
                  _buildHeader(),
                  Expanded(child: _buildBody()),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildHeader() {
    final actionWidth = largeDisplay ? 70.0 : 58.0;
    return Container(
      height: largeDisplay ? 44 : 34,
      color: AppColors.gridHeader,
      child: Row(
        children: [
          _headerCell('Material / número de parte', flex: 3),
          _headerCell('Estado', width: largeDisplay ? 230 : 190),
          _headerCell('Tiempo restante', width: largeDisplay ? 430 : 330),
          _headerCell('Línea', width: largeDisplay ? 110 : 90),
          _headerCell('Siguiente paso', flex: 4),
          if (actionBuilder != null)
            _headerCell('Acción', width: actionWidth, centered: true),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (loading && processes.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (processes.isEmpty) {
      return Center(
        child: Text(
          'No hay procesos activos para mostrar',
          style: TextStyle(
            color: Colors.white54,
            fontSize: largeDisplay ? 22 : 14,
          ),
        ),
      );
    }
    return ListView.builder(
      itemCount: processes.length,
      itemBuilder: (_, index) => _buildRow(processes[index], index),
    );
  }

  Widget _headerCell(
    String text, {
    double? width,
    int? flex,
    bool centered = false,
  }) {
    final child = Container(
      width: width,
      padding: EdgeInsets.symmetric(horizontal: largeDisplay ? 12 : 8),
      alignment: centered ? Alignment.center : Alignment.centerLeft,
      decoration: const BoxDecoration(
        border: Border(right: BorderSide(color: AppColors.border, width: .5)),
      ),
      child: Text(
        text,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: Colors.white,
          fontSize: largeDisplay ? 15 : 11,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
    return flex == null ? child : Expanded(flex: flex, child: child);
  }

  Widget _buildRow(SolderPasteProcess process, int index) {
    final color = _statusColor(process.status);
    final progress = _progressFor(process);
    final timer = _timerFor(process);
    final rowHeight = largeDisplay ? 88.0 : 66.0;

    return Container(
      height: rowHeight,
      decoration: BoxDecoration(
        color: index.isEven ? AppColors.gridRowEven : AppColors.gridRowOdd,
        border: const Border(
          bottom: BorderSide(color: Colors.white12, width: .5),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: largeDisplay ? 14 : 8),
              child: Row(
                children: [
                  Icon(
                    Icons.science_outlined,
                    color: color,
                    size: largeDisplay ? 32 : 21,
                  ),
                  SizedBox(width: largeDisplay ? 12 : 8),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          process.code,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: largeDisplay ? 18 : 12,
                          ),
                        ),
                        Text(
                          '${process.partNumber.isEmpty ? 'Sin número de parte' : process.partNumber} · ${process.startedBy}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white54,
                            fontSize: largeDisplay ? 14 : 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          SizedBox(
            width: largeDisplay ? 230 : 190,
            child: Align(
              alignment: Alignment.centerLeft,
              child: _StatusBadge(
                text: process.status.displayName,
                color: color,
                largeDisplay: largeDisplay,
              ),
            ),
          ),
          SizedBox(
            width: largeDisplay ? 430 : 330,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: largeDisplay ? 14 : 8),
              child: progress == null
                  ? Text(
                      '—',
                      style: TextStyle(
                        color: Colors.white54,
                        fontSize: largeDisplay ? 18 : 12,
                      ),
                    )
                  : _TimeConsumptionBar(
                      consumed: progress,
                      timeText: timer,
                      largeDisplay: largeDisplay,
                    ),
            ),
          ),
          SizedBox(
            width: largeDisplay ? 110 : 90,
            child: Text(
              process.lineCode ?? '—',
              style: TextStyle(
                color: Colors.white,
                fontSize: largeDisplay ? 18 : 12,
                fontWeight: largeDisplay ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
          Expanded(
            flex: 4,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: largeDisplay ? 12 : 8),
              child: Text(
                process.nextAction,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: largeDisplay ? 16 : 11,
                ),
              ),
            ),
          ),
          if (actionBuilder != null)
            SizedBox(
              width: largeDisplay ? 70 : 58,
              child: actionBuilder!(process),
            ),
        ],
      ),
    );
  }

  double? _progressFor(SolderPasteProcess process) {
    switch (process.status) {
      case SolderPasteStatus.tempering:
        return process.ambientProgress;
      case SolderPasteStatus.readyForAgitation:
        return process.readyForAgitationProgress;
      case SolderPasteStatus.agitating:
        return process.agitationProgress;
      case SolderPasteStatus.inLine:
        return process.lineProgress;
      default:
        return null;
    }
  }

  String _timerFor(SolderPasteProcess process) {
    switch (process.status) {
      case SolderPasteStatus.tempering:
        return _formatDuration(process.ambientRemainingSeconds);
      case SolderPasteStatus.readyForAgitation:
        return _formatDuration(process.readyForAgitationRemainingSeconds);
      case SolderPasteStatus.agitating:
        return _formatDuration(process.agitationRemainingSeconds);
      case SolderPasteStatus.inLine:
        return _formatDuration(process.lineRemainingSeconds);
      default:
        return '—';
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
}

class _TimeConsumptionBar extends StatelessWidget {
  final double consumed;
  final String timeText;
  final bool largeDisplay;

  const _TimeConsumptionBar({
    required this.consumed,
    required this.timeText,
    required this.largeDisplay,
  });

  @override
  Widget build(BuildContext context) {
    final consumedValue = consumed.clamp(0.0, 1.0);
    final remainingValue = 1 - consumedValue;
    return LayoutBuilder(
      builder: (context, constraints) => ClipRRect(
        borderRadius: BorderRadius.circular(largeDisplay ? 8 : 6),
        child: SizedBox(
          height: largeDisplay ? 34 : 24,
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
              Positioned.fill(
                child: Center(
                  child: Text(
                    timeText,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: largeDisplay ? 18 : 12,
                      fontWeight: FontWeight.bold,
                      fontFeatures: const [FontFeature.tabularFigures()],
                      shadows: const [
                        Shadow(color: Colors.black54, blurRadius: 2),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String text;
  final Color color;
  final bool largeDisplay;

  const _StatusBadge({
    required this.text,
    required this.color,
    required this.largeDisplay,
  });

  @override
  Widget build(BuildContext context) => Container(
        padding: EdgeInsets.symmetric(
          horizontal: largeDisplay ? 12 : 8,
          vertical: largeDisplay ? 7 : 4,
        ),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .13),
          borderRadius: BorderRadius.circular(3),
          border: Border.all(color: color.withValues(alpha: .65)),
        ),
        child: Text(
          text,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.bold,
            fontSize: largeDisplay ? 15 : 11,
          ),
        ),
      );
}
