import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../models/exercise.dart';
import '../models/workout.dart';

class StatsScreen extends StatelessWidget {
  final List<WorkoutSession> history;
  final DateTime? now;

  const StatsScreen({super.key, required this.history, this.now});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final today = _dateOnly(now ?? DateTime.now());

    if (history.isEmpty) {
      return const Center(
        child: Text('Nessun dato per mostrare le statistiche.'),
      );
    }

    final sortedHistory = List<WorkoutSession>.from(history)
      ..sort((a, b) => a.startTime.compareTo(b.startTime));
    final currentMonthStart = DateTime(today.year, today.month);
    final nextMonthStart = DateTime(today.year, today.month + 1);
    final currentYearStart = DateTime(today.year);
    final nextYearStart = DateTime(today.year + 1);
    final currentWeekStart = _startOfWeek(today);

    final monthSessions = _sessionsInRange(
      sortedHistory,
      currentMonthStart,
      nextMonthStart,
    );
    final yearSessions = _sessionsInRange(
      sortedHistory,
      currentYearStart,
      nextYearStart,
    );

    final totalWorkouts = sortedHistory.length;
    final totalCompletedSets = _completedSetsForSessions(sortedHistory);
    final totalVolume = _volumeForSessions(sortedHistory);
    final monthVolume = _volumeForSessions(monthSessions);
    final yearVolume = _volumeForSessions(yearSessions);
    final monthCompletedSets = _completedSetsForSessions(monthSessions);
    final averageDurationMinutes = _averageDurationMinutes(sortedHistory);
    final averageVolumePerWorkout = totalWorkouts == 0
        ? 0.0
        : totalVolume / totalWorkouts;
    final averageRpe = _averageRpe(sortedHistory);

    final weeklyStats = _buildWeeklyStats(
      sortedHistory,
      now: today,
      weekCount: 8,
    );
    final monthlyStats = _buildMonthlyStats(
      sortedHistory,
      now: today,
      monthCount: 12,
    );
    final annualStats = _buildAnnualStats(sortedHistory);
    final dailyVolumes = _buildDailyVolumes(
      sortedHistory,
      now: today,
      days: 30,
    );
    final maxDailyVolume = dailyVolumes.fold<double>(
      0,
      (max, entry) => entry.volume > max ? entry.volume : max,
    );
    final exerciseSummaries = _buildExerciseSummaries(sortedHistory);
    final bestE1rm = exerciseSummaries.fold<double>(
      0,
      (max, entry) => entry.bestE1rm > max ? entry.bestE1rm : max,
    );
    final monthMuscleGroupStats = _buildMuscleGroupStats(monthSessions);
    final currentWeekMuscleGroupStats = _buildMuscleGroupStats(
      _sessionsInRange(
        sortedHistory,
        currentWeekStart,
        currentWeekStart.add(const Duration(days: 7)),
      ),
    );
    final activeWeekStreak = _currentActiveWeekStreak(
      sortedHistory,
      currentWeekStart,
    );
    final longestWeekStreak = _longestActiveWeekStreak(sortedHistory);
    final workoutsLast30Days = dailyVolumes.fold<int>(
      0,
      (sum, entry) => sum + entry.sessionCount,
    );
    final trainedDaysLast30 = dailyVolumes
        .where((entry) => entry.sessionCount > 0)
        .length;
    final averageWorkoutsPerWeek = weeklyStats.isEmpty
        ? 0.0
        : weeklyStats.fold<int>(0, (sum, entry) => sum + entry.sessionCount) /
              weeklyStats.length;
    final mostActiveWeekday = _mostActiveWeekday(sortedHistory);
    final bestMonth = monthlyStats.fold<_PeriodStats?>(null, (best, entry) {
      if (best == null || entry.volume > best.volume) {
        return entry;
      }
      return best;
    });

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _MetricGrid(
            metrics: [
              _MetricData(
                label: 'Allenamenti',
                value: '$totalWorkouts',
                helper: 'totali',
                icon: Icons.fitness_center,
              ),
              _MetricData(
                label: 'Questo mese',
                value: '${monthSessions.length}',
                helper: _monthName(currentMonthStart.month),
                icon: Icons.calendar_month,
              ),
              _MetricData(
                label: 'Volume mese',
                value: _formatCompactKg(monthVolume),
                helper: 'Anno ${_formatCompactKg(yearVolume)}',
                icon: Icons.show_chart,
              ),
              _MetricData(
                label: 'Set mese',
                value: '$monthCompletedSets',
                helper: 'Set totali $totalCompletedSets',
                icon: Icons.checklist,
              ),
              _MetricData(
                label: 'Settimane attive',
                value: '$activeWeekStreak',
                helper: 'Record $longestWeekStreak',
                icon: Icons.local_fire_department,
              ),
              _MetricData(
                label: 'Media sett.',
                value: averageWorkoutsPerWeek.toStringAsFixed(1),
                helper: 'ultime 8 settimane',
                icon: Icons.timeline,
              ),
              _MetricData(
                label: 'Durata media',
                value: _formatDurationMinutes(averageDurationMinutes),
                helper: 'per allenamento',
                icon: Icons.timer,
              ),
              _MetricData(
                label: 'Miglior e1RM',
                value: '${bestE1rm.toStringAsFixed(0)} kg',
                helper: 'stimato',
                icon: Icons.military_tech,
              ),
              _MetricData(
                label: 'RPE medio',
                value: averageRpe == null ? '-' : averageRpe.toStringAsFixed(1),
                helper: 'set allenanti',
                icon: Icons.speed,
              ),
            ],
          ),
          const SizedBox(height: 24),
          _SectionTitle(
            title: 'Trend mensile',
            subtitle: 'Volume e sedute negli ultimi 12 mesi.',
          ),
          const SizedBox(height: 12),
          _VolumeChartCard(
            entries: monthlyStats,
            color: colorScheme.primary,
            emptyText: 'Nessun volume mensile disponibile.',
          ),
          const SizedBox(height: 24),
          _SectionTitle(
            title: 'Trend annuale',
            subtitle: 'Carico totale per anno e numero allenamenti.',
          ),
          const SizedBox(height: 12),
          _VolumeChartCard(
            entries: annualStats,
            color: colorScheme.tertiary,
            emptyText: 'Nessun volume annuale disponibile.',
          ),
          const SizedBox(height: 24),
          _SectionTitle(
            title: 'Consistenza',
            subtitle: 'Frequenza, giorni attivi e ritmo medio.',
          ),
          const SizedBox(height: 12),
          _InsightCard(
            rows: [
              _InsightRowData(
                'Allenamenti ultimi 30 giorni',
                '$workoutsLast30Days',
              ),
              _InsightRowData(
                'Giorni allenati ultimi 30',
                '$trainedDaysLast30/30',
              ),
              _InsightRowData('Settimane attive di fila', '$activeWeekStreak'),
              _InsightRowData('Giorno più frequente', mostActiveWeekday),
              _InsightRowData(
                'Volume medio per allenamento',
                _formatCompactKg(averageVolumePerWorkout),
              ),
              _InsightRowData(
                'Mese migliore',
                bestMonth == null || bestMonth.volume == 0
                    ? '-'
                    : '${bestMonth.label} - ${_formatCompactKg(bestMonth.volume)}',
              ),
            ],
          ),
          const SizedBox(height: 24),
          _SectionTitle(
            title: 'Distribuzione muscolare - mese',
            subtitle: 'Dove sta andando il volume questo mese.',
          ),
          const SizedBox(height: 12),
          _MuscleGroupDistributionCard(stats: monthMuscleGroupStats),
          const SizedBox(height: 24),
          _SectionTitle(
            title:
                'Gruppi muscolari - settimana ${_isoWeekNumber(currentWeekStart)}',
            subtitle: 'Serie, ripetizioni e volume della settimana corrente.',
          ),
          const SizedBox(height: 12),
          _MuscleGroupListCard(stats: currentWeekMuscleGroupStats),
          const SizedBox(height: 24),
          _SectionTitle(
            title: 'Progressione settimanale',
            subtitle: 'Volume nelle ultime 8 settimane.',
          ),
          const SizedBox(height: 12),
          _VolumeChartCard(
            entries: weeklyStats,
            color: colorScheme.secondary,
            emptyText: 'Nessun volume settimanale disponibile.',
          ),
          const SizedBox(height: 24),
          _SectionTitle(
            title: 'Calendario ultimi 30 giorni',
            subtitle: 'Intensità colore proporzionale al volume.',
          ),
          const SizedBox(height: 12),
          _TrainingCalendarCard(
            dailyVolumes: dailyVolumes,
            maxDailyVolume: maxDailyVolume,
          ),
          const SizedBox(height: 24),
          _SectionTitle(
            title: 'Esercizi migliori',
            subtitle: 'Ordinati per volume totale.',
          ),
          const SizedBox(height: 12),
          _ExerciseSummaryCard(summaries: exerciseSummaries.take(6).toList()),
        ],
      ),
    );
  }
}

class _MetricGrid extends StatelessWidget {
  final List<_MetricData> metrics;

  const _MetricGrid({required this.metrics});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = constraints.maxWidth >= 720
            ? 4
            : constraints.maxWidth >= 480
            ? 3
            : 2;

        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: metrics.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: 1.35,
          ),
          itemBuilder: (context, index) => _MetricCard(data: metrics[index]),
        );
      },
    );
  }
}

class _MetricCard extends StatelessWidget {
  final _MetricData data;

  const _MetricCard({required this.data});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      child: Container(
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerLow,
        ),
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: colorScheme.primary.withValues(
                      alpha: isDark ? 0.24 : 0.14,
                    ),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Icon(data.icon, size: 17, color: colorScheme.primary),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    data.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
            Text(
              data.value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w900,
                color: colorScheme.primary,
              ),
            ),
            Text(
              data.helper,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  final String subtitle;

  const _SectionTitle({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: theme.textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _VolumeChartCard extends StatelessWidget {
  final List<_PeriodStats> entries;
  final Color color;
  final String emptyText;

  const _VolumeChartCard({
    required this.entries,
    required this.color,
    required this.emptyText,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final maxY = _chartMax(entries.map((entry) => entry.volume));

    if (entries.isEmpty) {
      return Card(
        elevation: 1,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(emptyText),
        ),
      );
    }

    return Card(
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 230,
              child: BarChart(
                BarChartData(
                  maxY: maxY,
                  alignment: BarChartAlignment.spaceAround,
                  barTouchData: BarTouchData(
                    enabled: true,
                    touchTooltipData: BarTouchTooltipData(
                      fitInsideHorizontally: true,
                      fitInsideVertically: true,
                      tooltipMargin: 6,
                      tooltipPadding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      tooltipBorderRadius: BorderRadius.circular(10),
                      maxContentWidth: 120,
                      getTooltipColor: (_) => colorScheme.inverseSurface,
                      getTooltipItem: (group, groupIndex, rod, rodIndex) {
                        final entry = entries[groupIndex];
                        return BarTooltipItem(
                          '${entry.label}\n${_formatCompactKg(rod.toY)}',
                          TextStyle(
                            color: colorScheme.onInverseSurface,
                            fontWeight: FontWeight.w800,
                            fontSize: 12,
                          ),
                        );
                      },
                    ),
                  ),
                  titlesData: FlTitlesData(
                    show: true,
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 34,
                        getTitlesWidget: (value, meta) {
                          final index = value.toInt();
                          if (index < 0 || index >= entries.length) {
                            return const SizedBox.shrink();
                          }

                          return SideTitleWidget(
                            meta: meta,
                            child: Text(
                              entries[index].label,
                              style: TextStyle(
                                color: colorScheme.onSurfaceVariant,
                                fontSize: 10,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 42,
                        interval: maxY / 4,
                        getTitlesWidget: (value, meta) {
                          if (value == 0 || value == maxY) {
                            return const SizedBox.shrink();
                          }
                          return Text(
                            _formatAxisKg(value),
                            style: TextStyle(
                              color: colorScheme.onSurfaceVariant,
                              fontSize: 10,
                            ),
                          );
                        },
                      ),
                    ),
                    topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                  ),
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    getDrawingHorizontalLine: (value) => FlLine(
                      color: colorScheme.outlineVariant,
                      strokeWidth: 1,
                    ),
                  ),
                  borderData: FlBorderData(show: false),
                  barGroups: List.generate(entries.length, (index) {
                    final entry = entries[index];
                    return BarChartGroupData(
                      x: index,
                      barRods: [
                        BarChartRodData(
                          toY: entry.volume,
                          color: entry.volume == 0
                              ? colorScheme.surfaceContainerHighest
                              : color,
                          width: entries.length > 10 ? 14 : 22,
                          borderRadius: BorderRadius.circular(5),
                        ),
                      ],
                    );
                  }),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: entries.where((entry) => entry.sessionCount > 0).map((
                entry,
              ) {
                return Chip(
                  label: Text(
                    '${entry.label}: ${entry.sessionCount} allen. - ${_formatCompactKg(entry.volume)}',
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }
}

class _InsightCard extends StatelessWidget {
  final List<_InsightRowData> rows;

  const _InsightCard({required this.rows});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      elevation: 1,
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: rows.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final row = rows[index];
          return ListTile(
            dense: true,
            title: Text(row.label),
            trailing: Text(
              row.value,
              style: TextStyle(
                color: colorScheme.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
          );
        },
      ),
    );
  }
}

class _MuscleGroupDistributionCard extends StatelessWidget {
  final List<_MuscleGroupStats> stats;

  const _MuscleGroupDistributionCard({required this.stats});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final topStats = stats.take(6).toList();
    final totalVolume = topStats.fold<double>(
      0,
      (sum, entry) => sum + entry.load,
    );
    final colors = [
      colorScheme.primary,
      colorScheme.secondary,
      colorScheme.tertiary,
      colorScheme.error,
      colorScheme.primaryContainer,
      colorScheme.secondaryContainer,
    ];

    if (topStats.isEmpty || totalVolume == 0) {
      return const Card(
        elevation: 1,
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text('Nessun set completato questo mese.'),
        ),
      );
    }

    return Card(
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            SizedBox(
              height: 220,
              child: PieChart(
                PieChartData(
                  centerSpaceRadius: 46,
                  sectionsSpace: 2,
                  sections: List.generate(topStats.length, (index) {
                    final entry = topStats[index];
                    final percent = totalVolume == 0
                        ? 0.0
                        : entry.load / totalVolume * 100;
                    return PieChartSectionData(
                      value: entry.load,
                      color: colors[index % colors.length],
                      title: percent >= 8
                          ? '${percent.toStringAsFixed(0)}%'
                          : '',
                      radius: 62,
                      titleStyle: TextStyle(
                        color: colorScheme.onPrimary,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    );
                  }),
                ),
              ),
            ),
            const SizedBox(height: 12),
            _MuscleGroupList(stats: topStats, colors: colors),
          ],
        ),
      ),
    );
  }
}

class _MuscleGroupListCard extends StatelessWidget {
  final List<_MuscleGroupStats> stats;

  const _MuscleGroupListCard({required this.stats});

  @override
  Widget build(BuildContext context) {
    if (stats.isEmpty) {
      return const Card(
        elevation: 1,
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text('Nessun set completato questa settimana.'),
        ),
      );
    }

    return Card(
      elevation: 1,
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: stats.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final entry = stats[index];
          return ListTile(
            title: Text(
              entry.group.label,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Text(
              'Serie: ${entry.completedSets} - Reps: ${entry.reps}',
            ),
            trailing: Text(
              _formatCompactKg(entry.load),
              textAlign: TextAlign.right,
              style: TextStyle(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
          );
        },
      ),
    );
  }
}

class _MuscleGroupList extends StatelessWidget {
  final List<_MuscleGroupStats> stats;
  final List<Color> colors;

  const _MuscleGroupList({required this.stats, required this.colors});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: List.generate(stats.length, (index) {
        final entry = stats[index];
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: colors[index % colors.length],
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(child: Text(entry.group.label)),
              Text(
                '${entry.completedSets} set - ${_formatCompactKg(entry.load)}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),
        );
      }),
    );
  }
}

class _TrainingCalendarCard extends StatelessWidget {
  final List<_DailyVolume> dailyVolumes;
  final double maxDailyVolume;

  const _TrainingCalendarCard({
    required this.dailyVolumes,
    required this.maxDailyVolume,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
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
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
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
                        style: TextStyle(color: foregroundColor, fontSize: 11),
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
    );
  }
}

class _ExerciseSummaryCard extends StatelessWidget {
  final List<_ExerciseSummary> summaries;

  const _ExerciseSummaryCard({required this.summaries});

  @override
  Widget build(BuildContext context) {
    if (summaries.isEmpty) {
      return const Card(
        elevation: 1,
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text('Nessun set allenante completato.'),
        ),
      );
    }

    return Card(
      elevation: 1,
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: summaries.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final summary = summaries[index];
          return ListTile(
            title: Text(
              summary.name,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Text(
              'Volume: ${_formatCompactKg(summary.volume)} - Set: ${summary.completedSets} - e1RM: ${summary.bestE1rm.toStringAsFixed(1)} kg${summary.averageRpe == null ? '' : ' - RPE medio: ${summary.averageRpe!.toStringAsFixed(1)}'}',
            ),
            trailing: Text(
              'Top set\n${summary.bestLoad.toStringAsFixed(1)} kg',
              textAlign: TextAlign.right,
            ),
          );
        },
      ),
    );
  }
}

class _MetricData {
  final String label;
  final String value;
  final String helper;
  final IconData icon;

  const _MetricData({
    required this.label,
    required this.value,
    required this.helper,
    required this.icon,
  });
}

class _InsightRowData {
  final String label;
  final String value;

  const _InsightRowData(this.label, this.value);
}

class _PeriodStats {
  final DateTime date;
  final String label;
  double volume = 0;
  int sessionCount = 0;
  int completedSets = 0;
  int reps = 0;
  int durationMinutes = 0;

  _PeriodStats({required this.date, required this.label});
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

class _MuscleGroupStats {
  final MuscleGroup group;
  int completedSets = 0;
  int reps = 0;
  double load = 0;

  _MuscleGroupStats(this.group);
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

List<WorkoutSession> _sessionsInRange(
  List<WorkoutSession> history,
  DateTime start,
  DateTime end,
) {
  return history
      .where(
        (session) =>
            !session.startTime.isBefore(start) &&
            session.startTime.isBefore(end),
      )
      .toList();
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

double _volumeForSessions(List<WorkoutSession> sessions) {
  return sessions.fold<double>(
    0,
    (sum, session) => sum + _volumeForSession(session),
  );
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

int _completedSetsForSessions(List<WorkoutSession> sessions) {
  return sessions.fold<int>(
    0,
    (sum, session) => sum + _completedSetsForSession(session),
  );
}

int _completedRepsForSession(WorkoutSession session) {
  int reps = 0;
  for (final exercise in session.exercises) {
    for (final set in exercise.sets) {
      if (set.isCompleted && !set.isWarmup) {
        reps += set.reps;
      }
    }
  }
  return reps;
}

int _durationMinutesForSession(WorkoutSession session) {
  final minutes = session.endTime.difference(session.startTime).inMinutes;
  return minutes < 0 ? 0 : minutes;
}

double _averageDurationMinutes(List<WorkoutSession> history) {
  if (history.isEmpty) {
    return 0;
  }

  final total = history.fold<int>(
    0,
    (sum, session) => sum + _durationMinutesForSession(session),
  );
  return total / history.length;
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

List<_PeriodStats> _buildWeeklyStats(
  List<WorkoutSession> history, {
  required DateTime now,
  required int weekCount,
}) {
  final currentWeekStart = _startOfWeek(now);
  final firstWeekStart = currentWeekStart.subtract(
    Duration(days: 7 * (weekCount - 1)),
  );
  final statsByWeek = <DateTime, _PeriodStats>{};

  for (int i = 0; i < weekCount; i++) {
    final weekStart = firstWeekStart.add(Duration(days: 7 * i));
    statsByWeek[weekStart] = _PeriodStats(
      date: weekStart,
      label: 'S${_isoWeekNumber(weekStart)}',
    );
  }

  for (final session in history) {
    final weekStart = _startOfWeek(session.startTime);
    final stats = statsByWeek[weekStart];
    if (stats == null) {
      continue;
    }
    _addSessionToPeriod(stats, session);
  }

  return statsByWeek.values.toList();
}

List<_PeriodStats> _buildMonthlyStats(
  List<WorkoutSession> history, {
  required DateTime now,
  required int monthCount,
}) {
  final firstMonth = DateTime(now.year, now.month - (monthCount - 1));
  final statsByMonth = <DateTime, _PeriodStats>{};

  for (int i = 0; i < monthCount; i++) {
    final monthStart = DateTime(firstMonth.year, firstMonth.month + i);
    statsByMonth[monthStart] = _PeriodStats(
      date: monthStart,
      label: _monthShortName(monthStart.month),
    );
  }

  for (final session in history) {
    final monthStart = DateTime(
      session.startTime.year,
      session.startTime.month,
    );
    final stats = statsByMonth[monthStart];
    if (stats == null) {
      continue;
    }
    _addSessionToPeriod(stats, session);
  }

  return statsByMonth.values.toList();
}

List<_PeriodStats> _buildAnnualStats(List<WorkoutSession> history) {
  if (history.isEmpty) {
    return [];
  }

  final years = history.map((session) => session.startTime.year).toList();
  final firstYear = years.reduce(math.min);
  final lastYear = years.reduce(math.max);
  final statsByYear = <DateTime, _PeriodStats>{};

  for (int year = firstYear; year <= lastYear; year++) {
    final yearStart = DateTime(year);
    statsByYear[yearStart] = _PeriodStats(date: yearStart, label: '$year');
  }

  for (final session in history) {
    final yearStart = DateTime(session.startTime.year);
    final stats = statsByYear[yearStart];
    if (stats == null) {
      continue;
    }
    _addSessionToPeriod(stats, session);
  }

  final stats = statsByYear.values.toList();
  if (stats.length <= 8) {
    return stats;
  }
  return stats.sublist(stats.length - 8);
}

void _addSessionToPeriod(_PeriodStats stats, WorkoutSession session) {
  stats.volume += _volumeForSession(session);
  stats.sessionCount++;
  stats.completedSets += _completedSetsForSession(session);
  stats.reps += _completedRepsForSession(session);
  stats.durationMinutes += _durationMinutesForSession(session);
}

List<_DailyVolume> _buildDailyVolumes(
  List<WorkoutSession> history, {
  required DateTime now,
  required int days,
}) {
  final today = _dateOnly(now);
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

List<_MuscleGroupStats> _buildMuscleGroupStats(List<WorkoutSession> history) {
  final statsByGroup = <MuscleGroup, _MuscleGroupStats>{};

  for (final session in history) {
    for (final exercise in session.exercises) {
      final stats = statsByGroup.putIfAbsent(
        exercise.muscleGroup,
        () => _MuscleGroupStats(exercise.muscleGroup),
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

int _currentActiveWeekStreak(
  List<WorkoutSession> history,
  DateTime currentWeekStart,
) {
  final activeWeeks = history
      .map((session) => _startOfWeek(session.startTime))
      .toSet();
  var streak = 0;
  var week = currentWeekStart;

  while (activeWeeks.contains(week)) {
    streak++;
    week = week.subtract(const Duration(days: 7));
  }

  return streak;
}

int _longestActiveWeekStreak(List<WorkoutSession> history) {
  final activeWeeks =
      history.map((session) => _startOfWeek(session.startTime)).toSet().toList()
        ..sort();
  if (activeWeeks.isEmpty) {
    return 0;
  }

  var longest = 1;
  var current = 1;
  for (int i = 1; i < activeWeeks.length; i++) {
    final previous = activeWeeks[i - 1];
    final currentWeek = activeWeeks[i];
    if (currentWeek.difference(previous).inDays == 7) {
      current++;
    } else {
      longest = math.max(longest, current);
      current = 1;
    }
  }

  return math.max(longest, current);
}

String _mostActiveWeekday(List<WorkoutSession> history) {
  if (history.isEmpty) {
    return '-';
  }

  final counts = <int, int>{};
  for (final session in history) {
    counts[session.startTime.weekday] =
        (counts[session.startTime.weekday] ?? 0) + 1;
  }

  final best = counts.entries.reduce((a, b) => a.value >= b.value ? a : b);
  return _weekdayName(best.key);
}

double _chartMax(Iterable<double> values) {
  final maxValue = values.fold<double>(0, math.max);
  if (maxValue <= 0) {
    return 1;
  }
  return maxValue * 1.18;
}

String _formatCompactKg(double value) {
  if (value >= 1000000) {
    return '${(value / 1000000).toStringAsFixed(1)}M kg';
  }
  if (value >= 10000) {
    return '${(value / 1000).toStringAsFixed(0)}k kg';
  }
  if (value >= 1000) {
    return '${(value / 1000).toStringAsFixed(1)}k kg';
  }
  return '${value.toStringAsFixed(0)} kg';
}

String _formatAxisKg(double value) {
  if (value >= 1000000) {
    return '${(value / 1000000).toStringAsFixed(1)}M';
  }
  if (value >= 1000) {
    return '${(value / 1000).toStringAsFixed(1)}k';
  }
  return value.toStringAsFixed(0);
}

String _formatDurationMinutes(double minutes) {
  if (minutes <= 0) {
    return '-';
  }
  final rounded = minutes.round();
  if (rounded < 60) {
    return '${rounded}m';
  }
  final hours = rounded ~/ 60;
  final remainingMinutes = rounded % 60;
  return remainingMinutes == 0 ? '${hours}h' : '${hours}h ${remainingMinutes}m';
}

String _monthName(int month) {
  const names = [
    'Gennaio',
    'Febbraio',
    'Marzo',
    'Aprile',
    'Maggio',
    'Giugno',
    'Luglio',
    'Agosto',
    'Settembre',
    'Ottobre',
    'Novembre',
    'Dicembre',
  ];
  return names[month - 1];
}

String _monthShortName(int month) {
  const names = [
    'Gen',
    'Feb',
    'Mar',
    'Apr',
    'Mag',
    'Giu',
    'Lug',
    'Ago',
    'Set',
    'Ott',
    'Nov',
    'Dic',
  ];
  return names[month - 1];
}

String _weekdayName(int weekday) {
  const names = [
    'Lunedi',
    'Martedi',
    'Mercoledi',
    'Giovedi',
    'Venerdi',
    'Sabato',
    'Domenica',
  ];
  return names[weekday - 1];
}
