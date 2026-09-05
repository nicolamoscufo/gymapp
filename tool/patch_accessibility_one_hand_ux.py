from pathlib import Path

# ---------------------------------------------------------------------------
# Stable workout inputs / jump bar
# ---------------------------------------------------------------------------
p = Path('lib/ui/active_workout_input_components.dart')
s = p.read_text()

s = s.replace(
    """    final colorScheme = Theme.of(context).colorScheme;\n    return Card(\n""",
    """    final colorScheme = Theme.of(context).colorScheme;\n    final largeText = MediaQuery.textScalerOf(context).scale(14) >= 21;\n    return Card(\n""",
    1,
)
s = s.replace(
    """      child: SizedBox(\n        height: 58,\n""",
    """      child: SizedBox(\n        height: largeText ? 82 : 58,\n""",
    1,
)
old = """            return ActionChip(\n              avatar: Icon(\n                Icons.keyboard_arrow_down,\n                color: colorScheme.primary,\n              ),\n              label: Text(exercise.name),\n              onPressed: () => onSelected(exercise.id),\n            );\n"""
new = """            return Semantics(\n              key: ValueKey('jump-semantics-${exercise.id}'),\n              button: true,\n              excludeSemantics: true,\n              label: 'Vai a ${exercise.name}',\n              onTap: () => onSelected(exercise.id),\n              child: ActionChip(\n                avatar: Icon(\n                  Icons.keyboard_arrow_down,\n                  color: colorScheme.primary,\n                ),\n                label: Text(exercise.name),\n                onPressed: () => onSelected(exercise.id),\n              ),\n            );\n"""
assert s.count(old) == 1
s = s.replace(old, new, 1)

s = s.replace(
    """  final bool selectAllOnFocus;\n\n  const StableWorkoutSetTextField({\n""",
    """  final bool selectAllOnFocus;\n  final String? semanticLabel;\n\n  const StableWorkoutSetTextField({\n""",
    1,
)
s = s.replace(
    """    this.onSubmitted,\n    this.selectAllOnFocus = false,\n  });\n""",
    """    this.onSubmitted,\n    this.selectAllOnFocus = false,\n    this.semanticLabel,\n  });\n""",
    1,
)
old = """  @override\n  Widget build(BuildContext context) {\n    return TextFormField(\n      controller: _controller,\n      focusNode: _focusNode,\n      keyboardType: widget.keyboardType,\n      inputFormatters: widget.inputFormatters,\n      textInputAction: widget.textInputAction,\n      textAlign: widget.textAlign,\n      decoration: widget.decoration,\n      onTap: widget.selectAllOnFocus ? _selectAll : null,\n      onChanged: widget.onChanged,\n      onFieldSubmitted: widget.onSubmitted,\n    );\n  }\n"""
new = """  @override\n  Widget build(BuildContext context) {\n    final field = TextFormField(\n      controller: _controller,\n      focusNode: _focusNode,\n      keyboardType: widget.keyboardType,\n      inputFormatters: widget.inputFormatters,\n      textInputAction: widget.textInputAction,\n      textAlign: widget.textAlign,\n      decoration: widget.decoration,\n      onTap: widget.selectAllOnFocus ? _selectAll : null,\n      onChanged: widget.onChanged,\n      onFieldSubmitted: widget.onSubmitted,\n    );\n    final label = widget.semanticLabel?.trim();\n    if (label == null || label.isEmpty) return field;\n    return Semantics(label: label, textField: true, child: field);\n  }\n"""
assert s.count(old) == 1
s = s.replace(old, new, 1)
p.write_text(s)

# ---------------------------------------------------------------------------
# Shared workout components
# ---------------------------------------------------------------------------
p = Path('lib/ui/workout_components.dart')
s = p.read_text()

start = s.index('class WorkoutCompactExerciseCard extends StatelessWidget {')
end = s.index('class WorkoutSetTableHeader extends StatelessWidget {', start)
compact = r'''class WorkoutCompactExerciseCard extends StatelessWidget {
  final String exerciseId;
  final String name;
  final int completedSets;
  final int totalSets;
  final String? nextPrescription;
  final bool isComplete;
  final Color accent;
  final VoidCallback onTap;

  const WorkoutCompactExerciseCard({
    super.key,
    required this.exerciseId,
    required this.name,
    required this.completedSets,
    required this.totalSets,
    required this.isComplete,
    required this.accent,
    required this.onTap,
    this.nextPrescription,
  });

  String get _status {
    if (isComplete) {
      return 'Completato · $completedSets/$totalSets set';
    }
    final next = nextPrescription?.trim();
    if (next == null || next.isEmpty) {
      return '$completedSets/$totalSets set';
    }
    return '$completedSets/$totalSets set · prossimo $next';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final largeText = MediaQuery.textScalerOf(context).scale(14) >= 21;

    return Card(
      key: ValueKey('compact-exercise-$exerciseId'),
      margin: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      child: InkWell(
        key: ValueKey('expand-exercise-$exerciseId'),
        borderRadius: BorderRadius.circular(AppRadii.card),
        excludeFromSemantics: true,
        onTap: onTap,
        child: Semantics(
          button: true,
          excludeSemantics: true,
          label: '$name. $_status. Tocca per aprire.',
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
            child: Row(
              children: [
                Container(
                  width: 4,
                  height: 38,
                  decoration: BoxDecoration(
                    color: isComplete ? colorScheme.tertiary : accent,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              name,
                              maxLines: largeText ? 2 : 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          if (isComplete)
                            Icon(
                              Icons.check_circle,
                              size: 18,
                              color: colorScheme.tertiary,
                            ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.xxs),
                      Text(
                        _status,
                        key: ValueKey('compact-progress-$exerciseId'),
                        maxLines: largeText ? 2 : 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Icon(
                  Icons.chevron_right,
                  size: 20,
                  color: colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

'''
s = s[:start] + compact + s[end:]
s = s.replace(
    """          const SizedBox(width: 40, child: Icon(Icons.check, size: 18)),\n""",
    """          const SizedBox(width: 48, child: Icon(Icons.check, size: 18)),\n""",
    1,
)

start = s.index('class WorkoutRestPanel extends StatelessWidget {')
rest = r'''class WorkoutRestPanel extends StatelessWidget {
  final String exerciseName;
  final String countdown;
  final double? progress;
  final String? nextSetId;
  final String? nextExerciseName;
  final String? nextSetLabel;
  final String? nextPrescription;
  final VoidCallback onMinusThirty;
  final VoidCallback onPlusThirty;
  final VoidCallback onSkip;

  const WorkoutRestPanel({
    super.key,
    required this.exerciseName,
    required this.countdown,
    required this.onMinusThirty,
    required this.onPlusThirty,
    required this.onSkip,
    this.progress,
    this.nextSetId,
    this.nextExerciseName,
    this.nextSetLabel,
    this.nextPrescription,
  });

  bool get _hasNextSet =>
      nextExerciseName != null && nextExerciseName!.trim().isNotEmpty;

  Widget _semanticButton({
    required String label,
    required VoidCallback onTap,
    required Widget child,
  }) {
    return Semantics(
      button: true,
      excludeSemantics: true,
      label: label,
      onTap: onTap,
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final largeText = MediaQuery.textScalerOf(context).scale(14) >= 21;

    final minusButton = _semanticButton(
      label: 'Riduci recupero di 30 secondi',
      onTap: onMinusThirty,
      child: OutlinedButton.icon(
        key: const ValueKey('rest-minus-30'),
        onPressed: onMinusThirty,
        icon: const Icon(Icons.remove),
        label: const Text('30 s'),
      ),
    );
    final plusButton = _semanticButton(
      label: 'Aumenta recupero di 30 secondi',
      onTap: onPlusThirty,
      child: OutlinedButton.icon(
        key: const ValueKey('rest-plus-30'),
        onPressed: onPlusThirty,
        icon: const Icon(Icons.add),
        label: const Text('30 s'),
      ),
    );
    final skipButton = _semanticButton(
      label: 'Salta il recupero',
      onTap: onSkip,
      child: FilledButton(
        key: const ValueKey('rest-skip'),
        onPressed: onSkip,
        child: const Text('Salta'),
      ),
    );

    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          0,
          AppSpacing.md,
          AppSpacing.sm,
        ),
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(AppRadii.prominent),
          border: Border.all(color: colorScheme.outlineVariant),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Semantics(
              liveRegion: true,
              excludeSemantics: true,
              label: 'Recupero: $countdown dopo $exerciseName',
              child: Row(
                children: [
                  Icon(
                    Icons.timer_outlined,
                    size: 24,
                    color: colorScheme.primary,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'RECUPERO',
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: colorScheme.primary,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.8,
                          ),
                        ),
                        Text(
                          countdown,
                          key: const ValueKey('rest-mode-countdown'),
                          style: theme.textTheme.headlineMedium?.copyWith(
                            fontWeight: FontWeight.w900,
                            height: 1,
                          ),
                        ),
                        Text(
                          'dopo $exerciseName',
                          maxLines: largeText ? 2 : 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (progress != null) ...[
              const SizedBox(height: AppSpacing.sm),
              LinearProgressIndicator(
                key: const ValueKey('rest-mode-progress'),
                value: progress!.clamp(0.0, 1.0).toDouble(),
                minHeight: 4,
                borderRadius: BorderRadius.circular(2),
              ),
            ],
            const SizedBox(height: AppSpacing.md),
            Semantics(
              excludeSemantics: true,
              label: _hasNextSet
                  ? 'Prossimo set: ${nextExerciseName!}, ${nextSetLabel ?? ''}${nextPrescription == null ? '' : ', $nextPrescription'}'
                  : 'Ultimo set completato. Recupera e poi termina l’allenamento.',
              child: Container(
                key: _hasNextSet && nextSetId != null
                    ? ValueKey('rest-next-set-$nextSetId')
                    : const ValueKey('rest-workout-complete'),
                width: double.infinity,
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: colorScheme.surface,
                  borderRadius: BorderRadius.circular(AppRadii.card),
                  border: Border.all(color: colorScheme.outlineVariant),
                ),
                child: _hasNextSet
                    ? largeText
                          ? Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'PROSSIMO SET',
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: colorScheme.primary,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                const SizedBox(height: AppSpacing.xxs),
                                Text(
                                  nextExerciseName!,
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                if (nextSetLabel != null) Text(nextSetLabel!),
                                if (nextPrescription != null) ...[
                                  const SizedBox(height: AppSpacing.xs),
                                  Text(
                                    nextPrescription!,
                                    key: const ValueKey(
                                      'rest-next-prescription',
                                    ),
                                    style: theme.textTheme.titleMedium?.copyWith(
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ],
                              ],
                            )
                          : Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'PROSSIMO SET',
                                        style: theme.textTheme.labelSmall
                                            ?.copyWith(
                                              color: colorScheme.primary,
                                              fontWeight: FontWeight.w900,
                                            ),
                                      ),
                                      const SizedBox(height: AppSpacing.xxs),
                                      Text(
                                        nextExerciseName!,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: theme.textTheme.titleSmall
                                            ?.copyWith(
                                              fontWeight: FontWeight.w800,
                                            ),
                                      ),
                                      if (nextSetLabel != null)
                                        Text(
                                          nextSetLabel!,
                                          style: theme.textTheme.bodySmall
                                              ?.copyWith(
                                                color: colorScheme
                                                    .onSurfaceVariant,
                                              ),
                                        ),
                                    ],
                                  ),
                                ),
                                if (nextPrescription != null) ...[
                                  const SizedBox(width: AppSpacing.sm),
                                  Text(
                                    nextPrescription!,
                                    key: const ValueKey(
                                      'rest-next-prescription',
                                    ),
                                    textAlign: TextAlign.right,
                                    style: theme.textTheme.titleMedium?.copyWith(
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ],
                              ],
                            )
                    : Row(
                        children: [
                          Icon(Icons.check_circle, color: colorScheme.tertiary),
                          const SizedBox(width: AppSpacing.sm),
                          const Expanded(
                            child: Text(
                              'Ultimo set completato · recupera e poi termina l’allenamento.',
                            ),
                          ),
                        ],
                      ),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            if (largeText)
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(height: 48, child: minusButton),
                  const SizedBox(height: AppSpacing.sm),
                  SizedBox(height: 48, child: plusButton),
                  const SizedBox(height: AppSpacing.sm),
                  SizedBox(height: 48, child: skipButton),
                ],
              )
            else
              Row(
                children: [
                  Expanded(child: minusButton),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(child: plusButton),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(child: skipButton),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
'''
s = s[:start] + rest + '\n'
p.write_text(s)

# ---------------------------------------------------------------------------
# Active workout screen
# ---------------------------------------------------------------------------
p = Path('lib/screens/active_workout.dart')
s = p.read_text()

s = s.replace(
    "import 'package:flutter/material.dart';\n",
    "import 'package:flutter/material.dart';\nimport 'package:flutter/semantics.dart';\n",
    1,
)
s = s.replace(
    """    final isDark = theme.brightness == Brightness.dark;\n    final compactInputBorder = OutlineInputBorder(\n""",
    """    final isDark = theme.brightness == Brightness.dark;\n    final largeText = MediaQuery.textScalerOf(context).scale(14) >= 21;\n    final compactInputBorder = OutlineInputBorder(\n""",
    1,
)

old = """              const SizedBox(width: 8),\n              _buildStatBadge(\n                icon: Icons.check_circle_outline,\n                value: '${stats.completedSets}/${stats.totalSets}',\n                colorScheme: colorScheme,\n              ),\n              const SizedBox(width: 6),\n              _buildStatBadge(\n                icon: Icons.timer,\n                value: _formatDuration(_elapsedSeconds),\n                colorScheme: colorScheme,\n              ),\n"""
new = """              if (!largeText) ...[\n                const SizedBox(width: 8),\n                _buildStatBadge(\n                  icon: Icons.check_circle_outline,\n                  value: '${stats.completedSets}/${stats.totalSets}',\n                  colorScheme: colorScheme,\n                ),\n                const SizedBox(width: 6),\n                _buildStatBadge(\n                  icon: Icons.timer,\n                  value: _formatDuration(_elapsedSeconds),\n                  colorScheme: colorScheme,\n                ),\n              ],\n"""
assert s.count(old) == 1
s = s.replace(old, new, 1)

old = """          bottom: PreferredSize(\n            preferredSize: const Size.fromHeight(22),\n"""
new = """          bottom: PreferredSize(\n            preferredSize: Size.fromHeight(largeText ? 44 : 22),\n"""
assert s.count(old) == 1
s = s.replace(old, new, 1)
old = """                child: Text(\n                  '${_saveStatusLabel()} · Readiness ${workoutReadiness.score}/100 ${workoutReadiness.status.label}',\n                  style: theme.textTheme.bodySmall?.copyWith(\n"""
new = """                child: Text(\n                  '${_saveStatusLabel()} · Readiness ${workoutReadiness.score}/100 ${workoutReadiness.status.label}',\n                  maxLines: largeText ? 2 : 1,\n                  overflow: TextOverflow.ellipsis,\n                  style: theme.textTheme.bodySmall?.copyWith(\n"""
assert s.count(old) == 1
s = s.replace(old, new, 1)

# Rest duration input gets an explicit screen-reader name.
s = s.replace(
    """                              selectAllOnFocus: true,\n                              onSubmitted: (_) =>\n                                  FocusScope.of(context).unfocus(),\n""",
    """                              selectAllOnFocus: true,\n                              semanticLabel:\n                                  'Recupero ${exercise.name} in secondi',\n                              onSubmitted: (_) =>\n                                  FocusScope.of(context).unfocus(),\n""",
    1,
)

# Set row: expose a non-gesture-only delete custom action.
start = s.index('                        return Dismissible(')
end_marker = '\n                        );\n                      }),' 
end = s.index(end_marker, start)
block = s[start:end + len('\n                        );')]
block = block.replace(
    '                        return Dismissible(',
    """                        return Semantics(\n                          key: ValueKey('set-semantics-${exSet.id}'),\n                          container: true,\n                          label: '${exercise.name}, set $displaySetLabel',\n                          customSemanticsActions: {\n                            CustomSemanticsAction(label: 'Elimina set'): () =>\n                                _removeSet(exercise, setIndex),\n                          },\n                          child: Dismissible(""",
    1,
)
assert block.endswith('\n                        );')
block = block[:-len('\n                        );')] + '\n                          ),\n                        );'
s = s[:start] + block + s[end + len('\n                        );'):]

# Weight and reps fields get explicit semantics.
needle = """                                          selectAllOnFocus: true,\n                                          textAlign: TextAlign.center,\n                                          decoration: InputDecoration(\n"""
replacement = """                                          selectAllOnFocus: true,\n                                          semanticLabel:\n                                              '${exercise.name}, set $displaySetLabel, carico in kg',\n                                          textAlign: TextAlign.center,\n                                          decoration: InputDecoration(\n"""
assert s.count(needle) >= 2
s = s.replace(needle, replacement, 1)
# Reps field has onSubmitted between selectAll and textAlign.
needle = """                                          selectAllOnFocus: true,\n                                          onSubmitted: (value) =>\n                                              _submitSetFromKeyboard(\n"""
replacement = """                                          selectAllOnFocus: true,\n                                          semanticLabel:\n                                              '${exercise.name}, set $displaySetLabel, ripetizioni',\n                                          onSubmitted: (value) =>\n                                              _submitSetFromKeyboard(\n"""
assert s.count(needle) == 1
s = s.replace(needle, replacement, 1)

old = """                                    InkWell(\n                                      key: ValueKey('complete-${exSet.id}'),\n                                      onTap: () => _toggleSetCompleted(\n                                        exercise,\n                                        exSet,\n                                        setIndex,\n                                      ),\n                                      child: Container(\n                                        width: 40,\n                                        height: 36,\n                                        decoration: BoxDecoration(\n                                          color: exSet.isCompleted\n                                              ? colorScheme.tertiary\n                                              : colorScheme\n                                                    .surfaceContainerHighest,\n                                          borderRadius: BorderRadius.circular(\n                                            8,\n                                          ),\n                                        ),\n                                        child: Icon(\n                                          Icons.check,\n                                          color: exSet.isCompleted\n                                              ? colorScheme.onTertiary\n                                              : colorScheme.onSurfaceVariant,\n                                        ),\n                                      ),\n                                    ),\n"""
new = """                                    Semantics(\n                                      button: true,\n                                      checked: exSet.isCompleted,\n                                      excludeSemantics: true,\n                                      label:\n                                          '${exercise.name}, set $displaySetLabel: ${exSet.isCompleted ? 'set completato' : 'completa set'}',\n                                      onTap: () => _toggleSetCompleted(\n                                        exercise,\n                                        exSet,\n                                        setIndex,\n                                      ),\n                                      child: InkWell(\n                                        key: ValueKey('complete-${exSet.id}'),\n                                        excludeFromSemantics: true,\n                                        onTap: () => _toggleSetCompleted(\n                                          exercise,\n                                          exSet,\n                                          setIndex,\n                                        ),\n                                        borderRadius: BorderRadius.circular(8),\n                                        child: Container(\n                                          width: 48,\n                                          height: 48,\n                                          decoration: BoxDecoration(\n                                            color: exSet.isCompleted\n                                                ? colorScheme.tertiary\n                                                : colorScheme\n                                                      .surfaceContainerHighest,\n                                            borderRadius: BorderRadius.circular(\n                                              8,\n                                            ),\n                                          ),\n                                          child: Icon(\n                                            Icons.check,\n                                            color: exSet.isCompleted\n                                                ? colorScheme.onTertiary\n                                                : colorScheme.onSurfaceVariant,\n                                          ),\n                                        ),\n                                      ),\n                                    ),\n"""
assert s.count(old) == 1
s = s.replace(old, new, 1)
p.write_text(s)
