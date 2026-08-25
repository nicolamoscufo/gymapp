import 'dart:math' as math;

import 'active_workout_session_builder.dart';
import 'models/exercise.dart';
import 'models/schedule.dart';
import 'models/workout.dart';
import 'workout_progression_analytics.dart';

/// Synchronizes a completed live workout with its persisted routine template.
///
/// Persistence and UI confirmation intentionally stay outside this class. The
/// sync layer only resolves stable identities and mutates the supplied models.
class ActiveWorkoutScheduleSync {
  ActiveWorkoutScheduleSync({
    required this.session,
    required this.sessionBuilder,
  });

  final WorkoutSession session;
  final ActiveWorkoutSessionBuilder sessionBuilder;

  Schedule? storedScheduleForSession(
    List<Schedule> schedules, {
    Schedule? liveSchedule,
  }) {
    final scheduleId = session.scheduleId ?? liveSchedule?.id;
    if (scheduleId != null) {
      for (final schedule in schedules) {
        if (schedule.id == scheduleId) return schedule;
      }
    }

    // Title fallback keeps legacy sessions/routines usable when stable ids were
    // not persisted yet.
    final scheduleTitle = liveSchedule?.title ?? session.scheduleTitle;
    for (final schedule in schedules) {
      if (schedule.title == scheduleTitle) return schedule;
    }
    return null;
  }

  Exercise? scheduleExerciseFor(
    WorkoutExercise workoutExercise,
    Schedule schedule,
  ) {
    final sourceId = workoutExercise.sourceExerciseId;
    if (sourceId != null) {
      for (final exercise in schedule.exercises) {
        if (exercise.id == sourceId) return exercise;
      }
    }

    // Name fallback is deliberately a second pass so duplicate exercise names
    // cannot shadow an exact sourceExerciseId match.
    final normalizedName = _normalizeName(workoutExercise.name);
    for (final exercise in schedule.exercises) {
      if (_normalizeName(exercise.name) == normalizedName) return exercise;
    }
    return null;
  }

  bool workoutExerciseExistsInSchedule(
    WorkoutExercise workoutExercise,
    Schedule schedule,
  ) {
    return scheduleExerciseFor(workoutExercise, schedule) != null;
  }

  List<WorkoutExercise> newExercisesForSchedule(Schedule schedule) {
    return session.exercises
        .where(
          (exercise) => !workoutExerciseExistsInSchedule(exercise, schedule),
        )
        .toList();
  }

  /// Appends live-only exercises to [storedSchedule], binds their newly created
  /// routine ids back to the workout, and returns those ids so progression can
  /// skip them during the same finish transaction.
  Set<String> addNewExercisesToSchedule(Schedule storedSchedule) {
    final addedIds = <String>{};
    for (final workoutExercise in newExercisesForSchedule(storedSchedule)) {
      final scheduleExercise = sessionBuilder.exerciseFromWorkoutExercise(
        workoutExercise,
      );
      storedSchedule.exercises.add(scheduleExercise);
      workoutExercise.sourceExerciseId = scheduleExercise.id;
      addedIds.add(scheduleExercise.id);
    }
    return addedIds;
  }

  void syncLiveSchedule({
    required Schedule storedSchedule,
    Schedule? liveSchedule,
  }) {
    if (liveSchedule == null) return;
    final sameSchedule =
        liveSchedule.id == storedSchedule.id ||
        liveSchedule.title == storedSchedule.title;
    if (!sameSchedule) return;

    liveSchedule.exercises
      ..clear()
      ..addAll(
        storedSchedule.exercises.map(
          (exercise) => Exercise.fromJson(exercise.toJson()),
        ),
      );
  }

  void applyProgressionToSchedule({
    required Schedule storedSchedule,
    required List<WorkoutSession> history,
    Set<String> skipSourceExerciseIds = const <String>{},
  }) {
    for (final completedExercise in session.exercises) {
      if (skipSourceExerciseIds.contains(completedExercise.sourceExerciseId)) {
        continue;
      }

      final targetExercise = scheduleExerciseFor(
        completedExercise,
        storedSchedule,
      );
      if (targetExercise == null) continue;

      final decision = buildProgressionDecision(
        exercise: completedExercise,
        history: history,
        excludeSessionId: session.id,
      );

      switch (decision.action) {
        case ProgressionAction.manual:
        case ProgressionAction.maintain:
          break;
        case ProgressionAction.increaseLoad:
          targetExercise.weight += targetExercise.progressionKgStep;
          if (targetExercise.progressionScheme ==
                  ProgressionScheme.doubleProgression &&
              targetExercise.targetMinReps != null) {
            targetExercise.reps = targetExercise.targetMinReps!;
          }
          break;
        case ProgressionAction.increaseReps:
          final nextReps =
              targetExercise.reps + targetExercise.progressionRepStep;
          targetExercise.reps = targetExercise.targetMaxReps == null
              ? nextReps
              : math.min(targetExercise.targetMaxReps!, nextReps);
          break;
        case ProgressionAction.deload:
          targetExercise.weight = sessionBuilder.deloadWeight(
            targetExercise.weight,
          );
          if (targetExercise.targetMinReps != null) {
            targetExercise.reps = targetExercise.targetMinReps!;
          }
          break;
      }
    }
  }

  String _normalizeName(String value) => value.trim().toLowerCase();
}
