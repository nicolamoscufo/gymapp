import 'package:flutter/material.dart';

import '../ai_coach/ai_action_protocol.dart';
import '../models/schedule.dart';

class AiProgramDraftReviewScreen extends StatefulWidget {
  final AiProgramActionProposal proposal;
  final List<Schedule> currentSchedules;
  final AiActionProtocolService actionProtocolService;

  const AiProgramDraftReviewScreen({
    super.key,
    required this.proposal,
    required this.currentSchedules,
    this.actionProtocolService = const AiActionProtocolService(),
  });

  @override
  State<AiProgramDraftReviewScreen> createState() =>
      _AiProgramDraftReviewScreenState();
}

class _AiProgramDraftReviewScreenState
    extends State<AiProgramDraftReviewScreen> {
  late AiProgramActionProposal _draft;
  List<String> _validationErrors = const [];

  @override
  void initState() {
    super.initState();
    _draft = widget.proposal.copyWith(
      schedules: widget.proposal.schedules
          .map(
            (schedule) => schedule.copyWith(
              trainingWeekdays: [...schedule.trainingWeekdays],
              exercises: [...schedule.exercises],
            ),
          )
          .toList(),
    );
  }

  void _replaceSchedule(int index, AiProgramScheduleDraft value) {
    final schedules = [..._draft.schedules];
    schedules[index] = value;
    setState(() {
      _draft = _draft.copyWith(schedules: schedules);
      _validationErrors = const [];
    });
  }

  void _replaceExercise(
    int scheduleIndex,
    int exerciseIndex,
    AiProgramDraftExercise value,
  ) {
    final schedule = _draft.schedules[scheduleIndex];
    final exercises = [...schedule.exercises];
    exercises[exerciseIndex] = value;
    _replaceSchedule(scheduleIndex, schedule.copyWith(exercises: exercises));
  }

  void _removeExercise(int scheduleIndex, int exerciseIndex) {
    final schedule = _draft.schedules[scheduleIndex];
    final exercises = [...schedule.exercises]..removeAt(exerciseIndex);
    _replaceSchedule(scheduleIndex, schedule.copyWith(exercises: exercises));
  }

  void _toggleWeekday(int scheduleIndex, int weekday) {
    final schedule = _draft.schedules[scheduleIndex];
    final days = schedule.trainingWeekdays.toSet();
    if (!days.add(weekday)) days.remove(weekday);
    final sorted = days.toList()..sort();
    _replaceSchedule(
      scheduleIndex,
      schedule.copyWith(trainingWeekdays: sorted),
    );
  }

  void _finishEditing() {
    final validation = widget.actionProtocolService.validate(
      _draft,
      widget.currentSchedules,
    );
    if (!validation.isValid) {
      setState(() => _validationErrors = validation.errors);
      return;
    }
    Navigator.pop(context, _draft);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Rivedi proposta AI'),
        actions: [
          TextButton(
            key: const ValueKey('ai-program-draft-done'),
            onPressed: _finishEditing,
            child: const Text('Fine'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.auto_awesome, color: colorScheme.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _draft.summary,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(_draft.rationale),
                  const SizedBox(height: 8),
                  Text(
                    'Bozza locale · nessuna modifica viene salvata finché non confermi dalla chat.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_validationErrors.isNotEmpty) ...[
            const SizedBox(height: 12),
            Card(
              color: colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Correggi la bozza prima di continuare',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: colorScheme.onErrorContainer,
                      ),
                    ),
                    const SizedBox(height: 6),
                    ..._validationErrors.take(6).map(
                      (error) => Text(
                        '• ${_friendlyValidationError(error)}',
                        style: TextStyle(color: colorScheme.onErrorContainer),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 12),
          ...List.generate(
            _draft.schedules.length,
            (index) => _ScheduleDraftEditor(
              key: ValueKey(
                'ai-program-schedule-${_draft.schedules[index].draftKey}',
              ),
              index: index,
              schedule: _draft.schedules[index],
              onChanged: (value) => _replaceSchedule(index, value),
              onExerciseChanged: (exerciseIndex, value) =>
                  _replaceExercise(index, exerciseIndex, value),
              onRemoveExercise: (exerciseIndex) =>
                  _removeExercise(index, exerciseIndex),
              onToggleWeekday: (weekday) => _toggleWeekday(index, weekday),
            ),
          ),
        ],
      ),
    );
  }
}

class _ScheduleDraftEditor extends StatelessWidget {
  final int index;
  final AiProgramScheduleDraft schedule;
  final ValueChanged<AiProgramScheduleDraft> onChanged;
  final void Function(int, AiProgramDraftExercise) onExerciseChanged;
  final ValueChanged<int> onRemoveExercise;
  final ValueChanged<int> onToggleWeekday;

  const _ScheduleDraftEditor({
    super.key,
    required this.index,
    required this.schedule,
    required this.onChanged,
    required this.onExerciseChanged,
    required this.onRemoveExercise,
    required this.onToggleWeekday,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Seduta ${index + 1}',
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 10),
            TextFormField(
              key: ValueKey('ai-draft-title-${schedule.draftKey}'),
              initialValue: schedule.title,
              decoration: const InputDecoration(labelText: 'Nome seduta'),
              onChanged: (value) => onChanged(schedule.copyWith(title: value)),
            ),
            const SizedBox(height: 10),
            TextFormField(
              key: ValueKey('ai-draft-goal-${schedule.draftKey}'),
              initialValue: schedule.goal,
              decoration: const InputDecoration(labelText: 'Obiettivo'),
              onChanged: (value) => onChanged(schedule.copyWith(goal: value)),
            ),
            const SizedBox(height: 12),
            Text('Giorni', style: theme.textTheme.labelLarge),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: List.generate(7, (dayIndex) {
                final weekday = dayIndex + 1;
                return FilterChip(
                  key: ValueKey(
                    'ai-draft-day-${schedule.draftKey}-$weekday',
                  ),
                  label: Text(_weekdayLabel(weekday)),
                  selected: schedule.trainingWeekdays.contains(weekday),
                  onSelected: (_) => onToggleWeekday(weekday),
                );
              }),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Esercizi',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Text('${schedule.exercises.length}'),
              ],
            ),
            const SizedBox(height: 8),
            ...List.generate(
              schedule.exercises.length,
              (exerciseIndex) => _ExerciseDraftEditor(
                key: ValueKey(
                  'ai-draft-exercise-${schedule.draftKey}-$exerciseIndex',
                ),
                exercise: schedule.exercises[exerciseIndex],
                onChanged: (value) =>
                    onExerciseChanged(exerciseIndex, value),
                onRemove: () => onRemoveExercise(exerciseIndex),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ExerciseDraftEditor extends StatelessWidget {
  final AiProgramDraftExercise exercise;
  final ValueChanged<AiProgramDraftExercise> onChanged;
  final VoidCallback onRemove;

  const _ExerciseDraftEditor({
    super.key,
    required this.exercise,
    required this.onChanged,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  initialValue: exercise.name,
                  decoration: const InputDecoration(labelText: 'Esercizio'),
                  onChanged: (value) =>
                      onChanged(exercise.copyWith(name: value)),
                ),
              ),
              IconButton(
                tooltip: 'Rimuovi esercizio',
                onPressed: onRemove,
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _NumericDraftField(
                  label: 'Serie',
                  initialValue: exercise.sets.toString(),
                  onChanged: (value) {
                    final parsed = int.tryParse(value);
                    if (parsed != null) {
                      onChanged(exercise.copyWith(sets: parsed));
                    }
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _NumericDraftField(
                  label: 'Reps',
                  initialValue: exercise.reps.toString(),
                  onChanged: (value) {
                    final parsed = int.tryParse(value);
                    if (parsed != null) {
                      onChanged(exercise.copyWith(reps: parsed));
                    }
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _NumericDraftField(
                  label: 'Kg',
                  decimal: true,
                  initialValue: _formatDouble(exercise.weight),
                  onChanged: (value) {
                    final parsed = double.tryParse(value.replaceAll(',', '.'));
                    if (parsed != null) {
                      onChanged(exercise.copyWith(weight: parsed));
                    }
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _NumericDraftField(
                  label: 'Recupero sec',
                  initialValue: exercise.restSeconds?.toString() ?? '',
                  onChanged: (value) {
                    if (value.trim().isEmpty) {
                      onChanged(exercise.copyWith(clearRestSeconds: true));
                      return;
                    }
                    final parsed = int.tryParse(value);
                    if (parsed != null) {
                      onChanged(exercise.copyWith(restSeconds: parsed));
                    }
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: TextFormField(
                  initialValue: exercise.notes,
                  decoration: const InputDecoration(labelText: 'Note'),
                  onChanged: (value) =>
                      onChanged(exercise.copyWith(notes: value)),
                ),
              ),
            ],
          ),
          if (exercise.sourceExerciseId.isNotEmpty) ...[
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Esercizio esistente · ID preservato',
                style: theme.textTheme.bodySmall,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _NumericDraftField extends StatelessWidget {
  final String label;
  final String initialValue;
  final bool decimal;
  final ValueChanged<String> onChanged;

  const _NumericDraftField({
    required this.label,
    required this.initialValue,
    required this.onChanged,
    this.decimal = false,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      initialValue: initialValue,
      decoration: InputDecoration(labelText: label),
      keyboardType: TextInputType.numberWithOptions(decimal: decimal),
      onChanged: onChanged,
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

String _friendlyValidationError(String error) {
  final code = error.split(':').last;
  return switch (code) {
    'invalid_title' => 'Inserisci un nome valido per la seduta.',
    'invalid_exercise_count' => 'Ogni seduta deve avere almeno un esercizio.',
    'invalid_name' => 'Inserisci un nome valido per ogni esercizio.',
    'invalid_sets' => 'Le serie devono essere tra 1 e 20.',
    'invalid_reps' => 'Le ripetizioni devono essere tra 1 e 100.',
    'invalid_weight' => 'Il carico non è valido.',
    'invalid_rest_seconds' => 'Il recupero deve essere tra 0 e 900 secondi.',
    'stale_base_version' => 'La scheda originale è cambiata: rigenera la proposta.',
    _ => error,
  };
}
