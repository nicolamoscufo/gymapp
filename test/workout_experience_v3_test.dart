import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gymapp/models/exercise.dart';
import 'package:gymapp/models/workout.dart';
import 'package:gymapp/screens/active_workout.dart';

WorkoutExercise _bench(double weight, int reps) {
  return WorkoutExercise(
    name: 'Panca',
    notes: '',
    muscleGroup: MuscleGroup.chest,
    technique: IntensityTechnique.none,
    sets: [
      ExerciseSet(weight: weight, reps: reps, isCompleted: true),
    ],
  );
}

WorkoutSession _session({
  required String id,
  required DateTime date,
  required WorkoutExercise exercise,
}) {
  return WorkoutSession(
    id: id,
    scheduleTitle: 'Upper',
    startTime: date.subtract(const Duration(hours: 1)),
    endTime: date,
    exercises: [exercise],
  );
}

void main() {
  testWidgets('active workout exposes exercise history and e1RM PR', (
    tester,
  ) async {
    final previous = _session(
      id: 'previous',
      date: DateTime(2026, 8, 20),
      exercise: _bench(100, 5),
    );
    final currentExercise = _bench(105, 5);
    final current = _session(
      id: 'current',
      date: DateTime(2026, 8, 25),
      exercise: currentExercise,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ActiveWorkoutScreen.editCompleted(
          session: current,
          history: [previous],
          defaultRestSeconds: 90,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('PR e1RM'), findsOneWidget);
    expect(find.textContaining('Best e1RM'), findsOneWidget);

    await tester.tap(
      find.byKey(ValueKey('exercise-history-${currentExercise.id}')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Storico Panca'), findsOneWidget);
    expect(find.textContaining('116.7 kg'), findsWidgets);
    expect(find.textContaining('100 kg × 5'), findsOneWidget);
  });
}
