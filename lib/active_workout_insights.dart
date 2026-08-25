import 'models/workout.dart';
import 'workout_progression_analytics.dart';

/// Pure, UI-independent analytics used while logging an active workout.
///
/// Keeping historical comparisons here prevents the workout screen from
/// owning both rendering and PR/domain logic, and makes the behavior directly
/// unit-testable.
class ActiveWorkoutInsights {
  final List<WorkoutSession> history;
  final String currentSessionId;

  const ActiveWorkoutInsights({
    required this.history,
    required this.currentSessionId,
  });

  Iterable<WorkoutSession> get comparisonHistory =>
      history.where((session) => session.id != currentSessionId);

  double setVolume(ExerciseSet set) => set.weight * set.reps;

  double completedExerciseVolume(WorkoutExercise exercise) {
    return exercise.sets
        .where((set) => set.isCompleted && !set.isWarmup)
        .fold<double>(0, (total, set) => total + setVolume(set));
  }

  Iterable<WorkoutExercise> historicalExercisesFor(WorkoutExercise exercise) {
    final exerciseName = _normalizeExerciseName(exercise.name);
    return comparisonHistory.expand((historySession) {
      return historySession.exercises.where(
        (historicalExercise) =>
            _normalizeExerciseName(historicalExercise.name) == exerciseName,
      );
    });
  }

  Iterable<ExerciseSet> historicalWorkSetsFor(WorkoutExercise exercise) {
    return historicalExercisesFor(exercise)
        .expand((historicalExercise) => historicalExercise.sets)
        .where((set) => set.isCompleted && !set.isWarmup);
  }

  double? maxHistoricalWeightFor(WorkoutExercise exercise) {
    double? maxWeight;
    for (final set in historicalWorkSetsFor(exercise)) {
      if (maxWeight == null || set.weight > maxWeight) {
        maxWeight = set.weight;
      }
    }
    return maxWeight;
  }

  int? maxHistoricalRepsFor(WorkoutExercise exercise) {
    int? maxReps;
    for (final set in historicalWorkSetsFor(exercise)) {
      if (maxReps == null || set.reps > maxReps) {
        maxReps = set.reps;
      }
    }
    return maxReps;
  }

  double? bestHistoricalSetVolumeFor(WorkoutExercise exercise) {
    double? bestVolume;
    for (final set in historicalWorkSetsFor(exercise)) {
      final volume = setVolume(set);
      if (bestVolume == null || volume > bestVolume) {
        bestVolume = volume;
      }
    }
    return bestVolume;
  }

  double? bestHistoricalExerciseVolumeFor(WorkoutExercise exercise) {
    double? bestVolume;
    for (final historicalExercise in historicalExercisesFor(exercise)) {
      final volume = completedExerciseVolume(historicalExercise);
      if (volume <= 0) {
        continue;
      }
      if (bestVolume == null || volume > bestVolume) {
        bestVolume = volume;
      }
    }
    return bestVolume;
  }

  int? lastCompletedWorkSetIndex(WorkoutExercise exercise) {
    for (var index = exercise.sets.length - 1; index >= 0; index--) {
      final set = exercise.sets[index];
      if (set.isCompleted && !set.isWarmup) {
        return index;
      }
    }
    return null;
  }

  List<String> personalRecordLabelsFor(
    WorkoutExercise exercise,
    ExerciseSet set,
    int setIndex,
  ) {
    if (!set.isCompleted || set.isWarmup) {
      return const [];
    }

    final labels = <String>[];
    final maxWeight = maxHistoricalWeightFor(exercise);
    if (maxWeight != null && set.weight > maxWeight) {
      labels.add('PR kg');
    }

    final maxReps = maxHistoricalRepsFor(exercise);
    if (maxReps != null && set.reps > maxReps) {
      labels.add('PR reps');
    }

    final bestSetVolume = bestHistoricalSetVolumeFor(exercise);
    if (bestSetVolume != null && setVolume(set) > bestSetVolume) {
      labels.add('PR set');
    }

    final setEstimatedOneRepMax = estimateOneRepMax(set.weight, set.reps);
    final historicalEstimatedOneRepMax = historicalBestEstimatedOneRepMax(
      history: history,
      exerciseName: exercise.name,
      excludeSessionId: currentSessionId,
    );
    if (setEstimatedOneRepMax != null &&
        historicalEstimatedOneRepMax != null &&
        setEstimatedOneRepMax > historicalEstimatedOneRepMax + 0.05) {
      labels.add('PR e1RM');
    }

    final bestExerciseVolume = bestHistoricalExerciseVolumeFor(exercise);
    if (bestExerciseVolume != null &&
        lastCompletedWorkSetIndex(exercise) == setIndex &&
        completedExerciseVolume(exercise) > bestExerciseVolume) {
      labels.add('PR volume');
    }

    return labels;
  }

  int sessionPrCount(WorkoutSession session) {
    var count = 0;
    for (final exercise in session.exercises) {
      for (var index = 0; index < exercise.sets.length; index++) {
        if (personalRecordLabelsFor(
          exercise,
          exercise.sets[index],
          index,
        ).isNotEmpty) {
          count++;
        }
      }
    }
    return count;
  }

  String _normalizeExerciseName(String name) => name.trim().toLowerCase();
}
