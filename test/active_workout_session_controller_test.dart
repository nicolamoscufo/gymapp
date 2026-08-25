import 'dart:async';

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

  test(
    'disable skips queued late writes while drain waits for active write',
    () async {
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
    },
  );

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
