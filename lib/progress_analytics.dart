import 'dart:math' as math;

import 'models/exercise.dart';
import 'models/workout.dart';

enum PersonalRecordKind {
  weight,
  reps,
  setVolume,
  estimatedOneRepMax,
  sessionVolume,
}

extension PersonalRecordKindLabel on PersonalRecordKind {
  String get label => switch (this) {
    PersonalRecordKind.weight => 'Carico',
    PersonalRecordKind.reps => 'Ripetizioni',
    PersonalRecordKind.setVolume => 'Volume set',
    PersonalRecordKind.estimatedOneRepMax => 'e1RM',
    PersonalRecordKind.sessionVolume => 'Volume esercizio',
  };
}

class ExerciseProgressPoint {
  final DateTime date;
  final double bestWeight;
  final int bestReps;
  final double volume;
  final double? estimatedOneRepMax;
  final int completedSets;

  const ExerciseProgressPoint({
    required this.date,
    required this.bestWeight,
    required this.bestReps,
    required this.volume,
    required this.estimatedOneRepMax,
    required this.completedSets,
  });

  Map<String, dynamic> toJson() => {
    'date': date.toIso8601String(),
    'best_weight': bestWeight,
    'best_reps': bestReps,
    'volume': volume,
    'estimated_1rm': estimatedOneRepMax,
    'completed_sets': completedSets,
  };
}

class ExerciseProgressSummary {
  final String name;
  final MuscleGroup muscleGroup;
  final int sessionCount;
  final int completedSets;
  final int totalReps;
  final double totalVolume;
  final double bestWeight;
  final int bestReps;
  final double bestSetVolume;
  final double bestEstimatedOneRepMax;
  final double? latestEstimatedOneRepMax;
  final double? estimatedOneRepMaxTrendPercent;
  final DateTime lastTrainedAt;
  final List<ExerciseProgressPoint> points;

  const ExerciseProgressSummary({
    required this.name,
    required this.muscleGroup,
    required this.sessionCount,
    required this.completedSets,
    required this.totalReps,
    required this.totalVolume,
    required this.bestWeight,
    required this.bestReps,
    required this.bestSetVolume,
    required this.bestEstimatedOneRepMax,
    required this.latestEstimatedOneRepMax,
    required this.estimatedOneRepMaxTrendPercent,
    required this.lastTrainedAt,
    required this.points,
  });

  Map<String, dynamic> toJson() => {
    'exercise': name,
    'muscle_group': muscleGroup.name,
    'sessions': sessionCount,
    'completed_sets': completedSets,
    'total_reps': totalReps,
    'total_volume': totalVolume,
    'best_weight': bestWeight,
    'best_reps': bestReps,
    'best_set_volume': bestSetVolume,
    'best_estimated_1rm': bestEstimatedOneRepMax,
    'latest_estimated_1rm': latestEstimatedOneRepMax,
    'estimated_1rm_trend_percent': estimatedOneRepMaxTrendPercent,
    'last_trained_at': lastTrainedAt.toIso8601String(),
    'timeline': points.map((point) => point.toJson()).toList(),
  };
}

class PersonalRecordEvent {
  final String exerciseName;
  final MuscleGroup muscleGroup;
  final PersonalRecordKind kind;
  final DateTime date;
  final double value;
  final double? weight;
  final int? reps;

  const PersonalRecordEvent({
    required this.exerciseName,
    required this.muscleGroup,
    required this.kind,
    required this.date,
    required this.value,
    this.weight,
    this.reps,
  });

  Map<String, dynamic> toJson() => {
    'exercise': exerciseName,
    'muscle_group': muscleGroup.name,
    'kind': kind.name,
    'date': date.toIso8601String(),
    'value': value,
    'weight': weight,
    'reps': reps,
  };
}

class WeeklyMusclePoint {
  final DateTime weekStart;
  final int sets;
  final double volume;

  const WeeklyMusclePoint({
    required this.weekStart,
    required this.sets,
    required this.volume,
  });

  Map<String, dynamic> toJson() => {
    'week_start': weekStart.toIso8601String(),
    'sets': sets,
    'volume': volume,
  };
}

class MuscleProgressSummary {
  final MuscleGroup muscleGroup;
  final int sets7Days;
  final int sets30Days;
  final double volume7Days;
  final double volume30Days;
  final int sessionCount30Days;
  final double setShare30Days;
  final List<WeeklyMusclePoint> weekly;

  const MuscleProgressSummary({
    required this.muscleGroup,
    required this.sets7Days,
    required this.sets30Days,
    required this.volume7Days,
    required this.volume30Days,
    required this.sessionCount30Days,
    required this.setShare30Days,
    required this.weekly,
  });

  Map<String, dynamic> toJson() => {
    'muscle_group': muscleGroup.name,
    'sets_7d': sets7Days,
    'sets_30d': sets30Days,
    'volume_7d': volume7Days,
    'volume_30d': volume30Days,
    'sessions_30d': sessionCount30Days,
    'set_share_30d': setShare30Days,
    'weekly': weekly.map((point) => point.toJson()).toList(),
  };
}

class ConsistencySummary {
  final int workouts30Days;
  final int trainedDays30Days;
  final int currentActiveWeekStreak;
  final int longestActiveWeekStreak;
  final double averageWorkoutsPerWeek8Weeks;
  final String mostActiveWeekday;

  const ConsistencySummary({
    required this.workouts30Days,
    required this.trainedDays30Days,
    required this.currentActiveWeekStreak,
    required this.longestActiveWeekStreak,
    required this.averageWorkoutsPerWeek8Weeks,
    required this.mostActiveWeekday,
  });

  Map<String, dynamic> toJson() => {
    'workouts_30d': workouts30Days,
    'trained_days_30d': trainedDays30Days,
    'current_active_week_streak': currentActiveWeekStreak,
    'longest_active_week_streak': longestActiveWeekStreak,
    'average_workouts_per_week_8w': averageWorkoutsPerWeek8Weeks,
    'most_active_weekday': mostActiveWeekday,
  };
}

class PeriodProgressReport {
  final DateTime start;
  final DateTime endExclusive;
  final int workouts;
  final int completedSets;
  final int totalReps;
  final double volume;
  final int durationMinutes;
  final int personalRecords;
  final String? topExercise;
  final MuscleGroup? topMuscleGroup;

  const PeriodProgressReport({
    required this.start,
    required this.endExclusive,
    required this.workouts,
    required this.completedSets,
    required this.totalReps,
    required this.volume,
    required this.durationMinutes,
    required this.personalRecords,
    required this.topExercise,
    required this.topMuscleGroup,
  });

  Map<String, dynamic> toJson() => {
    'start': start.toIso8601String(),
    'end_exclusive': endExclusive.toIso8601String(),
    'workouts': workouts,
    'completed_sets': completedSets,
    'total_reps': totalReps,
    'volume': volume,
    'duration_minutes': durationMinutes,
    'personal_records': personalRecords,
    'top_exercise': topExercise,
    'top_muscle_group': topMuscleGroup?.name,
  };
}

class ProgressAnalytics {
  final List<ExerciseProgressSummary> exercises;
  final List<MuscleProgressSummary> muscles;
  final List<PersonalRecordEvent> personalRecords;
  final ConsistencySummary consistency;
  final PeriodProgressReport currentMonth;
  final PeriodProgressReport currentYear;

  const ProgressAnalytics({
    required this.exercises,
    required this.muscles,
    required this.personalRecords,
    required this.consistency,
    required this.currentMonth,
    required this.currentYear,
  });

  Map<String, dynamic> toJson() => {
    'exercises': exercises.map((entry) => entry.toJson()).toList(),
    'muscles': muscles.map((entry) => entry.toJson()).toList(),
    'personal_records': personalRecords.map((entry) => entry.toJson()).toList(),
    'consistency': consistency.toJson(),
    'current_month': currentMonth.toJson(),
    'current_year': currentYear.toJson(),
  };
}

ProgressAnalytics buildProgressAnalytics({
  required List<WorkoutSession> history,
  DateTime? now,
}) {
  final reference = _dateOnly(now ?? DateTime.now());
  final sorted = [...history]
    ..sort((a, b) => a.startTime.compareTo(b.startTime));
  final personalRecords = _buildPersonalRecords(sorted);
  return ProgressAnalytics(
    exercises: _buildExerciseSummaries(sorted),
    muscles: _buildMuscleSummaries(sorted, reference),
    personalRecords: personalRecords.reversed.toList(),
    consistency: _buildConsistency(sorted, reference),
    currentMonth: _buildPeriodReport(
      sorted,
      personalRecords,
      DateTime(reference.year, reference.month),
      DateTime(reference.year, reference.month + 1),
    ),
    currentYear: _buildPeriodReport(
      sorted,
      personalRecords,
      DateTime(reference.year),
      DateTime(reference.year + 1),
    ),
  );
}

List<ExerciseProgressSummary> _buildExerciseSummaries(
  List<WorkoutSession> history,
) {
  final grouped = <String, _ExerciseAccumulator>{};
  for (final session in history) {
    for (final exercise in session.exercises) {
      final workSets = _workSets(exercise);
      if (workSets.isEmpty) continue;
      final key = _normalize(exercise.name);
      final accumulator = grouped.putIfAbsent(
        key,
        () => _ExerciseAccumulator(exercise.name, exercise.muscleGroup),
      );
      accumulator.name = exercise.name;
      accumulator.muscleGroup = exercise.muscleGroup;
      accumulator.lastTrainedAt = session.startTime;
      accumulator.sessionCount += 1;
      accumulator.completedSets += workSets.length;
      accumulator.totalReps += workSets.fold(0, (sum, set) => sum + set.reps);
      final volume = workSets.fold<double>(
        0,
        (sum, set) => sum + _setVolume(set),
      );
      accumulator.totalVolume += volume;
      final bestWeight = workSets.fold<double>(
        0,
        (best, set) => math.max(best, set.weight),
      );
      final bestReps = workSets.fold<int>(
        0,
        (best, set) => math.max(best, set.reps),
      );
      final bestSetVolume = workSets.fold<double>(
        0,
        (best, set) => math.max(best, _setVolume(set)),
      );
      final bestE1rm = _bestE1rm(workSets);
      accumulator.bestWeight = math.max(accumulator.bestWeight, bestWeight);
      accumulator.bestReps = math.max(accumulator.bestReps, bestReps);
      accumulator.bestSetVolume = math.max(
        accumulator.bestSetVolume,
        bestSetVolume,
      );
      accumulator.bestEstimatedOneRepMax = math.max(
        accumulator.bestEstimatedOneRepMax,
        bestE1rm ?? 0,
      );
      accumulator.points.add(
        ExerciseProgressPoint(
          date: session.startTime,
          bestWeight: bestWeight,
          bestReps: bestReps,
          volume: volume,
          estimatedOneRepMax: bestE1rm,
          completedSets: workSets.length,
        ),
      );
    }
  }

  final summaries = grouped.values.map((entry) {
    final e1rmPoints = entry.points
        .where((point) => point.estimatedOneRepMax != null)
        .toList();
    final latestE1rm = e1rmPoints.isEmpty
        ? null
        : e1rmPoints.last.estimatedOneRepMax;
    double? trend;
    if (e1rmPoints.length >= 2) {
      final previous = e1rmPoints[e1rmPoints.length - 2].estimatedOneRepMax!;
      final latest = e1rmPoints.last.estimatedOneRepMax!;
      if (previous > 0) trend = ((latest - previous) / previous) * 100;
    }
    return ExerciseProgressSummary(
      name: entry.name,
      muscleGroup: entry.muscleGroup,
      sessionCount: entry.sessionCount,
      completedSets: entry.completedSets,
      totalReps: entry.totalReps,
      totalVolume: entry.totalVolume,
      bestWeight: entry.bestWeight,
      bestReps: entry.bestReps,
      bestSetVolume: entry.bestSetVolume,
      bestEstimatedOneRepMax: entry.bestEstimatedOneRepMax,
      latestEstimatedOneRepMax: latestE1rm,
      estimatedOneRepMaxTrendPercent: trend,
      lastTrainedAt: entry.lastTrainedAt,
      points: List.unmodifiable(entry.points),
    );
  }).toList()..sort((a, b) => b.lastTrainedAt.compareTo(a.lastTrainedAt));
  return summaries;
}

List<PersonalRecordEvent> _buildPersonalRecords(List<WorkoutSession> history) {
  final records = <PersonalRecordEvent>[];
  final stateByExercise = <String, _RecordState>{};

  for (final session in history) {
    for (final exercise in session.exercises) {
      final workSets = _workSets(exercise);
      if (workSets.isEmpty) continue;
      final key = _normalize(exercise.name);
      final state = stateByExercise.putIfAbsent(key, _RecordState.new);
      final sessionVolume = workSets.fold<double>(
        0,
        (sum, set) => sum + _setVolume(set),
      );

      for (final set in workSets) {
        final volume = _setVolume(set);
        final e1rm = _estimatedOneRepMax(set);
        if (set.weight > state.bestWeight) {
          state.bestWeight = set.weight;
          records.add(
            PersonalRecordEvent(
              exerciseName: exercise.name,
              muscleGroup: exercise.muscleGroup,
              kind: PersonalRecordKind.weight,
              date: session.startTime,
              value: set.weight,
              weight: set.weight,
              reps: set.reps,
            ),
          );
        }
        if (set.reps > state.bestReps) {
          state.bestReps = set.reps;
          records.add(
            PersonalRecordEvent(
              exerciseName: exercise.name,
              muscleGroup: exercise.muscleGroup,
              kind: PersonalRecordKind.reps,
              date: session.startTime,
              value: set.reps.toDouble(),
              weight: set.weight,
              reps: set.reps,
            ),
          );
        }
        if (volume > state.bestSetVolume) {
          state.bestSetVolume = volume;
          records.add(
            PersonalRecordEvent(
              exerciseName: exercise.name,
              muscleGroup: exercise.muscleGroup,
              kind: PersonalRecordKind.setVolume,
              date: session.startTime,
              value: volume,
              weight: set.weight,
              reps: set.reps,
            ),
          );
        }
        if (e1rm != null && e1rm > state.bestE1rm) {
          state.bestE1rm = e1rm;
          records.add(
            PersonalRecordEvent(
              exerciseName: exercise.name,
              muscleGroup: exercise.muscleGroup,
              kind: PersonalRecordKind.estimatedOneRepMax,
              date: session.startTime,
              value: e1rm,
              weight: set.weight,
              reps: set.reps,
            ),
          );
        }
      }

      if (sessionVolume > state.bestSessionVolume) {
        state.bestSessionVolume = sessionVolume;
        records.add(
          PersonalRecordEvent(
            exerciseName: exercise.name,
            muscleGroup: exercise.muscleGroup,
            kind: PersonalRecordKind.sessionVolume,
            date: session.startTime,
            value: sessionVolume,
          ),
        );
      }
    }
  }
  return records;
}

List<MuscleProgressSummary> _buildMuscleSummaries(
  List<WorkoutSession> history,
  DateTime now,
) {
  final weekStart = _startOfWeek(now);
  final firstWeek = weekStart.subtract(const Duration(days: 7 * 7));
  final cutoff7 = now.subtract(const Duration(days: 6));
  final cutoff30 = now.subtract(const Duration(days: 29));
  final accumulators = <MuscleGroup, _MuscleAccumulator>{};

  for (final session in history) {
    for (final exercise in session.exercises) {
      if (exercise.muscleGroup == MuscleGroup.unassigned) continue;
      final workSets = _workSets(exercise);
      if (workSets.isEmpty) continue;
      final accumulator = accumulators.putIfAbsent(
        exercise.muscleGroup,
        () => _MuscleAccumulator(exercise.muscleGroup),
      );
      final sessionDate = _dateOnly(session.startTime);
      final volume = workSets.fold<double>(
        0,
        (sum, set) => sum + _setVolume(set),
      );
      if (!sessionDate.isBefore(cutoff30)) {
        accumulator.sets30 += workSets.length;
        accumulator.volume30 += volume;
        accumulator.sessionIds30.add(session.id);
      }
      if (!sessionDate.isBefore(cutoff7)) {
        accumulator.sets7 += workSets.length;
        accumulator.volume7 += volume;
      }
      final sessionWeek = _startOfWeek(sessionDate);
      if (!sessionWeek.isBefore(firstWeek) && !sessionWeek.isAfter(weekStart)) {
        final bucket = accumulator.weekly.putIfAbsent(
          sessionWeek,
          () => _WeeklyMutable(),
        );
        bucket.sets += workSets.length;
        bucket.volume += volume;
      }
    }
  }

  final totalSets30 = accumulators.values.fold<int>(
    0,
    (sum, entry) => sum + entry.sets30,
  );
  final summaries = accumulators.values.map((entry) {
    final weekly = List.generate(8, (index) {
      final start = firstWeek.add(Duration(days: 7 * index));
      final bucket = entry.weekly[start];
      return WeeklyMusclePoint(
        weekStart: start,
        sets: bucket?.sets ?? 0,
        volume: bucket?.volume ?? 0,
      );
    });
    return MuscleProgressSummary(
      muscleGroup: entry.group,
      sets7Days: entry.sets7,
      sets30Days: entry.sets30,
      volume7Days: entry.volume7,
      volume30Days: entry.volume30,
      sessionCount30Days: entry.sessionIds30.length,
      setShare30Days: totalSets30 == 0 ? 0 : entry.sets30 / totalSets30,
      weekly: weekly,
    );
  }).toList()..sort((a, b) => b.sets30Days.compareTo(a.sets30Days));
  return summaries;
}

ConsistencySummary _buildConsistency(
  List<WorkoutSession> history,
  DateTime now,
) {
  final cutoff30 = now.subtract(const Duration(days: 29));
  final sessions30 = history
      .where((session) => !_dateOnly(session.startTime).isBefore(cutoff30))
      .toList();
  final trainedDays = sessions30
      .map((session) => _dateOnly(session.startTime))
      .toSet();
  final currentWeek = _startOfWeek(now);
  final activeWeeks = history
      .map((session) => _startOfWeek(session.startTime))
      .toSet();

  var currentStreak = 0;
  var cursor = currentWeek;
  while (activeWeeks.contains(cursor)) {
    currentStreak++;
    cursor = cursor.subtract(const Duration(days: 7));
  }

  final sortedWeeks = activeWeeks.toList()..sort();
  var longest = 0;
  var running = 0;
  DateTime? previous;
  for (final week in sortedWeeks) {
    if (previous != null && week.difference(previous).inDays == 7) {
      running++;
    } else {
      running = 1;
    }
    longest = math.max(longest, running);
    previous = week;
  }

  final first8Week = currentWeek.subtract(const Duration(days: 49));
  final sessions8Week = history.where((session) {
    final day = _dateOnly(session.startTime);
    return !day.isBefore(first8Week) &&
        day.isBefore(currentWeek.add(const Duration(days: 7)));
  }).length;

  final weekdayCounts = List<int>.filled(7, 0);
  for (final session in history) {
    weekdayCounts[session.startTime.weekday - 1]++;
  }
  final maxCount = weekdayCounts.fold<int>(0, math.max);
  final weekday = maxCount == 0
      ? '-'
      : _weekdayLabel(weekdayCounts.indexOf(maxCount) + 1);

  return ConsistencySummary(
    workouts30Days: sessions30.length,
    trainedDays30Days: trainedDays.length,
    currentActiveWeekStreak: currentStreak,
    longestActiveWeekStreak: longest,
    averageWorkoutsPerWeek8Weeks: sessions8Week / 8,
    mostActiveWeekday: weekday,
  );
}

PeriodProgressReport _buildPeriodReport(
  List<WorkoutSession> history,
  List<PersonalRecordEvent> records,
  DateTime start,
  DateTime endExclusive,
) {
  final sessions = history.where((session) {
    final date = session.startTime;
    return !date.isBefore(start) && date.isBefore(endExclusive);
  }).toList();
  var completedSets = 0;
  var totalReps = 0;
  var volume = 0.0;
  var durationMinutes = 0;
  final exerciseVolume = <String, double>{};
  final muscleSets = <MuscleGroup, int>{};

  for (final session in sessions) {
    durationMinutes += math.max(
      0,
      session.endTime.difference(session.startTime).inMinutes,
    );
    for (final exercise in session.exercises) {
      final sets = _workSets(exercise);
      if (sets.isEmpty) continue;
      completedSets += sets.length;
      final reps = sets.fold<int>(0, (sum, set) => sum + set.reps);
      final exerciseSessionVolume = sets.fold<double>(
        0,
        (sum, set) => sum + _setVolume(set),
      );
      totalReps += reps;
      volume += exerciseSessionVolume;
      exerciseVolume.update(
        exercise.name,
        (value) => value + exerciseSessionVolume,
        ifAbsent: () => exerciseSessionVolume,
      );
      if (exercise.muscleGroup != MuscleGroup.unassigned) {
        muscleSets.update(
          exercise.muscleGroup,
          (value) => value + sets.length,
          ifAbsent: () => sets.length,
        );
      }
    }
  }

  String? topExercise;
  double topExerciseVolume = -1;
  exerciseVolume.forEach((name, value) {
    if (value > topExerciseVolume) {
      topExercise = name;
      topExerciseVolume = value;
    }
  });
  MuscleGroup? topMuscle;
  var topMuscleSets = -1;
  muscleSets.forEach((group, value) {
    if (value > topMuscleSets) {
      topMuscle = group;
      topMuscleSets = value;
    }
  });
  final recordCount = records.where((record) {
    return !record.date.isBefore(start) && record.date.isBefore(endExclusive);
  }).length;

  return PeriodProgressReport(
    start: start,
    endExclusive: endExclusive,
    workouts: sessions.length,
    completedSets: completedSets,
    totalReps: totalReps,
    volume: volume,
    durationMinutes: durationMinutes,
    personalRecords: recordCount,
    topExercise: topExercise,
    topMuscleGroup: topMuscle,
  );
}

List<ExerciseSet> _workSets(WorkoutExercise exercise) =>
    exercise.sets.where((set) => set.isCompleted && !set.isWarmup).toList();

double _setVolume(ExerciseSet set) => set.weight * set.reps;

double? _estimatedOneRepMax(ExerciseSet set) {
  if (set.weight <= 0 || set.reps <= 0 || set.reps > 15) return null;
  return set.weight * (1 + set.reps / 30.0);
}

double? _bestE1rm(List<ExerciseSet> sets) {
  double? best;
  for (final set in sets) {
    final value = _estimatedOneRepMax(set);
    if (value != null && (best == null || value > best)) best = value;
  }
  return best;
}

DateTime _dateOnly(DateTime date) => DateTime(date.year, date.month, date.day);

DateTime _startOfWeek(DateTime date) {
  final day = _dateOnly(date);
  return day.subtract(Duration(days: day.weekday - DateTime.monday));
}

String _normalize(String value) => value.trim().toLowerCase();

String _weekdayLabel(int weekday) => switch (weekday) {
  DateTime.monday => 'Lunedì',
  DateTime.tuesday => 'Martedì',
  DateTime.wednesday => 'Mercoledì',
  DateTime.thursday => 'Giovedì',
  DateTime.friday => 'Venerdì',
  DateTime.saturday => 'Sabato',
  DateTime.sunday => 'Domenica',
  _ => '-',
};

class _ExerciseAccumulator {
  String name;
  MuscleGroup muscleGroup;
  int sessionCount = 0;
  int completedSets = 0;
  int totalReps = 0;
  double totalVolume = 0;
  double bestWeight = 0;
  int bestReps = 0;
  double bestSetVolume = 0;
  double bestEstimatedOneRepMax = 0;
  DateTime lastTrainedAt = DateTime.fromMillisecondsSinceEpoch(0);
  final List<ExerciseProgressPoint> points = [];

  _ExerciseAccumulator(this.name, this.muscleGroup);
}

class _RecordState {
  double bestWeight = -1;
  int bestReps = -1;
  double bestSetVolume = -1;
  double bestE1rm = -1;
  double bestSessionVolume = -1;
}

class _WeeklyMutable {
  int sets = 0;
  double volume = 0;
}

class _MuscleAccumulator {
  final MuscleGroup group;
  int sets7 = 0;
  int sets30 = 0;
  double volume7 = 0;
  double volume30 = 0;
  final Set<String> sessionIds30 = {};
  final Map<DateTime, _WeeklyMutable> weekly = {};

  _MuscleAccumulator(this.group);
}
