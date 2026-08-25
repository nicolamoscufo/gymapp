import 'app_preferences.dart';
import 'models/exercise.dart';
import 'models/schedule.dart';
import 'models/workout.dart';

/// Pure data-normalization and ordering rules shared by the Home screen.
class HomeDataPolicy {
  const HomeDataPolicy._();

  static bool applyBackoffReductionToExercises(
    List<Exercise> exercises,
    double reductionPercent,
  ) {
    var changed = false;
    final normalized = AppPreferences.normalizeBackoffReductionPercent(
      reductionPercent,
    );
    for (final exercise in exercises) {
      if (exercise.backoffReductionPercent != normalized) {
        exercise.backoffReductionPercent = normalized;
        changed = true;
      }
    }
    return changed;
  }

  static bool applyBackoffReductionToWorkoutExercises(
    List<WorkoutExercise> exercises,
    double reductionPercent,
  ) {
    var changed = false;
    final normalized = AppPreferences.normalizeBackoffReductionPercent(
      reductionPercent,
    );
    for (final exercise in exercises) {
      if (exercise.backoffReductionPercent != normalized) {
        exercise.backoffReductionPercent = normalized;
        changed = true;
      }
    }
    return changed;
  }

  static bool applyBackoffReductionToSchedules(
    List<Schedule> schedules,
    double reductionPercent,
  ) {
    var changed = false;
    for (final schedule in schedules) {
      changed |= applyBackoffReductionToExercises(
        schedule.exercises,
        reductionPercent,
      );
    }
    return changed;
  }

  static bool applyBackoffReductionToSession(
    WorkoutSession? session,
    double reductionPercent,
  ) {
    if (session == null) {
      return false;
    }
    return applyBackoffReductionToWorkoutExercises(
      session.exercises,
      reductionPercent,
    );
  }

  static bool applyBackoffReductionToHistory(
    List<WorkoutSession> history,
    double reductionPercent,
  ) {
    var changed = false;
    for (final session in history) {
      changed |= applyBackoffReductionToSession(session, reductionPercent);
    }
    return changed;
  }

  static void sortSchedules(List<Schedule> schedules) {
    schedules.sort((a, b) {
      if (a.isArchived != b.isArchived) {
        return a.isArchived ? 1 : -1;
      }

      final weekCompare = a.currentWeek().compareTo(b.currentWeek());
      if (weekCompare != 0) {
        return weekCompare;
      }

      return a.title.toLowerCase().compareTo(b.title.toLowerCase());
    });
  }
}
