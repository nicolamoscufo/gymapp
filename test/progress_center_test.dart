import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gymapp/models/exercise.dart';
import 'package:gymapp/models/workout.dart';
import 'package:gymapp/screens/progress_center.dart';

void main() {
  testWidgets(
    'progress center exposes overview, exercise, muscle and PR views',
    (tester) async {
      final history = [
        _session(DateTime(2026, 8, 18, 18), 80, 8),
        _session(DateTime(2026, 8, 25, 18), 85, 8),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ProgressCenterScreen(
              history: history,
              now: DateTime(2026, 8, 25, 20),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Panoramica'), findsOneWidget);
      expect(find.text('Esercizi'), findsOneWidget);
      expect(find.text('Muscoli'), findsOneWidget);
      expect(find.text('Record'), findsOneWidget);
      expect(find.text('Trend mensile'), findsOneWidget);

      await tester.tap(find.text('Esercizi'));
      await tester.pumpAndSettle();
      expect(find.text('Progressione esercizi'), findsOneWidget);
      expect(find.text('Panca'), findsWidgets);
      expect(find.text('e1RM nel tempo'), findsOneWidget);
      expect(find.text('Volume per sessione'), findsOneWidget);

      await tester.tap(find.text('Muscoli'));
      await tester.pumpAndSettle();
      expect(find.text('Volume muscolare'), findsOneWidget);
      expect(find.text('Petto'), findsWidgets);
      expect(find.text('Set / settimana'), findsOneWidget);

      await tester.tap(find.text('Record'));
      await tester.pumpAndSettle();
      expect(find.text('PR Dashboard'), findsOneWidget);
      expect(find.text('Report mensile'), findsOneWidget);
      expect(find.text('Year in review'), findsOneWidget);

      final recordList = find.byType(ListView).last;
      for (
        var i = 0;
        i < 3 && find.text('Record recenti').evaluate().isEmpty;
        i++
      ) {
        await tester.drag(recordList, const Offset(0, -350));
        await tester.pumpAndSettle();
      }
      expect(find.text('Record recenti'), findsOneWidget);
    },
  );
}

WorkoutSession _session(DateTime start, double weight, int reps) {
  return WorkoutSession(
    scheduleTitle: 'Push',
    startTime: start,
    endTime: start.add(const Duration(minutes: 65)),
    exercises: [
      WorkoutExercise(
        name: 'Panca',
        notes: '',
        muscleGroup: MuscleGroup.chest,
        technique: IntensityTechnique.none,
        sets: [
          ExerciseSet(weight: weight, reps: reps, isCompleted: true),
          ExerciseSet(weight: weight, reps: reps, isCompleted: true),
        ],
      ),
    ],
  );
}
