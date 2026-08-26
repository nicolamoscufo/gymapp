import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../active_workout_exercise_manager.dart';
import '../active_workout_insights.dart';
import '../active_workout_rest_controller.dart';
import '../active_workout_schedule_sync.dart';
import '../active_workout_session_builder.dart';
import '../active_workout_session_controller.dart';
import '../active_workout_set_manager.dart';
import '../app_data_store.dart';
import '../dialog_form.dart';
import '../exercise_catalog.dart';
import '../local_notifications.dart';
import '../models/body_log.dart';
import '../models/exercise.dart';
import '../models/schedule.dart';
import '../models/workout.dart';
import '../number_input.dart';
import '../top_set_backoff.dart' as top_set_backoff;
import '../workout_fatigue_analytics.dart';
import '../workout_plate_calculator.dart';
import '../workout_progression_analytics.dart';
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
  final List<BodyLog> bodyLogs;
  final int defaultRestSeconds;
  final double defaultBackoffReductionPercent;
  final bool editCompletedSession;

  const ActiveWorkoutScreen({
    super.key,
    required this.schedule,
    this.history = const [],
    this.bodyLogs = const [],
    required this.defaultRestSeconds,
    this.defaultBackoffReductionPercent =
        top_set_backoff.defaultBackoffReductionPercent,
  }) : resumedSession = null,
       editCompletedSession = false;

  const ActiveWorkoutScreen.resume({
    super.key,
    required this.resumedSession,
    this.history = const [],
    this.bodyLogs = const [],
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
    this.bodyLogs = const [],
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
  late List<BodyLog> _bodyLogs;
  Timer? _durationTimer;
  int _elapsedSeconds = 0;
  final Map<String, GlobalKey> _exerciseCardKeys = {};
  final Map<String, GlobalKey> _setRowKeys = {};
  final ScrollController _workoutScrollController = ScrollController();
  String? _handoffSetId;
  bool _handoffPulseEmphasis = false;
  Timer? _handoffPulseTimer;
  Timer? _handoffClearTimer;
  final Set<String> _exerciseIdsAddedToScheduleThisFinish = {};
  int _prBannerGeneration = 0;
  Timer? _prBannerTimer;
  final ActiveWorkoutSessionController _sessionPersistence =
      ActiveWorkoutSessionController();
  late final ActiveWorkoutRestController _restController =
      ActiveWorkoutRestController(
        exercises: () => session.exercises,
        restSecondsFor: (exercise) =>
            exercise.restSeconds ?? widget.defaultRestSeconds,
        onChanged: _notifyRestControllerChanged,
        onFinished: _handleRestFinished,
      );

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

  GlobalKey _setRowKey(String setId) {
    return _setRowKeys.putIfAbsent(setId, GlobalKey.new);
  }

  Future<void> _scrollToSet(String exerciseId, String setId) async {
    var setContext = _setRowKeys[setId]?.currentContext;
    if (setContext != null) {
      await Scrollable.ensureVisible(
        setContext,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
        alignment: 0.28,
      );
      return;
    }

    final exerciseContext = _exerciseCardKeys[exerciseId]?.currentContext;
    if (exerciseContext != null) {
      await Scrollable.ensureVisible(
        exerciseContext,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
        alignment: 0.08,
      );
      await Future<void>.delayed(const Duration(milliseconds: 24));
      setContext = _setRowKeys[setId]?.currentContext;
      if (setContext != null) {
        await Scrollable.ensureVisible(
          setContext,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          alignment: 0.28,
        );
      }
      return;
    }

    if (!_workoutScrollController.hasClients || session.exercises.isEmpty) {
      return;
    }
    final exerciseIndex = session.exercises.indexWhere(
      (exercise) => exercise.id == exerciseId,
    );
    if (exerciseIndex < 0) return;

    final position = _workoutScrollController.position;
    final fraction = session.exercises.length <= 1
        ? 0.0
        : exerciseIndex / (session.exercises.length - 1);
    await _workoutScrollController.animateTo(
      position.maxScrollExtent * fraction,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
    await Future<void>.delayed(const Duration(milliseconds: 24));

    final revealedExerciseContext =
        _exerciseCardKeys[exerciseId]?.currentContext;
    if (revealedExerciseContext != null) {
      await Scrollable.ensureVisible(
        revealedExerciseContext,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        alignment: 0.08,
      );
    }
    await Future<void>.delayed(const Duration(milliseconds: 24));
    setContext = _setRowKeys[setId]?.currentContext;
    if (setContext != null) {
      await Scrollable.ensureVisible(
        setContext,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        alignment: 0.28,
      );
    }
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

  String? _backoffHintFor(WorkoutExercise exercise, int setIndex) {
    final reduction = _setManager.backoffReductionFor(exercise, setIndex);
    final backoffWeight = _setManager.recommendedBackoffWeightFor(
      exercise,
      setIndex,
    );
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

  String _saveStatusLabel() => _sessionPersistence.statusLabel(
    editCompletedSession: widget.editCompletedSession,
  );

  void _notifySessionPersistenceChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  ActiveWorkoutInsights get _workoutInsights => ActiveWorkoutInsights(
    history: widget.history,
    currentSessionId: session.id,
  );

  ActiveWorkoutSessionBuilder get _sessionBuilder =>
      ActiveWorkoutSessionBuilder(history: widget.history, bodyLogs: _bodyLogs);

  ActiveWorkoutExerciseManager get _exerciseManager =>
      ActiveWorkoutExerciseManager(
        session: session,
        sessionBuilder: _sessionBuilder,
      );

  ActiveWorkoutScheduleSync get _scheduleSync => ActiveWorkoutScheduleSync(
    session: session,
    sessionBuilder: _sessionBuilder,
  );

  ActiveWorkoutSetManager get _setManager =>
      ActiveWorkoutSetManager(session: session);

  double _setVolume(ExerciseSet set) => _workoutInsights.setVolume(set);

  List<String> _personalRecordLabelsFor(
    WorkoutExercise exercise,
    ExerciseSet set,
    int setIndex,
  ) {
    return _workoutInsights.personalRecordLabelsFor(exercise, set, setIndex);
  }

  int _sessionPrCount() => _workoutInsights.sessionPrCount(session);

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

  void _applyPreviousValuesForExercise(WorkoutExercise exercise) {
    var changed = false;
    setState(() {
      changed = _setManager.applyPreviousValues(exercise);
    });
    if (!changed) return;
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

  WorkoutExercise? _activeRestExercise() => _restController.activeExercise();

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

    if (_exerciseManager.hasPendingDropContinuation(exercise, setIndex)) {
      return 'Prossimo: drop set, senza recupero.';
    }

    if (exercise.technique == IntensityTechnique.topsetBackoff &&
        setIndex == 0) {
      final backoffWeight = _setManager.recommendedBackoffWeightFor(
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

  String _progressionConfidenceLabel(ProgressionConfidence confidence) {
    return switch (confidence) {
      ProgressionConfidence.low => 'bassa',
      ProgressionConfidence.medium => 'media',
      ProgressionConfidence.high => 'alta',
    };
  }

  FatigueReadinessReport _readinessForExercise(
    WorkoutExercise exercise, {
    bool includeCurrentEffort = true,
  }) {
    return buildExerciseReadinessReport(
      history: widget.history,
      bodyLogs: _bodyLogs,
      exerciseName: exercise.name,
      muscleGroup: exercise.muscleGroup,
      now: DateTime.now(),
      excludeSessionId: session.id,
      currentExercise: includeCurrentEffort ? exercise : null,
    );
  }

  FatigueReadinessReport _workoutReadiness() {
    return buildWorkoutReadinessReport(
      history: widget.history,
      bodyLogs: _bodyLogs,
      exercises: session.exercises,
      now: DateTime.now(),
    );
  }

  ProgressionDecision _progressionDecisionFor(WorkoutExercise exercise) {
    final decision = buildProgressionDecision(
      exercise: exercise,
      history: widget.history,
      excludeSessionId: session.id,
    );
    if (widget.editCompletedSession) {
      return decision;
    }
    return applyReadinessToProgression(
      decision: decision,
      readiness: _readinessForExercise(exercise),
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
    final readiness = _readinessForExercise(exercise);
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
                  Chip(
                    label: Text(
                      'Readiness ${readiness.score}/100 · ${readiness.status.label}',
                    ),
                  ),
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

  Future<void> _showReadinessDetails(WorkoutExercise exercise) async {
    final report = _readinessForExercise(exercise);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Fatigue & Readiness',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 4),
              Text(exercise.name),
              const SizedBox(height: 12),
              Text(
                '${report.score}/100 · ${report.status.label}',
                style: theme.textTheme.headlineSmall?.copyWith(
                  color: colorScheme.primary,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                report.adaptation.label,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (report.hoursSinceLastStimulus != null)
                    Chip(
                      label: Text('${report.hoursSinceLastStimulus}h recupero'),
                    ),
                  if (report.averageRir != null)
                    Chip(
                      label: Text(
                        'RIR medio ${report.averageRir!.toStringAsFixed(1)}',
                      ),
                    ),
                  if (report.sleepHours != null)
                    Chip(label: Text('Sonno ${report.sleepHours}h')),
                  if (report.selfReadiness != null)
                    Chip(label: Text('Check-in ${report.selfReadiness}/10')),
                ],
              ),
              const SizedBox(height: 8),
              for (final reason in report.reasons)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.monitor_heart_outlined),
                  title: Text(reason),
                ),
              if (!widget.editCompletedSession &&
                  report.adaptation != SessionAdaptation.normal) ...[
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    key: ValueKey('apply-readiness-${exercise.id}'),
                    onPressed: () {
                      Navigator.pop(sheetContext);
                      _confirmReadinessAdaptation(exercise, report);
                    },
                    icon: const Icon(Icons.tune),
                    label: const Text('Adatta questa sessione'),
                  ),
                ),
              ],
              const SizedBox(height: 8),
              Text(
                'Il punteggio e deterministico e combina recupero, frequenza, volume, RIR/RPE, trend prestativo, sonno e check-in readiness.',
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

  Future<void> _confirmReadinessAdaptation(
    WorkoutExercise exercise,
    FatigueReadinessReport report,
  ) async {
    final loadReduction = ((1 - report.recommendedLoadMultiplier) * 100)
        .round();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Adattare la sessione?'),
        content: Text(
          report.recommendedSetReduction > 0
              ? 'Riduce del $loadReduction% i set non completati e rimuove un set di lavoro non ancora eseguito. I set completati non vengono toccati.'
              : 'Riduce del $loadReduction% i set non completati. I set completati non vengono toccati.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annulla'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Applica'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    setState(() {
      for (final set in exercise.sets) {
        if (set.isWarmup || set.isCompleted) continue;
        set.weight =
            (set.weight * report.recommendedLoadMultiplier * 2)
                .roundToDouble() /
            2;
      }
      if (report.recommendedSetReduction > 0 &&
          exercise.technique != IntensityTechnique.topsetBackoff) {
        final workSets = exercise.sets.where((set) => !set.isWarmup).toList();
        if (workSets.length > 1) {
          ExerciseSet? removable;
          for (final set in workSets.reversed) {
            if (!set.isCompleted) {
              removable = set;
              break;
            }
          }
          if (removable != null) {
            exercise.sets.remove(removable);
          }
        }
      }
    });
    HapticFeedback.mediumImpact();
    _saveCurrentSession();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${exercise.name}: sessione adattata a ${report.status.label.toLowerCase()}.',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
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

  void _notifyRestControllerChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  void _triggerPostRestHandoff(WorkoutExercise exercise, ExerciseSet set) {
    _handoffPulseTimer?.cancel();
    _handoffClearTimer?.cancel();
    var pulseTransitions = 0;
    setState(() {
      _handoffSetId = set.id;
      _handoffPulseEmphasis = true;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _scrollToSet(exercise.id, set.id);
      }
    });

    _handoffPulseTimer = Timer.periodic(const Duration(milliseconds: 260), (
      timer,
    ) {
      if (!mounted || _handoffSetId != set.id) {
        timer.cancel();
        return;
      }
      pulseTransitions++;
      setState(() {
        _handoffPulseEmphasis = !_handoffPulseEmphasis;
      });
      if (pulseTransitions >= 4) {
        timer.cancel();
        _handoffPulseTimer = null;
      }
    });
    _handoffClearTimer = Timer(const Duration(milliseconds: 1800), () {
      _handoffClearTimer = null;
      if (!mounted || _handoffSetId != set.id) return;
      setState(() {
        _handoffSetId = null;
        _handoffPulseEmphasis = false;
      });
    });
  }

  void _handleRestFinished(String exerciseId, String? exerciseName) {
    WorkoutExercise? restExercise;
    for (final candidate in session.exercises) {
      if (candidate.id == exerciseId) {
        restExercise = candidate;
        break;
      }
    }
    final handoffTarget = restExercise == null
        ? null
        : _nextSetAfterRest(restExercise);

    _saveCurrentSession();
    if (handoffTarget == null) {
      HapticFeedback.mediumImpact();
    } else {
      HapticFeedback.heavyImpact();
    }
    SystemSound.play(SystemSoundType.alert);
    LocalNotificationService.showRestFinished(exerciseName ?? '');

    if (!mounted) return;
    if (handoffTarget != null) {
      _triggerPostRestHandoff(handoffTarget.exercise, handoffTarget.set);
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          handoffTarget == null
              ? (exerciseName == null
                    ? 'Recupero finito.'
                    : 'Recupero finito: $exerciseName.')
              : 'Recupero finito · ${handoffTarget.exercise.name}: ${_formatWeight(handoffTarget.set.weight)} kg × ${handoffTarget.set.reps}.',
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _startRestForExercise(WorkoutExercise exercise) {
    if (_restController.start(exercise)) {
      _saveCurrentSession();
    }
  }

  void _addThirtySeconds(WorkoutExercise exercise) {
    if (_restController.addThirtySeconds(exercise)) {
      _saveCurrentSession();
    }
  }

  void _subtractThirtySeconds(WorkoutExercise exercise) {
    if (_restController.subtractThirtySeconds(exercise)) {
      _saveCurrentSession();
    }
  }

  void _stopRestForExercise(WorkoutExercise exercise) {
    if (_restController.stop(exercise)) {
      _saveCurrentSession();
    }
  }

  Future<void> _cancelAllRestTimers() => _restController.cancelAll();

  void _updateExerciseRestSeconds(WorkoutExercise exercise, String value) {
    final parsedSeconds = parseIntInput(value);
    if (parsedSeconds == null) return;
    if (_restController.updateConfiguredRest(exercise, parsedSeconds)) {
      _saveCurrentSession();
    }
  }

  void _restoreRestTimersFromSession({bool notifyExpired = false}) {
    _restController.restore(notifyExpired: notifyExpired);
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

  Future<void> _loadReadinessBodyLogs() async {
    final bundle = await AppDataStore.loadBundle();
    if (!mounted || _bodyLogs.isNotEmpty) return;
    setState(() {
      _bodyLogs = List<BodyLog>.from(bundle.bodyLogs);
    });
  }

  @override
  void initState() {
    super.initState();
    _bodyLogs = List<BodyLog>.from(widget.bodyLogs);
    if (_bodyLogs.isEmpty) {
      _loadReadinessBodyLogs();
    }
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
      session = _sessionBuilder.buildFromSchedule(widget.schedule!);
      _restoreRestTimersFromSession();
      _restoreIfNeeded();
    } else {
      session = _sessionBuilder.buildEmptySession();
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
      _sessionPersistence.markLocalEdit(
        onChanged: _notifySessionPersistenceChanged,
      );
      return;
    }
    await _queueCurrentSessionSave(showSaving: true);
  }

  Future<void> _saveCurrentSessionSilently() async {
    if (widget.editCompletedSession) {
      _sessionPersistence.markLocalEdit();
      return;
    }
    await _queueCurrentSessionSave();
  }

  Future<void> _queueCurrentSessionSave({bool showSaving = false}) {
    return _sessionPersistence.save(
      session,
      showSaving: showSaving,
      onChanged: _notifySessionPersistenceChanged,
    );
  }

  Future<void> _drainCurrentSessionSaves() => _sessionPersistence.drain();

  Future<void> _clearSavedSession() async {
    if (widget.editCompletedSession) {
      return;
    }
    await _sessionPersistence.clear();
  }

  Future<bool> _confirmSaveAddedExercises(Schedule? schedule) async {
    if (schedule == null || !mounted) {
      return false;
    }

    final newExercises = _scheduleSync.newExercisesForSchedule(schedule);
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
    final storedSchedule = _scheduleSync.storedScheduleForSession(
      bundle.schedules,
      liveSchedule: widget.schedule,
    );
    if (storedSchedule == null) return;

    final addedIds = _scheduleSync.addNewExercisesToSchedule(storedSchedule);
    if (addedIds.isEmpty) return;
    _exerciseIdsAddedToScheduleThisFinish.addAll(addedIds);
    _scheduleSync.syncLiveSchedule(
      storedSchedule: storedSchedule,
      liveSchedule: widget.schedule,
    );
    await AppDataStore.saveSchedules(bundle.schedules);
  }

  Future<void> _applyProgressionToSchedule() async {
    final bundle = await AppDataStore.loadBundle();
    final storedSchedule = _scheduleSync.storedScheduleForSession(
      bundle.schedules,
      liveSchedule: widget.schedule,
    );
    if (storedSchedule == null) return;

    _scheduleSync.applyProgressionToSchedule(
      storedSchedule: storedSchedule,
      history: bundle.history,
      skipSourceExerciseIds: _exerciseIdsAddedToScheduleThisFinish,
    );
    await AppDataStore.saveSchedules(bundle.schedules);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _prBannerTimer?.cancel();
    _prBannerTimer = null;
    _handoffPulseTimer?.cancel();
    _handoffPulseTimer = null;
    _handoffClearTimer?.cancel();
    _handoffClearTimer = null;
    _restController.dispose();
    _durationTimer?.cancel();
    _workoutScrollController.dispose();
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

    _sessionPersistence.disable();
    await _drainCurrentSessionSaves();
    await _cancelAllRestTimers();
    session.endTime = DateTime.now();

    final bundle = await AppDataStore.loadBundle();
    final saveAddedExercises = await _confirmSaveAddedExercises(
      _scheduleSync.storedScheduleForSession(
        bundle.schedules,
        liveSchedule: widget.schedule,
      ),
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

  void _addExercisesToSession(List<Exercise> exercises) {
    if (exercises.isEmpty) return;
    setState(() => _exerciseManager.addExercises(exercises));
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

  bool _shouldStartRestAfterSet(
    WorkoutExercise exercise,
    int completedSetIndex,
  ) {
    return _exerciseManager.shouldStartRestAfterSet(
      exercise,
      completedSetIndex: completedSetIndex,
    );
  }

  void _advanceSupersetNavigation(
    WorkoutExercise exercise,
    int completedSetIndex,
  ) {
    final next = _exerciseManager.nextSupersetMemberAfterSet(
      exercise,
      completedSetIndex,
    );
    if (next == null) return;
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

    _restController.stop(exercise);
    WorkoutExercise? replacement;
    setState(() {
      replacement = _exerciseManager.replaceExercise(
        exercise,
        replacements.first,
      );
      if (replacement != null) {
        _exerciseCardKeys.remove(exercise.id);
      }
    });
    if (replacement == null) return;
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
    WorkoutExercise? duplicate;
    setState(() {
      duplicate = _exerciseManager.duplicateExercise(exercise);
    });
    if (duplicate == null) return;
    HapticFeedback.selectionClick();
    _saveCurrentSession();
  }

  void _moveExercise(WorkoutExercise exercise, int delta) {
    var moved = false;
    setState(() {
      moved = _exerciseManager.moveExercise(exercise, delta);
    });
    if (!moved) return;
    HapticFeedback.selectionClick();
    _saveCurrentSession();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _scrollToExercise(exercise.id);
    });
  }

  void _removeExerciseFromSession(WorkoutExercise exercise) {
    _restController.stop(exercise);
    RemovedWorkoutExercise? removal;
    setState(() {
      removal = _exerciseManager.removeExercise(exercise);
      if (removal != null) {
        _exerciseCardKeys.remove(exercise.id);
      }
    });
    if (removal == null) return;
    _saveCurrentSession();

    _showUndoSnackBar(
      message: '${exercise.name} eliminato dalla sessione.',
      onUndo: () {
        if (!mounted) return;
        var restored = false;
        setState(() {
          restored = _exerciseManager.restoreRemoved(removal!);
        });
        if (restored) {
          _saveCurrentSession();
        }
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

    if (selectedId == '__remove__') {
      var changed = false;
      setState(() {
        changed = _exerciseManager.removeFromSuperset(exercise);
      });
      if (changed) {
        _saveCurrentSession();
      }
      return;
    }

    final targetIndex = session.exercises.indexWhere(
      (candidate) => candidate.id == selectedId,
    );
    if (targetIndex < 0) return;
    final target = session.exercises[targetIndex];

    var changed = false;
    setState(() {
      changed = _exerciseManager.linkSuperset(exercise, target);
    });
    if (!changed) return;
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
    setState(() => _setManager.addSet(exercise, isWarmup: isWarmup));
    _saveCurrentSession();
  }

  void _copySet(WorkoutExercise exercise, int setIndex) {
    ExerciseSet? copy;
    setState(() => copy = _setManager.copySet(exercise, setIndex));
    if (copy == null) return;
    _saveCurrentSession();
  }

  List<String> _sessionValidationProblems() => _setManager.validationProblems();

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
    var applied = false;
    setState(() {
      applied = _setManager.applyRecommendedBackoffWeight(exercise, setIndex);
    });
    if (!applied) return;
    _saveCurrentSession();
  }

  Future<void> _showExerciseHistory(WorkoutExercise exercise) async {
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
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                              ),
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

  List<ExerciseSet> _warmupSetsFor(WorkoutExercise exercise) =>
      _setManager.warmupSetsFor(exercise);

  void _insertWarmupPlan(WorkoutExercise exercise) {
    setState(() => _setManager.insertWarmupPlan(exercise));
    _saveCurrentSession();
  }

  void _showWarmupPlan(WorkoutExercise exercise) {
    final warmups = _warmupSetsFor(exercise);
    if (warmups.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Imposta prima un carico di lavoro per calcolare il warm-up.',
          ),
        ),
      );
      return;
    }
    final rows = warmups
        .map((set) => '${_formatWeight(set.weight)} kg x ${set.reps}')
        .toList();

    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Warm-up smart ${exercise.name}'),
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

  void _showPersonalRecordCelebration(ActiveWorkoutPrEvent event) {
    if (!mounted) return;

    final generation = ++_prBannerGeneration;
    final messenger = ScaffoldMessenger.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    _prBannerTimer?.cancel();
    _prBannerTimer = null;
    messenger.removeCurrentMaterialBanner();
    HapticFeedback.mediumImpact();
    messenger.showMaterialBanner(
      MaterialBanner(
        key: const ValueKey('live-pr-banner'),
        backgroundColor: colorScheme.tertiaryContainer,
        leading: Icon(Icons.emoji_events, color: colorScheme.tertiary),
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              event.headline,
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 2),
            Text(event.exerciseName),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: event.kinds
                  .map(
                    (kind) => Chip(
                      key: ValueKey('live-pr-${kind.name}'),
                      label: Text(kind.displayLabel),
                      visualDensity: VisualDensity.compact,
                    ),
                  )
                  .toList(),
            ),
          ],
        ),
        actions: [
          TextButton(
            key: const ValueKey('dismiss-live-pr'),
            onPressed: () {
              _prBannerGeneration++;
              _prBannerTimer?.cancel();
              _prBannerTimer = null;
              messenger.hideCurrentMaterialBanner();
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );

    _prBannerTimer = Timer(const Duration(seconds: 4), () {
      _prBannerTimer = null;
      if (!mounted || generation != _prBannerGeneration) return;
      _prBannerGeneration++;
      ScaffoldMessenger.of(context).hideCurrentMaterialBanner();
    });
  }

  void _toggleSetCompleted(
    WorkoutExercise exercise,
    ExerciseSet set,
    int setIndex,
  ) {
    var willComplete = false;
    setState(() {
      willComplete = _setManager.toggleSetCompleted(set);
    });
    _saveCurrentSession();
    final prEvent = willComplete
        ? _workoutInsights.personalRecordEventFor(exercise, set, setIndex)
        : null;
    if (willComplete && !widget.editCompletedSession) {
      if (_shouldStartRestAfterSet(exercise, setIndex)) {
        _startRestForExercise(exercise);
      }
      _advanceSupersetNavigation(exercise, setIndex);
      if (prEvent != null) {
        _showPersonalRecordCelebration(prEvent);
      }
    }

    final delta = _setVolumeDelta(exercise, set, setIndex);
    if (willComplete &&
        prEvent == null &&
        delta != null &&
        delta > 0 &&
        mounted) {
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

  int _currentSetIndexFor(WorkoutExercise exercise) {
    for (var index = 0; index < exercise.sets.length; index++) {
      if (!exercise.sets[index].isCompleted) return index;
    }
    return -1;
  }

  String? _setMetadataSummary(ExerciseSet set) {
    final parts = <String>[];
    if (set.type != SetType.normal) parts.add(set.type.label);
    if (set.rpe != null) parts.add('RPE ${_formatWeight(set.rpe!)}');
    if (set.rir != null) parts.add('RIR ${set.rir}');
    if (set.notes.trim().isNotEmpty) parts.add('Nota');
    return parts.isEmpty ? null : parts.join(' · ');
  }

  ({WorkoutExercise exercise, ExerciseSet set, int setIndex})?
  _nextSetAfterRest(WorkoutExercise restExercise) {
    final supersetMembers = _exerciseManager.supersetMembers(restExercise);
    if (supersetMembers.length >= 2) {
      final memberIndex = supersetMembers.indexWhere(
        (member) => member.id == restExercise.id,
      );
      if (memberIndex >= 0) {
        for (var offset = 1; offset <= supersetMembers.length; offset++) {
          final candidate =
              supersetMembers[(memberIndex + offset) % supersetMembers.length];
          final setIndex = _currentSetIndexFor(candidate);
          if (setIndex >= 0) {
            return (
              exercise: candidate,
              set: candidate.sets[setIndex],
              setIndex: setIndex,
            );
          }
        }
      }
    }

    final currentSetIndex = _currentSetIndexFor(restExercise);
    if (currentSetIndex >= 0) {
      return (
        exercise: restExercise,
        set: restExercise.sets[currentSetIndex],
        setIndex: currentSetIndex,
      );
    }

    final exerciseIndex = session.exercises.indexWhere(
      (exercise) => exercise.id == restExercise.id,
    );
    if (exerciseIndex < 0) return null;
    for (
      var index = exerciseIndex + 1;
      index < session.exercises.length;
      index++
    ) {
      final candidate = session.exercises[index];
      final setIndex = _currentSetIndexFor(candidate);
      if (setIndex >= 0) {
        return (
          exercise: candidate,
          set: candidate.sets[setIndex],
          setIndex: setIndex,
        );
      }
    }
    return null;
  }

  void _submitSetFromKeyboard(
    WorkoutExercise exercise,
    ExerciseSet set,
    int setIndex,
    String value,
  ) {
    final reps = parseIntInput(value);
    if (reps == null || reps <= 0 || set.isCompleted) return;
    FocusScope.of(context).unfocus();
    _toggleSetCompleted(exercise, set, setIndex);
  }

  Future<void> _showSetDetailsDialog(ExerciseSet set) async {
    final rpeController = TextEditingController(
      text: set.rpe?.toString() ?? '',
    );
    final rirController = TextEditingController(
      text: set.rir?.toString() ?? '',
    );
    final notesController = TextEditingController(text: set.notes);
    var selectedSetType = set.type;

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Dettagli set'),
          content: AppDialogContent(
            maxWidth: 480,
            children: [
              DropdownButtonFormField<SetType>(
                key: ValueKey('set-details-type-${set.id}'),
                initialValue: selectedSetType,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Tipo set'),
                items: SetType.values
                    .map(
                      (type) => DropdownMenuItem<SetType>(
                        value: type,
                        child: Text(type.label),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value == null) return;
                  setDialogState(() => selectedSetType = value);
                },
              ),
              appDialogFieldGap,
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
      set.type = selectedSetType;
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
    RemovedExerciseSet? removal;
    setState(() {
      removal = _setManager.removeSet(exercise, index);
    });
    if (removal == null) return;
    _saveCurrentSession();

    _showUndoSnackBar(
      message: 'Set eliminato.',
      onUndo: () {
        if (!mounted) return;
        var restored = false;
        setState(() {
          restored = _setManager.restoreRemovedSet(exercise, removal!);
        });
        if (restored) {
          _saveCurrentSession();
        }
      },
    );
  }

  ActiveWorkoutStats get _workoutStats => _setManager.workoutStats;

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
        : _restController.remainingFor(activeRestExercise.id);
    final restTarget = activeRestExercise == null
        ? null
        : _nextSetAfterRest(activeRestExercise);
    final configuredRestSeconds = activeRestExercise == null
        ? null
        : _restController.configuredSecondsFor(activeRestExercise);
    final restProgress =
        activeRestSeconds == null ||
            configuredRestSeconds == null ||
            configuredRestSeconds <= 0
        ? null
        : (activeRestSeconds / configuredRestSeconds)
              .clamp(0.0, 1.0)
              .toDouble();
    final workoutReadiness = _workoutReadiness();

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
                  '${_saveStatusLabel()} · Readiness ${workoutReadiness.score}/100 ${workoutReadiness.status.label}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ),
        ),
        body: ListView.builder(
          controller: _workoutScrollController,
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
            final activeRestSeconds = _restController.remainingFor(exercise.id);
            final restSeconds =
                activeRestSeconds ??
                _restController.configuredSecondsFor(exercise);
            final accent = _accentForIndex(colorScheme, exIndex);
            final currentEstimatedOneRepMax = bestEstimatedOneRepMaxForSets(
              exercise.sets.where((set) => set.isCompleted && !set.isWarmup),
            );
            final historicalEstimatedOneRepMax =
                historicalBestEstimatedOneRepMax(
                  history: widget.history,
                  exerciseName: exercise.name,
                  excludeSessionId: session.id,
                );

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
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                _formatPreviousWeights(
                                  exercise.previousWeights,
                                ),
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: colorScheme.primary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            ActionChip(
                              key: ValueKey(
                                'use-previous-values-${exercise.id}',
                              ),
                              avatar: const Icon(Icons.history, size: 16),
                              label: const Text('Usa precedenti'),
                              tooltip: 'Carica kg e reps dell’ultima sessione nei set non completati',
                              visualDensity: VisualDensity.compact,
                              onPressed: () =>
                                  _applyPreviousValuesForExercise(exercise),
                            ),
                          ],
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
                          ActionChip(
                            key: ValueKey('readiness-${exercise.id}'),
                            avatar: const Icon(
                              Icons.monitor_heart_outlined,
                              size: 18,
                            ),
                            label: Text(
                              '${_readinessForExercise(exercise).status.label} ${_readinessForExercise(exercise).score}',
                            ),
                            visualDensity: VisualDensity.compact,
                            onPressed: () => _showReadinessDetails(exercise),
                          ),
                          if (exercise.sets.any(
                            (set) => set.isCompleted && !set.isWarmup,
                          ))
                            ActionChip(
                              key: ValueKey(
                                'progression-intelligence-${exercise.id}',
                              ),
                              avatar: const Icon(Icons.auto_graph, size: 18),
                              label: Text(
                                progressionActionLabel(
                                  _progressionDecisionFor(exercise),
                                ),
                              ),
                              visualDensity: VisualDensity.compact,
                              onPressed: () =>
                                  _showProgressionDecision(exercise),
                            ),
                          if (historicalEstimatedOneRepMax != null)
                            Chip(
                              avatar: const Icon(
                                Icons.workspace_premium,
                                size: 18,
                              ),
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
                            width: 88,
                            child: _StableSetTextField(
                              key: ValueKey('rest-${exercise.id}'),
                              text: _restController
                                  .configuredSecondsFor(exercise)
                                  .toString(),
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                              ],
                              textInputAction: TextInputAction.done,
                              selectAllOnFocus: true,
                              onSubmitted: (_) =>
                                  FocusScope.of(context).unfocus(),
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
                          PopupMenuButton<int>(
                            key: ValueKey('rest-preset-${exercise.id}'),
                            tooltip: 'Preset recupero',
                            icon: const Icon(Icons.tune),
                            onSelected: (seconds) => _updateExerciseRestSeconds(
                              exercise,
                              seconds.toString(),
                            ),
                            itemBuilder: (context) => const [60, 90, 120, 180]
                                .map(
                                  (seconds) => PopupMenuItem<int>(
                                    value: seconds,
                                    child: Text('$seconds s'),
                                  ),
                                )
                                .toList(),
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
                        final currentSetIndex = _currentSetIndexFor(exercise);
                        final isCurrentSet = setIndex == currentSetIndex;
                        final isHandoffSet = _handoffSetId == exSet.id;
                        final setMetadataSummary = _setMetadataSummary(exSet);
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
                          child: AnimatedContainer(
                            key: _setRowKey(exSet.id),
                            duration: const Duration(milliseconds: 220),
                            curve: Curves.easeInOut,
                            transformAlignment: Alignment.center,
                            transform: Matrix4.diagonal3Values(
                              isHandoffSet && _handoffPulseEmphasis
                                  ? 1.012
                                  : 1.0,
                              isHandoffSet && _handoffPulseEmphasis
                                  ? 1.012
                                  : 1.0,
                              1.0,
                            ),
                            margin: const EdgeInsets.symmetric(vertical: 3),
                            padding: const EdgeInsets.symmetric(vertical: 5.0),
                            decoration: BoxDecoration(
                              color: exSet.isCompleted
                                  ? colorScheme.tertiaryContainer.withValues(
                                      alpha: isDark ? 0.38 : 0.62,
                                    )
                                  : isHandoffSet
                                  ? colorScheme.primaryContainer.withValues(
                                      alpha: isDark
                                          ? (_handoffPulseEmphasis
                                                ? 0.58
                                                : 0.36)
                                          : (_handoffPulseEmphasis
                                                ? 0.82
                                                : 0.58),
                                    )
                                  : isCurrentSet
                                  ? colorScheme.primaryContainer.withValues(
                                      alpha: isDark ? 0.28 : 0.48,
                                    )
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: exSet.isCompleted
                                    ? colorScheme.tertiary.withValues(
                                        alpha: 0.35,
                                      )
                                    : isHandoffSet || isCurrentSet
                                    ? colorScheme.primary
                                    : Colors.transparent,
                                width: isHandoffSet
                                    ? (_handoffPulseEmphasis ? 2.8 : 2.0)
                                    : isCurrentSet
                                    ? 1.6
                                    : 1,
                              ),
                              boxShadow: isHandoffSet && _handoffPulseEmphasis
                                  ? [
                                      BoxShadow(
                                        color: colorScheme.primary.withValues(
                                          alpha: 0.24,
                                        ),
                                        blurRadius: 14,
                                        spreadRadius: 1,
                                      ),
                                    ]
                                  : null,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    SizedBox(
                                      width: 72,
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            displaySetLabel,
                                            textAlign: TextAlign.center,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          if (isCurrentSet)
                                            Container(
                                              key: ValueKey(
                                                'current-set-${exSet.id}',
                                              ),
                                              margin: const EdgeInsets.only(
                                                top: 2,
                                              ),
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 6,
                                                    vertical: 1,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: colorScheme.primary,
                                                borderRadius:
                                                    BorderRadius.circular(99),
                                              ),
                                              child: Text(
                                                'ORA',
                                                style: theme
                                                    .textTheme
                                                    .labelSmall
                                                    ?.copyWith(
                                                      color:
                                                          colorScheme.onPrimary,
                                                      fontWeight:
                                                          FontWeight.w900,
                                                    ),
                                              ),
                                            ),
                                        ],
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
                                          inputFormatters: [
                                            FilteringTextInputFormatter.allow(
                                              RegExp(r'[0-9.,]'),
                                            ),
                                          ],
                                          textInputAction: TextInputAction.next,
                                          selectAllOnFocus: true,
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
                                          inputFormatters: [
                                            FilteringTextInputFormatter
                                                .digitsOnly,
                                          ],
                                          textInputAction: TextInputAction.done,
                                          selectAllOnFocus: true,
                                          onSubmitted: (value) =>
                                              _submitSetFromKeyboard(
                                                exercise,
                                                exSet,
                                                setIndex,
                                                value,
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
                                      key: ValueKey('complete-${exSet.id}'),
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
                                      key: ValueKey('set-details-${exSet.id}'),
                                      tooltip: 'RPE, RIR, tipo e note',
                                      onPressed: () =>
                                          _showSetDetailsDialog(exSet),
                                      icon: const Icon(Icons.tune),
                                    ),
                                  ],
                                ),
                                if (isHandoffSet && !exSet.isCompleted)
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                      72,
                                      6,
                                      8,
                                      0,
                                    ),
                                    child: Container(
                                      key: ValueKey('handoff-set-${exSet.id}'),
                                      width: double.infinity,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 7,
                                      ),
                                      decoration: BoxDecoration(
                                        color: colorScheme.primary.withValues(
                                          alpha: isDark ? 0.18 : 0.10,
                                        ),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Icon(
                                            Icons.bolt,
                                            size: 17,
                                            color: colorScheme.primary,
                                          ),
                                          const SizedBox(width: 5),
                                          Text(
                                            'TOCCA A TE',
                                            style: theme.textTheme.labelMedium
                                                ?.copyWith(
                                                  color: colorScheme.primary,
                                                  fontWeight: FontWeight.w900,
                                                  letterSpacing: 0.7,
                                                ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                if (isCurrentSet && !exSet.isCompleted)
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                      72,
                                      6,
                                      8,
                                      0,
                                    ),
                                    child: SizedBox(
                                      width: double.infinity,
                                      child: FilledButton.icon(
                                        key: ValueKey(
                                          'thumb-complete-${exSet.id}',
                                        ),
                                        onPressed: () => _toggleSetCompleted(
                                          exercise,
                                          exSet,
                                          setIndex,
                                        ),
                                        icon: const Icon(Icons.check_circle),
                                        label: const Text('Completa set'),
                                      ),
                                    ),
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
                                if (isCurrentSet)
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
                                          itemBuilder: (context) => SetType
                                              .values
                                              .map(
                                                (type) =>
                                                    PopupMenuItem<SetType>(
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
                                            visualDensity:
                                                VisualDensity.compact,
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
                                            visualDensity:
                                                VisualDensity.compact,
                                          ),
                                      ],
                                    ),
                                  ),
                                if (!isCurrentSet && setMetadataSummary != null)
                                  Padding(
                                    padding: const EdgeInsets.only(
                                      left: 72,
                                      top: 4,
                                      right: 8,
                                    ),
                                    child: Text(
                                      setMetadataSummary,
                                      key: ValueKey('set-meta-${exSet.id}'),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(
                                            color: colorScheme.onSurfaceVariant,
                                            fontWeight: FontWeight.w600,
                                          ),
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
                  key: ValueKey('rest-mode-${activeRestExercise.id}'),
                  margin: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: colorScheme.primary, width: 1.4),
                    boxShadow: [
                      BoxShadow(
                        color: colorScheme.shadow.withValues(alpha: 0.12),
                        blurRadius: 16,
                        offset: const Offset(0, -3),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Container(
                            width: 52,
                            height: 52,
                            decoration: BoxDecoration(
                              color: colorScheme.primaryContainer,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.timer_outlined,
                              color: colorScheme.onPrimaryContainer,
                              size: 28,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'RECUPERO',
                                  style: theme.textTheme.labelMedium?.copyWith(
                                    color: colorScheme.primary,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 1.1,
                                  ),
                                ),
                                Text(
                                  _formatDuration(activeRestSeconds),
                                  key: const ValueKey('rest-mode-countdown'),
                                  style: theme.textTheme.displaySmall?.copyWith(
                                    fontWeight: FontWeight.w900,
                                    height: 1,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'dopo ${activeRestExercise.name}',
                                  maxLines: 1,
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
                      if (restProgress != null) ...[
                        const SizedBox(height: 10),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(99),
                          child: LinearProgressIndicator(
                            key: const ValueKey('rest-mode-progress'),
                            value: restProgress,
                            minHeight: 6,
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),
                      if (restTarget != null)
                        Container(
                          key: ValueKey('rest-next-set-${restTarget.set.id}'),
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 11,
                          ),
                          decoration: BoxDecoration(
                            color: colorScheme.surface,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: colorScheme.outlineVariant,
                            ),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'PROSSIMO SET',
                                      style: theme.textTheme.labelSmall
                                          ?.copyWith(
                                            color: colorScheme.primary,
                                            fontWeight: FontWeight.w900,
                                            letterSpacing: 0.8,
                                          ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      restTarget.exercise.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.titleMedium
                                          ?.copyWith(
                                            fontWeight: FontWeight.w900,
                                          ),
                                    ),
                                    Text(
                                      'Serie ${restTarget.setIndex + 1}${restTarget.set.type == SetType.normal ? '' : ' · ${restTarget.set.type.label}'}',
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(
                                            color: colorScheme.onSurfaceVariant,
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 12),
                              Text(
                                '${_formatWeight(restTarget.set.weight)} kg\n× ${restTarget.set.reps}',
                                key: const ValueKey('rest-next-prescription'),
                                textAlign: TextAlign.right,
                                style: theme.textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.w900,
                                  height: 1.05,
                                ),
                              ),
                            ],
                          ),
                        )
                      else
                        Container(
                          key: const ValueKey('rest-workout-complete'),
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 11,
                          ),
                          decoration: BoxDecoration(
                            color: colorScheme.tertiaryContainer.withValues(
                              alpha: isDark ? 0.35 : 0.65,
                            ),
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.check_circle,
                                color: colorScheme.tertiary,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Ultimo set completato',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                    Text(
                                      'Recupera e poi puoi terminare l’allenamento.',
                                      style: theme.textTheme.bodySmall,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              key: const ValueKey('rest-minus-30'),
                              onPressed: () =>
                                  _subtractThirtySeconds(activeRestExercise),
                              icon: const Icon(Icons.remove),
                              label: const Text('30 s'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton.icon(
                              key: const ValueKey('rest-plus-30'),
                              onPressed: () =>
                                  _addThirtySeconds(activeRestExercise),
                              icon: const Icon(Icons.add),
                              label: const Text('30 s'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: FilledButton(
                              key: const ValueKey('rest-skip'),
                              onPressed: () =>
                                  _stopRestForExercise(activeRestExercise),
                              child: const Text('Salta'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
        floatingActionButton: activeRestExercise == null
            ? FloatingActionButton.extended(
                onPressed: _openExercisePicker,
                icon: const Icon(Icons.add),
                label: const Text('Esercizio'),
              )
            : null,
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
  final List<TextInputFormatter>? inputFormatters;
  final TextInputAction textInputAction;
  final ValueChanged<String>? onSubmitted;
  final bool selectAllOnFocus;

  const _StableSetTextField({
    super.key,
    required this.text,
    required this.keyboardType,
    required this.textAlign,
    required this.decoration,
    required this.onChanged,
    this.inputFormatters,
    this.textInputAction = TextInputAction.next,
    this.onSubmitted,
    this.selectAllOnFocus = false,
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
    _focusNode = FocusNode()..addListener(_handleFocusChanged);
  }

  void _handleFocusChanged() {
    if (_focusNode.hasFocus && widget.selectAllOnFocus) {
      _selectAll();
    }
  }

  void _selectAll() {
    _controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _controller.text.length,
    );
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
    _focusNode.removeListener(_handleFocusChanged);
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
      inputFormatters: widget.inputFormatters,
      textInputAction: widget.textInputAction,
      textAlign: widget.textAlign,
      decoration: widget.decoration,
      onTap: widget.selectAllOnFocus ? _selectAll : null,
      onChanged: widget.onChanged,
      onFieldSubmitted: widget.onSubmitted,
    );
  }
}
