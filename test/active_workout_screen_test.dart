import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gymapp/models/exercise.dart';
import 'package:gymapp/models/schedule.dart';
import 'package:gymapp/models/workout.dart';
import 'package:gymapp/screens/active_workout.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('active workout shows and saves exercise notes', (tester) async {
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
          set: 1,
          notes: 'Gomiti stretti',
          weight: 80,
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

    final noteField = find.widgetWithText(TextFormField, 'Note esercizio');
    expect(noteField, findsOneWidget);
    expect(
      tester.widget<TextFormField>(noteField).initialValue,
      'Gomiti stretti',
    );

    await tester.enterText(
      find.descendant(of: noteField, matching: find.byType(EditableText)),
      'Spalle basse',
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(TextButton, 'Fine'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ElevatedButton, 'Salva'));
    await tester.pumpAndSettle();

    final prefs = await SharedPreferences.getInstance();
    final storedHistory = jsonDecode(prefs.getString('history')!) as List;
    final storedExercise =
        ((storedHistory.single as Map<String, dynamic>)['exercises'] as List)
                .single
            as Map<String, dynamic>;
    expect(storedExercise['notes'], 'Spalle basse');
  });

  testWidgets('completed session edit can add exercise sets', (tester) async {
    final session = WorkoutSession(
      id: 'session_1',
      scheduleTitle: 'Push',
      startTime: DateTime(2026, 5, 1, 10),
      endTime: DateTime(2026, 5, 1, 11),
      exercises: [
        WorkoutExercise(
          id: 'workout_exercise_1',
          name: 'Panca',
          notes: '',
          technique: IntensityTechnique.none,
          sets: [
            ExerciseSet(id: 'set_1', weight: 80, reps: 8, isCompleted: true),
          ],
        ),
      ],
    );
    SharedPreferences.setMockInitialValues({
      'history': jsonEncode([session.toJson()]),
    });

    await tester.pumpWidget(
      MaterialApp(
        home: ActiveWorkoutScreen.editCompleted(
          session: session,
          history: [session],
          defaultRestSeconds: 90,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final addSetButton = find.widgetWithText(TextButton, 'serie');
    await tester.ensureVisible(addSetButton);
    await tester.pumpAndSettle();
    await tester.tap(addSetButton);
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(TextButton, 'Salva'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ElevatedButton, 'Salva modifiche'));
    await tester.pumpAndSettle();

    final prefs = await SharedPreferences.getInstance();
    final storedHistory = jsonDecode(prefs.getString('history')!) as List;
    final storedExercise =
        ((storedHistory.single as Map<String, dynamic>)['exercises'] as List)
                .single
            as Map<String, dynamic>;
    expect((storedExercise['sets'] as List).length, 2);
  });
  testWidgets('drop set skips automatic rest until the drop chain ends', (
    tester,
  ) async {
    final session = WorkoutSession(
      id: 'drop_session',
      scheduleTitle: 'Drop workout',
      startTime: DateTime(2026, 8, 26, 10),
      endTime: DateTime(2026, 8, 26, 10),
      exercises: [
        WorkoutExercise(
          id: 'drop_exercise',
          name: 'Alzate laterali',
          notes: '',
          technique: IntensityTechnique.none,
          restSeconds: 90,
          sets: [
            ExerciseSet(id: 'normal_set', weight: 12, reps: 12),
            ExerciseSet(
              id: 'drop_set',
              weight: 9,
              reps: 10,
              type: SetType.drop,
            ),
          ],
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ActiveWorkoutScreen.resume(
          resumedSession: session,
          history: const [],
          defaultRestSeconds: 90,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final normalComplete = find.byKey(const ValueKey('complete-normal_set'));
    await tester.ensureVisible(normalComplete);
    await tester.tap(normalComplete);
    await tester.pump();

    expect(find.text('Prossimo: drop set, senza recupero.'), findsOneWidget);
    expect(find.byKey(const ValueKey('rest-mode-drop_exercise')), findsNothing);

    final dropComplete = find.byKey(const ValueKey('complete-drop_set'));
    await tester.ensureVisible(dropComplete);
    await tester.tap(dropComplete);
    await tester.pump();

    expect(
      find.byKey(const ValueKey('rest-mode-drop_exercise')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('rest-workout-complete')), findsOneWidget);
  });
  testWidgets(
    'live PR banner celebrates structured records without duplicate volume snackbar',
    (tester) async {
      final historicalExercise = WorkoutExercise(
        id: 'historical_bench',
        name: 'Panca',
        notes: '',
        technique: IntensityTechnique.none,
        sets: [
          ExerciseSet(
            id: 'historical_set',
            weight: 80,
            reps: 5,
            isCompleted: true,
          ),
        ],
      );
      final historical = WorkoutSession(
        id: 'historical_session',
        scheduleTitle: 'Push',
        startTime: DateTime(2026, 8, 20, 10),
        endTime: DateTime(2026, 8, 20, 11),
        exercises: [historicalExercise],
      );
      final current = WorkoutSession(
        id: 'current_session',
        scheduleTitle: 'Push',
        startTime: DateTime(2026, 8, 26, 10),
        endTime: DateTime(2026, 8, 26, 10),
        exercises: [
          WorkoutExercise(
            id: 'current_bench',
            name: 'Panca',
            notes: '',
            technique: IntensityTechnique.none,
            restSeconds: 90,
            sets: [ExerciseSet(id: 'current_pr_set', weight: 82.5, reps: 6)],
          ),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: ActiveWorkoutScreen.resume(
            resumedSession: current,
            history: [historical],
            defaultRestSeconds: 90,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final complete = find.byKey(const ValueKey('complete-current_pr_set'));
      await tester.ensureVisible(complete);
      await tester.tap(complete);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byKey(const ValueKey('live-pr-banner')), findsOneWidget);
      expect(find.text('5 nuovi record personali!'), findsOneWidget);
      expect(find.text('Panca'), findsWidgets);
      expect(find.byKey(const ValueKey('live-pr-weight')), findsOneWidget);
      expect(find.byKey(const ValueKey('live-pr-reps')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('live-pr-estimatedOneRepMax')),
        findsOneWidget,
      );
      expect(find.textContaining('volume set migliorato'), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );
}
