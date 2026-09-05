import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'local_sqlite_store.dart';
import 'persistence_recovery.dart';
import 'models/body_log.dart';
import 'models/exercise.dart';
import 'models/schedule.dart';
import 'models/schedule_version.dart';
import 'models/workout.dart';
import 'schedule_version_history.dart';

class AppDataKeys {
  static const schedules = 'schedules';
  static const scheduleVersions = 'schedule_versions';
  static const history = 'history';
  static const currentSession = 'current_session';
  static const bodyLogs = 'body_logs';
  static const favoriteExerciseIds = 'favorite_exercise_ids';
  static const customExercises = 'custom_exercises';
  static const scheduledReminderNotificationIds =
      'scheduled_reminder_notification_ids';
  static const autoBackupJson = 'auto_backup_json';
  static const lastAutoBackupAt = 'last_auto_backup_at';
}

class AppDataBundle {
  final List<Schedule> schedules;
  final List<WorkoutSession> history;
  final List<ScheduleVersion> scheduleVersions;
  final WorkoutSession? currentSession;
  final List<BodyLog> bodyLogs;
  final List<Exercise> customExercises;
  final Set<String> favoriteExerciseIds;
  final bool recoveredFromCorruption;

  const AppDataBundle({
    required this.schedules,
    required this.history,
    this.scheduleVersions = const <ScheduleVersion>[],
    required this.currentSession,
    required this.bodyLogs,
    this.customExercises = const [],
    this.favoriteExerciseIds = const <String>{},
    required this.recoveredFromCorruption,
  });

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

  static LocalSqliteStore get _sqliteStore => _sqlite ??= LocalSqliteStore();

  static Object? _safePreferenceValue(SharedPreferences prefs, String key) {
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

  static Future<void> _writeLegacyAutoBackupSnapshot(
    SharedPreferences prefs,
  ) async {
    final payload = {
      'version': 6,
      'auto': true,
      'exportedAt': DateTime.now().toIso8601String(),
      'schedules': _decodeJsonOr(prefs, AppDataKeys.schedules, []),
      'scheduleVersions': _decodeJsonOr(
        prefs,
        AppDataKeys.scheduleVersions,
        [],
      ),
      'history': _decodeJsonOr(prefs, AppDataKeys.history, []),
      'bodyLogs': _decodeJsonOr(prefs, AppDataKeys.bodyLogs, []),
      'currentSession': prefs.getString(AppDataKeys.currentSession) == null
          ? null
          : _decodeJsonOr(prefs, AppDataKeys.currentSession, null),
      'customExercises': _decodeJsonOr(prefs, AppDataKeys.customExercises, []),
      'favoriteExerciseIds': _decodeJsonOr(
        prefs,
        AppDataKeys.favoriteExerciseIds,
        [],
      ),
    };
    await prefs.setString(AppDataKeys.autoBackupJson, jsonEncode(payload));
    await prefs.setString(
      AppDataKeys.lastAutoBackupAt,
      DateTime.now().toIso8601String(),
    );
  }

  static Future<void> _writeSqliteAutoBackup({bool force = false}) async {
    final prefs = await SharedPreferences.getInstance();
    if (!force) {
      final last = DateTime.tryParse(
        prefs.getString(AppDataKeys.lastAutoBackupAt) ?? '',
      );
      if (last != null &&
          DateTime.now().difference(last) < const Duration(minutes: 5)) {
        return;
      }
    }
    final snapshot = await _sqliteStore.loadAll();
    final payload = {
      'version': 6,
      'auto': true,
      'storage': 'sqlite',
      'exportedAt': DateTime.now().toIso8601String(),
      'schedules': snapshot.schedules.map((e) => e.toJson()).toList(),
      'scheduleVersions': snapshot.scheduleVersions
          .map((e) => e.toJson())
          .toList(),
      'history': snapshot.history.map((e) => e.toJson()).toList(),
      'bodyLogs': snapshot.bodyLogs.map((e) => e.toJson()).toList(),
      'currentSession': snapshot.currentSession?.toJson(),
      'customExercises': snapshot.customExercises
          .map((e) => e.toJson())
          .toList(),
      'favoriteExerciseIds': snapshot.favoriteExerciseIds.toList(),
    };
    await prefs.setString(AppDataKeys.autoBackupJson, jsonEncode(payload));
    await prefs.setString(
      AppDataKeys.lastAutoBackupAt,
      DateTime.now().toIso8601String(),
    );
  }

  static Future<void> _ensureSqliteMigration() async {
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

  static bool _looksLikeStoredDataCorruption(Object error) {
    if (error is FormatException || error is TypeError) return true;
    final message = error.toString().toLowerCase();
    return message.contains('database disk image is malformed') ||
        message.contains('file is not a database') ||
        message.contains('malformed database');
  }

  static Future<AppDataBundle> loadBundle() async {
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
        return await _backfillScheduleHistory(bundle, persistSqlite: true);
      } catch (error) {
        final prefs = await SharedPreferences.getInstance();
        final fallback =
            _bundleFromAutoBackup(prefs) ?? _loadLegacyBundle(prefs);
        return _backfillScheduleHistory(
          _looksLikeStoredDataCorruption(error)
              ? _markRecovered(fallback)
              : fallback,
          persistSqlite: false,
        );
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

  static List<ScheduleVersion> _legacyScheduleVersions(
    SharedPreferences prefs,
  ) {
    return _safeLegacyList(
      prefs,
      AppDataKeys.scheduleVersions,
      ScheduleVersion.fromJson,
    );
  }

  static Future<List<ScheduleVersion>> loadScheduleVersions() async {
    return (await loadBundle()).scheduleVersions;
  }

  static Future<List<WorkoutSession>> loadHistory() async =>
      (await loadBundle()).history;

  static Future<void> saveSchedules(
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

  static Future<void> saveHistory(List<WorkoutSession> history) async {
    if (_sqliteSupported) {
      try {
        await _ensureSqliteMigration();
        await _sqliteStore.replaceHistory(history);
        await _writeSqliteAutoBackup(force: true);
        return;
      } catch (_) {}
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      AppDataKeys.history,
      jsonEncode(history.map((e) => e.toJson()).toList()),
    );
    await _writeLegacyAutoBackupSnapshot(prefs);
  }

  static Future<void> saveBodyLogs(List<BodyLog> bodyLogs) async {
    if (_sqliteSupported) {
      try {
        await _ensureSqliteMigration();
        await _sqliteStore.replaceBodyLogs(bodyLogs);
        await _writeSqliteAutoBackup(force: true);
        return;
      } catch (_) {}
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      AppDataKeys.bodyLogs,
      jsonEncode(bodyLogs.map((e) => e.toJson()).toList()),
    );
    await _writeLegacyAutoBackupSnapshot(prefs);
  }

  static Future<void> saveCurrentSession(WorkoutSession session) async {
    if (_sqliteSupported) {
      try {
        await _ensureSqliteMigration();
        await _sqliteStore.saveCurrentSession(session);
        await _writeSqliteAutoBackup();
        return;
      } catch (_) {}
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      AppDataKeys.currentSession,
      jsonEncode(session.toJson()),
    );
    await _writeLegacyAutoBackupSnapshot(prefs);
  }

  static Future<void> clearCurrentSession() async {
    if (_sqliteSupported) {
      try {
        await _ensureSqliteMigration();
        await _sqliteStore.clearCurrentSession();
        await _writeSqliteAutoBackup();
        return;
      } catch (_) {}
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(AppDataKeys.currentSession);
    await _writeLegacyAutoBackupSnapshot(prefs);
  }

  static Future<Set<String>> loadFavoriteExerciseIds() async {
    if (_sqliteSupported) {
      try {
        await _ensureSqliteMigration();
        return await _sqliteStore.loadFavoriteExerciseIds();
      } catch (_) {}
    }
    return _legacyFavoriteIds(await SharedPreferences.getInstance());
  }

  static Future<void> saveFavoriteExerciseIds(Set<String> ids) async {
    if (_sqliteSupported) {
      try {
        await _ensureSqliteMigration();
        await _sqliteStore.replaceFavoriteExerciseIds(ids);
        await _writeSqliteAutoBackup(force: true);
        return;
      } catch (_) {}
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      AppDataKeys.favoriteExerciseIds,
      jsonEncode(ids.toList()),
    );
    await _writeLegacyAutoBackupSnapshot(prefs);
  }

  static Future<List<Exercise>> loadCustomExercises() async {
    if (_sqliteSupported) {
      try {
        await _ensureSqliteMigration();
        return await _sqliteStore.loadCustomExercises();
      } catch (_) {}
    }
    return _safeLegacyList(
      await SharedPreferences.getInstance(),
      AppDataKeys.customExercises,
      Exercise.fromJson,
    );
  }

  static Future<void> saveCustomExercises(List<Exercise> exercises) async {
    if (_sqliteSupported) {
      try {
        await _ensureSqliteMigration();
        await _sqliteStore.replaceCustomExercises(exercises);
        await _writeSqliteAutoBackup(force: true);
        return;
      } catch (_) {}
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      AppDataKeys.customExercises,
      jsonEncode(exercises.map((e) => e.toJson()).toList()),
    );
    await _writeLegacyAutoBackupSnapshot(prefs);
  }

  static Future<void> addCustomExercise(Exercise exercise) async {
    final exercises = await loadCustomExercises();
    final normalizedName = exercise.name.trim().toLowerCase();
    final index = exercises.indexWhere(
      (e) => e.name.trim().toLowerCase() == normalizedName,
    );
    final template = Exercise.fromJson(exercise.toJson());
    if (index == -1) {
      exercises.add(template);
    } else {
      exercises[index] = template;
    }
    exercises.sort(
      (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );
    await saveCustomExercises(exercises);
  }

  static Future<Set<int>> loadScheduledReminderNotificationIds() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(AppDataKeys.scheduledReminderNotificationIds);
    if (raw == null || raw.trim().isEmpty) return <int>{};
    try {
      return (jsonDecode(raw) as List<dynamic>)
          .whereType<num>()
          .map((e) => e.toInt())
          .toSet();
    } catch (_) {
      return <int>{};
    }
  }

  static Future<void> saveScheduledReminderNotificationIds(Set<int> ids) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      AppDataKeys.scheduledReminderNotificationIds,
      jsonEncode(ids.toList()),
    );
  }

  static Future<DateTime?> loadLastAutoBackupAt() async {
    final prefs = await SharedPreferences.getInstance();
    return DateTime.tryParse(
      prefs.getString(AppDataKeys.lastAutoBackupAt) ?? '',
    );
  }

  static Future<AppDataBundle?> loadAutoBackupBundle() async {
    return _bundleFromAutoBackup(await SharedPreferences.getInstance());
  }

  static Future<Map<String, dynamic>> buildExportPayload({
    required List<Schedule> schedules,
    required List<WorkoutSession> history,
    required List<BodyLog> bodyLogs,
    WorkoutSession? currentSession,
  }) async {
    final favoriteExerciseIds = (await loadFavoriteExerciseIds()).toList()
      ..sort();
    final customExercises = await loadCustomExercises();
    final scheduleVersions = await loadScheduleVersions();
    return {
      'version': 6,
      'exportedAt': DateTime.now().toIso8601String(),
      'schedules': schedules.map((e) => e.toJson()).toList(),
      'scheduleVersions': scheduleVersions.map((e) => e.toJson()).toList(),
      'history': history.map((e) => e.toJson()).toList(),
      'bodyLogs': bodyLogs.map((e) => e.toJson()).toList(),
      'currentSession': currentSession?.toJson(),
      'customExercises': customExercises.map((e) => e.toJson()).toList(),
      'favoriteExerciseIds': favoriteExerciseIds,
    };
  }

  static Future<void> saveAll({
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
        final existing =
            scheduleVersions ?? await _sqliteStore.loadScheduleVersions();
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
}
