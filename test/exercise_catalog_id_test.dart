import 'package:flutter_test/flutter_test.dart';
import 'package:gymapp/active_workout_session_builder.dart';
import 'package:gymapp/models/exercise.dart';
import 'package:gymapp/models/schedule.dart';
import 'package:gymapp/models/workout.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('catalogId roundtrips through Exercise JSON', () {
    final exercise = Exercise(
      id: 'bench-instance',
      catalogId: 'catalog-bench',
      name: 'barbell bench press',
      reps: 8,
      set: 3,
      notes: '',
      weight: 80,
      muscleGroup: MuscleGroup.chest,
      equipment: 'barbell',
      movementPattern: 'Spinta',
      technique: IntensityTechnique.none,
    );

    final restored = Exercise.fromJson(exercise.toJson());

    expect(restored.id, 'bench-instance');
    expect(restored.catalogId, 'catalog-bench');
  });

  test('legacy Exercise JSON without catalogId remains compatible', () {
    final restored = Exercise.fromJson({
      'id': 'legacy',
      'name': 'Panca',
      'reps': 8,
      'set': 3,
      'notes': '',
      'weight': 80.0,
      'muscleGroup': 'chest',
      'equipment': 'barbell',
      'movementPattern': 'Spinta',
      'technique': 'none',
    });

    expect(restored.catalogId, isNull);
    expect(restored.name, 'Panca');
  });

  test('WorkoutExercise preserves catalogId in historical JSON', () {
    final exercise = WorkoutExercise(
      id: 'workout-bench',
      sourceExerciseId: 'bench-instance',
      catalogId: 'catalog-bench',
      name: 'barbell bench press',
      notes: '',
      muscleGroup: MuscleGroup.chest,
      equipment: 'barbell',
      movementPattern: 'Spinta',
      technique: IntensityTechnique.none,
      sets: [ExerciseSet(weight: 80, reps: 8)],
    );

    final restored = WorkoutExercise.fromJson(exercise.toJson());

    expect(restored.sourceExerciseId, 'bench-instance');
    expect(restored.catalogId, 'catalog-bench');
  });

  test('active workout snapshot carries schedule exercise catalogId', () {
    final schedule = Schedule(
      id: 'push',
      title: 'Push',
      week: 1,
      createdAt: DateTime(2026, 8, 1),
      exercises: [
        Exercise(
          id: 'bench-instance',
          catalogId: 'catalog-bench',
          name: 'barbell bench press',
          reps: 8,
          set: 3,
          notes: '',
          weight: 80,
          muscleGroup: MuscleGroup.chest,
          equipment: 'barbell',
          movementPattern: 'Spinta',
          technique: IntensityTechnique.none,
        ),
      ],
    );
    final builder = ActiveWorkoutSessionBuilder(
      history: const [],
      bodyLogs: const [],
      now: () => DateTime(2026, 8, 26),
    );

    final session = builder.buildFromSchedule(schedule);

    expect(session.exercises.single.sourceExerciseId, 'bench-instance');
    expect(session.exercises.single.catalogId, 'catalog-bench');
  });
}
