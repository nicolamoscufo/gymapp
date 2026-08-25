import 'dart:math' as math;

import 'models/body_log.dart';
import 'models/exercise.dart';
import 'models/workout.dart';
import 'workout_progression_analytics.dart';

enum ReadinessStatus { fresh, ready, caution, fatigued, recovery }

enum SessionAdaptation {
  normal,
  holdProgression,
  reduceIntensity,
  reduceVolumeAndIntensity,
}

extension ReadinessStatusLabel on ReadinessStatus {
  String get label => switch (this) {
    ReadinessStatus.fresh => 'Fresco',
    ReadinessStatus.ready => 'Pronto',
    ReadinessStatus.caution => 'Attenzione',
    ReadinessStatus.fatigued => 'Affaticato',
    ReadinessStatus.recovery => 'Recupero',
  };
}

extension SessionAdaptationLabel on SessionAdaptation {
  String get label => switch (this) {
    SessionAdaptation.normal => 'Sessione normale',
    SessionAdaptation.holdProgression => 'Mantieni la progressione',
    SessionAdaptation.reduceIntensity => 'Riduci intensita',
    SessionAdaptation.reduceVolumeAndIntensity => 'Riduci volume e intensita',
  };
}

class FatigueReadinessReport {
  final int score;
  final ReadinessStatus status;
  final SessionAdaptation adaptation;
  final List<String> reasons;
  final int sessionsLast7Days;
  final int? hoursSinceLastStimulus;
  final double? averageRir;
  final double? averageRpe;
  final double? acuteVolumeRatio;
  final double? estimatedOneRepMaxTrendPercent;
  final int? selfReadiness;
  final int? sleepHours;
  final double recommendedLoadMultiplier;
  final int recommendedSetReduction;

  const FatigueReadinessReport({
    required this.score,
    required this.status,
    required this.adaptation,
    required this.reasons,
    required this.sessionsLast7Days,
    required this.hoursSinceLastStimulus,
    required this.averageRir,
    required this.averageRpe,
    required this.acuteVolumeRatio,
    required this.estimatedOneRepMaxTrendPercent,
    required this.selfReadiness,
    required this.sleepHours,
    required this.recommendedLoadMultiplier,
    required this.recommendedSetReduction,
  });

  Map<String, dynamic> toJson() => {
    'score': score,
    'status': status.name,
    'adaptation': adaptation.name,
    'reasons': reasons,
    'sessions_last_7_days': sessionsLast7Days,
    'hours_since_last_stimulus': hoursSinceLastStimulus,
    'average_rir': averageRir,
    'average_rpe': averageRpe,
    'acute_volume_ratio': acuteVolumeRatio,
    'estimated_1rm_trend_percent': estimatedOneRepMaxTrendPercent,
    'self_readiness': selfReadiness,
    'sleep_hours': sleepHours,
    'recommended_load_multiplier': recommendedLoadMultiplier,
    'recommended_set_reduction': recommendedSetReduction,
  };
}

bool _sameExercise(String left, String right) =>
    normalizeExerciseName(left) == normalizeExerciseName(right);

bool _matchesMuscle(WorkoutExercise exercise, MuscleGroup muscleGroup) {
  if (muscleGroup == MuscleGroup.unassigned) {
    return false;
  }
  return exercise.muscleGroup == muscleGroup;
}

Iterable<ExerciseSet> _completedWorkSets(WorkoutExercise exercise) =>
    exercise.sets.where((set) => set.isCompleted && !set.isWarmup);

double _exerciseVolume(WorkoutExercise exercise) => _completedWorkSets(exercise)
    .fold<double>(0, (sum, set) => sum + set.weight * set.reps);

double? _effectiveRir(ExerciseSet set) {
  if (set.rir != null) {
    return set.rir!.toDouble();
  }
  if (set.rpe != null) {
    return (10 - set.rpe!).clamp(0, 5).toDouble();
  }
  if (set.type == SetType.failure) {
    return 0;
  }
  return null;
}

BodyLog? _latestRelevantBodyLog(List<BodyLog> bodyLogs, DateTime now) {
  final candidates = bodyLogs
      .where(
        (entry) =>
            !entry.date.isAfter(now) &&
            now.difference(entry.date).inHours <= 72 &&
            (entry.readiness != null || entry.sleepHours != null),
      )
      .toList()
    ..sort((a, b) => b.date.compareTo(a.date));
  return candidates.isEmpty ? null : candidates.first;
}

ReadinessStatus _statusForScore(int score) {
  if (score >= 85) return ReadinessStatus.fresh;
  if (score >= 70) return ReadinessStatus.ready;
  if (score >= 55) return ReadinessStatus.caution;
  if (score >= 40) return ReadinessStatus.fatigued;
  return ReadinessStatus.recovery;
}

SessionAdaptation _adaptationForStatus(ReadinessStatus status) {
  return switch (status) {
    ReadinessStatus.fresh || ReadinessStatus.ready => SessionAdaptation.normal,
    ReadinessStatus.caution => SessionAdaptation.holdProgression,
    ReadinessStatus.fatigued => SessionAdaptation.reduceIntensity,
    ReadinessStatus.recovery =>
      SessionAdaptation.reduceVolumeAndIntensity,
  };
}

double _loadMultiplierForStatus(ReadinessStatus status) {
  return switch (status) {
    ReadinessStatus.fresh || ReadinessStatus.ready => 1.0,
    ReadinessStatus.caution => 1.0,
    ReadinessStatus.fatigued => 0.95,
    ReadinessStatus.recovery => 0.90,
  };
}

int _setReductionForStatus(ReadinessStatus status) {
  return switch (status) {
    ReadinessStatus.fresh || ReadinessStatus.ready || ReadinessStatus.caution =>
      0,
    ReadinessStatus.fatigued || ReadinessStatus.recovery => 1,
  };
}

FatigueReadinessReport buildExerciseReadinessReport({
  required List<WorkoutSession> history,
  required List<BodyLog> bodyLogs,
  required String exerciseName,
  required MuscleGroup muscleGroup,
  DateTime? now,
  String? excludeSessionId,
  WorkoutExercise? currentExercise,
}) {
  final referenceTime = now ?? DateTime.now();
  final cutoff7 = referenceTime.subtract(const Duration(days: 7));
  final cutoff3 = referenceTime.subtract(const Duration(days: 3));
  final baselineStart = referenceTime.subtract(const Duration(days: 28));

  bool matches(WorkoutExercise exercise) {
    if (_matchesMuscle(exercise, muscleGroup)) {
      return true;
    }
    return _sameExercise(exercise.name, exerciseName);
  }

  final relevantSessions = history
      .where(
        (session) =>
            session.id != excludeSessionId &&
            !session.endTime.isAfter(referenceTime) &&
            session.exercises.any(matches),
      )
      .toList()
    ..sort((a, b) => a.endTime.compareTo(b.endTime));

  final sessionsLast7Days = relevantSessions
      .where((session) => !session.endTime.isBefore(cutoff7))
      .length;

  int? hoursSinceLastStimulus;
  if (relevantSessions.isNotEmpty) {
    hoursSinceLastStimulus = referenceTime
        .difference(relevantSessions.last.endTime)
        .inHours
        .clamp(0, 100000)
        .toInt();
  }

  final effortSets = <ExerciseSet>[];
  for (final session in relevantSessions) {
    if (session.endTime.isBefore(cutoff7)) continue;
    for (final exercise in session.exercises.where(matches)) {
      effortSets.addAll(_completedWorkSets(exercise));
    }
  }
  if (currentExercise != null && matches(currentExercise)) {
    effortSets.addAll(_completedWorkSets(currentExercise));
  }

  final rirValues = <double>[];
  final rpeValues = <double>[];
  for (final set in effortSets) {
    final rir = _effectiveRir(set);
    if (rir != null) rirValues.add(rir);
    if (set.rpe != null) rpeValues.add(set.rpe!);
  }
  final averageRir = rirValues.isEmpty
      ? null
      : rirValues.reduce((a, b) => a + b) / rirValues.length;
  final averageRpe = rpeValues.isEmpty
      ? null
      : rpeValues.reduce((a, b) => a + b) / rpeValues.length;

  var acuteVolume = 0.0;
  var baselineVolume = 0.0;
  for (final session in relevantSessions) {
    for (final exercise in session.exercises.where(matches)) {
      final volume = _exerciseVolume(exercise);
      if (!session.endTime.isBefore(cutoff3)) {
        acuteVolume += volume;
      } else if (!session.endTime.isBefore(baselineStart)) {
        baselineVolume += volume;
      }
    }
  }
  final expectedThreeDayBaseline = baselineVolume <= 0
      ? null
      : (baselineVolume / 25.0) * 3.0;
  final acuteVolumeRatio = expectedThreeDayBaseline == null ||
          expectedThreeDayBaseline <= 0
      ? null
      : acuteVolume / expectedThreeDayBaseline;

  final exerciseSnapshots = buildExercisePerformanceHistory(
    history: history,
    exerciseName: exerciseName,
    excludeSessionId: excludeSessionId,
  );
  final e1rmTrend = latestEstimatedOneRepMaxTrendPercent(exerciseSnapshots);
  final bodyLog = _latestRelevantBodyLog(bodyLogs, referenceTime);

  var score = 78;
  final reasons = <String>[];

  if (hoursSinceLastStimulus != null) {
    if (hoursSinceLastStimulus < 24) {
      score -= 24;
      reasons.add('Stesso distretto allenato meno di 24 ore fa.');
    } else if (hoursSinceLastStimulus < 36) {
      score -= 14;
      reasons.add('Recupero locale inferiore a 36 ore.');
    } else if (hoursSinceLastStimulus < 48) {
      score -= 6;
      reasons.add('Recupero locale ancora breve.');
    } else if (hoursSinceLastStimulus >= 72) {
      score += 5;
      reasons.add('Recupero locale superiore a 72 ore.');
    }
  }

  if (averageRir != null) {
    if (averageRir <= 0.75) {
      score -= 18;
      reasons.add('Molti set recenti sono stati vicini al cedimento.');
    } else if (averageRir <= 1.5) {
      score -= 9;
      reasons.add('Sforzo recente elevato.');
    } else if (averageRir >= 2.5) {
      score += 3;
      reasons.add('Buon margine medio nelle serie recenti.');
    }
  }

  if (acuteVolumeRatio != null) {
    if (acuteVolumeRatio >= 1.6) {
      score -= 16;
      reasons.add('Volume acuto molto sopra il tuo baseline recente.');
    } else if (acuteVolumeRatio >= 1.2) {
      score -= 8;
      reasons.add('Volume acuto sopra il baseline recente.');
    }
  }

  if (sessionsLast7Days >= 5) {
    score -= 8;
    reasons.add('Frequenza di allenamento alta negli ultimi 7 giorni.');
  }

  if (e1rmTrend != null) {
    if (e1rmTrend <= -5) {
      score -= 16;
      reasons.add('e1RM in calo marcato rispetto alla sessione precedente.');
    } else if (e1rmTrend <= -2) {
      score -= 8;
      reasons.add('e1RM in lieve calo.');
    } else if (e1rmTrend >= 2) {
      score += 4;
      reasons.add('e1RM recente in crescita.');
    }
  }

  final selfReadiness = bodyLog?.readiness;
  if (selfReadiness != null) {
    if (selfReadiness <= 3) {
      score -= 20;
      reasons.add('Readiness soggettiva molto bassa (${selfReadiness}/10).');
    } else if (selfReadiness <= 5) {
      score -= 11;
      reasons.add('Readiness soggettiva bassa (${selfReadiness}/10).');
    } else if (selfReadiness >= 8) {
      score += 4;
      reasons.add('Readiness soggettiva alta (${selfReadiness}/10).');
    }
  }

  final sleepHours = bodyLog?.sleepHours;
  if (sleepHours != null) {
    if (sleepHours < 5) {
      score -= 20;
      reasons.add('Sonno recente sotto le 5 ore.');
    } else if (sleepHours < 6) {
      score -= 12;
      reasons.add('Sonno recente insufficiente.');
    } else if (sleepHours < 7) {
      score -= 5;
      reasons.add('Sonno recente sotto le 7 ore.');
    } else if (sleepHours >= 8) {
      score += 3;
      reasons.add('Sonno recente favorevole al recupero.');
    }
  }

  score = score.clamp(0, 100).toInt();
  final status = _statusForScore(score);
  if (reasons.isEmpty) {
    reasons.add('Dati ancora limitati: usa RIR/RPE e readiness per affinare il calcolo.');
  }

  return FatigueReadinessReport(
    score: score,
    status: status,
    adaptation: _adaptationForStatus(status),
    reasons: reasons,
    sessionsLast7Days: sessionsLast7Days,
    hoursSinceLastStimulus: hoursSinceLastStimulus,
    averageRir: averageRir,
    averageRpe: averageRpe,
    acuteVolumeRatio: acuteVolumeRatio,
    estimatedOneRepMaxTrendPercent: e1rmTrend,
    selfReadiness: selfReadiness,
    sleepHours: sleepHours,
    recommendedLoadMultiplier: _loadMultiplierForStatus(status),
    recommendedSetReduction: _setReductionForStatus(status),
  );
}

FatigueReadinessReport buildGlobalReadinessReport({
  required List<WorkoutSession> history,
  required List<BodyLog> bodyLogs,
  DateTime? now,
}) {
  final referenceTime = now ?? DateTime.now();
  if (history.isEmpty) {
    final bodyLog = _latestRelevantBodyLog(bodyLogs, referenceTime);
    var score = 70;
    final reasons = <String>[];
    if (bodyLog?.readiness != null) {
      score += (bodyLog!.readiness! - 6) * 4;
      reasons.add('Readiness soggettiva ${bodyLog.readiness}/10.');
    }
    if (bodyLog?.sleepHours != null) {
      score += (bodyLog!.sleepHours! - 7) * 4;
      reasons.add('Sonno recente ${bodyLog.sleepHours}h.');
    }
    score = score.clamp(0, 100).toInt();
    final status = _statusForScore(score);
    return FatigueReadinessReport(
      score: score,
      status: status,
      adaptation: _adaptationForStatus(status),
      reasons: reasons.isEmpty
          ? const ['Servono piu dati di allenamento per stimare la fatica.']
          : reasons,
      sessionsLast7Days: 0,
      hoursSinceLastStimulus: null,
      averageRir: null,
      averageRpe: null,
      acuteVolumeRatio: null,
      estimatedOneRepMaxTrendPercent: null,
      selfReadiness: bodyLog?.readiness,
      sleepHours: bodyLog?.sleepHours,
      recommendedLoadMultiplier: _loadMultiplierForStatus(status),
      recommendedSetReduction: _setReductionForStatus(status),
    );
  }

  final latestSession = history.reduce(
    (a, b) => a.endTime.isAfter(b.endTime) ? a : b,
  );
  final primaryExercise = latestSession.exercises.isEmpty
      ? null
      : latestSession.exercises.first;
  if (primaryExercise == null) {
    return buildGlobalReadinessReport(
      history: const [],
      bodyLogs: bodyLogs,
      now: referenceTime,
    );
  }

  return buildExerciseReadinessReport(
    history: history,
    bodyLogs: bodyLogs,
    exerciseName: primaryExercise.name,
    muscleGroup: MuscleGroup.unassigned,
    now: referenceTime,
  );
}

ProgressionDecision applyReadinessToProgression({
  required ProgressionDecision decision,
  required FatigueReadinessReport readiness,
}) {
  if (decision.action == ProgressionAction.manual) {
    return decision;
  }

  ProgressionAction action = decision.action;
  double? weightDelta = decision.suggestedWeightDelta;
  int? repDelta = decision.suggestedRepDelta;
  double? weightMultiplier = decision.suggestedWeightMultiplier;
  final reasons = List<String>.from(decision.reasons);

  switch (readiness.status) {
    case ReadinessStatus.fresh:
    case ReadinessStatus.ready:
      break;
    case ReadinessStatus.caution:
      if (action == ProgressionAction.increaseLoad) {
        action = ProgressionAction.maintain;
        weightDelta = null;
        repDelta = null;
        weightMultiplier = null;
        reasons.add('Readiness ${readiness.score}/100: aumento carico sospeso.');
      }
    case ReadinessStatus.fatigued:
      if (action == ProgressionAction.increaseLoad ||
          action == ProgressionAction.increaseReps) {
        action = ProgressionAction.maintain;
        weightDelta = null;
        repDelta = null;
        weightMultiplier = null;
        reasons.add('Fatica ${readiness.score}/100: mantieni finche recuperi.');
      }
    case ReadinessStatus.recovery:
      action = ProgressionAction.deload;
      weightDelta = null;
      repDelta = null;
      weightMultiplier = 0.90;
      reasons.add('Readiness ${readiness.score}/100: priorita al recupero.');
  }

  return ProgressionDecision(
    action: action,
    confidence: decision.confidence,
    reasons: reasons,
    suggestedWeightDelta: weightDelta,
    suggestedRepDelta: repDelta,
    suggestedWeightMultiplier: weightMultiplier,
    currentEstimatedOneRepMax: decision.currentEstimatedOneRepMax,
    estimatedOneRepMaxChangePercent:
        decision.estimatedOneRepMaxChangePercent,
    volumeChangePercent: decision.volumeChangePercent,
    effectiveRir: decision.effectiveRir,
    completedWorkSets: decision.completedWorkSets,
    plannedWorkSets: decision.plannedWorkSets,
    allWorkSetsCompleted: decision.allWorkSetsCompleted,
    allAtTop: decision.allAtTop,
    anyBelowMin: decision.anyBelowMin,
  );
}
