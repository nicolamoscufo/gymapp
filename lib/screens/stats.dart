import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../models/exercise.dart';
import '../models/workout.dart';

class StatsScreen extends StatelessWidget {
  final List<WorkoutSession> history;

  const StatsScreen({super.key, required this.history});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    if (history.isEmpty) {
      return const Center(
        child: Text('Nessun dato per mostrare le statistiche.'),
      );
    }

    final sortedHistory = List<WorkoutSession>.from(history)
      ..sort((a, b) => a.startTime.compareTo(b.startTime));

    final totalWorkouts = sortedHistory.length;
    final totalCompletedSets = sortedHistory.fold<int>(
      0,
      (sum, session) => sum + _completedSetsForSession(session),
    );
    final totalVolumeLast7Days = sortedHistory.fold<double>(0, (sum, session) {
      if (DateTime.now().difference(session.startTime).inDays <= 7) {
        return sum + _volumeForSession(session);
      }
      return sum;
    });

    final weeklyVolumes = _buildWeeklyVolumes(sortedHistory, weekCount: 8);
    final dailyVolumes = _buildDailyVolumes(sortedHistory, days: 30);
    final maxDailyVolume = dailyVolumes.fold<double>(
      0,
      (max, entry) => entry.volume > max ? entry.volume : max,
    );
    final exerciseSummaries = _buildExerciseSummaries(sortedHistory);
    final bestE1rm = exerciseSummaries.fold<double>(
      0,
      (max, entry) => entry.bestE1rm > max ? entry.bestE1rm : max,
    );
    final averageRpe = _averageRpe(sortedHistory);
    final currentWeekStart = _startOfWeek(DateTime.now());
    final weeklyMuscleGroupStats = _buildMuscleGroupWeeklyStats(
      sortedHistory,
      currentWeekStart,
    );

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _MetricCard(
                  label: 'Allenamenti',
                  value: '$totalWorkouts',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _MetricCard(
                  label: 'Volume 7 giorni',
                  value: '${totalVolumeLast7Days.toStringAsFixed(0)} kg',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _MetricCard(
                  label: 'Set completati',
                  value: '$totalCompletedSets',
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _MetricCard(
                  label: 'Miglior e1RM',
                  value: '${bestE1rm.toStringAsFixed(0)} kg',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _MetricCard(
                  label: 'RPE medio',
                  value: averageRpe == null
                      ? '-'
                      : averageRpe.toStringAsFixed(1),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Text(
            'Gruppi muscolari - settimana ${_isoWeekNumber(currentWeekStart)}',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          Card(
            elevation: 1,
            child: weeklyMuscleGroupStats.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('Nessun set completato questa settimana.'),
                  )
                : ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: weeklyMuscleGroupStats.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final stats = weeklyMuscleGroupStats[index];
                      return ListTile(
                        title: Text(
                          stats.group.label,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text(
                          'Serie: ${stats.completedSets} • Ripetizioni: ${stats.reps}',
                        ),
                        trailing: Text(
                          '${stats.load.toStringAsFixed(0)} kg',
                          textAlign: TextAlign.right,
                          style: TextStyle(
                            color: colorScheme.primary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      );
                    },
                  ),
          ),
          const SizedBox(height: 24),
          Text(
            'Progressione settimanale',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          Card(
            elevation: 1,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                height: 260,
                child: BarChart(
                  BarChartData(
                    alignment: BarChartAlignment.spaceAround,
                    barTouchData: BarTouchData(enabled: true),
                    titlesData: FlTitlesData(
                      show: true,
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 34,
                          getTitlesWidget: (value, meta) {
                            final index = value.toInt();
                            if (index < 0 || index >= weeklyVolumes.length) {
                              return const SizedBox.shrink();
                            }

                            final label = weeklyVolumes[index].label;
                            return SideTitleWidget(
                              meta: meta,
                              child: Text(
                                label,
                                style: TextStyle(
                                  color: colorScheme.onSurfaceVariant,
                                  fontSize: 10,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      leftTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                      topTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                      rightTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                    ),
                    gridData: const FlGridData(show: false),
                    borderData: FlBorderData(show: false),
                    barGroups: List.generate(weeklyVolumes.length, (index) {
                      final entry = weeklyVolumes[index];
                      return BarChartGroupData(
                        x: index,
                        barRods: [
                          BarChartRodData(
                            toY: entry.volume,
                            color: colorScheme.primary,
                            width: 18,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ],
                      );
                    }),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Calendario ultimi 30 giorni',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          Card(
            elevation: 1,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: dailyVolumes.length,
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 7,
                          crossAxisSpacing: 6,
                          mainAxisSpacing: 6,
                          childAspectRatio: 0.9,
                        ),
                    itemBuilder: (context, index) {
                      final day = dailyVolumes[index].date;
                      final volume = dailyVolumes[index].volume;
                      final sessionCount = dailyVolumes[index].sessionCount;
                      final intensity = maxDailyVolume == 0
                          ? 0.0
                          : (volume / maxDailyVolume).clamp(0.0, 1.0);
                      final backgroundColor = volume == 0
                          ? colorScheme.surfaceContainerHighest
                          : Color.lerp(
                                  colorScheme.primaryContainer,
                                  colorScheme.primary,
                                  intensity,
                                ) ??
                                colorScheme.primary;
                      final foregroundColor = volume == 0
                          ? colorScheme.onSurfaceVariant
                          : intensity > 0.55
                          ? colorScheme.onPrimary
                          : colorScheme.onPrimaryContainer;

                      return Container(
                        decoration: BoxDecoration(
                          color: backgroundColor,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: colorScheme.outlineVariant),
                        ),
                        padding: const EdgeInsets.all(6),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              '${day.day}',
                              style: TextStyle(
                                color: foregroundColor,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              sessionCount > 0 ? '$sessionCount' : '',
                              style: TextStyle(
                                color: foregroundColor,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Container(
                        width: 14,
                        height: 14,
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: colorScheme.outlineVariant),
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Text('Nessun allenamento'),
                      const SizedBox(width: 16),
                      Container(
                        width: 14,
                        height: 14,
                        decoration: BoxDecoration(
                          color: colorScheme.primary,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Text('Più volume'),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Esercizi migliori',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          Card(
            elevation: 1,
            child: ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: exerciseSummaries.take(5).length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final summary = exerciseSummaries[index];
                return ListTile(
                  title: Text(
                    summary.name,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(
                    'Volume: ${summary.volume.toStringAsFixed(1)} kg • Set: ${summary.completedSets} • e1RM: ${summary.bestE1rm.toStringAsFixed(1)} kg${summary.averageRpe == null ? '' : ' • RPE medio: ${summary.averageRpe!.toStringAsFixed(1)}'}',
                  ),
                  trailing: Text(
                    'Top set ${summary.bestLoad.toStringAsFixed(1)} kg',
                    textAlign: TextAlign.right,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  final String label;
  final String value;

  const _MetricCard({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text(
              label,
              style: theme.textTheme.labelMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              value,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: colorScheme.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PeriodVolume {
  final DateTime date;
  final double volume;
  final int sessionCount;
  final String label;

  _PeriodVolume({
    required this.date,
    required this.volume,
    required this.sessionCount,
    required this.label,
  });
}

class _DailyVolume {
  final DateTime date;
  final double volume;
  final int sessionCount;

  _DailyVolume({
    required this.date,
    required this.volume,
    required this.sessionCount,
  });
}

class _ExerciseSummary {
  final String name;
  double volume = 0;
  double bestLoad = 0;
  double bestSetVolume = 0;
  double bestE1rm = 0;
  double rpeTotal = 0;
  int rpeCount = 0;
  int completedSets = 0;

  _ExerciseSummary(this.name);

  double? get averageRpe => rpeCount == 0 ? null : rpeTotal / rpeCount;
}

class _MuscleGroupWeeklyStats {
  final MuscleGroup group;
  int completedSets = 0;
  int reps = 0;
  double load = 0;

  _MuscleGroupWeeklyStats(this.group);
}

DateTime _dateOnly(DateTime date) => DateTime(date.year, date.month, date.day);

DateTime _startOfWeek(DateTime date) {
  final normalized = _dateOnly(date);
  return normalized.subtract(Duration(days: normalized.weekday - 1));
}

int _dayOfYear(DateTime date) {
  return _dateOnly(date).difference(DateTime(date.year)).inDays + 1;
}

int _isoWeekNumber(DateTime date) {
  final week = ((_dayOfYear(date) - date.weekday + 10) / 7).floor();
  if (week < 1) {
    return _isoWeekNumber(DateTime(date.year - 1, 12, 31));
  }

  return week;
}

double _volumeForSession(WorkoutSession session) {
  double totalVolume = 0;
  for (final exercise in session.exercises) {
    for (final set in exercise.sets) {
      if (set.isCompleted && !set.isWarmup) {
        totalVolume += set.weight * set.reps;
      }
    }
  }
  return totalVolume;
}

int _completedSetsForSession(WorkoutSession session) {
  int completedSets = 0;
  for (final exercise in session.exercises) {
    for (final set in exercise.sets) {
      if (set.isCompleted && !set.isWarmup) {
        completedSets++;
      }
    }
  }
  return completedSets;
}

double _estimatedOneRepMax(double weight, int reps) {
  if (reps <= 0 || weight <= 0) {
    return 0;
  }
  return weight * (1 + reps / 30);
}

double? _averageRpe(List<WorkoutSession> history) {
  double total = 0;
  int count = 0;

  for (final session in history) {
    for (final exercise in session.exercises) {
      for (final set in exercise.sets) {
        if (set.isCompleted && !set.isWarmup && set.rpe != null) {
          total += set.rpe!;
          count++;
        }
      }
    }
  }

  return count == 0 ? null : total / count;
}

List<_PeriodVolume> _buildWeeklyVolumes(
  List<WorkoutSession> history, {
  required int weekCount,
}) {
  final currentWeekStart = _startOfWeek(DateTime.now());
  final firstWeekStart = currentWeekStart.subtract(
    Duration(days: 7 * (weekCount - 1)),
  );

  final weeklyVolumes = <DateTime, double>{};
  final weeklySessionCount = <DateTime, int>{};

  for (int i = 0; i < weekCount; i++) {
    final weekStart = firstWeekStart.add(Duration(days: 7 * i));
    weeklyVolumes[weekStart] = 0;
    weeklySessionCount[weekStart] = 0;
  }

  for (final session in history) {
    final weekStart = _startOfWeek(session.startTime);
    if (weeklyVolumes.containsKey(weekStart)) {
      weeklyVolumes[weekStart] =
          weeklyVolumes[weekStart]! + _volumeForSession(session);
      weeklySessionCount[weekStart] = weeklySessionCount[weekStart]! + 1;
    }
  }

  return weeklyVolumes.entries.map((entry) {
    final weekStart = entry.key;
    return _PeriodVolume(
      date: weekStart,
      volume: entry.value,
      sessionCount: weeklySessionCount[weekStart] ?? 0,
      label: 'S${_isoWeekNumber(weekStart)}',
    );
  }).toList();
}

List<_MuscleGroupWeeklyStats> _buildMuscleGroupWeeklyStats(
  List<WorkoutSession> history,
  DateTime weekStart,
) {
  final weekEnd = weekStart.add(const Duration(days: 7));
  final statsByGroup = <MuscleGroup, _MuscleGroupWeeklyStats>{};

  for (final session in history) {
    if (session.startTime.isBefore(weekStart) ||
        !session.startTime.isBefore(weekEnd)) {
      continue;
    }

    for (final exercise in session.exercises) {
      final stats = statsByGroup.putIfAbsent(
        exercise.muscleGroup,
        () => _MuscleGroupWeeklyStats(exercise.muscleGroup),
      );

      for (final set in exercise.sets) {
        if (!set.isCompleted || set.isWarmup) {
          continue;
        }

        stats.completedSets++;
        stats.reps += set.reps;
        stats.load += set.weight * set.reps;
      }
    }
  }

  final sorted =
      statsByGroup.values.where((stats) => stats.completedSets > 0).toList()
        ..sort((a, b) => b.load.compareTo(a.load));
  return sorted;
}

List<_DailyVolume> _buildDailyVolumes(
  List<WorkoutSession> history, {
  required int days,
}) {
  final today = _dateOnly(DateTime.now());
  final firstDay = today.subtract(Duration(days: days - 1));

  final dailyVolumes = <DateTime, double>{};
  final dailySessionCount = <DateTime, int>{};

  for (int i = 0; i < days; i++) {
    final day = firstDay.add(Duration(days: i));
    dailyVolumes[day] = 0;
    dailySessionCount[day] = 0;
  }

  for (final session in history) {
    final day = _dateOnly(session.startTime);
    if (dailyVolumes.containsKey(day)) {
      dailyVolumes[day] = dailyVolumes[day]! + _volumeForSession(session);
      dailySessionCount[day] = dailySessionCount[day]! + 1;
    }
  }

  return dailyVolumes.entries.map((entry) {
    final day = entry.key;
    return _DailyVolume(
      date: day,
      volume: entry.value,
      sessionCount: dailySessionCount[day] ?? 0,
    );
  }).toList();
}

List<_ExerciseSummary> _buildExerciseSummaries(List<WorkoutSession> history) {
  final summaries = <String, _ExerciseSummary>{};

  for (final session in history) {
    for (final exercise in session.exercises) {
      final summary = summaries.putIfAbsent(
        exercise.name,
        () => _ExerciseSummary(exercise.name),
      );

      for (final set in exercise.sets) {
        if (!set.isCompleted || set.isWarmup) {
          continue;
        }

        final setVolume = set.weight * set.reps;
        final estimatedOneRepMax = _estimatedOneRepMax(set.weight, set.reps);
        summary.volume += setVolume;
        summary.completedSets++;
        if (set.rpe != null) {
          summary.rpeTotal += set.rpe!;
          summary.rpeCount++;
        }
        if (set.weight > summary.bestLoad) {
          summary.bestLoad = set.weight;
        }
        if (setVolume > summary.bestSetVolume) {
          summary.bestSetVolume = setVolume;
        }
        if (estimatedOneRepMax > summary.bestE1rm) {
          summary.bestE1rm = estimatedOneRepMax;
        }
      }
    }
  }

  final sorted = summaries.values.toList()
    ..sort((a, b) => b.volume.compareTo(a.volume));
  return sorted;
}
