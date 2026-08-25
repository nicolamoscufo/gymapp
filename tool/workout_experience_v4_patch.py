from pathlib import Path
import re


def sub_once(text: str, pattern: str, replacement: str, label: str) -> str:
    updated, count = re.subn(pattern, replacement, text, count=1, flags=re.S)
    if count != 1:
        raise RuntimeError(f'{label}: expected 1 match, found {count}')
    return updated


path = Path('lib/screens/active_workout.dart')
text = path.read_text()

progression_ui = r'''  String _progressionConfidenceLabel(ProgressionConfidence confidence) {
    return switch (confidence) {
      ProgressionConfidence.low => 'bassa',
      ProgressionConfidence.medium => 'media',
      ProgressionConfidence.high => 'alta',
    };
  }

  ProgressionDecision _progressionDecisionFor(WorkoutExercise exercise) {
    return buildProgressionDecision(
      exercise: exercise,
      history: widget.history,
      excludeSessionId: session.id,
    );
  }

  String? _progressionHintFor(WorkoutExercise exercise) {
    if (exercise.progressionScheme == ProgressionScheme.manual) {
      return 'Progressione manuale: carico e reps non cambiano in automatico.';
    }

    final hasCompletedWorkSet = exercise.sets.any(
      (set) => set.isCompleted && !set.isWarmup,
    );
    if (!hasCompletedWorkSet) {
      if (exercise.previousWeights.isEmpty || exercise.previousReps.isEmpty) {
        return null;
      }
      return 'Progressione intelligente: completa i set e registra RIR/RPE per aggiornare la decisione.';
    }

    final decision = _progressionDecisionFor(exercise);
    return 'Prossima sessione: ${progressionActionLabel(decision)} · confidenza ${_progressionConfidenceLabel(decision.confidence)}';
  }

  Future<void> _showProgressionDecision(WorkoutExercise exercise) async {
    final decision = _progressionDecisionFor(exercise);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Progressione consigliata',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                exercise.name,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                progressionActionLabel(decision),
                style: theme.textTheme.headlineSmall?.copyWith(
                  color: colorScheme.primary,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Confidenza: ${_progressionConfidenceLabel(decision.confidence)}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (decision.effectiveRir != null)
                    Chip(
                      label: Text(
                        'RIR medio ${decision.effectiveRir!.toStringAsFixed(1)}',
                      ),
                    ),
                  if (decision.estimatedOneRepMaxChangePercent != null)
                    Chip(
                      label: Text(
                        'e1RM ${decision.estimatedOneRepMaxChangePercent! >= 0 ? '+' : ''}${decision.estimatedOneRepMaxChangePercent!.toStringAsFixed(1)}%',
                      ),
                    ),
                  if (decision.volumeChangePercent != null)
                    Chip(
                      label: Text(
                        'Volume ${decision.volumeChangePercent! >= 0 ? '+' : ''}${decision.volumeChangePercent!.toStringAsFixed(1)}%',
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              for (final reason in decision.reasons)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  leading: const Icon(Icons.check_circle_outline),
                  title: Text(reason),
                ),
              const SizedBox(height: 4),
              Text(
                'La decisione e deterministica: usa range reps, completamento set, RIR/RPE, e1RM e volume. Il Coach AI la spiega ma non la sostituisce.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  double _deloadWeight'''

text = sub_once(
    text,
    r"  String\? _progressionHintFor\(WorkoutExercise exercise\) \{.*?\n  \}\n\n  double _deloadWeight",
    progression_ui,
    'progression UI helpers',
)

progression_prefill = r'''  double _weightForSet(
    Exercise exercise,
    List<double> previousWeights,
    List<int> previousReps,
    ProgressionDecision? progressionDecision,
    int index,
  ) {
    if (previousWeights.isEmpty) {
      return exercise.weight;
    }

    final previousWeight = index < previousWeights.length
        ? previousWeights[index]
        : previousWeights.last;
    final previousRep = index < previousReps.length
        ? previousReps[index]
        : (previousReps.isEmpty ? exercise.reps : previousReps.last);

    if (exercise.progressionScheme == ProgressionScheme.manual ||
        exercise.progressionScheme == ProgressionScheme.repsOnly) {
      return previousWeight;
    }

    if (progressionDecision != null) {
      return switch (progressionDecision.action) {
        ProgressionAction.increaseLoad =>
          previousWeight + exercise.progressionKgStep,
        ProgressionAction.deload => _deloadWeight(previousWeight),
        ProgressionAction.increaseReps ||
        ProgressionAction.maintain ||
        ProgressionAction.manual => previousWeight,
      };
    }

    final minReps = exercise.targetMinReps;
    final maxReps = exercise.targetMaxReps;
    if (minReps == null || maxReps == null) {
      return previousWeight;
    }
    if (exercise.progressionScheme == ProgressionScheme.linear) {
      return previousWeight + exercise.progressionKgStep;
    }
    if (exercise.progressionScheme == ProgressionScheme.loadOnly) {
      return previousRep >= maxReps
          ? previousWeight + exercise.progressionKgStep
          : previousWeight;
    }
    if (previousRep >= maxReps) {
      return previousWeight + exercise.progressionKgStep;
    }
    if (previousRep < minReps) {
      return _deloadWeight(previousWeight);
    }
    return previousWeight;
  }

  int _repsForSet(
    Exercise exercise,
    List<int> previousReps,
    ProgressionDecision? progressionDecision,
    int index,
  ) {
    final minReps = exercise.targetMinReps;
    final maxReps = exercise.targetMaxReps;
    if (previousReps.isEmpty || minReps == null || maxReps == null) {
      return exercise.reps;
    }

    final previousRep = index < previousReps.length
        ? previousReps[index]
        : previousReps.last;

    if (exercise.progressionScheme == ProgressionScheme.manual) {
      return previousRep;
    }

    if (progressionDecision != null) {
      return switch (progressionDecision.action) {
        ProgressionAction.increaseReps => math.min(
          maxReps,
          previousRep + exercise.progressionRepStep,
        ),
        ProgressionAction.increaseLoad =>
          exercise.progressionScheme == ProgressionScheme.doubleProgression
              ? minReps
              : exercise.reps,
        ProgressionAction.deload => minReps,
        ProgressionAction.maintain => previousRep.clamp(minReps, maxReps),
        ProgressionAction.manual => previousRep,
      };
    }

    if (exercise.progressionScheme == ProgressionScheme.loadOnly ||
        exercise.progressionScheme == ProgressionScheme.linear) {
      return exercise.reps;
    }
    if (exercise.progressionScheme == ProgressionScheme.repsOnly) {
      return math.min(maxReps, previousRep + exercise.progressionRepStep);
    }
    if (previousRep >= maxReps) {
      return minReps;
    }
    return math.min(maxReps, previousRep + exercise.progressionRepStep);
  }

  List<ExerciseSet> _setsForExercise(
    Exercise exercise,
    List<double> previousWeights,
    List<int> previousReps,
    ProgressionDecision? progressionDecision,
  ) {
    final isBackoff =
        exercise.technique == IntensityTechnique.topsetBackoff &&
        exercise.backoffReps != null;

    if (isBackoff) {
      final topWeight = _weightForSet(
        exercise,
        previousWeights,
        previousReps,
        progressionDecision,
        0,
      );
      return [
        ExerciseSet(
          weight: topWeight,
          reps: _repsForSet(
            exercise,
            previousReps,
            progressionDecision,
            0,
          ),
        ),
        ExerciseSet(
          weight: top_set_backoff.recommendedBackoffWeight(
            topWeight,
            reductionPercent: exercise.backoffReductionPercent,
          ),
          reps: exercise.backoffReps!,
        ),
      ];
    }

    return List.generate(
      exercise.set,
      (index) => ExerciseSet(
        weight: _weightForSet(
          exercise,
          previousWeights,
          previousReps,
          progressionDecision,
          index,
        ),
        reps: _repsForSet(
          exercise,
          previousReps,
          progressionDecision,
          index,
        ),
      ),
    );
  }

  WorkoutExercise _workoutExerciseFromExercise('''

text = sub_once(
    text,
    r"  double _weightForSet\(.*?\n  WorkoutExercise _workoutExerciseFromExercise\(",
    progression_prefill,
    'progression-aware prefill',
)

old_previous = '''    final previousExercise = _previousExerciseFor(exercise, previousSession);\n    final previousWeights = _previousWeightsFor(previousExercise);\n    final previousReps = _previousRepsFor(previousExercise);\n'''
new_previous = '''    final previousExercise = _previousExerciseFor(exercise, previousSession);\n    final previousWeights = _previousWeightsFor(previousExercise);\n    final previousReps = _previousRepsFor(previousExercise);\n    final progressionDecision = previousExercise == null\n        ? null\n        : buildProgressionDecision(\n            exercise: previousExercise,\n            history: widget.history,\n            excludeSessionId: previousSession?.id,\n          );\n'''
if old_previous not in text:
    raise RuntimeError('previous exercise decision insertion: source not found')
text = text.replace(old_previous, new_previous, 1)

old_sets_call = '      sets: _setsForExercise(exercise, previousWeights, previousReps),'
new_sets_call = '''      sets: _setsForExercise(\n        exercise,\n        previousWeights,\n        previousReps,\n        progressionDecision,\n      ),'''
if old_sets_call not in text:
    raise RuntimeError('progression decision sets call: source not found')
text = text.replace(old_sets_call, new_sets_call, 1)

text = sub_once(
    text,
    r"  List<ExerciseSet> _workSets\(WorkoutExercise exercise\) \{.*?\n  Schedule\? _storedScheduleForSession",
    '  Schedule? _storedScheduleForSession',
    'remove legacy progression helpers',
)

apply_progression = r'''  Future<void> _applyProgressionToSchedule() async {
    final bundle = await AppDataStore.loadBundle();
    final storedSchedule = _storedScheduleForSession(bundle.schedules);
    if (storedSchedule == null) {
      return;
    }

    for (final completedExercise in session.exercises) {
      if (_exerciseIdsAddedToScheduleThisFinish.contains(
        completedExercise.sourceExerciseId,
      )) {
        continue;
      }

      Exercise? targetExercise;
      for (final exercise in storedSchedule.exercises) {
        final sameId =
            completedExercise.sourceExerciseId != null &&
            exercise.id == completedExercise.sourceExerciseId;
        final sameName =
            exercise.name.trim().toLowerCase() ==
            completedExercise.name.trim().toLowerCase();
        if (sameId || sameName) {
          targetExercise = exercise;
          break;
        }
      }
      if (targetExercise == null) {
        continue;
      }

      final decision = buildProgressionDecision(
        exercise: completedExercise,
        history: bundle.history,
        excludeSessionId: session.id,
      );

      switch (decision.action) {
        case ProgressionAction.manual:
        case ProgressionAction.maintain:
          break;
        case ProgressionAction.increaseLoad:
          targetExercise.weight += targetExercise.progressionKgStep;
          if (targetExercise.progressionScheme ==
                  ProgressionScheme.doubleProgression &&
              targetExercise.targetMinReps != null) {
            targetExercise.reps = targetExercise.targetMinReps!;
          }
        case ProgressionAction.increaseReps:
          final nextReps =
              targetExercise.reps + targetExercise.progressionRepStep;
          targetExercise.reps = targetExercise.targetMaxReps == null
              ? nextReps
              : math.min(targetExercise.targetMaxReps!, nextReps);
        case ProgressionAction.deload:
          targetExercise.weight = _deloadWeight(targetExercise.weight);
          if (targetExercise.targetMinReps != null) {
            targetExercise.reps = targetExercise.targetMinReps!;
          }
      }
    }

    await AppDataStore.saveSchedules(bundle.schedules);
  }

  @override
  void dispose'''

text = sub_once(
    text,
    r"  Future<void> _applyProgressionToSchedule\(\) async \{.*?\n  @override\n  void dispose",
    apply_progression,
    'deterministic schedule progression',
)

history_chip = '''                          ActionChip(\n                            key: ValueKey('exercise-history-${exercise.id}'),\n                            avatar: const Icon(Icons.history, size: 18),\n                            label: const Text('Storico'),\n                            visualDensity: VisualDensity.compact,\n                            onPressed: () => _showExerciseHistory(exercise),\n                          ),\n'''
progression_chip = history_chip + '''                          if (exercise.sets.any(\n                            (set) => set.isCompleted && !set.isWarmup,\n                          ))\n                            ActionChip(\n                              key: ValueKey(\n                                'progression-intelligence-${exercise.id}',\n                              ),\n                              avatar: const Icon(Icons.auto_graph, size: 18),\n                              label: Text(\n                                progressionActionLabel(\n                                  _progressionDecisionFor(exercise),\n                                ),\n                              ),\n                              visualDensity: VisualDensity.compact,\n                              onPressed: () =>\n                                  _showProgressionDecision(exercise),\n                            ),\n'''
if history_chip not in text:
    raise RuntimeError('progression intelligence chip: history chip not found')
text = text.replace(history_chip, progression_chip, 1)

path.write_text(text)
