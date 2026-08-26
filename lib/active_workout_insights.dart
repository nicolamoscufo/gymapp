import 'models/workout.dart';
import 'workout_progression_analytics.dart';

enum ActiveWorkoutPrKind {
  weight,
  reps,
  setVolume,
  estimatedOneRepMax,
  exerciseVolume,
}

extension ActiveWorkoutPrKindLabel on ActiveWorkoutPrKind {
  String get legacyLabel => switch (this) {
    ActiveWorkoutPrKind.weight => 'PR kg',
    ActiveWorkoutPrKind.reps => 'PR reps',
    ActiveWorkoutPrKind.setVolume => 'PR set',
    ActiveWorkoutPrKind.estimatedOneRepMax => 'PR e1RM',
    ActiveWorkoutPrKind.exerciseVolume => 'PR volume',
  };

  String get displayLabel => switch (this) {
    ActiveWorkoutPrKind.weight => 'Carico',
    ActiveWorkoutPrKind.reps => 'Reps',
    ActiveWorkoutPrKind.setVolume => 'Volume set',
    ActiveWorkoutPrKind.estimatedOneRepMax => 'e1RM',
    ActiveWorkoutPrKind.exerciseVolume => 'Volume esercizio',
  };
}

class ActiveWorkoutPrEvent {
  const ActiveWorkoutPrEvent({required this.exerciseName, required this.kinds});

  final String exerciseName;
  final List<ActiveWorkoutPrKind> kinds;

  String get headline => kinds.length == 1
      ? 'Nuovo record personale!'
      : '${kinds.length} nuovi record personali!';

  String get summary => kinds.map((kind) => kind.displayLabel).join(' · ');

  List<String> get legacyLabels =>
      kinds.map((kind) => kind.legacyLabel).toList(growable: false);
}

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

  ActiveWorkoutPrEvent? personalRecordEventFor(
    WorkoutExercise exercise,
    ExerciseSet set,
    int setIndex,
  ) {
    if (!set.isCompleted || set.isWarmup) {
      return null;
    }

    final kinds = <ActiveWorkoutPrKind>[];
    final maxWeight = maxHistoricalWeightFor(exercise);
    if (maxWeight != null && set.weight > maxWeight) {
      kinds.add(ActiveWorkoutPrKind.weight);
    }

    final maxReps = maxHistoricalRepsFor(exercise);
    if (maxReps != null && set.reps > maxReps) {
      kinds.add(ActiveWorkoutPrKind.reps);
    }

    final bestSetVolume = bestHistoricalSetVolumeFor(exercise);
    if (bestSetVolume != null && setVolume(set) > bestSetVolume) {
      kinds.add(ActiveWorkoutPrKind.setVolume);
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
      kinds.add(ActiveWorkoutPrKind.estimatedOneRepMax);
    }

    final bestExerciseVolume = bestHistoricalExerciseVolumeFor(exercise);
    if (bestExerciseVolume != null &&
        lastCompletedWorkSetIndex(exercise) == setIndex &&
        completedExerciseVolume(exercise) > bestExerciseVolume) {
      kinds.add(ActiveWorkoutPrKind.exerciseVolume);
    }

    if (kinds.isEmpty) {
      return null;
    }
    return ActiveWorkoutPrEvent(exerciseName: exercise.name, kinds: kinds);
  }

  List<String> personalRecordLabelsFor(
    WorkoutExercise exercise,
    ExerciseSet set,
    int setIndex,
  ) {
    return personalRecordEventFor(exercise, set, setIndex)?.legacyLabels ??
        const [];
  }

  int sessionPrCount(WorkoutSession session) {
    var count = 0;
    for (final exercise in session.exercises) {
      for (var index = 0; index < exercise.sets.length; index++) {
        if (personalRecordEventFor(exercise, exercise.sets[index], index) !=
            null) {
          count++;
        }
      }
    }
    return count;
  }

  String _normalizeExerciseName(String name) => name.trim().toLowerCase();
}
