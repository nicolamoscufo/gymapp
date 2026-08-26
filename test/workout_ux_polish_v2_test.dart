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

  testWidgets(
    'numeric set flow selects, advances and completes from keyboard',
    (tester) async {
      final set = ExerciseSet(weight: 50, reps: 8);
      final exercise = _exercise('Bench', sets: [set])..restSeconds = 0;
      final session = _session([exercise]);

      await tester.pumpWidget(
        MaterialApp(
          home: ActiveWorkoutScreen.resume(
            resumedSession: session,
            defaultRestSeconds: 90,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final weightField = find.descendant(
        of: find.byKey(ValueKey('${set.id}-weight')),
        matching: find.byType(TextFormField),
      );
      final repsField = find.descendant(
        of: find.byKey(ValueKey('${set.id}-reps')),
        matching: find.byType(TextFormField),
      );

      await tester.tap(weightField);
      await tester.pump();
      var weightWidget = tester.widget<TextFormField>(weightField);
      expect(weightWidget.controller?.selection.baseOffset, 0);
      expect(weightWidget.controller?.selection.extentOffset, 2);

      await tester.enterText(weightField, '55x');
      weightWidget = tester.widget<TextFormField>(weightField);
      expect(weightWidget.controller?.text, '55');

      await tester.testTextInput.receiveAction(TextInputAction.next);
      await tester.pump();

      var repsWidget = tester.widget<TextFormField>(repsField);
      expect(repsWidget.controller?.selection.baseOffset, 0);
      expect(repsWidget.controller?.selection.extentOffset, 1);

      await tester.enterText(repsField, '10x');
      repsWidget = tester.widget<TextFormField>(repsField);
      expect(repsWidget.controller?.text, '10');

      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();

      expect(set.weight, 55);
      expect(set.reps, 10);
      expect(set.isCompleted, isTrue);
    },
  );

  testWidgets('one-hand UX promotes only the next pending set', (tester) async {
    final first = ExerciseSet(weight: 50, reps: 8);
    final second = ExerciseSet(weight: 50, reps: 8);
    final exercise = _exercise('Bench', sets: [first, second]);
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

    expect(find.byKey(ValueKey('current-set-${first.id}')), findsOneWidget);
    expect(find.byKey(ValueKey('current-set-${second.id}')), findsNothing);
    expect(find.byKey(ValueKey('thumb-complete-${first.id}')), findsOneWidget);
    expect(find.byKey(ValueKey('thumb-complete-${second.id}')), findsNothing);
    expect(find.byKey(ValueKey('plates-${first.id}')), findsOneWidget);
    expect(find.byKey(ValueKey('plates-${second.id}')), findsNothing);

    final thumbComplete = find.byKey(ValueKey('thumb-complete-${first.id}'));
    await tester.ensureVisible(thumbComplete);
    await tester.tap(thumbComplete);
    await tester.pumpAndSettle();

    expect(find.byKey(ValueKey('current-set-${first.id}')), findsNothing);
    expect(find.byKey(ValueKey('current-set-${second.id}')), findsOneWidget);
    expect(find.byKey(ValueKey('thumb-complete-${second.id}')), findsOneWidget);
    expect(find.byKey(ValueKey('plates-${first.id}')), findsNothing);
    expect(find.byKey(ValueKey('plates-${second.id}')), findsOneWidget);
  });

  testWidgets(
    'set details keeps type editing available outside quick controls',
    (tester) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(1200, 1200);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);

      final first = ExerciseSet(weight: 50, reps: 8, isCompleted: true);
      final second = ExerciseSet(weight: 50, reps: 8);
      final exercise = _exercise('Bench', sets: [first, second]);
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

      expect(find.byKey(ValueKey('plates-${first.id}')), findsNothing);
      final details = find.byKey(ValueKey('set-details-${first.id}'));
      await tester.ensureVisible(details);
      await tester.tap(details);
      await tester.pump(const Duration(milliseconds: 300));

      final typePicker = find.byKey(ValueKey('set-details-type-${first.id}'));
      expect(typePicker, findsOneWidget);
      expect(find.text('Tipo set'), findsOneWidget);
    },
  );

  testWidgets('rest mode surfaces the next set and thumb controls', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(900, 1200);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final first = ExerciseSet(weight: 50, reps: 8);
    final second = ExerciseSet(weight: 52.5, reps: 8);
    final exercise = _exercise('Bench', sets: [first, second])
      ..restSeconds = 90;
    final session = _session([exercise]);

    await tester.pumpWidget(
      MaterialApp(
        home: ActiveWorkoutScreen.resume(
          resumedSession: session,
          defaultRestSeconds: 90,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final complete = find.byKey(ValueKey('thumb-complete-${first.id}'));
    await tester.ensureVisible(complete);
    await tester.tap(complete);
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.byKey(ValueKey('rest-mode-${exercise.id}')), findsOneWidget);
    expect(find.byKey(ValueKey('rest-next-set-${second.id}')), findsOneWidget);
    expect(find.text('PROSSIMO SET'), findsOneWidget);
    expect(find.textContaining('52.5 kg'), findsOneWidget);
    expect(find.byKey(const ValueKey('rest-minus-30')), findsOneWidget);
    expect(find.byKey(const ValueKey('rest-plus-30')), findsOneWidget);
    expect(find.byKey(const ValueKey('rest-skip')), findsOneWidget);
    final restingScaffold = tester.widget<Scaffold>(
      find.byType(Scaffold).first,
    );
    expect(restingScaffold.floatingActionButton, isNull);

    await tester.tap(find.byKey(const ValueKey('rest-skip')));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byKey(ValueKey('rest-mode-${exercise.id}')), findsNothing);
    final idleScaffold = tester.widget<Scaffold>(find.byType(Scaffold).first);
    expect(idleScaffold.floatingActionButton, isNotNull);
  });

  testWidgets('rest mode follows the next superset round', (tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(900, 1400);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final a1 = ExerciseSet(weight: 60, reps: 8);
    final a2 = ExerciseSet(weight: 62.5, reps: 8);
    final b1 = ExerciseSet(weight: 30, reps: 10);
    final b2 = ExerciseSet(weight: 32.5, reps: 10);
    final a = _exercise('Bench', sets: [a1, a2], supersetGroup: 7)
      ..restSeconds = 90;
    final b = _exercise('Row', sets: [b1, b2], supersetGroup: 7)
      ..restSeconds = 90;
    final session = _session([a, b]);

    await tester.pumpWidget(
      MaterialApp(
        home: ActiveWorkoutScreen.resume(
          resumedSession: session,
          defaultRestSeconds: 90,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final completeA = find.byKey(ValueKey('complete-${a1.id}'));
    await tester.ensureVisible(completeA);
    await tester.tap(completeA);
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byKey(ValueKey('rest-mode-${a.id}')), findsNothing);

    final completeB = find.byKey(ValueKey('complete-${b1.id}'));
    await tester.ensureVisible(completeB);
    await tester.tap(completeB);
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.byKey(ValueKey('rest-mode-${b.id}')), findsOneWidget);
    expect(find.byKey(ValueKey('rest-next-set-${a2.id}')), findsOneWidget);
    expect(find.text('Bench'), findsWidgets);
    expect(find.textContaining('62.5 kg'), findsOneWidget);
  });

  testWidgets('rest expiry hands off to the exact next set', (tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(900, 1200);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final first = ExerciseSet(weight: 50, reps: 8);
    final second = ExerciseSet(weight: 52.5, reps: 8);
    final exercise = _exercise('Bench', sets: [first, second])..restSeconds = 1;
    final session = _session([exercise]);

    await tester.pumpWidget(
      MaterialApp(
        home: ActiveWorkoutScreen.resume(
          resumedSession: session,
          defaultRestSeconds: 90,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final complete = find.byKey(ValueKey('thumb-complete-${first.id}'));
    await tester.ensureVisible(complete);
    await tester.tap(complete);
    await tester.pump();
    expect(find.byKey(ValueKey('rest-mode-${exercise.id}')), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 1100));
    await tester.pump(const Duration(milliseconds: 40));

    expect(find.byKey(ValueKey('rest-mode-${exercise.id}')), findsNothing);
    expect(find.byKey(ValueKey('current-set-${second.id}')), findsOneWidget);
    expect(find.byKey(ValueKey('handoff-set-${second.id}')), findsOneWidget);
    expect(find.text('TOCCA A TE'), findsOneWidget);
    expect(find.textContaining('Recupero finito · Bench'), findsOneWidget);
  });

  testWidgets('rest expiry hands a superset to the next round leader', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(900, 1500);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final a1 = ExerciseSet(weight: 60, reps: 8);
    final a2 = ExerciseSet(weight: 62.5, reps: 8);
    final b1 = ExerciseSet(weight: 30, reps: 10);
    final b2 = ExerciseSet(weight: 32.5, reps: 10);
    final a = _exercise('Bench', sets: [a1, a2], supersetGroup: 7)
      ..restSeconds = 1;
    final b = _exercise('Row', sets: [b1, b2], supersetGroup: 7)
      ..restSeconds = 1;
    final session = _session([a, b]);

    await tester.pumpWidget(
      MaterialApp(
        home: ActiveWorkoutScreen.resume(
          resumedSession: session,
          defaultRestSeconds: 90,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final completeA = find.byKey(ValueKey('complete-${a1.id}'));
    await tester.ensureVisible(completeA);
    await tester.tap(completeA);
    await tester.pump();
    expect(find.byKey(ValueKey('rest-mode-${a.id}')), findsNothing);

    final completeB = find.byKey(ValueKey('complete-${b1.id}'));
    await tester.ensureVisible(completeB);
    await tester.tap(completeB);
    await tester.pump();
    expect(find.byKey(ValueKey('rest-mode-${b.id}')), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 1100));
    await tester.pump(const Duration(milliseconds: 40));

    expect(find.byKey(ValueKey('rest-mode-${b.id}')), findsNothing);
    expect(find.byKey(ValueKey('handoff-set-${a2.id}')), findsOneWidget);
    expect(find.byKey(ValueKey('current-set-${a2.id}')), findsOneWidget);
    expect(find.byKey(ValueKey('handoff-set-${b2.id}')), findsNothing);
  });
}
