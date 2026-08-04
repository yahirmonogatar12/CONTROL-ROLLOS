import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_warehousing_flutter/app.dart';

class SolderPasteNotificationOverlay {
  static final SolderPasteNotificationOverlay _instance =
      SolderPasteNotificationOverlay._();
  static SolderPasteNotificationOverlay get instance => _instance;
  SolderPasteNotificationOverlay._();

  int _activeCount = 0;

  void show({required String code, required String partNumber}) {
    final overlay = appNavigatorKey.currentState?.overlay;
    if (overlay == null) return;
    SystemSound.play(SystemSoundType.alert);

    final top = 40.0 + (_activeCount * 126.0);
    _activeCount++;
    late OverlayEntry entry;
    var removed = false;
    void remove() {
      if (removed) return;
      removed = true;
      try {
        entry.remove();
      } catch (_) {}
      _activeCount = (_activeCount - 1).clamp(0, 99);
    }

    entry = OverlayEntry(
      builder: (_) => Positioned(
        top: top,
        right: 12,
        width: 390,
        child: Material(
          color: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF172033),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.greenAccent, width: 2),
              boxShadow: const [
                BoxShadow(color: Colors.black54, blurRadius: 18),
              ],
            ),
            child: Row(
              children: [
                const CircleAvatar(
                  backgroundColor: Color(0x2233FF99),
                  child:
                      Icon(Icons.science_outlined, color: Colors.greenAccent),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Material listo para agitación',
                        style: TextStyle(
                          color: Colors.greenAccent,
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        partNumber.isEmpty ? code : '$partNumber · $code',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: remove,
                  icon: const Icon(Icons.close, color: Colors.white54),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    overlay.insert(entry);
    Timer(const Duration(seconds: 8), remove);
  }
}
