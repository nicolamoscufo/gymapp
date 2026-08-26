import 'dart:math' as math;

import 'models/exercise.dart';
import 'models/schedule.dart';
import 'models/workout.dart';
import 'progress_analytics.dart';

enum ProgressComparisonRange { fourWeeks, eightWeeks, threeMonths, mesocycle }

extension ProgressComparisonRangeLabel on ProgressComparisonRange {
  String get label => switch (this) {
    ProgressComparisonRange.fourWeeks => '4 settimane',
    ProgressComparisonRange.eightWeeks => '8 settimane',
    ProgressComparisonRange.threeMonths => '3 mesi',
    ProgressComparisonRange.mesocycle => 'Mesociclo',
  };
}

class ProgressComparisonWindow {
  final DateTime start;
  final DateTime endExclusive;

  const ProgressComparisonWindow({
    required this.start,
    required this.endExclusive,
  });

  int get durationDays =>
      math.max(1, endExclusive.difference(start).inDays).toInt();
  double get durationWeeks => durationDays / 7.0;

  String get label {
    final end = endExclusive.subtract(const Duration(days: 1));
    return '${start.day}/${start.month}/${start.year} – ${end.day}/${end.month}/${end.year}';
  }
}

class PeriodStrengthShift {
  final String exerciseName;
  final MuscleGroup muscleGroup;
  final double previousBestEstimatedOneRepMax;
  final double currentBestEstimatedOneRepMax;
  final double changePercent;

  const PeriodStrengthShift({
    required this.exerciseName,
    required this.muscleGroup,
    required this.previousBestEstimatedOneRepMax,
    required this.currentBestEstimatedOneRepMax,
    required this.changePercent,
  });

  bool get improved => changePercent > 2;
  bool get declined => changePercent < -2;
}

class PeriodMuscleShift {
  final MuscleGroup muscleGroup;
  final int previousSets;
  final int currentSets;
  final double? changePercent;

  const PeriodMuscleShift({
    required this.muscleGroup,
    required this.previousSets,
    required this.currentSets,
    required this.changePercent,
  });

  bool get newlyActive => previousSets == 0 && currentSets > 0;
}

class ProgressPeriodComparison {
  final ProgressComparisonRange range;
  final ProgressComparisonWindow currentWindow;
  final ProgressComparisonWindow previousWindow;
  final PeriodProgressReport current;
  final PeriodProgressReport previous;
  final List<PeriodStrengthShift> strengthShifts;
  final List<PeriodMuscleShift> muscleShifts;
  final Schedule? schedule;

  const ProgressPeriodComparison({
    required this.range,
    required this.currentWindow,
    required this.previousWindow,
    required this.current,
    required this.previous,
    required this.strengthShifts,
    required this.muscleShifts,
    required this.schedule,
  });

  double get currentWorkoutsPerWeek =>
      current.workouts / currentWindow.durationWeeks;
  double get previousWorkoutsPerWeek =>
      previous.workouts / previousWindow.durationWeeks;
  int get improvedStrengthCount =>
      strengthShifts.where((entry) => entry.improved).length;
  int get declinedStrengthCount =>
      strengthShifts.where((entry) => entry.declined).length;
}

ProgressPeriodComparison? buildProgressPeriodComparison({
  required List<WorkoutSession> history,
  required ProgressAnalytics analytics,
  required ProgressComparisonRange range,
  DateTime? now,
  Schedule? schedule,
}) {
  final reference = _dateOnly(now ?? DateTime.now());
  final endExclusive = reference.add(const Duration(days: 1));

  late ProgressComparisonWindow currentWindow;
  late ProgressComparisonWindow previousWindow;
  List<WorkoutSession> scopedHistory = history;
  ProgressAnalytics scopedAnalytics = analytics;

  switch (range) {
    case ProgressComparisonRange.fourWeeks:
      currentWindow = ProgressComparisonWindow(
        start: endExclusive.subtract(const Duration(days: 28)),
        endExclusive: endExclusive,
      );
      previousWindow = ProgressComparisonWindow(
        start: currentWindow.start.subtract(const Duration(days: 28)),
        endExclusive: currentWindow.start,
      );
    case ProgressComparisonRange.eightWeeks:
      currentWindow = ProgressComparisonWindow(
        start: endExclusive.subtract(const Duration(days: 56)),
        endExclusive: endExclusive,
      );
      previousWindow = ProgressComparisonWindow(
        start: currentWindow.start.subtract(const Duration(days: 56)),
        endExclusive: currentWindow.start,
      );
    case ProgressComparisonRange.threeMonths:
      final currentStart = _shiftMonths(endExclusive, -3);
      currentWindow = ProgressComparisonWindow(
        start: currentStart,
        endExclusive: endExclusive,
      );
      previousWindow = ProgressComparisonWindow(
        start: _shiftMonths(currentStart, -3),
        endExclusive: currentStart,
      );
    case ProgressComparisonRange.mesocycle:
      if (schedule == null) return null;
      final cycleStart = _dateOnly(schedule.createdAt);
      if (!cycleStart.isBefore(endExclusive)) return null;
      final cycleDays = math.max(1, schedule.mesocycleWeeks).toInt() * 7;
      final plannedCycleEnd = cycleStart.add(Duration(days: cycleDays));
      final currentEnd = endExclusive.isBefore(plannedCycleEnd)
          ? endExclusive
          : plannedCycleEnd;
      final elapsedDays = math
          .max(1, currentEnd.difference(cycleStart).inDays)
          .toInt();
      currentWindow = ProgressComparisonWindow(
        start: cycleStart,
        endExclusive: currentEnd,
      );
      previousWindow = ProgressComparisonWindow(
        start: cycleStart.subtract(Duration(days: elapsedDays)),
        endExclusive: cycleStart,
      );
      scopedHistory = history
          .where((session) => _matchesSchedule(session, schedule))
          .toList();
      scopedAnalytics = buildProgressAnalytics(
        history: scopedHistory,
        now: reference,
      );
  }

  final currentReport = buildPeriodProgressReport(
    history: scopedHistory,
    personalRecords: scopedAnalytics.personalRecords,
    start: currentWindow.start,
    endExclusive: currentWindow.endExclusive,
  );
  final previousReport = buildPeriodProgressReport(
    history: scopedHistory,
    personalRecords: scopedAnalytics.personalRecords,
    start: previousWindow.start,
    endExclusive: previousWindow.endExclusive,
  );

  return ProgressPeriodComparison(
    range: range,
    currentWindow: currentWindow,
    previousWindow: previousWindow,
    current: currentReport,
    previous: previousReport,
    strengthShifts: List.unmodifiable(
      _buildStrengthShifts(scopedHistory, currentWindow, previousWindow),
    ),
    muscleShifts: List.unmodifiable(
      _buildMuscleShifts(scopedHistory, currentWindow, previousWindow),
    ),
    schedule: range == ProgressComparisonRange.mesocycle ? schedule : null,
  );
}

List<PeriodStrengthShift> _buildStrengthShifts(
  List<WorkoutSession> history,
  ProgressComparisonWindow current,
  ProgressComparisonWindow previous,
) {
  final currentBest = _bestE1rmByExercise(history, current);
  final previousBest = _bestE1rmByExercise(history, previous);
  final shifts = <PeriodStrengthShift>[];

  for (final entry in currentBest.entries) {
    final previousEntry = previousBest[entry.key];
    if (previousEntry == null || previousEntry.best <= 0) continue;
    final change =
        ((entry.value.best - previousEntry.best) / previousEntry.best) * 100;
    shifts.add(
      PeriodStrengthShift(
        exerciseName: entry.value.name,
        muscleGroup: entry.value.muscleGroup,
        previousBestEstimatedOneRepMax: previousEntry.best,
        currentBestEstimatedOneRepMax: entry.value.best,
        changePercent: change,
      ),
    );
  }

  shifts.sort((a, b) => b.changePercent.compareTo(a.changePercent));
  return shifts;
}

Map<String, _StrengthAccumulator> _bestE1rmByExercise(
  List<WorkoutSession> history,
  ProgressComparisonWindow window,
) {
  final result = <String, _StrengthAccumulator>{};
  for (final session in history) {
    if (!_inWindow(session.startTime, window)) continue;
    for (final exercise in session.exercises) {
      double? best;
      for (final set in exercise.sets) {
        if (!set.isCompleted || set.isWarmup) continue;
        final e1rm = _estimatedOneRepMax(set);
        if (e1rm == null) continue;
        if (best == null || e1rm > best) best = e1rm;
      }
      if (best == null) continue;
      final key = _normalize(exercise.name);
      final existing = result[key];
      if (existing == null || best > existing.best) {
        result[key] = _StrengthAccumulator(
          name: exercise.name,
          muscleGroup: exercise.muscleGroup,
          best: best,
        );
      }
    }
  }
  return result;
}

List<PeriodMuscleShift> _buildMuscleShifts(
  List<WorkoutSession> history,
  ProgressComparisonWindow current,
  ProgressComparisonWindow previous,
) {
  final currentSets = _setsByMuscle(history, current);
  final previousSets = _setsByMuscle(history, previous);
  final groups = <MuscleGroup>{...currentSets.keys, ...previousSets.keys};
  final shifts = groups.map((group) {
    final currentValue = currentSets[group] ?? 0;
    final previousValue = previousSets[group] ?? 0;
    return PeriodMuscleShift(
      muscleGroup: group,
      previousSets: previousValue,
      currentSets: currentValue,
      changePercent: previousValue <= 0
          ? null
          : ((currentValue - previousValue) / previousValue) * 100,
    );
  }).toList();
  shifts.sort((a, b) {
    final byCurrent = b.currentSets.compareTo(a.currentSets);
    if (byCurrent != 0) return byCurrent;
    return (b.currentSets - b.previousSets).abs().compareTo(
      (a.currentSets - a.previousSets).abs(),
    );
  });
  return shifts;
}

Map<MuscleGroup, int> _setsByMuscle(
  List<WorkoutSession> history,
  ProgressComparisonWindow window,
) {
  final result = <MuscleGroup, int>{};
  for (final session in history) {
    if (!_inWindow(session.startTime, window)) continue;
    for (final exercise in session.exercises) {
      if (exercise.muscleGroup == MuscleGroup.unassigned) continue;
      final count = exercise.sets
          .where((set) => set.isCompleted && !set.isWarmup)
          .length;
      if (count == 0) continue;
      result.update(
        exercise.muscleGroup,
        (value) => value + count,
        ifAbsent: () => count,
      );
    }
  }
  return result;
}

bool _matchesSchedule(WorkoutSession session, Schedule schedule) {
  if (session.scheduleId != null) return session.scheduleId == schedule.id;
  return _normalize(session.scheduleTitle) == _normalize(schedule.title);
}

bool _inWindow(DateTime value, ProgressComparisonWindow window) {
  final day = _dateOnly(value);
  return !day.isBefore(window.start) && day.isBefore(window.endExclusive);
}

double? _estimatedOneRepMax(ExerciseSet set) {
  if (set.weight <= 0 || set.reps <= 0 || set.reps > 15) return null;
  return set.weight * (1 + set.reps / 30.0);
}

DateTime _shiftMonths(DateTime date, int delta) {
  final monthIndex = date.year * 12 + date.month - 1 + delta;
  final year = monthIndex ~/ 12;
  final month = monthIndex % 12 + 1;
  final lastDay = DateTime(year, month + 1, 0).day;
  return DateTime(year, month, math.min(date.day, lastDay));
}

DateTime _dateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);
String _normalize(String value) => value.trim().toLowerCase();

class _StrengthAccumulator {
  final String name;
  final MuscleGroup muscleGroup;
  final double best;

  const _StrengthAccumulator({
    required this.name,
    required this.muscleGroup,
    required this.best,
  });
}
