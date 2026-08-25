import 'package:flutter_test/flutter_test.dart';
import 'package:gymapp/active_workout_session_builder.dart';
import 'package:gymapp/models/exercise.dart';
import 'package:gymapp/models/schedule.dart';
import 'package:gymapp/models/workout.dart';

Exercise _exercise({
  String? id,
  String name = 'Panca',
  double weight = 80,
  int reps = 8,
  int sets = 3,
  int? minReps = 8,
  int? maxReps = 10,
  IntensityTechnique technique = IntensityTechnique.none,
  int? backoffReps,
  ProgressionScheme progressionScheme = ProgressionScheme.doubleProgression,
}) {
  return Exercise(
    id: id,
    name: name,
    reps: reps,
    set: sets,
    notes: '',
    weight: weight,
    targetMinReps: minReps,
    targetMaxReps: maxReps,
    technique: technique,
    backoffReps: backoffReps,
    progressionScheme: progressionScheme,
  );
}

WorkoutExercise _performedExercise({
  String? sourceExerciseId,
  String name = 'Panca',
  List<ExerciseSet>? sets,
  ProgressionScheme progressionScheme = ProgressionScheme.doubleProgression,
}) {
  return WorkoutExercise(
    sourceExerciseId: sourceExerciseId,
    name: name,
    notes: '',
    technique: IntensityTechnique.none,
    targetMinReps: 8,
    targetMaxReps: 10,
    progressionScheme: progressionScheme,
    sets: sets ??
        [
          ExerciseSet(weight: 80, reps: 8, isCompleted: true),
          ExerciseSet(weight: 80, reps: 8, isCompleted: true),
        ],
  );
}

WorkoutSession _session({
  String? scheduleId,
  String title = 'Push',
  required DateTime endTime,
  required List<WorkoutExercise> exercises,
}) {
  return WorkoutSession(
    scheduleId: scheduleId,
    scheduleTitle: title,
    startTime: endTime.subtract(const Duration(hours: 1)),
    endTime: endTime,
    exercises: exercises,
  );
}

void main() {
  test('latest session prefers stable schedule id and supports legacy title', () {
    final now = DateTime(2026, 8, 26, 12);
    final schedule = Schedule(
      id: 'schedule-push',
      title: 'Push renamed',
      week: 1,
      createdAt: now,
      exercises: [],
    );
    final legacy = _session(
      title: 'Push renamed',
      endTime: now.subtract(const Duration(days: 3)),
      exercises: [],
    );
    final exactId = _session(
      scheduleId: 'schedule-push',
      title: 'Old Push title',
      endTime: now.subtract(const Duration(days: 1)),
      exercises: [],
    );
    final other = _session(
      scheduleId: 'other',
      title: 'Push renamed',
      endTime: now,
      exercises: [],
    );

    final builder = ActiveWorkoutSessionBuilder(
      history: [legacy, exactId, other],
      bodyLogs: const [],
      now: () => now,
    );

    expect(builder.latestSessionForSchedule(schedule), same(exactId));
  });

  test('previous values use stable exercise id and completed sets only', () {
    final template = _exercise(id: 'bench-template', name: 'Panca nuova');
    final previous = _performedExercise(
      sourceExerciseId: 'bench-template',
      name: 'Vecchia panca',
      sets: [
        ExerciseSet(weight: 80, reps: 8, isCompleted: true),
        ExerciseSet(weight: 82.5, reps: 7, isCompleted: false),
        ExerciseSet(weight: 80, reps: 9, isCompleted: true),
      ],
    );
    final previousSession = _session(
      scheduleId: 'push',
      endTime: DateTime(2026, 8, 20),
      exercises: [previous],
    );
    final builder = ActiveWorkoutSessionBuilder(
      history: [previousSession],
      bodyLogs: const [],
    );

    final resolved = builder.previousExerciseFor(template, previousSession);
    expect(resolved, same(previous));
    expect(builder.previousWeightsFor(resolved), [80, 80]);
    expect(builder.previousRepsFor(resolved), [8, 9]);
  });

  test('manual progression carries previous load and reps into next session', () {
    final now = DateTime(2026, 8, 26, 12);
    final template = _exercise(
      id: 'bench',
      weight: 100,
      reps: 10,
      sets: 2,
      progressionScheme: ProgressionScheme.manual,
    );
    final previous = _performedExercise(
      sourceExerciseId: 'bench',
      progressionScheme: ProgressionScheme.manual,
      sets: [
        ExerciseSet(weight: 87.5, reps: 7, isCompleted: true),
        ExerciseSet(weight: 85, reps: 8, isCompleted: true),
      ],
    );
    final historySession = _session(
      scheduleId: 'push',
      endTime: now.subtract(const Duration(days: 7)),
      exercises: [previous],
    );
    final schedule = Schedule(
      id: 'push',
      title: 'Push',
      week: 1,
      createdAt: now,
      exercises: [template],
    );
    final builder = ActiveWorkoutSessionBuilder(
      history: [historySession],
      bodyLogs: const [],
      now: () => now,
    );

    final built = builder.buildFromSchedule(schedule).exercises.single;

    expect(built.previousWeights, [87.5, 85]);
    expect(built.previousReps, [7, 8]);
    expect(built.sets.map((set) => set.weight), [87.5, 85]);
    expect(built.sets.map((set) => set.reps), [7, 8]);
  });

  test('top set and backoff are constructed from one progression source', () {
    final template = _exercise(
      weight: 100,
      reps: 5,
      sets: 2,
      minReps: 5,
      maxReps: 5,
      technique: IntensityTechnique.topsetBackoff,
      backoffReps: 8,
    )..backoffReductionPercent = 10;
    final builder = ActiveWorkoutSessionBuilder(
      history: const [],
      bodyLogs: const [],
    );

    final built = builder.workoutExerciseFromExercise(template, null);

    expect(built.sets, hasLength(2));
    expect(built.sets.first.weight, 100);
    expect(built.sets.first.reps, 5);
    expect(built.sets.last.weight, 90);
    expect(built.sets.last.reps, 8);
  });

  test('schedule deload week is applied while building the session', () {
    final now = DateTime(2026, 8, 26, 12);
    final schedule = Schedule(
      id: 'legs',
      title: 'Legs',
      week: 4,
      createdAt: now,
      exercises: [_exercise(name: 'Squat', weight: 100, reps: 5, minReps: 5, maxReps: 5)],
      deloadEveryWeeks: 4,
    );
    final builder = ActiveWorkoutSessionBuilder(
      history: const [],
      bodyLogs: const [],
      now: () => now,
    );

    final session = builder.buildFromSchedule(schedule);

    expect(session.scheduleId, schedule.id);
    expect(session.startTime, now);
    expect(session.endTime, now);
    expect(session.exercises.single.sets.first.weight, 90);
  });

  test('workout exercise converts back to a reusable schedule template', () {
    final workoutExercise = WorkoutExercise(
      name: 'Panca',
      notes: 'fermo al petto',
      technique: IntensityTechnique.topsetBackoff,
      backoffReductionPercent: 12.5,
      targetMinReps: 5,
      targetMaxReps: 8,
      restSeconds: 180,
      sets: [
        ExerciseSet(weight: 100, reps: 5, isCompleted: true),
        ExerciseSet(weight: 87.5, reps: 8, isCompleted: true),
      ],
    );
    final builder = ActiveWorkoutSessionBuilder(
      history: const [],
      bodyLogs: const [],
    );

    final template = builder.exerciseFromWorkoutExercise(workoutExercise);

    expect(template.name, 'Panca');
    expect(template.weight, 100);
    expect(template.reps, 5);
    expect(template.set, 2);
    expect(template.backoffReps, 8);
    expect(template.backoffReductionPercent, 12.5);
    expect(template.restSeconds, 180);
  });
}
