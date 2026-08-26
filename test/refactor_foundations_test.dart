import 'package:flutter_test/flutter_test.dart';
import 'package:gymapp/active_workout_insights.dart';
import 'package:gymapp/home_data_policy.dart';
import 'package:gymapp/models/exercise.dart';
import 'package:gymapp/models/schedule.dart';
import 'package:gymapp/models/workout.dart';

WorkoutExercise workoutExercise({
  required String id,
  required String name,
  required double weight,
  required int reps,
  SetType type = SetType.normal,
}) {
  return WorkoutExercise(
    id: id,
    name: name,
    notes: '',
    technique: IntensityTechnique.none,
    sets: [
      ExerciseSet(
        id: '${id}_set',
        weight: weight,
        reps: reps,
        isCompleted: true,
        type: type,
      ),
    ],
  );
}

WorkoutSession workoutSession({
  required String id,
  required WorkoutExercise exercise,
}) {
  return WorkoutSession(
    id: id,
    scheduleTitle: 'Test',
    startTime: DateTime(2026, 8, 1, 10),
    endTime: DateTime(2026, 8, 1, 11),
    exercises: [exercise],
  );
}

Exercise planExercise(String id, double reduction) {
  return Exercise(
    id: id,
    name: 'Panca piana',
    reps: 8,
    set: 3,
    notes: '',
    weight: 80,
    technique: IntensityTechnique.topsetBackoff,
    backoffReductionPercent: reduction,
  );
}

void main() {
  test('active workout insights preserve PR detection outside the widget', () {
    final historical = workoutExercise(
      id: 'historical_bench',
      name: 'Panca piana',
      weight: 80,
      reps: 5,
    );
    final current = workoutExercise(
      id: 'current_bench',
      name: 'Panca piana',
      weight: 82.5,
      reps: 5,
    );
    final insights = ActiveWorkoutInsights(
      history: [workoutSession(id: 'old_session', exercise: historical)],
      currentSessionId: 'current_session',
    );

    final labels = insights.personalRecordLabelsFor(
      current,
      current.sets.single,
      0,
    );

    expect(labels, contains('PR kg'));
    expect(labels, contains('PR set'));
    expect(labels, contains('PR e1RM'));
    expect(labels, contains('PR volume'));

    final currentSession = workoutSession(
      id: 'current_session',
      exercise: current,
    );
    expect(insights.sessionPrCount(currentSession), 1);
  });

  test('active workout insights exposes structured PR celebration event', () {
    final historical = workoutExercise(
      id: 'historical_press',
      name: 'Panca piana',
      weight: 80,
      reps: 5,
    );
    final current = workoutExercise(
      id: 'current_press',
      name: 'Panca piana',
      weight: 82.5,
      reps: 5,
    );
    final insights = ActiveWorkoutInsights(
      history: [workoutSession(id: 'old_session', exercise: historical)],
      currentSessionId: 'current_session',
    );

    final event = insights.personalRecordEventFor(
      current,
      current.sets.single,
      0,
    );

    expect(event, isNotNull);
    expect(event!.exerciseName, 'Panca piana');
    expect(event.kinds, [
      ActiveWorkoutPrKind.weight,
      ActiveWorkoutPrKind.setVolume,
      ActiveWorkoutPrKind.estimatedOneRepMax,
      ActiveWorkoutPrKind.exerciseVolume,
    ]);
    expect(event.headline, '4 nuovi record personali!');
    expect(event.summary, 'Carico · Volume set · e1RM · Volume esercizio');
    expect(event.legacyLabels, ['PR kg', 'PR set', 'PR e1RM', 'PR volume']);
  });

  test('active workout insights ignore warm-up sets for PRs', () {
    final historical = workoutExercise(
      id: 'historical_bench',
      name: 'Panca piana',
      weight: 80,
      reps: 5,
    );
    final warmup = workoutExercise(
      id: 'warmup_bench',
      name: 'Panca piana',
      weight: 100,
      reps: 20,
      type: SetType.warmup,
    );
    final insights = ActiveWorkoutInsights(
      history: [workoutSession(id: 'old_session', exercise: historical)],
      currentSessionId: 'current_session',
    );

    expect(
      insights.personalRecordLabelsFor(warmup, warmup.sets.single, 0),
      isEmpty,
    );
  });

  test('home data policy applies backoff defaults across persisted graphs', () {
    final scheduleExercise = planExercise('plan_exercise', 10);
    final schedule = Schedule(
      id: 'schedule',
      title: 'Push',
      week: 1,
      createdAt: DateTime(2026, 8, 24),
      exercises: [scheduleExercise],
    );
    final historicalExercise = workoutExercise(
      id: 'history_exercise',
      name: 'Panca piana',
      weight: 80,
      reps: 5,
    )..backoffReductionPercent = 10;
    final history = [
      workoutSession(id: 'history_session', exercise: historicalExercise),
    ];
    final currentExercise = workoutExercise(
      id: 'current_exercise',
      name: 'Panca piana',
      weight: 80,
      reps: 5,
    )..backoffReductionPercent = 10;
    final currentSession = workoutSession(
      id: 'current_session',
      exercise: currentExercise,
    );

    expect(
      HomeDataPolicy.applyBackoffReductionToSchedules([schedule], 25),
      isTrue,
    );
    expect(HomeDataPolicy.applyBackoffReductionToHistory(history, 25), isTrue);
    expect(
      HomeDataPolicy.applyBackoffReductionToSession(currentSession, 25),
      isTrue,
    );
    expect(scheduleExercise.backoffReductionPercent, 25);
    expect(historicalExercise.backoffReductionPercent, 25);
    expect(currentExercise.backoffReductionPercent, 25);
  });

  test(
    'home data policy keeps active schedules ordered before archived ones',
    () {
      final createdAt = DateTime(2026, 8, 24);
      Schedule schedule(String id, String title, {bool archived = false}) {
        return Schedule(
          id: id,
          title: title,
          week: 1,
          createdAt: createdAt,
          exercises: const [],
          isArchived: archived,
        );
      }

      final schedules = [
        schedule('archived', 'Archived', archived: true),
        schedule('b', 'Beta'),
        schedule('a', 'Alpha'),
      ];

      HomeDataPolicy.sortSchedules(schedules);

      expect(schedules.map((item) => item.id), ['a', 'b', 'archived']);
    },
  );
}
