import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gymapp/models/exercise.dart';
import 'package:gymapp/models/schedule.dart';
import 'package:gymapp/models/workout.dart';
import 'package:gymapp/progress_analytics.dart';
import 'package:gymapp/progress_period_comparison.dart';
import 'package:gymapp/screens/progress_center.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test(
    'compares equal rolling 4-week windows with strength and muscle shifts',
    () {
      final now = DateTime(2026, 8, 26);
      final history = [
        _session(
          id: 'prev',
          date: DateTime(2026, 7, 10),
          scheduleId: 's1',
          weight: 80,
          reps: 8,
          sets: 2,
        ),
        _session(
          id: 'current-1',
          date: DateTime(2026, 8, 2),
          scheduleId: 's1',
          weight: 90,
          reps: 8,
          sets: 3,
        ),
        _session(
          id: 'current-2',
          date: DateTime(2026, 8, 18),
          scheduleId: 's1',
          weight: 92.5,
          reps: 8,
          sets: 3,
        ),
      ];
      final analytics = buildProgressAnalytics(history: history, now: now);

      final comparison = buildProgressPeriodComparison(
        history: history,
        analytics: analytics,
        range: ProgressComparisonRange.fourWeeks,
        now: now,
      )!;

      expect(comparison.currentWindow.durationDays, 28);
      expect(comparison.previousWindow.durationDays, 28);
      expect(comparison.current.workouts, 2);
      expect(comparison.previous.workouts, 1);
      expect(comparison.current.completedSets, 6);
      expect(comparison.previous.completedSets, 2);
      expect(comparison.strengthShifts, hasLength(1));
      expect(comparison.strengthShifts.single.exerciseName, 'Panca');
      expect(comparison.strengthShifts.single.changePercent, greaterThan(15));
      expect(comparison.muscleShifts.single.muscleGroup, MuscleGroup.chest);
      expect(comparison.muscleShifts.single.currentSets, 6);
      expect(comparison.muscleShifts.single.previousSets, 2);
    },
  );

  test(
    'mesocycle compares equal elapsed days and filters the selected schedule',
    () {
      final now = DateTime(2026, 8, 15);
      final schedule = Schedule(
        id: 's1',
        title: 'Upper',
        week: 1,
        createdAt: DateTime(2026, 8, 1),
        exercises: const [],
        mesocycleWeeks: 8,
        cycleNumber: 2,
      );
      final history = [
        _session(
          id: 'prev-upper',
          date: DateTime(2026, 7, 20),
          scheduleId: 's1',
          weight: 80,
          reps: 8,
        ),
        _session(
          id: 'current-upper',
          date: DateTime(2026, 8, 5),
          scheduleId: 's1',
          weight: 85,
          reps: 8,
        ),
        _session(
          id: 'other',
          date: DateTime(2026, 8, 6),
          scheduleId: 's2',
          scheduleTitle: 'Lower',
          weight: 160,
          reps: 5,
        ),
      ];
      final analytics = buildProgressAnalytics(history: history, now: now);

      final comparison = buildProgressPeriodComparison(
        history: history,
        analytics: analytics,
        range: ProgressComparisonRange.mesocycle,
        schedule: schedule,
        now: now,
      )!;

      expect(comparison.currentWindow.start, DateTime(2026, 8, 1));
      expect(comparison.currentWindow.durationDays, 15);
      expect(comparison.previousWindow.durationDays, 15);
      expect(comparison.current.workouts, 1);
      expect(comparison.previous.workouts, 1);
      expect(comparison.schedule?.id, 's1');
      expect(comparison.strengthShifts, hasLength(1));
    },
  );

  testWidgets('Progress Center exposes rolling and mesocycle comparison UI', (
    tester,
  ) async {
    final now = DateTime(2026, 8, 26);
    final schedule = Schedule(
      id: 's1',
      title: 'Upper',
      week: 1,
      createdAt: DateTime(2026, 8, 1),
      exercises: const [],
      mesocycleWeeks: 8,
      cycleNumber: 2,
    );
    final history = [
      _session(
        id: 'prev',
        date: DateTime(2026, 7, 10),
        scheduleId: 's1',
        weight: 80,
        reps: 8,
      ),
      _session(
        id: 'current',
        date: DateTime(2026, 8, 10),
        scheduleId: 's1',
        weight: 90,
        reps: 8,
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ProgressCenterScreen(
            history: history,
            schedules: [schedule],
            now: now,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Periodi'));
    await tester.pumpAndSettle();
    expect(find.text('Confronto periodi'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('period-comparison-window')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('period-metric-workouts')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('period-metric-volume')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('period-range-mesocycle')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('period-mesocycle-schedule')),
      findsOneWidget,
    );
    expect(find.textContaining('ciclo 2'), findsWidgets);
  });
}

WorkoutSession _session({
  required String id,
  required DateTime date,
  required String scheduleId,
  String scheduleTitle = 'Upper',
  required double weight,
  required int reps,
  int sets = 1,
}) {
  return WorkoutSession(
    id: id,
    scheduleId: scheduleId,
    scheduleTitle: scheduleTitle,
    startTime: date,
    endTime: date.add(const Duration(minutes: 60)),
    exercises: [
      WorkoutExercise(
        name: 'Panca',
        notes: '',
        muscleGroup: MuscleGroup.chest,
        technique: IntensityTechnique.none,
        sets: List.generate(
          sets,
          (_) => ExerciseSet(weight: weight, reps: reps, isCompleted: true),
        ),
      ),
    ],
  );
}
