import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as timezone_data;
import 'package:timezone/timezone.dart' as timezone;

import 'app_data_store.dart';
import 'models/schedule.dart';

class LocalNotificationService {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static bool _initialized = false;
  static bool _available = false;

  static Future<bool> initialize() async {
    if (kIsWeb || _initialized) {
      return _available;
    }

    _initialized = true;
    try {
      timezone_data.initializeTimeZones();
      const initializationSettings = InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/launcher_icon'),
        iOS: DarwinInitializationSettings(),
        macOS: DarwinInitializationSettings(),
        linux: LinuxInitializationSettings(defaultActionName: 'Apri'),
        windows: WindowsInitializationSettings(
          appName: 'Gym App',
          appUserModelId: 'GymApp.LocalNotifications',
          guid: '0f053db2-49b9-4e15-b005-7e3c539b35d8',
        ),
      );
      _available = await _plugin.initialize(initializationSettings) ?? false;
      await _requestPermissions();
      return _available;
    } catch (_) {
      _available = false;
      return false;
    }
  }

  static Future<void> _requestPermissions() async {
    await _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.requestNotificationsPermission();
    await _plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >()
        ?.requestPermissions(alert: true, badge: true, sound: true);
    await _plugin
        .resolvePlatformSpecificImplementation<
          MacOSFlutterLocalNotificationsPlugin
        >()
        ?.requestPermissions(alert: true, badge: true, sound: true);
  }

  static NotificationDetails _notificationDetails(String channelId) {
    return NotificationDetails(
      android: AndroidNotificationDetails(
        channelId,
        channelId == 'rest_timer' ? 'Timer recupero' : 'Promemoria workout',
        channelDescription: channelId == 'rest_timer'
            ? 'Avvisi di fine recupero'
            : 'Promemoria allenamenti programmati',
        importance: Importance.high,
        priority: Priority.high,
        playSound: true,
        enableVibration: true,
      ),
      iOS: const DarwinNotificationDetails(presentSound: true),
      macOS: const DarwinNotificationDetails(presentSound: true),
      linux: const LinuxNotificationDetails(),
      windows: const WindowsNotificationDetails(),
    );
  }

  static timezone.TZDateTime _scheduledDate(DateTime date) {
    final delay = date.difference(DateTime.now());
    final safeDelay = delay.isNegative ? const Duration(seconds: 1) : delay;
    return timezone.TZDateTime.now(timezone.local).add(safeDelay);
  }

  static int restNotificationId(String exerciseId) {
    return 100000 + exerciseId.hashCode.abs() % 800000;
  }

  static int workoutReminderId(String scheduleId, DateTime date) {
    final dayId = date.year * 10000 + date.month * 100 + date.day;
    return 900000 + (scheduleId.hashCode.abs() + dayId) % 900000;
  }

  static Future<void> showRestFinished(String exerciseName) async {
    if (!await initialize()) {
      return;
    }

    await _plugin.show(
      restNotificationId('foreground-$exerciseName'),
      'Recupero finito',
      exerciseName.isEmpty ? 'Prossimo set pronto.' : '$exerciseName pronto.',
      _notificationDetails('rest_timer'),
    );
  }

  static Future<void> scheduleRestFinished({
    required int id,
    required DateTime endTime,
    required String exerciseName,
  }) async {
    if (!await initialize() || !endTime.isAfter(DateTime.now())) {
      return;
    }

    await _plugin.zonedSchedule(
      id,
      'Recupero finito',
      exerciseName.isEmpty ? 'Prossimo set pronto.' : '$exerciseName pronto.',
      _scheduledDate(endTime),
      _notificationDetails('rest_timer'),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
    );
  }

  static Future<void> cancel(int id) async {
    if (!await initialize()) {
      return;
    }
    await _plugin.cancel(id);
  }

  static Future<void> scheduleWorkoutReminders({
    required List<Schedule> schedules,
    required bool enabled,
    required int hour,
    required int minute,
  }) async {
    if (!await initialize()) {
      return;
    }

    final previousIds =
        await AppDataStore.loadScheduledReminderNotificationIds();
    for (final id in previousIds) {
      await _plugin.cancel(id);
    }

    if (!enabled) {
      await AppDataStore.saveScheduledReminderNotificationIds(<int>{});
      return;
    }

    final now = DateTime.now();
    final scheduledIds = <int>{};
    for (var offset = 0; offset < 35; offset++) {
      final day = DateTime(
        now.year,
        now.month,
        now.day,
      ).add(Duration(days: offset));
      final reminderAt = DateTime(
        day.year,
        day.month,
        day.day,
        hour.clamp(0, 23),
        minute.clamp(0, 59),
      );
      if (!reminderAt.isAfter(now)) {
        continue;
      }

      for (final schedule in schedules) {
        if (schedule.isArchived || !schedule.isPlannedOn(day)) {
          continue;
        }
        final id = workoutReminderId(schedule.id, day);
        scheduledIds.add(id);
        await _plugin.zonedSchedule(
          id,
          'Allenamento programmato',
          '${schedule.title} - Week ${schedule.currentWeek(now: day)}',
          _scheduledDate(reminderAt),
          _notificationDetails('workout_reminder'),
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        );
      }
    }

    await AppDataStore.saveScheduledReminderNotificationIds(scheduledIds);
  }
}
