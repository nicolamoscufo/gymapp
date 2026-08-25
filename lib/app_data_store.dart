import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'local_sqlite_store.dart';
import 'models/body_log.dart';
import 'models/exercise.dart';
import 'models/schedule.dart';
import 'models/workout.dart';

class AppDataKeys {
  static const schedules = 'schedules';
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
  final WorkoutSession? currentSession;
  final List<BodyLog> bodyLogs;
  final List<Exercise> customExercises;
  final Set<String> favoriteExerciseIds;
  final bool recoveredFromCorruption;

  const AppDataBundle({
    required this.schedules,
    required this.history,
    required this.currentSession,
    required this.bodyLogs,
    this.customExercises = const [],
    this.favoriteExerciseIds = const <String>{},
    required this.recoveredFromCorruption,
  });
}

class AppDataStore {
  static LocalSqliteStore? _sqlite;

  static bool get _sqliteSupported {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS;
  }

  static LocalSqliteStore get _sqliteStore => _sqlite ??= LocalSqliteStore();

  static dynamic _decodeJsonOr(
    SharedPreferences prefs,
    String key,
    dynamic fallback,
  ) {
    final raw = prefs.getString(key);
    if (raw == null || raw.trim().isEmpty) return fallback;
    try {
      return jsonDecode(raw);
    } catch (_) {
      return fallback;
    }
  }

  static List<T> _safeLegacyList<T>(
    SharedPreferences prefs,
    String key,
    T Function(Map<String, dynamic>) fromJson,
  ) {
    final raw = prefs.getString(key);
    if (raw == null || raw.trim().isEmpty) return [];
    try {
      return (jsonDecode(raw) as List<dynamic>)
          .whereType<Map>()
          .map((entry) => fromJson(Map<String, dynamic>.from(entry)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Set<String> _legacyFavoriteIds(SharedPreferences prefs) {
    final raw = prefs.getString(AppDataKeys.favoriteExerciseIds);
    if (raw == null || raw.trim().isEmpty) return <String>{};
    try {
      return (jsonDecode(raw) as List<dynamic>)
          .map((e) => e.toString())
          .toSet();
    } catch (_) {
      return <String>{};
    }
  }

  static AppDataBundle _loadLegacyBundle(SharedPreferences prefs) {
    var recovered = false;

    List<T> checkedList<T>(
      String key,
      T Function(Map<String, dynamic>) parser,
    ) {
      final raw = prefs.getString(key);
      if (raw == null || raw.trim().isEmpty) return [];
      try {
        return (jsonDecode(raw) as List<dynamic>)
            .whereType<Map>()
            .map((entry) => parser(Map<String, dynamic>.from(entry)))
            .toList();
      } catch (_) {
        recovered = true;
        return [];
      }
    }

    WorkoutSession? current;
    final rawCurrent = prefs.getString(AppDataKeys.currentSession);
    if (rawCurrent != null && rawCurrent.trim().isNotEmpty) {
      try {
        current = WorkoutSession.fromJson(
          Map<String, dynamic>.from(jsonDecode(rawCurrent) as Map),
        );
      } catch (_) {
        recovered = true;
      }
    }

    final bundle = AppDataBundle(
      schedules: checkedList(AppDataKeys.schedules, Schedule.fromJson),
      history: checkedList(AppDataKeys.history, WorkoutSession.fromJson),
      currentSession: current,
      bodyLogs: checkedList(AppDataKeys.bodyLogs, BodyLog.fromJson),
      customExercises: checkedList(
        AppDataKeys.customExercises,
        Exercise.fromJson,
      ),
      favoriteExerciseIds: _legacyFavoriteIds(prefs),
      recoveredFromCorruption: recovered,
    );
    if (!recovered) return bundle;
    return _bundleFromAutoBackup(prefs) ?? bundle;
  }

  static AppDataBundle? _bundleFromAutoBackup(SharedPreferences prefs) {
    final rawBackup = prefs.getString(AppDataKeys.autoBackupJson);
    if (rawBackup == null || rawBackup.trim().isEmpty) return null;
    try {
      final backupMap = Map<String, dynamic>.from(jsonDecode(rawBackup) as Map);
      return AppDataBundle(
        schedules: (backupMap['schedules'] as List? ?? [])
            .whereType<Map>()
            .map((entry) => Schedule.fromJson(Map<String, dynamic>.from(entry)))
            .toList(),
        history: (backupMap['history'] as List? ?? [])
            .whereType<Map>()
            .map(
              (entry) =>
                  WorkoutSession.fromJson(Map<String, dynamic>.from(entry)),
            )
            .toList(),
        currentSession: backupMap['currentSession'] == null
            ? null
            : WorkoutSession.fromJson(
                Map<String, dynamic>.from(backupMap['currentSession'] as Map),
              ),
        bodyLogs: (backupMap['bodyLogs'] as List? ?? [])
            .whereType<Map>()
            .map((entry) => BodyLog.fromJson(Map<String, dynamic>.from(entry)))
            .toList(),
        customExercises: (backupMap['customExercises'] as List? ?? [])
            .whereType<Map>()
            .map((entry) => Exercise.fromJson(Map<String, dynamic>.from(entry)))
            .toList(),
        favoriteExerciseIds: (backupMap['favoriteExerciseIds'] as List? ?? [])
            .map((entry) => entry.toString())
            .toSet(),
        recoveredFromCorruption: true,
      );
    } catch (_) {
      return null;
    }
  }

  static Future<void> _writeLegacyAutoBackupSnapshot(
    SharedPreferences prefs,
  ) async {
    final payload = {
      'version': 5,
      'auto': true,
      'exportedAt': DateTime.now().toIso8601String(),
      'schedules': _decodeJsonOr(prefs, AppDataKeys.schedules, []),
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
      'version': 5,
      'auto': true,
      'storage': 'sqlite',
      'exportedAt': DateTime.now().toIso8601String(),
      'schedules': snapshot.schedules.map((e) => e.toJson()).toList(),
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
    if (await store.hasAnyData) {
      await store.markMigrationComplete();
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    final legacy = _loadLegacyBundle(prefs);
    await store.migrateLegacyData(
      schedules: legacy.schedules,
      history: legacy.history,
      currentSession: legacy.currentSession,
      bodyLogs: legacy.bodyLogs,
      customExercises: legacy.customExercises,
      favoriteExerciseIds: legacy.favoriteExerciseIds,
    );
  }

  static Future<AppDataBundle> loadBundle() async {
    if (_sqliteSupported) {
      try {
        await _ensureSqliteMigration();
        final data = await _sqliteStore.loadAll();
        return AppDataBundle(
          schedules: data.schedules,
          history: data.history,
          currentSession: data.currentSession,
          bodyLogs: data.bodyLogs,
          customExercises: data.customExercises,
          favoriteExerciseIds: data.favoriteExerciseIds,
          recoveredFromCorruption: false,
        );
      } catch (_) {
        final prefs = await SharedPreferences.getInstance();
        return _bundleFromAutoBackup(prefs) ?? _loadLegacyBundle(prefs);
      }
    }
    return _loadLegacyBundle(await SharedPreferences.getInstance());
  }

  static Future<List<WorkoutSession>> loadHistory() async =>
      (await loadBundle()).history;

  static Future<void> saveSchedules(List<Schedule> schedules) async {
    if (_sqliteSupported) {
      try {
        await _ensureSqliteMigration();
        await _sqliteStore.replaceSchedules(schedules);
        await _writeSqliteAutoBackup(force: true);
        return;
      } catch (_) {}
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      AppDataKeys.schedules,
      jsonEncode(schedules.map((e) => e.toJson()).toList()),
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
    return {
      'version': 5,
      'exportedAt': DateTime.now().toIso8601String(),
      'schedules': schedules.map((e) => e.toJson()).toList(),
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
  }) async {
    if (_sqliteSupported) {
      try {
        await _ensureSqliteMigration();
        await _sqliteStore.replaceSchedules(schedules);
        await _sqliteStore.replaceHistory(history);
        await _sqliteStore.replaceBodyLogs(bodyLogs);
        await _writeSqliteAutoBackup(force: true);
        return;
      } catch (_) {}
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      AppDataKeys.schedules,
      jsonEncode(schedules.map((e) => e.toJson()).toList()),
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
