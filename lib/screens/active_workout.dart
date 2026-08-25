import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../app_data_store.dart';
import '../dialog_form.dart';
import '../exercise_catalog.dart';
import '../local_notifications.dart';
import '../models/exercise.dart';
import '../models/schedule.dart';
import '../models/workout.dart';
import '../number_input.dart';
import '../top_set_backoff.dart' as top_set_backoff;
import '../workout_plate_calculator.dart';
import 'exercise_picker.dart';
import 'session_summary.dart';

enum _WorkoutExerciseAction {
  replace,
  duplicate,
  superset,
  moveUp,
  moveDown,
  delete,
}

class ActiveWorkoutScreen extends StatefulWidget {
  final Schedule? schedule;
  final WorkoutSession? resumedSession;
  final List<WorkoutSession> history;
  final int defaultRestSeconds;
  final double defaultBackoffReductionPercent;
  final bool editCompletedSession;

  const ActiveWorkoutScreen({
    super.key,
    required this.schedule,
    this.history = const [],
    required this.defaultRestSeconds,
    this.defaultBackoffReductionPercent =
        top_set_backoff.defaultBackoffReductionPercent,
  }) : resumedSession = null,
       editCompletedSession = false;

  const ActiveWorkoutScreen.resume({
    super.key,
    required this.resumedSession,
    this.history = const [],
    required this.defaultRestSeconds,
    this.defaultBackoffReductionPercent =
        top_set_backoff.defaultBackoffReductionPercent,
  }) : schedule = null,
       editCompletedSession = false,
       assert(resumedSession != null);

  const ActiveWorkoutScreen.editCompleted({
    super.key,
    required WorkoutSession session,
    this.history = const [],
    required this.defaultRestSeconds,
    this.defaultBackoffReductionPercent =
        top_set_backoff.defaultBackoffReductionPercent,
  }) : schedule = null,
       resumedSession = session,
       editCompletedSession = true;

  @override
  State<ActiveWorkoutScreen> createState() => _ActiveWorkoutScreenState();
}

class _ActiveWorkoutScreenState extends State<ActiveWorkoutScreen>
    with WidgetsBindingObserver {
  late WorkoutSession session;
  Timer? _restTimer;
  Timer? _durationTimer;
  int _elapsedSeconds = 0;
  final Map<String, int> _restSecondsByExerciseId = {};
  final Map<String, GlobalKey> _exerciseCardKeys = {};
  final Set<String> _exerciseIdsAddedToScheduleThisFinish = {};
  DateTime? _lastSavedAt;
  bool _isSaving = false;
  bool _allowCurrentSessionSaves = true;
  Future<void> _pendingCurrentSessionSave = Future.value();

  Color _accentForIndex(ColorScheme colorScheme, int index) {
    final accents = [
      colorScheme.primary,
      colorScheme.secondary,
      colorScheme.tertiary,
      colorScheme.error,
    ];
    return accents[index % accents.length];
  }

  GlobalKey _exerciseCardKey(String exerciseId) {
    return _exerciseCardKeys.putIfAbsent(exerciseId, GlobalKey.new);
  }

  void _scrollToExercise(String exerciseId) {
    final context = _exerciseCardKeys[exerciseId]?.currentContext;
    if (context == null) {
      return;
    }
    Scrollable.ensureVisible(
      context,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      alignment: 0.08,
    );
  }

  Iterable<WorkoutSession> get _comparisonHistory {
    return widget.history.where(
      (historySession) => historySession.id != session.id,
    );
  }

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

  double? _backoffReductionFor(WorkoutExercise exercise, int setIndex) {
    if (exercise.technique != IntensityTechnique.topsetBackoff ||
        setIndex == 0 ||
        exercise.sets.isEmpty) {
      return null;
    }

    return top_set_backoff.backoffReductionPercentFor(
      reductionPercent: exercise.backoffReductionPercent,
    );
  }

  double? _recommendedBackoffWeightFor(WorkoutExercise exercise, int setIndex) {
    final reduction = _backoffReductionFor(exercise, setIndex);
    if (reduction == null) {
      return null;
    }

    final topSetWeight = exercise.sets.first.weight;
    if (topSetWeight <= 0) {
      return null;
    }

    return top_set_backoff.recommendedBackoffWeight(
      topSetWeight,
      reductionPercent: reduction,
    );
  }

  String? _backoffHintFor(WorkoutExercise exercise, int setIndex) {
    final reduction = _backoffReductionFor(exercise, setIndex);
    final backoffWeight = _recommendedBackoffWeightFor(exercise, setIndex);
    if (reduction == null || backoffWeight == null) {
      return null;
    }

    return 'Back off: ${_formatWeight(backoffWeight)} kg (-${_formatWeight(reduction)}%)';
  }

  String _formatVolume(double volume) {
    return volume % 1 == 0
        ? volume.toStringAsFixed(0)
        : volume.toStringAsFixed(1);
  }

  String _saveStatusLabel() {
    if (widget.editCompletedSession) {
      return _lastSavedAt == null ? 'Modifica storico' : 'Modifiche locali';
    }
    if (_isSaving) {
      return 'Salvataggio...';
    }
    final savedAt = _lastSavedAt;
    if (savedAt == null) {
      return 'Autosave attivo';
    }
    return 'Salvato ${savedAt.hour.toString().padLeft(2, '0')}:${savedAt.minute.toString().padLeft(2, '0')}';
  }

  double _setVolume(ExerciseSet set) => set.weight * set.reps;

  double _completedExerciseVolume(WorkoutExercise exercise) {
    return exercise.sets
        .where((set) => set.isCompleted && !set.isWarmup)
        .fold<double>(0, (total, set) => total + _setVolume(set));
  }

  Iterable<WorkoutExercise> _historicalExercisesFor(WorkoutExercise exercise) {
    final exerciseName = _normalizeExerciseName(exercise.name);
    return _comparisonHistory.expand((historySession) {
      return historySession.exercises.where(
        (historicalExercise) =>
            _normalizeExerciseName(historicalExercise.name) == exerciseName,
      );
    });
  }

  Iterable<ExerciseSet> _historicalWorkSetsFor(WorkoutExercise exercise) {
    return _historicalExercisesFor(exercise)
        .expand((historicalExercise) => historicalExercise.sets)
        .where((set) => set.isCompleted && !set.isWarmup);
  }

  double? _maxHistoricalWeightFor(WorkoutExercise exercise) {
    double? maxWeight;
    for (final set in _historicalWorkSetsFor(exercise)) {
      if (maxWeight == null || set.weight > maxWeight) {
        maxWeight = set.weight;
      }
    }
    return maxWeight;
  }

  int? _maxHistoricalRepsFor(WorkoutExercise exercise) {
    int? maxReps;
    for (final set in _historicalWorkSetsFor(exercise)) {
      if (maxReps == null || set.reps > maxReps) {
        maxReps = set.reps;
      }
    }
    return maxReps;
  }

  double? _bestHistoricalSetVolumeFor(WorkoutExercise exercise) {
    double? bestVolume;
    for (final set in _historicalWorkSetsFor(exercise)) {
      final volume = _setVolume(set);
      if (bestVolume == null || volume > bestVolume) {
        bestVolume = volume;
      }
    }
    return bestVolume;
  }

  double? _bestHistoricalExerciseVolumeFor(WorkoutExercise exercise) {
    double? bestVolume;
    for (final historicalExercise in _historicalExercisesFor(exercise)) {
      final volume = _completedExerciseVolume(historicalExercise);
      if (volume <= 0) {
        continue;
      }
      if (bestVolume == null || volume > bestVolume) {
        bestVolume = volume;
      }
    }
    return bestVolume;
  }

  int? _lastCompletedWorkSetIndex(WorkoutExercise exercise) {
    for (var index = exercise.sets.length - 1; index >= 0; index--) {
      final set = exercise.sets[index];
      if (set.isCompleted && !set.isWarmup) {
        return index;
      }
    }
    return null;
  }

  List<String> _personalRecordLabelsFor(
    WorkoutExercise exercise,
    ExerciseSet set,
    int setIndex,
  ) {
    if (!set.isCompleted || set.isWarmup) {
      return const [];
    }

    final labels = <String>[];
    final maxWeight = _maxHistoricalWeightFor(exercise);
    if (maxWeight != null && set.weight > maxWeight) {
      labels.add('PR kg');
    }

    final maxReps = _maxHistoricalRepsFor(exercise);
    if (maxReps != null && set.reps > maxReps) {
      labels.add('PR reps');
    }

    final bestSetVolume = _bestHistoricalSetVolumeFor(exercise);
    if (bestSetVolume != null && _setVolume(set) > bestSetVolume) {
      labels.add('PR set');
    }

    final bestExerciseVolume = _bestHistoricalExerciseVolumeFor(exercise);
    if (bestExerciseVolume != null &&
        _lastCompletedWorkSetIndex(exercise) == setIndex &&
        _completedExerciseVolume(exercise) > bestExerciseVolume) {
      labels.add('PR volume');
    }

    return labels;
  }

  int _sessionPrCount() {
    var count = 0;
    for (final exercise in session.exercises) {
      for (var index = 0; index < exercise.sets.length; index++) {
        if (_personalRecordLabelsFor(
          exercise,
          exercise.sets[index],
          index,
        ).isNotEmpty) {
          count++;
        }
      }
    }
    return count;
  }

  String? _previousSetLabelFor(WorkoutExercise exercise, int setIndex) {
    if (setIndex >= exercise.previousWeights.length ||
        setIndex >= exercise.previousReps.length) {
      return null;
    }

    return 'Ultima: ${_formatWeight(exercise.previousWeights[setIndex])} kg x ${exercise.previousReps[setIndex]}';
  }

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
              for (final value in const [
                6.0,
                7.0,
                7.5,
                8.0,
                8.5,
                9.0,
                9.5,
                10.0,
              ])
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

  String? _nextSetHintFor(
    WorkoutExercise exercise,
    ExerciseSet set,
    int setIndex,
  ) {
    if (!set.isCompleted ||
        set.isWarmup ||
        setIndex >= exercise.sets.length - 1) {
      return null;
    }

    if (exercise.technique == IntensityTechnique.topsetBackoff &&
        setIndex == 0) {
      final backoffWeight = _recommendedBackoffWeightFor(
        exercise,
        setIndex + 1,
      );
      if (backoffWeight != null) {
        return 'Prossimo: back off ${_formatWeight(backoffWeight)} kg.';
      }
    }

    final targetMinReps =
        exercise.targetMinReps ?? exercise.sets[setIndex + 1].reps;
    final targetMaxReps = exercise.targetMaxReps;
    if (set.reps < targetMinReps) {
      return 'Prossimo: mantieni, eri sotto target.';
    }
    if (targetMaxReps != null && set.reps >= targetMaxReps) {
      return 'Prossimo: +${_formatWeight(exercise.progressionKgStep)} kg se tecnica ok.';
    }
    return 'Prossimo: stesso kg, prova +1 rep.';
  }

  double? _previousSetVolumeFor(WorkoutExercise exercise, int setIndex) {
    if (setIndex >= exercise.previousWeights.length ||
        setIndex >= exercise.previousReps.length) {
      return null;
    }

    return exercise.previousWeights[setIndex] * exercise.previousReps[setIndex];
  }

  double? _setVolumeDelta(
    WorkoutExercise exercise,
    ExerciseSet set,
    int setIndex,
  ) {
    if (!set.isCompleted || set.isWarmup) {
      return null;
    }

    final previousVolume = _previousSetVolumeFor(exercise, setIndex);
    if (previousVolume == null || previousVolume <= 0) {
      return null;
    }

    return _setVolume(set) - previousVolume;
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
    if (exercise.progressionScheme == ProgressionScheme.manual) {
      return 'Progressione manuale: carico e reps non cambiano in automatico.';
    }
    if (exercise.previousWeights.isEmpty || exercise.previousReps.isEmpty) {
      return null;
    }

    final minReps = exercise.targetMinReps;
    final maxReps = exercise.targetMaxReps;
    if (minReps == null || maxReps == null) {
      return 'Progressione auto: riparti dai carichi dell ultima volta.';
    }

    if (exercise.progressionScheme == ProgressionScheme.loadOnly) {
      return 'Schema carico: aumenta kg solo quando tutte le serie stanno al top.';
    }
    if (exercise.progressionScheme == ProgressionScheme.repsOnly) {
      return 'Schema reps: carico fisso, sali di ${exercise.progressionRepStep} rep.';
    }
    if (exercise.progressionScheme == ProgressionScheme.linear) {
      return 'Schema lineare: +${exercise.progressionKgStep} kg quando completi le serie.';
    }

    final allAtTop = exercise.previousReps.every((reps) => reps >= maxReps);
    final anyBelowMin = exercise.previousReps.any((reps) => reps < minReps);

    if (allAtTop) {
      return 'Progressione auto: prossimo giro +${exercise.progressionKgStep} kg se tecnica ok.';
    }
    if (anyBelowMin) {
      return 'Progressione auto: mantieni o riduci -${exercise.progressionKgStep} kg.';
    }
    return 'Progressione auto: stesso carico, +${exercise.progressionRepStep} rep obiettivo.';
  }

  double _deloadWeight(double weight) {
    return (weight * 0.9 * 2).roundToDouble() / 2;
  }

  double _weightForSet(
    Exercise exercise,
    List<double> previousWeights,
    List<int> previousReps,
    int index,
  ) {
    if (previousWeights.isEmpty) {
      return exercise.weight;
    }

    if (exercise.progressionScheme == ProgressionScheme.manual ||
        exercise.progressionScheme == ProgressionScheme.repsOnly) {
      return index < previousWeights.length
          ? previousWeights[index]
          : previousWeights.last;
    }

    final previousWeight = index < previousWeights.length
        ? previousWeights[index]
        : previousWeights.last;
    final previousRep = index < previousReps.length
        ? previousReps[index]
        : (previousReps.isEmpty ? exercise.reps : previousReps.last);
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
      return math.max(0, previousWeight - exercise.progressionKgStep);
    }
    return previousWeight;
  }

  int _repsForSet(Exercise exercise, List<int> previousReps, int index) {
    final minReps = exercise.targetMinReps;
    final maxReps = exercise.targetMaxReps;
    if (previousReps.isEmpty || minReps == null || maxReps == null) {
      return exercise.reps;
    }

    if (exercise.progressionScheme == ProgressionScheme.manual ||
        exercise.progressionScheme == ProgressionScheme.loadOnly ||
        exercise.progressionScheme == ProgressionScheme.linear) {
      return exercise.reps;
    }

    final previousRep = index < previousReps.length
        ? previousReps[index]
        : previousReps.last;
    if (previousRep >= maxReps || previousRep < minReps) {
      return minReps;
    }
    return math.min(maxReps, previousRep + exercise.progressionRepStep);
  }

  List<ExerciseSet> _setsForExercise(
    Exercise exercise,
    List<double> previousWeights,
    List<int> previousReps,
  ) {
    final isBackoff =
        exercise.technique == IntensityTechnique.topsetBackoff &&
        exercise.backoffReps != null;

    if (isBackoff) {
      return [
        ExerciseSet(
          weight: _weightForSet(exercise, previousWeights, previousReps, 0),
          reps: _repsForSet(exercise, previousReps, 0),
        ),
        ExerciseSet(
          weight: _weightForSet(exercise, previousWeights, previousReps, 1),
          reps: exercise.backoffReps!,
        ),
      ];
    }

    return List.generate(
      exercise.set,
      (index) => ExerciseSet(
        weight: _weightForSet(exercise, previousWeights, previousReps, index),
        reps: _repsForSet(exercise, previousReps, index),
      ),
    );
  }

  WorkoutExercise _workoutExerciseFromExercise(
    Exercise exercise,
    WorkoutSession? previousSession, {
    bool keepSourceExerciseId = true,
  }) {
    final previousExercise = _previousExerciseFor(exercise, previousSession);
    final previousWeights = _previousWeightsFor(previousExercise);
    final previousReps = _previousRepsFor(previousExercise);

    return WorkoutExercise(
      sourceExerciseId: keepSourceExerciseId ? exercise.id : null,
      name: exercise.name,
      notes: exercise.notes,
      muscleGroup: exercise.muscleGroup,
      equipment: exercise.equipment,
      movementPattern: exercise.movementPattern,
      targetMinReps: exercise.targetMinReps,
      targetMaxReps: exercise.targetMaxReps,
      technique: exercise.technique,
      backoffReductionPercent: exercise.backoffReductionPercent,
      restSeconds: exercise.restSeconds,
      supersetGroup: exercise.supersetGroup,
      progressionKgStep: exercise.progressionKgStep,
      progressionRepStep: exercise.progressionRepStep,
      progressionScheme: exercise.progressionScheme,
      sets: _setsForExercise(exercise, previousWeights, previousReps),
      previousWeights: previousWeights,
      previousReps: previousReps,
    );
  }

  Exercise _exerciseFromCatalogEntry(ExerciseCatalogEntry entry) {
    return Exercise(
      name: entry.name,
      set: 3,
      reps: 10,
      weight: 0,
      muscleGroup: entry.muscleGroup,
      equipment: entry.equipment,
      movementPattern: entry.movementPattern,
      notes: '',
      technique: IntensityTechnique.none,
      backoffReductionPercent: widget.defaultBackoffReductionPercent,
      restSeconds: widget.defaultRestSeconds,
      progressionKgStep: 2.5,
      progressionRepStep: 1,
      progressionScheme: ProgressionScheme.doubleProgression,
    );
  }

  Exercise _copyExerciseTemplate(Exercise exercise) {
    return Exercise.fromJson(exercise.toJson());
  }

  Exercise _exerciseFromWorkoutExercise(WorkoutExercise exercise) {
    final workSets = exercise.sets.where((set) => !set.isWarmup).toList();
    final sourceSet = workSets.isNotEmpty
        ? workSets.first
        : (exercise.sets.isNotEmpty ? exercise.sets.first : null);
    final isBackoff = exercise.technique == IntensityTechnique.topsetBackoff;
    final reps = sourceSet?.reps ?? exercise.targetMinReps ?? 10;
    final backoffReps = isBackoff
        ? (workSets.length > 1 ? workSets[1].reps : reps)
        : null;

    return Exercise(
      name: exercise.name,
      set: isBackoff ? 2 : math.max(1, workSets.length),
      reps: reps,
      weight: sourceSet?.weight ?? 0,
      muscleGroup: exercise.muscleGroup,
      equipment: exercise.equipment,
      movementPattern: exercise.movementPattern,
      targetMinReps: exercise.targetMinReps,
      targetMaxReps: exercise.targetMaxReps,
      notes: exercise.notes,
      technique: exercise.technique,
      backoffReductionPercent: exercise.backoffReductionPercent,
      backoffReps: backoffReps,
      restSeconds: exercise.restSeconds,
      supersetGroup: exercise.supersetGroup,
      progressionKgStep: exercise.progressionKgStep,
      progressionRepStep: exercise.progressionRepStep,
      progressionScheme: exercise.progressionScheme,
    );
  }

  void _applyDeloadToSession() {
    for (final exercise in session.exercises) {
      for (final set in exercise.sets) {
        set.weight = _deloadWeight(set.weight);
      }
    }
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
        exercise.activeRestSeconds = null;
        exercise.activeRestStartedAt = null;
        break;
      }
    }
    _saveCurrentSession();

    HapticFeedback.mediumImpact();
    SystemSound.play(SystemSoundType.alert);
    LocalNotificationService.cancel(
      LocalNotificationService.restNotificationId(exerciseId),
    );
    LocalNotificationService.showRestFinished(exerciseName ?? '');

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
      exercise.activeRestSeconds = restSeconds;
      exercise.activeRestStartedAt = DateTime.now();
    });
    LocalNotificationService.scheduleRestFinished(
      id: LocalNotificationService.restNotificationId(exercise.id),
      endTime: DateTime.now().add(Duration(seconds: restSeconds)),
      exerciseName: exercise.name,
    );
    _ensureRestTimerRunning();
    _saveCurrentSession();
  }

  void _addThirtySeconds(WorkoutExercise exercise) {
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

  void _subtractThirtySeconds(WorkoutExercise exercise) {
    final currentSeconds = _restSecondsByExerciseId[exercise.id];
    if (currentSeconds == null) return;
    final nextSeconds = math.max(1, currentSeconds - 30);
    setState(() {
      _restSecondsByExerciseId[exercise.id] = nextSeconds;
      exercise.activeRestSeconds = nextSeconds;
      exercise.activeRestStartedAt = DateTime.now();
    });
    final notificationId = LocalNotificationService.restNotificationId(
      exercise.id,
    );
    LocalNotificationService.cancel(notificationId);
    LocalNotificationService.scheduleRestFinished(
      id: notificationId,
      endTime: DateTime.now().add(Duration(seconds: nextSeconds)),
      exerciseName: exercise.name,
    );
    _saveCurrentSession();
  }

  void _stopRestForExercise(WorkoutExercise exercise) {
    setState(() {
      _restSecondsByExerciseId.remove(exercise.id);
      exercise.activeRestSeconds = null;
      exercise.activeRestStartedAt = null;
    });
    LocalNotificationService.cancel(
      LocalNotificationService.restNotificationId(exercise.id),
    );

    if (_restSecondsByExerciseId.isEmpty) {
      _restTimer?.cancel();
      _restTimer = null;
    }
    _saveCurrentSession();
  }

  Future<void> _cancelAllRestTimers() async {
    _restTimer?.cancel();
    _restTimer = null;
    final exerciseIds = <String>{
      ..._restSecondsByExerciseId.keys,
      ...session.exercises
          .where(
            (exercise) =>
                exercise.activeRestStartedAt != null ||
                exercise.activeRestSeconds != null,
          )
          .map((exercise) => exercise.id),
    };
    _restSecondsByExerciseId.clear();
    for (final exercise in session.exercises) {
      exercise.activeRestSeconds = null;
      exercise.activeRestStartedAt = null;
    }
    for (final exerciseId in exerciseIds) {
      await LocalNotificationService.cancel(
        LocalNotificationService.restNotificationId(exerciseId),
      );
    }
  }

  void _updateExerciseRestSeconds(WorkoutExercise exercise, String value) {
    final parsedSeconds = parseIntInput(value);
    if (parsedSeconds == null) {
      return;
    }

    final normalizedSeconds = parsedSeconds.clamp(0, 3600).toInt();
    final wasActive = _restSecondsByExerciseId.containsKey(exercise.id);
    if (wasActive && normalizedSeconds == 0) {
      _stopRestForExercise(exercise);
      return;
    }

    setState(() {
      exercise.restSeconds = normalizedSeconds;
      if (wasActive) {
        _restSecondsByExerciseId[exercise.id] = normalizedSeconds;
        exercise.activeRestSeconds = normalizedSeconds;
        exercise.activeRestStartedAt = DateTime.now();
      }
    });
    if (wasActive) {
      final notificationId = LocalNotificationService.restNotificationId(
        exercise.id,
      );
      LocalNotificationService.cancel(notificationId);
      LocalNotificationService.scheduleRestFinished(
        id: notificationId,
        endTime: DateTime.now().add(Duration(seconds: normalizedSeconds)),
        exerciseName: exercise.name,
      );
    }
    _saveCurrentSession();
  }

  void _restoreRestTimersFromSession({bool notifyExpired = false}) {
    final now = DateTime.now();
    final expiredExerciseIds = <String>[];
    _restSecondsByExerciseId.clear();
    for (final exercise in session.exercises) {
      final startedAt = exercise.activeRestStartedAt;
      final duration = exercise.activeRestSeconds;
      if (startedAt == null || duration == null) {
        continue;
      }

      final remaining = duration - now.difference(startedAt).inSeconds;
      if (remaining > 0) {
        _restSecondsByExerciseId[exercise.id] = remaining;
        LocalNotificationService.scheduleRestFinished(
          id: LocalNotificationService.restNotificationId(exercise.id),
          endTime: now.add(Duration(seconds: remaining)),
          exerciseName: exercise.name,
        );
      } else {
        exercise.activeRestStartedAt = null;
        exercise.activeRestSeconds = null;
        if (notifyExpired) {
          expiredExerciseIds.add(exercise.id);
        }
      }
    }
    if (_restSecondsByExerciseId.isNotEmpty) {
      _ensureRestTimerRunning();
    }
    for (final exerciseId in expiredExerciseIds) {
      _notifyRestFinished(exerciseId);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (!widget.editCompletedSession) {
        _restoreRestTimersFromSession(notifyExpired: true);
      }
      if (mounted) {
        setState(() {
          _elapsedSeconds = _elapsedSecondsFromClock();
        });
      }
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (!widget.editCompletedSession) {
      WakelockPlus.enable();
    }
    if (widget.resumedSession != null) {
      session = widget.editCompletedSession
          ? WorkoutSession.fromJson(widget.resumedSession!.toJson())
          : widget.resumedSession!;
      if (!widget.editCompletedSession) {
        _restoreRestTimersFromSession();
      }
    } else if (widget.schedule != null) {
      final previousSession = _latestSessionForSchedule(widget.schedule!);
      session = WorkoutSession(
        scheduleId: widget.schedule!.id,
        scheduleTitle: widget.schedule!.title,
        startTime: DateTime.now(),
        endTime: DateTime.now(),
        exercises: widget.schedule!.exercises
            .map(
              (exercise) =>
                  _workoutExerciseFromExercise(exercise, previousSession),
            )
            .toList(),
      );
      if (widget.schedule!.isDeloadWeek()) {
        _applyDeloadToSession();
      }
      _restoreRestTimersFromSession();
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
    _elapsedSeconds = _elapsedSecondsFromClock();
    if (widget.editCompletedSession) {
      return;
    }
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) {
        _durationTimer?.cancel();
        _durationTimer = null;
        return;
      }
      setState(() {
        _elapsedSeconds = _elapsedSecondsFromClock();
      });
    });
  }

  int _elapsedSecondsFromClock() {
    final endTime = widget.editCompletedSession
        ? session.endTime
        : DateTime.now();
    return math.max(0, endTime.difference(session.startTime).inSeconds);
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
        _elapsedSeconds = _elapsedSecondsFromClock();
      });
      _restoreRestTimersFromSession();
    } else {
      await _clearSavedSession();
    }
  }

  Future<void> _saveCurrentSession() async {
    if (widget.editCompletedSession) {
      if (mounted) {
        setState(() => _lastSavedAt = DateTime.now());
      }
      return;
    }
    if (!_allowCurrentSessionSaves) {
      return;
    }
    if (mounted) {
      setState(() => _isSaving = true);
    }
    await _queueCurrentSessionSave(showSaving: true);
  }

  Future<void> _saveCurrentSessionSilently() async {
    if (widget.editCompletedSession) {
      _lastSavedAt = DateTime.now();
      return;
    }
    if (!_allowCurrentSessionSaves) {
      return;
    }

    await _queueCurrentSessionSave();
  }

  Future<void> _queueCurrentSessionSave({bool showSaving = false}) {
    final nextSave = _pendingCurrentSessionSave.catchError((_) {}).then((
      _,
    ) async {
      if (!_allowCurrentSessionSaves) {
        return;
      }
      await AppDataStore.saveCurrentSession(session);
      if (mounted) {
        setState(() {
          _lastSavedAt = DateTime.now();
          if (showSaving) {
            _isSaving = false;
          }
        });
      } else {
        _lastSavedAt = DateTime.now();
      }
    });
    _pendingCurrentSessionSave = nextSave;
    return nextSave;
  }

  Future<void> _drainCurrentSessionSaves() async {
    await _pendingCurrentSessionSave.catchError((_) {});
  }

  Future<void> _clearSavedSession() async {
    if (widget.editCompletedSession) {
      return;
    }
    await AppDataStore.clearCurrentSession();
  }

  List<ExerciseSet> _workSets(WorkoutExercise exercise) {
    return exercise.sets.where((set) => !set.isWarmup).toList();
  }

  bool _allWorkSetsCompleted(WorkoutExercise exercise, Exercise target) {
    final workSets = _workSets(exercise);
    final requiredSets = math.max(1, target.set);
    return workSets.length >= requiredSets &&
        workSets.every((set) => set.isCompleted);
  }

  bool _allCompletedAtTop(WorkoutExercise exercise, Exercise target) {
    if (!_allWorkSetsCompleted(exercise, target)) {
      return false;
    }
    final workSets = _workSets(exercise);
    final targetReps = target.targetMaxReps ?? target.reps;
    return workSets.every((set) => set.reps >= targetReps);
  }

  bool _anyCompletedBelowMin(WorkoutExercise exercise, Exercise target) {
    final workSets = exercise.sets.where(
      (set) => set.isCompleted && !set.isWarmup,
    );
    if (workSets.isEmpty) {
      return false;
    }
    final minReps = target.targetMinReps ?? target.reps;
    return workSets.any((set) => set.reps < minReps);
  }

  Schedule? _storedScheduleForSession(List<Schedule> schedules) {
    final scheduleId = session.scheduleId ?? widget.schedule?.id;
    if (scheduleId != null) {
      for (final schedule in schedules) {
        if (schedule.id == scheduleId) {
          return schedule;
        }
      }
    }

    final scheduleTitle = widget.schedule?.title ?? session.scheduleTitle;
    for (final schedule in schedules) {
      if (schedule.title == scheduleTitle) {
        return schedule;
      }
    }
    return null;
  }

  bool _workoutExerciseExistsInSchedule(
    WorkoutExercise workoutExercise,
    Schedule schedule,
  ) {
    for (final exercise in schedule.exercises) {
      final sameId =
          workoutExercise.sourceExerciseId != null &&
          exercise.id == workoutExercise.sourceExerciseId;
      final sameName =
          exercise.name.trim().toLowerCase() ==
          workoutExercise.name.trim().toLowerCase();
      if (sameId || sameName) {
        return true;
      }
    }
    return false;
  }

  List<WorkoutExercise> _newExercisesForSchedule(Schedule schedule) {
    return session.exercises
        .where(
          (exercise) => !_workoutExerciseExistsInSchedule(exercise, schedule),
        )
        .toList();
  }

  Future<bool> _confirmSaveAddedExercises(Schedule? schedule) async {
    if (schedule == null || !mounted) {
      return false;
    }

    final newExercises = _newExercisesForSchedule(schedule);
    if (newExercises.isEmpty) {
      return false;
    }

    final count = newExercises.length;
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          count == 1 ? 'Salvare nuovo esercizio?' : 'Salvare nuovi esercizi?',
        ),
        content: Text(
          count == 1
              ? 'Hai aggiunto ${newExercises.first.name}. Vuoi sovrascrivere la scheda ${schedule.title} con questo esercizio?'
              : 'Hai aggiunto $count esercizi. Vuoi sovrascrivere la scheda ${schedule.title} con questi esercizi?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Solo sessione'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sovrascrivi scheda'),
          ),
        ],
      ),
    );

    return result == true;
  }

  Future<void> _saveAddedExercisesToSchedule() async {
    final bundle = await AppDataStore.loadBundle();
    final storedSchedule = _storedScheduleForSession(bundle.schedules);
    if (storedSchedule == null) {
      return;
    }

    final newExercises = _newExercisesForSchedule(storedSchedule);
    if (newExercises.isEmpty) {
      return;
    }

    for (final workoutExercise in newExercises) {
      final scheduleExercise = _exerciseFromWorkoutExercise(workoutExercise);
      storedSchedule.exercises.add(scheduleExercise);
      workoutExercise.sourceExerciseId = scheduleExercise.id;
      _exerciseIdsAddedToScheduleThisFinish.add(scheduleExercise.id);
    }

    final liveSchedule = widget.schedule;
    if (liveSchedule != null &&
        (liveSchedule.id == storedSchedule.id ||
            liveSchedule.title == storedSchedule.title)) {
      liveSchedule.exercises
        ..clear()
        ..addAll(
          storedSchedule.exercises.map(
            (exercise) => Exercise.fromJson(exercise.toJson()),
          ),
        );
    }

    await AppDataStore.saveSchedules(bundle.schedules);
  }

  Future<void> _applyProgressionToSchedule() async {
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

      if (targetExercise.progressionScheme == ProgressionScheme.manual) {
        continue;
      }

      if (targetExercise.progressionScheme == ProgressionScheme.linear) {
        if (_allWorkSetsCompleted(completedExercise, targetExercise)) {
          targetExercise.weight += targetExercise.progressionKgStep;
        }
        continue;
      }

      if (targetExercise.progressionScheme == ProgressionScheme.loadOnly) {
        if (_allCompletedAtTop(completedExercise, targetExercise)) {
          targetExercise.weight += targetExercise.progressionKgStep;
        }
        continue;
      }

      if (targetExercise.progressionScheme == ProgressionScheme.repsOnly) {
        if (_allWorkSetsCompleted(completedExercise, targetExercise) &&
            !_anyCompletedBelowMin(completedExercise, targetExercise) &&
            targetExercise.targetMaxReps != null &&
            targetExercise.reps < targetExercise.targetMaxReps!) {
          targetExercise.reps = math.min(
            targetExercise.targetMaxReps!,
            targetExercise.reps + targetExercise.progressionRepStep,
          );
        }
        continue;
      }

      if (_allCompletedAtTop(completedExercise, targetExercise)) {
        targetExercise.weight += targetExercise.progressionKgStep;
      } else if (_anyCompletedBelowMin(completedExercise, targetExercise)) {
        targetExercise.weight = math.max(
          0,
          targetExercise.weight - targetExercise.progressionKgStep,
        );
      } else if (_allWorkSetsCompleted(completedExercise, targetExercise) &&
          targetExercise.targetMaxReps != null &&
          targetExercise.reps < targetExercise.targetMaxReps!) {
        targetExercise.reps = math.min(
          targetExercise.targetMaxReps!,
          targetExercise.reps + targetExercise.progressionRepStep,
        );
      }
    }

    await AppDataStore.saveSchedules(bundle.schedules);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _restTimer?.cancel();
    _durationTimer?.cancel();
    if (!widget.editCompletedSession) {
      WakelockPlus.disable();
    }
    super.dispose();
  }

  Future<void> _finishWorkout() async {
    if (widget.editCompletedSession) {
      await _saveEditedCompletedSession();
      return;
    }

    _allowCurrentSessionSaves = false;
    await _drainCurrentSessionSaves();
    await _cancelAllRestTimers();
    session.endTime = DateTime.now();

    final bundle = await AppDataStore.loadBundle();
    final saveAddedExercises = await _confirmSaveAddedExercises(
      _storedScheduleForSession(bundle.schedules),
    );
    if (saveAddedExercises) {
      await _saveAddedExercisesToSchedule();
    }

    final history = await AppDataStore.loadHistory();
    final previousHistory = List<WorkoutSession>.from(history);
    history.add(session);
    await AppDataStore.saveHistory(history);
    await _applyProgressionToSchedule();
    await AppDataStore.clearCurrentSession();

    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => SessionSummaryScreen(
            session: session,
            previousHistory: previousHistory,
          ),
        ),
      );
    }
  }

  Future<void> _saveEditedCompletedSession() async {
    final history = await AppDataStore.loadHistory();
    final index = history.indexWhere(
      (historySession) => historySession.id == session.id,
    );

    if (index == -1) {
      history.add(session);
    } else {
      history[index] = session;
    }

    await AppDataStore.saveHistory(history);
    if (mounted) {
      Navigator.pop(context, true);
    }
  }

  WorkoutSession? _previousSessionForAddedExercises() {
    WorkoutSession? latestSession;
    for (final historySession in widget.history) {
      if (historySession.id == session.id ||
          historySession.scheduleTitle != session.scheduleTitle ||
          !historySession.endTime.isBefore(session.endTime)) {
        continue;
      }

      if (latestSession == null ||
          historySession.endTime.isAfter(latestSession.endTime)) {
        latestSession = historySession;
      }
    }
    return latestSession;
  }

  void _addExercisesToSession(List<Exercise> exercises) {
    if (exercises.isEmpty) {
      return;
    }

    final previousSession = _previousSessionForAddedExercises();
    setState(() {
      session.exercises.addAll(
        exercises.map(
          (exercise) => _workoutExerciseFromExercise(
            exercise,
            previousSession,
            keepSourceExerciseId: false,
          ),
        ),
      );
    });
    _saveCurrentSession();
  }

  Future<List<Exercise>?> _pickExercisesForSession() async {
    final result = await Navigator.push<ExercisePickerResult>(
      context,
      MaterialPageRoute(builder: (context) => const ExercisePickerScreen()),
    );

    if (!mounted || result == null) {
      return null;
    }

    if (result.addCustom) {
      final customExercise = await _showCustomExerciseDialog();
      return customExercise == null ? null : [customExercise];
    }

    return [
      ...result.customExercises.map(_copyExerciseTemplate),
      ...result.entries.map(_exerciseFromCatalogEntry),
    ];
  }

  Future<void> _openExercisePicker() async {
    final exercises = await _pickExercisesForSession();
    if (!mounted || exercises == null || exercises.isEmpty) {
      return;
    }
    _addExercisesToSession(exercises);
  }

  int _nextSupersetGroupId() {
    var maxGroup = 0;
    for (final exercise in session.exercises) {
      final group = exercise.supersetGroup;
      if (group != null && group > maxGroup) {
        maxGroup = group;
      }
    }
    return maxGroup + 1;
  }

  List<WorkoutExercise> _supersetMembers(WorkoutExercise exercise) {
    final group = exercise.supersetGroup;
    if (group == null) {
      return const [];
    }
    return session.exercises
        .where((candidate) => candidate.supersetGroup == group)
        .toList();
  }

  void _cleanupSupersetGroup(int? group) {
    if (group == null) return;
    final members = session.exercises
        .where((exercise) => exercise.supersetGroup == group)
        .toList();
    if (members.length < 2) {
      for (final member in members) {
        member.supersetGroup = null;
      }
    }
  }

  bool _shouldStartRestAfterSet(WorkoutExercise exercise) {
    final members = _supersetMembers(exercise);
    return members.length < 2 || members.last.id == exercise.id;
  }

  void _advanceSupersetNavigation(WorkoutExercise exercise) {
    final members = _supersetMembers(exercise);
    if (members.length < 2) return;
    final currentIndex = members.indexWhere(
      (member) => member.id == exercise.id,
    );
    if (currentIndex < 0) return;
    final next = members[(currentIndex + 1) % members.length];
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _scrollToExercise(next.id);
      }
    });
  }

  Future<void> _replaceExercise(WorkoutExercise exercise) async {
    final replacements = await _pickExercisesForSession();
    if (!mounted || replacements == null || replacements.isEmpty) {
      return;
    }

    final index = session.exercises.indexWhere(
      (item) => item.id == exercise.id,
    );
    if (index < 0) return;

    final previousSession = _previousSessionForAddedExercises();
    final replacement = _workoutExerciseFromExercise(
      replacements.first,
      previousSession,
      keepSourceExerciseId: false,
    )..supersetGroup = exercise.supersetGroup;

    final notificationId = LocalNotificationService.restNotificationId(
      exercise.id,
    );
    setState(() {
      _restSecondsByExerciseId.remove(exercise.id);
      session.exercises[index] = replacement;
      _exerciseCardKeys.remove(exercise.id);
    });
    await LocalNotificationService.cancel(notificationId);
    await _saveCurrentSession();

    if (replacements.length > 1 && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Per la sostituzione è stato usato il primo esercizio selezionato.',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _duplicateExercise(WorkoutExercise exercise) {
    final index = session.exercises.indexWhere(
      (item) => item.id == exercise.id,
    );
    if (index < 0) return;

    final duplicate = _workoutExerciseFromExercise(
      _exerciseFromWorkoutExercise(exercise),
      null,
      keepSourceExerciseId: false,
    )..supersetGroup = null;
    duplicate.sets = exercise.sets
        .map(
          (set) => ExerciseSet(
            weight: set.weight,
            reps: set.reps,
            type: set.type,
            rpe: set.rpe,
            rir: set.rir,
            notes: set.notes,
          ),
        )
        .toList();
    duplicate.previousWeights = List<double>.from(exercise.previousWeights);
    duplicate.previousReps = List<int>.from(exercise.previousReps);

    setState(() => session.exercises.insert(index + 1, duplicate));
    HapticFeedback.selectionClick();
    _saveCurrentSession();
  }

  void _moveExercise(WorkoutExercise exercise, int delta) {
    final index = session.exercises.indexWhere(
      (item) => item.id == exercise.id,
    );
    if (index < 0) return;
    final nextIndex = index + delta;
    if (nextIndex < 0 || nextIndex >= session.exercises.length) return;

    setState(() {
      final moved = session.exercises.removeAt(index);
      session.exercises.insert(nextIndex, moved);
    });
    HapticFeedback.selectionClick();
    _saveCurrentSession();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _scrollToExercise(exercise.id);
    });
  }

  void _removeExerciseFromSession(WorkoutExercise exercise) {
    final index = session.exercises.indexWhere(
      (item) => item.id == exercise.id,
    );
    if (index < 0) return;

    final deletedGroup = exercise.supersetGroup;
    final originalGroupMembers = deletedGroup == null
        ? const <WorkoutExercise>[]
        : session.exercises
              .where((item) => item.supersetGroup == deletedGroup)
              .toList();
    final notificationId = LocalNotificationService.restNotificationId(
      exercise.id,
    );

    setState(() {
      _restSecondsByExerciseId.remove(exercise.id);
      session.exercises.removeAt(index);
      _exerciseCardKeys.remove(exercise.id);
      _cleanupSupersetGroup(deletedGroup);
    });
    LocalNotificationService.cancel(notificationId);
    _saveCurrentSession();

    _showUndoSnackBar(
      message: '${exercise.name} eliminato dalla sessione.',
      onUndo: () {
        if (!mounted ||
            session.exercises.any((item) => item.id == exercise.id)) {
          return;
        }
        setState(() {
          final restoreIndex = index.clamp(0, session.exercises.length).toInt();
          session.exercises.insert(restoreIndex, exercise);
          if (deletedGroup != null) {
            for (final member in originalGroupMembers) {
              member.supersetGroup = deletedGroup;
            }
          }
        });
        _saveCurrentSession();
      },
    );
  }

  Future<void> _configureSuperset(WorkoutExercise exercise) async {
    if (session.exercises.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Aggiungi almeno un altro esercizio per creare un superset.',
          ),
        ),
      );
      return;
    }

    final selectedId = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.only(bottom: 12),
          children: [
            ListTile(
              title: Text(
                exercise.supersetGroup == null
                    ? 'Crea superset con ${exercise.name}'
                    : 'Gestisci superset ${exercise.supersetGroup}',
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
              subtitle: const Text('Scegli un esercizio da collegare.'),
            ),
            if (exercise.supersetGroup != null)
              ListTile(
                key: ValueKey('remove-superset-${exercise.id}'),
                leading: const Icon(Icons.link_off),
                title: const Text('Rimuovi dal superset'),
                onTap: () => Navigator.pop(context, '__remove__'),
              ),
            for (final candidate in session.exercises)
              if (candidate.id != exercise.id)
                ListTile(
                  key: ValueKey('superset-target-${candidate.id}'),
                  leading: Icon(
                    candidate.supersetGroup == null ? Icons.link : Icons.hub,
                  ),
                  title: Text(candidate.name),
                  subtitle: Text(
                    candidate.supersetGroup == null
                        ? 'Nessun superset'
                        : 'Superset ${candidate.supersetGroup}',
                  ),
                  onTap: () => Navigator.pop(context, candidate.id),
                ),
          ],
        ),
      ),
    );

    if (!mounted || selectedId == null) return;

    final oldGroup = exercise.supersetGroup;
    if (selectedId == '__remove__') {
      setState(() {
        exercise.supersetGroup = null;
        _cleanupSupersetGroup(oldGroup);
      });
      _saveCurrentSession();
      return;
    }

    final targetIndex = session.exercises.indexWhere(
      (candidate) => candidate.id == selectedId,
    );
    if (targetIndex < 0) return;
    final target = session.exercises[targetIndex];

    setState(() {
      final group = target.supersetGroup ?? oldGroup ?? _nextSupersetGroupId();
      exercise.supersetGroup = group;
      target.supersetGroup = group;
      if (oldGroup != null && oldGroup != group) {
        _cleanupSupersetGroup(oldGroup);
      }
    });
    HapticFeedback.selectionClick();
    _saveCurrentSession();
  }

  Future<void> _handleWorkoutExerciseAction(
    _WorkoutExerciseAction action,
    WorkoutExercise exercise,
  ) async {
    switch (action) {
      case _WorkoutExerciseAction.replace:
        await _replaceExercise(exercise);
        break;
      case _WorkoutExerciseAction.duplicate:
        _duplicateExercise(exercise);
        break;
      case _WorkoutExerciseAction.superset:
        await _configureSuperset(exercise);
        break;
      case _WorkoutExerciseAction.moveUp:
        _moveExercise(exercise, -1);
        break;
      case _WorkoutExerciseAction.moveDown:
        _moveExercise(exercise, 1);
        break;
      case _WorkoutExerciseAction.delete:
        _removeExerciseFromSession(exercise);
        break;
    }
  }

  Future<Exercise?> _showCustomExerciseDialog() async {
    MuscleGroup? selectedMuscleGroup;
    final nameController = TextEditingController();
    final setsController = TextEditingController(text: '3');
    final repsController = TextEditingController(text: '10');
    final weightController = TextEditingController(text: '0');
    final restSecondsController = TextEditingController(
      text: widget.defaultRestSeconds.toString(),
    );
    final equipmentController = TextEditingController();
    final notesController = TextEditingController();
    String? validationMessage;
    Exercise? createdExercise;
    bool saveToCatalog = true;

    try {
      final saved = await showDialog<bool>(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: const Text('Nuovo esercizio'),
            content: AppDialogContent(
              maxWidth: 520,
              children: [
                DropdownButtonFormField<MuscleGroup>(
                  initialValue: selectedMuscleGroup,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Gruppo'),
                  items: selectableMuscleGroups
                      .map(
                        (group) => DropdownMenuItem<MuscleGroup>(
                          value: group,
                          child: Text(group.label),
                        ),
                      )
                      .toList(),
                  onChanged: (value) => setDialogState(() {
                    selectedMuscleGroup = value;
                  }),
                ),
                appDialogFieldGap,
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(labelText: 'Nome'),
                ),
                appDialogFieldGap,
                AppFieldRow(
                  children: [
                    TextField(
                      controller: setsController,
                      decoration: const InputDecoration(labelText: 'Serie'),
                      keyboardType: TextInputType.number,
                    ),
                    TextField(
                      controller: repsController,
                      decoration: const InputDecoration(labelText: 'Reps'),
                      keyboardType: TextInputType.number,
                    ),
                  ],
                ),
                appDialogFieldGap,
                AppFieldRow(
                  children: [
                    TextField(
                      controller: weightController,
                      decoration: const InputDecoration(labelText: 'Kg'),
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                    ),
                    TextField(
                      controller: restSecondsController,
                      decoration: const InputDecoration(
                        labelText: 'Recupero sec',
                      ),
                      keyboardType: TextInputType.number,
                    ),
                  ],
                ),
                appDialogFieldGap,
                TextField(
                  controller: equipmentController,
                  decoration: const InputDecoration(labelText: 'Attrezzo'),
                ),
                appDialogFieldGap,
                TextField(
                  controller: notesController,
                  decoration: const InputDecoration(labelText: 'Note'),
                ),
                appDialogFieldGap,
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Salva nel catalogo personale'),
                  value: saveToCatalog,
                  onChanged: (value) => setDialogState(() {
                    saveToCatalog = value;
                  }),
                ),
                if (validationMessage != null) ...[
                  appDialogFieldGap,
                  Text(
                    validationMessage!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Annulla'),
              ),
              ElevatedButton(
                onPressed: () {
                  final name = nameController.text.trim();
                  final sets = parseIntInput(setsController.text);
                  final reps = parseIntInput(repsController.text);
                  final weight = parseDecimalInput(weightController.text);
                  final restSeconds = parseIntInput(restSecondsController.text);

                  if (name.isEmpty ||
                      sets == null ||
                      reps == null ||
                      weight == null ||
                      restSeconds == null) {
                    setDialogState(() {
                      validationMessage =
                          'Completa nome, serie, reps, kg e recupero.';
                    });
                    return;
                  }

                  if (sets < 1 || reps < 1 || weight < 0 || restSeconds < 0) {
                    setDialogState(() {
                      validationMessage = 'Usa valori validi: serie/reps almeno 1, kg e recupero non negativi.';
                    });
                    return;
                  }

                  createdExercise = Exercise(
                    name: name,
                    set: sets,
                    reps: reps,
                    weight: weight.toDouble(),
                    muscleGroup: selectedMuscleGroup ?? MuscleGroup.unassigned,
                    equipment: equipmentController.text.trim(),
                    notes: notesController.text.trim(),
                    technique: IntensityTechnique.none,
                    restSeconds: restSeconds.clamp(0, 3600).toInt(),
                    progressionKgStep: 2.5,
                    progressionRepStep: 1,
                  );
                  Navigator.pop(context, true);
                },
                child: const Text('Aggiungi'),
              ),
            ],
          ),
        ),
      );

      if (saved == true && createdExercise != null && saveToCatalog) {
        await AppDataStore.addCustomExercise(createdExercise!);
      }
      return saved == true ? createdExercise : null;
    } finally {
      nameController.dispose();
      setsController.dispose();
      repsController.dispose();
      weightController.dispose();
      restSecondsController.dispose();
      equipmentController.dispose();
      notesController.dispose();
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

  void _copySet(WorkoutExercise exercise, int setIndex) {
    if (setIndex < 0 || setIndex >= exercise.sets.length) {
      return;
    }
    final source = exercise.sets[setIndex];
    setState(() {
      exercise.sets.insert(
        setIndex + 1,
        ExerciseSet(
          weight: source.weight,
          reps: source.reps,
          type: source.type,
          rpe: source.rpe,
          rir: source.rir,
          notes: source.notes,
        ),
      );
    });
    _saveCurrentSession();
  }

  List<String> _sessionValidationProblems() {
    final problems = <String>[];
    for (final exercise in session.exercises) {
      for (var index = 0; index < exercise.sets.length; index++) {
        final set = exercise.sets[index];
        final label = '${exercise.name} set ${index + 1}';
        if (set.weight < 0 || set.weight > 1000) {
          problems.add('$label: kg fuori range 0-1000.');
        }
        if (set.reps <= 0 || set.reps > 200) {
          problems.add('$label: reps fuori range 1-200.');
        }
        if (set.rpe != null && (set.rpe! < 1 || set.rpe! > 10)) {
          problems.add('$label: RPE fuori range 1-10.');
        }
        if (set.rir != null && (set.rir! < 0 || set.rir! > 10)) {
          problems.add('$label: RIR fuori range 0-10.');
        }
      }
    }
    return problems;
  }

  Future<void> _showValidationProblems(List<String> problems) async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Controlla dati'),
        content: AppDialogContent(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: problems
              .take(8)
              .map((problem) => Text('- $problem'))
              .toList(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Ok'),
          ),
        ],
      ),
    );
  }

  void _applyRecommendedBackoffWeight(WorkoutExercise exercise, int setIndex) {
    if (setIndex < 0 || setIndex >= exercise.sets.length) {
      return;
    }

    final recommendedWeight = _recommendedBackoffWeightFor(exercise, setIndex);
    if (recommendedWeight == null) {
      return;
    }

    final set = exercise.sets[setIndex];
    setState(() {
      set.weight = recommendedWeight;
    });
    _saveCurrentSession();
  }

  List<ExerciseSet> _warmupSetsFor(WorkoutExercise exercise) {
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

  void _insertWarmupPlan(WorkoutExercise exercise) {
    final warmups = _warmupSetsFor(exercise);
    setState(() {
      exercise.sets.removeWhere((set) => set.isWarmup && !set.isCompleted);
      exercise.sets.insertAll(0, warmups);
    });
    _saveCurrentSession();
  }

  void _showWarmupPlan(WorkoutExercise exercise) {
    final warmups = _warmupSetsFor(exercise);
    final rows = warmups
        .map((set) => '${_formatWeight(set.weight)} kg x ${set.reps}')
        .toList();

    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Warm-up ${exercise.name}'),
        content: AppDialogContent(
          maxWidth: 420,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: rows.map((row) => Text(row)).toList(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Chiudi'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _insertWarmupPlan(exercise);
            },
            child: const Text('Aggiungi warm-up'),
          ),
        ],
      ),
    );
  }

  void _toggleSetCompleted(
    WorkoutExercise exercise,
    ExerciseSet set,
    int setIndex,
  ) {
    final willComplete = !set.isCompleted;
    setState(() {
      set.isCompleted = !set.isCompleted;
    });
    _saveCurrentSession();
    if (willComplete && !widget.editCompletedSession) {
      if (_shouldStartRestAfterSet(exercise)) {
        _startRestForExercise(exercise);
      }
      _advanceSupersetNavigation(exercise);
    }

    final delta = _setVolumeDelta(exercise, set, setIndex);
    if (willComplete && delta != null && delta > 0 && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.emoji_events, color: Colors.amber),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${exercise.name}: volume set migliorato +${_formatVolume(delta)} kg.',
                ),
              ),
            ],
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
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
          content: AppDialogContent(
            maxWidth: 480,
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Warm-up'),
                value: isWarmup,
                onChanged: (value) => setDialogState(() => isWarmup = value),
              ),
              AppFieldRow(
                children: [
                  TextField(
                    controller: rpeController,
                    decoration: const InputDecoration(labelText: 'RPE (1-10)'),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                  ),
                  TextField(
                    controller: rirController,
                    decoration: const InputDecoration(labelText: 'RIR (0-10)'),
                    keyboardType: TextInputType.number,
                  ),
                ],
              ),
              appDialogFieldGap,
              TextField(
                controller: notesController,
                decoration: const InputDecoration(labelText: 'Note set'),
                minLines: 1,
                maxLines: 3,
              ),
            ],
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
    final isDark = theme.brightness == Brightness.dark;
    final compactInputBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide(color: colorScheme.outlineVariant),
    );
    final stats = _workoutStats;
    final activeRestExercise = _activeRestExercise();
    final activeRestSeconds = activeRestExercise == null
        ? null
        : _restSecondsByExerciseId[activeRestExercise.id];

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final navigator = Navigator.of(context);
        final confirm = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(
              widget.editCompletedSession
                  ? 'Uscire dalla modifica?'
                  : 'Annullare allenamento?',
            ),
            content: Text(
              widget.editCompletedSession
                  ? 'Le modifiche non salvate andranno perse.'
                  : 'I progressi non salvati andranno persi.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Continua'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(widget.editCompletedSession ? 'Esci' : 'Annulla'),
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
                    title: Text(
                      widget.editCompletedSession
                          ? 'Uscire dalla modifica?'
                          : 'Annullare allenamento?',
                    ),
                    content: Text(
                      widget.editCompletedSession
                          ? 'Le modifiche non salvate andranno perse.'
                          : 'I progressi non salvati andranno persi.',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('Continua'),
                      ),
                      ElevatedButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: Text(
                          widget.editCompletedSession ? 'Esci' : 'Annulla',
                        ),
                      ),
                    ],
                  ),
                );

                if (confirm != true) return;

                await _clearSavedSession();
                if (mounted) navigator.pop();
              },
              style: TextButton.styleFrom(foregroundColor: colorScheme.error),
              child: Text(widget.editCompletedSession ? 'Chiudi' : 'Stop'),
            ),
            TextButton(
              onPressed: () async {
                final problems = _sessionValidationProblems();
                if (problems.isNotEmpty) {
                  await _showValidationProblems(problems);
                  return;
                }

                final duration = _formatDuration(_elapsedSeconds);
                final prCount = _sessionPrCount();

                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: Text(
                      widget.editCompletedSession
                          ? 'Salvare modifiche?'
                          : 'Riepilogo allenamento',
                    ),
                    content: AppDialogContent(
                      maxWidth: 420,
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
                        _summaryRow('PR rilevati', '$prCount'),
                        Text(
                          prCount > 0
                              ? 'Record salvati nello storico esercizi.'
                              : 'Nessun record rispetto allo storico.',
                          style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                            color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('Annulla'),
                      ),
                      ElevatedButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: Text(
                          widget.editCompletedSession
                              ? 'Salva modifiche'
                              : 'Salva',
                        ),
                      ),
                    ],
                  ),
                );

                if (confirm != true) return;

                await _finishWorkout();
              },
              style: TextButton.styleFrom(foregroundColor: colorScheme.primary),
              child: Text(widget.editCompletedSession ? 'Salva' : 'Fine'),
            ),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(22),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
                child: Text(
                  _saveStatusLabel(),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ),
        ),
        body: ListView.builder(
          padding: const EdgeInsets.only(bottom: 96),
          itemCount:
              session.exercises.length + (session.exercises.length > 1 ? 1 : 0),
          itemBuilder: (context, itemIndex) {
            if (session.exercises.length > 1 && itemIndex == 0) {
              return _ExerciseJumpBar(
                exercises: session.exercises,
                onSelected: _scrollToExercise,
              );
            }

            final exIndex = session.exercises.length > 1
                ? itemIndex - 1
                : itemIndex;
            final exercise = session.exercises[exIndex];
            final activeRestSeconds = _restSecondsByExerciseId[exercise.id];
            final restSeconds = activeRestSeconds ?? _restSecondsFor(exercise);
            final accent = _accentForIndex(colorScheme, exIndex);

            return Card(
              key: _exerciseCardKey(exercise.id),
              margin: const EdgeInsets.fromLTRB(8, 5, 8, 5),
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      accent.withValues(alpha: isDark ? 0.18 : 0.10),
                      Colors.transparent,
                    ],
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(10.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              exercise.name,
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w900,
                                color: accent,
                              ),
                            ),
                          ),
                          PopupMenuButton<_WorkoutExerciseAction>(
                            key: ValueKey('exercise-menu-${exercise.id}'),
                            tooltip: 'Azioni esercizio',
                            onSelected: (action) =>
                                _handleWorkoutExerciseAction(action, exercise),
                            itemBuilder: (context) => [
                              const PopupMenuItem(
                                value: _WorkoutExerciseAction.replace,
                                child: ListTile(
                                  leading: Icon(Icons.swap_horiz),
                                  title: Text('Sostituisci'),
                                ),
                              ),
                              const PopupMenuItem(
                                value: _WorkoutExerciseAction.duplicate,
                                child: ListTile(
                                  leading: Icon(Icons.copy_all),
                                  title: Text('Duplica'),
                                ),
                              ),
                              PopupMenuItem(
                                value: _WorkoutExerciseAction.superset,
                                child: ListTile(
                                  leading: const Icon(Icons.link),
                                  title: Text(
                                    exercise.supersetGroup == null
                                        ? 'Crea superset'
                                        : 'Gestisci superset',
                                  ),
                                ),
                              ),
                              PopupMenuItem(
                                value: _WorkoutExerciseAction.moveUp,
                                enabled: exIndex > 0,
                                child: const ListTile(
                                  leading: Icon(Icons.arrow_upward),
                                  title: Text('Sposta su'),
                                ),
                              ),
                              PopupMenuItem(
                                value: _WorkoutExerciseAction.moveDown,
                                enabled: exIndex < session.exercises.length - 1,
                                child: const ListTile(
                                  leading: Icon(Icons.arrow_downward),
                                  title: Text('Sposta giù'),
                                ),
                              ),
                              PopupMenuItem(
                                value: _WorkoutExerciseAction.delete,
                                child: ListTile(
                                  leading: Icon(
                                    Icons.delete_outline,
                                    color: colorScheme.error,
                                  ),
                                  title: Text(
                                    'Elimina',
                                    style: TextStyle(color: colorScheme.error),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
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
                            label: Text(_targetLabelFor(exercise)),
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
                          if (exercise.supersetGroup != null)
                            Chip(
                              avatar: const Icon(Icons.link, size: 18),
                              label: Text('Superset ${exercise.supersetGroup}'),
                              visualDensity: VisualDensity.compact,
                            ),
                          Chip(
                            label: Text(exercise.progressionScheme.label),
                            visualDensity: VisualDensity.compact,
                          ),
                          if (widget.schedule?.isDeloadWeek() ?? false)
                            Chip(
                              avatar: const Icon(Icons.trending_down, size: 18),
                              label: const Text('Deload -10%'),
                              visualDensity: VisualDensity.compact,
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        key: ValueKey('exercise-notes-${exercise.id}'),
                        initialValue: exercise.notes,
                        minLines: 1,
                        maxLines: 3,
                        decoration: InputDecoration(
                          labelText: 'Note esercizio',
                          hintText: 'Tecnica, setup, cue...',
                          isDense: true,
                          border: compactInputBorder,
                          enabledBorder: compactInputBorder,
                          focusedBorder: compactInputBorder.copyWith(
                            borderSide: BorderSide(
                              color: colorScheme.primary,
                              width: 1.5,
                            ),
                          ),
                        ),
                        onChanged: (value) {
                          exercise.notes = value;
                          _saveCurrentSessionSilently();
                        },
                      ),
                      if (exercise.previousWeights.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          _formatPreviousWeights(exercise.previousWeights),
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
                          Icon(Icons.timer, size: 18, color: accent),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              activeRestSeconds == null
                                  ? 'Timer recupero'
                                  : 'Rest ${_formatDuration(restSeconds)}',
                              style: theme.textTheme.bodyMedium,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          SizedBox(
                            width: 96,
                            child: TextFormField(
                              key: ValueKey('rest-${exercise.id}'),
                              initialValue: _restSecondsFor(exercise)
                                  .toString(),
                              keyboardType: TextInputType.number,
                              textAlign: TextAlign.center,
                              decoration: InputDecoration(
                                labelText: 'sec',
                                isDense: true,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 10,
                                ),
                                border: compactInputBorder,
                                enabledBorder: compactInputBorder,
                                focusedBorder: compactInputBorder.copyWith(
                                  borderSide: BorderSide(
                                    color: colorScheme.primary,
                                    width: 1.5,
                                  ),
                                ),
                              ),
                              onChanged: (value) =>
                                  _updateExerciseRestSeconds(exercise, value),
                            ),
                          ),
                          IconButton(
                            tooltip: activeRestSeconds == null
                                ? 'Avvia recupero'
                                : 'Aggiungi 30 secondi',
                            onPressed: activeRestSeconds == null
                                ? () => _startRestForExercise(exercise)
                                : () => _addThirtySeconds(exercise),
                            icon: Icon(
                              activeRestSeconds == null
                                  ? Icons.play_arrow
                                  : Icons.add,
                            ),
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
                              '#',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ),
                          Expanded(
                            child: Center(
                              child: Text(
                                'kg',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ),
                          ),
                          Expanded(
                            child: Center(
                              child: Text(
                                'reps',
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
                            exercise.technique ==
                                IntensityTechnique.topsetBackoff
                            ? (setIndex == 0 ? 'Top Set' : 'Back off')
                            : '${setIndex + 1}';
                        final displaySetLabel = exSet.type == SetType.normal
                            ? setLabel
                            : '${exSet.type.shortLabel} $setLabel';
                        final setVolumeDelta = _setVolumeDelta(
                          exercise,
                          exSet,
                          setIndex,
                        );
                        final backoffHint = _backoffHintFor(exercise, setIndex);
                        final previousSetLabel = _previousSetLabelFor(
                          exercise,
                          setIndex,
                        );
                        final nextSetHint = _nextSetHintFor(
                          exercise,
                          exSet,
                          setIndex,
                        );
                        final prLabels = _personalRecordLabelsFor(
                          exercise,
                          exSet,
                          setIndex,
                        );
                        return Dismissible(
                          key: ValueKey(exSet.id),
                          direction: DismissDirection.endToStart,
                          onDismissed: (_) => _removeSet(exercise, setIndex),
                          background: Container(
                            margin: const EdgeInsets.symmetric(vertical: 3),
                            decoration: BoxDecoration(
                              color: colorScheme.errorContainer,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            alignment: Alignment.centerRight,
                            padding: const EdgeInsets.only(right: 20),
                            child: Icon(
                              Icons.delete,
                              color: colorScheme.onErrorContainer,
                            ),
                          ),
                          child: Container(
                            margin: const EdgeInsets.symmetric(vertical: 3),
                            padding: const EdgeInsets.symmetric(vertical: 5.0),
                            decoration: BoxDecoration(
                              color: exSet.isCompleted
                                  ? colorScheme.tertiaryContainer.withValues(
                                      alpha: isDark ? 0.38 : 0.62,
                                    )
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: exSet.isCompleted
                                    ? colorScheme.tertiary.withValues(
                                        alpha: 0.35,
                                      )
                                    : Colors.transparent,
                              ),
                            ),
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
                                        child: _StableSetTextField(
                                          key: ValueKey('${exSet.id}-weight'),
                                          text: _formatWeight(exSet.weight),
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
                                            final parsedWeight =
                                                parseDecimalInput(value);
                                            if (parsedWeight == null) {
                                              return;
                                            }
                                            final normalizedWeight =
                                                parsedWeight
                                                    .clamp(0, 1000)
                                                    .toDouble();
                                            if (exercise.technique ==
                                                    IntensityTechnique
                                                        .topsetBackoff &&
                                                setIndex == 0) {
                                              setState(() {
                                                exSet.weight = normalizedWeight;
                                              });
                                            } else {
                                              exSet.weight = normalizedWeight;
                                            }
                                            _saveCurrentSessionSilently();
                                          },
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8.0,
                                        ),
                                        child: _StableSetTextField(
                                          key: ValueKey('${exSet.id}-reps'),
                                          text: exSet.reps.toString(),
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
                                            final parsedReps = parseIntInput(
                                              value,
                                            );
                                            if (parsedReps == null) {
                                              return;
                                            }
                                            exSet.reps = parsedReps
                                                .clamp(0, 200)
                                                .toInt();
                                            _saveCurrentSessionSilently();
                                          },
                                        ),
                                      ),
                                    ),
                                    InkWell(
                                      onTap: () => _toggleSetCompleted(
                                        exercise,
                                        exSet,
                                        setIndex,
                                      ),
                                      child: Container(
                                        width: 40,
                                        height: 36,
                                        decoration: BoxDecoration(
                                          color: exSet.isCompleted
                                              ? colorScheme.tertiary
                                              : colorScheme
                                                    .surfaceContainerHighest,
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
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
                                if (previousSetLabel != null)
                                  Padding(
                                    padding: const EdgeInsets.only(
                                      left: 72,
                                      top: 4,
                                    ),
                                    child: ActionChip(
                                      avatar: const Icon(
                                        Icons.history,
                                        size: 16,
                                      ),
                                      label: Text(previousSetLabel),
                                      tooltip:
                                          'Usa i valori dell’ultima sessione',
                                      visualDensity: VisualDensity.compact,
                                      onPressed: () => _applyPreviousSetValues(
                                        exercise,
                                        setIndex,
                                      ),
                                    ),
                                  ),
                                if (nextSetHint != null)
                                  Padding(
                                    padding: const EdgeInsets.only(
                                      left: 72,
                                      top: 2,
                                    ),
                                    child: Text(
                                      nextSetHint,
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(
                                            color: colorScheme.primary,
                                            fontWeight: FontWeight.w600,
                                          ),
                                    ),
                                  ),
                                if (setVolumeDelta != null &&
                                    setVolumeDelta > 0)
                                  Padding(
                                    padding: const EdgeInsets.only(
                                      left: 72,
                                      top: 4,
                                    ),
                                    child: Chip(
                                      avatar: Icon(
                                        Icons.emoji_events,
                                        color: colorScheme.tertiary,
                                        size: 18,
                                      ),
                                      label: Text(
                                        'Volume +${_formatVolume(setVolumeDelta)} kg',
                                      ),
                                    ),
                                  ),
                                if (backoffHint != null)
                                  Padding(
                                    padding: const EdgeInsets.only(
                                      left: 72,
                                      top: 4,
                                    ),
                                    child: ActionChip(
                                      avatar: const Icon(
                                        Icons.touch_app,
                                        size: 16,
                                      ),
                                      label: Text(backoffHint),
                                      visualDensity: VisualDensity.compact,
                                      onPressed: () =>
                                          _applyRecommendedBackoffWeight(
                                            exercise,
                                            setIndex,
                                          ),
                                    ),
                                  ),
                                if (prLabels.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(
                                      left: 72,
                                      top: 4,
                                    ),
                                    child: Wrap(
                                      spacing: 6,
                                      runSpacing: 4,
                                      children: prLabels
                                          .map(
                                            (label) => Chip(
                                              avatar: Icon(
                                                Icons.emoji_events,
                                                color: colorScheme.tertiary,
                                                size: 18,
                                              ),
                                              label: Text(label),
                                              visualDensity:
                                                  VisualDensity.compact,
                                            ),
                                          )
                                          .toList(),
                                    ),
                                  ),
                                Padding(
                                  padding: const EdgeInsets.only(
                                    left: 72,
                                    top: 4,
                                  ),
                                  child: Wrap(
                                    spacing: 6,
                                    runSpacing: 4,
                                    crossAxisAlignment:
                                        WrapCrossAlignment.center,
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
                                        avatar: const Icon(
                                          Icons.calculate,
                                          size: 16,
                                        ),
                                        label: const Text('Piastre'),
                                        tooltip: 'Plate calculator',
                                        visualDensity: VisualDensity.compact,
                                        onPressed: () =>
                                            showWorkoutPlateCalculator(
                                              context,
                                              initialWeight: exSet.weight,
                                            ),
                                      ),
                                      if (exSet.notes.trim().isNotEmpty)
                                        Chip(
                                          avatar: const Icon(
                                            Icons.notes,
                                            size: 16,
                                          ),
                                          label: Text(exSet.notes),
                                          visualDensity: VisualDensity.compact,
                                        ),
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
                            label: const Text('serie'),
                          ),
                          TextButton.icon(
                            onPressed: exercise.sets.isEmpty
                                ? null
                                : () => _copySet(
                                    exercise,
                                    exercise.sets.length - 1,
                                  ),
                            icon: const Icon(Icons.copy),
                            label: const Text('copia ultimo'),
                          ),
                          TextButton.icon(
                            onPressed: () => _addSet(exercise, isWarmup: true),
                            icon: const Icon(Icons.local_fire_department),
                            label: const Text('warm-up'),
                          ),
                          TextButton.icon(
                            onPressed: () => _showWarmupPlan(exercise),
                            icon: const Icon(Icons.calculate),
                            label: const Text('warm-up calc'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
        bottomNavigationBar:
            activeRestExercise == null || activeRestSeconds == null
            ? null
            : SafeArea(
                top: false,
                child: Container(
                  margin: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
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
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                              ),
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
                        onPressed: () =>
                            _subtractThirtySeconds(activeRestExercise),
                        icon: const Icon(Icons.remove),
                      ),
                      IconButton(
                        tooltip: '+30 sec',
                        onPressed: () => _addThirtySeconds(activeRestExercise),
                        icon: const Icon(Icons.add),
                      ),
                      TextButton(
                        onPressed: () =>
                            _stopRestForExercise(activeRestExercise),
                        child: const Text('Salta'),
                      ),
                    ],
                  ),
                ),
              ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _openExercisePicker,
          icon: const Icon(Icons.add),
          label: const Text('Esercizio'),
        ),
      ),
    );
  }
}

class _ExerciseJumpBar extends StatelessWidget {
  final List<WorkoutExercise> exercises;
  final ValueChanged<String> onSelected;

  const _ExerciseJumpBar({required this.exercises, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: SizedBox(
        height: 58,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          itemBuilder: (context, index) {
            final exercise = exercises[index];
            return ActionChip(
              avatar: Icon(
                Icons.keyboard_arrow_down,
                color: colorScheme.primary,
              ),
              label: Text(exercise.name),
              onPressed: () => onSelected(exercise.id),
            );
          },
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemCount: exercises.length,
        ),
      ),
    );
  }
}

class _StableSetTextField extends StatefulWidget {
  final String text;
  final TextInputType keyboardType;
  final TextAlign textAlign;
  final InputDecoration decoration;
  final ValueChanged<String> onChanged;

  const _StableSetTextField({
    super.key,
    required this.text,
    required this.keyboardType,
    required this.textAlign,
    required this.decoration,
    required this.onChanged,
  });

  @override
  State<_StableSetTextField> createState() => _StableSetTextFieldState();
}

class _StableSetTextFieldState extends State<_StableSetTextField> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.text);
    _focusNode = FocusNode();
  }

  @override
  void didUpdateWidget(covariant _StableSetTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_focusNode.hasFocus && _controller.text != widget.text) {
      _controller.text = widget.text;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: _controller,
      focusNode: _focusNode,
      keyboardType: widget.keyboardType,
      textInputAction: TextInputAction.next,
      textAlign: widget.textAlign,
      decoration: widget.decoration,
      onChanged: widget.onChanged,
    );
  }
}
