import 'package:flutter/material.dart';

import '../ai_coach/ai_action_protocol.dart';

class AiProgramDraftCard extends StatelessWidget {
  final AiProgramActionProposal proposal;
  final VoidCallback onEdit;
  final VoidCallback onSave;
  final bool isSaving;

  const AiProgramDraftCard({
    super.key,
    required this.proposal,
    required this.onEdit,
    required this.onSave,
    this.isSaving = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final actionLabel = proposal.kind == AiProgramActionKind.proposeProgram
        ? 'Nuova programmazione'
        : 'Modifica programmazione';

    return Card(
      key: const ValueKey('ai-program-draft-card'),
      margin: const EdgeInsets.only(top: 8),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.auto_awesome, color: colorScheme.primary, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        actionLabel,
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: colorScheme.primary,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        proposal.summary,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
                _ConfidenceBadge(confidence: proposal.confidence),
              ],
            ),
            if (proposal.rationale.trim().isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                proposal.rationale,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: 12),
            ...proposal.schedules.map(
              (schedule) => _SchedulePreview(schedule: schedule),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    key: const ValueKey('edit-ai-program-draft'),
                    onPressed: isSaving ? null : onEdit,
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('Modifica'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.icon(
                    key: const ValueKey('save-ai-program-draft'),
                    onPressed: isSaving ? null : onSave,
                    icon: isSaving
                        ? const SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.save_outlined),
                    label: Text(isSaving ? 'Salvataggio…' : 'Salva'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(
                  Icons.verified_user_outlined,
                  size: 14,
                  color: colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    'È una bozza: nessun dato viene modificato senza Salva.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
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

class _SchedulePreview extends StatelessWidget {
  final AiProgramScheduleDraft schedule;

  const _SchedulePreview({required this.schedule});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final days = schedule.trainingWeekdays.isEmpty
        ? 'Giorno da definire'
        : schedule.trainingWeekdays.map(_weekdayLabel).join(' · ');

    return Container(
      key: ValueKey('ai-program-preview-${schedule.draftKey}'),
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  schedule.title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Text(
                days,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          if (schedule.goal.trim().isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              schedule.goal,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: 8),
          ...schedule.exercises.take(8).map(
            (exercise) => Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      exercise.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${exercise.sets} × ${exercise.targetMinReps != null && exercise.targetMaxReps != null ? '${exercise.targetMinReps}-${exercise.targetMaxReps}' : exercise.reps}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (exercise.weight > 0) ...[
                    const SizedBox(width: 8),
                    Text(
                      '${_formatDouble(exercise.weight)} kg',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (schedule.exercises.length > 8)
            Text(
              '+${schedule.exercises.length - 8} esercizi',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
        ],
      ),
    );
  }
}

class _ConfidenceBadge extends StatelessWidget {
  final String confidence;

  const _ConfidenceBadge({required this.confidence});

  @override
  Widget build(BuildContext context) {
    final label = switch (confidence) {
      'high' => 'Alta',
      'medium' => 'Media',
      _ => 'Bassa',
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(label, style: Theme.of(context).textTheme.labelSmall),
    );
  }
}

String _weekdayLabel(int weekday) => switch (weekday) {
  DateTime.monday => 'Lun',
  DateTime.tuesday => 'Mar',
  DateTime.wednesday => 'Mer',
  DateTime.thursday => 'Gio',
  DateTime.friday => 'Ven',
  DateTime.saturday => 'Sab',
  DateTime.sunday => 'Dom',
  _ => '?',
};

String _formatDouble(double value) {
  if (value == value.roundToDouble()) return value.toStringAsFixed(0);
  return value
      .toStringAsFixed(2)
      .replaceFirst(RegExp(r'0+$'), '')
      .replaceFirst(RegExp(r'\.$'), '');
}
