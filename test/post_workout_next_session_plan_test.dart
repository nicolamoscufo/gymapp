import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gymapp/app_data_store.dart';
import 'package:gymapp/models/exercise.dart';
import 'package:gymapp/models/schedule.dart';
import 'package:gymapp/models/workout.dart';
import 'package:gymapp/post_workout_next_session_plan.dart';
import 'package:gymapp/screens/session_summary.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('builds an exact load progression diff from the deterministic engine', () {
    final schedule = _schedule(weight: 80, reps: 8);
    final previous = _session(
      id: 'previous',
      reps: 9,
      weight: 80,
      end: DateTime(2026, 8, 19, 19),
    );
    final current = _session(
      id: 'current',
      reps: 10,
      weight: 80,
      end: DateTime(2026, 8, 26, 19),
    );

    final plan = buildNextSessionPlan(
      session: current,
      history: [previous],
      schedules: [schedule],
    );

    expect(plan, isNotNull);
    expect(plan!.actions, hasLength(1));
    final action = plan.actions.single;
    expect(action.exerciseName, 'Panca');
    expect(action.actionLabel, contains('Aumenta carico'));
    expect(action.defaultSelected, isTrue);
    expect(action.changes, hasLength(1));
    expect(action.changes.single.field, 'weight');
    expect(action.changes.single.currentValue, 80.0);
    expect(action.changes.single.suggestedValue, 82.5);
  });

  test('builds a rep progression diff without changing the load', () {
    final schedule = _schedule(weight: 80, reps: 8);
    final previous = _session(
      id: 'previous',
      reps: 8,
      weight: 80,
      end: DateTime(2026, 8, 19, 19),
    );
    final current = _session(
      id: 'current',
      reps: 9,
      weight: 80,
      end: DateTime(2026, 8, 26, 19),
    );

    final plan = buildNextSessionPlan(
      session: current,
      history: [previous],
      schedules: [schedule],
    )!;

    final action = plan.actions.single;
    expect(action.actionLabel, contains('Aumenta reps'));
    expect(action.changes, hasLength(1));
    expect(action.changes.single.field, 'reps');
    expect(action.changes.single.currentValue, 8);
    expect(action.changes.single.suggestedValue, 9);
  });

  test('skips exercises added to the schedule during the same finish flow', () {
    final schedule = _schedule(weight: 80, reps: 8);
    final current = _session(
      id: 'current',
      reps: 10,
      weight: 80,
      end: DateTime(2026, 8, 26, 19),
    );

    final plan = buildNextSessionPlan(
      session: current,
      history: const [],
      schedules: [schedule],
      skipSourceExerciseIds: const {'bench'},
    );

    expect(plan, isNotNull);
    expect(plan!.actions, isEmpty);
  });

  test('apply is atomic per exercise and skips stale schedule values', () {
    final schedule = _schedule(weight: 80, reps: 8);
    final previous = _session(
      id: 'previous',
      reps: 9,
      weight: 80,
      end: DateTime(2026, 8, 19, 19),
    );
    final current = _session(
      id: 'current',
      reps: 10,
      weight: 80,
      end: DateTime(2026, 8, 26, 19),
    );
    final action = buildNextSessionPlan(
      session: current,
      history: [previous],
      schedules: [schedule],
    )!
        .actions
        .single;

    schedule.exercises.single.weight = 81;
    final result = applyNextSessionPlan(
      schedules: [schedule],
      actions: [action],
    );

    expect(result.applied, 0);
    expect(result.skipped, 1);
    expect(schedule.exercises.single.weight, 81);
  });

  testWidgets('summary reviews and applies the next-session plan on confirmation', (
    tester,
  ) async {
    final schedule = _schedule(weight: 80, reps: 8);
    await AppDataStore.saveSchedules([schedule]);
    final previous = _session(
      id: 'previous',
      reps: 9,
      weight: 80,
      end: DateTime(2026, 8, 19, 19),
    );
    final current = _session(
      id: 'current',
      reps: 10,
      weight: 80,
      end: DateTime(2026, 8, 26, 19),
    );

    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(900, 1400);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      MaterialApp(
        home: SessionSummaryScreen(
          session: current,
          previousHistory: [previous],
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));

    await tester.tap(find.byKey(const ValueKey('next-session-plan')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 450));

    expect(find.text('Piano prossima seduta'), findsWidgets);
    expect(find.textContaining('80 kg → 82.5 kg'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('apply-next-session-plan')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    final saved = (await AppDataStore.loadBundle()).schedules.single;
    expect(saved.exercises.single.weight, 82.5);
    expect(find.text('Piano applicato'), findsOneWidget);
  });
}

Schedule _schedule({required double weight, required int reps}) {
  return Schedule(
    id: 'push',
    title: 'Push',
    week: 1,
    createdAt: DateTime(2026, 8, 1),
    exercises: [
      Exercise(
        id: 'bench',
        name: 'Panca',
        reps: reps,
        set: 3,
        notes: '',
        weight: weight,
        targetMinReps: 8,
        targetMaxReps: 10,
        technique: IntensityTechnique.none,
        progressionKgStep: 2.5,
        progressionRepStep: 1,
        progressionScheme: ProgressionScheme.doubleProgression,
      ),
    ],
  );
}

WorkoutSession _session({
  required String id,
  required int reps,
  required double weight,
  required DateTime end,
}) {
  return WorkoutSession(
    id: id,
    scheduleId: 'push',
    scheduleTitle: 'Push',
    startTime: end.subtract(const Duration(minutes: 60)),
    endTime: end,
    exercises: [
      WorkoutExercise(
        id: 'bench-$id',
        sourceExerciseId: 'bench',
        name: 'Panca',
        notes: '',
        technique: IntensityTechnique.none,
        targetMinReps: 8,
        targetMaxReps: 10,
        progressionKgStep: 2.5,
        progressionRepStep: 1,
        progressionScheme: ProgressionScheme.doubleProgression,
        sets: List.generate(
          3,
          (_) => ExerciseSet(
            weight: weight,
            reps: reps,
            isCompleted: true,
            rir: 2,
          ),
        ),
      ),
    ],
  );
}
