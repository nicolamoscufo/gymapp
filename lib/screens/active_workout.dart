import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../app_data_store.dart';
import '../models/exercise.dart';
import '../models/schedule.dart';
import '../models/workout.dart';
import '../number_input.dart';
import '../top_set_backoff.dart';

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
    this.history = const [],
    required this.defaultRestSeconds,
  }) : schedule = null,
       assert(resumedSession != null);

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
  final Map<String, int> _weightFieldVersions = {};
  DateTime? _lastSavedAt;
  bool _isSaving = false;

  Color _accentForIndex(ColorScheme colorScheme, int index) {
    final accents = [
      colorScheme.primary,
      colorScheme.secondary,
      colorScheme.tertiary,
      colorScheme.error,
    ];
    return accents[index % accents.length];
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

    final topSet = exercise.sets.first;
    return backoffReductionPercentFor(rpe: topSet.rpe, rir: topSet.rir);
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

    return recommendedBackoffWeight(topSetWeight, reductionPercent: reduction);
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
    if (_isSaving) {
      return 'Salvataggio...';
    }
    final savedAt = _lastSavedAt;
    if (savedAt == null) {
      return 'Autosave attivo';
    }
    return 'Salvato ${savedAt.hour.toString().padLeft(2, '0')}:${savedAt.minute.toString().padLeft(2, '0')}';
  }

  String _plateSummaryFor(double targetWeight, {double barWeight = 20}) {
    final perSide = ((targetWeight - barWeight) / 2).clamp(0, 999).toDouble();
    var remaining = perSide;
    final plates = <String>[];
    for (final plate in const [25, 20, 15, 10, 5, 2.5, 1.25]) {
      final count = remaining ~/ plate;
      if (count > 0) {
        plates.add('${count}x ${_formatWeight(plate.toDouble())}');
        remaining -= count * plate;
      }
    }
    return plates.isEmpty ? 'nessun disco' : plates.join(' + ');
  }

  double _setVolume(ExerciseSet set) => set.weight * set.reps;

  double _completedExerciseVolume(WorkoutExercise exercise) {
    return exercise.sets
        .where((set) => set.isCompleted && !set.isWarmup)
        .fold<double>(0, (total, set) => total + _setVolume(set));
  }

  Iterable<WorkoutExercise> _historicalExercisesFor(WorkoutExercise exercise) {
    final exerciseName = _normalizeExerciseName(exercise.name);
    return widget.history.expand((session) {
      return session.exercises.where(
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
    if (exercise.previousWeights.isEmpty || exercise.previousReps.isEmpty) {
      return null;
    }

    final minReps = exercise.targetMinReps;
    final maxReps = exercise.targetMaxReps;
    if (minReps == null || maxReps == null) {
      return 'Progressione auto: riparti dai carichi dell ultima volta.';
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
    _ensureRestTimerRunning();
    _saveCurrentSession();
  }

  void _stopRestForExercise(WorkoutExercise exercise) {
    setState(() {
      _restSecondsByExerciseId.remove(exercise.id);
      exercise.activeRestSeconds = null;
      exercise.activeRestStartedAt = null;
    });

    if (_restSecondsByExerciseId.isEmpty) {
      _restTimer?.cancel();
      _restTimer = null;
    }
    _saveCurrentSession();
  }

  void _updateExerciseRestSeconds(WorkoutExercise exercise, String value) {
    final parsedSeconds = parseIntInput(value);
    if (parsedSeconds == null) {
      return;
    }

    final normalizedSeconds = parsedSeconds.clamp(0, 3600).toInt();
    setState(() {
      exercise.restSeconds = normalizedSeconds;
      if (_restSecondsByExerciseId.containsKey(exercise.id)) {
        _restSecondsByExerciseId[exercise.id] = normalizedSeconds;
        exercise.activeRestSeconds = normalizedSeconds;
        exercise.activeRestStartedAt = DateTime.now();
      }
    });
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
      _restoreRestTimersFromSession(notifyExpired: true);
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WakelockPlus.enable();
    if (widget.resumedSession != null) {
      session = widget.resumedSession!;
      _restoreRestTimersFromSession();
    } else if (widget.schedule != null) {
      final previousSession = _latestSessionForSchedule(widget.schedule!);
      session = WorkoutSession(
        scheduleId: widget.schedule!.id,
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
            sourceExerciseId: exercise.id,
            name: exercise.name,
            notes: exercise.notes,
            muscleGroup: exercise.muscleGroup,
            equipment: exercise.equipment,
            movementPattern: exercise.movementPattern,
            targetMinReps: exercise.targetMinReps,
            targetMaxReps: exercise.targetMaxReps,
            technique: exercise.technique,
            restSeconds: exercise.restSeconds,
            supersetGroup: exercise.supersetGroup,
            progressionKgStep: exercise.progressionKgStep,
            progressionRepStep: exercise.progressionRepStep,
            sets: _setsForExercise(exercise, previousWeights),
            previousWeights: previousWeights,
            previousReps: previousReps,
          );
        }).toList(),
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
      _restoreRestTimersFromSession();
    } else {
      await _clearSavedSession();
    }
  }

  Future<void> _saveCurrentSession() async {
    if (mounted) {
      setState(() => _isSaving = true);
    }
    await AppDataStore.saveCurrentSession(session);
    if (mounted) {
      setState(() {
        _lastSavedAt = DateTime.now();
        _isSaving = false;
      });
    }
  }

  Future<void> _clearSavedSession() async {
    await AppDataStore.clearCurrentSession();
  }

  bool _allCompletedAtTop(WorkoutExercise exercise, Exercise target) {
    final workSets = exercise.sets.where(
      (set) => set.isCompleted && !set.isWarmup,
    );
    if (workSets.isEmpty) {
      return false;
    }
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

  Future<void> _applyProgressionToSchedule() async {
    final sourceSchedule = widget.schedule;
    if (sourceSchedule == null) {
      return;
    }

    final bundle = await AppDataStore.loadBundle();
    Schedule? storedSchedule;
    for (final schedule in bundle.schedules) {
      if (schedule.id == sourceSchedule.id ||
          schedule.title == sourceSchedule.title) {
        storedSchedule = schedule;
        break;
      }
    }
    if (storedSchedule == null) {
      return;
    }

    for (final completedExercise in session.exercises) {
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

      if (_allCompletedAtTop(completedExercise, targetExercise)) {
        targetExercise.weight += targetExercise.progressionKgStep;
      } else if (_anyCompletedBelowMin(completedExercise, targetExercise)) {
        targetExercise.weight = math.max(
          0,
          targetExercise.weight - targetExercise.progressionKgStep,
        );
      } else if (targetExercise.targetMaxReps != null &&
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
    WakelockPlus.disable();
    super.dispose();
  }

  Future<void> _finishWorkout() async {
    session.endTime = DateTime.now();

    final history = await AppDataStore.loadHistory();
    history.add(session);
    await AppDataStore.saveHistory(history);
    await _applyProgressionToSchedule();
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
      _weightFieldVersions[set.id] = (_weightFieldVersions[set.id] ?? 0) + 1;
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

  void _addQuickSetNote(ExerciseSet set, String note) {
    final notes = set.notes
        .split(' • ')
        .map((entry) => entry.trim())
        .where((entry) => entry.isNotEmpty)
        .toList();
    if (!notes.contains(note)) {
      notes.add(note);
    }
    setState(() {
      set.notes = notes.join(' • ');
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
        content: Column(
          mainAxisSize: MainAxisSize.min,
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
    final isDark = theme.brightness == Brightness.dark;
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
              child: const Text('Stop'),
            ),
            TextButton(
              onPressed: () async {
                final duration = _formatDuration(_elapsedSeconds);
                final prCount = _sessionPrCount();

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
                        child: const Text('Salva'),
                      ),
                    ],
                  ),
                );

                if (confirm != true) return;

                await _finishWorkout();
              },
              style: TextButton.styleFrom(foregroundColor: colorScheme.primary),
              child: const Text('Fine'),
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
          padding: const EdgeInsets.only(bottom: 16),
          itemCount: session.exercises.length,
          itemBuilder: (context, exIndex) {
            final exercise = session.exercises[exIndex];
            final activeRestSeconds = _restSecondsByExerciseId[exercise.id];
            final restSeconds = activeRestSeconds ?? _restSecondsFor(exercise);
            final accent = _accentForIndex(colorScheme, exIndex);

            return Card(
              margin: const EdgeInsets.fromLTRB(12, 8, 12, 8),
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
                  padding: const EdgeInsets.all(14.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        exercise.name,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          color: accent,
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
                          if (widget.schedule?.isDeloadWeek() ?? false)
                            Chip(
                              avatar: const Icon(Icons.trending_down, size: 18),
                              label: const Text('Deload -10%'),
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
                            width: 86,
                            child: TextFormField(
                              key: ValueKey('rest-${exercise.id}'),
                              initialValue: _restSecondsFor(
                                exercise,
                              ).toString(),
                              keyboardType: TextInputType.number,
                              textAlign: TextAlign.center,
                              decoration: InputDecoration(
                                labelText: 'sec',
                                isDense: true,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 8,
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
                        final displaySetLabel = exSet.isWarmup
                            ? 'W $setLabel'
                            : setLabel;
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
                        final plateSummary = exSet.weight <= 0
                            ? null
                            : _plateSummaryFor(exSet.weight);

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
                                        child: TextFormField(
                                          key: ValueKey(
                                            '${exSet.id}-weight-${_weightFieldVersions[exSet.id] ?? 0}',
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
                                            final parsedWeight =
                                                parseDecimalInput(value) ?? 0.0;
                                            if (exercise.technique ==
                                                    IntensityTechnique
                                                        .topsetBackoff &&
                                                setIndex == 0) {
                                              setState(() {
                                                exSet.weight = parsedWeight;
                                              });
                                            } else {
                                              exSet.weight = parsedWeight;
                                            }
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
                                if (plateSummary != null)
                                  Padding(
                                    padding: const EdgeInsets.only(
                                      left: 72,
                                      top: 2,
                                    ),
                                    child: Text(
                                      'Dischi: $plateSummary per lato',
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(
                                            color: colorScheme.onSurfaceVariant,
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
                                Padding(
                                  padding: const EdgeInsets.only(
                                    left: 72,
                                    top: 4,
                                  ),
                                  child: PopupMenuButton<String>(
                                    tooltip: 'Note rapide',
                                    onSelected: (note) =>
                                        _addQuickSetNote(exSet, note),
                                    itemBuilder: (context) => const [
                                      PopupMenuItem(
                                        value: 'facile',
                                        child: Text('facile'),
                                      ),
                                      PopupMenuItem(
                                        value: 'duro',
                                        child: Text('duro'),
                                      ),
                                      PopupMenuItem(
                                        value: 'dolore',
                                        child: Text('dolore'),
                                      ),
                                      PopupMenuItem(
                                        value: 'tecnica ok',
                                        child: Text('tecnica ok'),
                                      ),
                                    ],
                                    child: Chip(
                                      avatar: Icon(
                                        Icons.note_add,
                                        color: colorScheme.primary,
                                        size: 16,
                                      ),
                                      label: const Text('note rapida'),
                                      visualDensity: VisualDensity.compact,
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
                                if (exSet.rpe != null ||
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
                            label: const Text('set'),
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
      ),
    );
  }
}
