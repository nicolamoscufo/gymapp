import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gymapp/models/exercise.dart';
import 'package:gymapp/models/workout.dart';
import 'package:gymapp/screens/stats.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('stats screen shows monthly annual and consistency insights', (
    tester,
  ) async {
    final history = [
      _session(
        title: 'Push',
        start: DateTime(2026, 5, 20, 10),
        minutes: 70,
        exercises: [
          _exercise(
            name: 'Panca',
            group: MuscleGroup.chest,
            sets: [
              _set(weight: 100, reps: 5, rpe: 8),
              _set(weight: 80, reps: 8),
            ],
          ),
        ],
      ),
      _session(
        title: 'Pull',
        start: DateTime(2026, 5, 27, 10),
        minutes: 55,
        exercises: [
          _exercise(
            name: 'Rematore',
            group: MuscleGroup.back,
            sets: [_set(weight: 70, reps: 10, rpe: 7)],
          ),
        ],
      ),
      _session(
        title: 'Legs',
        start: DateTime(2026, 4, 12, 10),
        minutes: 80,
        exercises: [
          _exercise(
            name: 'Squat',
            group: MuscleGroup.quadriceps,
            sets: [_set(weight: 120, reps: 5)],
          ),
        ],
      ),
      _session(
        title: 'Old Push',
        start: DateTime(2025, 12, 10, 10),
        minutes: 60,
        exercises: [
          _exercise(
            name: 'Panca',
            group: MuscleGroup.chest,
            sets: [_set(weight: 90, reps: 6)],
          ),
        ],
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatsScreen(history: history, now: DateTime(2026, 5, 29)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Trend mensile'), findsOneWidget);
    expect(find.text('Trend annuale'), findsOneWidget);
    expect(find.text('Consistenza'), findsOneWidget);
    expect(find.text('Distribuzione muscolare - mese'), findsOneWidget);
    expect(find.text('Allenamenti ultimi 30 giorni'), findsOneWidget);
    expect(find.text('Mese migliore'), findsOneWidget);
    expect(find.text('Esercizi migliori'), findsOneWidget);
    expect(find.text('Questo mese'), findsOneWidget);
    expect(find.byType(BarChart), findsNWidgets(3));
    expect(find.byType(PieChart), findsOneWidget);
  });

  testWidgets('stats screen handles empty history', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: StatsScreen(history: [])),
      ),
    );

    expect(
      find.text('Nessun dato per mostrare le statistiche.'),
      findsOneWidget,
    );
  });
}

WorkoutSession _session({
  required String title,
  required DateTime start,
  required int minutes,
  required List<WorkoutExercise> exercises,
}) {
  return WorkoutSession(
    scheduleTitle: title,
    startTime: start,
    endTime: start.add(Duration(minutes: minutes)),
    exercises: exercises,
  );
}

WorkoutExercise _exercise({
  required String name,
  required MuscleGroup group,
  required List<ExerciseSet> sets,
}) {
  return WorkoutExercise(
    name: name,
    notes: '',
    muscleGroup: group,
    technique: IntensityTechnique.none,
    sets: sets,
  );
}

ExerciseSet _set({required double weight, required int reps, double? rpe}) {
  return ExerciseSet(weight: weight, reps: reps, rpe: rpe, isCompleted: true);
}
