from pathlib import Path

# ---------------------------------------------------------------------------
# progress_intelligence.dart: expose exact comparison windows for drill-down.
# ---------------------------------------------------------------------------
path = Path('lib/progress_intelligence.dart')
text = path.read_text()

anchor = "class MuscleVolumeShift {"
insert = r'''class ProgressMetricComparisonWindow {
  final int windowSize;
  final double? previousAverage;
  final double? recentAverage;
  final double? changePercent;

  const ProgressMetricComparisonWindow({
    required this.windowSize,
    required this.previousAverage,
    required this.recentAverage,
    required this.changePercent,
  });

  bool get hasComparison =>
      windowSize > 0 && previousAverage != null && recentAverage != null;
}

class ExerciseProgressDrilldown {
  final ExerciseProgressInsight insight;
  final ExerciseProgressSummary summary;
  final ProgressMetricComparisonWindow estimatedOneRepMax;
  final ProgressMetricComparisonWindow volume;
  final List<PersonalRecordEvent> personalRecords;

  const ExerciseProgressDrilldown({
    required this.insight,
    required this.summary,
    required this.estimatedOneRepMax,
    required this.volume,
    required this.personalRecords,
  });
}

'''
if insert.strip() not in text:
    if anchor not in text:
        raise SystemExit('MuscleVolumeShift anchor not found')
    text = text.replace(anchor, insert + anchor, 1)

builder_anchor = "ProgressCenterIntelligence buildProgressCenterIntelligence({"
builder = r'''ExerciseProgressDrilldown? buildExerciseProgressDrilldown({
  required String exerciseName,
  required ProgressAnalytics analytics,
  DateTime? now,
}) {
  final reference = _dateOnly(now ?? DateTime.now());
  final normalized = exerciseName.trim().toLowerCase();
  ExerciseProgressSummary? summary;
  for (final candidate in analytics.exercises) {
    if (candidate.name.trim().toLowerCase() == normalized) {
      summary = candidate;
      break;
    }
  }
  if (summary == null) return null;

  final eligiblePoints = summary.points
      .where((point) => !_dateOnly(point.date).isAfter(reference))
      .toList();
  final e1rmValues = eligiblePoints
      .where((point) => point.estimatedOneRepMax != null)
      .map((point) => point.estimatedOneRepMax!)
      .toList();
  final volumeValues = eligiblePoints.map((point) => point.volume).toList();
  final records = analytics.personalRecords.where((record) {
    return record.exerciseName.trim().toLowerCase() == normalized &&
        !_dateOnly(record.date).isAfter(reference);
  }).toList();

  return ExerciseProgressDrilldown(
    insight: _buildExerciseInsight(summary, reference),
    summary: summary,
    estimatedOneRepMax: _buildMetricComparisonWindow(e1rmValues),
    volume: _buildMetricComparisonWindow(volumeValues),
    personalRecords: List.unmodifiable(records),
  );
}

'''
if builder.strip() not in text:
    if builder_anchor not in text:
        raise SystemExit('ProgressCenter builder anchor not found')
    text = text.replace(builder_anchor, builder + builder_anchor, 1)

old_window = r'''double? _windowChange(List<double> values) {
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
'''
new_window = r'''double? _windowChange(List<double> values) =>
    _buildMetricComparisonWindow(values).changePercent;

ProgressMetricComparisonWindow _buildMetricComparisonWindow(
  List<double> values,
) {
  if (values.length < 4) {
    return const ProgressMetricComparisonWindow(
      windowSize: 0,
      previousAverage: null,
      recentAverage: null,
      changePercent: null,
    );
  }
  final windowSize = math.min(3, values.length ~/ 2);
  final recent = values.sublist(values.length - windowSize);
  final previous = values.sublist(
    values.length - (windowSize * 2),
    values.length - windowSize,
  );
  final recentAverage = _average(recent);
  final previousAverage = _average(previous);
  return ProgressMetricComparisonWindow(
    windowSize: windowSize,
    previousAverage: previousAverage,
    recentAverage: recentAverage,
    changePercent: previousAverage <= 0
        ? null
        : ((recentAverage - previousAverage) / previousAverage) * 100,
  );
}
'''
if old_window not in text:
    raise SystemExit('window helper anchor not found')
text = text.replace(old_window, new_window, 1)
path.write_text(text)

# ---------------------------------------------------------------------------
# exercise_detail.dart: turn existing history screen into the canonical drill-down.
# ---------------------------------------------------------------------------
path = Path('lib/screens/exercise_detail.dart')
text = path.read_text()

if "import '../progress_analytics.dart';" not in text:
    text = text.replace(
        "import '../models/workout.dart';\n",
        "import '../models/workout.dart';\nimport '../progress_analytics.dart';\nimport '../progress_intelligence.dart';\n",
        1,
    )

text = text.replace(
    "  final List<WorkoutSession> history;\n\n  const ExerciseDetailScreen({\n    super.key,\n    required this.exerciseName,\n    required this.history,\n  });",
    "  final List<WorkoutSession> history;\n  final DateTime? now;\n\n  const ExerciseDetailScreen({\n    super.key,\n    required this.exerciseName,\n    required this.history,\n    this.now,\n  });",
    1,
)

text = text.replace(
    "    final entries = _buildEntries();\n\n    return Scaffold(",
    "    final entries = _buildEntries();\n    final analytics = buildProgressAnalytics(history: history, now: now);\n    final drilldown = buildExerciseProgressDrilldown(\n      exerciseName: exerciseName,\n      analytics: analytics,\n      now: now,\n    );\n\n    return Scaffold(",
    1,
)

text = text.replace(
    "                _SummaryCard(entries: entries),\n                const SizedBox(height: 14),\n                _MetricLineChart(",
    "                _SummaryCard(entries: entries),\n                if (drilldown != null) ...[\n                  const SizedBox(height: 14),\n                  _ProgressInterpretationCard(drilldown: drilldown),\n                ],\n                const SizedBox(height: 14),\n                _MetricLineChart(",
    1,
)

session_anchor = r'''                const SizedBox(height: 14),
                Text(
                  'Sessioni',
'''
replacement = r'''                if (drilldown != null) ...[
                  const SizedBox(height: 14),
                  _PersonalRecordTimelineCard(
                    records: drilldown.personalRecords.take(12).toList(),
                  ),
                ],
                const SizedBox(height: 14),
                Text(
                  'Sessioni',
'''
if session_anchor not in text:
    raise SystemExit('Sessioni anchor not found')
text = text.replace(session_anchor, replacement, 1)

summary_anchor = "class _SummaryCard extends StatelessWidget {"
widgets = r'''class _ProgressInterpretationCard extends StatelessWidget {
  final ExerciseProgressDrilldown drilldown;

  const _ProgressInterpretationCard({required this.drilldown});

  @override
  Widget build(BuildContext context) {
    final insight = drilldown.insight;
    final scheme = Theme.of(context).colorScheme;
    final accent = switch (insight.momentum) {
      ProgressMomentum.growing => scheme.primary,
      ProgressMomentum.stable => scheme.tertiary,
      ProgressMomentum.declining => scheme.error,
      ProgressMomentum.insufficient => scheme.onSurfaceVariant,
    };
    final recency = insight.daysSinceLastTrained == 0
        ? 'Allenato oggi'
        : '${insight.daysSinceLastTrained} giorni dall’ultima seduta';

    return Card(
      key: const ValueKey('exercise-progress-drilldown'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Analisi del trend',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    insight.momentum.label,
                    style: TextStyle(
                      color: accent,
                      fontWeight: FontWeight.w900,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              insight.primarySignal,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            _ComparisonRow(
              label: 'e1RM blocchi',
              window: drilldown.estimatedOneRepMax,
            ),
            const Divider(height: 18),
            _ComparisonRow(
              label: 'Volume blocchi',
              window: drilldown.volume,
            ),
            const Divider(height: 18),
            Row(
              children: [
                const Icon(Icons.history_toggle_off, size: 18),
                const SizedBox(width: 8),
                Expanded(child: Text(recency)),
                if (insight.isStale)
                  Text(
                    'Poco recente',
                    style: TextStyle(
                      color: scheme.error,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              'Classificazione: crescita oltre +2%, calo sotto -2%, altrimenti stabile. Il confronto usa fino a 3 sedute recenti contro lo stesso numero di sedute precedenti.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ComparisonRow extends StatelessWidget {
  final String label;
  final ProgressMetricComparisonWindow window;

  const _ComparisonRow({required this.label, required this.window});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (!window.hasComparison) {
      return Row(
        children: [
          Expanded(
            child: Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
          ),
          Text(
            'Dati insufficienti',
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
        ],
      );
    }
    final change = window.changePercent;
    final changeColor = change != null && change < -2
        ? scheme.error
        : change != null && change > 2
        ? scheme.primary
        : scheme.onSurfaceVariant;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 2),
              Text(
                '${window.windowSize} sedute vs ${window.windowSize} sedute',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        Text(
          '${_formatKg(window.previousAverage!)} → ${_formatKg(window.recentAverage!)}',
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        const SizedBox(width: 8),
        Text(
          change == null ? '-' : _signedPercent(change),
          style: TextStyle(color: changeColor, fontWeight: FontWeight.w900),
        ),
      ],
    );
  }
}

class _PersonalRecordTimelineCard extends StatelessWidget {
  final List<PersonalRecordEvent> records;

  const _PersonalRecordTimelineCard({required this.records});

  @override
  Widget build(BuildContext context) {
    return Card(
      key: const ValueKey('exercise-pr-timeline'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'PR timeline',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Gli ultimi record rilevati per questo esercizio.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            if (records.isEmpty)
              const Text('Nessun PR disponibile.')
            else
              ...records.map(
                (record) => ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.emoji_events_outlined),
                  title: Text(
                    record.kind.label,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  subtitle: Text(
                    '${record.date.day}/${record.date.month}/${record.date.year}',
                  ),
                  trailing: Text(
                    _formatPersonalRecord(record),
                    textAlign: TextAlign.right,
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

String _formatPersonalRecord(PersonalRecordEvent record) => switch (record.kind) {
  PersonalRecordKind.weight => _formatKg(record.value),
  PersonalRecordKind.reps => '${record.value.toStringAsFixed(0)} reps',
  PersonalRecordKind.setVolume => _formatKg(record.value),
  PersonalRecordKind.estimatedOneRepMax => '${_formatKg(record.value)} e1RM',
  PersonalRecordKind.sessionVolume => _formatKg(record.value),
};

String _signedPercent(double value) =>
    '${value > 0 ? '+' : ''}${value.toStringAsFixed(1)}%';

'''
if widgets.strip() not in text:
    if summary_anchor not in text:
        raise SystemExit('Summary card anchor not found')
    text = text.replace(summary_anchor, widgets + summary_anchor, 1)

path.write_text(text)

# ---------------------------------------------------------------------------
# progress_center.dart: navigation from Focus and Exercises.
# ---------------------------------------------------------------------------
path = Path('lib/screens/progress_center.dart')
text = path.read_text()

if "import 'exercise_detail.dart';" not in text:
    text = text.replace("import 'stats.dart';\n", "import 'exercise_detail.dart';\nimport 'stats.dart';\n", 1)

text = text.replace(
    "                _ProgressFocusTab(intelligence: intelligence),\n                _ExerciseProgressTab(analytics: analytics),",
    "                _ProgressFocusTab(\n                  intelligence: intelligence,\n                  history: history,\n                  now: now,\n                ),\n                _ExerciseProgressTab(\n                  analytics: analytics,\n                  history: history,\n                  now: now,\n                ),",
    1,
)

text = text.replace(
    "class _ProgressFocusTab extends StatelessWidget {\n  final ProgressCenterIntelligence intelligence;\n\n  const _ProgressFocusTab({required this.intelligence});",
    "class _ProgressFocusTab extends StatelessWidget {\n  final ProgressCenterIntelligence intelligence;\n  final List<WorkoutSession> history;\n  final DateTime? now;\n\n  const _ProgressFocusTab({\n    required this.intelligence,\n    required this.history,\n    required this.now,\n  });",
    1,
)

text = text.replace(
    "          ...attention.map((entry) => _ExerciseInsightTile(insight: entry)),",
    "          ...attention.map(\n            (entry) => _ExerciseInsightTile(\n              insight: entry,\n              onTap: () => _openExerciseDrilldown(\n                context,\n                entry.name,\n                history,\n                now,\n              ),\n            ),\n          ),",
    1,
)
text = text.replace(
    "          ...intelligence.exercises.map(\n            (entry) => _ExerciseInsightTile(insight: entry),\n          ),",
    "          ...intelligence.exercises.map(\n            (entry) => _ExerciseInsightTile(\n              insight: entry,\n              onTap: () => _openExerciseDrilldown(\n                context,\n                entry.name,\n                history,\n                now,\n              ),\n            ),\n          ),",
    1,
)

text = text.replace(
    "class _ExerciseInsightTile extends StatelessWidget {\n  final ExerciseProgressInsight insight;\n\n  const _ExerciseInsightTile({required this.insight});",
    "class _ExerciseInsightTile extends StatelessWidget {\n  final ExerciseProgressInsight insight;\n  final VoidCallback? onTap;\n\n  const _ExerciseInsightTile({required this.insight, this.onTap});",
    1,
)
text = text.replace(
    "        trailing: _MomentumBadge(momentum: insight.momentum),\n      ),",
    "        trailing: Row(\n          mainAxisSize: MainAxisSize.min,\n          children: [\n            _MomentumBadge(momentum: insight.momentum),\n            if (onTap != null) ...[\n              const SizedBox(width: 4),\n              const Icon(Icons.chevron_right),\n            ],\n          ],\n        ),\n        onTap: onTap,\n      ),",
    1,
)

text = text.replace(
    "class _ExerciseProgressTab extends StatefulWidget {\n  final ProgressAnalytics analytics;\n\n  const _ExerciseProgressTab({required this.analytics});",
    "class _ExerciseProgressTab extends StatefulWidget {\n  final ProgressAnalytics analytics;\n  final List<WorkoutSession> history;\n  final DateTime? now;\n\n  const _ExerciseProgressTab({\n    required this.analytics,\n    required this.history,\n    required this.now,\n  });",
    1,
)
text = text.replace("  String? _selectedName;\n", "", 1)
text = text.replace(
    "    final selected = _selectedExercise(exercises);",
    "    final selected = exercises.isEmpty ? null : exercises.first;",
    1,
)
text = text.replace(
    "          _ExerciseDetailCard(summary: selected),",
    "          _ExerciseDetailCard(\n            summary: selected,\n            onOpen: () => _openExerciseDrilldown(\n              context,\n              selected.name,\n              widget.history,\n              widget.now,\n            ),\n          ),",
    1,
)

old_tile = r'''            (entry) => Card(
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
'''
new_tile = r'''            (entry) => Card(
              key: ValueKey('progress-exercise-open-${entry.name}'),
              child: ListTile(
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
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _TrendBadge(
                      percent: entry.estimatedOneRepMaxTrendPercent,
                    ),
                    const SizedBox(width: 4),
                    const Icon(Icons.chevron_right),
                  ],
                ),
                onTap: () => _openExerciseDrilldown(
                  context,
                  entry.name,
                  widget.history,
                  widget.now,
                ),
              ),
            ),
'''
if old_tile not in text:
    raise SystemExit('Exercise list tile anchor not found')
text = text.replace(old_tile, new_tile, 1)

# Remove obsolete selected-exercise helper.
helper_start = "  ExerciseProgressSummary? _selectedExercise(\n"
helper_end = "  }\n}\n\nclass _ExerciseDetailCard extends StatelessWidget {"
start = text.find(helper_start)
if start != -1:
    end = text.find(helper_end, start)
    if end == -1:
        raise SystemExit('selected exercise helper end not found')
    text = text[:start] + "}\n\nclass _ExerciseDetailCard extends StatelessWidget {" + text[end + len(helper_end):]

text = text.replace(
    "class _ExerciseDetailCard extends StatelessWidget {\n  final ExerciseProgressSummary summary;\n\n  const _ExerciseDetailCard({required this.summary});",
    "class _ExerciseDetailCard extends StatelessWidget {\n  final ExerciseProgressSummary summary;\n  final VoidCallback onOpen;\n\n  const _ExerciseDetailCard({required this.summary, required this.onOpen});",
    1,
)

chip_anchor = r'''            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _ValueChip(label: 'Best kg', value: _kg(summary.bestWeight)),
'''
# Insert CTA after the wrap's known final chip block.
chip_end = r'''                _ValueChip(
                  label: 'Best set',
                  value: _compactKg(summary.bestSetVolume),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              'e1RM nel tempo',
'''
chip_new = r'''                _ValueChip(
                  label: 'Best set',
                  value: _compactKg(summary.bestSetVolume),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                key: ValueKey('exercise-open-drilldown-${summary.name}'),
                onPressed: onOpen,
                icon: const Icon(Icons.analytics_outlined),
                label: const Text('Analisi completa'),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'e1RM nel tempo',
'''
if chip_end not in text:
    raise SystemExit('Exercise detail chip end anchor not found')
text = text.replace(chip_end, chip_new, 1)

helper_anchor = "class _ExerciseProgressTab extends StatefulWidget {"
nav_helper = r'''void _openExerciseDrilldown(
  BuildContext context,
  String exerciseName,
  List<WorkoutSession> history,
  DateTime? now,
) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => ExerciseDetailScreen(
        exerciseName: exerciseName,
        history: history,
        now: now,
      ),
    ),
  );
}

'''
if nav_helper.strip() not in text:
    if helper_anchor not in text:
        raise SystemExit('Exercise progress tab anchor not found')
    text = text.replace(helper_anchor, nav_helper + helper_anchor, 1)

path.write_text(text)
