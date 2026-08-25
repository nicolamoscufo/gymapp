import 'package:flutter_test/flutter_test.dart';
import 'package:gymapp/active_workout_rest_controller.dart';
import 'package:gymapp/models/exercise.dart';
import 'package:gymapp/models/workout.dart';

WorkoutExercise _exercise({
  String name = 'Panca',
  int? restSeconds = 90,
  int? activeRestSeconds,
  DateTime? activeRestStartedAt,
}) {
  return WorkoutExercise(
    name: name,
    notes: '',
    technique: IntensityTechnique.none,
    restSeconds: restSeconds,
    activeRestSeconds: activeRestSeconds,
    activeRestStartedAt: activeRestStartedAt,
    sets: [ExerciseSet(weight: 80, reps: 8)],
  );
}

void main() {
  test('rest controller starts and adjusts a persisted countdown', () async {
    final now = DateTime(2026, 8, 26, 0, 0);
    final exercise = _exercise(restSeconds: 90);
    final scheduledSeconds = <int>[];
    final cancelledIds = <int>[];
    var changes = 0;

    final controller = ActiveWorkoutRestController(
      exercises: () => [exercise],
      restSecondsFor: (exercise) => exercise.restSeconds ?? 0,
      now: () => now,
      onChanged: () => changes += 1,
      scheduleNotification:
          ({
            required int id,
            required DateTime endTime,
            required String exerciseName,
          }) async {
            scheduledSeconds.add(endTime.difference(now).inSeconds);
          },
      cancelNotification: (id) async => cancelledIds.add(id),
    );
    addTearDown(controller.dispose);

    expect(controller.start(exercise), isTrue);
    expect(controller.remainingFor(exercise.id), 90);
    expect(exercise.activeRestSeconds, 90);
    expect(exercise.activeRestStartedAt, now);

    expect(controller.addThirtySeconds(exercise), isTrue);
    expect(controller.remainingFor(exercise.id), 120);
    expect(exercise.activeRestSeconds, 120);

    expect(controller.subtractThirtySeconds(exercise), isTrue);
    expect(controller.remainingFor(exercise.id), 90);
    expect(exercise.activeRestSeconds, 90);

    await Future<void>.delayed(Duration.zero);
    expect(scheduledSeconds, [90, 120, 90]);
    expect(cancelledIds, isNotEmpty);
    expect(changes, greaterThanOrEqualTo(3));
  });

  test(
    'rest controller stop clears runtime and persisted rest state',
    () async {
      final exercise = _exercise(restSeconds: 60);
      final cancelled = <int>[];
      final controller = ActiveWorkoutRestController(
        exercises: () => [exercise],
        restSecondsFor: (exercise) => exercise.restSeconds ?? 0,
        scheduleNotification:
            ({
              required int id,
              required DateTime endTime,
              required String exerciseName,
            }) async {},
        cancelNotification: (id) async => cancelled.add(id),
      );
      addTearDown(controller.dispose);

      controller.start(exercise);
      expect(controller.isActive(exercise.id), isTrue);

      expect(controller.stop(exercise), isTrue);
      await Future<void>.delayed(Duration.zero);

      expect(controller.isActive(exercise.id), isFalse);
      expect(exercise.activeRestSeconds, isNull);
      expect(exercise.activeRestStartedAt, isNull);
      expect(cancelled, hasLength(1));
    },
  );

  test('rest controller restores remaining time from persisted metadata', () {
    final now = DateTime(2026, 8, 26, 0, 2);
    final exercise = _exercise(
      activeRestSeconds: 120,
      activeRestStartedAt: now.subtract(const Duration(seconds: 45)),
    );
    final controller = ActiveWorkoutRestController(
      exercises: () => [exercise],
      restSecondsFor: (exercise) => exercise.restSeconds ?? 0,
      now: () => now,
      scheduleNotification:
          ({
            required int id,
            required DateTime endTime,
            required String exerciseName,
          }) async {},
      cancelNotification: (id) async {},
    );
    addTearDown(controller.dispose);

    controller.restore();

    expect(controller.remainingFor(exercise.id), 75);
    expect(controller.activeExercise(), same(exercise));
  });

  test('expired restored rest emits finish and clears metadata', () async {
    final now = DateTime(2026, 8, 26, 0, 4);
    final exercise = _exercise(
      activeRestSeconds: 60,
      activeRestStartedAt: now.subtract(const Duration(seconds: 75)),
    );
    final finished = <String>[];
    final controller = ActiveWorkoutRestController(
      exercises: () => [exercise],
      restSecondsFor: (exercise) => exercise.restSeconds ?? 0,
      now: () => now,
      onFinished: (exerciseId, exerciseName) => finished.add(exerciseId),
      scheduleNotification:
          ({
            required int id,
            required DateTime endTime,
            required String exerciseName,
          }) async {},
      cancelNotification: (id) async {},
    );
    addTearDown(controller.dispose);

    controller.restore(notifyExpired: true);
    await Future<void>.delayed(Duration.zero);

    expect(finished, [exercise.id]);
    expect(controller.hasActiveRest, isFalse);
    expect(exercise.activeRestSeconds, isNull);
    expect(exercise.activeRestStartedAt, isNull);
  });

  test('timer expiry is owned by controller instead of the widget', () async {
    final exercise = _exercise(restSeconds: 1);
    final finished = <String>[];
    final controller = ActiveWorkoutRestController(
      exercises: () => [exercise],
      restSecondsFor: (exercise) => exercise.restSeconds ?? 0,
      tickInterval: const Duration(milliseconds: 5),
      onFinished: (exerciseId, exerciseName) => finished.add(exerciseId),
      scheduleNotification:
          ({
            required int id,
            required DateTime endTime,
            required String exerciseName,
          }) async {},
      cancelNotification: (id) async {},
    );
    addTearDown(controller.dispose);

    controller.start(exercise);
    await Future<void>.delayed(const Duration(milliseconds: 30));

    expect(finished, [exercise.id]);
    expect(controller.hasActiveRest, isFalse);
    expect(exercise.activeRestSeconds, isNull);
  });

  test('cancelAll clears every active or persisted rest', () async {
    final first = _exercise(name: 'Panca', restSeconds: 30);
    final second = _exercise(
      name: 'Squat',
      restSeconds: 60,
      activeRestSeconds: 60,
      activeRestStartedAt: DateTime(2026, 8, 26),
    );
    final cancelled = <int>[];
    final controller = ActiveWorkoutRestController(
      exercises: () => [first, second],
      restSecondsFor: (exercise) => exercise.restSeconds ?? 0,
      scheduleNotification:
          ({
            required int id,
            required DateTime endTime,
            required String exerciseName,
          }) async {},
      cancelNotification: (id) async => cancelled.add(id),
    );
    addTearDown(controller.dispose);

    controller.start(first);
    await controller.cancelAll();

    expect(controller.hasActiveRest, isFalse);
    expect(first.activeRestSeconds, isNull);
    expect(second.activeRestSeconds, isNull);
    expect(cancelled, hasLength(2));
  });
}
