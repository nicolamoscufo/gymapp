from pathlib import Path

active_path = Path('lib/screens/active_workout.dart')
active = active_path.read_text()
for block in [
    """  void _addCatalogExercisesToSession(List<ExerciseCatalogEntry> entries) {
    _addExercisesToSession(entries.map(_exerciseFromCatalogEntry).toList());
  }

""",
    """  void _addCustomExercisesToSession(List<Exercise> exercises) {
    _addExercisesToSession(exercises.map(_copyExerciseTemplate).toList());
  }

""",
]:
    if block not in active:
        raise RuntimeError('expected legacy add helper was not found')
    active = active.replace(block, '', 1)
active_path.write_text(active)

path = Path('test/workout_experience_v2_test.dart')
text = path.read_text()
start = text.index("  testWidgets('exercise menu can create and remove a superset'")
end = text.index("  testWidgets('exercise menu exposes reorder replace and delete actions'", start)
replacement = r'''  testWidgets('exercise menu can create and remove a superset', (tester) async {
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

    expect(find.text('Superset 1'), findsNWidgets(2));

    await tester.tap(find.byTooltip('Azioni esercizio').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Gestisci superset'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rimuovi dal superset'));
    await tester.pumpAndSettle();

    expect(find.text('Superset 1'), findsNothing);
  });

'''
text = text[:start] + replacement + text[end:]
text = text.replace(
    "          notes: '',\n        ),",
    "          notes: '',\n          technique: IntensityTechnique.none,\n        ),",
)
path.write_text(text)
