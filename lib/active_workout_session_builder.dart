import 'dart:math' as math;

import 'models/body_log.dart';
import 'models/exercise.dart';
import 'models/schedule.dart';
import 'models/workout.dart';
import 'top_set_backoff.dart' as top_set_backoff;
import 'workout_fatigue_analytics.dart';
import 'workout_progression_analytics.dart';

/// Builds the executable workout state from a saved routine and training
/// history.
///
/// This class owns previous-performance lookup, progression prefill and deload
/// construction so the active-workout screen does not need to know how a
/// [Schedule] becomes a [WorkoutSession].
class ActiveWorkoutSessionBuilder {
  ActiveWorkoutSessionBuilder({
    required this.history,
    required this.bodyLogs,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final List<WorkoutSession> history;
  final List<BodyLog> bodyLogs;
  final DateTime Function() _now;

  WorkoutSession? latestSessionForSchedule(Schedule schedule) {
    WorkoutSession? latestSession;
    for (final session in history) {
      // Keep title fallback for legacy sessions that pre-date scheduleId.
      final belongsToSchedule =
          session.scheduleId == schedule.id ||
          (session.scheduleId == null &&
              session.scheduleTitle == schedule.title);
      if (!belongsToSchedule) continue;

      if (latestSession == null ||
          session.endTime.isAfter(latestSession.endTime)) {
        latestSession = session;
      }
    }
    return latestSession;
  }

  WorkoutExercise? previousExerciseFor(
    Exercise exercise,
    WorkoutSession? previousSession,
  ) {
    if (previousSession == null) return null;

    for (final previousExercise in previousSession.exercises) {
      if (previousExercise.sourceExerciseId == exercise.id) {
        return previousExercise;
      }
    }

    final exerciseName = normalizeExerciseName(exercise.name);
    for (final previousExercise in previousSession.exercises) {
      if (normalizeExerciseName(previousExercise.name) == exerciseName) {
        return previousExercise;
      }
    }
    return null;
  }

  List<double> previousWeightsFor(WorkoutExercise? previousExercise) {
    if (previousExercise == null) return const [];
    final sourceSets = _preferredPreviousSets(previousExercise);
    return sourceSets.map((set) => set.weight).toList();
  }

  List<int> previousRepsFor(WorkoutExercise? previousExercise) {
    if (previousExercise == null) return const [];
    final sourceSets = _preferredPreviousSets(previousExercise);
    return sourceSets.map((set) => set.reps).toList();
  }

  double deloadWeight(double weight) {
    return (weight * 0.9 * 2).roundToDouble() / 2;
  }

  double weightForSet(
    Exercise exercise,
    List<double> previousWeights,
    List<int> previousReps,
    ProgressionDecision? progressionDecision,
    int index,
  ) {
    if (previousWeights.isEmpty) return exercise.weight;

    final previousWeight = index < previousWeights.length
        ? previousWeights[index]
        : previousWeights.last;
    final previousRep = index < previousReps.length
        ? previousReps[index]
        : (previousReps.isEmpty ? exercise.reps : previousReps.last);

    if (exercise.progressionScheme == ProgressionScheme.manual ||
        exercise.progressionScheme == ProgressionScheme.repsOnly) {
      return previousWeight;
    }

    if (progressionDecision != null) {
      return switch (progressionDecision.action) {
        ProgressionAction.increaseLoad =>
          previousWeight + exercise.progressionKgStep,
        ProgressionAction.deload => deloadWeight(previousWeight),
        ProgressionAction.increaseReps ||
        ProgressionAction.maintain ||
        ProgressionAction.manual => previousWeight,
      };
    }

    final minReps = exercise.targetMinReps;
    final maxReps = exercise.targetMaxReps;
    if (minReps == null || maxReps == null) return previousWeight;
    if (exercise.progressionScheme == ProgressionScheme.linear) {
      return previousWeight + exercise.progressionKgStep;
    }
    if (exercise.progressionScheme == ProgressionScheme.loadOnly) {
      return previousRep >= maxReps
          ? previousWeight + exercise.progressionKgStep
          : previousWeight;
    }
    if (previousRep >= maxReps) {
      return previousWeight + exercise.progressionKgStep;
    }
    if (previousRep < minReps) return deloadWeight(previousWeight);
    return previousWeight;
  }

  int repsForSet(
    Exercise exercise,
    List<int> previousReps,
    ProgressionDecision? progressionDecision,
    int index,
  ) {
    final minReps = exercise.targetMinReps;
    final maxReps = exercise.targetMaxReps;
    if (previousReps.isEmpty || minReps == null || maxReps == null) {
      return exercise.reps;
    }

    final previousRep = index < previousReps.length
        ? previousReps[index]
        : previousReps.last;

    if (exercise.progressionScheme == ProgressionScheme.manual) {
      return previousRep;
    }

    if (progressionDecision != null) {
      return switch (progressionDecision.action) {
        ProgressionAction.increaseReps => math.min(
          maxReps,
          previousRep + exercise.progressionRepStep,
        ),
        ProgressionAction.increaseLoad =>
          exercise.progressionScheme == ProgressionScheme.doubleProgression
              ? minReps
              : exercise.reps,
        ProgressionAction.deload => minReps,
        ProgressionAction.maintain => previousRep.clamp(minReps, maxReps),
        ProgressionAction.manual => previousRep,
      };
    }

    if (exercise.progressionScheme == ProgressionScheme.loadOnly ||
        exercise.progressionScheme == ProgressionScheme.linear) {
      return exercise.reps;
    }
    if (exercise.progressionScheme == ProgressionScheme.repsOnly) {
      return math.min(maxReps, previousRep + exercise.progressionRepStep);
    }
    if (previousRep >= maxReps) return minReps;
    return math.min(maxReps, previousRep + exercise.progressionRepStep);
  }

  List<ExerciseSet> setsForExercise(
    Exercise exercise,
    List<double> previousWeights,
    List<int> previousReps,
    ProgressionDecision? progressionDecision,
  ) {
    final isBackoff =
        exercise.technique == IntensityTechnique.topsetBackoff &&
        exercise.backoffReps != null;

    if (isBackoff) {
      final topWeight = weightForSet(
        exercise,
        previousWeights,
        previousReps,
        progressionDecision,
        0,
      );
      return [
        ExerciseSet(
          weight: topWeight,
          reps: repsForSet(exercise, previousReps, progressionDecision, 0),
        ),
        ExerciseSet(
          weight: top_set_backoff.recommendedBackoffWeight(
            topWeight,
            reductionPercent: exercise.backoffReductionPercent,
          ),
          reps: exercise.backoffReps!,
        ),
      ];
    }

    return List.generate(
      exercise.set,
      (index) => ExerciseSet(
        weight: weightForSet(
          exercise,
          previousWeights,
          previousReps,
          progressionDecision,
          index,
        ),
        reps: repsForSet(exercise, previousReps, progressionDecision, index),
      ),
    );
  }

  WorkoutExercise workoutExerciseFromExercise(
    Exercise exercise,
    WorkoutSession? previousSession, {
    bool keepSourceExerciseId = true,
  }) {
    final previousExercise = previousExerciseFor(exercise, previousSession);
    final previousWeights = previousWeightsFor(previousExercise);
    final previousReps = previousRepsFor(previousExercise);
    final progressionDecision = previousExercise == null
        ? null
        : _progressionDecisionFor(previousExercise, previousSession);

    return WorkoutExercise(
      sourceExerciseId: keepSourceExerciseId ? exercise.id : null,
      catalogId: exercise.catalogId,
      name: exercise.name,
      notes: exercise.notes,
      muscleGroup: exercise.muscleGroup,
      equipment: exercise.equipment,
      movementPattern: exercise.movementPattern,
      targetMinReps: exercise.targetMinReps,
      targetMaxReps: exercise.targetMaxReps,
      technique: exercise.technique,
      backoffReductionPercent: exercise.backoffReductionPercent,
      restSeconds: exercise.restSeconds,
      supersetGroup: exercise.supersetGroup,
      progressionKgStep: exercise.progressionKgStep,
      progressionRepStep: exercise.progressionRepStep,
      progressionScheme: exercise.progressionScheme,
      sets: setsForExercise(
        exercise,
        previousWeights,
        previousReps,
        progressionDecision,
      ),
      previousWeights: previousWeights,
      previousReps: previousReps,
    );
  }

  WorkoutSession buildFromSchedule(Schedule schedule) {
    final currentTime = _now();
    final previousSession = latestSessionForSchedule(schedule);
    final session = WorkoutSession(
      scheduleId: schedule.id,
      scheduleVersionId: schedule.currentVersionId,
      scheduleTitle: schedule.title,
      startTime: currentTime,
      endTime: currentTime,
      exercises: schedule.exercises
          .map(
            (exercise) =>
                workoutExerciseFromExercise(exercise, previousSession),
          )
          .toList(),
    );

    if (schedule.isDeloadWeek(now: currentTime)) {
      applyDeloadToSession(session);
    }
    return session;
  }

  WorkoutSession buildEmptySession({String title = 'Sessione'}) {
    final currentTime = _now();
    return WorkoutSession(
      scheduleTitle: title,
      startTime: currentTime,
      endTime: currentTime,
      exercises: [],
    );
  }

  void applyDeloadToSession(WorkoutSession session) {
    for (final exercise in session.exercises) {
      for (final set in exercise.sets) {
        set.weight = deloadWeight(set.weight);
      }
    }
  }

  Exercise exerciseFromWorkoutExercise(WorkoutExercise exercise) {
    final workSets = exercise.sets.where((set) => !set.isWarmup).toList();
    final sourceSet = workSets.isNotEmpty
        ? workSets.first
        : (exercise.sets.isNotEmpty ? exercise.sets.first : null);
    final isBackoff = exercise.technique == IntensityTechnique.topsetBackoff;
    final reps = sourceSet?.reps ?? exercise.targetMinReps ?? 10;
    final backoffReps = isBackoff
        ? (workSets.length > 1 ? workSets[1].reps : reps)
        : null;

    return Exercise(
      catalogId: exercise.catalogId,
      name: exercise.name,
      set: isBackoff ? 2 : math.max(1, workSets.length),
      reps: reps,
      weight: sourceSet?.weight ?? 0,
      muscleGroup: exercise.muscleGroup,
      equipment: exercise.equipment,
      movementPattern: exercise.movementPattern,
      targetMinReps: exercise.targetMinReps,
      targetMaxReps: exercise.targetMaxReps,
      notes: exercise.notes,
      technique: exercise.technique,
      backoffReductionPercent: exercise.backoffReductionPercent,
      backoffReps: backoffReps,
      restSeconds: exercise.restSeconds,
      supersetGroup: exercise.supersetGroup,
      progressionKgStep: exercise.progressionKgStep,
      progressionRepStep: exercise.progressionRepStep,
      progressionScheme: exercise.progressionScheme,
    );
  }

  Iterable<ExerciseSet> _preferredPreviousSets(WorkoutExercise exercise) {
    final completedSets = exercise.sets.where((set) => set.isCompleted);
    return completedSets.isEmpty ? exercise.sets : completedSets;
  }

  ProgressionDecision _progressionDecisionFor(
    WorkoutExercise previousExercise,
    WorkoutSession? previousSession,
  ) {
    final baseDecision = buildProgressionDecision(
      exercise: previousExercise,
      history: history,
      excludeSessionId: previousSession?.id,
    );
    final readiness = buildExerciseReadinessReport(
      history: history,
      bodyLogs: bodyLogs,
      exerciseName: previousExercise.name,
      muscleGroup: previousExercise.muscleGroup,
      now: _now(),
    );
    return applyReadinessToProgression(
      decision: baseDecision,
      readiness: readiness,
    );
  }
}
