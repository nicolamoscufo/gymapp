import 'models/exercise.dart';
import 'models/workout.dart';
import 'top_set_backoff.dart' as top_set_backoff;
import 'workout_progression_analytics.dart';

class RemovedExerciseSet {
  const RemovedExerciseSet({
    required this.exerciseId,
    required this.set,
    required this.index,
  });

  final String exerciseId;
  final ExerciseSet set;
  final int index;
}

class ActiveWorkoutStats {
  const ActiveWorkoutStats({
    required this.completedSets,
    required this.totalSets,
    required this.volume,
    required this.exercises,
  });

  final int completedSets;
  final int totalSets;
  final double volume;
  final int exercises;
}

/// Owns mutations and derived state local to exercise sets in a live workout.
///
/// UI effects (dialogs, haptics, rest timers, snackbars and persistence) remain
/// in the screen. This class only changes the in-memory workout graph.
class ActiveWorkoutSetManager {
  ActiveWorkoutSetManager({required this.session});

  final WorkoutSession session;

  double? backoffReductionFor(WorkoutExercise exercise, int setIndex) {
    if (exercise.technique != IntensityTechnique.topsetBackoff ||
        setIndex == 0 ||
        exercise.sets.isEmpty) {
      return null;
    }

    return top_set_backoff.backoffReductionPercentFor(
      reductionPercent: exercise.backoffReductionPercent,
    );
  }

  double? recommendedBackoffWeightFor(WorkoutExercise exercise, int setIndex) {
    final reduction = backoffReductionFor(exercise, setIndex);
    if (reduction == null) return null;

    final topSetWeight = exercise.sets.first.weight;
    if (topSetWeight <= 0) return null;

    return top_set_backoff.recommendedBackoffWeight(
      topSetWeight,
      reductionPercent: reduction,
    );
  }

  bool applyRecommendedBackoffWeight(WorkoutExercise exercise, int setIndex) {
    if (setIndex < 0 || setIndex >= exercise.sets.length) return false;
    final weight = recommendedBackoffWeightFor(exercise, setIndex);
    if (weight == null) return false;
    exercise.sets[setIndex].weight = weight;
    return true;
  }

  ExerciseSet addSet(WorkoutExercise exercise, {bool isWarmup = false}) {
    final added = exercise.sets.isNotEmpty
        ? ExerciseSet(
            weight: exercise.sets.last.weight,
            reps: exercise.sets.last.reps,
            isWarmup: isWarmup,
          )
        : ExerciseSet(weight: 0, reps: 10, isWarmup: isWarmup);
    exercise.sets.add(added);
    return added;
  }

  ExerciseSet? copySet(WorkoutExercise exercise, int setIndex) {
    if (setIndex < 0 || setIndex >= exercise.sets.length) return null;
    final source = exercise.sets[setIndex];
    final copy = ExerciseSet(
      weight: source.weight,
      reps: source.reps,
      type: source.type,
      rpe: source.rpe,
      rir: source.rir,
      notes: source.notes,
    );
    exercise.sets.insert(setIndex + 1, copy);
    return copy;
  }

  List<String> validationProblems() {
    final problems = <String>[];
    for (final exercise in session.exercises) {
      for (var index = 0; index < exercise.sets.length; index++) {
        final set = exercise.sets[index];
        final label = '${exercise.name} set ${index + 1}';
        if (set.weight < 0 || set.weight > 1000) {
          problems.add('$label: kg fuori range 0-1000.');
        }
        if (set.reps <= 0 || set.reps > 200) {
          problems.add('$label: reps fuori range 1-200.');
        }
        if (set.rpe != null && (set.rpe! < 1 || set.rpe! > 10)) {
          problems.add('$label: RPE fuori range 1-10.');
        }
        if (set.rir != null && (set.rir! < 0 || set.rir! > 10)) {
          problems.add('$label: RIR fuori range 0-10.');
        }
      }
    }
    return problems;
  }

  List<ExerciseSet> warmupSetsFor(WorkoutExercise exercise) {
    ExerciseSet? workSet;
    for (final set in exercise.sets) {
      if (!set.isWarmup) {
        workSet = set;
        break;
      }
    }
    if (workSet == null) return const <ExerciseSet>[];

    return buildAdaptiveWarmupPlan(
          workWeight: workSet.weight,
          workReps: workSet.reps,
        )
        .map(
          (suggestion) => ExerciseSet(
            weight: suggestion.weight,
            reps: suggestion.reps,
            isWarmup: true,
          ),
        )
        .toList();
  }

  List<ExerciseSet> insertWarmupPlan(WorkoutExercise exercise) {
    final warmups = warmupSetsFor(exercise);
    exercise.sets.removeWhere((set) => set.isWarmup && !set.isCompleted);
    exercise.sets.insertAll(0, warmups);
    return warmups;
  }

  /// Toggles completion and returns true when this interaction completed the
  /// set (rather than reopening it).
  bool toggleSetCompleted(ExerciseSet set) {
    final willComplete = !set.isCompleted;
    set.isCompleted = !set.isCompleted;
    return willComplete;
  }

  RemovedExerciseSet? removeSet(WorkoutExercise exercise, int index) {
    if (index < 0 || index >= exercise.sets.length) return null;
    final removed = exercise.sets.removeAt(index);
    return RemovedExerciseSet(
      exerciseId: exercise.id,
      set: removed,
      index: index,
    );
  }

  bool restoreRemovedSet(WorkoutExercise exercise, RemovedExerciseSet removal) {
    if (exercise.id != removal.exerciseId ||
        exercise.sets.contains(removal.set)) {
      return false;
    }
    final restoreIndex = removal.index.clamp(0, exercise.sets.length).toInt();
    exercise.sets.insert(restoreIndex, removal.set);
    return true;
  }

  ActiveWorkoutStats get workoutStats {
    var completed = 0;
    var total = 0;
    var volume = 0.0;

    for (final exercise in session.exercises) {
      for (final set in exercise.sets) {
        total++;
        if (!set.isCompleted) continue;
        completed++;
        if (!set.isWarmup) {
          volume += set.weight * set.reps;
        }
      }
    }

    return ActiveWorkoutStats(
      completedSets: completed,
      totalSets: total,
      volume: volume,
      exercises: session.exercises.length,
    );
  }
}
