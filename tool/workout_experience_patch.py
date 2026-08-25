from pathlib import Path

path = Path('lib/screens/active_workout.dart')
text = path.read_text()


def replace_once(old: str, new: str, label: str) -> None:
    global text
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f'{label}: expected 1 match, found {count}')
    text = text.replace(old, new, 1)


replace_once(
    "import '../top_set_backoff.dart' as top_set_backoff;\n",
    "import '../top_set_backoff.dart' as top_set_backoff;\nimport '../workout_plate_calculator.dart';\n",
    'plate calculator import',
)

previous_block = """  String? _previousSetLabelFor(WorkoutExercise exercise, int setIndex) {
    if (setIndex >= exercise.previousWeights.length ||
        setIndex >= exercise.previousReps.length) {
      return null;
    }

    return 'Ultima: ${_formatWeight(exercise.previousWeights[setIndex])} kg x ${exercise.previousReps[setIndex]}';
  }
"""
helpers = previous_block + """
  void _applyPreviousSetValues(WorkoutExercise exercise, int setIndex) {
    if (setIndex >= exercise.previousWeights.length ||
        setIndex >= exercise.previousReps.length ||
        setIndex >= exercise.sets.length) {
      return;
    }
    setState(() {
      exercise.sets[setIndex].weight = exercise.previousWeights[setIndex];
      exercise.sets[setIndex].reps = exercise.previousReps[setIndex];
    });
    HapticFeedback.selectionClick();
    _saveCurrentSession();
  }

  Future<void> _pickRpe(ExerciseSet set) async {
    final value = await showModalBottomSheet<double>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ActionChip(
                label: const Text('RPE —'),
                onPressed: () => Navigator.pop(context, -1),
              ),
              for (final value in const [6.0, 7.0, 7.5, 8.0, 8.5, 9.0, 9.5, 10.0])
                ActionChip(
                  label: Text('RPE ${_formatWeight(value)}'),
                  onPressed: () => Navigator.pop(context, value),
                ),
            ],
          ),
        ),
      ),
    );
    if (value == null || !mounted) return;
    setState(() => set.rpe = value < 0 ? null : value);
    _saveCurrentSession();
  }

  Future<void> _pickRir(ExerciseSet set) async {
    final value = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ActionChip(
                label: const Text('RIR —'),
                onPressed: () => Navigator.pop(context, -1),
              ),
              for (final value in const [0, 1, 2, 3, 4, 5])
                ActionChip(
                  label: Text('RIR $value'),
                  onPressed: () => Navigator.pop(context, value),
                ),
            ],
          ),
        ),
      ),
    );
    if (value == null || !mounted) return;
    setState(() => set.rir = value < 0 ? null : value);
    _saveCurrentSession();
  }

  WorkoutExercise? _activeRestExercise() {
    for (final exercise in session.exercises) {
      if (_restSecondsByExerciseId.containsKey(exercise.id)) {
        return exercise;
      }
    }
    return null;
  }
"""
replace_once(previous_block, helpers, 'previous value helpers')

add_thirty_block = """  void _addThirtySeconds(WorkoutExercise exercise) {
    final currentSeconds = _restSecondsByExerciseId[exercise.id];
    if (currentSeconds == null) {
      _startRestForExercise(exercise);
      return;
    }

    setState(() {
      _restSecondsByExerciseId[exercise.id] = currentSeconds + 30;
      exercise.activeRestSeconds = currentSeconds + 30;
      exercise.activeRestStartedAt = DateTime.now();
    });
    LocalNotificationService.scheduleRestFinished(
      id: LocalNotificationService.restNotificationId(exercise.id),
      endTime: DateTime.now().add(Duration(seconds: currentSeconds + 30)),
      exerciseName: exercise.name,
    );
    _ensureRestTimerRunning();
    _saveCurrentSession();
  }
"""
subtract_helper = add_thirty_block + """
  void _subtractThirtySeconds(WorkoutExercise exercise) {
    final currentSeconds = _restSecondsByExerciseId[exercise.id];
    if (currentSeconds == null) return;
    final nextSeconds = math.max(1, currentSeconds - 30);
    setState(() {
      _restSecondsByExerciseId[exercise.id] = nextSeconds;
      exercise.activeRestSeconds = nextSeconds;
      exercise.activeRestStartedAt = DateTime.now();
    });
    final notificationId = LocalNotificationService.restNotificationId(exercise.id);
    LocalNotificationService.cancel(notificationId);
    LocalNotificationService.scheduleRestFinished(
      id: notificationId,
      endTime: DateTime.now().add(Duration(seconds: nextSeconds)),
      exerciseName: exercise.name,
    );
    _saveCurrentSession();
  }
"""
replace_once(add_thirty_block, subtract_helper, 'rest subtract helper')

replace_once(
    """          isWarmup: source.isWarmup,
          rpe: source.rpe,
""",
    """          type: source.type,
          rpe: source.rpe,
""",
    'copy set type',
)

replace_once(
    """    _saveCurrentSession();

    final delta = _setVolumeDelta(exercise, set, setIndex);
""",
    """    _saveCurrentSession();
    if (willComplete && !widget.editCompletedSession) {
      _startRestForExercise(exercise);
    }

    final delta = _setVolumeDelta(exercise, set, setIndex);
""",
    'automatic rest timer',
)

replace_once(
    """    final stats = _workoutStats;

    return PopScope(
""",
    """    final stats = _workoutStats;
    final activeRestExercise = _activeRestExercise();
    final activeRestSeconds = activeRestExercise == null
        ? null
        : _restSecondsByExerciseId[activeRestExercise.id];

    return PopScope(
""",
    'active rest build values',
)

replace_once(
    """                        final displaySetLabel = exSet.isWarmup
                            ? 'W $setLabel'
                            : setLabel;
""",
    """                        final displaySetLabel = exSet.type == SetType.normal
                            ? setLabel
                            : '${exSet.type.shortLabel} $setLabel';
""",
    'set type label',
)

previous_ui = """                                if (previousSetLabel != null)
                                  Padding(
                                    padding: const EdgeInsets.only(
                                      left: 72,
                                      top: 2,
                                    ),
                                    child: Text(
                                      previousSetLabel,
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(
                                            color: colorScheme.onSurfaceVariant,
                                          ),
                                    ),
                                  ),
"""
previous_action = """                                if (previousSetLabel != null)
                                  Padding(
                                    padding: const EdgeInsets.only(
                                      left: 72,
                                      top: 4,
                                    ),
                                    child: ActionChip(
                                      avatar: const Icon(Icons.history, size: 16),
                                      label: Text(previousSetLabel),
                                      tooltip: 'Usa i valori dell’ultima sessione',
                                      visualDensity: VisualDensity.compact,
                                      onPressed: () => _applyPreviousSetValues(
                                        exercise,
                                        setIndex,
                                      ),
                                    ),
                                  ),
"""
replace_once(previous_ui, previous_action, 'previous action chip')

old_details = """                                if (exSet.rpe != null ||
                                    exSet.rir != null ||
                                    exSet.notes.trim().isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(
                                      left: 72,
                                      top: 4,
                                    ),
                                    child: Wrap(
                                      spacing: 6,
                                      runSpacing: 4,
                                      children: [
                                        if (exSet.rpe != null)
                                          Chip(label: Text('RPE ${exSet.rpe}')),
                                        if (exSet.rir != null)
                                          Chip(label: Text('RIR ${exSet.rir}')),
                                        if (exSet.notes.trim().isNotEmpty)
                                          Chip(label: Text(exSet.notes)),
                                      ],
                                    ),
                                  ),
"""
new_details = """                                Padding(
                                  padding: const EdgeInsets.only(
                                    left: 72,
                                    top: 4,
                                  ),
                                  child: Wrap(
                                    spacing: 6,
                                    runSpacing: 4,
                                    crossAxisAlignment: WrapCrossAlignment.center,
                                    children: [
                                      PopupMenuButton<SetType>(
                                        key: ValueKey('set-type-${exSet.id}'),
                                        tooltip: 'Tipo di set',
                                        onSelected: (type) {
                                          setState(() => exSet.type = type);
                                          _saveCurrentSession();
                                        },
                                        itemBuilder: (context) => SetType.values
                                            .map(
                                              (type) => PopupMenuItem<SetType>(
                                                value: type,
                                                child: Text(type.label),
                                              ),
                                            )
                                            .toList(),
                                        child: Chip(
                                          avatar: Text(
                                            exSet.type.shortLabel,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w900,
                                            ),
                                          ),
                                          label: Text(exSet.type.label),
                                          visualDensity: VisualDensity.compact,
                                        ),
                                      ),
                                      ActionChip(
                                        key: ValueKey('rpe-${exSet.id}'),
                                        label: Text(
                                          exSet.rpe == null
                                              ? 'RPE —'
                                              : 'RPE ${_formatWeight(exSet.rpe!)}',
                                        ),
                                        visualDensity: VisualDensity.compact,
                                        onPressed: () => _pickRpe(exSet),
                                      ),
                                      ActionChip(
                                        key: ValueKey('rir-${exSet.id}'),
                                        label: Text(
                                          exSet.rir == null
                                              ? 'RIR —'
                                              : 'RIR ${exSet.rir}',
                                        ),
                                        visualDensity: VisualDensity.compact,
                                        onPressed: () => _pickRir(exSet),
                                      ),
                                      ActionChip(
                                        key: ValueKey('plates-${exSet.id}'),
                                        avatar: const Icon(Icons.calculate, size: 16),
                                        label: const Text('Piastre'),
                                        tooltip: 'Plate calculator',
                                        visualDensity: VisualDensity.compact,
                                        onPressed: () => showWorkoutPlateCalculator(
                                          context,
                                          initialWeight: exSet.weight,
                                        ),
                                      ),
                                      if (exSet.notes.trim().isNotEmpty)
                                        Chip(
                                          avatar: const Icon(Icons.notes, size: 16),
                                          label: Text(exSet.notes),
                                          visualDensity: VisualDensity.compact,
                                        ),
                                    ],
                                  ),
                                ),
"""
replace_once(old_details, new_details, 'inline set controls')

fab = """        floatingActionButton: FloatingActionButton.extended(
          onPressed: _openExercisePicker,
          icon: const Icon(Icons.add),
          label: const Text('Esercizio'),
        ),
"""
rest_bar = """        bottomNavigationBar: activeRestExercise == null || activeRestSeconds == null
            ? null
            : SafeArea(
                top: false,
                child: Container(
                  margin: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: colorScheme.outlineVariant),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.timer, color: colorScheme.primary),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Recupero ${_formatDuration(activeRestSeconds)}',
                              style: const TextStyle(fontWeight: FontWeight.w900),
                            ),
                            Text(
                              activeRestExercise.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: '-30 sec',
                        onPressed: () => _subtractThirtySeconds(activeRestExercise),
                        icon: const Icon(Icons.remove),
                      ),
                      IconButton(
                        tooltip: '+30 sec',
                        onPressed: () => _addThirtySeconds(activeRestExercise),
                        icon: const Icon(Icons.add),
                      ),
                      TextButton(
                        onPressed: () => _stopRestForExercise(activeRestExercise),
                        child: const Text('Salta'),
                      ),
                    ],
                  ),
                ),
              ),
""" + fab
replace_once(fab, rest_bar, 'sticky rest bar')

path.write_text(text)
