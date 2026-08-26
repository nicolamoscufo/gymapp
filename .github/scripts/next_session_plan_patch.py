from pathlib import Path


def replace_once(text: str, old: str, new: str, label: str) -> str:
    if old not in text:
        raise SystemExit(f'missing patch target: {label}')
    return text.replace(old, new, 1)


# 1) Stop silently mutating the saved schedule when the workout is finished.
path = Path('lib/screens/active_workout.dart')
text = path.read_text()
start = text.find('  Future<void> _applyProgressionToSchedule() async {')
end = text.find('  Future<void> _finishWorkout() async {', start)
if start < 0 or end < 0:
    raise SystemExit('missing active workout progression method boundaries')
text = text[:start] + text[end:]
text = replace_once(
    text,
    '    await AppDataStore.saveHistory(history);\n    await _applyProgressionToSchedule();\n    await AppDataStore.clearCurrentSession();',
    '    await AppDataStore.saveHistory(history);\n    await AppDataStore.clearCurrentSession();',
    'remove automatic schedule progression',
)
text = replace_once(
    text,
    '          builder: (context) => SessionSummaryScreen(\n            session: session,\n            previousHistory: previousHistory,\n          ),',
    '          builder: (context) => SessionSummaryScreen(\n'
    '            session: session,\n'
    '            previousHistory: previousHistory,\n'
    '            skipProgressionExerciseIds: Set<String>.unmodifiable(\n'
    '              _exerciseIdsAddedToScheduleThisFinish,\n'
    '            ),\n'
    '          ),',
    'pass newly-added exercise ids to summary',
)
path.write_text(text)


# 2) Add reviewed Next Session Plan UI and confirmed persistence.
path = Path('lib/screens/session_summary.dart')
text = path.read_text()
text = replace_once(
    text,
    "import '../ai_coach/ai_coach_handoff.dart';\n",
    "import '../ai_coach/ai_coach_handoff.dart';\nimport '../app_data_store.dart';\n",
    'summary app store import',
)
text = replace_once(
    text,
    "import '../post_workout_debrief.dart';\n",
    "import '../post_workout_debrief.dart';\nimport '../post_workout_next_session_plan.dart';\n",
    'summary next plan import',
)
text = replace_once(
    text,
    '  final List<WorkoutSession> previousHistory;\n',
    '  final List<WorkoutSession> previousHistory;\n'
    '  final Set<String> skipProgressionExerciseIds;\n',
    'summary skip ids field',
)
text = replace_once(
    text,
    '    required this.session,\n    this.previousHistory = const [],\n  });',
    '    required this.session,\n'
    '    this.previousHistory = const [],\n'
    '    this.skipProgressionExerciseIds = const <String>{},\n'
    '  });',
    'summary constructor skip ids',
)
text = replace_once(
    text,
    '  bool _isSharing = false;\n',
    '  bool _isSharing = false;\n'
    '  bool _isApplyingNextPlan = false;\n'
    '  bool _nextPlanApplied = false;\n',
    'summary plan state',
)
insert_marker = '  Future<void> _openCoachDebrief(PostWorkoutDebrief debrief) async {'
if insert_marker not in text:
    raise SystemExit('missing summary coach method marker')
method = r'''  Future<void> _openNextSessionPlan() async {
    if (_isApplyingNextPlan || _nextPlanApplied) return;
    setState(() => _isApplyingNextPlan = true);
    try {
      final bundle = await AppDataStore.loadBundle();
      final plan = buildNextSessionPlan(
        session: widget.session,
        history: widget.previousHistory,
        schedules: bundle.schedules,
        skipSourceExerciseIds: widget.skipProgressionExerciseIds,
      );
      if (!mounted) return;
      if (plan == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Scheda originale non trovata: nessuna modifica applicata.'),
          ),
        );
        return;
      }
      if (!plan.hasActions) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Nessuna modifica alla scheda consigliata per la prossima seduta.'),
          ),
        );
        return;
      }

      final selected = await showModalBottomSheet<List<NextSessionPlanAction>>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) => _NextSessionPlanSheet(plan: plan),
      );
      if (!mounted || selected == null || selected.isEmpty) return;

      final latestBundle = await AppDataStore.loadBundle();
      final result = applyNextSessionPlan(
        schedules: latestBundle.schedules,
        actions: selected,
      );
      if (result.applied > 0) {
        await AppDataStore.saveSchedules(latestBundle.schedules);
      }
      if (!mounted) return;
      if (result.applied > 0) {
        setState(() => _nextPlanApplied = true);
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.skipped == 0
                ? '${result.applied} modifiche applicate alla scheda.'
                : '${result.applied} applicate, ${result.skipped} saltate perché la scheda era cambiata.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _isApplyingNextPlan = false);
    }
  }

'''
text = text.replace(insert_marker, method + insert_marker, 1)

old_bottom = r'''              SizedBox(
                width: double.infinity,
                child: FilledButton.tonalIcon(
                  key: const ValueKey('ask-coach-debrief'),
                  onPressed: () => _openCoachDebrief(debrief),
                  icon: const Icon(Icons.smart_toy_outlined),
                  label: const Text('Chiedi al Coach'),
                ),
              ),
              const SizedBox(height: 8),'''
new_bottom = r'''              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  key: const ValueKey('next-session-plan'),
                  onPressed: _isApplyingNextPlan || _nextPlanApplied
                      ? null
                      : _openNextSessionPlan,
                  icon: _isApplyingNextPlan
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(
                          _nextPlanApplied
                              ? Icons.check_circle_outline
                              : Icons.next_plan_outlined,
                        ),
                  label: Text(
                    _nextPlanApplied
                        ? 'Piano applicato'
                        : 'Piano prossima seduta',
                  ),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton.tonalIcon(
                  key: const ValueKey('ask-coach-debrief'),
                  onPressed: () => _openCoachDebrief(debrief),
                  icon: const Icon(Icons.smart_toy_outlined),
                  label: const Text('Chiedi al Coach'),
                ),
              ),
              const SizedBox(height: 8),'''
text = replace_once(text, old_bottom, new_bottom, 'summary next plan button')

marker = 'class _SummaryShareCard extends StatelessWidget {'
if marker not in text:
    raise SystemExit('missing summary share card marker')
sheet = r'''class _NextSessionPlanSheet extends StatefulWidget {
  final NextSessionPlan plan;

  const _NextSessionPlanSheet({required this.plan});

  @override
  State<_NextSessionPlanSheet> createState() => _NextSessionPlanSheetState();
}

class _NextSessionPlanSheetState extends State<_NextSessionPlanSheet> {
  late final Set<String> _selectedIds = widget.plan.actions
      .where((action) => action.defaultSelected)
      .map((action) => action.id)
      .toSet();

  String _changesLabel(NextSessionPlanAction action) {
    return action.changes
        .map(
          (change) =>
              '${change.label} ${change.currentLabel} → ${change.suggestedLabel}',
        )
        .join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final selected = widget.plan.actions
        .where((action) => _selectedIds.contains(action.id))
        .toList();

    return SafeArea(
      child: FractionallySizedBox(
        heightFactor: 0.88,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Piano prossima seduta',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'La scheda salvata non viene più modificata automaticamente. Controlla il diff e scegli cosa applicare; i suggerimenti derivano dallo stesso motore deterministico del Smart Debrief.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                itemCount: widget.plan.actions.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final action = widget.plan.actions[index];
                  final checked = _selectedIds.contains(action.id);
                  return Card(
                    margin: EdgeInsets.zero,
                    child: CheckboxListTile(
                      key: ValueKey('next-plan-action-${action.exerciseId}'),
                      value: checked,
                      onChanged: (value) {
                        setState(() {
                          if (value == true) {
                            _selectedIds.add(action.id);
                          } else {
                            _selectedIds.remove(action.id);
                          }
                        });
                      },
                      controlAffinity: ListTileControlAffinity.leading,
                      title: Row(
                        children: [
                          Expanded(
                            child: Text(
                              action.exerciseName,
                              style: const TextStyle(fontWeight: FontWeight.w900),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: scheme.secondaryContainer,
                              borderRadius: BorderRadius.circular(99),
                            ),
                            child: Text(
                              'Conf. ${action.confidenceLabel}',
                              style: theme.textTheme.labelSmall?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              action.actionLabel,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: scheme.primary,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _changesLabel(action),
                              key: ValueKey('next-plan-diff-${action.exerciseId}'),
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            if (action.decision.reasons.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(
                                action.decision.reasons.take(2).join(' '),
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Annulla'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: FilledButton.icon(
                      key: const ValueKey('apply-next-session-plan'),
                      onPressed: selected.isEmpty
                          ? null
                          : () => Navigator.pop(context, selected),
                      icon: const Icon(Icons.check),
                      label: Text(
                        selected.length == 1
                            ? 'Applica 1 modifica'
                            : 'Applica ${selected.length} modifiche',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

'''
text = text.replace(marker, sheet + marker, 1)
path.write_text(text)
