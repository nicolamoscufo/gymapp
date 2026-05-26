import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gymapp/models/exercise.dart';
import 'package:gymapp/models/schedule.dart';
import 'package:gymapp/models/workout.dart';
import 'package:gymapp/number_input.dart';
import 'package:gymapp/screens/home.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('schedule deletion can be undone', (tester) async {
    final schedule = Schedule(
      id: 'schedule_1',
      title: 'Push',
      week: 1,
      createdAt: DateTime(2026),
      exercises: [
        Exercise(
          id: 'exercise_1',
          name: 'Panca',
          reps: 8,
          set: 3,
          notes: '',
          weight: 80,
          technique: IntensityTechnique.none,
        ),
      ],
    );

    SharedPreferences.setMockInitialValues({
      'schedules': jsonEncode([schedule.toJson()]),
      'history': '[]',
    });

    await tester.pumpWidget(const MaterialApp(home: HomePage()));
    await tester.pumpAndSettle();

    expect(find.text('Push'), findsOneWidget);

    await tester.drag(find.text('Push'), const Offset(-500, 0));
    await tester.pumpAndSettle();

    expect(find.text('Push'), findsNothing);
    expect(find.text('Scheda eliminata.'), findsOneWidget);

    await tester.tap(find.text('ANNULLA'));
    await tester.pumpAndSettle();

    expect(find.text('Push'), findsOneWidget);

    final prefs = await SharedPreferences.getInstance();
    final storedSchedules =
        jsonDecode(prefs.getString('schedules')!) as List<dynamic>;
    expect(storedSchedules.single['id'], 'schedule_1');
  });

  testWidgets('history deletion can be undone', (tester) async {
    final session = WorkoutSession(
      id: 'session_1',
      scheduleTitle: 'Pull',
      startTime: DateTime(2026, 4, 1, 10),
      endTime: DateTime(2026, 4, 1, 11),
      exercises: [
        WorkoutExercise(
          id: 'workout_exercise_1',
          name: 'Rematore',

          sets: [
            ExerciseSet(id: 'set_1', weight: 60, reps: 10, isCompleted: true),
          ],
          notes: '',
          technique: IntensityTechnique.none,
        ),
      ],
    );

    SharedPreferences.setMockInitialValues({
      'schedules': '[]',
      'history': jsonEncode([session.toJson()]),
    });

    await tester.pumpWidget(const MaterialApp(home: HomePage()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cronologia'));
    await tester.pumpAndSettle();

    expect(find.text('Pull'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.delete));
    await tester.pumpAndSettle();

    expect(find.text('Pull'), findsNothing);
    expect(find.text('Allenamento eliminato.'), findsOneWidget);

    await tester.tap(find.text('ANNULLA'));
    await tester.pumpAndSettle();

    expect(find.text('Pull'), findsOneWidget);

    final prefs = await SharedPreferences.getInstance();
    final storedHistory =
        jsonDecode(prefs.getString('history')!) as List<dynamic>;
    expect(storedHistory.single['id'], 'session_1');
  });

  test('legacy json gets generated ids and keeps them after serialization', () {
    final schedule = Schedule.fromJson(<String, dynamic>{
      'title': 'Legacy',
      'week': 1,
      'createdAt': DateTime(2026).toIso8601String(),
      'exercises': [
        <String, dynamic>{
          'name': 'Squat',
          'reps': 5,
          'set': 5,
          'notes': '',
          'weight': 100,
        },
      ],
    });

    final restored = Schedule.fromJson(schedule.toJson());

    expect(schedule.id, isNotEmpty);
    expect(schedule.exercises.single.id, isNotEmpty);
    expect(schedule.exercises.single.muscleGroup, MuscleGroup.unassigned);
    expect(restored.id, schedule.id);
    expect(restored.exercises.single.id, schedule.exercises.single.id);
  });

  test('muscle group survives exercise serialization', () {
    final exercise = Exercise.fromJson(<String, dynamic>{
      'name': 'Panca piana',
      'reps': 8,
      'set': 4,
      'notes': '',
      'weight': 90,
      'muscleGroup': 'Petto',
      'technique': 'none',
    });

    final restored = Exercise.fromJson(exercise.toJson());

    expect(exercise.muscleGroup, MuscleGroup.chest);
    expect(restored.muscleGroup, MuscleGroup.chest);
    expect(restored.toJson()['muscleGroup'], 'chest');
  });

  test('schedule week advances automatically each Monday', () {
    final schedule = Schedule(
      title: 'Push',
      week: 1,
      createdAt: DateTime(2026, 5, 18),
      exercises: [],
    );

    expect(schedule.currentWeek(now: DateTime(2026, 5, 18)), 1);
    expect(schedule.currentWeek(now: DateTime(2026, 5, 24)), 1);
    expect(schedule.currentWeek(now: DateTime(2026, 5, 25)), 2);
  });

  test('workout exercise keeps muscle group and previous weights', () {
    final exercise = WorkoutExercise(
      name: 'Rematore',
      notes: '',
      muscleGroup: MuscleGroup.back,
      technique: IntensityTechnique.none,
      sets: [ExerciseSet(weight: 70, reps: 10, isCompleted: true)],
      previousWeights: [65, 67.5],
    );

    final restored = WorkoutExercise.fromJson(exercise.toJson());

    expect(restored.muscleGroup, MuscleGroup.back);
    expect(restored.previousWeights, [65, 67.5]);
  });

  test('set metadata survives serialization', () {
    final set = ExerciseSet(
      weight: 100,
      reps: 5,
      isCompleted: true,
      isWarmup: true,
      rpe: 7.5,
      rir: 2,
      notes: 'Tecnica pulita',
    );

    final restored = ExerciseSet.fromJson(set.toJson());

    expect(restored.isWarmup, isTrue);
    expect(restored.rpe, 7.5);
    expect(restored.rir, 2);
    expect(restored.notes, 'Tecnica pulita');
  });

  test('number parser accepts comma decimals', () {
    expect(parseDecimalInput('72,5'), 72.5);
    expect(parseDecimalInput('72.5'), 72.5);
    expect(parseDecimalInput(''), isNull);
  });
}
