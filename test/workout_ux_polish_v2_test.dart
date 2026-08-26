import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gymapp/active_workout_exercise_manager.dart';
import 'package:gymapp/active_workout_session_builder.dart';
import 'package:gymapp/active_workout_set_manager.dart';
import 'package:gymapp/models/exercise.dart';
import 'package:gymapp/models/workout.dart';
import 'package:gymapp/screens/active_workout.dart';
import 'package:shared_preferences/shared_preferences.dart';

WorkoutExercise _exercise(
  String name, {
  List<ExerciseSet>? sets,
  List<double> previousWeights = const [],
  List<int> previousReps = const [],
  int? supersetGroup,
}) {
  return WorkoutExercise(
    name: name,
    notes: '',
    muscleGroup: MuscleGroup.chest,
    technique: IntensityTechnique.none,
    supersetGroup: supersetGroup,
    progressionScheme: ProgressionScheme.manual,
    sets:
        sets ??
        [ExerciseSet(weight: 50, reps: 8), ExerciseSet(weight: 50, reps: 8)],
    previousWeights: previousWeights,
    previousReps: previousReps,
  );
}

WorkoutSession _session(List<WorkoutExercise> exercises) {
  final now = DateTime(2026, 8, 26, 10);
  return WorkoutSession(
    scheduleTitle: 'Push',
    startTime: now,
    endTime: now.add(const Duration(hours: 1)),
    exercises: exercises,
  );
}

ActiveWorkoutExerciseManager _exerciseManager(WorkoutSession session) {
  return ActiveWorkoutExerciseManager(
    session: session,
    sessionBuilder: ActiveWorkoutSessionBuilder(
      history: const [],
      bodyLogs: const [],
      now: () => DateTime(2026, 8, 26, 12),
    ),
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test(
    'smart navigation advances only after a normal exercise is complete',
    () {
      final first = _exercise('Bench');
      final completedMiddle = _exercise(
        'Fly',
        sets: [ExerciseSet(weight: 20, reps: 12, isCompleted: true)],
      );
      final next = _exercise('Press');
      final session = _session([first, completedMiddle, next]);
      final manager = _exerciseManager(session);

      first.sets.first.isCompleted = true;
      expect(manager.nextSupersetMemberAfterSet(first, 0), isNull);

      first.sets.last.isCompleted = true;
      expect(manager.nextSupersetMemberAfterSet(first, 1)?.id, next.id);
    },
  );

  test('smart navigation keeps drop-set and superset priority', () {
    final supersetA = _exercise('A', supersetGroup: 7);
    final supersetB = _exercise('B', supersetGroup: 7);
    final drop = _exercise(
      'Drop',
      sets: [
        ExerciseSet(weight: 30, reps: 10),
        ExerciseSet(weight: 20, reps: 10, type: SetType.drop),
      ],
    );
    final manager = _exerciseManager(_session([supersetA, supersetB, drop]));

    supersetA.sets.first.isCompleted = true;
    expect(manager.nextSupersetMemberAfterSet(supersetA, 0)?.id, supersetB.id);
    expect(manager.nextSupersetMemberAfterSet(drop, 0), isNull);
  });

  test('previous-values bulk fill preserves completed sets', () {
    final exercise = _exercise(
      'Bench',
      sets: [
        ExerciseSet(weight: 70, reps: 6, isCompleted: true),
        ExerciseSet(weight: 72.5, reps: 7),
      ],
      previousWeights: const [67.5, 70],
      previousReps: const [8, 9],
    );
    final manager = ActiveWorkoutSetManager(session: _session([exercise]));

    expect(manager.applyPreviousValues(exercise), isTrue);
    expect(exercise.sets.first.weight, 70);
    expect(exercise.sets.first.reps, 6);
    expect(exercise.sets.last.weight, 70);
    expect(exercise.sets.last.reps, 9);
    expect(manager.applyPreviousValues(exercise), isFalse);
  });

  testWidgets('workout UX exposes bulk previous values and timer presets', (
    tester,
  ) async {
    final exercise = _exercise(
      'Bench',
      previousWeights: const [47.5, 50],
      previousReps: const [9, 8],
    )..restSeconds = 120;
    final session = _session([exercise]);

    await tester.pumpWidget(
      MaterialApp(
        home: ActiveWorkoutScreen.editCompleted(
          session: session,
          defaultRestSeconds: 90,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(ValueKey('use-previous-values-${exercise.id}')),
      findsOneWidget,
    );
    expect(find.byKey(ValueKey('rest-preset-${exercise.id}')), findsOneWidget);

    await tester.tap(find.byKey(ValueKey('rest-preset-${exercise.id}')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('90 s'));
    await tester.pumpAndSettle();

    final restField = tester.widget<TextFormField>(
      find.descendant(
        of: find.byKey(ValueKey('rest-${exercise.id}')),
        matching: find.byType(TextFormField),
      ),
    );
    expect(restField.controller?.text, '90');
  });
}
