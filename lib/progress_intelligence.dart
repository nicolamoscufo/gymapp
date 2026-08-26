import 'dart:math' as math;

import 'models/exercise.dart';
import 'models/workout.dart';
import 'progress_analytics.dart';

enum ProgressMomentum { growing, stable, declining, insufficient }

extension ProgressMomentumLabel on ProgressMomentum {
  String get label => switch (this) {
    ProgressMomentum.growing => 'In crescita',
    ProgressMomentum.stable => 'Stabile',
    ProgressMomentum.declining => 'In calo',
    ProgressMomentum.insufficient => 'Dati insufficienti',
  };
}

class ExerciseProgressInsight {
  final String name;
  final MuscleGroup muscleGroup;
  final ProgressMomentum momentum;
  final double? estimatedOneRepMaxWindowChangePercent;
  final double? volumeWindowChangePercent;
  final int sessionCount;
  final DateTime lastTrainedAt;
  final int daysSinceLastTrained;
  final bool isStale;

  const ExerciseProgressInsight({
    required this.name,
    required this.muscleGroup,
    required this.momentum,
    required this.estimatedOneRepMaxWindowChangePercent,
    required this.volumeWindowChangePercent,
    required this.sessionCount,
    required this.lastTrainedAt,
    required this.daysSinceLastTrained,
    required this.isStale,
  });

  String get primarySignal {
    final change = estimatedOneRepMaxWindowChangePercent;
    if (change == null) {
      return 'Servono almeno 4 sessioni con e1RM valido.';
    }
    final sign = change > 0 ? '+' : '';
    return 'e1RM medio $sign${change.toStringAsFixed(1)}% vs blocco precedente';
  }
}

class MuscleVolumeShift {
  final MuscleGroup muscleGroup;
  final int recentSets;
  final int previousSets;
  final double? setChangePercent;

  const MuscleVolumeShift({
    required this.muscleGroup,
    required this.recentSets,
    required this.previousSets,
    required this.setChangePercent,
  });

  bool get newlyActive => previousSets == 0 && recentSets > 0;
}

class ProgressCenterIntelligence {
  final List<ExerciseProgressInsight> exercises;
  final List<MuscleVolumeShift> muscleShifts;
  final int personalRecordsLast30Days;
  final int personalRecordsPrevious30Days;

  const ProgressCenterIntelligence({
    required this.exercises,
    required this.muscleShifts,
    required this.personalRecordsLast30Days,
    required this.personalRecordsPrevious30Days,
  });

  int get growingCount => exercises
      .where((entry) => entry.momentum == ProgressMomentum.growing)
      .length;

  int get stableCount => exercises
      .where((entry) => entry.momentum == ProgressMomentum.stable)
      .length;

  int get decliningCount => exercises
      .where((entry) => entry.momentum == ProgressMomentum.declining)
      .length;

  int get staleCount => exercises.where((entry) => entry.isStale).length;

  List<ExerciseProgressInsight> get attentionExercises {
    final entries = exercises
        .where(
          (entry) =>
              entry.momentum == ProgressMomentum.declining || entry.isStale,
        )
        .toList();
    entries.sort((a, b) {
      final aDeclining = a.momentum == ProgressMomentum.declining ? 0 : 1;
      final bDeclining = b.momentum == ProgressMomentum.declining ? 0 : 1;
      final byKind = aDeclining.compareTo(bDeclining);
      if (byKind != 0) return byKind;
      final aChange = a.estimatedOneRepMaxWindowChangePercent ?? 0;
      final bChange = b.estimatedOneRepMaxWindowChangePercent ?? 0;
      final byChange = aChange.compareTo(bChange);
      if (byChange != 0) return byChange;
      return b.daysSinceLastTrained.compareTo(a.daysSinceLastTrained);
    });
    return entries;
  }
}

ProgressCenterIntelligence buildProgressCenterIntelligence({
  required List<WorkoutSession> history,
  required ProgressAnalytics analytics,
  DateTime? now,
}) {
  final reference = _dateOnly(now ?? DateTime.now());
  final exerciseInsights =
      analytics.exercises
          .map((summary) => _buildExerciseInsight(summary, reference))
          .toList()
        ..sort((a, b) => b.lastTrainedAt.compareTo(a.lastTrainedAt));

  final recentStart = reference.subtract(const Duration(days: 29));
  final previousStart = recentStart.subtract(const Duration(days: 30));
  final recentMuscleSets = <MuscleGroup, int>{};
  final previousMuscleSets = <MuscleGroup, int>{};

  for (final session in history) {
    final day = _dateOnly(session.startTime);
    if (day.isAfter(reference) || day.isBefore(previousStart)) continue;
    final bucket = !day.isBefore(recentStart)
        ? recentMuscleSets
        : previousMuscleSets;
    for (final exercise in session.exercises) {
      final completedWorkSets = exercise.sets
          .where((set) => set.isCompleted && !set.isWarmup)
          .length;
      if (completedWorkSets == 0) continue;
      bucket.update(
        exercise.muscleGroup,
        (value) => value + completedWorkSets,
        ifAbsent: () => completedWorkSets,
      );
    }
  }

  final muscleGroups = <MuscleGroup>{
    ...recentMuscleSets.keys,
    ...previousMuscleSets.keys,
  };
  final muscleShifts = muscleGroups.map((group) {
    final recent = recentMuscleSets[group] ?? 0;
    final previous = previousMuscleSets[group] ?? 0;
    return MuscleVolumeShift(
      muscleGroup: group,
      recentSets: recent,
      previousSets: previous,
      setChangePercent: previous <= 0
          ? null
          : ((recent - previous) / previous) * 100,
    );
  }).toList()..sort((a, b) => b.recentSets.compareTo(a.recentSets));

  var recentPrs = 0;
  var previousPrs = 0;
  for (final record in analytics.personalRecords) {
    final day = _dateOnly(record.date);
    if (day.isAfter(reference) || day.isBefore(previousStart)) continue;
    if (!day.isBefore(recentStart)) {
      recentPrs++;
    } else {
      previousPrs++;
    }
  }

  return ProgressCenterIntelligence(
    exercises: List.unmodifiable(exerciseInsights),
    muscleShifts: List.unmodifiable(muscleShifts),
    personalRecordsLast30Days: recentPrs,
    personalRecordsPrevious30Days: previousPrs,
  );
}

ExerciseProgressInsight _buildExerciseInsight(
  ExerciseProgressSummary summary,
  DateTime reference,
) {
  final eligiblePoints = summary.points
      .where((point) => !_dateOnly(point.date).isAfter(reference))
      .toList();
  final e1rmValues = eligiblePoints
      .where((point) => point.estimatedOneRepMax != null)
      .map((point) => point.estimatedOneRepMax!)
      .toList();

  final e1rmChange = _windowChange(e1rmValues);
  final volumeChange = _windowChange(
    eligiblePoints.map((point) => point.volume).toList(),
  );
  final momentum = e1rmChange == null
      ? ProgressMomentum.insufficient
      : e1rmChange > 2
      ? ProgressMomentum.growing
      : e1rmChange < -2
      ? ProgressMomentum.declining
      : ProgressMomentum.stable;

  final lastDay = _dateOnly(summary.lastTrainedAt);
  final daysSince = math.max(0, reference.difference(lastDay).inDays);

  return ExerciseProgressInsight(
    name: summary.name,
    muscleGroup: summary.muscleGroup,
    momentum: momentum,
    estimatedOneRepMaxWindowChangePercent: e1rmChange,
    volumeWindowChangePercent: volumeChange,
    sessionCount: summary.sessionCount,
    lastTrainedAt: summary.lastTrainedAt,
    daysSinceLastTrained: daysSince,
    isStale: summary.sessionCount >= 2 && daysSince >= 21,
  );
}

double? _windowChange(List<double> values) {
  if (values.length < 4) return null;
  final windowSize = math.min(3, values.length ~/ 2);
  final recent = values.sublist(values.length - windowSize);
  final previous = values.sublist(
    values.length - (windowSize * 2),
    values.length - windowSize,
  );
  final recentAverage = _average(recent);
  final previousAverage = _average(previous);
  if (previousAverage <= 0) return null;
  return ((recentAverage - previousAverage) / previousAverage) * 100;
}

double _average(List<double> values) =>
    values.reduce((left, right) => left + right) / values.length;

DateTime _dateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);
