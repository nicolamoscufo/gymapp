import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gymapp/ai_coach/training_context_builder.dart';
import 'package:gymapp/models/body_log.dart';
import 'package:gymapp/models/exercise.dart';
import 'package:gymapp/models/workout.dart';
import 'package:gymapp/screens/active_workout.dart';

WorkoutExercise _bench({
  double weight = 100,
  int reps = 8,
  int rir = 0,
  bool completed = true,
}) {
  return WorkoutExercise(
    name: 'Panca',
    notes: '',
    muscleGroup: MuscleGroup.chest,
    targetMinReps: 6,
    targetMaxReps: 8,
    progressionKgStep: 2.5,
    progressionRepStep: 1,
    progressionScheme: ProgressionScheme.doubleProgression,
    technique: IntensityTechnique.none,
    sets: [
      ExerciseSet(
        weight: weight,
        reps: reps,
        isCompleted: completed,
        rir: rir,
        rpe: rir == 0 ? 10 : 10 - rir,
      ),
    ],
  );
}

WorkoutSession _session({
  required String id,
  required DateTime end,
  required WorkoutExercise exercise,
}) {
  return WorkoutSession(
    id: id,
    scheduleTitle: 'Upper',
    startTime: end.subtract(const Duration(hours: 1)),
    endTime: end,
    exercises: [exercise],
  );
}

void main() {
  testWidgets('active workout exposes fatigue readiness details', (tester) async {
    final now = DateTime.now();
    final previous = _session(
      id: 'previous',
      end: now.subtract(const Duration(hours: 18)),
      exercise: _bench(),
    );
    final currentExercise = _bench(completed: false);
    final current = _session(
      id: 'current',
      end: now,
      exercise: currentExercise,
    );
    final bodyLogs = [
      BodyLog(
        date: now.subtract(const Duration(hours: 2)),
        readiness: 2,
        sleepHours: 4,
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: ActiveWorkoutScreen.resume(
          resumedSession: current,
          history: [previous],
          bodyLogs: bodyLogs,
          defaultRestSeconds: 90,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final readinessChip = find.byKey(ValueKey('readiness-${currentExercise.id}'));
    expect(readinessChip, findsOneWidget);
    expect(find.textContaining('Readiness'), findsWidgets);

    await tester.tap(readinessChip);
    await tester.pumpAndSettle();

    expect(find.text('Fatigue & Readiness'), findsOneWidget);
    expect(find.textContaining('/100'), findsWidgets);
    expect(find.text('Adatta questa sessione'), findsOneWidget);
  });

  test('AI context includes deterministic fatigue and per-exercise readiness', () {
    final now = DateTime(2026, 8, 25, 18);
    final previous = _session(
      id: 'previous',
      end: now.subtract(const Duration(days: 3)),
      exercise: _bench(weight: 97.5, reps: 8, rir: 2),
    );
    final latest = _session(
      id: 'latest',
      end: now.subtract(const Duration(hours: 2)),
      exercise: _bench(weight: 100, reps: 8, rir: 1),
    );
    final bodyLogs = [
      BodyLog(
        date: now.subtract(const Duration(hours: 3)),
        readiness: 5,
        sleepHours: 6,
      ),
    ];

    final context = TrainingContextBuilder(now: now).recent(
      history: [previous, latest],
      schedules: const [],
      bodyLogs: bodyLogs,
    );
    final analytics = context['deterministic_analytics'] as Map<String, dynamic>;
    final readiness = analytics['fatigue_readiness'] as Map<String, dynamic>;
    final recommendations =
        analytics['progression_recommendations'] as List<dynamic>;
    final first = recommendations.first as Map<String, dynamic>;

    expect(readiness['score'], isA<int>());
    expect(readiness['status'], isA<String>());
    expect(readiness['adaptation'], isA<String>());
    expect(first['readiness'], isA<Map<String, dynamic>>());
  });
}
