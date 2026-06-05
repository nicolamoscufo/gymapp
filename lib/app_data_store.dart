import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

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
  static dynamic _decodeJsonOr(
    SharedPreferences prefs,
    String key,
    dynamic fallback,
  ) {
    final raw = prefs.getString(key);
    if (raw == null || raw.trim().isEmpty) {
      return fallback;
    }

    try {
      return jsonDecode(raw);
    } catch (_) {
      return fallback;
    }
  }

  static AppDataBundle? _bundleFromAutoBackup(SharedPreferences prefs) {
    final rawBackup = prefs.getString(AppDataKeys.autoBackupJson);
    if (rawBackup == null || rawBackup.trim().isEmpty) {
      return null;
    }

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

  static Future<void> _writeAutoBackupSnapshot(SharedPreferences prefs) async {
    final payload = {
      'version': 4,
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

  static Future<AppDataBundle> loadBundle() async {
    final prefs = await SharedPreferences.getInstance();
    var recovered = false;

    List<T> safeList<T>(String key, T Function(Map<String, dynamic>) fromJson) {
      final raw = prefs.getString(key);
      if (raw == null || raw.trim().isEmpty) {
        return [];
      }

      try {
        final decoded = jsonDecode(raw) as List<dynamic>;
        return decoded
            .whereType<Map>()
            .map((entry) => fromJson(Map<String, dynamic>.from(entry)))
            .toList();
      } catch (_) {
        recovered = true;
        return [];
      }
    }

    WorkoutSession? safeCurrentSession() {
      final raw = prefs.getString(AppDataKeys.currentSession);
      if (raw == null || raw.trim().isEmpty) {
        return null;
      }

      try {
        return WorkoutSession.fromJson(
          Map<String, dynamic>.from(jsonDecode(raw) as Map),
        );
      } catch (_) {
        recovered = true;
        return null;
      }
    }

    final bundle = AppDataBundle(
      schedules: safeList(AppDataKeys.schedules, Schedule.fromJson),
      history: safeList(AppDataKeys.history, WorkoutSession.fromJson),
      currentSession: safeCurrentSession(),
      bodyLogs: safeList(AppDataKeys.bodyLogs, BodyLog.fromJson),
      recoveredFromCorruption: recovered,
    );

    if (recovered) {
      return _bundleFromAutoBackup(prefs) ?? bundle;
    }

    return bundle;
  }

  static Future<List<WorkoutSession>> loadHistory() async {
    return (await loadBundle()).history;
  }

  static Future<void> saveSchedules(List<Schedule> schedules) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      AppDataKeys.schedules,
      jsonEncode(schedules.map((entry) => entry.toJson()).toList()),
    );
    await _writeAutoBackupSnapshot(prefs);
  }

  static Future<void> saveHistory(List<WorkoutSession> history) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      AppDataKeys.history,
      jsonEncode(history.map((entry) => entry.toJson()).toList()),
    );
    await _writeAutoBackupSnapshot(prefs);
  }

  static Future<void> saveBodyLogs(List<BodyLog> bodyLogs) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      AppDataKeys.bodyLogs,
      jsonEncode(bodyLogs.map((entry) => entry.toJson()).toList()),
    );
    await _writeAutoBackupSnapshot(prefs);
  }

  static Future<void> saveCurrentSession(WorkoutSession session) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      AppDataKeys.currentSession,
      jsonEncode(session.toJson()),
    );
    await _writeAutoBackupSnapshot(prefs);
  }

  static Future<void> clearCurrentSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(AppDataKeys.currentSession);
    await _writeAutoBackupSnapshot(prefs);
  }

  static Future<Set<String>> loadFavoriteExerciseIds() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(AppDataKeys.favoriteExerciseIds);
    if (raw == null || raw.trim().isEmpty) {
      return <String>{};
    }

    try {
      return (jsonDecode(raw) as List<dynamic>)
          .map((entry) => entry.toString())
          .toSet();
    } catch (_) {
      return <String>{};
    }
  }

  static Future<void> saveFavoriteExerciseIds(Set<String> ids) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      AppDataKeys.favoriteExerciseIds,
      jsonEncode(ids.toList()),
    );
    await _writeAutoBackupSnapshot(prefs);
  }

  static Future<List<Exercise>> loadCustomExercises() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(AppDataKeys.customExercises);
    if (raw == null || raw.trim().isEmpty) {
      return [];
    }

    try {
      return (jsonDecode(raw) as List<dynamic>)
          .whereType<Map>()
          .map((entry) => Exercise.fromJson(Map<String, dynamic>.from(entry)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> saveCustomExercises(List<Exercise> exercises) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      AppDataKeys.customExercises,
      jsonEncode(exercises.map((entry) => entry.toJson()).toList()),
    );
    await _writeAutoBackupSnapshot(prefs);
  }

  static Future<void> addCustomExercise(Exercise exercise) async {
    final exercises = await loadCustomExercises();
    final normalizedName = exercise.name.trim().toLowerCase();
    final existingIndex = exercises.indexWhere(
      (entry) => entry.name.trim().toLowerCase() == normalizedName,
    );
    final template = Exercise.fromJson(exercise.toJson());
    if (existingIndex == -1) {
      exercises.add(template);
    } else {
      exercises[existingIndex] = template;
    }
    exercises.sort(
      (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );
    await saveCustomExercises(exercises);
  }

  static Future<Set<int>> loadScheduledReminderNotificationIds() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(AppDataKeys.scheduledReminderNotificationIds);
    if (raw == null || raw.trim().isEmpty) {
      return <int>{};
    }

    try {
      return (jsonDecode(raw) as List<dynamic>)
          .whereType<num>()
          .map((entry) => entry.toInt())
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
    final raw = prefs.getString(AppDataKeys.lastAutoBackupAt);
    return raw == null ? null : DateTime.tryParse(raw);
  }

  static Future<AppDataBundle?> loadAutoBackupBundle() async {
    final prefs = await SharedPreferences.getInstance();
    return _bundleFromAutoBackup(prefs);
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
      'schedules': schedules.map((schedule) => schedule.toJson()).toList(),
      'history': history.map((session) => session.toJson()).toList(),
      'bodyLogs': bodyLogs.map((entry) => entry.toJson()).toList(),
      'currentSession': currentSession?.toJson(),
      'customExercises': customExercises
          .map((exercise) => exercise.toJson())
          .toList(),
      'favoriteExerciseIds': favoriteExerciseIds,
    };
  }

  static Future<void> saveAll({
    required List<Schedule> schedules,
    required List<WorkoutSession> history,
    required List<BodyLog> bodyLogs,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      AppDataKeys.schedules,
      jsonEncode(schedules.map((entry) => entry.toJson()).toList()),
    );
    await prefs.setString(
      AppDataKeys.history,
      jsonEncode(history.map((entry) => entry.toJson()).toList()),
    );
    await prefs.setString(
      AppDataKeys.bodyLogs,
      jsonEncode(bodyLogs.map((entry) => entry.toJson()).toList()),
    );
    await _writeAutoBackupSnapshot(prefs);
  }
}
