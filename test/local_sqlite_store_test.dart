import 'package:flutter_test/flutter_test.dart';
import 'package:gymapp/local_sqlite_store.dart';
import 'package:gymapp/models/body_log.dart';
import 'package:gymapp/models/exercise.dart';
import 'package:gymapp/models/schedule.dart';
import 'package:gymapp/models/schedule_version.dart';
import 'package:gymapp/models/workout.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  test(
    'normalized sqlite store round-trips the full local data graph',
    () async {
      final store = LocalSqliteStore(
        factoryOverride: databaseFactoryFfi,
        databasePath: inMemoryDatabasePath,
      );
      addTearDown(store.close);

      final planExercise = Exercise(
        id: 'bench-plan',
        name: 'Panca',
        reps: 8,
        set: 3,
        notes: 'petto',
        weight: 80,
        muscleGroup: MuscleGroup.chest,
        restSeconds: 180,
        technique: IntensityTechnique.none,
      );
      final schedule = Schedule(
        id: 'push',
        title: 'Push',
        week: 2,
        createdAt: DateTime(2026, 8, 1),
        exercises: [planExercise],
        trainingWeekdays: [1, 4],
      );
      final version = ScheduleVersion.capture(
        schedule: schedule,
        versionNumber: 1,
        createdAt: DateTime(2026, 8, 1),
        source: ScheduleVersionSource.migration,
      );
      schedule.currentVersionId = version.id;
      schedule.currentVersionNumber = 1;
      final session = WorkoutSession(
        id: 'session-1',
        scheduleId: 'push',
        scheduleVersionId: version.id,
        scheduleTitle: 'Push',
        startTime: DateTime(2026, 8, 25, 18),
        endTime: DateTime(2026, 8, 25, 19),
        exercises: [
          WorkoutExercise(
            id: 'work-bench',
            sourceExerciseId: 'bench-plan',
            name: 'Panca',
            notes: 'bene',
            muscleGroup: MuscleGroup.chest,
            technique: IntensityTechnique.none,
            previousWeights: const [77.5],
            previousReps: const [8],
            sets: [
              ExerciseSet(
                id: 'set-1',
                weight: 80,
                reps: 8,
                isCompleted: true,
                rir: 2,
                rpe: 8,
              ),
            ],
          ),
        ],
      );
      final body = BodyLog(
        id: 'body-1',
        date: DateTime(2026, 8, 25),
        bodyWeight: 79.5,
        sleepHours: 8,
        readiness: 8,
      );

      await store.migrateLegacyData(
        schedules: [schedule],
        history: [session],
        currentSession: _session('current-session', 81),
        bodyLogs: [body],
        customExercises: [planExercise],
        favoriteExerciseIds: {'bench-plan'},
        scheduleVersions: [version],
      );

      final data = await store.loadAll();
      expect(await store.migrationComplete, isTrue);
      expect(data.schedules.single.id, 'push');
      expect(data.schedules.single.currentVersionId, version.id);
      expect(data.scheduleVersions.single.id, version.id);
      expect(data.history.single.scheduleVersionId, version.id);
      expect(data.schedules.single.exercises.single.restSeconds, 180);
      expect(data.history.single.exercises.single.sets.single.rir, 2);
      expect(data.currentSession?.id, 'current-session');
      expect(data.bodyLogs.single.bodyWeight, 79.5);
      expect(data.customExercises.single.id, 'bench-plan');
      expect(data.favoriteExerciseIds, contains('bench-plan'));
    },
  );

  test('current-session writes do not require rewriting history', () async {
    final store = LocalSqliteStore(
      factoryOverride: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    addTearDown(store.close);
    final history = _session('history', 70);
    final current = _session('current', 80);
    await store.replaceHistory([history]);
    await store.saveCurrentSession(current);
    await store.saveCurrentSession(_session('current', 82.5));

    expect((await store.loadHistory()).single.id, 'history');
    expect(
      (await store.loadCurrentSession())!.exercises.single.sets.single.weight,
      82.5,
    );
  });
}

WorkoutSession _session(String id, double weight) {
  return WorkoutSession(
    id: id,
    scheduleTitle: 'Push',
    startTime: DateTime(2026, 8, 25, 18),
    endTime: DateTime(2026, 8, 25, 19),
    exercises: [
      WorkoutExercise(
        name: 'Panca',
        notes: '',
        technique: IntensityTechnique.none,
        sets: [ExerciseSet(weight: weight, reps: 8, isCompleted: true)],
      ),
    ],
  );
}
