import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../models/exercise.dart';
import '../models/workout.dart';
import '../progress_analytics.dart';
import '../progress_intelligence.dart';
import 'stats.dart';

class ProgressCenterScreen extends StatelessWidget {
  final List<WorkoutSession> history;
  final DateTime? now;

  const ProgressCenterScreen({super.key, required this.history, this.now});

  @override
  Widget build(BuildContext context) {
    if (history.isEmpty) {
      return StatsScreen(history: history, now: now);
    }
    final analytics = buildProgressAnalytics(history: history, now: now);
    final intelligence = buildProgressCenterIntelligence(
      history: history,
      analytics: analytics,
      now: now,
    );
    return DefaultTabController(
      length: 5,
      child: Column(
        children: [
          Material(
            color: Theme.of(context).colorScheme.surface,
            child: const TabBar(
              isScrollable: true,
              tabs: [
                Tab(icon: Icon(Icons.dashboard_outlined), text: 'Panoramica'),
                Tab(icon: Icon(Icons.track_changes), text: 'Focus'),
                Tab(icon: Icon(Icons.show_chart), text: 'Esercizi'),
                Tab(icon: Icon(Icons.accessibility_new), text: 'Muscoli'),
                Tab(icon: Icon(Icons.emoji_events_outlined), text: 'Record'),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              children: [
                StatsScreen(history: history, now: now),
                _ProgressFocusTab(intelligence: intelligence),
                _ExerciseProgressTab(analytics: analytics),
                _MuscleProgressTab(analytics: analytics),
                _RecordsProgressTab(analytics: analytics),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProgressFocusTab extends StatelessWidget {
  final ProgressCenterIntelligence intelligence;

  const _ProgressFocusTab({required this.intelligence});

  @override
  Widget build(BuildContext context) {
    final attention = intelligence.attentionExercises.take(6).toList();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Progress Intelligence',
          style: Theme.of(context).textTheme.titleLarge
              ?.copyWith(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 4),
        Text(
          'Segnali deterministici su momentum, recency e spostamenti dei set. Nessun punteggio opaco.',
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 12),
        _AnalyticsMetricGrid(
          items: [
            _AnalyticsMetric(
              'In crescita',
              '${intelligence.growingCount}',
              Icons.trending_up,
            ),
            _AnalyticsMetric(
              'Stabili',
              '${intelligence.stableCount}',
              Icons.trending_flat,
            ),
            _AnalyticsMetric(
              'In calo',
              '${intelligence.decliningCount}',
              Icons.trending_down,
            ),
            _AnalyticsMetric(
              'Poco recenti',
              '${intelligence.staleCount}',
              Icons.history_toggle_off,
            ),
          ],
        ),
        const SizedBox(height: 12),
        Card(
          key: const ValueKey('progress-pr-momentum'),
          child: ListTile(
            leading: const CircleAvatar(
              child: Icon(Icons.emoji_events_outlined),
            ),
            title: const Text(
              'PR momentum',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            subtitle: const Text('Ultimi 30 giorni vs 30 giorni precedenti'),
            trailing: Text(
              '${intelligence.personalRecordsLast30Days} / ${intelligence.personalRecordsPrevious30Days}',
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
        ),
        const SizedBox(height: 20),
        Text(
          'Da monitorare',
          style: Theme.of(context).textTheme.titleMedium
              ?.copyWith(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 4),
        Text(
          'Prima gli esercizi in calo, poi quelli non allenati da almeno 21 giorni.',
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 8),
        if (attention.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Nessun esercizio in calo o poco recente con i dati disponibili.',
              ),
            ),
          )
        else
          ...attention.map((entry) => _ExerciseInsightTile(insight: entry)),
        const SizedBox(height: 20),
        Text(
          'Momentum esercizi',
          style: Theme.of(context).textTheme.titleMedium
              ?.copyWith(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 4),
        Text(
          'Confronto tra le ultime 2-3 sedute valide e il blocco precedente della stessa dimensione.',
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 8),
        if (intelligence.exercises.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text('Nessun esercizio con set di lavoro completati.'),
            ),
          )
        else
          ...intelligence.exercises.map(
            (entry) => _ExerciseInsightTile(insight: entry),
          ),
        const SizedBox(height: 20),
        Text(
          'Esposizione muscolare',
          style: Theme.of(context).textTheme.titleMedium
              ?.copyWith(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 4),
        Text(
          'Set completati negli ultimi 30 giorni confrontati con i 30 precedenti.',
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 8),
        if (intelligence.muscleShifts.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text('Nessuna esposizione muscolare recente disponibile.'),
            ),
          )
        else
          ...intelligence.muscleShifts.map(
            (entry) => _MuscleShiftTile(shift: entry),
          ),
        const SizedBox(height: 80),
      ],
    );
  }
}

class _ExerciseInsightTile extends StatelessWidget {
  final ExerciseProgressInsight insight;

  const _ExerciseInsightTile({required this.insight});

  @override
  Widget build(BuildContext context) {
    final volumeChange = insight.volumeWindowChangePercent;
    final volumeText = volumeChange == null
        ? null
        : 'volume ${_signedPercent(volumeChange)}';
    final recency = insight.isStale
        ? 'poco recente · ${insight.daysSinceLastTrained}g'
        : insight.daysSinceLastTrained == 0
        ? 'allenato oggi'
        : '${insight.daysSinceLastTrained}g dall’ultima';

    return Card(
      key: ValueKey('progress-focus-${insight.name}'),
      child: ListTile(
        leading: CircleAvatar(
          child: Icon(_momentumIcon(insight.momentum), size: 20),
        ),
        title: Text(
          insight.name,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        subtitle: Text(
          [
            insight.primarySignal,
            if (volumeText != null) volumeText,
            recency,
          ].join(' · '),
        ),
        trailing: _MomentumBadge(momentum: insight.momentum),
      ),
    );
  }
}

class _MuscleShiftTile extends StatelessWidget {
  final MuscleVolumeShift shift;

  const _MuscleShiftTile({required this.shift});

  @override
  Widget build(BuildContext context) {
    final change = shift.setChangePercent;
    final changeLabel = shift.newlyActive
        ? 'Nuovo'
        : change == null
        ? '-'
        : _signedPercent(change);
    final color = change != null && change < 0
        ? Theme.of(context).colorScheme.error
        : Theme.of(context).colorScheme.primary;

    return Card(
      key: ValueKey('progress-muscle-shift-${shift.muscleGroup.name}'),
      child: ListTile(
        leading: const CircleAvatar(child: Icon(Icons.accessibility_new)),
        title: Text(
          shift.muscleGroup.label,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        subtitle: Text(
          '${shift.recentSets} set recenti · ${shift.previousSets} precedenti',
        ),
        trailing: Text(
          changeLabel,
          style: TextStyle(color: color, fontWeight: FontWeight.w900),
        ),
      ),
    );
  }
}

class _MomentumBadge extends StatelessWidget {
  final ProgressMomentum momentum;

  const _MomentumBadge({required this.momentum});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = switch (momentum) {
      ProgressMomentum.growing => scheme.primary,
      ProgressMomentum.stable => scheme.tertiary,
      ProgressMomentum.declining => scheme.error,
      ProgressMomentum.insufficient => scheme.onSurfaceVariant,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        momentum.label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

IconData _momentumIcon(ProgressMomentum momentum) => switch (momentum) {
  ProgressMomentum.growing => Icons.trending_up,
  ProgressMomentum.stable => Icons.trending_flat,
  ProgressMomentum.declining => Icons.trending_down,
  ProgressMomentum.insufficient => Icons.more_horiz,
};

String _signedPercent(double value) =>
    '${value > 0 ? '+' : ''}${value.toStringAsFixed(1)}%';

class _ExerciseProgressTab extends StatefulWidget {
  final ProgressAnalytics analytics;

  const _ExerciseProgressTab({required this.analytics});

  @override
  State<_ExerciseProgressTab> createState() => _ExerciseProgressTabState();
}

class _ExerciseProgressTabState extends State<_ExerciseProgressTab> {
  String _query = '';
  String? _selectedName;

  @override
  Widget build(BuildContext context) {
    final exercises = widget.analytics.exercises.where((entry) {
      return entry.name.toLowerCase().contains(_query.trim().toLowerCase());
    }).toList();
    final selected = _selectedExercise(exercises);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Progressione esercizi',
          style: Theme.of(context).textTheme.titleLarge
              ?.copyWith(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 4),
        Text(
          'e1RM, volume, carico, reps e storico sessione per sessione.',
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 12),
        TextField(
          key: const ValueKey('progress-exercise-search'),
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search),
            labelText: 'Cerca esercizio',
            border: OutlineInputBorder(),
            isDense: true,
          ),
          onChanged: (value) => setState(() => _query = value),
        ),
        if (selected != null) ...[
          const SizedBox(height: 16),
          _ExerciseDetailCard(summary: selected),
        ],
        const SizedBox(height: 16),
        Text(
          'Tutti gli esercizi',
          style: Theme.of(context).textTheme.titleMedium
              ?.copyWith(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 8),
        if (exercises.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text('Nessun esercizio corrisponde alla ricerca.'),
            ),
          )
        else
          ...exercises.map(
            (entry) => Card(
              child: ListTile(
                selected: selected?.name == entry.name,
                leading: CircleAvatar(
                  child: Text(entry.muscleGroup.label.characters.first),
                ),
                title: Text(
                  entry.name,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                subtitle: Text(
                  '${entry.muscleGroup.label} · ${entry.sessionCount} sessioni · ${entry.completedSets} set',
                ),
                trailing: _TrendBadge(
                  percent: entry.estimatedOneRepMaxTrendPercent,
                ),
                onTap: () => setState(() => _selectedName = entry.name),
              ),
            ),
          ),
        const SizedBox(height: 80),
      ],
    );
  }

  ExerciseProgressSummary? _selectedExercise(
    List<ExerciseProgressSummary> filtered,
  ) {
    if (filtered.isEmpty) return null;
    final selectedName = _selectedName;
    if (selectedName != null) {
      for (final entry in filtered) {
        if (entry.name == selectedName) return entry;
      }
    }
    return filtered.first;
  }
}

class _ExerciseDetailCard extends StatelessWidget {
  final ExerciseProgressSummary summary;

  const _ExerciseDetailCard({required this.summary});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final e1rmPoints = summary.points
        .where((point) => point.estimatedOneRepMax != null)
        .toList();
    final volumeMax = summary.points.fold<double>(
      0,
      (value, point) => math.max(value, point.volume),
    );

    return Card(
      key: ValueKey('exercise-progress-${summary.name}'),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        summary.name,
                        style: Theme.of(context).textTheme.titleLarge
                            ?.copyWith(fontWeight: FontWeight.w900),
                      ),
                      Text(
                        '${summary.muscleGroup.label} · ultima ${_shortDate(summary.lastTrainedAt)}',
                        style: Theme.of(context).textTheme.bodySmall
                            ?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                _TrendBadge(percent: summary.estimatedOneRepMaxTrendPercent),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _ValueChip(label: 'Best kg', value: _kg(summary.bestWeight)),
                _ValueChip(label: 'Best reps', value: '${summary.bestReps}'),
                _ValueChip(
                  label: 'Best e1RM',
                  value: _kg(summary.bestEstimatedOneRepMax),
                ),
                _ValueChip(
                  label: 'Volume totale',
                  value: _compactKg(summary.totalVolume),
                ),
                _ValueChip(
                  label: 'Best set',
                  value: _compactKg(summary.bestSetVolume),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              'e1RM nel tempo',
              style: Theme.of(context).textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 180,
              child: e1rmPoints.length < 2
                  ? const Center(
                      child: Text('Servono almeno 2 sessioni con e1RM valido.'),
                    )
                  : LineChart(
                      LineChartData(
                        gridData: const FlGridData(show: true),
                        borderData: FlBorderData(show: false),
                        titlesData: const FlTitlesData(
                          topTitles: AxisTitles(
                            sideTitles: SideTitles(showTitles: false),
                          ),
                          rightTitles: AxisTitles(
                            sideTitles: SideTitles(showTitles: false),
                          ),
                          leftTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 42,
                            ),
                          ),
                          bottomTitles: AxisTitles(
                            sideTitles: SideTitles(showTitles: false),
                          ),
                        ),
                        lineBarsData: [
                          LineChartBarData(
                            isCurved: true,
                            barWidth: 3,
                            color: scheme.primary,
                            dotData: const FlDotData(show: true),
                            spots: [
                              for (
                                var index = 0;
                                index < e1rmPoints.length;
                                index++
                              )
                                FlSpot(
                                  index.toDouble(),
                                  e1rmPoints[index].estimatedOneRepMax!,
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
            ),
            const SizedBox(height: 16),
            Text(
              'Volume per sessione',
              style: Theme.of(context).textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 170,
              child: BarChart(
                BarChartData(
                  maxY: volumeMax <= 0 ? 1 : volumeMax * 1.15,
                  borderData: FlBorderData(show: false),
                  gridData: const FlGridData(show: false),
                  titlesData: const FlTitlesData(
                    topTitles: AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    rightTitles: AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                  ),
                  barGroups: [
                    for (var index = 0; index < summary.points.length; index++)
                      BarChartGroupData(
                        x: index,
                        barRods: [
                          BarChartRodData(
                            toY: summary.points[index].volume,
                            width: 10,
                            color: scheme.tertiary,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ],
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

class _MuscleProgressTab extends StatefulWidget {
  final ProgressAnalytics analytics;

  const _MuscleProgressTab({required this.analytics});

  @override
  State<_MuscleProgressTab> createState() => _MuscleProgressTabState();
}

class _MuscleProgressTabState extends State<_MuscleProgressTab> {
  MuscleGroup? _selected;

  @override
  Widget build(BuildContext context) {
    final muscles = widget.analytics.muscles;
    if (muscles.isEmpty) {
      return const Center(child: Text('Nessun gruppo muscolare disponibile.'));
    }
    final selectedGroup = _selected ?? muscles.first.muscleGroup;
    final selected = muscles.firstWhere(
      (entry) => entry.muscleGroup == selectedGroup,
      orElse: () => muscles.first,
    );
    final maxSets = selected.weekly.fold<int>(
      0,
      (value, point) => math.max(value, point.sets),
    );

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Volume muscolare',
          style: Theme.of(context).textTheme.titleLarge
              ?.copyWith(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 4),
        Text(
          'Set e volume per distretto, con distribuzione 30 giorni e trend 8 settimane.',
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 14),
        SizedBox(height: 230, child: _MuscleDistributionPie(muscles: muscles)),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final entry in muscles)
              ChoiceChip(
                label: Text(entry.muscleGroup.label),
                selected: entry.muscleGroup == selected.muscleGroup,
                onSelected: (_) =>
                    setState(() => _selected = entry.muscleGroup),
              ),
          ],
        ),
        const SizedBox(height: 14),
        Card(
          key: ValueKey('muscle-progress-${selected.muscleGroup.name}'),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  selected.muscleGroup.label,
                  style: Theme.of(context).textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _ValueChip(label: 'Set 7g', value: '${selected.sets7Days}'),
                    _ValueChip(
                      label: 'Set 30g',
                      value: '${selected.sets30Days}',
                    ),
                    _ValueChip(
                      label: 'Volume 7g',
                      value: _compactKg(selected.volume7Days),
                    ),
                    _ValueChip(
                      label: 'Volume 30g',
                      value: _compactKg(selected.volume30Days),
                    ),
                    _ValueChip(
                      label: 'Quota set',
                      value:
                          '${(selected.setShare30Days * 100).toStringAsFixed(0)}%',
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  'Set / settimana',
                  style: Theme.of(context).textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 190,
                  child: BarChart(
                    BarChartData(
                      maxY: math.max(1, maxSets + 2).toDouble(),
                      borderData: FlBorderData(show: false),
                      gridData: const FlGridData(show: true),
                      titlesData: FlTitlesData(
                        topTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        rightTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        leftTitles: const AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 30,
                          ),
                        ),
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 32,
                            getTitlesWidget: (value, meta) {
                              final index = value.toInt();
                              if (index < 0 ||
                                  index >= selected.weekly.length) {
                                return const SizedBox.shrink();
                              }
                              final date = selected.weekly[index].weekStart;
                              return Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Text(
                                  '${date.day}/${date.month}',
                                  style: const TextStyle(fontSize: 10),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                      barGroups: [
                        for (
                          var index = 0;
                          index < selected.weekly.length;
                          index++
                        )
                          BarChartGroupData(
                            x: index,
                            barRods: [
                              BarChartRodData(
                                toY: selected.weekly[index].sets.toDouble(),
                                width: 16,
                                color: Theme.of(context).colorScheme.primary,
                                borderRadius: BorderRadius.circular(5),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        ...muscles.map(
          (entry) => Card(
            child: ListTile(
              title: Text(entry.muscleGroup.label),
              subtitle: Text(
                '${entry.sets30Days} set · ${entry.sessionCount30Days} sessioni · ${_compactKg(entry.volume30Days)}',
              ),
              trailing: Text(
                '${(entry.setShare30Days * 100).toStringAsFixed(0)}%',
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
              onTap: () => setState(() => _selected = entry.muscleGroup),
            ),
          ),
        ),
        const SizedBox(height: 80),
      ],
    );
  }
}

class _MuscleDistributionPie extends StatelessWidget {
  final List<MuscleProgressSummary> muscles;

  const _MuscleDistributionPie({required this.muscles});

  @override
  Widget build(BuildContext context) {
    final colors = [
      Theme.of(context).colorScheme.primary,
      Theme.of(context).colorScheme.secondary,
      Theme.of(context).colorScheme.tertiary,
      Theme.of(context).colorScheme.error,
      Theme.of(context).colorScheme.primaryContainer,
      Theme.of(context).colorScheme.secondaryContainer,
    ];
    final relevant = muscles
        .where((entry) => entry.sets30Days > 0)
        .take(8)
        .toList();
    if (relevant.isEmpty) {
      return const Center(child: Text('Nessun set negli ultimi 30 giorni.'));
    }
    return PieChart(
      PieChartData(
        centerSpaceRadius: 42,
        sectionsSpace: 2,
        sections: [
          for (var index = 0; index < relevant.length; index++)
            PieChartSectionData(
              value: relevant[index].sets30Days.toDouble(),
              color: colors[index % colors.length],
              radius: 70,
              title:
                  '${(relevant[index].setShare30Days * 100).toStringAsFixed(0)}%',
              titleStyle: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w900,
              ),
              badgeWidget: Tooltip(
                message: relevant[index].muscleGroup.label,
                child: const SizedBox(width: 2, height: 2),
              ),
            ),
        ],
      ),
    );
  }
}

class _RecordsProgressTab extends StatelessWidget {
  final ProgressAnalytics analytics;

  const _RecordsProgressTab({required this.analytics});

  @override
  Widget build(BuildContext context) {
    final month = analytics.currentMonth;
    final year = analytics.currentYear;
    final records = analytics.personalRecords;
    final latest = records.take(30).toList();
    final e1rmRecords = records
        .where((record) => record.kind == PersonalRecordKind.estimatedOneRepMax)
        .length;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'PR Dashboard',
          style: Theme.of(context).textTheme.titleLarge
              ?.copyWith(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 4),
        Text(
          'Record di carico, reps, volume, e1RM e volume esercizio.',
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 12),
        _AnalyticsMetricGrid(
          items: [
            _AnalyticsMetric(
              'PR totali',
              '${records.length}',
              Icons.emoji_events,
            ),
            _AnalyticsMetric(
              'PR mese',
              '${month.personalRecords}',
              Icons.calendar_month,
            ),
            _AnalyticsMetric('PR e1RM', '$e1rmRecords', Icons.military_tech),
            _AnalyticsMetric(
              'Streak settimane',
              '${analytics.consistency.currentActiveWeekStreak}',
              Icons.local_fire_department,
            ),
          ],
        ),
        const SizedBox(height: 20),
        _PeriodReportCard(
          title: 'Report mensile',
          subtitle: '${_monthName(month.start.month)} ${month.start.year}',
          report: month,
        ),
        const SizedBox(height: 12),
        _PeriodReportCard(
          title: 'Year in review',
          subtitle: '${year.start.year}',
          report: year,
        ),
        const SizedBox(height: 20),
        Text(
          'Record recenti',
          style: Theme.of(context).textTheme.titleMedium
              ?.copyWith(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 8),
        if (latest.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text('Nessun record disponibile.'),
            ),
          )
        else
          ...latest.map((record) => _RecordTile(record: record)),
        const SizedBox(height: 80),
      ],
    );
  }
}

class _PeriodReportCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final PeriodProgressReport report;

  const _PeriodReportCard({
    required this.title,
    required this.subtitle,
    required this.report,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w900),
            ),
            Text(
              subtitle,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _ValueChip(label: 'Workout', value: '${report.workouts}'),
                _ValueChip(label: 'Set', value: '${report.completedSets}'),
                _ValueChip(label: 'Reps', value: '${report.totalReps}'),
                _ValueChip(label: 'Volume', value: _compactKg(report.volume)),
                _ValueChip(
                  label: 'Tempo',
                  value: _duration(report.durationMinutes),
                ),
                _ValueChip(label: 'PR', value: '${report.personalRecords}'),
              ],
            ),
            const SizedBox(height: 12),
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.fitness_center),
              title: const Text('Esercizio principale'),
              trailing: Text(report.topExercise ?? '-'),
            ),
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.accessibility_new),
              title: const Text('Gruppo più allenato'),
              trailing: Text(report.topMuscleGroup?.label ?? '-'),
            ),
          ],
        ),
      ),
    );
  }
}

class _RecordTile extends StatelessWidget {
  final PersonalRecordEvent record;

  const _RecordTile({required this.record});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: const CircleAvatar(child: Icon(Icons.emoji_events_outlined)),
        title: Text(
          '${record.exerciseName} · ${record.kind.label}',
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        subtitle: Text(
          '${record.muscleGroup.label} · ${_shortDate(record.date)}',
        ),
        trailing: Text(
          _recordValue(record),
          textAlign: TextAlign.end,
          style: TextStyle(
            fontWeight: FontWeight.w900,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
      ),
    );
  }
}

class _ValueChip extends StatelessWidget {
  final String label;
  final String value;

  const _ValueChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        '$label  $value',
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _TrendBadge extends StatelessWidget {
  final double? percent;

  const _TrendBadge({required this.percent});

  @override
  Widget build(BuildContext context) {
    final value = percent;
    if (value == null) return const SizedBox.shrink();
    final positive = value >= 0;
    final color = positive
        ? Theme.of(context).colorScheme.primary
        : Theme.of(context).colorScheme.error;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        '${positive ? '+' : ''}${value.toStringAsFixed(1)}% e1RM',
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w800,
          fontSize: 12,
        ),
      ),
    );
  }
}

class _AnalyticsMetric {
  final String label;
  final String value;
  final IconData icon;

  const _AnalyticsMetric(this.label, this.value, this.icon);
}

class _AnalyticsMetricGrid extends StatelessWidget {
  final List<_AnalyticsMetric> items;

  const _AnalyticsMetricGrid({required this.items});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final count = constraints.maxWidth >= 700 ? 4 : 2;
        return GridView.count(
          crossAxisCount: count,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
          childAspectRatio: 1.6,
          children: [
            for (final item in items)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Icon(item.icon, size: 19),
                      Text(
                        item.value,
                        style: Theme.of(context).textTheme.titleLarge
                            ?.copyWith(fontWeight: FontWeight.w900),
                      ),
                      Text(
                        item.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

String _recordValue(PersonalRecordEvent record) => switch (record.kind) {
  PersonalRecordKind.weight =>
    '${_kg(record.value)}\n${record.reps ?? '-'} reps',
  PersonalRecordKind.reps =>
    '${record.value.toStringAsFixed(0)} reps\n${_kg(record.weight ?? 0)}',
  PersonalRecordKind.setVolume =>
    '${_compactKg(record.value)}\n${record.weight == null ? '' : '${_kg(record.weight!)} × ${record.reps}'}',
  PersonalRecordKind.estimatedOneRepMax => '${_kg(record.value)} e1RM',
  PersonalRecordKind.sessionVolume => _compactKg(record.value),
};

String _kg(double value) {
  final text = value % 1 == 0
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(1);
  return '$text kg';
}

String _compactKg(double value) {
  if (value >= 1000000) return '${(value / 1000000).toStringAsFixed(1)}M kg';
  if (value >= 1000) return '${(value / 1000).toStringAsFixed(1)}k kg';
  return _kg(value);
}

String _duration(int minutes) {
  if (minutes < 60) return '${minutes}m';
  final hours = minutes ~/ 60;
  final rest = minutes % 60;
  return rest == 0 ? '${hours}h' : '${hours}h ${rest}m';
}

String _shortDate(DateTime date) => '${date.day}/${date.month}/${date.year}';

String _monthName(int month) => const [
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
][month - 1];
