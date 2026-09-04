import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gymapp/active_workout_focus_controller.dart';
import 'package:gymapp/home_dashboard_state.dart';
import 'package:gymapp/home_history_analytics.dart';
import 'package:gymapp/models/body_log.dart';
import 'package:gymapp/models/exercise.dart';
import 'package:gymapp/models/schedule.dart';
import 'package:gymapp/models/workout.dart';
import 'package:gymapp/ui/active_workout_input_components.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'workout focus controller resolves explicit and pending exercise focus',
    () {
      final controller = ActiveWorkoutFocusController();
      final completed = _workoutExercise(
        id: 'bench',
        name: 'Panca',
        weight: 80,
        completed: true,
      );
      final pending = _workoutExercise(
        id: 'row',
        name: 'Rematore',
        weight: 70,
        completed: false,
      );

      expect(
        controller.effectiveFocusedExerciseId([
          completed,
          pending,
        ], editCompletedSession: false),
        'row',
      );

      controller.focusedExerciseId = 'bench';
      expect(
        controller.effectiveFocusedExerciseId([
          completed,
          pending,
        ], editCompletedSession: false),
        'bench',
      );

      controller.removeExercise('bench');
      expect(controller.focusedExerciseId, isNull);
      expect(
        controller.effectiveFocusedExerciseId([
          completed,
          pending,
        ], editCompletedSession: true),
        isNull,
      );
      controller.dispose();
    },
  );

  test('workout focus controller keeps stable anchor keys', () {
    final controller = ActiveWorkoutFocusController();
    expect(
      identical(
        controller.exerciseCardKey('bench'),
        controller.exerciseCardKey('bench'),
      ),
      isTrue,
    );
    expect(
      identical(controller.setRowKey('set-1'), controller.setRowKey('set-1')),
      isTrue,
    );
    controller.dispose();
  });

  test(
    'home history analytics owns PR, filtering and progress calculations',
    () {
      final first = _session(DateTime(2026, 8, 1, 18), [
        _workoutExercise(id: 'b1', name: 'Panca', weight: 80),
      ]);
      final second = _session(DateTime(2026, 8, 8, 18), [
        _workoutExercise(id: 'b2', name: 'Panca', weight: 82.5),
      ]);
      final analytics = HomeHistoryAnalytics([first, second]);

      final progress = analytics.buildExerciseProgressSummaries();
      expect(progress, hasLength(1));
      expect(progress.single.name, 'Panca');
      expect(progress.single.isImproved, isTrue);
      expect(progress.single.volumeDelta, greaterThan(0));

      final prs = analytics.buildRecentPrSummaries();
      expect(prs, hasLength(1));
      expect(prs.single.exerciseName, 'Panca');
      expect(analytics.sessionHasPr(first), isFalse);
      expect(analytics.sessionHasPr(second), isTrue);

      final filtered = analytics.filteredSessions(
        [second, first],
        range: HomeHistoryRangeFilter.last30,
        query: 'panca',
        onlyPr: true,
        now: DateTime(2026, 8, 10),
      );
      expect(filtered, [second]);
    },
  );

  test('home dashboard derived state is deterministic for a supplied date', () {
    final schedule = Schedule(
      id: 'schedule-1',
      title: 'Upper',
      week: 1,
      createdAt: DateTime(2026, 8),
      deloadEveryWeeks: 0,
      trainingWeekdays: const [DateTime.monday],
      exercises: [
        Exercise(
          id: 'exercise-1',
          name: 'Panca',
          set: 3,
          reps: 8,
          weight: 80,
          notes: '',
          technique: IntensityTechnique.none,
        ),
      ],
    );
    final now = DateTime(2026, 9, 4, 12);

    final planned = HomeDashboardState.nextPlannedWorkout([schedule], now: now);
    expect(planned, isNotNull);
    expect(planned!.schedule.id, 'schedule-1');
    expect(planned.date, DateTime(2026, 9, 7));

    final bodyLogs = [
      BodyLog(date: DateTime(2026, 9, 1), bodyWeight: 80),
      BodyLog(date: DateTime(2026, 9, 3), bodyWeight: 79.5),
    ];
    expect(HomeDashboardState.latestBodyLog(bodyLogs)?.bodyWeight, 79.5);

    final history = [
      _session(DateTime(2026, 9, 1, 18), const []),
      _session(DateTime(2026, 8, 30, 18), const []),
    ];
    expect(HomeDashboardState.workoutsThisWeek(history, now: now), 1);
  });

  testWidgets(
    'stable set input preserves an active edit across parent rebuilds',
    (tester) async {
      var modelText = '80';
      late StateSetter rebuild;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                rebuild = setState;
                return StableWorkoutSetTextField(
                  text: modelText,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  decoration: const InputDecoration(),
                  onChanged: (_) {},
                );
              },
            ),
          ),
        ),
      );

      final field = find.byType(TextFormField);
      await tester.tap(field);
      await tester.enterText(field, '82.5');
      modelText = '90';
      rebuild(() {});
      await tester.pump();

      expect(find.text('82.5'), findsOneWidget);
    },
  );

  testWidgets('exercise jump bar emits the stable exercise id', (tester) async {
    String? selected;
    final exercise = _workoutExercise(
      id: 'bench',
      name: 'Panca piana',
      weight: 80,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WorkoutExerciseJumpBar(
            exercises: [exercise],
            onSelected: (id) => selected = id,
          ),
        ),
      ),
    );

    await tester.tap(find.text('Panca piana'));
    expect(selected, 'bench');
  });
}

WorkoutSession _session(DateTime start, List<WorkoutExercise> exercises) {
  return WorkoutSession(
    scheduleTitle: 'Workout',
    startTime: start,
    endTime: start.add(const Duration(hours: 1)),
    exercises: exercises,
  );
}

WorkoutExercise _workoutExercise({
  required String id,
  required String name,
  required double weight,
  bool completed = true,
}) {
  return WorkoutExercise(
    id: id,
    name: name,
    notes: '',
    technique: IntensityTechnique.none,
    sets: [
      ExerciseSet(weight: weight, reps: 8, isCompleted: completed),
      ExerciseSet(weight: weight, reps: 8, isCompleted: completed),
    ],
  );
}
