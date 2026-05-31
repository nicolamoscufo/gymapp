import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../models/workout.dart';

class ExerciseDetailScreen extends StatelessWidget {
  final String exerciseName;
  final List<WorkoutSession> history;

  const ExerciseDetailScreen({
    super.key,
    required this.exerciseName,
    required this.history,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final entries = _buildEntries();

    return Scaffold(
      appBar: AppBar(title: Text(exerciseName)),
      body: entries.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Text(
                  'Servono set completati per mostrare lo storico esercizio.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _SummaryCard(entries: entries),
                const SizedBox(height: 14),
                _MetricLineChart(
                  title: 'Volume',
                  entries: entries,
                  valueFor: (entry) => entry.volume,
                  formatValue: _formatKg,
                ),
                const SizedBox(height: 14),
                _MetricLineChart(
                  title: 'Top kg',
                  entries: entries,
                  valueFor: (entry) => entry.bestLoad,
                  formatValue: _formatKg,
                ),
                const SizedBox(height: 14),
                _CombinedExerciseTrendChart(entries: entries),
                const SizedBox(height: 14),
                _MetricLineChart(
                  title: 'Reps migliori',
                  entries: entries,
                  valueFor: (entry) => entry.bestReps.toDouble(),
                  formatValue: (value) => value.toStringAsFixed(0),
                ),
                const SizedBox(height: 14),
                _MetricLineChart(
                  title: 'e1RM',
                  entries: entries,
                  valueFor: (entry) => entry.e1rm,
                  formatValue: _formatKg,
                ),
                const SizedBox(height: 14),
                _MetricLineChart(
                  title: 'Top set volume',
                  entries: entries,
                  valueFor: (entry) => entry.bestSetVolume,
                  formatValue: _formatKg,
                ),
                const SizedBox(height: 14),
                Text(
                  'Sessioni',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 8),
                ...entries.reversed.map(
                  (entry) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Card(
                      child: ListTile(
                        leading: CircleAvatar(
                          child: Text(
                            '${entry.date.day}',
                            style: const TextStyle(fontWeight: FontWeight.w900),
                          ),
                        ),
                        title: Text(
                          '${entry.date.day}/${entry.date.month}/${entry.date.year}',
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                        subtitle: Text(
                          'Volume ${_formatKg(entry.volume)} - Set ${entry.completedSets} - e1RM ${_formatKg(entry.e1rm)}',
                        ),
                        trailing: Text(
                          '${_formatKg(entry.bestLoad)}\nTop load',
                          textAlign: TextAlign.right,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  List<_ExerciseHistoryEntry> _buildEntries() {
    final normalizedName = _normalize(exerciseName);
    final entries = <_ExerciseHistoryEntry>[];

    final sortedHistory = List<WorkoutSession>.from(history)
      ..sort((a, b) => a.endTime.compareTo(b.endTime));
    for (final session in sortedHistory) {
      for (final exercise in session.exercises) {
        if (_normalize(exercise.name) != normalizedName) {
          continue;
        }

        var volume = 0.0;
        var bestLoad = 0.0;
        var e1rm = 0.0;
        var bestReps = 0;
        var totalReps = 0;
        var bestSetVolume = 0.0;
        var completedSets = 0;
        var rpeTotal = 0.0;
        var rpeCount = 0;
        for (final set in exercise.sets) {
          if (!set.isCompleted || set.isWarmup) {
            continue;
          }
          completedSets++;
          volume += set.weight * set.reps;
          totalReps += set.reps;
          bestLoad = math.max(bestLoad, set.weight);
          bestReps = math.max(bestReps, set.reps);
          bestSetVolume = math.max(bestSetVolume, set.weight * set.reps);
          e1rm = math.max(e1rm, set.weight * (1 + set.reps / 30));
          if (set.rpe != null) {
            rpeTotal += set.rpe!;
            rpeCount++;
          }
        }
        if (completedSets == 0) {
          continue;
        }

        entries.add(
          _ExerciseHistoryEntry(
            date: session.endTime,
            volume: volume,
            bestLoad: bestLoad,
            e1rm: e1rm,
            bestReps: bestReps,
            averageReps: completedSets == 0 ? 0 : totalReps / completedSets,
            averageRpe: rpeCount == 0 ? null : rpeTotal / rpeCount,
            bestSetVolume: bestSetVolume,
            completedSets: completedSets,
          ),
        );
      }
    }

    return entries;
  }
}

class _SummaryCard extends StatelessWidget {
  final List<_ExerciseHistoryEntry> entries;

  const _SummaryCard({required this.entries});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final latest = entries.last;
    final bestVolume = entries.fold<double>(
      0,
      (best, entry) => math.max(best, entry.volume),
    );
    final bestE1rm = entries.fold<double>(
      0,
      (best, entry) => math.max(best, entry.e1rm),
    );
    final bestLoad = entries.fold<double>(
      0,
      (best, entry) => math.max(best, entry.bestLoad),
    );
    final bestReps = entries.fold<int>(
      0,
      (best, entry) => math.max(best, entry.bestReps),
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _MetricChip(
              label: 'Ultimo volume',
              value: _formatKg(latest.volume),
            ),
            _MetricChip(label: 'Record volume', value: _formatKg(bestVolume)),
            _MetricChip(label: 'Record kg', value: _formatKg(bestLoad)),
            _MetricChip(label: 'Record reps', value: '$bestReps'),
            _MetricChip(
              label: 'RPE ultimo',
              value: latest.averageRpe?.toStringAsFixed(1) ?? '-',
              color: colorScheme.tertiary,
            ),
            _MetricChip(label: 'Record e1RM', value: _formatKg(bestE1rm)),
            _MetricChip(
              label: 'Sessioni',
              value: '${entries.length}',
              color: colorScheme.secondary,
            ),
          ],
        ),
      ),
    );
  }
}

class _CombinedExerciseTrendChart extends StatelessWidget {
  final List<_ExerciseHistoryEntry> entries;

  const _CombinedExerciseTrendChart({required this.entries});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final maxLoad = entries.fold<double>(
      0,
      (max, entry) => math.max(max, entry.bestLoad),
    );
    final maxReps = entries.fold<double>(
      0,
      (max, entry) => math.max(max, entry.averageReps),
    );
    final hasRpe = entries.any((entry) => entry.averageRpe != null);

    double normalized(double value, double maxValue) {
      if (maxValue <= 0) return 0;
      return value / maxValue * 100;
    }

    LineChartBarData line({
      required Color color,
      required double Function(_ExerciseHistoryEntry entry) valueFor,
    }) {
      return LineChartBarData(
        spots: List.generate(
          entries.length,
          (index) => FlSpot(index.toDouble(), valueFor(entries[index])),
        ),
        isCurved: true,
        color: color,
        barWidth: 3,
        dotData: const FlDotData(show: true),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Kg / Reps / RPE nel tempo',
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 4),
            Text(
              'Linee normalizzate per confrontare trend diversi.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 210,
              child: LineChart(
                LineChartData(
                  minY: 0,
                  maxY: 110,
                  gridData: FlGridData(
                    drawVerticalLine: false,
                    getDrawingHorizontalLine: (value) => FlLine(
                      color: colorScheme.outlineVariant,
                      strokeWidth: 1,
                    ),
                  ),
                  titlesData: const FlTitlesData(
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    rightTitles: AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    topTitles: AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                  ),
                  borderData: FlBorderData(show: false),
                  lineBarsData: [
                    line(
                      color: colorScheme.primary,
                      valueFor: (entry) => normalized(entry.bestLoad, maxLoad),
                    ),
                    line(
                      color: colorScheme.secondary,
                      valueFor: (entry) =>
                          normalized(entry.averageReps, maxReps),
                    ),
                    if (hasRpe)
                      line(
                        color: colorScheme.tertiary,
                        valueFor: (entry) =>
                            normalized(entry.averageRpe ?? 0, 10),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                Chip(
                  label: Text('Kg top'),
                  avatar: Icon(
                    Icons.circle,
                    color: colorScheme.primary,
                    size: 14,
                  ),
                ),
                Chip(
                  label: Text('Reps medie'),
                  avatar: Icon(
                    Icons.circle,
                    color: colorScheme.secondary,
                    size: 14,
                  ),
                ),
                if (hasRpe)
                  Chip(
                    label: Text('RPE medio'),
                    avatar: Icon(
                      Icons.circle,
                      color: colorScheme.tertiary,
                      size: 14,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MetricChip extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;

  const _MetricChip({required this.label, required this.value, this.color});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final accent = color ?? colorScheme.primary;

    return Container(
      width: 150,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accent.withValues(alpha: 0.20)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: theme.textTheme.titleMedium?.copyWith(
              color: accent,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricLineChart extends StatelessWidget {
  final String title;
  final List<_ExerciseHistoryEntry> entries;
  final double Function(_ExerciseHistoryEntry entry) valueFor;
  final String Function(double value) formatValue;

  const _MetricLineChart({
    required this.title,
    required this.entries,
    required this.valueFor,
    required this.formatValue,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final maxValue = entries.fold<double>(
      0,
      (max, entry) => math.max(max, valueFor(entry)),
    );
    final latestValue = entries.isEmpty ? 0.0 : valueFor(entries.last);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  title,
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900),
                ),
                Text(formatValue(latestValue)),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 190,
              child: LineChart(
                LineChartData(
                  minY: 0,
                  maxY: maxValue == 0 ? 1 : maxValue * 1.15,
                  gridData: FlGridData(
                    drawVerticalLine: false,
                    getDrawingHorizontalLine: (value) => FlLine(
                      color: colorScheme.outlineVariant,
                      strokeWidth: 1,
                    ),
                  ),
                  titlesData: const FlTitlesData(
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    rightTitles: AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    topTitles: AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                  ),
                  borderData: FlBorderData(show: false),
                  lineBarsData: [
                    LineChartBarData(
                      spots: List.generate(
                        entries.length,
                        (index) =>
                            FlSpot(index.toDouble(), valueFor(entries[index])),
                      ),
                      isCurved: true,
                      color: colorScheme.primary,
                      barWidth: 4,
                      dotData: const FlDotData(show: true),
                      belowBarData: BarAreaData(
                        show: true,
                        color: colorScheme.primary.withValues(alpha: 0.12),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ExerciseHistoryEntry {
  final DateTime date;
  final double volume;
  final double bestLoad;
  final double e1rm;
  final int bestReps;
  final double averageReps;
  final double? averageRpe;
  final double bestSetVolume;
  final int completedSets;

  const _ExerciseHistoryEntry({
    required this.date,
    required this.volume,
    required this.bestLoad,
    required this.e1rm,
    required this.bestReps,
    required this.averageReps,
    required this.averageRpe,
    required this.bestSetVolume,
    required this.completedSets,
  });
}

String _normalize(String value) => value.trim().toLowerCase();

String _formatKg(double value) {
  final formatted = value % 1 == 0
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(1);
  return '$formatted kg';
}
