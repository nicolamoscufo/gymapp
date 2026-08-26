import 'package:flutter_test/flutter_test.dart';
import 'package:gymapp/ai_coach/program_history_context.dart';
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

  test(
    'program history preserves baseline, diffs, provenance and exact outcomes',
    () {
      final schedule = _schedule();
      final v1 = ScheduleVersion.capture(
        schedule: schedule,
        versionNumber: 1,
        createdAt: DateTime(2026, 5, 1),
        source: ScheduleVersionSource.user,
        reason: 'Initial plan',
      );

      schedule.exercises.single
        ..weight = 82.5
        ..reps = 9;
      final v2 = ScheduleVersion.capture(
        schedule: schedule,
        versionNumber: 2,
        createdAt: DateTime(2026, 6, 1),
        source: ScheduleVersionSource.aiCoach,
        parentVersionId: v1.id,
        reason: 'Approved progression',
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
      final v3 = ScheduleVersion.capture(
        schedule: schedule,
        versionNumber: 3,
        createdAt: DateTime(2026, 7, 1),
        source: ScheduleVersionSource.user,
        parentVersionId: v2.id,
        reason: 'Added accessory',
      );
      schedule
        ..currentVersionId = v3.id
        ..currentVersionNumber = 3;

      final deleted = Schedule(
        id: 'old-plan',
        title: 'Old Upper',
        week: 1,
        createdAt: DateTime(2026, 3, 1),
        exercises: const [],
      );
      final oldVersion = ScheduleVersion.capture(
        schedule: deleted,
        versionNumber: 1,
        createdAt: DateTime(2026, 3, 1),
        source: ScheduleVersionSource.import,
        reason: 'Imported old plan',
      );

      final history = [
        _session('s1', DateTime(2026, 5, 10), versionId: v1.id, weight: 80),
        _session(
          's2',
          DateTime(2026, 6, 10),
          versionId: v2.id,
          weight: 82.5,
        ),
        _session(
          'legacy',
          DateTime(2026, 4, 10),
          versionId: null,
          weight: 77.5,
        ),
        _session(
          'orphan',
          DateTime(2026, 4, 20),
          versionId: 'missing-version',
          weight: 78,
        ),
      ];

      final context = buildProgramHistoryContext(
        scheduleVersions: [v1, v2, v3, oldVersion],
        history: history,
        schedules: [schedule],
      );

      final coverage = Map<String, dynamic>.from(context['coverage'] as Map);
      expect(coverage['version_count'], 4);
      expect(coverage['exactly_linked_workouts'], 2);
      expect(coverage['unresolved_legacy_workouts'], 1);
      expect(coverage['orphaned_version_link_workouts'], 1);
      expect(coverage['exact_link_coverage'], closeTo(0.5, 0.0001));

      final programs = (context['programs'] as List)
          .map((entry) => Map<String, dynamic>.from(entry as Map))
          .toList();
      expect(programs, hasLength(2));
      final push = programs.singleWhere(
        (entry) => entry['schedule_id'] == 'push',
      );
      final versions = (push['versions'] as List)
          .map((entry) => Map<String, dynamic>.from(entry as Map))
          .toList();
      expect(versions, hasLength(3));
      expect(versions.first, contains('baseline'));
      expect(versions[1]['source'], 'aiCoach');
      expect(versions[1]['reason'], 'Approved progression');

      final v2Diff = Map<String, dynamic>.from(
        versions[1]['changes_from_previous'] as Map,
      );
      final exerciseChanges = (v2Diff['exercises'] as List)
          .map((entry) => Map<String, dynamic>.from(entry as Map))
          .toList();
      final benchChange = exerciseChanges.singleWhere(
        (entry) => entry['exercise_id'] == 'bench',
      );
      final fields = (benchChange['fields'] as List)
          .map((entry) => Map<String, dynamic>.from(entry as Map))
          .toList();
      expect(
        fields.any(
          (entry) => entry['field'] == 'weight' && entry['to'] == 82.5,
        ),
        isTrue,
      );
      expect(
        fields.any((entry) => entry['field'] == 'reps' && entry['to'] == 9),
        isTrue,
      );

      final v3Diff = Map<String, dynamic>.from(
        versions[2]['changes_from_previous'] as Map,
      );
      expect(
        (v3Diff['exercises'] as List).any(
          (entry) =>
              (entry as Map)['type'] == 'added' &&
              entry['exercise_id'] == 'fly',
        ),
        isTrue,
      );

      final v1Performance = Map<String, dynamic>.from(
        versions[0]['performance'] as Map,
      );
      final v2Performance = Map<String, dynamic>.from(
        versions[1]['performance'] as Map,
      );
      final v3Performance = Map<String, dynamic>.from(
        versions[2]['performance'] as Map,
      );
      expect(v1Performance['session_count'], 1);
      expect(v2Performance['session_count'], 1);
      expect(v3Performance['session_count'], 0);
      expect(v1Performance['total_volume'], 80 * 8);
      expect(v2Performance['total_volume'], 82.5 * 8);

      final unresolved = Map<String, dynamic>.from(
        context['unresolved_legacy'] as Map,
      );
      expect(unresolved['count'], 1);
      expect(
        (unresolved['by_schedule'] as List).single,
        containsPair('sessions', 1),
      );

      final orphaned = Map<String, dynamic>.from(
        context['orphaned_version_links'] as Map,
      );
      expect(orphaned['count'], 1);
      expect(orphaned['version_ids'], contains('missing-version'));
      expect(
        (orphaned['sessions'] as List).single,
        containsPair('schedule_version_id', 'missing-version'),
      );

      final oldProgram = programs.singleWhere(
        (entry) => entry['schedule_id'] == 'old-plan',
      );
      expect(oldProgram['is_present_in_current_plans'], isFalse);
    },
  );

  test(
    'recent detail stays bounded while program history spans all exact sessions',
    () {
      final schedule = _schedule();
      final version = ScheduleVersion.capture(
        schedule: schedule,
        versionNumber: 1,
        createdAt: DateTime(2026, 1, 1),
        source: ScheduleVersionSource.user,
      );
      schedule
        ..currentVersionId = version.id
        ..currentVersionNumber = 1;
      final history = List.generate(
        15,
        (index) => _session(
          'session-$index',
          DateTime(2026, 1, 2 + index),
          versionId: version.id,
          weight: 70 + index.toDouble(),
        ),
      );

      final context = TrainingContextBuilder(now: DateTime(2026, 2, 1)).recent(
        history: history,
        schedules: [schedule],
        scheduleVersions: [version],
      );

      expect(context['workouts'], hasLength(12));
      final programHistory = Map<String, dynamic>.from(
        context['program_history'] as Map,
      );
      final program = Map<String, dynamic>.from(
        (programHistory['programs'] as List).single as Map,
      );
      final versionEntry = Map<String, dynamic>.from(
        (program['versions'] as List).single as Map,
      );
      final performance = Map<String, dynamic>.from(
        versionEntry['performance'] as Map,
      );
      expect(performance['session_count'], 15);
    },
  );
}

Schedule _schedule() => Schedule(
  id: 'push',
  title: 'Push',
  week: 1,
  createdAt: DateTime(2026, 5, 1),
  goal: 'Ipertrofia',
  exercises: [
    Exercise(
      id: 'bench',
      name: 'Panca',
      reps: 8,
      set: 3,
      notes: '',
      weight: 80,
      muscleGroup: MuscleGroup.chest,
      technique: IntensityTechnique.none,
    ),
  ],
);

WorkoutSession _session(
  String id,
  DateTime start, {
  required String? versionId,
  required double weight,
}) => WorkoutSession(
  id: id,
  scheduleId: 'push',
  scheduleVersionId: versionId,
  scheduleTitle: 'Push',
  startTime: start,
  endTime: start.add(const Duration(minutes: 60)),
  exercises: [
    WorkoutExercise(
      id: 'exercise-$id',
      sourceExerciseId: 'bench',
      name: 'Panca',
      notes: '',
      muscleGroup: MuscleGroup.chest,
      technique: IntensityTechnique.none,
      sets: [
        ExerciseSet(id: 'set-$id', weight: weight, reps: 8, isCompleted: true),
      ],
    ),
  ],
);
