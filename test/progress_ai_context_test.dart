import 'package:flutter_test/flutter_test.dart';
import 'package:gymapp/ai_coach/training_context_builder.dart';
import 'package:gymapp/models/exercise.dart';
import 'package:gymapp/models/workout.dart';

void main() {
  test('AI deterministic context exposes progress analytics', () {
    final start = DateTime(2026, 8, 25, 18);
    final history = [
      WorkoutSession(
        scheduleTitle: 'Push',
        startTime: start,
        endTime: start.add(const Duration(minutes: 60)),
        exercises: [
          WorkoutExercise(
            name: 'Panca',
            notes: '',
            muscleGroup: MuscleGroup.chest,
            technique: IntensityTechnique.none,
            sets: [
              ExerciseSet(weight: 85, reps: 8, isCompleted: true),
              ExerciseSet(weight: 85, reps: 8, isCompleted: true),
            ],
          ),
        ],
      ),
    ];

    final context = TrainingContextBuilder(now: DateTime(2026, 8, 25, 20)).recent(
      history: history,
      schedules: const [],
    );
    final deterministic = context['deterministic_analytics'] as Map<String, dynamic>;
    final progress = deterministic['progress_analytics'] as Map<String, dynamic>;

    expect(progress['exercises'], isNotEmpty);
    expect(progress['muscles'], isNotEmpty);
    expect(progress['personal_records'], isNotEmpty);
    expect(progress['consistency'], isA<Map<String, dynamic>>());
    expect(progress['current_month'], isA<Map<String, dynamic>>());
    expect(progress['current_year'], isA<Map<String, dynamic>>());
  });
}
