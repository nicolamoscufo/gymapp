import 'package:flutter_test/flutter_test.dart';
import 'package:gymapp/models/exercise.dart';
import 'package:gymapp/models/workout.dart';
import 'package:gymapp/workout_progression_analytics.dart';

WorkoutExercise exercise({
  required List<ExerciseSet> sets,
  ProgressionScheme scheme = ProgressionScheme.doubleProgression,
  int? minReps = 6,
  int? maxReps = 8,
}) {
  return WorkoutExercise(
    name: 'Panca',
    notes: '',
    targetMinReps: minReps,
    targetMaxReps: maxReps,
    technique: IntensityTechnique.none,
    progressionKgStep: 2.5,
    progressionRepStep: 1,
    progressionScheme: scheme,
    sets: sets,
  );
}

WorkoutSession session(
  String id,
  DateTime date,
  WorkoutExercise workoutExercise,
) {
  return WorkoutSession(
    id: id,
    scheduleTitle: 'Upper',
    startTime: date.subtract(const Duration(hours: 1)),
    endTime: date,
    exercises: [workoutExercise],
  );
}

ExerciseSet completed(double weight, int reps, {int? rir, double? rpe}) {
  return ExerciseSet(
    weight: weight,
    reps: reps,
    isCompleted: true,
    rir: rir,
    rpe: rpe,
  );
}

void main() {
  test('double progression increases load at top of range with reserve', () {
    final previous = session(
      'previous',
      DateTime(2026, 8, 18),
      exercise(
        sets: [completed(97.5, 8), completed(97.5, 8), completed(97.5, 8)],
      ),
    );
    final current = exercise(
      sets: [
        completed(100, 8, rir: 2),
        completed(100, 8, rir: 2),
        completed(100, 8, rir: 2),
      ],
    );

    final decision = buildProgressionDecision(
      exercise: current,
      history: [previous],
    );

    expect(decision.action, ProgressionAction.increaseLoad);
    expect(decision.suggestedWeightDelta, 2.5);
    expect(decision.confidence, ProgressionConfidence.high);
  });

  test('double progression increases reps before load', () {
    final current = exercise(
      sets: [
        completed(100, 7, rir: 2),
        completed(100, 7, rir: 2),
        completed(100, 7, rir: 2),
      ],
    );

    final decision = buildProgressionDecision(
      exercise: current,
      history: const [],
    );

    expect(decision.action, ProgressionAction.increaseReps);
    expect(decision.suggestedRepDelta, 1);
  });

  test('below target or near-failure effort keeps load stable', () {
    final current = exercise(
      sets: [
        completed(100, 5, rir: 0),
        completed(100, 6, rir: 1),
        completed(100, 6, rir: 1),
      ],
    );

    final decision = buildProgressionDecision(
      exercise: current,
      history: const [],
    );

    expect(decision.action, ProgressionAction.maintain);
    expect(decision.anyBelowMin, isTrue);
  });

  test('repeated performance decline with high effort triggers deload', () {
    final older = session(
      'older',
      DateTime(2026, 8, 1),
      exercise(sets: [completed(100, 8)]),
    );
    final previous = session(
      'previous',
      DateTime(2026, 8, 8),
      exercise(sets: [completed(95, 8)]),
    );
    final current = exercise(
      minReps: 6,
      maxReps: 8,
      sets: [completed(90, 8, rir: 0)],
    );

    final decision = buildProgressionDecision(
      exercise: current,
      history: [older, previous],
    );

    expect(decision.action, ProgressionAction.deload);
    expect(decision.suggestedWeightMultiplier, 0.90);
    expect(decision.estimatedOneRepMaxChangePercent, lessThan(-3));
  });

  test('manual progression remains untouched', () {
    final current = exercise(
      scheme: ProgressionScheme.manual,
      sets: [completed(100, 8, rir: 3)],
    );

    final decision = buildProgressionDecision(
      exercise: current,
      history: const [],
    );

    expect(decision.action, ProgressionAction.manual);
  });
}
