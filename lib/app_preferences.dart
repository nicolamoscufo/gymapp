import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'top_set_backoff.dart' as top_set_backoff;

class WorkoutReminderSettings {
  final bool enabled;
  final int hour;
  final int minute;

  const WorkoutReminderSettings({
    required this.enabled,
    required this.hour,
    required this.minute,
  });
}

class AppPreferences {
  static const themeModeKey = 'themeMode';
  static const defaultRestSecondsKey = 'defaultRestSeconds';
  static const defaultBackoffReductionPercentKey =
      'defaultBackoffReductionPercent';
  static const workoutRemindersEnabledKey = 'workoutRemindersEnabled';
  static const workoutReminderHourKey = 'workoutReminderHour';
  static const workoutReminderMinuteKey = 'workoutReminderMinute';

  static const defaultThemeMode = ThemeMode.system;
  static const defaultRestSeconds = 90;
  static const minRestSeconds = 30;
  static const maxRestSeconds = 300;
  static const defaultBackoffReductionPercent =
      top_set_backoff.defaultBackoffReductionPercent;
  static const minBackoffReductionPercent = 0.0;
  static const maxBackoffReductionPercent = 100.0;
  static const defaultWorkoutReminderHour = 8;
  static const defaultWorkoutReminderMinute = 0;

  static ThemeMode themeModeFromString(String? value) {
    return switch (value) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
  }

  static String themeModeToString(ThemeMode themeMode) {
    return switch (themeMode) {
      ThemeMode.light => 'light',
      ThemeMode.dark => 'dark',
      ThemeMode.system => 'system',
    };
  }

  static double normalizeBackoffReductionPercent(double value) {
    return value
        .clamp(minBackoffReductionPercent, maxBackoffReductionPercent)
        .toDouble();
  }

  static Future<double> loadDefaultBackoffReductionPercent() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getDouble(defaultBackoffReductionPercentKey);
    return normalizeBackoffReductionPercent(
      value ?? defaultBackoffReductionPercent,
    );
  }

  static Future<void> saveDefaultBackoffReductionPercent(double value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(
      defaultBackoffReductionPercentKey,
      normalizeBackoffReductionPercent(value),
    );
  }

  static Future<WorkoutReminderSettings> loadWorkoutReminderSettings() async {
    final prefs = await SharedPreferences.getInstance();
    return WorkoutReminderSettings(
      enabled: prefs.getBool(workoutRemindersEnabledKey) ?? false,
      hour: (prefs.getInt(workoutReminderHourKey) ?? defaultWorkoutReminderHour)
          .clamp(0, 23)
          .toInt(),
      minute:
          (prefs.getInt(workoutReminderMinuteKey) ??
                  defaultWorkoutReminderMinute)
              .clamp(0, 59)
              .toInt(),
    );
  }

  static Future<void> saveWorkoutReminderSettings(
    WorkoutReminderSettings settings,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(workoutRemindersEnabledKey, settings.enabled);
    await prefs.setInt(
      workoutReminderHourKey,
      settings.hour.clamp(0, 23).toInt(),
    );
    await prefs.setInt(
      workoutReminderMinuteKey,
      settings.minute.clamp(0, 59).toInt(),
    );
  }
}
