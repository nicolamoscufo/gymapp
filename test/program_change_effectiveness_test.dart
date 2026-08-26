import 'package:flutter_test/flutter_test.dart';
import 'package:gymapp/ai_coach/program_change_effectiveness.dart';
import 'package:gymapp/ai_coach/training_context_builder.dart';
import 'package:gymapp/models/exercise.dart';
import 'package:gymapp/models/schedule.dart';
import 'package:gymapp/models/schedule_version.dart';
import 'package:gymapp/models/workout.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('classifies exact-linked e1RM improvement after prescription change', () {
    final versions = _versions(weightBefore: 80, weightAfter: 82.5);
    final history = [
      _session('p1', versions.$1.id, DateTime(2026, 5, 10), 80),
      _session('p2', versions.$1.id, DateTime(2026, 5, 17), 80),
      _session('c1', versions.$2.id, DateTime(2026, 6, 5), 85),
      _session('c2', versions.$2.id, DateTime(2026, 6, 12), 87.5),
    ];

    final context = buildProgramChangeEffectivenessContext(
      scheduleVersions: [versions.$1, versions.$2],
      history: history,
    );
    final transition = _singleTransition(context);
    final signal = _singleSignal(transition);

    expect(transition['status'], 'improved');
    expect(signal['status'], 'improved');
    expect(signal['primary_metric'], 'mean_estimated_1rm');
    expect(signal['changed_fields'], contains('weight'));
    expect(signal['e1rm_change_percent'] as double, greaterThan(2));
    expect(
      (context['contract'] as Map)['does_not_prove_causality'],
      isTrue,
    );
  });

  test('classifies decline and can report mixed outcomes across exercises', () {
    final before = _schedule(twoExercises: true);
    final v1 = ScheduleVersion.capture(
      schedule: before,
      versionNumber: 1,
      createdAt: DateTime(2026, 5, 1),
      source: ScheduleVersionSource.user,
    );
    before.exercises[0].weight = 82.5;
    before.exercises[1].reps = 6;
    final v2 = ScheduleVersion.capture(
      schedule: before,
      versionNumber: 2,
      createdAt: DateTime(2026, 6, 1),
      source: ScheduleVersionSource.aiCoach,
      parentVersionId: v1.id,
      reason: 'Reviewed progression',
    );

    final history = [
      _session('p1', v1.id, DateTime(2026, 5, 10), 80, squatWeight: 100),
      _session('p2', v1.id, DateTime(2026, 5, 17), 80, squatWeight: 100),
      _session('c1', v2.id, DateTime(2026, 6, 5), 85, squatWeight: 90),
      _session('c2', v2.id, DateTime(2026, 6, 12), 87.5, squatWeight: 90),
    ];

    final transition = _singleTransition(
      buildProgramChangeEffectivenessContext(
        scheduleVersions: [v1, v2],
        history: history,
      ),
    );
    final signals = (transition['exercise_signals'] as List)
        .map((entry) => Map<String, dynamic>.from(entry as Map))
        .toList();

    expect(transition['status'], 'mixed');
    expect(
      signals.singleWhere((entry) => entry['exercise_id'] == 'bench')['status'],
      'improved',
    );
    expect(
      signals.singleWhere((entry) => entry['exercise_id'] == 'squat')['status'],
      'declined',
    );
  });

  test('requires at least two exact sessions on each side', () {
    final versions = _versions(weightBefore: 80, weightAfter: 82.5);
    final transition = _singleTransition(
      buildProgramChangeEffectivenessContext(
        scheduleVersions: [versions.$1, versions.$2],
        history: [
          _session('p1', versions.$1.id, DateTime(2026, 5, 10), 80),
          _session('p2', versions.$1.id, DateTime(2026, 5, 17), 80),
          _session('c1', versions.$2.id, DateTime(2026, 6, 5), 85),
        ],
      ),
    );

    final signal = _singleSignal(transition);
    expect(transition['status'], 'insufficient');
    expect(signal['status'], 'insufficient');
    expect(signal['reason'], 'requires_at_least_two_exact_sessions_per_side');
  });

  test('ignores note-only changes because they are not prescription changes', () {
    final schedule = _schedule();
    final v1 = ScheduleVersion.capture(
      schedule: schedule,
      versionNumber: 1,
      createdAt: DateTime(2026, 5, 1),
      source: ScheduleVersionSource.user,
    );
    schedule.exercises.single.notes = 'Nuova nota tecnica';
    final v2 = ScheduleVersion.capture(
      schedule: schedule,
      versionNumber: 2,
      createdAt: DateTime(2026, 6, 1),
      source: ScheduleVersionSource.user,
      parentVersionId: v1.id,
    );

    final transition = _singleTransition(
      buildProgramChangeEffectivenessContext(
        scheduleVersions: [v1, v2],
        history: const [],
      ),
    );

    expect(transition['status'], 'insufficient');
    expect(transition['exercise_signals'], isEmpty);
    expect(
      transition['evaluation_note'],
      'no_performance_relevant_exercise_changes',
    );
  });

  test('added exercise stays insufficient without a pre-change baseline', () {
    final schedule = _schedule();
    final v1 = ScheduleVersion.capture(
      schedule: schedule,
      versionNumber: 1,
      createdAt: DateTime(2026, 5, 1),
      source: ScheduleVersionSource.user,
    );
    schedule.exercises.add(
      Exercise(
        id: 'fly',
        name: 'Croci',
        reps: 12,
        set: 3,
        notes: '',
        weight: 20,
        technique: IntensityTechnique.none,
      ),
    );
    final v2 = ScheduleVersion.capture(
      schedule: schedule,
      versionNumber: 2,
      createdAt: DateTime(2026, 6, 1),
      source: ScheduleVersionSource.user,
      parentVersionId: v1.id,
    );

    final transition = _singleTransition(
      buildProgramChangeEffectivenessContext(
        scheduleVersions: [v1, v2],
        history: [
          _session(
            'c1',
            v2.id,
            DateTime(2026, 6, 5),
            80,
            extraExerciseId: 'fly',
            extraWeight: 20,
          ),
          _session(
            'c2',
            v2.id,
            DateTime(2026, 6, 12),
            80,
            extraExerciseId: 'fly',
            extraWeight: 22,
          ),
        ],
      ),
    );
    final fly = (transition['exercise_signals'] as List)
        .map((entry) => Map<String, dynamic>.from(entry as Map))
        .singleWhere((entry) => entry['exercise_id'] == 'fly');

    expect(fly['status'], 'insufficient');
    expect(fly['reason'], 'exercise_added_without_pre_change_baseline');
  });

  test('uses last previous and first current windows and exact source IDs only', () {
    final versions = _versions(weightBefore: 80, weightAfter: 82.5);
    final history = [
      _session('p-old', versions.$1.id, DateTime(2026, 5, 1), 40),
      _session('p1', versions.$1.id, DateTime(2026, 5, 8), 80),
      _session('p2', versions.$1.id, DateTime(2026, 5, 15), 80),
      _session('p3', versions.$1.id, DateTime(2026, 5, 22), 80),
      _session('c1', versions.$2.id, DateTime(2026, 6, 1), 82.5),
      _session('c2', versions.$2.id, DateTime(2026, 6, 8), 82.5),
      _session(
        'c3',
        versions.$2.id,
        DateTime(2026, 6, 15),
        82.5,
        contaminantWeight: 250,
      ),
      _session('c-late', versions.$2.id, DateTime(2026, 6, 22), 150),
    ];

    final signal = _singleSignal(
      _singleTransition(
        buildProgramChangeEffectivenessContext(
          scheduleVersions: [versions.$1, versions.$2],
          history: history,
        ),
      ),
    );

    expect(signal['previous_sessions'], 3);
    expect(signal['current_sessions'], 3);
    expect(signal['previous_mean_e1rm'] as double, closeTo(101.333, 0.01));
    expect(signal['current_mean_e1rm'] as double, closeTo(104.5, 0.01));
    expect(signal['current_mean_e1rm'] as double, lessThan(120));
  });

  test('TrainingContextBuilder exposes effectiveness beside program history', () {
    final versions = _versions(weightBefore: 80, weightAfter: 82.5);
    final schedule = versions.$2.restoreSchedule()
      ..currentVersionId = versions.$2.id
      ..currentVersionNumber = 2;
    final history = [
      _session('p1', versions.$1.id, DateTime(2026, 5, 10), 80),
      _session('p2', versions.$1.id, DateTime(2026, 5, 17), 80),
      _session('c1', versions.$2.id, DateTime(2026, 6, 5), 85),
      _session('c2', versions.$2.id, DateTime(2026, 6, 12), 87.5),
    ];

    final context = TrainingContextBuilder(now: DateTime(2026, 6, 20)).recent(
      history: history,
      schedules: [schedule],
      scheduleVersions: [versions.$1, versions.$2],
    );

    expect(context, contains('program_history'));
    expect(context, contains('program_change_effectiveness'));
    final effectiveness = Map<String, dynamic>.from(
      context['program_change_effectiveness'] as Map,
    );
    expect(
      (effectiveness['transitions'] as List).single,
      containsPair('status', 'improved'),
    );
  });
}

(ScheduleVersion, ScheduleVersion) _versions({
  required double weightBefore,
  required double weightAfter,
}) {
  final schedule = _schedule(weight: weightBefore);
  final v1 = ScheduleVersion.capture(
    schedule: schedule,
    versionNumber: 1,
    createdAt: DateTime(2026, 5, 1),
    source: ScheduleVersionSource.user,
  );
  schedule.exercises.single.weight = weightAfter;
  final v2 = ScheduleVersion.capture(
    schedule: schedule,
    versionNumber: 2,
    createdAt: DateTime(2026, 6, 1),
    source: ScheduleVersionSource.aiCoach,
    parentVersionId: v1.id,
    reason: 'Approved load progression',
  );
  return (v1, v2);
}

Schedule _schedule({double weight = 80, bool twoExercises = false}) => Schedule(
  id: 'push',
  title: 'Push',
  week: 1,
  createdAt: DateTime(2026, 5, 1),
  exercises: [
    Exercise(
      id: 'bench',
      name: 'Panca',
      reps: 8,
      set: 3,
      notes: '',
      weight: weight,
      muscleGroup: MuscleGroup.chest,
      technique: IntensityTechnique.none,
    ),
    if (twoExercises)
      Exercise(
        id: 'squat',
        name: 'Squat',
        reps: 8,
        set: 3,
        notes: '',
        weight: 100,
        muscleGroup: MuscleGroup.quadriceps,
        technique: IntensityTechnique.none,
      ),
  ],
);

WorkoutSession _session(
  String id,
  String versionId,
  DateTime start,
  double benchWeight, {
  double? squatWeight,
  String? extraExerciseId,
  double? extraWeight,
  double? contaminantWeight,
}) => WorkoutSession(
  id: id,
  scheduleId: 'push',
  scheduleVersionId: versionId,
  scheduleTitle: 'Push',
  startTime: start,
  endTime: start.add(const Duration(minutes: 60)),
  exercises: [
    _workoutExercise('bench', 'Panca', benchWeight),
    if (squatWeight != null) _workoutExercise('squat', 'Squat', squatWeight),
    if (extraExerciseId != null && extraWeight != null)
      _workoutExercise(extraExerciseId, 'Extra', extraWeight),
    if (contaminantWeight != null)
      _workoutExercise('different-source', 'Panca', contaminantWeight),
  ],
);

WorkoutExercise _workoutExercise(
  String sourceId,
  String name,
  double weight,
) => WorkoutExercise(
  sourceExerciseId: sourceId,
  name: name,
  notes: '',
  technique: IntensityTechnique.none,
  sets: [ExerciseSet(weight: weight, reps: 8, isCompleted: true)],
);

Map<String, dynamic> _singleTransition(Map<String, dynamic> context) =>
    Map<String, dynamic>.from((context['transitions'] as List).single as Map);

Map<String, dynamic> _singleSignal(Map<String, dynamic> transition) =>
    Map<String, dynamic>.from(
      (transition['exercise_signals'] as List).single as Map,
    );
