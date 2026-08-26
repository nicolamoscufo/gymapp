import 'package:flutter_test/flutter_test.dart';
import 'package:gymapp/active_workout_exercise_manager.dart';
import 'package:gymapp/active_workout_session_builder.dart';
import 'package:gymapp/models/exercise.dart';
import 'package:gymapp/models/workout.dart';

Exercise _template(
  String name, {
  String? id,
  double weight = 50,
  int reps = 8,
}) {
  return Exercise(
    id: id,
    name: name,
    reps: reps,
    set: 3,
    notes: '',
    weight: weight,
    targetMinReps: 8,
    targetMaxReps: 10,
    technique: IntensityTechnique.none,
    progressionScheme: ProgressionScheme.manual,
  );
}

WorkoutExercise _workoutExercise(
  String name, {
  String? id,
  String? sourceExerciseId,
  int? supersetGroup,
  double weight = 50,
  int reps = 8,
}) {
  return WorkoutExercise(
    id: id,
    sourceExerciseId: sourceExerciseId,
    name: name,
    notes: '',
    targetMinReps: 8,
    targetMaxReps: 10,
    technique: IntensityTechnique.none,
    supersetGroup: supersetGroup,
    progressionScheme: ProgressionScheme.manual,
    sets: [ExerciseSet(weight: weight, reps: reps)],
  );
}

WorkoutSession _session({
  String? id,
  String? scheduleId = 'schedule-a',
  String title = 'Push',
  DateTime? start,
  DateTime? end,
  List<WorkoutExercise>? exercises,
}) {
  final startTime = start ?? DateTime(2026, 8, 26, 10);
  return WorkoutSession(
    id: id,
    scheduleId: scheduleId,
    scheduleTitle: title,
    startTime: startTime,
    endTime: end ?? startTime.add(const Duration(hours: 1)),
    exercises: exercises ?? [],
  );
}

ActiveWorkoutExerciseManager _manager(
  WorkoutSession session, {
  List<WorkoutSession> history = const [],
}) {
  return ActiveWorkoutExerciseManager(
    session: session,
    sessionBuilder: ActiveWorkoutSessionBuilder(
      history: history,
      bodyLogs: const [],
      now: () => DateTime(2026, 8, 26, 12),
    ),
  );
}

void main() {
  test(
    'add exercises reuses previous values from the same stable schedule',
    () {
      final template = _template('Bench press', id: 'bench-template');
      final previousExercise = _workoutExercise(
        'Old bench label',
        sourceExerciseId: 'bench-template',
        weight: 82.5,
        reps: 9,
      );
      previousExercise.sets.first.isCompleted = true;
      final previous = _session(
        id: 'previous',
        scheduleId: 'schedule-a',
        title: 'Old push title',
        start: DateTime(2026, 8, 20, 10),
        end: DateTime(2026, 8, 20, 11),
        exercises: [previousExercise],
      );
      final current = _session(
        id: 'current',
        title: 'Renamed push',
        start: DateTime(2026, 8, 26, 10),
        end: DateTime(2026, 8, 26, 11),
      );

      final added = _manager(
        current,
        history: [previous],
      ).addExercises([template]);

      expect(added, hasLength(1));
      expect(current.exercises, hasLength(1));
      expect(added.single.sourceExerciseId, isNull);
      expect(added.single.previousWeights, [82.5]);
      expect(added.single.previousReps, [9]);
      expect(added.single.sets.first.weight, 82.5);
      expect(added.single.sets.first.reps, 9);
    },
  );

  test(
    'replace preserves superset membership and creates a live-only exercise',
    () {
      final original = _workoutExercise('Bench', supersetGroup: 3);
      final current = _session(exercises: [original]);
      final manager = _manager(current);

      final replacement = manager.replaceExercise(
        original,
        _template('Incline bench'),
      );

      expect(replacement, isNotNull);
      expect(current.exercises.single.name, 'Incline bench');
      expect(current.exercises.single.supersetGroup, 3);
      expect(current.exercises.single.sourceExerciseId, isNull);
      expect(current.exercises.single.id, isNot(original.id));
    },
  );

  test('duplicate copies set targets but resets completion and superset', () {
    final original = _workoutExercise('Row', supersetGroup: 2);
    original.sets = [
      ExerciseSet(
        weight: 70,
        reps: 10,
        isCompleted: true,
        type: SetType.failure,
        rpe: 9.5,
        rir: 0,
        notes: 'hard',
      ),
    ];
    original.previousWeights = [67.5];
    original.previousReps = [10];
    final current = _session(exercises: [original]);

    final duplicate = _manager(current).duplicateExercise(original);

    expect(duplicate, isNotNull);
    expect(current.exercises, hasLength(2));
    expect(duplicate!.id, isNot(original.id));
    expect(duplicate.supersetGroup, isNull);
    expect(duplicate.sourceExerciseId, isNull);
    expect(duplicate.sets.single.weight, 70);
    expect(duplicate.sets.single.reps, 10);
    expect(duplicate.sets.single.type, SetType.failure);
    expect(duplicate.sets.single.rpe, 9.5);
    expect(duplicate.sets.single.rir, 0);
    expect(duplicate.sets.single.notes, 'hard');
    expect(duplicate.sets.single.isCompleted, isFalse);
    expect(duplicate.sets.single.id, isNot(original.sets.single.id));
    expect(duplicate.previousWeights, [67.5]);
    expect(duplicate.previousReps, [10]);
  });

  test('move exercise enforces boundaries and preserves identity', () {
    final a = _workoutExercise('A');
    final b = _workoutExercise('B');
    final c = _workoutExercise('C');
    final current = _session(exercises: [a, b, c]);
    final manager = _manager(current);

    expect(manager.moveExercise(a, -1), isFalse);
    expect(manager.moveExercise(b, 1), isTrue);
    expect(current.exercises.map((e) => e.name).toList(), ['A', 'C', 'B']);
    expect(current.exercises.last.id, b.id);
  });

  test('remove cleans orphan superset and undo restores original group', () {
    final a = _workoutExercise('A', supersetGroup: 4);
    final b = _workoutExercise('B', supersetGroup: 4);
    final c = _workoutExercise('C');
    final current = _session(exercises: [a, b, c]);
    final manager = _manager(current);

    final removal = manager.removeExercise(a);

    expect(removal, isNotNull);
    expect(current.exercises.map((e) => e.name).toList(), ['B', 'C']);
    expect(b.supersetGroup, isNull);

    expect(manager.restoreRemoved(removal!), isTrue);
    expect(current.exercises.map((e) => e.name).toList(), ['A', 'B', 'C']);
    expect(a.supersetGroup, 4);
    expect(b.supersetGroup, 4);
    expect(manager.restoreRemoved(removal), isFalse);
  });

  test('linking to an existing superset cleans the previous orphan group', () {
    final a = _workoutExercise('A', supersetGroup: 1);
    final orphanPartner = _workoutExercise('B', supersetGroup: 1);
    final c = _workoutExercise('C', supersetGroup: 7);
    final d = _workoutExercise('D', supersetGroup: 7);
    final current = _session(exercises: [a, orphanPartner, c, d]);
    final manager = _manager(current);

    expect(manager.linkSuperset(a, c), isTrue);

    expect(a.supersetGroup, 7);
    expect(c.supersetGroup, 7);
    expect(d.supersetGroup, 7);
    expect(orphanPartner.supersetGroup, isNull);
  });

  test('remove from superset clears the last orphan member', () {
    final a = _workoutExercise('A', supersetGroup: 5);
    final b = _workoutExercise('B', supersetGroup: 5);
    final current = _session(exercises: [a, b]);
    final manager = _manager(current);

    expect(manager.removeFromSuperset(a), isTrue);
    expect(a.supersetGroup, isNull);
    expect(b.supersetGroup, isNull);
    expect(manager.removeFromSuperset(a), isFalse);
  });

  test('drop continuation suppresses rest until the drop chain ends', () {
    final exercise = _workoutExercise('Lateral raise');
    exercise.sets = [
      ExerciseSet(weight: 12, reps: 12),
      ExerciseSet(weight: 9, reps: 10, type: SetType.drop),
      ExerciseSet(weight: 6, reps: 10, type: SetType.drop),
    ];
    final current = _session(exercises: [exercise]);
    final manager = _manager(current);

    expect(manager.hasPendingDropContinuation(exercise, 0), isTrue);
    expect(manager.hasPendingDropContinuation(exercise, 1), isTrue);
    expect(manager.hasPendingDropContinuation(exercise, 2), isFalse);
    expect(
      manager.shouldStartRestAfterSet(exercise, completedSetIndex: 0),
      isFalse,
    );
    expect(
      manager.shouldStartRestAfterSet(exercise, completedSetIndex: 1),
      isFalse,
    );
    expect(
      manager.shouldStartRestAfterSet(exercise, completedSetIndex: 2),
      isTrue,
    );

    exercise.sets[1].isCompleted = true;
    expect(manager.hasPendingDropContinuation(exercise, 0), isFalse);
  });

  test('drop continuation takes priority over superset rest and navigation', () {
    final partner = _workoutExercise('Curl', supersetGroup: 11);
    final dropExercise = _workoutExercise('Pushdown', supersetGroup: 11);
    dropExercise.sets = [
      ExerciseSet(weight: 30, reps: 10),
      ExerciseSet(weight: 22.5, reps: 10, type: SetType.drop),
    ];
    final current = _session(exercises: [partner, dropExercise]);
    final manager = _manager(current);

    // Pushdown is the last superset member, so the legacy rule would rest here.
    expect(
      manager.shouldStartRestAfterSet(dropExercise, completedSetIndex: 0),
      isFalse,
    );
    expect(manager.nextSupersetMemberAfterSet(dropExercise, 0), isNull);

    // After the final drop, the normal superset cycle resumes.
    expect(
      manager.shouldStartRestAfterSet(dropExercise, completedSetIndex: 1),
      isTrue,
    );
    expect(manager.nextSupersetMemberAfterSet(dropExercise, 1)?.id, partner.id);
  });

  test('superset navigation and rest semantics follow session order', () {
    final a = _workoutExercise('A', supersetGroup: 9);
    final middle = _workoutExercise('Middle');
    final b = _workoutExercise('B', supersetGroup: 9);
    final c = _workoutExercise('C', supersetGroup: 9);
    final current = _session(exercises: [a, middle, b, c]);
    final manager = _manager(current);

    expect(manager.supersetMembers(a).map((e) => e.name).toList(), [
      'A',
      'B',
      'C',
    ]);
    expect(manager.nextSupersetMember(a)?.id, b.id);
    expect(manager.nextSupersetMember(b)?.id, c.id);
    expect(manager.nextSupersetMember(c)?.id, a.id);
    expect(manager.shouldStartRestAfterSet(a), isFalse);
    expect(manager.shouldStartRestAfterSet(b), isFalse);
    expect(manager.shouldStartRestAfterSet(c), isTrue);
    expect(manager.shouldStartRestAfterSet(middle), isTrue);
  });
}
