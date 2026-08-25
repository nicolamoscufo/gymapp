import 'dart:math' as math;

import 'models/exercise.dart';
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
      if (estimate != null && (topEstimate == null || estimate > topEstimate)) {
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

enum ProgressionAction { increaseLoad, increaseReps, maintain, deload, manual }

enum ProgressionConfidence { low, medium, high }

class ProgressionDecision {
  final ProgressionAction action;
  final ProgressionConfidence confidence;
  final List<String> reasons;
  final double? suggestedWeightDelta;
  final int? suggestedRepDelta;
  final double? suggestedWeightMultiplier;
  final double? currentEstimatedOneRepMax;
  final double? estimatedOneRepMaxChangePercent;
  final double? volumeChangePercent;
  final double? effectiveRir;
  final int completedWorkSets;
  final int plannedWorkSets;
  final bool allWorkSetsCompleted;
  final bool allAtTop;
  final bool anyBelowMin;

  const ProgressionDecision({
    required this.action,
    required this.confidence,
    required this.reasons,
    required this.suggestedWeightDelta,
    required this.suggestedRepDelta,
    required this.suggestedWeightMultiplier,
    required this.currentEstimatedOneRepMax,
    required this.estimatedOneRepMaxChangePercent,
    required this.volumeChangePercent,
    required this.effectiveRir,
    required this.completedWorkSets,
    required this.plannedWorkSets,
    required this.allWorkSetsCompleted,
    required this.allAtTop,
    required this.anyBelowMin,
  });

  Map<String, dynamic> toJson() => {
    'action': action.name,
    'confidence': confidence.name,
    'reasons': reasons,
    'suggested_weight_delta': suggestedWeightDelta,
    'suggested_rep_delta': suggestedRepDelta,
    'suggested_weight_multiplier': suggestedWeightMultiplier,
    'current_estimated_1rm': currentEstimatedOneRepMax,
    'estimated_1rm_change_percent': estimatedOneRepMaxChangePercent,
    'volume_change_percent': volumeChangePercent,
    'effective_rir': effectiveRir,
    'completed_work_sets': completedWorkSets,
    'planned_work_sets': plannedWorkSets,
    'all_work_sets_completed': allWorkSetsCompleted,
    'all_at_top': allAtTop,
    'any_below_min': anyBelowMin,
  };
}

double? _percentChange(double current, double? previous) {
  if (previous == null || previous <= 0) {
    return null;
  }
  return ((current - previous) / previous) * 100;
}

double? _averageEffectiveRir(Iterable<ExerciseSet> sets) {
  final values = <double>[];
  for (final set in sets) {
    double? value = set.rir?.toDouble();
    if (value == null && set.rpe != null) {
      value = (10 - set.rpe!).clamp(0, 5).toDouble();
    }
    if (value == null && set.type == SetType.failure) {
      value = 0;
    }
    if (value != null) {
      values.add(value);
    }
  }
  if (values.isEmpty) {
    return null;
  }
  return values.reduce((a, b) => a + b) / values.length;
}

ProgressionConfidence _progressionConfidence({
  required bool hasHistory,
  required bool hasEffort,
  required bool hasEstimatedOneRepMax,
  required bool allWorkSetsCompleted,
}) {
  var signals = 0;
  if (hasHistory) signals++;
  if (hasEffort) signals++;
  if (hasEstimatedOneRepMax) signals++;
  if (allWorkSetsCompleted) signals++;
  if (signals >= 3) return ProgressionConfidence.high;
  if (signals >= 2) return ProgressionConfidence.medium;
  return ProgressionConfidence.low;
}

ProgressionDecision buildProgressionDecision({
  required WorkoutExercise exercise,
  required List<WorkoutSession> history,
  String? excludeSessionId,
}) {
  final plannedWorkSets = exercise.sets.where((set) => !set.isWarmup).toList();
  final completedWorkSets = plannedWorkSets
      .where((set) => set.isCompleted)
      .toList();
  final allWorkSetsCompleted =
      plannedWorkSets.isNotEmpty &&
      completedWorkSets.length == plannedWorkSets.length;

  if (exercise.progressionScheme == ProgressionScheme.manual) {
    return ProgressionDecision(
      action: ProgressionAction.manual,
      confidence: ProgressionConfidence.high,
      reasons: const ['Schema impostato su progressione manuale.'],
      suggestedWeightDelta: null,
      suggestedRepDelta: null,
      suggestedWeightMultiplier: null,
      currentEstimatedOneRepMax: null,
      estimatedOneRepMaxChangePercent: null,
      volumeChangePercent: null,
      effectiveRir: null,
      completedWorkSets: completedWorkSets.length,
      plannedWorkSets: plannedWorkSets.length,
      allWorkSetsCompleted: allWorkSetsCompleted,
      allAtTop: false,
      anyBelowMin: false,
    );
  }

  if (completedWorkSets.isEmpty) {
    return ProgressionDecision(
      action: ProgressionAction.maintain,
      confidence: ProgressionConfidence.low,
      reasons: const [
        'Completa almeno un set di lavoro prima di valutare la progressione.',
      ],
      suggestedWeightDelta: null,
      suggestedRepDelta: null,
      suggestedWeightMultiplier: null,
      currentEstimatedOneRepMax: null,
      estimatedOneRepMaxChangePercent: null,
      volumeChangePercent: null,
      effectiveRir: null,
      completedWorkSets: 0,
      plannedWorkSets: plannedWorkSets.length,
      allWorkSetsCompleted: false,
      allAtTop: false,
      anyBelowMin: false,
    );
  }

  final minTarget =
      exercise.targetMinReps ??
      plannedWorkSets.map((set) => set.reps).reduce(math.min);
  final maxTarget =
      exercise.targetMaxReps ??
      plannedWorkSets.map((set) => set.reps).reduce(math.max);
  final allAtTop =
      allWorkSetsCompleted &&
      completedWorkSets.every((set) => set.reps >= maxTarget);
  final anyBelowMin = completedWorkSets.any((set) => set.reps < minTarget);
  final currentEstimatedOneRepMax = bestEstimatedOneRepMaxForSets(
    completedWorkSets,
  );
  final currentVolume = completedWorkSets.fold<double>(
    0,
    (sum, set) => sum + set.weight * set.reps,
  );
  final effectiveRir = _averageEffectiveRir(completedWorkSets);

  final historicalSnapshots = buildExercisePerformanceHistory(
    history: history,
    exerciseName: exercise.name,
    excludeSessionId: excludeSessionId,
  );
  final latestHistorical = historicalSnapshots.isEmpty
      ? null
      : historicalSnapshots.last;
  final estimatedOneRepMaxChangePercent = currentEstimatedOneRepMax == null
      ? null
      : _percentChange(
          currentEstimatedOneRepMax,
          latestHistorical?.estimatedOneRepMax,
        );
  final volumeChangePercent = _percentChange(
    currentVolume,
    latestHistorical?.totalVolume,
  );
  final historicalTrend = latestEstimatedOneRepMaxTrendPercent(
    historicalSnapshots,
  );

  final confidence = _progressionConfidence(
    hasHistory: latestHistorical != null,
    hasEffort: effectiveRir != null,
    hasEstimatedOneRepMax: currentEstimatedOneRepMax != null,
    allWorkSetsCompleted: allWorkSetsCompleted,
  );

  final reasons = <String>[];
  if (estimatedOneRepMaxChangePercent != null) {
    if (estimatedOneRepMaxChangePercent >= 2) {
      reasons.add(
        'e1RM in crescita di ${estimatedOneRepMaxChangePercent.toStringAsFixed(1)}% rispetto all ultima sessione.',
      );
    } else if (estimatedOneRepMaxChangePercent <= -3) {
      reasons.add(
        'e1RM in calo di ${estimatedOneRepMaxChangePercent.abs().toStringAsFixed(1)}% rispetto all ultima sessione.',
      );
    }
  }
  if (volumeChangePercent != null) {
    if (volumeChangePercent >= 5) {
      reasons.add(
        'Volume in crescita di ${volumeChangePercent.toStringAsFixed(1)}%.',
      );
    } else if (volumeChangePercent <= -15) {
      reasons.add(
        'Volume in calo di ${volumeChangePercent.abs().toStringAsFixed(1)}%.',
      );
    }
  }
  if (effectiveRir != null) {
    reasons.add(
      'Sforzo medio stimato: RIR ${effectiveRir.toStringAsFixed(1)}.',
    );
  }

  final highEffort = effectiveRir != null && effectiveRir <= 1.0;
  final veryHighEffort = effectiveRir != null && effectiveRir <= 0.5;
  final loadReady = effectiveRir == null || effectiveRir >= 1.5;
  final currentDecline =
      (estimatedOneRepMaxChangePercent != null &&
          estimatedOneRepMaxChangePercent <= -3) ||
      (volumeChangePercent != null && volumeChangePercent <= -15);
  final repeatedDecline = historicalTrend != null && historicalTrend <= -2;
  final failureSetPresent = completedWorkSets.any(
    (set) => set.type == SetType.failure,
  );

  if (allWorkSetsCompleted &&
      (highEffort || failureSetPresent) &&
      currentDecline &&
      repeatedDecline) {
    reasons.add(
      'Calo ripetuto con sforzo alto: meglio ridurre temporaneamente il carico.',
    );
    return ProgressionDecision(
      action: ProgressionAction.deload,
      confidence: confidence,
      reasons: reasons,
      suggestedWeightDelta: null,
      suggestedRepDelta: null,
      suggestedWeightMultiplier: 0.90,
      currentEstimatedOneRepMax: currentEstimatedOneRepMax,
      estimatedOneRepMaxChangePercent: estimatedOneRepMaxChangePercent,
      volumeChangePercent: volumeChangePercent,
      effectiveRir: effectiveRir,
      completedWorkSets: completedWorkSets.length,
      plannedWorkSets: plannedWorkSets.length,
      allWorkSetsCompleted: allWorkSetsCompleted,
      allAtTop: allAtTop,
      anyBelowMin: anyBelowMin,
    );
  }

  if (!allWorkSetsCompleted) {
    reasons.add('Sessione non ancora completa: nessun aumento automatico.');
    return ProgressionDecision(
      action: ProgressionAction.maintain,
      confidence: confidence,
      reasons: reasons,
      suggestedWeightDelta: null,
      suggestedRepDelta: null,
      suggestedWeightMultiplier: null,
      currentEstimatedOneRepMax: currentEstimatedOneRepMax,
      estimatedOneRepMaxChangePercent: estimatedOneRepMaxChangePercent,
      volumeChangePercent: volumeChangePercent,
      effectiveRir: effectiveRir,
      completedWorkSets: completedWorkSets.length,
      plannedWorkSets: plannedWorkSets.length,
      allWorkSetsCompleted: allWorkSetsCompleted,
      allAtTop: allAtTop,
      anyBelowMin: anyBelowMin,
    );
  }

  if (anyBelowMin || veryHighEffort) {
    reasons.add(
      anyBelowMin
          ? 'Almeno un set e sotto il range minimo: mantieni il carico.'
          : 'Sforzo troppo vicino al cedimento per aumentare ora.',
    );
    return ProgressionDecision(
      action: ProgressionAction.maintain,
      confidence: confidence,
      reasons: reasons,
      suggestedWeightDelta: null,
      suggestedRepDelta: null,
      suggestedWeightMultiplier: null,
      currentEstimatedOneRepMax: currentEstimatedOneRepMax,
      estimatedOneRepMaxChangePercent: estimatedOneRepMaxChangePercent,
      volumeChangePercent: volumeChangePercent,
      effectiveRir: effectiveRir,
      completedWorkSets: completedWorkSets.length,
      plannedWorkSets: plannedWorkSets.length,
      allWorkSetsCompleted: allWorkSetsCompleted,
      allAtTop: allAtTop,
      anyBelowMin: anyBelowMin,
    );
  }

  if (exercise.progressionScheme == ProgressionScheme.repsOnly) {
    if (!allAtTop) {
      reasons.add(
        'Set completati nel range: aumenta le ripetizioni mantenendo il carico.',
      );
      return ProgressionDecision(
        action: ProgressionAction.increaseReps,
        confidence: confidence,
        reasons: reasons,
        suggestedWeightDelta: null,
        suggestedRepDelta: exercise.progressionRepStep,
        suggestedWeightMultiplier: null,
        currentEstimatedOneRepMax: currentEstimatedOneRepMax,
        estimatedOneRepMaxChangePercent: estimatedOneRepMaxChangePercent,
        volumeChangePercent: volumeChangePercent,
        effectiveRir: effectiveRir,
        completedWorkSets: completedWorkSets.length,
        plannedWorkSets: plannedWorkSets.length,
        allWorkSetsCompleted: allWorkSetsCompleted,
        allAtTop: allAtTop,
        anyBelowMin: anyBelowMin,
      );
    }
    reasons.add(
      'Hai raggiunto il top del range ma lo schema consente solo progressione reps.',
    );
  } else if (exercise.progressionScheme == ProgressionScheme.linear) {
    if (loadReady) {
      reasons.add('Schema lineare completato con margine sufficiente.');
      return ProgressionDecision(
        action: ProgressionAction.increaseLoad,
        confidence: confidence,
        reasons: reasons,
        suggestedWeightDelta: exercise.progressionKgStep,
        suggestedRepDelta: null,
        suggestedWeightMultiplier: null,
        currentEstimatedOneRepMax: currentEstimatedOneRepMax,
        estimatedOneRepMaxChangePercent: estimatedOneRepMaxChangePercent,
        volumeChangePercent: volumeChangePercent,
        effectiveRir: effectiveRir,
        completedWorkSets: completedWorkSets.length,
        plannedWorkSets: plannedWorkSets.length,
        allWorkSetsCompleted: allWorkSetsCompleted,
        allAtTop: allAtTop,
        anyBelowMin: anyBelowMin,
      );
    }
    reasons.add(
      'Schema lineare completato ma senza margine sufficiente per aumentare.',
    );
  } else if (exercise.progressionScheme == ProgressionScheme.loadOnly) {
    if (allAtTop && loadReady) {
      reasons.add(
        'Tutte le serie sono al top del range con margine sufficiente.',
      );
      return ProgressionDecision(
        action: ProgressionAction.increaseLoad,
        confidence: confidence,
        reasons: reasons,
        suggestedWeightDelta: exercise.progressionKgStep,
        suggestedRepDelta: null,
        suggestedWeightMultiplier: null,
        currentEstimatedOneRepMax: currentEstimatedOneRepMax,
        estimatedOneRepMaxChangePercent: estimatedOneRepMaxChangePercent,
        volumeChangePercent: volumeChangePercent,
        effectiveRir: effectiveRir,
        completedWorkSets: completedWorkSets.length,
        plannedWorkSets: plannedWorkSets.length,
        allWorkSetsCompleted: allWorkSetsCompleted,
        allAtTop: allAtTop,
        anyBelowMin: anyBelowMin,
      );
    }
    reasons.add('Non ci sono ancora le condizioni per aumentare il carico.');
  } else {
    if (allAtTop && loadReady) {
      reasons.add(
        'Doppia progressione completata al top del range con margine sufficiente.',
      );
      return ProgressionDecision(
        action: ProgressionAction.increaseLoad,
        confidence: confidence,
        reasons: reasons,
        suggestedWeightDelta: exercise.progressionKgStep,
        suggestedRepDelta: null,
        suggestedWeightMultiplier: null,
        currentEstimatedOneRepMax: currentEstimatedOneRepMax,
        estimatedOneRepMaxChangePercent: estimatedOneRepMaxChangePercent,
        volumeChangePercent: volumeChangePercent,
        effectiveRir: effectiveRir,
        completedWorkSets: completedWorkSets.length,
        plannedWorkSets: plannedWorkSets.length,
        allWorkSetsCompleted: allWorkSetsCompleted,
        allAtTop: allAtTop,
        anyBelowMin: anyBelowMin,
      );
    }
    if (!allAtTop) {
      reasons.add('Doppia progressione: prima aumenta le reps nel range.');
      return ProgressionDecision(
        action: ProgressionAction.increaseReps,
        confidence: confidence,
        reasons: reasons,
        suggestedWeightDelta: null,
        suggestedRepDelta: exercise.progressionRepStep,
        suggestedWeightMultiplier: null,
        currentEstimatedOneRepMax: currentEstimatedOneRepMax,
        estimatedOneRepMaxChangePercent: estimatedOneRepMaxChangePercent,
        volumeChangePercent: volumeChangePercent,
        effectiveRir: effectiveRir,
        completedWorkSets: completedWorkSets.length,
        plannedWorkSets: plannedWorkSets.length,
        allWorkSetsCompleted: allWorkSetsCompleted,
        allAtTop: allAtTop,
        anyBelowMin: anyBelowMin,
      );
    }
  }

  return ProgressionDecision(
    action: ProgressionAction.maintain,
    confidence: confidence,
    reasons: reasons.isEmpty
        ? const ['Mantieni il carico e rivaluta alla prossima sessione.']
        : reasons,
    suggestedWeightDelta: null,
    suggestedRepDelta: null,
    suggestedWeightMultiplier: null,
    currentEstimatedOneRepMax: currentEstimatedOneRepMax,
    estimatedOneRepMaxChangePercent: estimatedOneRepMaxChangePercent,
    volumeChangePercent: volumeChangePercent,
    effectiveRir: effectiveRir,
    completedWorkSets: completedWorkSets.length,
    plannedWorkSets: plannedWorkSets.length,
    allWorkSetsCompleted: allWorkSetsCompleted,
    allAtTop: allAtTop,
    anyBelowMin: anyBelowMin,
  );
}

String progressionActionLabel(ProgressionDecision decision) {
  return switch (decision.action) {
    ProgressionAction.increaseLoad =>
      'Aumenta carico +${decision.suggestedWeightDelta?.toStringAsFixed(1) ?? '?'} kg',
    ProgressionAction.increaseReps =>
      'Aumenta reps +${decision.suggestedRepDelta ?? 1}',
    ProgressionAction.maintain => 'Mantieni',
    ProgressionAction.deload => 'Deload -10%',
    ProgressionAction.manual => 'Manuale',
  };
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
