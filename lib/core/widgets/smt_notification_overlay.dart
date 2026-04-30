import 'package:flutter/material.dart';
import 'package:material_warehousing_flutter/app.dart';

/// Servicio singleton para mostrar notificaciones overlay en la esquina
/// superior derecha cuando llega una nueva solicitud de material SMT.
/// Reemplaza FCM (que no funciona en Windows) usando polling.
class SMTNotificationOverlay {
  static final SMTNotificationOverlay _instance = SMTNotificationOverlay._();
  static SMTNotificationOverlay get instance => _instance;
  SMTNotificationOverlay._();

  int _activeCount = 0;

  static const double _cardHeight = 115.0;
  static const double _cardWidth = 380.0;
  static const double _spacing = 8.0;
  static const double _topOffset = 40.0;
  static const double _rightOffset = 12.0;

  void show({
    required String lineId,
    required String numeroParte,
    String? ubicacion,
  }) {
    final overlay = appNavigatorKey.currentState?.overlay;
    if (overlay == null) return;

    final positionTop = _topOffset + _activeCount * (_cardHeight + _spacing);
    _activeCount++;

    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => Positioned(
        top: positionTop,
        right: _rightOffset,
        width: _cardWidth,
        child: Material(
          color: Colors.transparent,
          child: _SMTNotifCard(
            lineId: lineId,
            numeroParte: numeroParte,
            ubicacion: ubicacion,
            onDismiss: () => _safeRemove(entry),
          ),
        ),
      ),
    );

    overlay.insert(entry);
  }

  void _safeRemove(OverlayEntry entry) {
    try {
      entry.remove();
    } catch (_) {}
    _activeCount = (_activeCount - 1).clamp(0, 99);
  }
}

class _SMTNotifCard extends StatefulWidget {
  final String lineId;
  final String numeroParte;
  final String? ubicacion;
  final VoidCallback onDismiss;

  const _SMTNotifCard({
    required this.lineId,
    required this.numeroParte,
    required this.ubicacion,
    required this.onDismiss,
  });

  @override
  State<_SMTNotifCard> createState() => _SMTNotifCardState();
}

class _SMTNotifCardState extends State<_SMTNotifCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _fadeAnimation;

  static const Map<String, String> _lineLabels = {
    'SA': 'SMT A',
    'SB': 'SMT B',
    'SC': 'SMT C',
    'SD': 'SMT D',
    'SE': 'SMT E',
  };

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 320),
      vsync: this,
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(1.3, 0),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
    _fadeAnimation =
        CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lineLabel = _lineLabels[widget.lineId] ?? widget.lineId;

    return SlideTransition(
      position: _slideAnimation,
      child: FadeTransition(
        opacity: _fadeAnimation,
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF1A1F2E),
            borderRadius: BorderRadius.circular(10),
            border:
                Border.all(color: Colors.amber.withOpacity(0.65), width: 2),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.55),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header
                Row(
                  children: [
                    const Icon(Icons.notifications_active,
                        color: Colors.amber, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      'Nueva solicitud · $lineLabel',
                      style: const TextStyle(
                        color: Colors.amber,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    const Spacer(),
                    GestureDetector(
                      onTap: widget.onDismiss,
                      child: const Icon(Icons.close,
                          size: 16, color: Colors.white38),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // Part number
                Row(
                  children: [
                    const Icon(Icons.qr_code, size: 16, color: Colors.white54),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        widget.numeroParte,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          fontFamily: 'monospace',
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                // Location
                if (widget.ubicacion != null &&
                    widget.ubicacion!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.location_on_outlined,
                          size: 16, color: Colors.white38),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          widget.ubicacion!,
                          style: const TextStyle(
                              color: Colors.white60, fontSize: 12),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
