import 'package:flutter_test/flutter_test.dart';
import 'package:gymapp/models/exercise.dart';
import 'package:gymapp/models/workout.dart';
import 'package:gymapp/progress_analytics.dart';

void main() {
  test(
    'progress analytics builds exercise, muscle, PR and period summaries',
    () {
      final history = [
        _session(DateTime(2026, 8, 11, 18), [
          _exercise('Panca', MuscleGroup.chest, [
            _set(80, 8),
            _set(80, 8),
            _set(80, 7),
          ]),
        ]),
        _session(DateTime(2026, 8, 18, 18), [
          _exercise('Panca', MuscleGroup.chest, [
            _set(82.5, 8),
            _set(82.5, 8),
            _set(82.5, 8),
          ]),
          _exercise('Rematore', MuscleGroup.back, [_set(70, 10), _set(70, 10)]),
        ]),
        _session(DateTime(2026, 8, 25, 18), [
          _exercise('Panca', MuscleGroup.chest, [
            _set(85, 8),
            _set(85, 7),
            _set(85, 7),
          ]),
        ]),
      ];

      final analytics = buildProgressAnalytics(
        history: history,
        now: DateTime(2026, 8, 25, 20),
      );

      final bench = analytics.exercises.firstWhere(
        (entry) => entry.name == 'Panca',
      );
      expect(bench.sessionCount, 3);
      expect(bench.completedSets, 9);
      expect(bench.bestWeight, 85);
      expect(bench.bestEstimatedOneRepMax, greaterThan(100));
      expect(bench.estimatedOneRepMaxTrendPercent, isNotNull);
      expect(bench.estimatedOneRepMaxTrendPercent!, greaterThan(0));

      final chest = analytics.muscles.firstWhere(
        (entry) => entry.muscleGroup == MuscleGroup.chest,
      );
      expect(chest.sets30Days, 9);
      expect(chest.sets7Days, 3);
      expect(chest.weekly, hasLength(8));

      expect(analytics.personalRecords, isNotEmpty);
      expect(analytics.currentMonth.workouts, 3);
      expect(analytics.currentMonth.topExercise, 'Panca');
      expect(analytics.currentMonth.topMuscleGroup, MuscleGroup.chest);
      expect(analytics.currentYear.workouts, 3);
      expect(analytics.consistency.currentActiveWeekStreak, 3);
    },
  );

  test('progress analytics ignores warmups and incomplete sets', () {
    final session = _session(DateTime(2026, 8, 25, 18), [
      WorkoutExercise(
        name: 'Squat',
        notes: '',
        muscleGroup: MuscleGroup.quadriceps,
        technique: IntensityTechnique.none,
        sets: [
          ExerciseSet(
            weight: 60,
            reps: 10,
            type: SetType.warmup,
            isCompleted: true,
          ),
          ExerciseSet(weight: 100, reps: 5, isCompleted: true),
          ExerciseSet(weight: 140, reps: 5, isCompleted: false),
        ],
      ),
    ]);

    final analytics = buildProgressAnalytics(
      history: [session],
      now: DateTime(2026, 8, 25, 20),
    );

    expect(analytics.exercises.single.completedSets, 1);
    expect(analytics.exercises.single.bestWeight, 100);
    expect(analytics.muscles.single.sets30Days, 1);
  });
}

WorkoutSession _session(DateTime start, List<WorkoutExercise> exercises) {
  return WorkoutSession(
    scheduleTitle: 'Workout',
    startTime: start,
    endTime: start.add(const Duration(minutes: 60)),
    exercises: exercises,
  );
}

WorkoutExercise _exercise(
  String name,
  MuscleGroup group,
  List<ExerciseSet> sets,
) {
  return WorkoutExercise(
    name: name,
    notes: '',
    muscleGroup: group,
    technique: IntensityTechnique.none,
    sets: sets,
  );
}

ExerciseSet _set(double weight, int reps) {
  return ExerciseSet(weight: weight, reps: reps, isCompleted: true);
}
