import 'app_data_store.dart';
import 'models/workout.dart';

typedef CurrentSessionWriter = Future<void> Function(WorkoutSession session);
typedef CurrentSessionClearer = Future<void> Function();
typedef SessionPersistenceChanged = void Function();

/// Serializes active-workout persistence and owns autosave lifecycle state.
///
/// The controller deliberately stays independent from Flutter widgets. This
/// keeps save ordering, finish-time write suppression and status semantics
/// directly testable without coupling them to ActiveWorkoutScreen.
class ActiveWorkoutSessionController {
  ActiveWorkoutSessionController({
    CurrentSessionWriter? writer,
    CurrentSessionClearer? clearer,
    DateTime Function()? now,
  }) : _writer = writer ?? AppDataStore.saveCurrentSession,
       _clearer = clearer ?? AppDataStore.clearCurrentSession,
       _now = now ?? DateTime.now;

  final CurrentSessionWriter _writer;
  final CurrentSessionClearer _clearer;
  final DateTime Function() _now;

  Future<void> _pendingSave = Future.value();
  bool _enabled = true;
  bool _saving = false;
  DateTime? _lastSavedAt;

  bool get enabled => _enabled;
  bool get saving => _saving;
  DateTime? get lastSavedAt => _lastSavedAt;

  String statusLabel({required bool editCompletedSession}) {
    if (editCompletedSession) {
      return _lastSavedAt == null ? 'Modifica storico' : 'Modifiche locali';
    }
    if (_saving) {
      return 'Salvataggio...';
    }
    final savedAt = _lastSavedAt;
    if (savedAt == null) {
      return 'Autosave attivo';
    }
    return 'Salvato ${savedAt.hour.toString().padLeft(2, '0')}:${savedAt.minute.toString().padLeft(2, '0')}';
  }

  void markLocalEdit({SessionPersistenceChanged? onChanged}) {
    _lastSavedAt = _now();
    onChanged?.call();
  }

  Future<void> save(
    WorkoutSession session, {
    bool showSaving = false,
    SessionPersistenceChanged? onChanged,
  }) {
    if (!_enabled) {
      return Future.value();
    }

    if (showSaving) {
      _saving = true;
      onChanged?.call();
    }

    final nextSave = _pendingSave.catchError((_) {}).then((_) async {
      // Finish/discard can disable persistence while this write is queued.
      if (!_enabled) {
        return;
      }
      await _writer(session);
      _lastSavedAt = _now();
      if (showSaving) {
        _saving = false;
      }
      onChanged?.call();
    });
    _pendingSave = nextSave;
    return nextSave;
  }

  /// Prevents new and not-yet-started queued writes.
  /// Already-running writes are still awaited by [drain].
  void disable() {
    _enabled = false;
  }

  Future<void> drain() async {
    await _pendingSave.catchError((_) {});
  }

  Future<void> clear() => _clearer();
}
