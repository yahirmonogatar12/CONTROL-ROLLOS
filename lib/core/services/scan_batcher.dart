import 'dart:async';

typedef ScanBatchLoader<T> = Future<Map<String, T>> Function(List<String> codes);

class ScanBatcher<T> {
  ScanBatcher({
    required this.loader,
    this.window = const Duration(milliseconds: 200),
    this.maxBatchSize = 20,
  });

  final ScanBatchLoader<T> loader;
  final Duration window;
  final int maxBatchSize;

  final Map<String, List<Completer<T?>>> _pending = <String, List<Completer<T?>>>{};
  Timer? _timer;
  bool _isFlushing = false;

  Future<T?> enqueue(String code) {
    final normalizedCode = code.trim();
    if (normalizedCode.isEmpty) {
      return Future<T?>.value(null);
    }

    final completer = Completer<T?>();
    _pending.putIfAbsent(normalizedCode, () => <Completer<T?>>[]).add(completer);

    if (_pending.length >= maxBatchSize) {
      unawaited(flush());
    } else {
      _timer ??= Timer(window, () {
        _timer = null;
        unawaited(flush());
      });
    }

    return completer.future;
  }

  Future<void> flush() async {
    if (_isFlushing || _pending.isEmpty) {
      return;
    }

    _isFlushing = true;
    _timer?.cancel();
    _timer = null;

    final batch = Map<String, List<Completer<T?>>>.from(_pending);
    _pending.clear();

    try {
      final results = await loader(batch.keys.toList());
      for (final entry in batch.entries) {
        final value = results[entry.key];
        for (final completer in entry.value) {
          if (!completer.isCompleted) {
            completer.complete(value);
          }
        }
      }
    } catch (error, stackTrace) {
      for (final completers in batch.values) {
        for (final completer in completers) {
          if (!completer.isCompleted) {
            completer.completeError(error, stackTrace);
          }
        }
      }
    } finally {
      _isFlushing = false;
      if (_pending.isNotEmpty) {
        unawaited(flush());
      }
    }
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;

    for (final completers in _pending.values) {
      for (final completer in completers) {
        if (!completer.isCompleted) {
          completer.complete(null);
        }
      }
    }

    _pending.clear();
  }
}
