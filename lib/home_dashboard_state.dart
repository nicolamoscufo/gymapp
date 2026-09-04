import 'models/body_log.dart';
import 'models/schedule.dart';
import 'models/workout.dart';

class HomePlannedWorkout {
  final Schedule schedule;
  final DateTime date;

  const HomePlannedWorkout({required this.schedule, required this.date});
}

class HomeDashboardState {
  const HomeDashboardState._();

  static bool sameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  static HomePlannedWorkout? nextPlannedWorkout(
    List<Schedule> schedules, {
    DateTime? now,
  }) {
    final activeSchedules = schedules
        .where(
          (schedule) => !schedule.isArchived && schedule.exercises.isNotEmpty,
        )
        .toList();
    if (activeSchedules.isEmpty) return null;

    final reference = now ?? DateTime.now();
    final today = DateTime(reference.year, reference.month, reference.day);
    for (var offset = 0; offset <= 7; offset++) {
      final date = today.add(Duration(days: offset));
      for (final schedule in activeSchedules) {
        if (schedule.isPlannedOn(date)) {
          return HomePlannedWorkout(schedule: schedule, date: date);
        }
      }
    }

    return HomePlannedWorkout(schedule: activeSchedules.first, date: today);
  }

  static int workoutsThisWeek(List<WorkoutSession> history, {DateTime? now}) {
    final reference = now ?? DateTime.now();
    final today = DateTime(reference.year, reference.month, reference.day);
    final startOfWeek = today.subtract(Duration(days: today.weekday - 1));
    final endOfWeek = startOfWeek.add(const Duration(days: 7));
    return history.where((session) {
      return !session.endTime.isBefore(startOfWeek) &&
          session.endTime.isBefore(endOfWeek);
    }).length;
  }

  static BodyLog? latestBodyLog(List<BodyLog> bodyLogs) {
    if (bodyLogs.isEmpty) return null;
    return bodyLogs.reduce((a, b) => a.date.isAfter(b.date) ? a : b);
  }
}
