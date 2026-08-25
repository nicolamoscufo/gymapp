import 'dart:math' as math;

import 'models/workout.dart';

/// Conservative Epley estimate intended for normal strength-training sets.
///
/// Very high-rep sets are deliberately excluded because estimated 1RM becomes
/// increasingly noisy and would create misleading PRs.
double? estimateOneRepMax(double weight, int reps) {
  if (weight <= 0 || reps <= 0 || reps > 12) {
    return null;
  }
  if (reps == 1) {
    return weight;
  }
  return weight * (1 + reps / 30.0);
}

double? bestEstimatedOneRepMaxForSets(Iterable<ExerciseSet> sets) {
  double? best;
  for (final set in sets) {
    final estimate = estimateOneRepMax(set.weight, set.reps);
    if (estimate == null) {
      continue;
    }
    if (best == null || estimate > best) {
      best = estimate;
    }
  }
  return best;
}

class ExercisePerformanceSnapshot {
  final DateTime date;
  final double topSetWeight;
  final int topSetReps;
  final double bestWeight;
  final double bestSetVolume;
  final double totalVolume;
  final double? estimatedOneRepMax;

  const ExercisePerformanceSnapshot({
    required this.date,
    required this.topSetWeight,
    required this.topSetReps,
    required this.bestWeight,
    required this.bestSetVolume,
    required this.totalVolume,
    required this.estimatedOneRepMax,
  });
}

String normalizeExerciseName(String value) => value.trim().toLowerCase();

List<ExercisePerformanceSnapshot> buildExercisePerformanceHistory({
  required List<WorkoutSession> history,
  required String exerciseName,
  String? excludeSessionId,
}) {
  final normalizedName = normalizeExerciseName(exerciseName);
  final snapshots = <ExercisePerformanceSnapshot>[];

  for (final session in history) {
    if (excludeSessionId != null && session.id == excludeSessionId) {
      continue;
    }

    final workSets = session.exercises
        .where(
          (exercise) => normalizeExerciseName(exercise.name) == normalizedName,
        )
        .expand((exercise) => exercise.sets)
        .where((set) => set.isCompleted && !set.isWarmup)
        .toList();

    if (workSets.isEmpty) {
      continue;
    }

    var bestWeight = 0.0;
    var bestSetVolume = 0.0;
    var totalVolume = 0.0;
    ExerciseSet? topSet;
    double? topEstimate;

    for (final set in workSets) {
      bestWeight = math.max(bestWeight, set.weight);
      final setVolume = set.weight * set.reps;
      bestSetVolume = math.max(bestSetVolume, setVolume);
      totalVolume += setVolume;

      final estimate = estimateOneRepMax(set.weight, set.reps);
      if (estimate != null &&
          (topEstimate == null || estimate > topEstimate)) {
        topEstimate = estimate;
        topSet = set;
      }
    }

    topSet ??= workSets.reduce(
      (left, right) => left.weight >= right.weight ? left : right,
    );

    snapshots.add(
      ExercisePerformanceSnapshot(
        date: session.endTime,
        topSetWeight: topSet.weight,
        topSetReps: topSet.reps,
        bestWeight: bestWeight,
        bestSetVolume: bestSetVolume,
        totalVolume: totalVolume,
        estimatedOneRepMax: topEstimate,
      ),
    );
  }

  snapshots.sort((a, b) => a.date.compareTo(b.date));
  return snapshots;
}

double? historicalBestEstimatedOneRepMax({
  required List<WorkoutSession> history,
  required String exerciseName,
  String? excludeSessionId,
}) {
  double? best;
  for (final snapshot in buildExercisePerformanceHistory(
    history: history,
    exerciseName: exerciseName,
    excludeSessionId: excludeSessionId,
  )) {
    final estimate = snapshot.estimatedOneRepMax;
    if (estimate != null && (best == null || estimate > best)) {
      best = estimate;
    }
  }
  return best;
}

double? latestEstimatedOneRepMaxTrendPercent(
  List<ExercisePerformanceSnapshot> snapshots,
) {
  final values = snapshots
      .where((snapshot) => snapshot.estimatedOneRepMax != null)
      .toList();
  if (values.length < 2) {
    return null;
  }

  final previous = values[values.length - 2].estimatedOneRepMax!;
  final latest = values.last.estimatedOneRepMax!;
  if (previous <= 0) {
    return null;
  }
  return ((latest - previous) / previous) * 100;
}

class WarmupSuggestion {
  final double weight;
  final int reps;
  final double loadFraction;

  const WarmupSuggestion({
    required this.weight,
    required this.reps,
    required this.loadFraction,
  });
}

double _roundedWarmupWeight(double workWeight, double fraction) {
  final rounded = (workWeight * fraction * 2).roundToDouble() / 2;
  if (workWeight <= 0.5) {
    return 0;
  }
  return math.max(0, math.min(workWeight - 0.5, rounded));
}

List<WarmupSuggestion> buildAdaptiveWarmupPlan({
  required double workWeight,
  required int workReps,
}) {
  if (workWeight <= 0) {
    return const [];
  }

  final reps = workReps.clamp(1, 20).toInt();
  final fractions = workWeight < 20
      ? const [0.50, 0.75]
      : workWeight < 50
      ? const [0.40, 0.65, 0.80]
      : const [0.40, 0.60, 0.75, 0.875];

  int repsForIndex(int index) => switch (index) {
    0 => (reps + 2).clamp(5, 10).toInt(),
    1 => reps.clamp(3, 6).toInt(),
    2 => (reps - 2).clamp(2, 4).toInt(),
    _ => reps <= 5 ? 1 : 2,
  };

  return List.generate(
    fractions.length,
    (index) => WarmupSuggestion(
      weight: _roundedWarmupWeight(workWeight, fractions[index]),
      reps: repsForIndex(index),
      loadFraction: fractions[index],
    ),
  );
}
