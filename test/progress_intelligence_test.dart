import 'package:flutter_test/flutter_test.dart';
import 'package:gymapp/models/exercise.dart';
import 'package:gymapp/models/workout.dart';
import 'package:gymapp/progress_analytics.dart';
import 'package:gymapp/progress_intelligence.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('classifies smoothed exercise momentum and stale exercises', () {
    final history = <WorkoutSession>[];
    final dates = [
      DateTime(2026, 7, 1),
      DateTime(2026, 7, 8),
      DateTime(2026, 7, 15),
      DateTime(2026, 8, 5),
      DateTime(2026, 8, 12),
      DateTime(2026, 8, 20),
    ];
    final benchWeights = [70.0, 72.0, 74.0, 80.0, 82.0, 84.0];
    final squatWeights = [120.0, 118.0, 116.0, 110.0, 108.0, 106.0];

    for (var index = 0; index < dates.length; index++) {
      history.add(
        _session(dates[index], [
          _exercise('Panca', MuscleGroup.chest, benchWeights[index], 8),
          _exercise('Squat', MuscleGroup.quadriceps, squatWeights[index], 8),
        ]),
      );
    }
    history.add(
      _session(DateTime(2026, 5, 1), [
        _exercise('Rematore', MuscleGroup.back, 60, 10),
      ]),
    );
    history.add(
      _session(DateTime(2026, 5, 8), [
        _exercise('Rematore', MuscleGroup.back, 62, 10),
      ]),
    );

    final analytics = buildProgressAnalytics(
      history: history,
      now: DateTime(2026, 8, 26),
    );
    final intelligence = buildProgressCenterIntelligence(
      history: history,
      analytics: analytics,
      now: DateTime(2026, 8, 26),
    );

    final bench = intelligence.exercises.firstWhere(
      (entry) => entry.name == 'Panca',
    );
    final squat = intelligence.exercises.firstWhere(
      (entry) => entry.name == 'Squat',
    );
    final row = intelligence.exercises.firstWhere(
      (entry) => entry.name == 'Rematore',
    );

    expect(bench.momentum, ProgressMomentum.growing);
    expect(bench.estimatedOneRepMaxWindowChangePercent, greaterThan(10));
    expect(squat.momentum, ProgressMomentum.declining);
    expect(squat.estimatedOneRepMaxWindowChangePercent, lessThan(-5));
    expect(row.momentum, ProgressMomentum.insufficient);
    expect(row.isStale, isTrue);
    expect(row.daysSinceLastTrained, greaterThan(90));
    expect(intelligence.growingCount, 1);
    expect(intelligence.decliningCount, 1);
    expect(intelligence.staleCount, 1);
    expect(intelligence.attentionExercises.first.name, 'Squat');
  });

  test(
    'compares muscle exposure and PR counts across rolling 30-day windows',
    () {
      final history = [
        _session(DateTime(2026, 7, 2), [
          _exercise('Panca', MuscleGroup.chest, 70, 8),
        ]),
        _session(DateTime(2026, 7, 16), [
          _exercise('Panca', MuscleGroup.chest, 72, 8),
        ]),
        _session(DateTime(2026, 8, 5), [
          _exercise('Panca', MuscleGroup.chest, 75, 8),
        ]),
        _session(DateTime(2026, 8, 20), [
          _exercise('Panca', MuscleGroup.chest, 77, 8),
          _exercise('Lat machine', MuscleGroup.back, 60, 10),
        ]),
      ];

      final analytics = buildProgressAnalytics(
        history: history,
        now: DateTime(2026, 8, 26),
      );
      final intelligence = buildProgressCenterIntelligence(
        history: history,
        analytics: analytics,
        now: DateTime(2026, 8, 26),
      );

      final chest = intelligence.muscleShifts.firstWhere(
        (entry) => entry.muscleGroup == MuscleGroup.chest,
      );
      final back = intelligence.muscleShifts.firstWhere(
        (entry) => entry.muscleGroup == MuscleGroup.back,
      );

      expect(chest.previousSets, 4);
      expect(chest.recentSets, 4);
      expect(chest.setChangePercent, closeTo(0, 0.001));
      expect(back.previousSets, 0);
      expect(back.recentSets, 2);
      expect(back.newlyActive, isTrue);
      expect(intelligence.personalRecordsLast30Days, greaterThan(0));
      expect(intelligence.personalRecordsPrevious30Days, greaterThan(0));
    },
  );
}

WorkoutSession _session(DateTime start, List<WorkoutExercise> exercises) {
  return WorkoutSession(
    scheduleTitle: 'Progress',
    startTime: start,
    endTime: start.add(const Duration(minutes: 60)),
    exercises: exercises,
  );
}

WorkoutExercise _exercise(
  String name,
  MuscleGroup muscleGroup,
  double weight,
  int reps,
) {
  return WorkoutExercise(
    name: name,
    notes: '',
    muscleGroup: muscleGroup,
    technique: IntensityTechnique.none,
    sets: [
      ExerciseSet(weight: weight, reps: reps, isCompleted: true),
      ExerciseSet(weight: weight, reps: reps, isCompleted: true),
    ],
  );
}
