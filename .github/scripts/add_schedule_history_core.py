from pathlib import Path


def replace_once(path, old, new):
    p = Path(path)
    text = p.read_text()
    if old not in text:
        raise SystemExit(f'anchor not found in {path}: {old[:100]!r}')
    p.write_text(text.replace(old, new, 1))

# Schedule version pointers.
replace_once(
    'lib/models/schedule.dart',
    "  String cycleNotes;\n",
    "  String cycleNotes;\n  String? currentVersionId;\n  int currentVersionNumber;\n",
)
replace_once(
    'lib/models/schedule.dart',
    "    this.cycleNotes = '',\n  }) : trainingWeekdays",
    "    this.cycleNotes = '',\n    this.currentVersionId,\n    this.currentVersionNumber = 0,\n  }) : trainingWeekdays",
)
replace_once(
    'lib/models/schedule.dart',
    "    'cycleNotes': cycleNotes,\n  };",
    "    'cycleNotes': cycleNotes,\n    'currentVersionId': currentVersionId,\n    'currentVersionNumber': currentVersionNumber,\n  };",
)
replace_once(
    'lib/models/schedule.dart',
    "    cycleNotes: json['cycleNotes'] as String? ?? '',\n  );",
    "    cycleNotes: json['cycleNotes'] as String? ?? '',\n    currentVersionId: json['currentVersionId'] as String?,\n    currentVersionNumber: (json['currentVersionNumber'] as num?)?.toInt() ?? 0,\n  );",
)

# Workout -> exact schedule version provenance.
replace_once(
    'lib/models/workout.dart',
    "  String? scheduleId;\n  String scheduleTitle;",
    "  String? scheduleId;\n  String? scheduleVersionId;\n  String scheduleTitle;",
)
replace_once(
    'lib/models/workout.dart',
    "    this.scheduleId,\n    required this.scheduleTitle,",
    "    this.scheduleId,\n    this.scheduleVersionId,\n    required this.scheduleTitle,",
)
replace_once(
    'lib/models/workout.dart',
    "    'scheduleId': scheduleId,\n    'scheduleTitle': scheduleTitle,",
    "    'scheduleId': scheduleId,\n    'scheduleVersionId': scheduleVersionId,\n    'scheduleTitle': scheduleTitle,",
)
replace_once(
    'lib/models/workout.dart',
    "    scheduleId: json['scheduleId'] as String?,\n    scheduleTitle:",
    "    scheduleId: json['scheduleId'] as String?,\n    scheduleVersionId: json['scheduleVersionId'] as String?,\n    scheduleTitle:",
)

replace_once(
    'lib/active_workout_session_builder.dart',
    "      scheduleId: schedule.id,\n      scheduleTitle: schedule.title,",
    "      scheduleId: schedule.id,\n      scheduleVersionId: schedule.currentVersionId,\n      scheduleTitle: schedule.title,",
)

# SQLite schema v2.
replace_once(
    'lib/local_sqlite_store.dart',
    "import 'models/schedule.dart';\n",
    "import 'models/schedule.dart';\nimport 'models/schedule_version.dart';\n",
)
replace_once(
    'lib/local_sqlite_store.dart',
    "        version: 1,\n        onConfigure:",
    "        version: 2,\n        onConfigure:",
)
replace_once(
    'lib/local_sqlite_store.dart',
    "        onCreate: _createSchema,\n",
    "        onCreate: _createSchema,\n        onUpgrade: _upgradeSchema,\n",
)
replace_once(
    'lib/local_sqlite_store.dart',
    "        cycle_number INTEGER NOT NULL,\n        cycle_notes TEXT NOT NULL\n",
    "        cycle_number INTEGER NOT NULL,\n        cycle_notes TEXT NOT NULL,\n        current_version_id TEXT,\n        current_version_number INTEGER NOT NULL DEFAULT 0\n",
)
replace_once(
    'lib/local_sqlite_store.dart',
    "    await db.execute('''\n      CREATE TABLE workout_sessions (",
    "    await db.execute('''\n      CREATE TABLE schedule_versions (\n        id TEXT PRIMARY KEY,\n        schedule_id TEXT NOT NULL,\n        version_number INTEGER NOT NULL,\n        created_at TEXT NOT NULL,\n        source TEXT NOT NULL,\n        parent_version_id TEXT,\n        reason TEXT NOT NULL,\n        snapshot_json TEXT NOT NULL\n      )\n    ''');\n    await db.execute('''\n      CREATE TABLE workout_sessions (",
)
replace_once(
    'lib/local_sqlite_store.dart',
    "        schedule_id TEXT,\n        schedule_title TEXT NOT NULL,",
    "        schedule_id TEXT,\n        schedule_version_id TEXT,\n        schedule_title TEXT NOT NULL,",
)
replace_once(
    'lib/local_sqlite_store.dart',
    "    await db.execute(\n      'CREATE INDEX idx_schedule_exercises_schedule ON schedule_exercises(schedule_id, position)',\n    );",
    "    await db.execute(\n      'CREATE INDEX idx_schedule_exercises_schedule ON schedule_exercises(schedule_id, position)',\n    );\n    await db.execute(\n      'CREATE UNIQUE INDEX idx_schedule_versions_number ON schedule_versions(schedule_id, version_number)',\n    );",
)
upgrade = r'''

  Future<void> _upgradeSchema(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('ALTER TABLE schedules ADD COLUMN current_version_id TEXT');
      await db.execute(
        'ALTER TABLE schedules ADD COLUMN current_version_number INTEGER NOT NULL DEFAULT 0',
      );
      await db.execute(
        'ALTER TABLE workout_sessions ADD COLUMN schedule_version_id TEXT',
      );
      await db.execute('''
        CREATE TABLE schedule_versions (
          id TEXT PRIMARY KEY,
          schedule_id TEXT NOT NULL,
          version_number INTEGER NOT NULL,
          created_at TEXT NOT NULL,
          source TEXT NOT NULL,
          parent_version_id TEXT,
          reason TEXT NOT NULL,
          snapshot_json TEXT NOT NULL
        )
      ''');
      await db.execute(
        'CREATE UNIQUE INDEX idx_schedule_versions_number ON schedule_versions(schedule_id, version_number)',
      );
    }
  }
'''
replace_once(
    'lib/local_sqlite_store.dart',
    "\n  Future<bool> get migrationComplete async {",
    upgrade + "\n  Future<bool> get migrationComplete async {",
)
replace_once(
    'lib/local_sqlite_store.dart',
    "    required Set<String> favoriteExerciseIds,\n  }) async {\n    await replaceSchedules(schedules);",
    "    required Set<String> favoriteExerciseIds,\n    List<ScheduleVersion> scheduleVersions = const <ScheduleVersion>[],\n  }) async {\n    await replaceSchedules(schedules);\n    await replaceScheduleVersions(scheduleVersions);",
)

# Atomic current schedule + historical version state.
methods = r'''

  Future<void> replaceScheduleState(
    List<Schedule> schedules,
    List<ScheduleVersion> versions,
  ) async {
    final db = await _db;
    await db.transaction((txn) async {
      await txn.delete('schedules');
      for (var i = 0; i < schedules.length; i += 1) {
        await _insertSchedule(txn, schedules[i], i);
      }
      await txn.delete('schedule_versions');
      for (final version in versions) {
        await _insertScheduleVersion(txn, version);
      }
    });
  }

  Future<void> replaceScheduleVersions(List<ScheduleVersion> versions) async {
    final db = await _db;
    await db.transaction((txn) async {
      await txn.delete('schedule_versions');
      for (final version in versions) {
        await _insertScheduleVersion(txn, version);
      }
    });
  }

  Future<void> _insertScheduleVersion(
    DatabaseExecutor db,
    ScheduleVersion version,
  ) async {
    await db.insert('schedule_versions', {
      'id': version.id,
      'schedule_id': version.scheduleId,
      'version_number': version.versionNumber,
      'created_at': version.createdAt.toIso8601String(),
      'source': version.source.name,
      'parent_version_id': version.parentVersionId,
      'reason': version.reason,
      'snapshot_json': jsonEncode(version.snapshot),
    });
  }
'''
replace_once(
    'lib/local_sqlite_store.dart',
    "\n  Future<void> _insertSchedule(\n",
    methods + "\n  Future<void> _insertSchedule(\n",
)
replace_once(
    'lib/local_sqlite_store.dart',
    "      'cycle_notes': schedule.cycleNotes,\n    });",
    "      'cycle_notes': schedule.cycleNotes,\n      'current_version_id': schedule.currentVersionId,\n      'current_version_number': schedule.currentVersionNumber,\n    });",
)
replace_once(
    'lib/local_sqlite_store.dart',
    "      'schedule_id': session.scheduleId,\n      'schedule_title': session.scheduleTitle,",
    "      'schedule_id': session.scheduleId,\n      'schedule_version_id': session.scheduleVersionId,\n      'schedule_title': session.scheduleTitle,",
)
# loadAll return shape.
replace_once(
    'lib/local_sqlite_store.dart',
    "      List<WorkoutSession> history,\n      WorkoutSession? currentSession,",
    "      List<WorkoutSession> history,\n      List<ScheduleVersion> scheduleVersions,\n      WorkoutSession? currentSession,",
)
replace_once(
    'lib/local_sqlite_store.dart',
    "    final history = await loadHistory();\n    final current = await loadCurrentSession();",
    "    final history = await loadHistory();\n    final scheduleVersions = await loadScheduleVersions();\n    final current = await loadCurrentSession();",
)
replace_once(
    'lib/local_sqlite_store.dart',
    "      history: history,\n      currentSession: current,",
    "      history: history,\n      scheduleVersions: scheduleVersions,\n      currentSession: current,",
)
replace_once(
    'lib/local_sqlite_store.dart',
    "          cycleNotes: row['cycle_notes'] as String,\n        ),",
    "          cycleNotes: row['cycle_notes'] as String,\n          currentVersionId: row['current_version_id'] as String?,\n          currentVersionNumber: row['current_version_number'] as int? ?? 0,\n        ),",
)
load_versions = r'''

  Future<List<ScheduleVersion>> loadScheduleVersions() async {
    final db = await _db;
    final rows = await db.query(
      'schedule_versions',
      orderBy: 'schedule_id ASC, version_number ASC, created_at ASC',
    );
    return rows.map((row) {
      ScheduleVersionSource source;
      try {
        source = ScheduleVersionSource.values.byName(row['source'] as String);
      } catch (_) {
        source = ScheduleVersionSource.system;
      }
      return ScheduleVersion(
        id: row['id'] as String,
        scheduleId: row['schedule_id'] as String,
        versionNumber: row['version_number'] as int,
        createdAt: DateTime.parse(row['created_at'] as String),
        source: source,
        parentVersionId: row['parent_version_id'] as String?,
        reason: row['reason'] as String,
        snapshot: Map<String, dynamic>.from(
          jsonDecode(row['snapshot_json'] as String) as Map,
        ),
      );
    }).toList();
  }
'''
replace_once(
    'lib/local_sqlite_store.dart',
    "\n  Future<List<WorkoutSession>> loadHistory() => _loadSessions('history');",
    load_versions + "\n  Future<List<WorkoutSession>> loadHistory() => _loadSessions('history');",
)
replace_once(
    'lib/local_sqlite_store.dart',
    "          scheduleId: row['schedule_id'] as String?,\n          scheduleTitle:",
    "          scheduleId: row['schedule_id'] as String?,\n          scheduleVersionId: row['schedule_version_id'] as String?,\n          scheduleTitle:",
)

# AppDataStore: persist and backfill schedule versions.
replace_once(
    'lib/app_data_store.dart',
    "import 'models/schedule.dart';\n",
    "import 'models/schedule.dart';\nimport 'models/schedule_version.dart';\n",
)
replace_once(
    'lib/app_data_store.dart',
    "import 'models/workout.dart';\n",
    "import 'models/workout.dart';\nimport 'schedule_version_history.dart';\n",
)
replace_once(
    'lib/app_data_store.dart',
    "  static const schedules = 'schedules';\n",
    "  static const schedules = 'schedules';\n  static const scheduleVersions = 'schedule_versions';\n",
)
replace_once(
    'lib/app_data_store.dart',
    "  final List<WorkoutSession> history;\n  final WorkoutSession? currentSession;",
    "  final List<WorkoutSession> history;\n  final List<ScheduleVersion> scheduleVersions;\n  final WorkoutSession? currentSession;",
)
replace_once(
    'lib/app_data_store.dart',
    "    required this.history,\n    required this.currentSession,",
    "    required this.history,\n    this.scheduleVersions = const <ScheduleVersion>[],\n    required this.currentSession,",
)
replace_once(
    'lib/app_data_store.dart',
    "      history: checkedList(AppDataKeys.history, WorkoutSession.fromJson),\n      currentSession: current,",
    "      history: checkedList(AppDataKeys.history, WorkoutSession.fromJson),\n      scheduleVersions: checkedList(\n        AppDataKeys.scheduleVersions,\n        ScheduleVersion.fromJson,\n      ),\n      currentSession: current,",
)
replace_once(
    'lib/app_data_store.dart',
    "        history: (backupMap['history'] as List? ?? [])",
    "        scheduleVersions: (backupMap['scheduleVersions'] as List? ?? [])\n            .whereType<Map>()\n            .map(\n              (entry) => ScheduleVersion.fromJson(\n                Map<String, dynamic>.from(entry),\n              ),\n            )\n            .toList(),\n        history: (backupMap['history'] as List? ?? [])",
)
replace_once(
    'lib/app_data_store.dart',
    "      'version': 5,\n      'auto': true,",
    "      'version': 6,\n      'auto': true,",
)
# first occurrence after schedules in legacy backup
replace_once(
    'lib/app_data_store.dart',
    "      'schedules': _decodeJsonOr(prefs, AppDataKeys.schedules, []),\n      'history':",
    "      'schedules': _decodeJsonOr(prefs, AppDataKeys.schedules, []),\n      'scheduleVersions': _decodeJsonOr(\n        prefs,\n        AppDataKeys.scheduleVersions,\n        [],\n      ),\n      'history':",
)
# sqlite backup's version and versions data
replace_once(
    'lib/app_data_store.dart',
    "      'version': 5,\n      'auto': true,\n      'storage': 'sqlite',",
    "      'version': 6,\n      'auto': true,\n      'storage': 'sqlite',",
)
replace_once(
    'lib/app_data_store.dart',
    "      'schedules': snapshot.schedules.map((e) => e.toJson()).toList(),\n      'history':",
    "      'schedules': snapshot.schedules.map((e) => e.toJson()).toList(),\n      'scheduleVersions': snapshot.scheduleVersions\n          .map((e) => e.toJson())\n          .toList(),\n      'history':",
)
replace_once(
    'lib/app_data_store.dart',
    "      schedules: legacy.schedules,\n      history: legacy.history,",
    "      schedules: legacy.schedules,\n      history: legacy.history,\n      scheduleVersions: legacy.scheduleVersions,",
)

# Replace loadBundle and add backfill/raw helpers.
start = Path('lib/app_data_store.dart').read_text()
old_start = start.index('  static Future<AppDataBundle> loadBundle() async {')
old_end = start.index('\n  static Future<List<WorkoutSession>> loadHistory()', old_start)
new_block = r'''  static Future<AppDataBundle> loadBundle() async {
    if (_sqliteSupported) {
      try {
        await _ensureSqliteMigration();
        final data = await _sqliteStore.loadAll();
        final bundle = AppDataBundle(
          schedules: data.schedules,
          history: data.history,
          scheduleVersions: data.scheduleVersions,
          currentSession: data.currentSession,
          bodyLogs: data.bodyLogs,
          customExercises: data.customExercises,
          favoriteExerciseIds: data.favoriteExerciseIds,
          recoveredFromCorruption: false,
        );
        return _backfillScheduleHistory(bundle, persistSqlite: true);
      } catch (_) {
        final prefs = await SharedPreferences.getInstance();
        final fallback = _bundleFromAutoBackup(prefs) ?? _loadLegacyBundle(prefs);
        return _backfillScheduleHistory(fallback, persistSqlite: false);
      }
    }
    final prefs = await SharedPreferences.getInstance();
    return _backfillScheduleHistory(
      _loadLegacyBundle(prefs),
      persistSqlite: false,
    );
  }

  static Future<AppDataBundle> _backfillScheduleHistory(
    AppDataBundle bundle, {
    required bool persistSqlite,
  }) async {
    final reconciliation = reconcileScheduleVersions(
      schedules: bundle.schedules,
      existingVersions: bundle.scheduleVersions,
      source: ScheduleVersionSource.migration,
      reason: 'Initial historical snapshot',
    );
    if (!reconciliation.changed) return bundle;

    if (persistSqlite) {
      await _sqliteStore.replaceScheduleState(
        bundle.schedules,
        reconciliation.versions,
      );
      await _writeSqliteAutoBackup(force: true);
    } else {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        AppDataKeys.schedules,
        jsonEncode(bundle.schedules.map((e) => e.toJson()).toList()),
      );
      await prefs.setString(
        AppDataKeys.scheduleVersions,
        jsonEncode(reconciliation.versions.map((e) => e.toJson()).toList()),
      );
      await _writeLegacyAutoBackupSnapshot(prefs);
    }

    return AppDataBundle(
      schedules: bundle.schedules,
      history: bundle.history,
      scheduleVersions: reconciliation.versions,
      currentSession: bundle.currentSession,
      bodyLogs: bundle.bodyLogs,
      customExercises: bundle.customExercises,
      favoriteExerciseIds: bundle.favoriteExerciseIds,
      recoveredFromCorruption: bundle.recoveredFromCorruption,
    );
  }

  static List<ScheduleVersion> _legacyScheduleVersions(SharedPreferences prefs) {
    return _safeLegacyList(
      prefs,
      AppDataKeys.scheduleVersions,
      ScheduleVersion.fromJson,
    );
  }

  static Future<List<ScheduleVersion>> loadScheduleVersions() async {
    return (await loadBundle()).scheduleVersions;
  }
'''
start = start[:old_start] + new_block + start[old_end:]
Path('lib/app_data_store.dart').write_text(start)

# Replace saveSchedules implementation.
text = Path('lib/app_data_store.dart').read_text()
s0 = text.index('  static Future<void> saveSchedules(List<Schedule> schedules) async {')
s1 = text.index('\n  static Future<void> saveHistory', s0)
new_save = r'''  static Future<void> saveSchedules(
    List<Schedule> schedules, {
    ScheduleVersionSource source = ScheduleVersionSource.user,
    String reason = '',
  }) async {
    if (_sqliteSupported) {
      try {
        await _ensureSqliteMigration();
        final reconciliation = reconcileScheduleVersions(
          schedules: schedules,
          existingVersions: await _sqliteStore.loadScheduleVersions(),
          source: source,
          reason: reason,
        );
        await _sqliteStore.replaceScheduleState(
          schedules,
          reconciliation.versions,
        );
        await _writeSqliteAutoBackup(force: true);
        return;
      } catch (_) {}
    }
    final prefs = await SharedPreferences.getInstance();
    final reconciliation = reconcileScheduleVersions(
      schedules: schedules,
      existingVersions: _legacyScheduleVersions(prefs),
      source: source,
      reason: reason,
    );
    await prefs.setString(
      AppDataKeys.schedules,
      jsonEncode(schedules.map((e) => e.toJson()).toList()),
    );
    await prefs.setString(
      AppDataKeys.scheduleVersions,
      jsonEncode(reconciliation.versions.map((e) => e.toJson()).toList()),
    );
    await _writeLegacyAutoBackupSnapshot(prefs);
  }
'''
Path('lib/app_data_store.dart').write_text(text[:s0] + new_save + text[s1:])

# Export includes history and schedule versions, version 6.
replace_once(
    'lib/app_data_store.dart',
    "    final customExercises = await loadCustomExercises();\n    return {\n      'version': 5,",
    "    final customExercises = await loadCustomExercises();\n    final scheduleVersions = await loadScheduleVersions();\n    return {\n      'version': 6,",
)
replace_once(
    'lib/app_data_store.dart',
    "      'schedules': schedules.map((e) => e.toJson()).toList(),\n      'history': history.map",
    "      'schedules': schedules.map((e) => e.toJson()).toList(),\n      'scheduleVersions': scheduleVersions.map((e) => e.toJson()).toList(),\n      'history': history.map",
)

# Replace saveAll with version-aware implementation.
text = Path('lib/app_data_store.dart').read_text()
a0 = text.index('  static Future<void> saveAll({')
a1 = text.rindex('\n}', a0)
new_all = r'''  static Future<void> saveAll({
    required List<Schedule> schedules,
    required List<WorkoutSession> history,
    required List<BodyLog> bodyLogs,
    List<ScheduleVersion>? scheduleVersions,
    ScheduleVersionSource source = ScheduleVersionSource.user,
    String reason = '',
  }) async {
    if (_sqliteSupported) {
      try {
        await _ensureSqliteMigration();
        final existing = scheduleVersions ?? await _sqliteStore.loadScheduleVersions();
        final reconciliation = reconcileScheduleVersions(
          schedules: schedules,
          existingVersions: existing,
          source: source,
          reason: reason,
        );
        await _sqliteStore.replaceScheduleState(
          schedules,
          reconciliation.versions,
        );
        await _sqliteStore.replaceHistory(history);
        await _sqliteStore.replaceBodyLogs(bodyLogs);
        await _writeSqliteAutoBackup(force: true);
        return;
      } catch (_) {}
    }
    final prefs = await SharedPreferences.getInstance();
    final reconciliation = reconcileScheduleVersions(
      schedules: schedules,
      existingVersions: scheduleVersions ?? _legacyScheduleVersions(prefs),
      source: source,
      reason: reason,
    );
    await prefs.setString(
      AppDataKeys.schedules,
      jsonEncode(schedules.map((e) => e.toJson()).toList()),
    );
    await prefs.setString(
      AppDataKeys.scheduleVersions,
      jsonEncode(reconciliation.versions.map((e) => e.toJson()).toList()),
    );
    await prefs.setString(
      AppDataKeys.history,
      jsonEncode(history.map((e) => e.toJson()).toList()),
    );
    await prefs.setString(
      AppDataKeys.bodyLogs,
      jsonEncode(bodyLogs.map((e) => e.toJson()).toList()),
    );
    await _writeLegacyAutoBackupSnapshot(prefs);
  }
'''
Path('lib/app_data_store.dart').write_text(text[:a0] + new_all + text[a1:])

# Mark AI/deterministic persisted mutations with provenance.
replace_once(
    'lib/screens/ai_coach.dart',
    "import '../models/schedule.dart';\n",
    "import '../models/schedule.dart';\nimport '../models/schedule_version.dart';\n",
)
replace_once(
    'lib/screens/ai_coach.dart',
    "        await AppDataStore.saveSchedules(widget.schedules);",
    "        await AppDataStore.saveSchedules(\n          widget.schedules,\n          source: ScheduleVersionSource.aiCoach,\n          reason: 'AI Coach plan adjustment approved by user',\n        );",
)
replace_once(
    'lib/screens/session_summary.dart',
    "import '../models/exercise.dart';\n",
    "import '../models/exercise.dart';\nimport '../models/schedule_version.dart';\n",
)
replace_once(
    'lib/screens/session_summary.dart',
    "        await AppDataStore.saveSchedules(latestBundle.schedules);",
    "        await AppDataStore.saveSchedules(\n          latestBundle.schedules,\n          source: ScheduleVersionSource.system,\n          reason: 'Reviewed next-session progression plan',\n        );",
)

# Tests.
Path('test/schedule_version_history_test.dart').write_text(r'''import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gymapp/active_workout_session_builder.dart';
import 'package:gymapp/app_data_store.dart';
import 'package:gymapp/models/exercise.dart';
import 'package:gymapp/models/schedule.dart';
import 'package:gymapp/models/schedule_version.dart';
import 'package:gymapp/schedule_version_history.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('reconciliation creates versions only for structural changes', () {
    final schedule = _schedule();
    final first = reconcileScheduleVersions(
      schedules: [schedule],
      existingVersions: const [],
      source: ScheduleVersionSource.migration,
      now: () => DateTime(2026, 8, 1),
    );

    expect(first.created.single.versionNumber, 1);
    expect(schedule.currentVersionId, first.created.single.id);
    expect(schedule.currentVersionNumber, 1);

    final unchanged = reconcileScheduleVersions(
      schedules: [schedule],
      existingVersions: first.versions,
      source: ScheduleVersionSource.user,
      now: () => DateTime(2026, 8, 2),
    );
    expect(unchanged.created, isEmpty);

    schedule.exercises.single.weight = 82.5;
    final changed = reconcileScheduleVersions(
      schedules: [schedule],
      existingVersions: first.versions,
      source: ScheduleVersionSource.aiCoach,
      reason: 'Approved coach change',
      now: () => DateTime(2026, 8, 3),
    );
    final second = changed.created.single;
    expect(second.versionNumber, 2);
    expect(second.parentVersionId, first.created.single.id);
    expect(second.source, ScheduleVersionSource.aiCoach);
    expect(second.restoreSchedule().exercises.single.weight, 82.5);
  });

  test('legacy load backfills version one and persists the pointer', () async {
    final schedule = _schedule();
    SharedPreferences.setMockInitialValues({
      AppDataKeys.schedules: jsonEncode([schedule.toJson()]),
      AppDataKeys.history: '[]',
      AppDataKeys.bodyLogs: '[]',
    });

    final bundle = await AppDataStore.loadBundle();
    expect(bundle.scheduleVersions, hasLength(1));
    expect(bundle.scheduleVersions.single.source, ScheduleVersionSource.migration);
    expect(bundle.schedules.single.currentVersionNumber, 1);
    expect(
      bundle.schedules.single.currentVersionId,
      bundle.scheduleVersions.single.id,
    );

    final prefs = await SharedPreferences.getInstance();
    final persisted = jsonDecode(
      prefs.getString(AppDataKeys.scheduleVersions)!,
    ) as List;
    expect(persisted, hasLength(1));
  });

  test('saveSchedules creates v2 once and repeated save is idempotent', () async {
    final schedule = _schedule();
    await AppDataStore.saveSchedules([schedule]);
    var versions = await AppDataStore.loadScheduleVersions();
    expect(versions, hasLength(1));

    schedule.exercises.single.reps = 9;
    await AppDataStore.saveSchedules(
      [schedule],
      source: ScheduleVersionSource.aiCoach,
      reason: 'Coach proposal accepted',
    );
    versions = await AppDataStore.loadScheduleVersions();
    expect(versions, hasLength(2));
    expect(versions.last.versionNumber, 2);
    expect(versions.last.source, ScheduleVersionSource.aiCoach);

    await AppDataStore.saveSchedules([schedule]);
    expect(await AppDataStore.loadScheduleVersions(), hasLength(2));
  });

  test('new workout binds to the exact current schedule version', () async {
    final schedule = _schedule();
    await AppDataStore.saveSchedules([schedule]);
    final persisted = (await AppDataStore.loadBundle()).schedules.single;
    final session = ActiveWorkoutSessionBuilder(
      history: const [],
      bodyLogs: const [],
      now: () => DateTime(2026, 8, 26, 18),
    ).buildFromSchedule(persisted);

    expect(session.scheduleVersionId, persisted.currentVersionId);
    expect(session.toJson()['scheduleVersionId'], isNotNull);
  });

  test('export payload includes historical schedule versions', () async {
    final schedule = _schedule();
    await AppDataStore.saveSchedules([schedule]);
    schedule.exercises.single.weight = 85;
    await AppDataStore.saveSchedules([schedule]);

    final payload = await AppDataStore.buildExportPayload(
      schedules: [schedule],
      history: const [],
      bodyLogs: const [],
    );
    expect(payload['version'], 6);
    expect(payload['scheduleVersions'], hasLength(2));
  });
}

Schedule _schedule() {
  return Schedule(
    id: 'push',
    title: 'Push',
    week: 1,
    createdAt: DateTime(2026, 8, 1),
    exercises: [
      Exercise(
        id: 'bench',
        name: 'Panca',
        reps: 8,
        set: 3,
        notes: '',
        weight: 80,
        muscleGroup: MuscleGroup.chest,
      ),
    ],
  );
}
''')

# Extend SQLite round-trip for versions and session provenance.
replace_once(
    'test/local_sqlite_store_test.dart',
    "import 'package:gymapp/models/schedule.dart';\n",
    "import 'package:gymapp/models/schedule.dart';\nimport 'package:gymapp/models/schedule_version.dart';\n",
)
replace_once(
    'test/local_sqlite_store_test.dart',
    "      final session = WorkoutSession(\n        id: 'session-1',\n        scheduleId: 'push',",
    "      final version = ScheduleVersion.capture(\n        schedule: schedule,\n        versionNumber: 1,\n        createdAt: DateTime(2026, 8, 1),\n        source: ScheduleVersionSource.migration,\n      );\n      schedule.currentVersionId = version.id;\n      schedule.currentVersionNumber = 1;\n      final session = WorkoutSession(\n        id: 'session-1',\n        scheduleId: 'push',\n        scheduleVersionId: version.id,",
)
replace_once(
    'test/local_sqlite_store_test.dart',
    "        favoriteExerciseIds: {'bench-plan'},\n      );",
    "        favoriteExerciseIds: {'bench-plan'},\n        scheduleVersions: [version],\n      );",
)
replace_once(
    'test/local_sqlite_store_test.dart',
    "      expect(data.schedules.single.id, 'push');\n",
    "      expect(data.schedules.single.id, 'push');\n      expect(data.schedules.single.currentVersionId, version.id);\n      expect(data.scheduleVersions.single.id, version.id);\n      expect(data.history.single.scheduleVersionId, version.id);\n",
)
