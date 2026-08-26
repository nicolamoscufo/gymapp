from pathlib import Path

path = Path('lib/screens/session_summary.dart')
text = path.read_text()

text = text.replace(
    "import '../models/workout.dart';\n",
    "import '../models/workout.dart';\nimport '../post_workout_debrief.dart';\n",
    1,
)

text = text.replace(
    "    final duration = widget.session.endTime.difference(\n      widget.session.startTime,\n    );\n\n    return Scaffold(",
    "    final duration = widget.session.endTime.difference(\n      widget.session.startTime,\n    );\n    final debrief = buildPostWorkoutDebrief(\n      session: widget.session,\n      history: widget.previousHistory,\n    );\n\n    return Scaffold(",
    1,
)

text = text.replace(
    "            recordLabels: _sessionRecordLabels,\n            exerciseCards:",
    "            recordLabels: _sessionRecordLabels,\n            debrief: debrief,\n            exerciseCards:",
    1,
)

text = text.replace(
    "  final List<String> recordLabels;\n  final List<Widget> exerciseCards;",
    "  final List<String> recordLabels;\n  final PostWorkoutDebrief debrief;\n  final List<Widget> exerciseCards;",
    1,
)

text = text.replace(
    "    required this.recordLabels,\n    required this.exerciseCards,",
    "    required this.recordLabels,\n    required this.debrief,\n    required this.exerciseCards,",
    1,
)

text = text.replace(
    "          const SizedBox(height: 18),\n          ...exerciseCards,",
    "          const SizedBox(height: 18),\n          _PostWorkoutDebriefCard(debrief: debrief),\n          const SizedBox(height: 18),\n          ...exerciseCards,",
    1,
)

marker = "class _SummaryMetricTile extends StatelessWidget {"
if marker not in text:
    raise SystemExit('summary metric marker not found')

widget = r'''class _PostWorkoutDebriefCard extends StatelessWidget {
  final PostWorkoutDebrief debrief;

  const _PostWorkoutDebriefCard({required this.debrief});

  String _signedPercent(double value) {
    return '${value >= 0 ? '+' : ''}${value.toStringAsFixed(1)}%';
  }

  String _signedInt(int value) => '${value >= 0 ? '+' : ''}$value';

  String _signalLabel(ExerciseDebrief entry) {
    final signals = <String>[];
    final e1rm = entry.progression.estimatedOneRepMaxChangePercent;
    final volume = entry.progression.volumeChangePercent;
    final rir = entry.progression.effectiveRir;
    if (e1rm != null) signals.add('e1RM ${_signedPercent(e1rm)}');
    if (volume != null) signals.add('volume ${_signedPercent(volume)}');
    if (rir != null) signals.add('RIR ${rir.toStringAsFixed(1)}');
    return signals.isEmpty
        ? 'Decisione basata sui set completati.'
        : signals.join(' · ');
  }

  IconData _actionIcon(ExerciseDebrief entry) {
    return switch (entry.progression.action) {
      ProgressionAction.increaseLoad => Icons.add_circle_outline,
      ProgressionAction.increaseReps => Icons.trending_up,
      ProgressionAction.maintain => Icons.horizontal_rule,
      ProgressionAction.deload => Icons.trending_down,
      ProgressionAction.manual => Icons.tune,
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final volumeDelta = debrief.volumeChangePercent;
    final densityDelta = debrief.densityChangePercent;
    final setDelta = debrief.completedWorkSetDelta;

    return Card(
      key: const ValueKey('post-workout-debrief'),
      margin: EdgeInsets.zero,
      color: scheme.primaryContainer.withValues(alpha: 0.38),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.insights, color: scheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Smart Debrief',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                Chip(
                  label: const Text('Deterministico'),
                  visualDensity: VisualDensity.compact,
                  side: BorderSide.none,
                  backgroundColor: scheme.surface.withValues(alpha: 0.72),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              debrief.hasComparableSession
                  ? 'Confronto con l’ultima seduta della stessa scheda.'
                  : 'Prima seduta comparabile: da qui costruiamo il tuo riferimento.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _DebriefMetricChip(
                  key: const ValueKey('debrief-volume'),
                  icon: Icons.scale_outlined,
                  label: 'Volume',
                  value: volumeDelta == null
                      ? '${debrief.totalVolume.toStringAsFixed(0)} kg'
                      : _signedPercent(volumeDelta),
                ),
                _DebriefMetricChip(
                  key: const ValueKey('debrief-density'),
                  icon: Icons.speed,
                  label: 'Densità',
                  value: densityDelta == null
                      ? '${debrief.densityKgPerMinute.toStringAsFixed(0)} kg/min'
                      : _signedPercent(densityDelta),
                ),
                _DebriefMetricChip(
                  key: const ValueKey('debrief-sets'),
                  icon: Icons.checklist,
                  label: 'Set lavoro',
                  value: setDelta == null
                      ? '${debrief.completedWorkSets}'
                      : _signedInt(setDelta),
                ),
                if (debrief.readyToProgressCount > 0)
                  _DebriefMetricChip(
                    key: const ValueKey('debrief-ready-count'),
                    icon: Icons.rocket_launch_outlined,
                    label: 'Da progredire',
                    value: '${debrief.readyToProgressCount}',
                  ),
                if (debrief.deloadCount > 0)
                  _DebriefMetricChip(
                    key: const ValueKey('debrief-deload-count'),
                    icon: Icons.battery_saver_outlined,
                    label: 'Da scaricare',
                    value: '${debrief.deloadCount}',
                  ),
              ],
            ),
            if (debrief.exercises.isNotEmpty) ...[
              const SizedBox(height: 14),
              Divider(color: scheme.outlineVariant),
              const SizedBox(height: 4),
              Text(
                'Prossima volta',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 4),
              for (final entry in debrief.exercises.take(5))
                ListTile(
                  key: ValueKey('debrief-next-${entry.exerciseId}'),
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  leading: Icon(_actionIcon(entry), color: scheme.primary),
                  title: Text(
                    entry.exerciseName,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  subtitle: Text(_signalLabel(entry)),
                  trailing: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 150),
                    child: Text(
                      entry.nextStep,
                      textAlign: TextAlign.right,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.primary,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
              if (debrief.exercises.length > 5)
                Text(
                  '+ ${debrief.exercises.length - 5} altri esercizi nel Progress Center',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _DebriefMetricChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _DebriefMetricChip({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 17, color: scheme.primary),
          const SizedBox(width: 6),
          Text('$label ', style: Theme.of(context).textTheme.labelMedium),
          Text(
            value,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

'''

text = text.replace(marker, widget + marker, 1)
path.write_text(text)
