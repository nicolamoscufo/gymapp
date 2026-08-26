import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gymapp/local_sqlite_store.dart';
import 'package:gymapp/models/body_log.dart';
import 'package:gymapp/models/exercise.dart';
import 'package:gymapp/models/schedule.dart';
import 'package:gymapp/models/schedule_version.dart';
import 'package:gymapp/models/workout.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

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
        catalogId: 'catalog-bench',
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
            catalogId: 'catalog-bench',
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
      expect(data.schedules.single.exercises.single.catalogId, 'catalog-bench');
      expect(data.history.single.exercises.single.catalogId, 'catalog-bench');
      expect(data.schedules.single.exercises.single.restSeconds, 180);
      expect(data.history.single.exercises.single.sets.single.rir, 2);
      expect(data.currentSession?.id, 'current-session');
      expect(data.bodyLogs.single.bodyWeight, 79.5);
      expect(data.customExercises.single.catalogId, 'catalog-bench');
      expect(data.favoriteExerciseIds, contains('bench-plan'));
    },
  );

  test(
    'existing v1 sqlite database upgrades without losing base tables',
    () async {
      final temp = await Directory.systemTemp.createTemp('gymapp-v1-upgrade-');
      addTearDown(() => temp.delete(recursive: true));
      final path = '${temp.path}/gymapp.db';
      final legacyDb = await databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: (db, _) async {
            await db.execute(
              'CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
            );
            await db.execute('CREATE TABLE schedules (id TEXT PRIMARY KEY)');
            await db.execute(
              'CREATE TABLE schedule_exercises (id TEXT PRIMARY KEY)',
            );
            await db.execute(
              'CREATE TABLE workout_sessions (id TEXT PRIMARY KEY, session_kind TEXT NOT NULL, position INTEGER NOT NULL, schedule_id TEXT, schedule_title TEXT NOT NULL, start_time TEXT NOT NULL, end_time TEXT NOT NULL)',
            );
            await db.execute(
              'CREATE TABLE workout_exercises (id TEXT PRIMARY KEY)',
            );
            await db.insert('meta', {
              'key': 'legacy_migrated_v1',
              'value': '1',
            });
            await db.insert('schedules', {'id': 'legacy-plan'});
          },
        ),
      );
      await legacyDb.close();

      final store = LocalSqliteStore(
        factoryOverride: databaseFactoryFfi,
        databasePath: path,
      );
      addTearDown(store.close);
      expect(await store.migrationComplete, isTrue);

      final upgraded = await databaseFactoryFfi.openDatabase(path);
      addTearDown(upgraded.close);
      final scheduleColumns = await upgraded.rawQuery(
        'PRAGMA table_info(schedules)',
      );
      final scheduleExerciseColumns = await upgraded.rawQuery(
        'PRAGMA table_info(schedule_exercises)',
      );
      final workoutColumns = await upgraded.rawQuery(
        'PRAGMA table_info(workout_sessions)',
      );
      final workoutExerciseColumns = await upgraded.rawQuery(
        'PRAGMA table_info(workout_exercises)',
      );
      final versionTable = await upgraded.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='schedule_versions'",
      );

      expect(
        scheduleColumns.map((row) => row['name']),
        containsAll(['current_version_id', 'current_version_number']),
      );
      expect(
        scheduleExerciseColumns.map((row) => row['name']),
        contains('catalog_id'),
      );
      expect(
        workoutColumns.map((row) => row['name']),
        contains('schedule_version_id'),
      );
      expect(
        workoutExerciseColumns.map((row) => row['name']),
        contains('catalog_id'),
      );
      expect(versionTable, hasLength(1));
      expect(
        await upgraded.query(
          'schedules',
          where: 'id = ?',
          whereArgs: ['legacy-plan'],
        ),
        hasLength(1),
      );
    },
  );

  test('existing v2 sqlite database upgrades catalog columns in place', () async {
    final temp = await Directory.systemTemp.createTemp('gymapp-v2-upgrade-');
    addTearDown(() => temp.delete(recursive: true));
    final path = '${temp.path}/gymapp.db';
    final v2Db = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 2,
        onCreate: (db, _) async {
          await db.execute(
            'CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
          );
          await db.execute(
            'CREATE TABLE schedule_exercises (id TEXT PRIMARY KEY, name TEXT NOT NULL)',
          );
          await db.execute(
            'CREATE TABLE workout_exercises (id TEXT PRIMARY KEY, name TEXT NOT NULL)',
          );
          await db.insert('schedule_exercises', {
            'id': 'legacy-plan-exercise',
            'name': 'Panca',
          });
          await db.insert('workout_exercises', {
            'id': 'legacy-work-exercise',
            'name': 'Panca',
          });
        },
      ),
    );
    await v2Db.close();

    final store = LocalSqliteStore(
      factoryOverride: databaseFactoryFfi,
      databasePath: path,
    );
    addTearDown(store.close);
    // Force opening/migration without requiring the rest of the application
    // schema to exist in this focused fixture.
    await store.hasAnyData;

    final upgraded = await databaseFactoryFfi.openDatabase(path);
    addTearDown(upgraded.close);
    final scheduleExerciseColumns = await upgraded.rawQuery(
      'PRAGMA table_info(schedule_exercises)',
    );
    final workoutExerciseColumns = await upgraded.rawQuery(
      'PRAGMA table_info(workout_exercises)',
    );

    expect(
      scheduleExerciseColumns.map((row) => row['name']),
      contains('catalog_id'),
    );
    expect(
      workoutExerciseColumns.map((row) => row['name']),
      contains('catalog_id'),
    );
    expect(
      await upgraded.query(
        'schedule_exercises',
        where: 'id = ?',
        whereArgs: ['legacy-plan-exercise'],
      ),
      hasLength(1),
    );
    expect(
      await upgraded.query(
        'workout_exercises',
        where: 'id = ?',
        whereArgs: ['legacy-work-exercise'],
      ),
      hasLength(1),
    );
  });

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
