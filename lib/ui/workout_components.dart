import 'package:flutter/material.dart';

/// Shared spacing primitives for workout-focused screens.
///
/// Keep these intentionally small: the app is used while training and should
/// favour information density over decorative whitespace.
abstract final class AppSpacing {
  static const double xxs = 2;
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
}

abstract final class AppRadii {
  static const double control = 8;
  static const double card = 12;
  static const double prominent = 16;
}

class WorkoutSectionHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? trailing;

  const WorkoutSectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (subtitle != null && subtitle!.trim().isNotEmpty) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(
                  subtitle!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (trailing != null) ...[
          const SizedBox(width: AppSpacing.sm),
          trailing!,
        ],
      ],
    );
  }
}

class WorkoutMetricTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final String? helper;

  const WorkoutMetricTile({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    this.helper,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppRadii.card),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          children: [
            Icon(icon, size: 20, color: colorScheme.primary),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  if (helper != null && helper!.trim().isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      helper!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Collapsed representation of a workout exercise.
///
/// This widget contains no workout logic: the parent computes progress and the
/// next prescription and only supplies display values plus [onTap].
class WorkoutCompactExerciseCard extends StatelessWidget {
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

class WorkoutSetTableHeader extends StatelessWidget {
  const WorkoutSetTableHeader({super.key});

  @override
  Widget build(BuildContext context) {
    final textStyle = Theme.of(
      context,
    ).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w800);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        children: [
          SizedBox(width: 72, child: Text('#', style: textStyle)),
          Expanded(
            child: Center(child: Text('kg', style: textStyle)),
          ),
          Expanded(
            child: Center(child: Text('reps', style: textStyle)),
          ),
          const SizedBox(width: 48, child: Icon(Icons.check, size: 18)),
          const SizedBox(width: 48),
        ],
      ),
    );
  }
}

class WorkoutRestPanel extends StatelessWidget {
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
                                    style: theme.textTheme.titleMedium
                                        ?.copyWith(fontWeight: FontWeight.w900),
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
                                    style: theme.textTheme.titleMedium
                                        ?.copyWith(fontWeight: FontWeight.w900),
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
