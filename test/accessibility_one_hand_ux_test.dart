import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gymapp/models/exercise.dart';
import 'package:gymapp/models/workout.dart';
import 'package:gymapp/screens/active_workout.dart';
import 'package:gymapp/ui/active_workout_input_components.dart';
import 'package:gymapp/ui/workout_components.dart';
import 'package:shared_preferences/shared_preferences.dart';

WorkoutExercise _exercise(String name, List<ExerciseSet> sets) {
  return WorkoutExercise(
    name: name,
    notes: '',
    muscleGroup: MuscleGroup.chest,
    technique: IntensityTechnique.none,
    progressionScheme: ProgressionScheme.manual,
    sets: sets,
  );
}

WorkoutSession _session(List<WorkoutExercise> exercises) {
  final start = DateTime(2026, 9, 5, 10);
  return WorkoutSession(
    scheduleTitle: 'Push',
    startTime: start,
    endTime: start.add(const Duration(hours: 1)),
    exercises: exercises,
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('active set controls expose explicit semantics and 48px target', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(900, 1200);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final semantics = tester.ensureSemantics();
    addTearDown(semantics.dispose);

    final set = ExerciseSet(id: 'set_accessible', weight: 80, reps: 8);
    final exercise = _exercise('Panca', [set]);

    await tester.pumpWidget(
      MaterialApp(
        home: ActiveWorkoutScreen.editCompleted(
          session: _session([exercise]),
          defaultRestSeconds: 90,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final compactComplete = find.byKey(const ValueKey('complete-set_accessible'));
    await tester.ensureVisible(compactComplete);
    await tester.pumpAndSettle();

    final size = tester.getSize(compactComplete);
    expect(size.width, greaterThanOrEqualTo(48));
    expect(size.height, greaterThanOrEqualTo(48));
    expect(
      find.bySemanticsLabel('Panca, set 1, carico in kg'),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel('Panca, set 1, ripetizioni'),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel('Panca, set 1: completa set'),
      findsOneWidget,
    );

    final rowSemantics = tester.getSemantics(
      find.byKey(const ValueKey('set-semantics-set_accessible')),
    );
    expect(rowSemantics.getSemanticsData().customSemanticsActionIds, isNotEmpty);
  });

  testWidgets('active workout supports 200 percent text on a narrow phone', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final set = ExerciseSet(id: 'set_large_text', weight: 80, reps: 8);
    final exercise = _exercise('Panca piana con bilanciere', [set]);

    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(2.0)),
          child: child!,
        ),
        home: ActiveWorkoutScreen.editCompleted(
          session: _session([exercise]),
          defaultRestSeconds: 90,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(
      find.byKey(const ValueKey('thumb-complete-set_large_text')),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(
      find.byKey(const ValueKey('thumb-complete-set_large_text')),
      findsOneWidget,
    );
  });

  testWidgets('rest panel has unambiguous controls and reflows at large text', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 720);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final semantics = tester.ensureSemantics();
    addTearDown(semantics.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2.0)),
          child: Scaffold(
            bottomNavigationBar: WorkoutRestPanel(
              exerciseName: 'Panca',
              countdown: '01:30',
              nextSetId: 'next_set',
              nextExerciseName: 'Panca',
              nextSetLabel: 'Serie 2',
              nextPrescription: '82.5 kg × 8',
              onMinusThirty: () {},
              onPlusThirty: () {},
              onSkip: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.bySemanticsLabel('Recupero: 01:30 dopo Panca'), findsOneWidget);
    expect(
      find.bySemanticsLabel('Riduci recupero di 30 secondi'),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel('Aumenta recupero di 30 secondi'),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel('Salta il recupero'), findsOneWidget);
  });

  testWidgets('exercise navigation and compact card remain usable at 200 percent', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 720);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final semantics = tester.ensureSemantics();
    addTearDown(semantics.dispose);

    final first = _exercise('Panca piana con bilanciere', [
      ExerciseSet(weight: 80, reps: 8),
    ]);
    final second = _exercise('Rematore con manubrio', [
      ExerciseSet(weight: 40, reps: 10),
    ]);

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2.0)),
          child: Scaffold(
            body: ListView(
              children: [
                WorkoutExerciseJumpBar(
                  exercises: [first, second],
                  onSelected: (_) {},
                ),
                WorkoutCompactExerciseCard(
                  exerciseId: second.id,
                  name: second.name,
                  completedSets: 1,
                  totalSets: 3,
                  nextPrescription: '40 kg × 10',
                  isComplete: false,
                  accent: Colors.blue,
                  onTap: () {},
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.bySemanticsLabel('Vai a Rematore con manubrio'), findsOneWidget);
    expect(
      find.bySemanticsLabel(
        'Rematore con manubrio. 1/3 set · prossimo 40 kg × 10. Tocca per aprire.',
      ),
      findsOneWidget,
    );
  });
}
