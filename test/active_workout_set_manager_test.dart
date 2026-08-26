import 'package:flutter_test/flutter_test.dart';
import 'package:gymapp/active_workout_set_manager.dart';
import 'package:gymapp/models/exercise.dart';
import 'package:gymapp/models/workout.dart';

WorkoutExercise _exercise(
  String name, {
  String? id,
  IntensityTechnique technique = IntensityTechnique.none,
  double backoffReductionPercent = 15,
  List<ExerciseSet>? sets,
}) {
  return WorkoutExercise(
    id: id,
    name: name,
    notes: '',
    technique: technique,
    backoffReductionPercent: backoffReductionPercent,
    sets: sets ?? [],
  );
}

WorkoutSession _session(List<WorkoutExercise> exercises) {
  return WorkoutSession(
    scheduleTitle: 'Sessione',
    startTime: DateTime(2026, 8, 26, 10),
    endTime: DateTime(2026, 8, 26, 11),
    exercises: exercises,
  );
}

void main() {
  test('add set reuses last target but creates fresh runtime metadata', () {
    final source = ExerciseSet(
      weight: 80,
      reps: 8,
      isCompleted: true,
      type: SetType.failure,
      rpe: 10,
      rir: 0,
      notes: 'old',
    );
    final exercise = _exercise('Bench', sets: [source]);
    final manager = ActiveWorkoutSetManager(session: _session([exercise]));

    final added = manager.addSet(exercise);

    expect(exercise.sets, hasLength(2));
    expect(added.weight, 80);
    expect(added.reps, 8);
    expect(added.type, SetType.normal);
    expect(added.isCompleted, isFalse);
    expect(added.rpe, isNull);
    expect(added.rir, isNull);
    expect(added.notes, isEmpty);
  });

  test('add warmup set marks only the new set as warmup', () {
    final exercise = _exercise(
      'Bench',
      sets: [ExerciseSet(weight: 60, reps: 8)],
    );
    final manager = ActiveWorkoutSetManager(session: _session([exercise]));

    final added = manager.addSet(exercise, isWarmup: true);

    expect(added.isWarmup, isTrue);
    expect(exercise.sets.first.isWarmup, isFalse);
  });

  test('copy set preserves details but resets completion and identity', () {
    final source = ExerciseSet(
      weight: 70,
      reps: 10,
      isCompleted: true,
      type: SetType.drop,
      rpe: 9,
      rir: 1,
      notes: 'controlled',
    );
    final exercise = _exercise('Row', sets: [source]);
    final manager = ActiveWorkoutSetManager(session: _session([exercise]));

    final copy = manager.copySet(exercise, 0);

    expect(copy, isNotNull);
    expect(copy!.id, isNot(source.id));
    expect(copy.weight, 70);
    expect(copy.reps, 10);
    expect(copy.type, SetType.drop);
    expect(copy.rpe, 9);
    expect(copy.rir, 1);
    expect(copy.notes, 'controlled');
    expect(copy.isCompleted, isFalse);
    expect(manager.copySet(exercise, -1), isNull);
  });

  test('validation reports invalid kg reps rpe and rir with set labels', () {
    final exercise = _exercise(
      'Bench',
      sets: [
        ExerciseSet(weight: -1, reps: 0, rpe: 11, rir: 12),
        ExerciseSet(weight: 1001, reps: 201),
      ],
    );
    final manager = ActiveWorkoutSetManager(session: _session([exercise]));

    final problems = manager.validationProblems();

    expect(problems, hasLength(6));
    expect(problems, contains('Bench set 1: kg fuori range 0-1000.'));
    expect(problems, contains('Bench set 1: reps fuori range 1-200.'));
    expect(problems, contains('Bench set 1: RPE fuori range 1-10.'));
    expect(problems, contains('Bench set 1: RIR fuori range 0-10.'));
    expect(problems, contains('Bench set 2: kg fuori range 0-1000.'));
    expect(problems, contains('Bench set 2: reps fuori range 1-200.'));
  });

  test('adaptive warmup uses first work set and ignores existing warmups', () {
    final exercise = _exercise(
      'Squat',
      sets: [
        ExerciseSet(weight: 20, reps: 10, isWarmup: true),
        ExerciseSet(weight: 100, reps: 5),
      ],
    );
    final manager = ActiveWorkoutSetManager(session: _session([exercise]));

    final warmups = manager.warmupSetsFor(exercise);

    expect(warmups, hasLength(4));
    expect(warmups.every((set) => set.isWarmup), isTrue);
    expect(warmups.map((set) => set.weight).toList(), [40, 60, 75, 87.5]);
  });

  test(
    'insert warmup replaces incomplete warmups but keeps completed ones',
    () {
      final completedWarmup = ExerciseSet(
        weight: 20,
        reps: 8,
        isWarmup: true,
        isCompleted: true,
      );
      final staleWarmup = ExerciseSet(weight: 30, reps: 5, isWarmup: true);
      final work = ExerciseSet(weight: 60, reps: 8);
      final exercise = _exercise(
        'Bench',
        sets: [completedWarmup, staleWarmup, work],
      );
      final manager = ActiveWorkoutSetManager(session: _session([exercise]));

      final inserted = manager.insertWarmupPlan(exercise);

      expect(inserted, isNotEmpty);
      expect(exercise.sets.contains(completedWarmup), isTrue);
      expect(exercise.sets.contains(staleWarmup), isFalse);
      expect(exercise.sets.contains(work), isTrue);
      expect(exercise.sets.take(inserted.length).toList(), inserted);
    },
  );

  test('toggle set completion reports direction of the interaction', () {
    final set = ExerciseSet(weight: 50, reps: 10);
    final manager = ActiveWorkoutSetManager(session: _session([]));

    expect(manager.toggleSetCompleted(set), isTrue);
    expect(set.isCompleted, isTrue);
    expect(manager.toggleSetCompleted(set), isFalse);
    expect(set.isCompleted, isFalse);
  });

  test('remove and restore set preserve original object and bounded index', () {
    final first = ExerciseSet(weight: 50, reps: 10);
    final removedSet = ExerciseSet(weight: 60, reps: 8);
    final exercise = _exercise('Bench', sets: [first, removedSet]);
    final manager = ActiveWorkoutSetManager(session: _session([exercise]));

    final removal = manager.removeSet(exercise, 1);

    expect(removal, isNotNull);
    expect(exercise.sets, [first]);
    expect(manager.restoreRemovedSet(exercise, removal!), isTrue);
    expect(exercise.sets, [first, removedSet]);
    expect(manager.restoreRemovedSet(exercise, removal), isFalse);
  });

  test('top set backoff recommendation can be applied to a backoff set', () {
    final top = ExerciseSet(weight: 100, reps: 5);
    final backoff = ExerciseSet(weight: 100, reps: 8);
    final exercise = _exercise(
      'Bench',
      technique: IntensityTechnique.topsetBackoff,
      backoffReductionPercent: 15,
      sets: [top, backoff],
    );
    final manager = ActiveWorkoutSetManager(session: _session([exercise]));

    expect(manager.backoffReductionFor(exercise, 1), 15);
    expect(manager.recommendedBackoffWeightFor(exercise, 1), 85);
    expect(manager.applyRecommendedBackoffWeight(exercise, 1), isTrue);
    expect(backoff.weight, 85);
    expect(manager.applyRecommendedBackoffWeight(exercise, 0), isFalse);
  });

  test('workout stats count all sets but volume only completed work sets', () {
    final exerciseA = _exercise(
      'Bench',
      sets: [
        ExerciseSet(weight: 20, reps: 10, isWarmup: true, isCompleted: true),
        ExerciseSet(weight: 80, reps: 10, isCompleted: true),
        ExerciseSet(weight: 80, reps: 8),
      ],
    );
    final exerciseB = _exercise(
      'Row',
      sets: [ExerciseSet(weight: 60, reps: 10, isCompleted: true)],
    );
    final manager = ActiveWorkoutSetManager(
      session: _session([exerciseA, exerciseB]),
    );

    final stats = manager.workoutStats;

    expect(stats.completedSets, 3);
    expect(stats.totalSets, 4);
    expect(stats.volume, 1400);
    expect(stats.exercises, 2);
  });
}
