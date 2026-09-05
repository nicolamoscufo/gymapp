import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gymapp/app_data_store.dart';
import 'package:gymapp/app_preferences.dart';
import 'package:gymapp/local_sqlite_store.dart';
import 'package:gymapp/models/body_log.dart';
import 'package:gymapp/models/exercise.dart';
import 'package:gymapp/models/schedule.dart';
import 'package:gymapp/models/workout.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppDataStore.resetSqliteForTesting();
  });

  tearDown(AppDataStore.resetSqliteForTesting);

  test(
    'backup salvages valid siblings instead of dropping a whole collection',
    () {
      final good = _schedule('good-plan', 'Push').toJson();
      final malformed = <String, dynamic>{
        'id': 'bad-plan',
        'title': 'Broken',
        // missing week and createdAt on purpose
        'exercises': <dynamic>[],
      };

      final parsed = AppDataStore.parseBackupText(
        jsonEncode({
          'version': 6,
          'schedules': [good, malformed],
          'history': <dynamic>[],
          'bodyLogs': <dynamic>[],
        }),
      );

      expect(parsed.bundle.schedules.map((e) => e.id), ['good-plan']);
      expect(parsed.bundle.recoveredFromCorruption, isTrue);
    },
  );

  test(
    'future backup versions fail closed before any records are accepted',
    () {
      expect(
        () => AppDataStore.parseBackupText(
          jsonEncode({
            'version': 999,
            'schedules': <dynamic>[],
            'history': <dynamic>[],
          }),
        ),
        throwsA(isA<UnsupportedError>()),
      );
    },
  );

  test(
    'duplicate persistent ids are skipped rather than silently reassigned',
    () {
      final first = _schedule('duplicate-plan', 'Push');
      first.exercises = [
        _exercise('duplicate-exercise', 'Panca'),
        _exercise('duplicate-exercise', 'Panca duplicata'),
      ];
      final second = _schedule('duplicate-plan', 'Pull');

      final parsed = AppDataStore.parseBackupText(
        jsonEncode({
          'version': 6,
          'schedules': [first.toJson(), second.toJson()],
        }),
      );

      expect(parsed.bundle.schedules, hasLength(1));
      expect(parsed.bundle.schedules.single.title, 'Push');
      expect(parsed.bundle.schedules.single.exercises, hasLength(1));
      expect(
        parsed.bundle.schedules.single.exercises.single.id,
        'duplicate-exercise',
      );
      expect(parsed.bundle.recoveredFromCorruption, isTrue);
    },
  );

  test(
    'partial current session keeps safe rows and drops only broken children',
    () {
      final parsed = AppDataStore.parseBackupText(
        jsonEncode({
          'version': 6,
          'currentSession': {
            'id': 'current-partial',
            'startTime': '2026-09-05T10:00:00.000',
            // scheduleTitle/endTime intentionally absent
            'exercises': [
              {
                'id': 'work-bench',
                'name': 'Panca',
                'notes': '',
                'sets': [
                  {
                    'id': 'set-good',
                    'weight': 80,
                    'reps': 8,
                    'isCompleted': true,
                  },
                  {'id': 'set-broken', 'weight': 'not-a-number', 'reps': 8},
                ],
              },
              {'id': 'work-broken', 'sets': <dynamic>[]},
            ],
          },
        }),
      );

      final current = parsed.bundle.currentSession;
      expect(current, isNotNull);
      expect(current!.id, 'current-partial');
      expect(current.scheduleTitle, 'Allenamento recuperato');
      expect(current.endTime, current.startTime);
      expect(current.exercises, hasLength(1));
      expect(current.exercises.single.sets, hasLength(1));
      expect(current.exercises.single.sets.single.id, 'set-good');
      expect(parsed.bundle.recoveredFromCorruption, isTrue);
    },
  );

  test(
    'legacy preferences keep valid rows when one sibling is malformed',
    () async {
      final good = _schedule('legacy-good', 'Push').toJson();
      SharedPreferences.setMockInitialValues({
        AppDataKeys.schedules: jsonEncode([
          good,
          {'id': 'legacy-bad', 'title': 'Broken'},
        ]),
      });

      final bundle = await AppDataStore.loadBundle();

      expect(bundle.schedules.map((e) => e.id), contains('legacy-good'));
      expect(bundle.schedules.where((e) => e.id == 'legacy-bad'), isEmpty);
      expect(bundle.recoveredFromCorruption, isTrue);
    },
  );

  test(
    'missing legacy ids migrate deterministically without corruption state',
    () async {
      SharedPreferences.setMockInitialValues({
        AppDataKeys.schedules: jsonEncode([
          {
            'title': 'Legacy Push',
            'week': 1,
            'createdAt': '2026-09-01T00:00:00.000',
            'exercises': [
              {
                'name': 'Panca',
                'reps': 8,
                'set': 3,
                'notes': '',
                'weight': 80,
                'technique': 'none',
              },
            ],
          },
        ]),
      });

      final bundle = await AppDataStore.loadBundle();

      expect(bundle.recoveredFromCorruption, isFalse);
      expect(bundle.schedules.single.id, 'legacy_schedule_0');
      expect(
        bundle.schedules.single.exercises.single.id,
        'legacy_schedule_0_exercise_0',
      );
    },
  );

  test(
    'malformed legacy root falls back to the last coherent auto backup',
    () async {
      final backup = _schedule('backup-plan', 'Recovered Push');
      SharedPreferences.setMockInitialValues({
        AppDataKeys.schedules: '{broken-json',
        AppDataKeys.autoBackupJson: jsonEncode({
          'version': 6,
          'schedules': [backup.toJson()],
          'history': <dynamic>[],
          'bodyLogs': <dynamic>[],
        }),
      });

      final bundle = await AppDataStore.loadBundle();

      expect(bundle.schedules.single.id, 'backup-plan');
      expect(bundle.recoveredFromCorruption, isTrue);
    },
  );

  test(
    'corrupted preference runtime types fall back and clamp safely',
    () async {
      SharedPreferences.setMockInitialValues({
        AppPreferences.defaultBackoffReductionPercentKey: 'not-a-double',
        AppPreferences.workoutRemindersEnabledKey: 'yes',
        AppPreferences.workoutReminderHourKey: 99,
        AppPreferences.workoutReminderMinuteKey: -10,
      });

      expect(
        await AppPreferences.loadDefaultBackoffReductionPercent(),
        AppPreferences.defaultBackoffReductionPercent,
      );
      final reminder = await AppPreferences.loadWorkoutReminderSettings();
      expect(reminder.enabled, isFalse);
      expect(reminder.hour, 23);
      expect(reminder.minute, 0);
    },
  );

  test(
    'legacy to sqlite migration rolls back every table on injected failure',
    () async {
      final store = LocalSqliteStore(
        factoryOverride: databaseFactoryFfi,
        databasePath: inMemoryDatabasePath,
        migrationFaultInjector: (phase) async {
          if (phase == 'afterSchedules') {
            throw StateError('injected migration crash');
          }
        },
      );
      addTearDown(store.close);

      await expectLater(
        store.migrateLegacyData(
          schedules: [_schedule('atomic-plan', 'Push')],
          history: [_session('atomic-history', 80)],
          currentSession: _session('atomic-current', 82.5),
          bodyLogs: [
            BodyLog(
              id: 'atomic-body',
              date: DateTime(2026, 9, 5),
              bodyWeight: 80,
            ),
          ],
          customExercises: [_exercise('atomic-custom', 'Curl')],
          favoriteExerciseIds: {'atomic-custom'},
        ),
        throwsStateError,
      );

      expect(await store.migrationComplete, isFalse);
      expect(await store.loadSchedules(), isEmpty);
      expect(await store.loadHistory(), isEmpty);
      expect(await store.loadCurrentSession(), isNull);
      expect(await store.loadBodyLogs(), isEmpty);
      expect(await store.loadCustomExercises(), isEmpty);
      expect(await store.loadFavoriteExerciseIds(), isEmpty);
    },
  );

  test(
    'partial sqlite without marker is replaced from coherent legacy data',
    () async {
      final store = LocalSqliteStore(
        factoryOverride: databaseFactoryFfi,
        databasePath: inMemoryDatabasePath,
      );
      addTearDown(store.close);
      await store.replaceSchedules([
        _schedule('partial-sqlite', 'Wrong partial'),
      ]);

      final legacy = _schedule('legacy-source', 'Push');
      SharedPreferences.setMockInitialValues({
        AppDataKeys.schedules: jsonEncode([legacy.toJson()]),
      });
      AppDataStore.configureSqliteForTesting(store);

      final bundle = await AppDataStore.loadBundle();

      expect(await store.migrationComplete, isTrue);
      expect(bundle.schedules.map((e) => e.id), contains('legacy-source'));
      expect(
        bundle.schedules.map((e) => e.id),
        isNot(contains('partial-sqlite')),
      );
    },
  );

  test(
    'corrupt sqlite row falls back to coherent backup without hybrid data',
    () async {
      final store = LocalSqliteStore(
        factoryOverride: databaseFactoryFfi,
        databasePath: inMemoryDatabasePath,
      );
      addTearDown(store.close);
      await store.migrateLegacyData(
        schedules: [_schedule('sqlite-plan', 'Corrupt me')],
        history: const [],
        currentSession: null,
        bodyLogs: const [],
        customExercises: const [],
        favoriteExerciseIds: const <String>{},
      );
      await store.executeForTesting(
        "UPDATE schedules SET created_at = 'not-a-date' WHERE id = 'sqlite-plan'",
      );

      final backup = _schedule('backup-only', 'Safe backup');
      SharedPreferences.setMockInitialValues({
        AppDataKeys.autoBackupJson: jsonEncode({
          'version': 6,
          'schedules': [backup.toJson()],
          'history': <dynamic>[],
          'bodyLogs': <dynamic>[],
        }),
      });
      AppDataStore.configureSqliteForTesting(store);

      final bundle = await AppDataStore.loadBundle();

      expect(bundle.schedules.map((e) => e.id), ['backup-only']);
      expect(bundle.recoveredFromCorruption, isTrue);
    },
  );

  test(
    'wrong backup collection type is isolated while other collections survive',
    () {
      final history = _session('history-good', 75);
      final parsed = AppDataStore.parseBackupText(
        jsonEncode({
          'version': 6,
          'schedules': 'not-a-list',
          'history': [history.toJson()],
        }),
      );

      expect(parsed.bundle.schedules, isEmpty);
      expect(parsed.bundle.history.single.id, 'history-good');
      expect(parsed.bundle.recoveredFromCorruption, isTrue);
    },
  );
}

Schedule _schedule(String id, String title) {
  return Schedule(
    id: id,
    title: title,
    week: 1,
    createdAt: DateTime(2026, 9, 1),
    exercises: [_exercise('${id}_exercise', 'Panca')],
  );
}

Exercise _exercise(String id, String name) {
  return Exercise(
    id: id,
    name: name,
    reps: 8,
    set: 3,
    notes: '',
    weight: 80,
    technique: IntensityTechnique.none,
  );
}

WorkoutSession _session(String id, double weight) {
  return WorkoutSession(
    id: id,
    scheduleTitle: 'Push',
    startTime: DateTime(2026, 9, 5, 18),
    endTime: DateTime(2026, 9, 5, 19),
    exercises: [
      WorkoutExercise(
        id: '${id}_exercise',
        name: 'Panca',
        notes: '',
        technique: IntensityTechnique.none,
        sets: [
          ExerciseSet(
            id: '${id}_set',
            weight: weight,
            reps: 8,
            isCompleted: true,
          ),
        ],
      ),
    ],
  );
}
