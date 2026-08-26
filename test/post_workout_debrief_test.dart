import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gymapp/models/exercise.dart';
import 'package:gymapp/models/workout.dart';
import 'package:gymapp/post_workout_debrief.dart';
import 'package:gymapp/screens/session_summary.dart';
import 'package:gymapp/workout_progression_analytics.dart';
import 'package:shared_preferences/shared_preferences.dart';

WorkoutExercise _exercise(
  String name, {
  required double weight,
  required int reps,
  int setCount = 3,
}) {
  return WorkoutExercise(
    name: name,
    notes: '',
    muscleGroup: MuscleGroup.chest,
    targetMinReps: 8,
    targetMaxReps: 10,
    technique: IntensityTechnique.none,
    progressionScheme: ProgressionScheme.doubleProgression,
    progressionKgStep: 2.5,
    sets: List.generate(
      setCount,
      (_) => ExerciseSet(weight: weight, reps: reps, isCompleted: true, rir: 2),
    ),
  );
}

WorkoutSession _session({
  required String id,
  required String scheduleId,
  required DateTime start,
  required Duration duration,
  required WorkoutExercise exercise,
}) {
  return WorkoutSession(
    id: id,
    scheduleId: scheduleId,
    scheduleTitle: 'Push',
    startTime: start,
    endTime: start.add(duration),
    exercises: [exercise],
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('debrief compares only the latest session from the same schedule', () {
    final previous = _session(
      id: 'previous',
      scheduleId: 'push-plan',
      start: DateTime(2026, 8, 19, 18),
      duration: const Duration(minutes: 60),
      exercise: _exercise('Bench Press', weight: 100, reps: 8),
    );
    final unrelated = _session(
      id: 'unrelated',
      scheduleId: 'pull-plan',
      start: DateTime(2026, 8, 24, 18),
      duration: const Duration(minutes: 40),
      exercise: _exercise('Bench Press', weight: 120, reps: 10),
    );
    final current = _session(
      id: 'current',
      scheduleId: 'push-plan',
      start: DateTime(2026, 8, 26, 18),
      duration: const Duration(minutes: 50),
      exercise: _exercise('Bench Press', weight: 100, reps: 10),
    );

    final debrief = buildPostWorkoutDebrief(
      session: current,
      history: [previous, unrelated],
    );

    expect(debrief.previousComparableSession?.id, 'previous');
    expect(debrief.totalVolume, 3000);
    expect(debrief.volumeChangePercent, closeTo(25, 0.001));
    expect(debrief.completedWorkSetDelta, 0);
    expect(debrief.densityKgPerMinute, closeTo(60, 0.001));
    expect(debrief.densityChangePercent, closeTo(50, 0.001));
    expect(debrief.exercises, hasLength(1));
    expect(
      debrief.exercises.single.progression.action,
      ProgressionAction.increaseLoad,
    );
    expect(debrief.readyToProgressCount, 1);
  });

  test(
    'first comparable session keeps absolute metrics without fake deltas',
    () {
      final current = _session(
        id: 'current',
        scheduleId: 'push-plan',
        start: DateTime(2026, 8, 26, 18),
        duration: const Duration(minutes: 45),
        exercise: _exercise('Bench Press', weight: 80, reps: 8),
      );

      final debrief = buildPostWorkoutDebrief(
        session: current,
        history: const [],
      );

      expect(debrief.hasComparableSession, isFalse);
      expect(debrief.volumeChangePercent, isNull);
      expect(debrief.completedWorkSetDelta, isNull);
      expect(debrief.densityChangePercent, isNull);
      expect(debrief.totalVolume, 1920);
      expect(debrief.completedWorkSets, 3);
    },
  );

  testWidgets('session summary surfaces comparison and next-session action', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1000, 1600);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final previous = _session(
      id: 'previous',
      scheduleId: 'push-plan',
      start: DateTime(2026, 8, 19, 18),
      duration: const Duration(minutes: 60),
      exercise: _exercise('Bench Press', weight: 100, reps: 8),
    );
    final currentExercise = _exercise('Bench Press', weight: 100, reps: 10);
    final current = _session(
      id: 'current',
      scheduleId: 'push-plan',
      start: DateTime(2026, 8, 26, 18),
      duration: const Duration(minutes: 50),
      exercise: currentExercise,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: SessionSummaryScreen(
          session: current,
          previousHistory: [previous],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('post-workout-debrief')), findsOneWidget);
    expect(find.text('Smart Debrief'), findsOneWidget);
    expect(
      find.text('Confronto con l’ultima seduta della stessa scheda.'),
      findsOneWidget,
    );
    expect(find.text('+25.0%'), findsOneWidget);
    expect(find.text('+50.0%'), findsOneWidget);
    expect(
      find.byKey(ValueKey('debrief-next-${currentExercise.id}')),
      findsOneWidget,
    );
    expect(find.textContaining('Aumenta carico'), findsOneWidget);
  });
}
