import 'package:flutter_test/flutter_test.dart';
import 'package:gymapp/models/exercise.dart';
import 'package:gymapp/models/workout.dart';
import 'package:gymapp/workout_progression_analytics.dart';

WorkoutExercise _exercise(
  String name,
  List<ExerciseSet> sets, {
  MuscleGroup muscleGroup = MuscleGroup.chest,
}) {
  return WorkoutExercise(
    name: name,
    notes: '',
    muscleGroup: muscleGroup,
    technique: IntensityTechnique.none,
    sets: sets,
  );
}

WorkoutSession _session(DateTime date, WorkoutExercise exercise, {String? id}) {
  return WorkoutSession(
    id: id,
    scheduleTitle: 'Test',
    startTime: date.subtract(const Duration(hours: 1)),
    endTime: date,
    exercises: [exercise],
  );
}

void main() {
  group('estimated one rep max', () {
    test('uses Epley for normal strength sets', () {
      expect(estimateOneRepMax(100, 5), closeTo(116.67, 0.01));
      expect(estimateOneRepMax(120, 1), 120);
    });

    test('rejects invalid and very high rep sets', () {
      expect(estimateOneRepMax(0, 5), isNull);
      expect(estimateOneRepMax(100, 0), isNull);
      expect(estimateOneRepMax(50, 15), isNull);
    });
  });

  test('exercise history ignores warmups and incomplete work sets', () {
    final history = [
      _session(
        DateTime(2026, 8, 20),
        _exercise('Panca', [
          ExerciseSet(
            weight: 40,
            reps: 10,
            isCompleted: true,
            type: SetType.warmup,
          ),
          ExerciseSet(weight: 100, reps: 5, isCompleted: true),
          ExerciseSet(weight: 105, reps: 3),
        ]),
      ),
      _session(
        DateTime(2026, 8, 22),
        _exercise('panca', [
          ExerciseSet(weight: 102.5, reps: 5, isCompleted: true),
          ExerciseSet(weight: 95, reps: 8, isCompleted: true),
        ]),
      ),
    ];

    final snapshots = buildExercisePerformanceHistory(
      history: history,
      exerciseName: ' PANCA ',
    );

    expect(snapshots, hasLength(2));
    expect(snapshots.first.bestWeight, 100);
    expect(snapshots.first.topSetWeight, 100);
    expect(snapshots.first.topSetReps, 5);
    expect(snapshots.last.bestWeight, 102.5);
    expect(snapshots.last.topSetWeight, 95);
    expect(snapshots.last.topSetReps, 8);
    expect(snapshots.last.totalVolume, 1272.5);
    expect(snapshots.last.estimatedOneRepMax, closeTo(120.33, 0.01));
  });

  test('historical best can exclude the current session', () {
    final first = _session(
      DateTime(2026, 8, 20),
      _exercise('Squat', [
        ExerciseSet(weight: 120, reps: 5, isCompleted: true),
      ]),
      id: 'old',
    );
    final current = _session(
      DateTime(2026, 8, 25),
      _exercise('Squat', [
        ExerciseSet(weight: 130, reps: 5, isCompleted: true),
      ]),
      id: 'current',
    );

    final best = historicalBestEstimatedOneRepMax(
      history: [first, current],
      exerciseName: 'Squat',
      excludeSessionId: 'current',
    );

    expect(best, closeTo(140, 0.01));
  });

  test('e1RM trend compares the two latest usable snapshots', () {
    final snapshots = [
      ExercisePerformanceSnapshot(
        date: DateTime(2026, 8, 1),
        topSetWeight: 100,
        topSetReps: 5,
        bestWeight: 100,
        bestSetVolume: 500,
        totalVolume: 1500,
        estimatedOneRepMax: 116.6666667,
      ),
      ExercisePerformanceSnapshot(
        date: DateTime(2026, 8, 8),
        topSetWeight: 102.5,
        topSetReps: 5,
        bestWeight: 102.5,
        bestSetVolume: 512.5,
        totalVolume: 1537.5,
        estimatedOneRepMax: 119.5833333,
      ),
    ];

    expect(latestEstimatedOneRepMaxTrendPercent(snapshots), closeTo(2.5, 0.01));
  });

  group('adaptive warmup plan', () {
    test('uses fewer ramps for light work weights', () {
      final plan = buildAdaptiveWarmupPlan(workWeight: 15, workReps: 10);

      expect(plan, hasLength(2));
      expect(plan.first.weight, lessThan(15));
      expect(plan.last.weight, lessThan(15));
      expect(plan.first.reps, greaterThan(plan.last.reps));
    });

    test('uses four tapered ramps for heavier work weights', () {
      final plan = buildAdaptiveWarmupPlan(workWeight: 100, workReps: 5);

      expect(plan, hasLength(4));
      expect(
        plan.map((entry) => entry.weight),
        orderedEquals([40, 60, 75, 87.5]),
      );
      expect(plan.map((entry) => entry.reps), orderedEquals([7, 5, 3, 1]));
      expect(plan.every((entry) => entry.weight < 100), isTrue);
    });
  });
}
