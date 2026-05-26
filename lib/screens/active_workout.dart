import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../app_data_store.dart';
import '../models/exercise.dart';
import '../models/schedule.dart';
import '../models/workout.dart';
import '../number_input.dart';

class ActiveWorkoutScreen extends StatefulWidget {
  final Schedule? schedule;
  final WorkoutSession? resumedSession;
  final List<WorkoutSession> history;
  final int defaultRestSeconds;

  const ActiveWorkoutScreen({
    super.key,
    required this.schedule,
    this.history = const [],
    required this.defaultRestSeconds,
  }) : resumedSession = null;

  const ActiveWorkoutScreen.resume({
    super.key,
    required this.resumedSession,
    required this.defaultRestSeconds,
  }) : schedule = null,
       history = const [];

  @override
  State<ActiveWorkoutScreen> createState() => _ActiveWorkoutScreenState();
}

class _ActiveWorkoutScreenState extends State<ActiveWorkoutScreen> {
  late WorkoutSession session;
  Timer? _restTimer;
  Timer? _durationTimer;
  int _elapsedSeconds = 0;
  final Map<String, int> _restSecondsByExerciseId = {};

  String _formatDuration(int totalSeconds) {
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  String _formatWeight(double weight) {
    return weight % 1 == 0
        ? weight.toStringAsFixed(0)
        : weight.toStringAsFixed(1);
  }

  String _formatPreviousWeights(List<double> weights) {
    return weights.map((weight) => '${_formatWeight(weight)} kg').join(', ');
  }

  String _targetLabelFor(WorkoutExercise exercise) {
    if (exercise.targetMinReps != null && exercise.targetMaxReps != null) {
      if (exercise.targetMinReps == exercise.targetMaxReps) {
        return '${exercise.targetMaxReps} reps';
      }
      return '${exercise.targetMinReps}-${exercise.targetMaxReps} reps';
    }

    if (exercise.sets.isEmpty) {
      return '-';
    }

    return '${exercise.sets.first.reps} reps';
  }

  String _normalizeExerciseName(String name) => name.trim().toLowerCase();

  WorkoutSession? _latestSessionForSchedule(Schedule schedule) {
    WorkoutSession? latestSession;

    for (final session in widget.history) {
      if (session.scheduleTitle != schedule.title) {
        continue;
      }

      if (latestSession == null ||
          session.endTime.isAfter(latestSession.endTime)) {
        latestSession = session;
      }
    }

    return latestSession;
  }

  WorkoutExercise? _previousExerciseFor(
    Exercise exercise,
    WorkoutSession? previousSession,
  ) {
    if (previousSession == null) {
      return null;
    }

    final exerciseName = _normalizeExerciseName(exercise.name);
    for (final previousExercise in previousSession.exercises) {
      if (_normalizeExerciseName(previousExercise.name) == exerciseName) {
        return previousExercise;
      }
    }

    return null;
  }

  List<double> _previousWeightsFor(WorkoutExercise? previousExercise) {
    if (previousExercise == null) {
      return const [];
    }

    final completedSets = previousExercise.sets.where((set) => set.isCompleted);
    final sourceSets = completedSets.isEmpty
        ? previousExercise.sets
        : completedSets;
    return sourceSets.map((set) => set.weight).toList();
  }

  List<int> _previousRepsFor(WorkoutExercise? previousExercise) {
    if (previousExercise == null) {
      return const [];
    }

    final completedSets = previousExercise.sets.where((set) => set.isCompleted);
    final sourceSets = completedSets.isEmpty
        ? previousExercise.sets
        : completedSets;
    return sourceSets.map((set) => set.reps).toList();
  }

  String? _progressionHintFor(WorkoutExercise exercise) {
    if (exercise.previousWeights.isEmpty || exercise.previousReps.isEmpty) {
      return null;
    }

    final minReps = exercise.targetMinReps;
    final maxReps = exercise.targetMaxReps;
    if (minReps == null || maxReps == null) {
      return 'Suggerimento: riparti dai carichi dell ultima volta.';
    }

    final allAtTop = exercise.previousReps.every((reps) => reps >= maxReps);
    final anyBelowMin = exercise.previousReps.any((reps) => reps < minReps);

    if (allAtTop) {
      return 'Suggerimento: aumenta +2.5 kg se tecnica ok.';
    }
    if (anyBelowMin) {
      return 'Suggerimento: mantieni o riduci -2.5 kg.';
    }
    return 'Suggerimento: stesso carico, cerca piu reps.';
  }

  double _weightForSet(
    Exercise exercise,
    List<double> previousWeights,
    int index,
  ) {
    if (previousWeights.isEmpty) {
      return exercise.weight;
    }

    return index < previousWeights.length
        ? previousWeights[index]
        : previousWeights.last;
  }

  List<ExerciseSet> _setsForExercise(
    Exercise exercise,
    List<double> previousWeights,
  ) {
    final isBackoff =
        exercise.technique == IntensityTechnique.topsetBackoff &&
        exercise.backoffReps != null;

    if (isBackoff) {
      return [
        ExerciseSet(
          weight: _weightForSet(exercise, previousWeights, 0),
          reps: exercise.reps,
        ),
        ExerciseSet(
          weight: _weightForSet(exercise, previousWeights, 1),
          reps: exercise.backoffReps!,
        ),
      ];
    }

    return List.generate(
      exercise.set,
      (index) => ExerciseSet(
        weight: _weightForSet(exercise, previousWeights, index),
        reps: exercise.reps,
      ),
    );
  }

  int _restSecondsFor(WorkoutExercise exercise) {
    return exercise.restSeconds ?? widget.defaultRestSeconds;
  }

  void _ensureRestTimerRunning() {
    if (_restTimer != null) return;

    _restTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) {
        _restTimer?.cancel();
        _restTimer = null;
        return;
      }

      final updatedCountdowns = <String, int>{};
      final finishedExerciseIds = <String>[];
      _restSecondsByExerciseId.forEach((exerciseId, remainingSeconds) {
        if (remainingSeconds > 1) {
          updatedCountdowns[exerciseId] = remainingSeconds - 1;
        } else {
          finishedExerciseIds.add(exerciseId);
        }
      });

      setState(() {
        _restSecondsByExerciseId
          ..clear()
          ..addAll(updatedCountdowns);
      });

      if (_restSecondsByExerciseId.isEmpty) {
        _restTimer?.cancel();
        _restTimer = null;
      }

      for (final exerciseId in finishedExerciseIds) {
        _notifyRestFinished(exerciseId);
      }
    });
  }

  void _notifyRestFinished(String exerciseId) {
    String? exerciseName;
    for (final exercise in session.exercises) {
      if (exercise.id == exerciseId) {
        exerciseName = exercise.name;
        break;
      }
    }

    HapticFeedback.mediumImpact();
    SystemSound.play(SystemSoundType.alert);

    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          exerciseName == null
              ? 'Recupero finito.'
              : 'Recupero finito: $exerciseName.',
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _startRestForExercise(WorkoutExercise exercise) {
    final restSeconds = _restSecondsFor(exercise);
    if (restSeconds <= 0) return;

    setState(() {
      _restSecondsByExerciseId[exercise.id] = restSeconds;
    });
    _ensureRestTimerRunning();
  }

  void _addThirtySeconds(WorkoutExercise exercise) {
    final currentSeconds = _restSecondsByExerciseId[exercise.id];
    if (currentSeconds == null) {
      _startRestForExercise(exercise);
      return;
    }

    setState(() {
      _restSecondsByExerciseId[exercise.id] = currentSeconds + 30;
    });
    _ensureRestTimerRunning();
  }

  void _stopRestForExercise(WorkoutExercise exercise) {
    setState(() {
      _restSecondsByExerciseId.remove(exercise.id);
    });

    if (_restSecondsByExerciseId.isEmpty) {
      _restTimer?.cancel();
      _restTimer = null;
    }
  }

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable();
    if (widget.resumedSession != null) {
      session = widget.resumedSession!;
    } else if (widget.schedule != null) {
      final previousSession = _latestSessionForSchedule(widget.schedule!);
      session = WorkoutSession(
        scheduleTitle: widget.schedule!.title,
        startTime: DateTime.now(),
        endTime: DateTime.now(),
        exercises: widget.schedule!.exercises.map((exercise) {
          final previousExercise = _previousExerciseFor(
            exercise,
            previousSession,
          );
          final previousWeights = _previousWeightsFor(previousExercise);
          final previousReps = _previousRepsFor(previousExercise);

          return WorkoutExercise(
            name: exercise.name,
            notes: exercise.notes,
            muscleGroup: exercise.muscleGroup,
            equipment: exercise.equipment,
            movementPattern: exercise.movementPattern,
            targetMinReps: exercise.targetMinReps,
            targetMaxReps: exercise.targetMaxReps,
            technique: exercise.technique,
            restSeconds: exercise.restSeconds,
            sets: _setsForExercise(exercise, previousWeights),
            previousWeights: previousWeights,
            previousReps: previousReps,
          );
        }).toList(),
      );
      _restoreIfNeeded();
    } else {
      session = WorkoutSession(
        scheduleTitle: 'Sessione',
        startTime: DateTime.now(),
        endTime: DateTime.now(),
        exercises: [],
      );
    }
    _startDurationTimer();
  }

  void _startDurationTimer() {
    _elapsedSeconds = DateTime.now().difference(session.startTime).inSeconds;
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) {
        _durationTimer?.cancel();
        _durationTimer = null;
        return;
      }
      setState(() {
        _elapsedSeconds++;
      });
    });
  }

  Future<void> _restoreIfNeeded() async {
    final savedSession = (await AppDataStore.loadBundle()).currentSession;

    if (savedSession == null || !mounted) return;

    final savedStartDay = savedSession.startTime.day;
    final savedStartMonth = savedSession.startTime.month;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Riprendere allenamento?'),
        content: Text(
          'C\'è un allenamento salvato dal $savedStartDay/$savedStartMonth.\n\nVuoi continuarlo o iniziare da zero?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Da zero'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Riprendi'),
          ),
        ],
      ),
    );

    if (!mounted) return;

    if (confirm == true) {
      setState(() {
        session = savedSession;
        _elapsedSeconds = DateTime.now()
            .difference(session.startTime)
            .inSeconds;
      });
    } else {
      await _clearSavedSession();
    }
  }

  Future<void> _saveCurrentSession() async {
    await AppDataStore.saveCurrentSession(session);
  }

  Future<void> _clearSavedSession() async {
    await AppDataStore.clearCurrentSession();
  }

  @override
  void dispose() {
    _restTimer?.cancel();
    _durationTimer?.cancel();
    WakelockPlus.disable();
    super.dispose();
  }

  Future<void> _finishWorkout() async {
    session.endTime = DateTime.now();

    final history = await AppDataStore.loadHistory();
    history.add(session);
    await AppDataStore.saveHistory(history);
    await AppDataStore.clearCurrentSession();

    if (mounted) {
      Navigator.pop(context, true);
    }
  }

  void _addSet(WorkoutExercise exercise, {bool isWarmup = false}) {
    setState(() {
      if (exercise.sets.isNotEmpty) {
        final last = exercise.sets.last;
        exercise.sets.add(
          ExerciseSet(weight: last.weight, reps: last.reps, isWarmup: isWarmup),
        );
      } else {
        exercise.sets.add(ExerciseSet(weight: 0, reps: 10, isWarmup: isWarmup));
      }
    });
    _saveCurrentSession();
  }

  void _updateSetWeight(ExerciseSet set, double delta) {
    setState(() {
      set.weight = (set.weight + delta).clamp(0, 1000).toDouble();
    });
    _saveCurrentSession();
  }

  void _updateSetReps(ExerciseSet set, int delta) {
    setState(() {
      set.reps = (set.reps + delta).clamp(0, 200).toInt();
    });
    _saveCurrentSession();
  }

  void _toggleSetCompleted(WorkoutExercise exercise, ExerciseSet set) {
    setState(() {
      set.isCompleted = !set.isCompleted;
      if (set.isCompleted) {
        _startRestForExercise(exercise);
      }
    });
    _saveCurrentSession();
  }

  Future<void> _showSetDetailsDialog(ExerciseSet set) async {
    final rpeController = TextEditingController(
      text: set.rpe?.toString() ?? '',
    );
    final rirController = TextEditingController(
      text: set.rir?.toString() ?? '',
    );
    final notesController = TextEditingController(text: set.notes);
    bool isWarmup = set.isWarmup;

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Dettagli set'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Warm-up'),
                  value: isWarmup,
                  onChanged: (value) => setDialogState(() => isWarmup = value),
                ),
                TextField(
                  controller: rpeController,
                  decoration: const InputDecoration(labelText: 'RPE (1-10)'),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: rirController,
                  decoration: const InputDecoration(labelText: 'RIR (0-10)'),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: notesController,
                  decoration: const InputDecoration(labelText: 'Note set'),
                  minLines: 1,
                  maxLines: 3,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Annulla'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Salva'),
            ),
          ],
        ),
      ),
    );

    if (saved != true) {
      return;
    }

    setState(() {
      set.isWarmup = isWarmup;
      final rpe = parseDecimalInput(rpeController.text);
      set.rpe = rpe?.clamp(1, 10).toDouble();
      final rir = parseIntInput(rirController.text);
      set.rir = rir?.clamp(0, 10).toInt();
      set.notes = notesController.text.trim();
    });
    _saveCurrentSession();
  }

  void _showUndoSnackBar({
    required String message,
    required VoidCallback onUndo,
  }) {
    if (!mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
        action: SnackBarAction(label: 'ANNULLA', onPressed: onUndo),
      ),
    );
  }

  void _removeSet(WorkoutExercise exercise, int index) {
    if (index < 0 || index >= exercise.sets.length) return;

    final deletedSet = exercise.sets[index];
    setState(() {
      exercise.sets.removeAt(index);
    });

    _saveCurrentSession();

    _showUndoSnackBar(
      message: 'Set eliminato.',
      onUndo: () {
        if (!mounted || exercise.sets.contains(deletedSet)) return;

        setState(() {
          final restoreIndex = index > exercise.sets.length
              ? exercise.sets.length
              : index;
          exercise.sets.insert(restoreIndex, deletedSet);
        });
        _saveCurrentSession();
      },
    );
  }

  ({int completedSets, int totalSets, double volume, int exercises})
  get _workoutStats {
    int completed = 0;
    int total = 0;
    double vol = 0;

    for (final exercise in session.exercises) {
      for (final set in exercise.sets) {
        total++;
        if (set.isCompleted) {
          completed++;
          if (!set.isWarmup) {
            vol += set.weight * set.reps;
          }
        }
      }
    }

    return (
      completedSets: completed,
      totalSets: total,
      volume: vol,
      exercises: session.exercises.length,
    );
  }

  Widget _summaryRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildStatBadge({
    required IconData icon,
    required String value,
    required ColorScheme colorScheme,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: colorScheme.onPrimaryContainer),
          const SizedBox(width: 2),
          Text(
            value,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: colorScheme.onPrimaryContainer,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final compactInputBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide(color: colorScheme.outlineVariant),
    );
    final stats = _workoutStats;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final navigator = Navigator.of(context);
        final confirm = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Annullare allenamento?'),
            content: const Text('I progressi non salvati andranno persi.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Continua'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Annulla'),
              ),
            ],
          ),
        );

        if (confirm == true) {
          await _clearSavedSession();
          if (mounted) navigator.pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  session.scheduleTitle,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              _buildStatBadge(
                icon: Icons.check_circle_outline,
                value: '${stats.completedSets}/${stats.totalSets}',
                colorScheme: colorScheme,
              ),
              const SizedBox(width: 6),
              _buildStatBadge(
                icon: Icons.timer,
                value: _formatDuration(_elapsedSeconds),
                colorScheme: colorScheme,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () async {
                final navigator = Navigator.of(context);
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Annullare allenamento?'),
                    content: const Text(
                      'I progressi non salvati andranno persi.',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('Continua'),
                      ),
                      ElevatedButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('Annulla'),
                      ),
                    ],
                  ),
                );

                if (confirm != true) return;

                await _clearSavedSession();
                if (mounted) navigator.pop();
              },
              style: TextButton.styleFrom(foregroundColor: colorScheme.error),
              child: const Text(
                'ANNULLA',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ),
            TextButton(
              onPressed: () async {
                final duration = _formatDuration(_elapsedSeconds);

                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Riepilogo allenamento'),
                    content: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _summaryRow('Esercizi', '${stats.exercises}'),
                        _summaryRow(
                          'Set',
                          '${stats.completedSets}/${stats.totalSets}',
                        ),
                        _summaryRow(
                          'Volume',
                          '${stats.volume.toStringAsFixed(1)} kg',
                        ),
                        _summaryRow('Durata', duration),
                      ],
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('Annulla'),
                      ),
                      ElevatedButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('Salva'),
                      ),
                    ],
                  ),
                );

                if (confirm != true) return;

                await _finishWorkout();
              },
              style: TextButton.styleFrom(foregroundColor: colorScheme.primary),
              child: const Text(
                'FINE',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ),
          ],
        ),
        body: ListView.builder(
          padding: const EdgeInsets.only(bottom: 16),
          itemCount: session.exercises.length,
          itemBuilder: (context, exIndex) {
            final exercise = session.exercises[exIndex];
            final activeRestSeconds = _restSecondsByExerciseId[exercise.id];
            final restSeconds = activeRestSeconds ?? _restSecondsFor(exercise);

            return Card(
              margin: const EdgeInsets.all(8.0),
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      exercise.name,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: colorScheme.primary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      exercise.muscleGroup.label,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        Chip(
                          label: Text('Target ${_targetLabelFor(exercise)}'),
                          visualDensity: VisualDensity.compact,
                        ),
                        if (exercise.equipment.trim().isNotEmpty)
                          Chip(
                            label: Text(exercise.equipment),
                            visualDensity: VisualDensity.compact,
                          ),
                        if (exercise.movementPattern.trim().isNotEmpty)
                          Chip(
                            label: Text(exercise.movementPattern),
                            visualDensity: VisualDensity.compact,
                          ),
                      ],
                    ),
                    if (exercise.notes.trim().isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        exercise.notes,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                    if (exercise.previousWeights.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        'Ultima volta: ${_formatPreviousWeights(exercise.previousWeights)}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                    if (_progressionHintFor(exercise) != null) ...[
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
                      children: [
                        Icon(Icons.timer, size: 18, color: colorScheme.primary),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            activeRestSeconds == null
                                ? 'Recupero ${_formatDuration(restSeconds)}'
                                : 'In corso: ${_formatDuration(restSeconds)}',
                            style: theme.textTheme.bodyMedium,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        IconButton(
                          tooltip: 'Aggiungi 30 secondi',
                          onPressed: () => _addThirtySeconds(exercise),
                          icon: const Icon(Icons.add),
                        ),
                        IconButton(
                          tooltip: 'Ferma recupero',
                          onPressed: activeRestSeconds == null
                              ? null
                              : () => _stopRestForExercise(exercise),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const SizedBox(
                          width: 72,
                          child: Text(
                            'SET',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                        Expanded(
                          child: Center(
                            child: Text(
                              'KG',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                        Expanded(
                          child: Center(
                            child: Text(
                              'REPS',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                        Container(
                          width: 40,
                          alignment: Alignment.center,
                          child: Icon(Icons.check),
                        ),
                      ],
                    ),
                    const Divider(),
                    ...List.generate(exercise.sets.length, (setIndex) {
                      final exSet = exercise.sets[setIndex];
                      final setLabel =
                          exercise.technique == IntensityTechnique.topsetBackoff
                          ? (setIndex == 0 ? 'Top Set' : 'Back off')
                          : '${setIndex + 1}';
                      final displaySetLabel = exSet.isWarmup
                          ? 'W $setLabel'
                          : setLabel;

                      return Dismissible(
                        key: ValueKey(exSet.id),
                        direction: DismissDirection.endToStart,
                        onDismissed: (_) => _removeSet(exercise, setIndex),
                        background: Container(
                          color: colorScheme.error,
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 20),
                          child: Icon(Icons.delete, color: colorScheme.onError),
                        ),
                        child: Container(
                          color: exSet.isCompleted
                              ? colorScheme.tertiaryContainer.withValues(
                                  alpha: 0.55,
                                )
                              : null,
                          padding: const EdgeInsets.symmetric(vertical: 4.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  SizedBox(
                                    width: 72,
                                    child: Text(
                                      displaySetLabel,
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8.0,
                                      ),
                                      child: TextFormField(
                                        key: ValueKey(
                                          '${exSet.id}-weight-${exSet.weight}',
                                        ),
                                        initialValue: _formatWeight(
                                          exSet.weight,
                                        ),
                                        keyboardType:
                                            const TextInputType.numberWithOptions(
                                              decimal: true,
                                            ),
                                        textAlign: TextAlign.center,
                                        decoration: InputDecoration(
                                          isDense: true,
                                          contentPadding:
                                              const EdgeInsets.symmetric(
                                                vertical: 8,
                                              ),
                                          border: compactInputBorder,
                                          enabledBorder: compactInputBorder,
                                          focusedBorder: compactInputBorder
                                              .copyWith(
                                                borderSide: BorderSide(
                                                  color: colorScheme.primary,
                                                  width: 1.5,
                                                ),
                                              ),
                                        ),
                                        onChanged: (value) {
                                          exSet.weight =
                                              parseDecimalInput(value) ?? 0.0;
                                          _saveCurrentSession();
                                        },
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8.0,
                                      ),
                                      child: TextFormField(
                                        key: ValueKey(
                                          '${exSet.id}-reps-${exSet.reps}',
                                        ),
                                        initialValue: exSet.reps.toString(),
                                        keyboardType: TextInputType.number,
                                        textAlign: TextAlign.center,
                                        decoration: InputDecoration(
                                          isDense: true,
                                          contentPadding:
                                              const EdgeInsets.symmetric(
                                                vertical: 8,
                                              ),
                                          border: compactInputBorder,
                                          enabledBorder: compactInputBorder,
                                          focusedBorder: compactInputBorder
                                              .copyWith(
                                                borderSide: BorderSide(
                                                  color: colorScheme.primary,
                                                  width: 1.5,
                                                ),
                                              ),
                                        ),
                                        onChanged: (value) {
                                          exSet.reps =
                                              parseIntInput(value) ?? 0;
                                          _saveCurrentSession();
                                        },
                                      ),
                                    ),
                                  ),
                                  InkWell(
                                    onTap: () =>
                                        _toggleSetCompleted(exercise, exSet),
                                    child: Container(
                                      width: 40,
                                      height: 36,
                                      decoration: BoxDecoration(
                                        color: exSet.isCompleted
                                            ? colorScheme.tertiary
                                            : colorScheme
                                                  .surfaceContainerHighest,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Icon(
                                        Icons.check,
                                        color: exSet.isCompleted
                                            ? colorScheme.onTertiary
                                            : colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: 'RPE, RIR, note',
                                    onPressed: () =>
                                        _showSetDetailsDialog(exSet),
                                    icon: const Icon(Icons.tune),
                                  ),
                                ],
                              ),
                              Padding(
                                padding: const EdgeInsets.only(
                                  left: 72,
                                  top: 4,
                                ),
                                child: Wrap(
                                  spacing: 6,
                                  runSpacing: 4,
                                  children: [
                                    OutlinedButton(
                                      onPressed: () =>
                                          _updateSetWeight(exSet, -2.5),
                                      child: const Text('-2.5kg'),
                                    ),
                                    OutlinedButton(
                                      onPressed: () =>
                                          _updateSetWeight(exSet, 2.5),
                                      child: const Text('+2.5kg'),
                                    ),
                                    OutlinedButton(
                                      onPressed: () =>
                                          _updateSetReps(exSet, -1),
                                      child: const Text('-1 rep'),
                                    ),
                                    OutlinedButton(
                                      onPressed: () => _updateSetReps(exSet, 1),
                                      child: const Text('+1 rep'),
                                    ),
                                    if (exSet.rpe != null)
                                      Chip(label: Text('RPE ${exSet.rpe}')),
                                    if (exSet.rir != null)
                                      Chip(label: Text('RIR ${exSet.rir}')),
                                    if (exSet.notes.trim().isNotEmpty)
                                      Chip(label: Text(exSet.notes)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: [
                        TextButton.icon(
                          onPressed: () => _addSet(exercise),
                          icon: const Icon(Icons.add),
                          label: const Text('aggiungi set'),
                        ),
                        TextButton.icon(
                          onPressed: () => _addSet(exercise, isWarmup: true),
                          icon: const Icon(Icons.local_fire_department),
                          label: const Text('warm-up'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
