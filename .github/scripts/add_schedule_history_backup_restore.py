from pathlib import Path


def replace_once(path, old, new):
    p = Path(path)
    text = p.read_text()
    if old not in text:
        raise SystemExit(f'anchor not found in {path}: {old[:120]!r}')
    p.write_text(text.replace(old, new, 1))

# Home: provenance-aware saves and full version-history backup restore.
replace_once(
    'lib/screens/home.dart',
    "import '../models/schedule.dart';\n",
    "import '../models/schedule.dart';\nimport '../models/schedule_version.dart';\n",
)
replace_once(
    'lib/screens/home.dart',
    "import '../workout_fatigue_analytics.dart';\n",
    "import '../workout_fatigue_analytics.dart';\nimport '../schedule_version_history.dart';\n",
)
replace_once(
    'lib/screens/home.dart',
    "  Future<void> _saveSchedules() async {\n    await AppDataStore.saveSchedules(schedules);\n    await _refreshWorkoutReminders();\n  }",
    "  Future<void> _saveSchedules({\n    ScheduleVersionSource source = ScheduleVersionSource.user,\n    String reason = '',\n  }) async {\n    await AppDataStore.saveSchedules(\n      schedules,\n      source: source,\n      reason: reason,\n    );\n    await _refreshWorkoutReminders();\n  }",
)
replace_once(
    'lib/screens/home.dart',
    "      _sortSchedules();\n      setState(() {});\n      await _saveSchedules();\n      await _showInfo(\n        'Importati $importedCount esercizi.",
    "      _sortSchedules();\n      setState(() {});\n      await _saveSchedules(\n        source: ScheduleVersionSource.import,\n        reason: 'CSV schedule import',\n      );\n      await _showInfo(\n        'Importati $importedCount esercizi.",
)
replace_once(
    'lib/screens/home.dart',
    "      final previousBodyLogs = _cloneBodyLogs(bodyLogs);\n      final previousCurrentSession = _savedSession == null",
    "      final previousBodyLogs = _cloneBodyLogs(bodyLogs);\n      final previousScheduleVersions =\n          await AppDataStore.loadScheduleVersions();\n      final previousCurrentSession = _savedSession == null",
)
replace_once(
    'lib/screens/home.dart',
    "      List<Schedule> restoredSchedules = [];\n      List<WorkoutSession> restoredHistory = [];",
    "      List<Schedule> restoredSchedules = [];\n      List<ScheduleVersion> restoredScheduleVersions = [];\n      List<WorkoutSession> restoredHistory = [];",
)
replace_once(
    'lib/screens/home.dart',
    "        restoredSchedules = (backupMap['schedules'] as List? ?? [])\n            .map((e) => Schedule.fromJson(Map<String, dynamic>.from(e as Map)))\n            .toList();\n        restoredHistory =",
    "        restoredSchedules = (backupMap['schedules'] as List? ?? [])\n            .map((e) => Schedule.fromJson(Map<String, dynamic>.from(e as Map)))\n            .toList();\n        restoredScheduleVersions =\n            (backupMap['scheduleVersions'] as List? ?? [])\n                .whereType<Map>()\n                .map(\n                  (e) => ScheduleVersion.fromJson(\n                    Map<String, dynamic>.from(e),\n                  ),\n                )\n                .toList();\n        restoredHistory =",
)
replace_once(
    'lib/screens/home.dart',
    "            'File: ${restoredSchedules.length} schede, ${restoredHistory.length} allenamenti, ${restoredBodyLogs.length} misure corpo, ${restoredCustomExercises?.length ?? 0} esercizi custom, ${restoredFavoriteExerciseIds?.length ?? 0} preferiti esercizi.",
    "            'File: ${restoredSchedules.length} schede, ${restoredScheduleVersions.length} versioni scheda, ${restoredHistory.length} allenamenti, ${restoredBodyLogs.length} misure corpo, ${restoredCustomExercises?.length ?? 0} esercizi custom, ${restoredFavoriteExerciseIds?.length ?? 0} preferiti esercizi.",
)
replace_once(
    'lib/screens/home.dart',
    "      final appliedCurrentSession = importMode == _BackupImportMode.merge\n          ? mergePreview.currentSession\n          : restoredCurrentSession;\n      final appliedCustomExercises =",
    "      final appliedCurrentSession = importMode == _BackupImportMode.merge\n          ? mergePreview.currentSession\n          : restoredCurrentSession;\n      final appliedScheduleVersions = importMode == _BackupImportMode.merge\n          ? mergeScheduleVersionHistories(\n              current: previousScheduleVersions,\n              incoming: restoredScheduleVersions,\n            )\n          : restoredScheduleVersions;\n      final appliedCustomExercises =",
)
replace_once(
    'lib/screens/home.dart',
    "      await _saveAllData();\n      if (appliedCurrentSession == null) {",
    "      await AppDataStore.saveAll(\n        schedules: schedules,\n        history: history,\n        bodyLogs: bodyLogs,\n        scheduleVersions: appliedScheduleVersions,\n        source: ScheduleVersionSource.import,\n        reason: importMode == _BackupImportMode.merge\n            ? 'Merged JSON backup'\n            : 'Restored JSON backup',\n      );\n      await _refreshWorkoutReminders();\n      if (appliedCurrentSession == null) {",
)
replace_once(
    'lib/screens/home.dart',
    "          _saveAllData();\n          if (previousCurrentSession == null) {",
    "          AppDataStore.saveAll(\n            schedules: schedules,\n            history: history,\n            bodyLogs: bodyLogs,\n            scheduleVersions: previousScheduleVersions,\n            source: ScheduleVersionSource.system,\n            reason: 'Undo backup restore',\n          );\n          _refreshWorkoutReminders();\n          if (previousCurrentSession == null) {",
)
# Auto-backup restore: preserve its exact historical timeline.
needle = """      await _saveAllData();
      if (_savedSession == null) {
        await AppDataStore.clearCurrentSession();
"""
replacement = """      await AppDataStore.saveAll(
        schedules: schedules,
        history: history,
        bodyLogs: bodyLogs,
        scheduleVersions: backupBundle.scheduleVersions,
        source: ScheduleVersionSource.import,
        reason: 'Restored auto-backup',
      );
      await _refreshWorkoutReminders();
      if (_savedSession == null) {
        await AppDataStore.clearCurrentSession();
"""
replace_once('lib/screens/home.dart', needle, replacement)

# Unit coverage for merging independent historical chains while retaining IDs.
path = Path('test/schedule_version_history_test.dart')
text = path.read_text()
anchor = "\n  test('legacy load backfills version one and persists the pointer', () async {"
test = r'''

  test('import merge keeps stable version ids and builds one ordered chain', () {
    final schedule = _schedule();
    final local = ScheduleVersion.capture(
      schedule: schedule,
      versionNumber: 1,
      createdAt: DateTime(2026, 7, 1),
      source: ScheduleVersionSource.user,
    );
    schedule.exercises.single.weight = 82.5;
    final imported = ScheduleVersion.capture(
      schedule: schedule,
      versionNumber: 1,
      createdAt: DateTime(2026, 8, 1),
      source: ScheduleVersionSource.aiCoach,
    );
    final deletedSchedule = Schedule(
      id: 'old-program',
      title: 'Old',
      week: 1,
      createdAt: DateTime(2026, 5, 1),
      exercises: const [],
    );
    final historicalOnly = ScheduleVersion.capture(
      schedule: deletedSchedule,
      versionNumber: 1,
      createdAt: DateTime(2026, 5, 1),
      source: ScheduleVersionSource.import,
    );

    final merged = mergeScheduleVersionHistories(
      current: [local],
      incoming: [imported, historicalOnly],
    );
    final push = merged.where((entry) => entry.scheduleId == 'push').toList();

    expect(push.map((entry) => entry.id), [local.id, imported.id]);
    expect(push.map((entry) => entry.versionNumber), [1, 2]);
    expect(push.last.parentVersionId, local.id);
    expect(
      merged.any((entry) => entry.id == historicalOnly.id),
      isTrue,
      reason: 'Deleted schedules still belong to long-term program history',
    );
  });
'''
if anchor not in text:
    raise SystemExit('schedule version merge test anchor not found')
path.write_text(text.replace(anchor, test + anchor, 1))

# Explicit SQLite v1 -> v2 upgrade smoke test.
path = Path('test/local_sqlite_store_test.dart')
text = path.read_text()
text = text.replace("import 'package:flutter_test/flutter_test.dart';", "import 'dart:io';\n\nimport 'package:flutter_test/flutter_test.dart';", 1)
anchor = "\n  test('current-session writes do not require rewriting history', () async {"
test = r'''

  test('existing v1 sqlite database upgrades without losing base tables', () async {
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
          await db.execute('''
            CREATE TABLE workout_sessions (
              id TEXT PRIMARY KEY,
              session_kind TEXT NOT NULL,
              position INTEGER NOT NULL,
              schedule_id TEXT,
              schedule_title TEXT NOT NULL,
              start_time TEXT NOT NULL,
              end_time TEXT NOT NULL
            )
          ''');
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
    final scheduleColumns = await upgraded.rawQuery('PRAGMA table_info(schedules)');
    final workoutColumns = await upgraded.rawQuery(
      'PRAGMA table_info(workout_sessions)',
    );
    final versionTable = await upgraded.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name='schedule_versions'",
    );

    expect(
      scheduleColumns.map((row) => row['name']),
      containsAll(['current_version_id', 'current_version_number']),
    );
    expect(
      workoutColumns.map((row) => row['name']),
      contains('schedule_version_id'),
    );
    expect(versionTable, hasLength(1));
    expect(
      await upgraded.query('schedules', where: 'id = ?', whereArgs: ['legacy-plan']),
      hasLength(1),
    );
  });
'''
if anchor not in text:
    raise SystemExit('sqlite upgrade test anchor not found')
path.write_text(text.replace(anchor, test + anchor, 1))
