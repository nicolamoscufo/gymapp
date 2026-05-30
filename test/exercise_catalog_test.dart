import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gymapp/exercise_catalog.dart';
import 'package:gymapp/models/exercise.dart';
import 'package:gymapp/models/schedule.dart';
import 'package:gymapp/screens/home.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('loads bundled exercise catalog from JSON asset', () async {
    final catalog = await loadExerciseCatalog();

    expect(catalog.length, greaterThan(1000));
    expect(
      catalog.map((entry) => entry.muscleGroup),
      contains(MuscleGroup.chest),
    );
    expect(
      catalog.map((entry) => entry.muscleGroup),
      contains(MuscleGroup.abs),
    );
  });

  test('filters catalog suggestions by muscle group and query', () {
    final catalog = parseExerciseCatalog('''
[
  {
    "bodyPart": "chest",
    "equipment": "barbell",
    "gifUrl": "",
    "id": "1",
    "name": "bench press test",
    "target": "pecs",
    "secondaryMuscles": ["triceps"],
    "instructions": []
  },
  {
    "bodyPart": "back",
    "equipment": "cable",
    "gifUrl": "",
    "id": "2",
    "name": "lat pulldown test",
    "target": "lats",
    "secondaryMuscles": ["biceps"],
    "instructions": []
  }
]
''');

    final suggestions = filterExerciseCatalog(
      catalog,
      query: 'bench',
      muscleGroup: MuscleGroup.chest,
    );

    expect(suggestions, hasLength(1));
    expect(suggestions.single.name, 'bench press test');
    expect(suggestions.single.muscleGroup, MuscleGroup.chest);
  });

  testWidgets('exercise picker adds catalog entries by muscle group', (
    tester,
  ) async {
    final schedule = Schedule(
      id: 'schedule_1',
      title: 'Push',
      week: 1,
      createdAt: DateTime(2026),
      exercises: [],
    );

    SharedPreferences.setMockInitialValues({
      'schedules': jsonEncode([schedule.toJson()]),
      'history': '[]',
    });

    await tester.pumpWidget(const MaterialApp(home: HomePage()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Push'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    expect(find.text('Aggiungi esercizi'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('exercise-filter-chest')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('exercise-picker-search')),
      'archer push up',
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('exercise-picker-3294')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('exercise-picker-3294')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Aggiungi 1 esercizio'));
    await tester.pumpAndSettle();

    expect(find.text('Archer Push Up'), findsOneWidget);

    final prefs = await SharedPreferences.getInstance();
    final storedSchedules =
        jsonDecode(prefs.getString('schedules')!) as List<dynamic>;
    final storedExercises =
        storedSchedules.single['exercises'] as List<dynamic>;
    expect(storedExercises.single['name'], 'Archer Push Up');
    expect(storedExercises.single['muscleGroup'], 'chest');
    expect(storedExercises.single['set'], 3);
    expect(storedExercises.single['reps'], 10);
  });
}
