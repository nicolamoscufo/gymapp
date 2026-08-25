import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gymapp/ai_coach/training_context_builder.dart';
import 'package:gymapp/models/exercise.dart';
import 'package:gymapp/models/workout.dart';
import 'package:gymapp/screens/active_workout.dart';

WorkoutExercise bench(double weight, int reps, {int? rir}) {
  return WorkoutExercise(
    name: 'Panca',
    notes: '',
    muscleGroup: MuscleGroup.chest,
    targetMinReps: 6,
    targetMaxReps: 8,
    technique: IntensityTechnique.none,
    progressionKgStep: 2.5,
    progressionRepStep: 1,
    progressionScheme: ProgressionScheme.doubleProgression,
    sets: [
      ExerciseSet(weight: weight, reps: reps, isCompleted: true, rir: rir),
      ExerciseSet(weight: weight, reps: reps, isCompleted: true, rir: rir),
      ExerciseSet(weight: weight, reps: reps, isCompleted: true, rir: rir),
    ],
  );
}

WorkoutSession workout(String id, DateTime date, WorkoutExercise exercise) {
  return WorkoutSession(
    id: id,
    scheduleTitle: 'Upper',
    startTime: date.subtract(const Duration(hours: 1)),
    endTime: date,
    exercises: [exercise],
  );
}

void main() {
  testWidgets('active workout exposes explainable progression decision', (
    tester,
  ) async {
    final previous = workout(
      'previous',
      DateTime(2026, 8, 20),
      bench(97.5, 8, rir: 2),
    );
    final currentExercise = bench(100, 8, rir: 2);
    final current = workout(
      'current',
      DateTime(2026, 8, 25),
      currentExercise,
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

    expect(find.textContaining('Aumenta carico +2.5 kg'), findsWidgets);

    await tester.tap(
      find.byKey(ValueKey('progression-intelligence-${currentExercise.id}')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Progressione consigliata'), findsOneWidget);
    expect(find.textContaining('Confidenza'), findsOneWidget);
    expect(find.textContaining('RIR'), findsWidgets);
  });

  test('AI context exposes deterministic progression recommendation', () {
    final previous = workout(
      'previous',
      DateTime(2026, 8, 20),
      bench(97.5, 8, rir: 2),
    );
    final current = workout(
      'current',
      DateTime(2026, 8, 25),
      bench(100, 8, rir: 2),
    );

    final context = TrainingContextBuilder(now: DateTime(2026, 8, 25)).recent(
      history: [previous, current],
      schedules: const [],
    );
    final analytics =
        context['deterministic_analytics'] as Map<String, dynamic>;
    final recommendations =
        analytics['progression_recommendations'] as List<dynamic>;
    final panca = recommendations.single as Map<String, dynamic>;

    expect(panca['exercise'], 'Panca');
    expect(panca['action'], 'increaseLoad');
    expect(panca['confidence'], 'high');
    expect(panca['suggested_weight_delta'], 2.5);
  });
}
