from pathlib import Path

# -----------------------------------------------------------------------------
# AppDataStore: route all boundary decoding through the recovery decoder, expose
# a test seam for SQLite, and never bless a partial legacy migration as complete.
# -----------------------------------------------------------------------------
path = Path('lib/app_data_store.dart')
text = path.read_text()
text = text.replace(
    "import 'local_sqlite_store.dart';\n",
    "import 'local_sqlite_store.dart';\nimport 'persistence_recovery.dart';\n",
    1,
)

bundle_end = """  });
}

class AppDataStore {
"""
bundle_repl = """  });

  bool get hasAnyData =>
      schedules.isNotEmpty ||
      history.isNotEmpty ||
      scheduleVersions.isNotEmpty ||
      currentSession != null ||
      bodyLogs.isNotEmpty ||
      customExercises.isNotEmpty ||
      favoriteExerciseIds.isNotEmpty;
}

class AppDataImportPayload {
  final AppDataBundle bundle;
  final bool includesCustomExercises;
  final bool includesFavoriteExerciseIds;
  final int? version;

  const AppDataImportPayload({
    required this.bundle,
    required this.includesCustomExercises,
    required this.includesFavoriteExerciseIds,
    required this.version,
  });
}

class AppDataStore {
"""
assert text.count(bundle_end) == 1
text = text.replace(bundle_end, bundle_repl, 1)

old_store_head = """class AppDataStore {
  static LocalSqliteStore? _sqlite;

  static bool get _sqliteSupported {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS;
  }
"""
new_store_head = """class AppDataStore {
  static LocalSqliteStore? _sqlite;
  static bool? _sqliteSupportedOverride;

  @visibleForTesting
  static void configureSqliteForTesting(LocalSqliteStore store) {
    _sqlite = store;
    _sqliteSupportedOverride = true;
  }

  @visibleForTesting
  static void resetSqliteForTesting() {
    _sqlite = null;
    _sqliteSupportedOverride = null;
  }

  static bool get _sqliteSupported {
    final override = _sqliteSupportedOverride;
    if (override != null) return override;
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS;
  }
"""
assert text.count(old_store_head) == 1
text = text.replace(old_store_head, new_store_head, 1)

start = text.index("  static dynamic _decodeJsonOr(")
end = text.index("  static Future<void> _writeLegacyAutoBackupSnapshot(", start)
new_decode_region = r'''  static Object? _safePreferenceValue(SharedPreferences prefs, String key) {
    try {
      return prefs.get(key);
    } catch (_) {
      return null;
    }
  }

  static dynamic _decodeJsonOr(
    SharedPreferences prefs,
    String key,
    dynamic fallback,
  ) {
    final value = _safePreferenceValue(prefs, key);
    if (value == null) return fallback;
    if (value is! String || value.trim().isEmpty) return fallback;
    try {
      return jsonDecode(value);
    } catch (_) {
      return fallback;
    }
  }

  static List<T> _safeLegacyList<T>(
    SharedPreferences prefs,
    String key,
    T Function(Map<String, dynamic>) fromJson,
  ) {
    final value = _safePreferenceValue(prefs, key);
    if (value == null) return [];
    if (value is! String || value.trim().isEmpty) return [];
    try {
      final decoded = jsonDecode(value);
      if (decoded is! List) return [];
      final result = <T>[];
      for (final entry in decoded) {
        if (entry is! Map) continue;
        try {
          result.add(fromJson(Map<String, dynamic>.from(entry)));
        } catch (_) {
          // A single broken legacy row must not erase valid siblings.
        }
      }
      return result;
    } catch (_) {
      return [];
    }
  }

  static Set<String> _legacyFavoriteIds(SharedPreferences prefs) {
    final value = _safePreferenceValue(prefs, AppDataKeys.favoriteExerciseIds);
    if (value == null) return <String>{};
    if (value is! String || value.trim().isEmpty) return <String>{};
    try {
      final decoded = jsonDecode(value);
      if (decoded is! List) return <String>{};
      return decoded
          .whereType<String>()
          .map((entry) => entry.trim())
          .where((entry) => entry.isNotEmpty)
          .toSet();
    } catch (_) {
      return <String>{};
    }
  }

  static AppDataBundle _bundleFromSnapshot(
    PersistenceRecoverySnapshot snapshot, {
    bool forceRecovered = false,
  }) {
    return AppDataBundle(
      schedules: snapshot.schedules,
      history: snapshot.history,
      scheduleVersions: snapshot.scheduleVersions,
      currentSession: snapshot.currentSession,
      bodyLogs: snapshot.bodyLogs,
      customExercises: snapshot.customExercises,
      favoriteExerciseIds: snapshot.favoriteExerciseIds,
      recoveredFromCorruption:
          forceRecovered || snapshot.recoveredFromCorruption,
    );
  }

  static AppDataBundle _markRecovered(AppDataBundle bundle) {
    if (bundle.recoveredFromCorruption) return bundle;
    return AppDataBundle(
      schedules: bundle.schedules,
      history: bundle.history,
      scheduleVersions: bundle.scheduleVersions,
      currentSession: bundle.currentSession,
      bodyLogs: bundle.bodyLogs,
      customExercises: bundle.customExercises,
      favoriteExerciseIds: bundle.favoriteExerciseIds,
      recoveredFromCorruption: true,
    );
  }

  static AppDataImportPayload parseBackupText(String rawText) {
    final snapshot = PersistenceRecoveryDecoder.decodeBackupText(rawText);
    return AppDataImportPayload(
      bundle: _bundleFromSnapshot(snapshot),
      includesCustomExercises: snapshot.includesCustomExercises,
      includesFavoriteExerciseIds: snapshot.includesFavoriteExerciseIds,
      version: snapshot.version,
    );
  }

  static AppDataBundle _loadLegacyBundle(SharedPreferences prefs) {
    final values = <String, Object?>{
      AppDataKeys.schedules: _safePreferenceValue(prefs, AppDataKeys.schedules),
      AppDataKeys.scheduleVersions: _safePreferenceValue(
        prefs,
        AppDataKeys.scheduleVersions,
      ),
      AppDataKeys.history: _safePreferenceValue(prefs, AppDataKeys.history),
      AppDataKeys.currentSession: _safePreferenceValue(
        prefs,
        AppDataKeys.currentSession,
      ),
      AppDataKeys.bodyLogs: _safePreferenceValue(prefs, AppDataKeys.bodyLogs),
      AppDataKeys.customExercises: _safePreferenceValue(
        prefs,
        AppDataKeys.customExercises,
      ),
      AppDataKeys.favoriteExerciseIds: _safePreferenceValue(
        prefs,
        AppDataKeys.favoriteExerciseIds,
      ),
    };
    final snapshot = PersistenceRecoveryDecoder.decodeLegacyStorage(values);
    final bundle = _bundleFromSnapshot(snapshot);

    // A malformed top-level preference can mean a torn/corrupted write. Prefer
    // the last coherent auto-backup in that case. Entry-level corruption is
    // salvaged in place so one bad row does not roll back all newer data.
    if (snapshot.rootCorruption) {
      final backup = _bundleFromAutoBackup(prefs);
      if (backup != null) return backup;
    }
    return bundle;
  }

  static AppDataBundle? _bundleFromAutoBackup(SharedPreferences prefs) {
    final value = _safePreferenceValue(prefs, AppDataKeys.autoBackupJson);
    if (value is! String || value.trim().isEmpty) return null;
    try {
      final snapshot = PersistenceRecoveryDecoder.decodeBackupText(value);
      return _bundleFromSnapshot(snapshot, forceRecovered: true);
    } catch (_) {
      return null;
    }
  }

'''
text = text[:start] + new_decode_region + text[end:]

old_migration = """  static Future<void> _ensureSqliteMigration() async {
    final store = _sqliteStore;
    if (await store.migrationComplete) return;
    if (await store.hasAnyData) {
      await store.markMigrationComplete();
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    final legacy = _loadLegacyBundle(prefs);
    await store.migrateLegacyData(
      schedules: legacy.schedules,
      history: legacy.history,
      scheduleVersions: legacy.scheduleVersions,
      currentSession: legacy.currentSession,
      bodyLogs: legacy.bodyLogs,
      customExercises: legacy.customExercises,
      favoriteExerciseIds: legacy.favoriteExerciseIds,
    );
  }
"""
new_migration = """  static Future<void> _ensureSqliteMigration() async {
    final store = _sqliteStore;
    if (await store.migrationComplete) return;

    final prefs = await SharedPreferences.getInstance();
    final legacy = _loadLegacyBundle(prefs);
    final sqliteHasData = await store.hasAnyData;

    // Older builds could leave a partial SQLite graph before the migration
    // marker was written. If a coherent legacy/backup snapshot still exists,
    // rerun the now-atomic migration instead of blessing the partial DB.
    if (sqliteHasData && !legacy.hasAnyData) {
      await store.markMigrationComplete();
      return;
    }

    await store.migrateLegacyData(
      schedules: legacy.schedules,
      history: legacy.history,
      scheduleVersions: legacy.scheduleVersions,
      currentSession: legacy.currentSession,
      bodyLogs: legacy.bodyLogs,
      customExercises: legacy.customExercises,
      favoriteExerciseIds: legacy.favoriteExerciseIds,
    );
  }
"""
assert text.count(old_migration) == 1
text = text.replace(old_migration, new_migration, 1)

old_catch = """      } catch (_) {
        final prefs = await SharedPreferences.getInstance();
        final fallback =
            _bundleFromAutoBackup(prefs) ?? _loadLegacyBundle(prefs);
        return _backfillScheduleHistory(fallback, persistSqlite: false);
      }
"""
new_catch = """      } catch (_) {
        final prefs = await SharedPreferences.getInstance();
        final fallback =
            _bundleFromAutoBackup(prefs) ?? _loadLegacyBundle(prefs);
        return _backfillScheduleHistory(
          _markRecovered(fallback),
          persistSqlite: false,
        );
      }
"""
assert text.count(old_catch) == 1
text = text.replace(old_catch, new_catch, 1)
path.write_text(text)

# -----------------------------------------------------------------------------
# LocalSqliteStore: make legacy migration all-or-nothing and expose controlled
# test-only fault/corruption seams.
# -----------------------------------------------------------------------------
path = Path('lib/local_sqlite_store.dart')
text = path.read_text()
old_ctor = """class LocalSqliteStore {
  final DatabaseFactory _factory;
  final String? _databasePath;
  Database? _database;

  LocalSqliteStore({DatabaseFactory? factoryOverride, String? databasePath})
    : _factory = factoryOverride ?? databaseFactory,
      _databasePath = databasePath;
"""
new_ctor = """class LocalSqliteStore {
  final DatabaseFactory _factory;
  final String? _databasePath;
  final Future<void> Function(String phase)? migrationFaultInjector;
  Database? _database;

  LocalSqliteStore({
    DatabaseFactory? factoryOverride,
    String? databasePath,
    this.migrationFaultInjector,
  }) : _factory = factoryOverride ?? databaseFactory,
       _databasePath = databasePath;
"""
assert text.count(old_ctor) == 1
text = text.replace(old_ctor, new_ctor, 1)

start = text.index("  Future<void> migrateLegacyData({")
end = text.index("\n  Future<void> replaceSchedules(", start)
new_migrate = r'''  Future<void> migrateLegacyData({
    required List<Schedule> schedules,
    required List<WorkoutSession> history,
    required WorkoutSession? currentSession,
    required List<BodyLog> bodyLogs,
    required List<Exercise> customExercises,
    required Set<String> favoriteExerciseIds,
    List<ScheduleVersion> scheduleVersions = const <ScheduleVersion>[],
  }) async {
    final db = await _db;
    await db.transaction((txn) async {
      await _replaceAllInTransaction(
        txn,
        schedules: schedules,
        history: history,
        scheduleVersions: scheduleVersions,
        currentSession: currentSession,
        bodyLogs: bodyLogs,
        customExercises: customExercises,
        favoriteExerciseIds: favoriteExerciseIds,
        checkpoint: true,
      );
      await txn.insert('meta', {
        'key': 'legacy_migrated_v1',
        'value': '1',
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      await _migrationCheckpoint('beforeCommit');
    });
  }

  Future<void> _migrationCheckpoint(String phase) async {
    final injector = migrationFaultInjector;
    if (injector != null) await injector(phase);
  }

  Future<void> _replaceAllInTransaction(
    DatabaseExecutor db, {
    required List<Schedule> schedules,
    required List<WorkoutSession> history,
    required List<ScheduleVersion> scheduleVersions,
    required WorkoutSession? currentSession,
    required List<BodyLog> bodyLogs,
    required List<Exercise> customExercises,
    required Set<String> favoriteExerciseIds,
    required bool checkpoint,
  }) async {
    await db.delete('schedules');
    for (var i = 0; i < schedules.length; i += 1) {
      await _insertSchedule(db, schedules[i], i);
    }
    if (checkpoint) await _migrationCheckpoint('afterSchedules');

    await db.delete('schedule_versions');
    for (final version in scheduleVersions) {
      await _insertScheduleVersion(db, version);
    }
    if (checkpoint) await _migrationCheckpoint('afterScheduleVersions');

    await db.delete('workout_sessions');
    for (var i = 0; i < history.length; i += 1) {
      await _insertSession(db, history[i], 'history', i);
    }
    if (currentSession != null) {
      await _insertSession(db, currentSession, 'current', 0);
    }
    if (checkpoint) await _migrationCheckpoint('afterSessions');

    await db.delete('body_logs');
    for (var i = 0; i < bodyLogs.length; i += 1) {
      final log = bodyLogs[i];
      await db.insert('body_logs', {
        'id': log.id,
        'position': i,
        'date': log.date.toIso8601String(),
        'body_weight': log.bodyWeight,
        'waist': log.waist,
        'chest': log.chest,
        'arm': log.arm,
        'thigh': log.thigh,
        'sleep_hours': log.sleepHours,
        'readiness': log.readiness,
        'notes': log.notes,
        'photo_path': log.photoPath,
        'photo_name': log.photoName,
      });
    }
    if (checkpoint) await _migrationCheckpoint('afterBodyLogs');

    await db.delete('custom_exercises');
    for (var i = 0; i < customExercises.length; i += 1) {
      final exercise = customExercises[i];
      await db.insert('custom_exercises', {
        'id': exercise.id,
        'position': i,
        'json': jsonEncode(exercise.toJson()),
      });
    }
    if (checkpoint) await _migrationCheckpoint('afterCustomExercises');

    await db.delete('favorite_exercises');
    for (final id in favoriteExerciseIds) {
      await db.insert('favorite_exercises', {'exercise_id': id});
    }
    if (checkpoint) await _migrationCheckpoint('afterFavorites');
  }

'''
text = text[:start] + new_migrate + text[end:]

close_marker = """  Future<void> close() async {
"""
debug_method = """  @visibleForTesting
  Future<void> executeForTesting(String sql, [List<Object?>? arguments]) async {
    final db = await _db;
    await db.execute(sql, arguments);
  }

  Future<void> close() async {
"""
# local_sqlite_store currently does not import foundation; use a plain method
# rather than adding an otherwise-unused annotation dependency.
debug_method = debug_method.replace('  @visibleForTesting\n', '')
assert text.count(close_marker) == 1
text = text.replace(close_marker, debug_method, 1)
path.write_text(text)

# -----------------------------------------------------------------------------
# Home JSON restore: use the same hardened parser as auto-backup/legacy storage.
# -----------------------------------------------------------------------------
path = Path('lib/screens/home.dart')
text = path.read_text()
old_decode = """      final rawText = await _readPickedTextFile(pickedFile);
      final decoded = jsonDecode(_normalizeText(rawText));
"""
new_decode = """      final rawText = await _readPickedTextFile(pickedFile);
      final parsedBackup = AppDataStore.parseBackupText(
        _normalizeText(rawText),
      );
"""
assert text.count(old_decode) == 1
text = text.replace(old_decode, new_decode, 1)

parse_start = text.index("      List<Schedule> restoredSchedules = [];", text.index(new_decode))
parse_end = text.index("\n\n      if (!mounted) {", parse_start)
new_parse = r'''      final restoredSchedules = parsedBackup.bundle.schedules;
      final restoredScheduleVersions = parsedBackup.bundle.scheduleVersions;
      final restoredHistory = parsedBackup.bundle.history;
      final restoredBodyLogs = parsedBackup.bundle.bodyLogs;
      final restoredCurrentSession = parsedBackup.bundle.currentSession;
      final List<Exercise>? restoredCustomExercises =
          parsedBackup.includesCustomExercises
          ? parsedBackup.bundle.customExercises
          : null;
      final Set<String>? restoredFavoriteExerciseIds =
          parsedBackup.includesFavoriteExerciseIds
          ? parsedBackup.bundle.favoriteExerciseIds
          : null;
      final recoveryNotice = parsedBackup.bundle.recoveredFromCorruption
          ? 'Attenzione: alcuni record invalidi o duplicati sono stati ignorati durante il recupero.\n\n'
          : '';
'''
text = text[:parse_start] + new_parse + text[parse_end:]
old_preview = """          content: Text(
            'File: ${restoredSchedules.length} schede,"""
new_preview = """          content: Text(
            '${recoveryNotice}File: ${restoredSchedules.length} schede,"""
assert text.count(old_preview) == 1
text = text.replace(old_preview, new_preview, 1)
path.write_text(text)
