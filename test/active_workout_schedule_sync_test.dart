import 'package:flutter_test/flutter_test.dart';
import 'package:gymapp/active_workout_schedule_sync.dart';
import 'package:gymapp/active_workout_session_builder.dart';
import 'package:gymapp/models/exercise.dart';
import 'package:gymapp/models/schedule.dart';
import 'package:gymapp/models/workout.dart';

Exercise _template(
  String name, {
  String? id,
  double weight = 50,
  int reps = 8,
  ProgressionScheme scheme = ProgressionScheme.doubleProgression,
}) {
  return Exercise(
    id: id,
    name: name,
    reps: reps,
    set: 2,
    notes: '',
    weight: weight,
    targetMinReps: 8,
    targetMaxReps: 10,
    technique: IntensityTechnique.none,
    progressionKgStep: 2.5,
    progressionRepStep: 1,
    progressionScheme: scheme,
  );
}

Schedule _schedule(String title, {String? id, List<Exercise>? exercises}) {
  return Schedule(
    id: id,
    title: title,
    week: 1,
    createdAt: DateTime(2026, 8, 1),
    exercises: exercises ?? [],
  );
}

WorkoutExercise _workoutExercise(
  String name, {
  String? sourceExerciseId,
  double weight = 50,
  int reps = 8,
  int setCount = 2,
  bool completed = false,
  int? rir,
  ProgressionScheme scheme = ProgressionScheme.doubleProgression,
}) {
  return WorkoutExercise(
    sourceExerciseId: sourceExerciseId,
    name: name,
    notes: '',
    targetMinReps: 8,
    targetMaxReps: 10,
    technique: IntensityTechnique.none,
    progressionKgStep: 2.5,
    progressionRepStep: 1,
    progressionScheme: scheme,
    sets: List.generate(
      setCount,
      (_) => ExerciseSet(
        weight: weight,
        reps: reps,
        isCompleted: completed,
        rir: rir,
      ),
    ),
  );
}

WorkoutSession _session({
  String? id,
  String? scheduleId = 'schedule-a',
  String title = 'Push',
  List<WorkoutExercise>? exercises,
}) {
  return WorkoutSession(
    id: id,
    scheduleId: scheduleId,
    scheduleTitle: title,
    startTime: DateTime(2026, 8, 26, 10),
    endTime: DateTime(2026, 8, 26, 11),
    exercises: exercises ?? [],
  );
}

ActiveWorkoutScheduleSync _sync(WorkoutSession session) {
  return ActiveWorkoutScheduleSync(
    session: session,
    sessionBuilder: ActiveWorkoutSessionBuilder(
      history: const [],
      bodyLogs: const [],
      now: () => DateTime(2026, 8, 26, 12),
    ),
  );
}

void main() {
  test('stored schedule lookup prefers stable id before title fallback', () {
    final wrongByTitle = _schedule('Push', id: 'wrong');
    final correctById = _schedule('Renamed push', id: 'schedule-a');
    final sync = _sync(_session(title: 'Push'));

    expect(
      sync.storedScheduleForSession([wrongByTitle, correctById]),
      same(correctById),
    );
  });

  test('stored schedule lookup keeps title fallback for legacy sessions', () {
    final legacy = _schedule('Legacy push', id: 'generated-id');
    final session = _session(scheduleId: null, title: 'Legacy push');

    expect(_sync(session).storedScheduleForSession([legacy]), same(legacy));
  });

  test('exercise lookup prefers source id when duplicate names exist', () {
    final wrong = _template('Bench', id: 'bench-wrong', weight: 60);
    final exact = _template('Bench', id: 'bench-exact', weight: 80);
    final schedule = _schedule('Push', exercises: [wrong, exact]);
    final live = _workoutExercise('Bench', sourceExerciseId: 'bench-exact');

    expect(
      _sync(_session(exercises: [live])).scheduleExerciseFor(live, schedule),
      same(exact),
    );
  });

  test('new live exercise is appended and bound to its routine id', () {
    final stored = _schedule(
      'Push',
      id: 'schedule-a',
      exercises: [_template('Bench', id: 'bench-id')],
    );
    final bench = _workoutExercise('Bench', sourceExerciseId: 'bench-id');
    final cable = _workoutExercise('Cable fly', weight: 20, reps: 10);
    final session = _session(exercises: [bench, cable]);
    final sync = _sync(session);

    expect(sync.newExercisesForSchedule(stored), [cable]);
    final addedIds = sync.addNewExercisesToSchedule(stored);

    expect(stored.exercises, hasLength(2));
    expect(stored.exercises.last.name, 'Cable fly');
    expect(cable.sourceExerciseId, stored.exercises.last.id);
    expect(addedIds, {stored.exercises.last.id});
    expect(sync.newExercisesForSchedule(stored), isEmpty);
  });

  test('live routine mirror receives deep copies of stored exercises', () {
    final storedExercise = _template('Bench', id: 'bench-id', weight: 75);
    final stored = _schedule(
      'Push',
      id: 'schedule-a',
      exercises: [storedExercise],
    );
    final live = _schedule('Push', id: 'schedule-a', exercises: []);
    final sync = _sync(_session());

    sync.syncLiveSchedule(storedSchedule: stored, liveSchedule: live);

    expect(live.exercises, hasLength(1));
    expect(live.exercises.single.id, storedExercise.id);
    expect(live.exercises.single, isNot(same(storedExercise)));
    live.exercises.single.weight = 90;
    expect(storedExercise.weight, 75);
  });

  test('progression mutates exact id match even with duplicate names', () {
    final wrong = _template('Bench', id: 'wrong-id', weight: 60, reps: 10);
    final exact = _template('Bench', id: 'exact-id', weight: 80, reps: 10);
    final stored = _schedule('Push', exercises: [wrong, exact]);
    final completed = _workoutExercise(
      'Bench',
      sourceExerciseId: 'exact-id',
      weight: 80,
      reps: 10,
      completed: true,
      rir: 2,
    );
    final session = _session(id: 'current', exercises: [completed]);

    _sync(
      session,
    ).applyProgressionToSchedule(storedSchedule: stored, history: [session]);

    expect(wrong.weight, 60);
    expect(exact.weight, 82.5);
    expect(exact.reps, 8);
  });

  test('partial workout keeps routine progression unchanged', () {
    final template = _template('Bench', id: 'bench-id', weight: 80, reps: 9);
    final stored = _schedule('Push', exercises: [template]);
    final partial = _workoutExercise(
      'Bench',
      sourceExerciseId: 'bench-id',
      weight: 80,
      reps: 10,
      completed: false,
      rir: 2,
    );
    partial.sets.first.isCompleted = true;
    final session = _session(id: 'partial', exercises: [partial]);

    _sync(
      session,
    ).applyProgressionToSchedule(storedSchedule: stored, history: [session]);

    expect(template.weight, 80);
    expect(template.reps, 9);
  });

  test('newly bound exercises can be skipped in same finish progression', () {
    final stored = _schedule('Push', id: 'schedule-a');
    final live = _workoutExercise(
      'Cable fly',
      weight: 20,
      reps: 10,
      completed: true,
      rir: 2,
    );
    final session = _session(id: 'current', exercises: [live]);
    final sync = _sync(session);
    final addedIds = sync.addNewExercisesToSchedule(stored);
    final initialWeight = stored.exercises.single.weight;

    sync.applyProgressionToSchedule(
      storedSchedule: stored,
      history: [session],
      skipSourceExerciseIds: addedIds,
    );

    expect(stored.exercises.single.weight, initialWeight);
    expect(live.sourceExerciseId, stored.exercises.single.id);
  });
}
