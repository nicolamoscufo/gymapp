import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:gymapp/models/exercise.dart';
import 'package:gymapp/models/schedule.dart';
import 'package:gymapp/screens/active_workout.dart';
import 'package:gymapp/screens/home.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({
      'schedules': '[]',
      'history': '[]',
    });
  });

  testWidgets('Allenati exposes and opens an empty workout', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: HomePage(initialIndex: 2)));
    await tester.pumpAndSettle();

    expect(find.text('Allenamento libero'), findsOneWidget);
    await tester.tap(find.text('Allenamento libero'));
    await tester.pumpAndSettle();

    expect(find.text('Sessione'), findsWidgets);
    expect(find.text('Esercizio'), findsOneWidget);
  });

  testWidgets('exercise menu duplicates an exercise in the live session', (
    tester,
  ) async {
    final schedule = Schedule(
      title: 'Push',
      week: 1,
      createdAt: DateTime(2026),
      exercises: [
        Exercise(
          name: 'Panca',
          set: 2,
          reps: 8,
          weight: 80,
          muscleGroup: MuscleGroup.chest,
          notes: '',
          technique: IntensityTechnique.none,
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ActiveWorkoutScreen(
          schedule: schedule,
          history: const [],
          defaultRestSeconds: 90,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Panca'), findsOneWidget);
    await tester.tap(find.byTooltip('Azioni esercizio'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Duplica'));
    await tester.pumpAndSettle();

    expect(find.text('Panca'), findsAtLeastNWidgets(2));
  });

  testWidgets('exercise menu can create and remove a superset', (tester) async {
    final schedule = Schedule(
      title: 'Upper',
      week: 1,
      createdAt: DateTime(2026),
      exercises: [
        Exercise(
          name: 'Panca',
          set: 1,
          reps: 8,
          weight: 80,
          muscleGroup: MuscleGroup.chest,
          notes: '',
          technique: IntensityTechnique.none,
        ),
        Exercise(
          name: 'Rematore',
          set: 1,
          reps: 10,
          weight: 60,
          muscleGroup: MuscleGroup.back,
          notes: '',
          technique: IntensityTechnique.none,
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ActiveWorkoutScreen(
          schedule: schedule,
          history: const [],
          defaultRestSeconds: 90,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Azioni esercizio').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Crea superset'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rematore').last);
    await tester.pumpAndSettle();

    expect(find.text('Superset 1'), findsWidgets);

    await tester.tap(find.byTooltip('Azioni esercizio').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Gestisci superset'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rimuovi dal superset'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Azioni esercizio').first);
    await tester.pumpAndSettle();
    expect(find.text('Crea superset'), findsOneWidget);
  });

  testWidgets('exercise menu exposes reorder replace and delete actions', (
    tester,
  ) async {
    final schedule = Schedule(
      title: 'Upper',
      week: 1,
      createdAt: DateTime(2026),
      exercises: [
        Exercise(
          name: 'Panca',
          set: 1,
          reps: 8,
          weight: 80,
          muscleGroup: MuscleGroup.chest,
          notes: '',
          technique: IntensityTechnique.none,
        ),
        Exercise(
          name: 'Rematore',
          set: 1,
          reps: 10,
          weight: 60,
          muscleGroup: MuscleGroup.back,
          notes: '',
          technique: IntensityTechnique.none,
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ActiveWorkoutScreen(
          schedule: schedule,
          history: const [],
          defaultRestSeconds: 90,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Azioni esercizio').first);
    await tester.pumpAndSettle();

    expect(find.text('Sostituisci'), findsOneWidget);
    expect(find.text('Duplica'), findsOneWidget);
    expect(find.text('Crea superset'), findsOneWidget);
    expect(find.text('Sposta su'), findsOneWidget);
    expect(find.text('Sposta giù'), findsOneWidget);
    expect(find.text('Elimina'), findsOneWidget);
  });
}
