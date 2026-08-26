from pathlib import Path

screen_path = Path('lib/screens/progress_center.dart')
text = screen_path.read_text()

text = text.replace(
    "import '../progress_analytics.dart';\n",
    "import '../progress_analytics.dart';\nimport '../progress_intelligence.dart';\n",
    1,
)
text = text.replace(
    "    final analytics = buildProgressAnalytics(history: history, now: now);\n    return DefaultTabController(\n      length: 4,",
    "    final analytics = buildProgressAnalytics(history: history, now: now);\n    final intelligence = buildProgressCenterIntelligence(\n      history: history,\n      analytics: analytics,\n      now: now,\n    );\n    return DefaultTabController(\n      length: 5,",
    1,
)
text = text.replace(
    "                Tab(icon: Icon(Icons.dashboard_outlined), text: 'Panoramica'),\n                Tab(icon: Icon(Icons.show_chart), text: 'Esercizi'),",
    "                Tab(icon: Icon(Icons.dashboard_outlined), text: 'Panoramica'),\n                Tab(icon: Icon(Icons.track_changes), text: 'Focus'),\n                Tab(icon: Icon(Icons.show_chart), text: 'Esercizi'),",
    1,
)
text = text.replace(
    "                StatsScreen(history: history, now: now),\n                _ExerciseProgressTab(analytics: analytics),",
    "                StatsScreen(history: history, now: now),\n                _ProgressFocusTab(intelligence: intelligence),\n                _ExerciseProgressTab(analytics: analytics),",
    1,
)

marker = "class _ExerciseProgressTab extends StatefulWidget {"
if marker not in text:
    raise SystemExit('exercise tab marker not found')

focus_classes = r'''class _ProgressFocusTab extends StatelessWidget {
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
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
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
            leading: const CircleAvatar(child: Icon(Icons.emoji_events_outlined)),
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
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
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
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
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
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
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

'''
text = text.replace(marker, focus_classes + marker, 1)
screen_path.write_text(text)

test_path = Path('test/progress_center_test.dart')
test = test_path.read_text()
test = test.replace(
    "import 'package:gymapp/screens/progress_center.dart';\n",
    "import 'package:gymapp/screens/progress_center.dart';\nimport 'package:shared_preferences/shared_preferences.dart';\n",
    1,
)
test = test.replace(
    "void main() {\n  testWidgets(",
    "void main() {\n  setUp(() {\n    SharedPreferences.setMockInitialValues({});\n  });\n\n  testWidgets(",
    1,
)
test = test.replace(
    "      expect(find.text('Panoramica'), findsOneWidget);\n      expect(find.text('Esercizi'), findsOneWidget);",
    "      expect(find.text('Panoramica'), findsOneWidget);\n      expect(find.text('Focus'), findsOneWidget);\n      expect(find.text('Esercizi'), findsOneWidget);",
    1,
)
test = test.replace(
    "      expect(find.text('Trend mensile'), findsOneWidget);\n\n      await tester.tap(find.text('Esercizi'));",
    "      expect(find.text('Trend mensile'), findsOneWidget);\n\n      await tester.tap(find.text('Focus'));\n      await tester.pumpAndSettle();\n      expect(find.text('Progress Intelligence'), findsOneWidget);\n      expect(find.text('Da monitorare'), findsOneWidget);\n      expect(find.text('Momentum esercizi'), findsOneWidget);\n      expect(find.text('Esposizione muscolare'), findsOneWidget);\n      expect(find.byKey(const ValueKey('progress-pr-momentum')), findsOneWidget);\n      expect(find.byKey(const ValueKey('progress-focus-Panca')), findsOneWidget);\n\n      await tester.tap(find.text('Esercizi'));",
    1,
)
test_path.write_text(test)
