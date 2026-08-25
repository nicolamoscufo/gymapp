from pathlib import Path


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f'{label}: expected 1 match, found {count}')
    return text.replace(old, new, 1)


active_path = Path('lib/screens/active_workout.dart')
active = active_path.read_text()

active = replace_once(
    active,
    "import '../workout_plate_calculator.dart';\n",
    "import '../workout_plate_calculator.dart';\nimport '../workout_progression_analytics.dart';\n",
    'active workout analytics import',
)

old_pr = """    final bestSetVolume = _bestHistoricalSetVolumeFor(exercise);
    if (bestSetVolume != null && _setVolume(set) > bestSetVolume) {
      labels.add('PR set');
    }

    final bestExerciseVolume = _bestHistoricalExerciseVolumeFor(exercise);
"""
new_pr = """    final bestSetVolume = _bestHistoricalSetVolumeFor(exercise);
    if (bestSetVolume != null && _setVolume(set) > bestSetVolume) {
      labels.add('PR set');
    }

    final setEstimatedOneRepMax = estimateOneRepMax(set.weight, set.reps);
    final historicalEstimatedOneRepMax = historicalBestEstimatedOneRepMax(
      history: widget.history,
      exerciseName: exercise.name,
      excludeSessionId: session.id,
    );
    if (setEstimatedOneRepMax != null &&
        historicalEstimatedOneRepMax != null &&
        setEstimatedOneRepMax > historicalEstimatedOneRepMax + 0.05) {
      labels.add('PR e1RM');
    }

    final bestExerciseVolume = _bestHistoricalExerciseVolumeFor(exercise);
"""
active = replace_once(active, old_pr, new_pr, 'e1RM personal record')

old_warmup = """  List<ExerciseSet> _warmupSetsFor(WorkoutExercise exercise) {
    final workWeight = exercise.sets.isEmpty ? 0.0 : exercise.sets.first.weight;
    final workReps = exercise.sets.isEmpty ? 8 : exercise.sets.first.reps;
    return [
      ExerciseSet(
        weight: (workWeight * 0.40 * 2).roundToDouble() / 2,
        reps: math.max(5, workReps + 2),
        isWarmup: true,
      ),
      ExerciseSet(
        weight: (workWeight * 0.60 * 2).roundToDouble() / 2,
        reps: math.max(3, workReps),
        isWarmup: true,
      ),
      ExerciseSet(
        weight: (workWeight * 0.75 * 2).roundToDouble() / 2,
        reps: math.max(2, workReps - 2),
        isWarmup: true,
      ),
      ExerciseSet(
        weight: (workWeight * 0.85 * 2).roundToDouble() / 2,
        reps: 2,
        isWarmup: true,
      ),
    ];
  }
"""
new_history_and_warmup = """  Future<void> _showExerciseHistory(WorkoutExercise exercise) async {
    final snapshots = buildExercisePerformanceHistory(
      history: widget.history,
      exerciseName: exercise.name,
      excludeSessionId: session.id,
    );
    double? bestEstimatedOneRepMax;
    for (final snapshot in snapshots) {
      final value = snapshot.estimatedOneRepMax;
      if (value != null &&
          (bestEstimatedOneRepMax == null || value > bestEstimatedOneRepMax)) {
        bestEstimatedOneRepMax = value;
      }
    }
    final trend = latestEstimatedOneRepMaxTrendPercent(snapshots);
    final latestFirst = snapshots.reversed.toList();

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        final theme = Theme.of(context);
        final colorScheme = theme.colorScheme;
        return SafeArea(
          child: FractionallySizedBox(
            heightFactor: 0.72,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Storico ${exercise.name}',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Set di lavoro completati. e1RM stimato con Epley fino a 12 reps.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (snapshots.isEmpty)
                    const Expanded(
                      child: Center(
                        child: Text('Nessuna sessione precedente disponibile.'),
                      ),
                    )
                  else ...[
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        if (bestEstimatedOneRepMax != null)
                          Chip(
                            avatar: const Icon(Icons.fitness_center, size: 18),
                            label: Text(
                              'Best e1RM ${_formatWeight(bestEstimatedOneRepMax)} kg',
                            ),
                          ),
                        if (trend != null)
                          Chip(
                            avatar: Icon(
                              trend >= 0
                                  ? Icons.trending_up
                                  : Icons.trending_down,
                              size: 18,
                            ),
                            label: Text(
                              'Trend ${trend >= 0 ? '+' : ''}${trend.toStringAsFixed(1)}%',
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: ListView.separated(
                        itemCount: latestFirst.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final snapshot = latestFirst[index];
                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: CircleAvatar(
                              child: Text(
                                '${snapshot.date.day}/${snapshot.date.month}',
                                style: theme.textTheme.labelSmall,
                              ),
                            ),
                            title: Text(
                              '${_formatWeight(snapshot.topSetWeight)} kg × ${snapshot.topSetReps}',
                              style: const TextStyle(fontWeight: FontWeight.w800),
                            ),
                            subtitle: Text(
                              'Volume ${_formatVolume(snapshot.totalVolume)} kg · best set ${_formatVolume(snapshot.bestSetVolume)} kg',
                            ),
                            trailing: snapshot.estimatedOneRepMax == null
                                ? null
                                : Text(
                                    'e1RM\n${_formatWeight(snapshot.estimatedOneRepMax!)} kg',
                                    textAlign: TextAlign.right,
                                    style: TextStyle(
                                      color: colorScheme.primary,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                          );
                        },
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  List<ExerciseSet> _warmupSetsFor(WorkoutExercise exercise) {
    ExerciseSet? workSet;
    for (final set in exercise.sets) {
      if (!set.isWarmup) {
        workSet = set;
        break;
      }
    }
    if (workSet == null) {
      return const <ExerciseSet>[];
    }

    return buildAdaptiveWarmupPlan(
      workWeight: workSet.weight,
      workReps: workSet.reps,
    )
        .map(
          (suggestion) => ExerciseSet(
            weight: suggestion.weight,
            reps: suggestion.reps,
            isWarmup: true,
          ),
        )
        .toList();
  }
"""
active = replace_once(
    active,
    old_warmup,
    new_history_and_warmup,
    'exercise history and adaptive warmup',
)

old_show_warmup = """  void _showWarmupPlan(WorkoutExercise exercise) {
    final warmups = _warmupSetsFor(exercise);
    final rows = warmups
"""
new_show_warmup = """  void _showWarmupPlan(WorkoutExercise exercise) {
    final warmups = _warmupSetsFor(exercise);
    if (warmups.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Imposta prima un carico di lavoro per calcolare il warm-up.'),
        ),
      );
      return;
    }
    final rows = warmups
"""
active = replace_once(
    active,
    old_show_warmup,
    new_show_warmup,
    'warmup empty-state',
)

old_warmup_title = """        title: Text('Warm-up ${exercise.name}'),
"""
new_warmup_title = """        title: Text('Warm-up smart ${exercise.name}'),
"""
active = replace_once(
    active,
    old_warmup_title,
    new_warmup_title,
    'warmup dialog title',
)

old_item_vars = """            final activeRestSeconds = _restSecondsByExerciseId[exercise.id];
            final restSeconds = activeRestSeconds ?? _restSecondsFor(exercise);
            final accent = _accentForIndex(colorScheme, exIndex);

            return Card(
"""
new_item_vars = """            final activeRestSeconds = _restSecondsByExerciseId[exercise.id];
            final restSeconds = activeRestSeconds ?? _restSecondsFor(exercise);
            final accent = _accentForIndex(colorScheme, exIndex);
            final currentEstimatedOneRepMax = bestEstimatedOneRepMaxForSets(
              exercise.sets.where(
                (set) => set.isCompleted && !set.isWarmup,
              ),
            );
            final historicalEstimatedOneRepMax = historicalBestEstimatedOneRepMax(
              history: widget.history,
              exerciseName: exercise.name,
              excludeSessionId: session.id,
            );

            return Card(
"""
active = replace_once(active, old_item_vars, new_item_vars, 'exercise insight vars')

old_progression_block = """                      if (_progressionHintFor(exercise) != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          _progressionHintFor(exercise)!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.tertiary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                      const SizedBox(height: 8),
                      Row(
"""
new_progression_block = """                      if (_progressionHintFor(exercise) != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          _progressionHintFor(exercise)!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.tertiary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          ActionChip(
                            key: ValueKey('exercise-history-${exercise.id}'),
                            avatar: const Icon(Icons.history, size: 18),
                            label: const Text('Storico'),
                            visualDensity: VisualDensity.compact,
                            onPressed: () => _showExerciseHistory(exercise),
                          ),
                          if (historicalEstimatedOneRepMax != null)
                            Chip(
                              avatar: const Icon(Icons.workspace_premium, size: 18),
                              label: Text(
                                'Best e1RM ${_formatWeight(historicalEstimatedOneRepMax)} kg',
                              ),
                              visualDensity: VisualDensity.compact,
                            ),
                          if (currentEstimatedOneRepMax != null)
                            Chip(
                              avatar: const Icon(Icons.bolt, size: 18),
                              label: Text(
                                'Oggi e1RM ${_formatWeight(currentEstimatedOneRepMax)} kg',
                              ),
                              visualDensity: VisualDensity.compact,
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
"""
active = replace_once(
    active,
    old_progression_block,
    new_progression_block,
    'exercise insights row',
)

active_path.write_text(active)

context_path = Path('lib/ai_coach/training_context_builder.dart')
context = context_path.read_text()
context = replace_once(
    context,
    "import '../models/workout.dart';\n",
    "import '../models/workout.dart';\nimport '../workout_progression_analytics.dart';\n",
    'training context analytics import',
)

old_progress = """        final bestWeight = workingSets.map((set) => set.weight).reduce((a, b) => a > b ? a : b);
        final totalReps = workingSets.fold<int>(0, (sum, set) => sum + set.reps);
        result.putIfAbsent(exercise.name, () => []).add({
          'date': session.startTime.toIso8601String(),
          'best_weight': bestWeight,
          'total_reps': totalReps,
        });
"""
new_progress = """        final bestWeight = workingSets.map((set) => set.weight).reduce((a, b) => a > b ? a : b);
        final totalReps = workingSets.fold<int>(0, (sum, set) => sum + set.reps);
        final volume = workingSets.fold<double>(
          0,
          (sum, set) => sum + set.weight * set.reps,
        );
        final estimatedOneRepMax = bestEstimatedOneRepMaxForSets(workingSets);
        result.putIfAbsent(exercise.name, () => []).add({
          'date': session.startTime.toIso8601String(),
          'best_weight': bestWeight,
          'total_reps': totalReps,
          'volume': volume,
          'estimated_1rm': estimatedOneRepMax,
        });
"""
context = replace_once(
    context,
    old_progress,
    new_progress,
    'AI exercise progress analytics',
)
context_path.write_text(context)
