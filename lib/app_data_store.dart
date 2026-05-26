import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'models/body_log.dart';
import 'models/schedule.dart';
import 'models/workout.dart';

class AppDataKeys {
  static const schedules = 'schedules';
  static const history = 'history';
  static const currentSession = 'current_session';
  static const bodyLogs = 'body_logs';
}

class AppDataBundle {
  final List<Schedule> schedules;
  final List<WorkoutSession> history;
  final WorkoutSession? currentSession;
  final List<BodyLog> bodyLogs;
  final bool recoveredFromCorruption;

  const AppDataBundle({
    required this.schedules,
    required this.history,
    required this.currentSession,
    required this.bodyLogs,
    required this.recoveredFromCorruption,
  });
}

class AppDataStore {
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

    return AppDataBundle(
      schedules: safeList(AppDataKeys.schedules, Schedule.fromJson),
      history: safeList(AppDataKeys.history, WorkoutSession.fromJson),
      currentSession: safeCurrentSession(),
      bodyLogs: safeList(AppDataKeys.bodyLogs, BodyLog.fromJson),
      recoveredFromCorruption: recovered,
    );
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
  }

  static Future<void> saveHistory(List<WorkoutSession> history) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      AppDataKeys.history,
      jsonEncode(history.map((entry) => entry.toJson()).toList()),
    );
  }

  static Future<void> saveBodyLogs(List<BodyLog> bodyLogs) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      AppDataKeys.bodyLogs,
      jsonEncode(bodyLogs.map((entry) => entry.toJson()).toList()),
    );
  }

  static Future<void> saveCurrentSession(WorkoutSession session) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      AppDataKeys.currentSession,
      jsonEncode(session.toJson()),
    );
  }

  static Future<void> clearCurrentSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(AppDataKeys.currentSession);
  }

  static Future<void> saveAll({
    required List<Schedule> schedules,
    required List<WorkoutSession> history,
    required List<BodyLog> bodyLogs,
  }) async {
    await Future.wait([
      saveSchedules(schedules),
      saveHistory(history),
      saveBodyLogs(bodyLogs),
    ]);
  }
}
