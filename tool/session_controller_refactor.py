from pathlib import Path
import re


def sub_once(text: str, pattern: str, replacement: str, label: str) -> str:
    updated, count = re.subn(pattern, replacement, text, count=1, flags=re.S)
    if count != 1:
        raise RuntimeError(f'{label}: expected one replacement, got {count}')
    return updated


Path('lib/active_workout_session_controller.dart').write_text(r'''import 'app_data_store.dart';
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
''')

Path('test/active_workout_session_controller_test.dart').write_text(r'''import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:gymapp/active_workout_session_controller.dart';
import 'package:gymapp/models/workout.dart';

WorkoutSession session(String id) => WorkoutSession(
  id: id,
  scheduleTitle: 'Test',
  startTime: DateTime(2026, 8, 26),
  endTime: DateTime(2026, 8, 26),
  exercises: const [],
);

void main() {
  test('serializes active-session writes in enqueue order', () async {
    final firstGate = Completer<void>();
    final writes = <String>[];
    var activeWriters = 0;
    var maxConcurrentWriters = 0;

    final controller = ActiveWorkoutSessionController(
      writer: (value) async {
        activeWriters++;
        if (activeWriters > maxConcurrentWriters) {
          maxConcurrentWriters = activeWriters;
        }
        writes.add(value.id);
        if (value.id == 'first') {
          await firstGate.future;
        }
        activeWriters--;
      },
      clearer: () async {},
    );

    final firstSave = controller.save(session('first'));
    final secondSave = controller.save(session('second'));
    await Future<void>.delayed(Duration.zero);

    expect(writes, ['first']);
    expect(maxConcurrentWriters, 1);

    firstGate.complete();
    await Future.wait([firstSave, secondSave]);

    expect(writes, ['first', 'second']);
    expect(maxConcurrentWriters, 1);
  });

  test('disable skips queued late writes while drain waits for active write', () async {
    final activeGate = Completer<void>();
    final writes = <String>[];

    final controller = ActiveWorkoutSessionController(
      writer: (value) async {
        writes.add(value.id);
        if (value.id == 'active') {
          await activeGate.future;
        }
      },
      clearer: () async {},
    );

    controller.save(session('active'));
    controller.save(session('late'));
    await Future<void>.delayed(Duration.zero);
    expect(writes, ['active']);

    controller.disable();
    activeGate.complete();
    await controller.drain();

    expect(writes, ['active']);
    expect(controller.enabled, isFalse);
  });

  test('status state is owned by controller and reports local edits', () async {
    final savedAt = DateTime(2026, 8, 26, 0, 42);
    final gate = Completer<void>();
    var changeCount = 0;
    final controller = ActiveWorkoutSessionController(
      writer: (_) => gate.future,
      clearer: () async {},
      now: () => savedAt,
    );

    expect(
      controller.statusLabel(editCompletedSession: false),
      'Autosave attivo',
    );
    expect(
      controller.statusLabel(editCompletedSession: true),
      'Modifica storico',
    );

    final save = controller.save(
      session('session'),
      showSaving: true,
      onChanged: () => changeCount++,
    );
    expect(controller.saving, isTrue);
    expect(
      controller.statusLabel(editCompletedSession: false),
      'Salvataggio...',
    );

    gate.complete();
    await save;
    expect(controller.saving, isFalse);
    expect(controller.lastSavedAt, savedAt);
    expect(
      controller.statusLabel(editCompletedSession: false),
      'Salvato 00:42',
    );
    expect(changeCount, 2);

    controller.markLocalEdit();
    expect(
      controller.statusLabel(editCompletedSession: true),
      'Modifiche locali',
    );
  });

  test('clear delegates to the configured current-session clearer', () async {
    var clears = 0;
    final controller = ActiveWorkoutSessionController(
      writer: (_) async {},
      clearer: () async => clears++,
    );

    await controller.clear();
    expect(clears, 1);
  });
}
''')

path = Path('lib/screens/active_workout.dart')
text = path.read_text()
text = text.replace(
    "import '../active_workout_insights.dart';\n",
    "import '../active_workout_insights.dart';\nimport '../active_workout_session_controller.dart';\n",
    1,
)
text = text.replace(
    "  DateTime? _lastSavedAt;\n  bool _isSaving = false;\n  bool _allowCurrentSessionSaves = true;\n  Future<void> _pendingCurrentSessionSave = Future.value();\n",
    "  final ActiveWorkoutSessionController _sessionPersistence =\n      ActiveWorkoutSessionController();\n",
    1,
)

text = sub_once(
    text,
    r"  String _saveStatusLabel\(\) \{.*?\n  \}\n\n  ActiveWorkoutInsights get _workoutInsights",
    "  String _saveStatusLabel() => _sessionPersistence.statusLabel(\n    editCompletedSession: widget.editCompletedSession,\n  );\n\n  void _notifySessionPersistenceChanged() {\n    if (mounted) {\n      setState(() {});\n    }\n  }\n\n  ActiveWorkoutInsights get _workoutInsights",
    'replace save status state',
)

replacement = r'''  Future<void> _saveCurrentSession() async {
    if (widget.editCompletedSession) {
      _sessionPersistence.markLocalEdit(
        onChanged: _notifySessionPersistenceChanged,
      );
      return;
    }
    await _queueCurrentSessionSave(showSaving: true);
  }

  Future<void> _saveCurrentSessionSilently() async {
    if (widget.editCompletedSession) {
      _sessionPersistence.markLocalEdit();
      return;
    }
    await _queueCurrentSessionSave();
  }

  Future<void> _queueCurrentSessionSave({bool showSaving = false}) {
    return _sessionPersistence.save(
      session,
      showSaving: showSaving,
      onChanged: _notifySessionPersistenceChanged,
    );
  }

  Future<void> _drainCurrentSessionSaves() => _sessionPersistence.drain();

  Future<void> _clearSavedSession() async {
    if (widget.editCompletedSession) {
      return;
    }
    await _sessionPersistence.clear();
  }
'''
text = sub_once(
    text,
    r"  Future<void> _saveCurrentSession\(\) async \{.*?  Future<void> _clearSavedSession\(\) async \{.*?\n  \}\n",
    replacement,
    'extract autosave methods',
)
text = text.replace(
    "    _allowCurrentSessionSaves = false;\n    await _drainCurrentSessionSaves();",
    "    _sessionPersistence.disable();\n    await _drainCurrentSessionSaves();",
    1,
)

for stale in ['_lastSavedAt', '_isSaving', '_allowCurrentSessionSaves', '_pendingCurrentSessionSave']:
    if stale in text:
        raise RuntimeError(f'stale session persistence state remains: {stale}')

path.write_text(text)
