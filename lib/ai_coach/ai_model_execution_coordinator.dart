import 'dart:async';

/// Serializes access to the single local inference runtime.
///
/// The LiteRT-LM model is configured with one concurrent session. This gate
/// makes that constraint explicit at the app layer, coalesces concurrent
/// initialization, and drains accepted work before disposing the shared model.
class AiModelExecutionCoordinator {
  Future<void>? _initialization;
  Future<void>? _disposeFuture;
  Future<void> _operationTail = Future<void>.value();
  bool _ready = false;
  bool _disposing = false;

  bool get isReady => _ready;
  bool get isDisposing => _disposing;

  Future<void> ensureReady(Future<void> Function() initializer) {
    if (_disposing) {
      return Future<void>.error(
        StateError('Local AI model is disposing; retry after cleanup.'),
      );
    }
    if (_ready) return Future<void>.value();
    final current = _initialization;
    if (current != null) return current;

    final future = _initialize(initializer);
    _initialization = future;
    return future;
  }

  Future<void> _initialize(Future<void> Function() initializer) async {
    try {
      await initializer();
      _ready = true;
    } finally {
      _initialization = null;
    }
  }

  Future<T> runExclusive<T>(Future<T> Function() operation) {
    if (_disposing) {
      return Future<T>.error(
        StateError('Local AI model is disposing; new inference is blocked.'),
      );
    }

    final completer = Completer<T>();
    final previous = _operationTail;
    _operationTail = _runQueued(previous, operation, completer);
    return completer.future;
  }

  Future<void> _runQueued<T>(
    Future<void> previous,
    Future<T> Function() operation,
    Completer<T> completer,
  ) async {
    try {
      await previous;
    } catch (_) {
      // A failed operation must never poison later queued work.
    }

    try {
      completer.complete(await operation());
    } catch (error, stackTrace) {
      completer.completeError(error, stackTrace);
    }
  }

  Future<void> dispose(Future<void> Function() disposer) {
    final current = _disposeFuture;
    if (current != null) return current;

    final future = _dispose(disposer);
    _disposeFuture = future;
    return future;
  }

  Future<void> _dispose(Future<void> Function() disposer) async {
    _disposing = true;
    try {
      final initialization = _initialization;
      if (initialization != null) {
        try {
          await initialization;
        } catch (_) {
          // Cleanup still has to run after a failed initialization.
        }
      }
      await _operationTail;
      await disposer();
      _ready = false;
    } finally {
      _disposing = false;
      _disposeFuture = null;
    }
  }

  /// Marks the shared runtime as requiring initialization again without
  /// discarding the queue. Useful after a recoverable runtime reset.
  void invalidate() {
    _ready = false;
  }
}
