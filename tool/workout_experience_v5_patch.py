from pathlib import Path
import re


def sub_once(text: str, pattern: str, replacement: str, label: str) -> str:
    updated, count = re.subn(pattern, replacement, text, count=1, flags=re.S)
    if count != 1:
        raise RuntimeError(f'{label}: expected 1 match, found {count}')
    return updated


# ---------------------------------------------------------------------------
# Fatigue engine cleanup + global/workout readiness aggregation.
# ---------------------------------------------------------------------------
fatigue_path = Path('lib/workout_fatigue_analytics.dart')
fatigue = fatigue_path.read_text()
fatigue = fatigue.replace("import 'dart:math' as math;\n\n", '', 1)
fatigue = fatigue.replace(
    '''    ReadinessStatus.fatigued || ReadinessStatus.recovery => 1,''',
    '''    ReadinessStatus.fatigued => 0,\n    ReadinessStatus.recovery => 1,''',
    1,
)
fatigue = fatigue.replace(
    '''        reasons.add('Readiness ${readiness.score}/100: aumento carico sospeso.');\n      }\n    case ReadinessStatus.fatigued:''',
    '''        reasons.add('Readiness ${readiness.score}/100: aumento carico sospeso.');\n      }\n      break;\n    case ReadinessStatus.fatigued:''',
    1,
)
fatigue = fatigue.replace(
    '''        reasons.add('Fatica ${readiness.score}/100: mantieni finche recuperi.');\n      }\n    case ReadinessStatus.recovery:''',
    '''        reasons.add('Fatica ${readiness.score}/100: mantieni finche recuperi.');\n      }\n      break;\n    case ReadinessStatus.recovery:''',
    1,
)
fatigue = fatigue.replace(
    '''      reasons.add('Readiness ${readiness.score}/100: priorita al recupero.');\n  }''',
    '''      reasons.add('Readiness ${readiness.score}/100: priorita al recupero.');\n      break;\n  }''',
    1,
)

global_and_workout = r'''FatigueReadinessReport buildGlobalReadinessReport({
  required List<WorkoutSession> history,
  required List<BodyLog> bodyLogs,
  DateTime? now,
}) {
  final referenceTime = now ?? DateTime.now();
  final cutoff7 = referenceTime.subtract(const Duration(days: 7));
  final cutoff3 = referenceTime.subtract(const Duration(days: 3));
  final baselineStart = referenceTime.subtract(const Duration(days: 28));
  final relevant = history
      .where((session) => !session.endTime.isAfter(referenceTime))
      .toList()
    ..sort((a, b) => a.endTime.compareTo(b.endTime));

  final sessionsLast7Days = relevant
      .where((session) => !session.endTime.isBefore(cutoff7))
      .length;
  final hoursSinceLastStimulus = relevant.isEmpty
      ? null
      : referenceTime.difference(relevant.last.endTime).inHours.clamp(0, 100000);

  final effortSets = <ExerciseSet>[];
  var acuteVolume = 0.0;
  var baselineVolume = 0.0;
  for (final session in relevant) {
    for (final exercise in session.exercises) {
      final workSets = _completedWorkSets(exercise).toList();
      if (!session.endTime.isBefore(cutoff7)) {
        effortSets.addAll(workSets);
      }
      final volume = _exerciseVolume(exercise);
      if (!session.endTime.isBefore(cutoff3)) {
        acuteVolume += volume;
      } else if (!session.endTime.isBefore(baselineStart)) {
        baselineVolume += volume;
      }
    }
  }

  final rirValues = effortSets
      .map(_effectiveRir)
      .whereType<double>()
      .toList();
  final rpeValues = effortSets
      .where((set) => set.rpe != null)
      .map((set) => set.rpe!)
      .toList();
  final averageRir = rirValues.isEmpty
      ? null
      : rirValues.reduce((a, b) => a + b) / rirValues.length;
  final averageRpe = rpeValues.isEmpty
      ? null
      : rpeValues.reduce((a, b) => a + b) / rpeValues.length;
  final expectedThreeDayBaseline = baselineVolume <= 0
      ? null
      : (baselineVolume / 25.0) * 3.0;
  final acuteVolumeRatio = expectedThreeDayBaseline == null ||
          expectedThreeDayBaseline <= 0
      ? null
      : acuteVolume / expectedThreeDayBaseline;
  final bodyLog = _latestRelevantBodyLog(bodyLogs, referenceTime);

  var score = 78;
  final reasons = <String>[];
  if (hoursSinceLastStimulus != null) {
    if (hoursSinceLastStimulus < 12) {
      score -= 18;
      reasons.add('Ultimo allenamento terminato meno di 12 ore fa.');
    } else if (hoursSinceLastStimulus < 24) {
      score -= 10;
      reasons.add('Recupero sistemico inferiore a 24 ore.');
    } else if (hoursSinceLastStimulus >= 48) {
      score += 4;
      reasons.add('Almeno 48 ore dall ultimo allenamento.');
    }
  }
  if (averageRir != null) {
    if (averageRir <= 0.75) {
      score -= 16;
      reasons.add('Sforzo medio recente molto vicino al cedimento.');
    } else if (averageRir <= 1.5) {
      score -= 8;
      reasons.add('Sforzo medio recente elevato.');
    } else if (averageRir >= 2.5) {
      score += 3;
      reasons.add('Buon margine medio nelle serie recenti.');
    }
  }
  if (acuteVolumeRatio != null) {
    if (acuteVolumeRatio >= 1.6) {
      score -= 15;
      reasons.add('Volume delle ultime 72 ore molto sopra il baseline.');
    } else if (acuteVolumeRatio >= 1.2) {
      score -= 7;
      reasons.add('Volume delle ultime 72 ore sopra il baseline.');
    }
  }
  if (sessionsLast7Days >= 6) {
    score -= 10;
    reasons.add('Sei sessioni o piu negli ultimi 7 giorni.');
  } else if (sessionsLast7Days >= 5) {
    score -= 5;
    reasons.add('Frequenza recente elevata.');
  }

  final selfReadiness = bodyLog?.readiness;
  if (selfReadiness != null) {
    if (selfReadiness <= 3) {
      score -= 20;
      reasons.add('Readiness soggettiva molto bassa (${selfReadiness}/10).');
    } else if (selfReadiness <= 5) {
      score -= 11;
      reasons.add('Readiness soggettiva bassa (${selfReadiness}/10).');
    } else if (selfReadiness >= 8) {
      score += 4;
      reasons.add('Readiness soggettiva alta (${selfReadiness}/10).');
    }
  }
  final sleepHours = bodyLog?.sleepHours;
  if (sleepHours != null) {
    if (sleepHours < 5) {
      score -= 20;
      reasons.add('Sonno recente sotto le 5 ore.');
    } else if (sleepHours < 6) {
      score -= 12;
      reasons.add('Sonno recente insufficiente.');
    } else if (sleepHours < 7) {
      score -= 5;
      reasons.add('Sonno recente sotto le 7 ore.');
    } else if (sleepHours >= 8) {
      score += 3;
      reasons.add('Sonno recente favorevole al recupero.');
    }
  }

  score = score.clamp(0, 100).toInt();
  final status = _statusForScore(score);
  if (reasons.isEmpty) {
    reasons.add('Dati ancora limitati: registra RIR/RPE, sonno e readiness.');
  }
  return FatigueReadinessReport(
    score: score,
    status: status,
    adaptation: _adaptationForStatus(status),
    reasons: reasons,
    sessionsLast7Days: sessionsLast7Days,
    hoursSinceLastStimulus: hoursSinceLastStimulus,
    averageRir: averageRir,
    averageRpe: averageRpe,
    acuteVolumeRatio: acuteVolumeRatio,
    estimatedOneRepMaxTrendPercent: null,
    selfReadiness: selfReadiness,
    sleepHours: sleepHours,
    recommendedLoadMultiplier: _loadMultiplierForStatus(status),
    recommendedSetReduction: _setReductionForStatus(status),
  );
}

FatigueReadinessReport buildWorkoutReadinessReport({
  required List<WorkoutSession> history,
  required List<BodyLog> bodyLogs,
  required List<WorkoutExercise> exercises,
  DateTime? now,
}) {
  final referenceTime = now ?? DateTime.now();
  if (exercises.isEmpty) {
    return buildGlobalReadinessReport(
      history: history,
      bodyLogs: bodyLogs,
      now: referenceTime,
    );
  }

  final reports = exercises
      .map(
        (exercise) => buildExerciseReadinessReport(
          history: history,
          bodyLogs: bodyLogs,
          exerciseName: exercise.name,
          muscleGroup: exercise.muscleGroup,
          now: referenceTime,
          currentExercise: exercise,
        ),
      )
      .toList();
  var minimumScore = 100;
  var scoreTotal = 0;
  FatigueReadinessReport lowest = reports.first;
  for (final report in reports) {
    scoreTotal += report.score;
    if (report.score < minimumScore) {
      minimumScore = report.score;
      lowest = report;
    }
  }
  final averageScore = scoreTotal / reports.length;
  final score = (averageScore * 0.7 + minimumScore * 0.3)
      .round()
      .clamp(0, 100)
      .toInt();
  final status = _statusForScore(score);
  final global = buildGlobalReadinessReport(
    history: history,
    bodyLogs: bodyLogs,
    now: referenceTime,
  );
  final reasons = <String>{...lowest.reasons.take(3), ...global.reasons.take(2)}
      .toList();

  return FatigueReadinessReport(
    score: score,
    status: status,
    adaptation: _adaptationForStatus(status),
    reasons: reasons,
    sessionsLast7Days: global.sessionsLast7Days,
    hoursSinceLastStimulus: lowest.hoursSinceLastStimulus,
    averageRir: global.averageRir,
    averageRpe: global.averageRpe,
    acuteVolumeRatio: global.acuteVolumeRatio,
    estimatedOneRepMaxTrendPercent:
        lowest.estimatedOneRepMaxTrendPercent,
    selfReadiness: global.selfReadiness,
    sleepHours: global.sleepHours,
    recommendedLoadMultiplier: _loadMultiplierForStatus(status),
    recommendedSetReduction: _setReductionForStatus(status),
  );
}

ProgressionDecision applyReadinessToProgression'''

fatigue = sub_once(
    fatigue,
    r"FatigueReadinessReport buildGlobalReadinessReport\(\{.*?\n\}\n\nProgressionDecision applyReadinessToProgression",
    global_and_workout,
    'global/workout readiness',
)
fatigue_path.write_text(fatigue)


# ---------------------------------------------------------------------------
# Active workout integration.
# ---------------------------------------------------------------------------
path = Path('lib/screens/active_workout.dart')
text = path.read_text()
text = text.replace(
    "import '../models/exercise.dart';",
    "import '../models/body_log.dart';\nimport '../models/exercise.dart';",
    1,
)
text = text.replace(
    "import '../workout_plate_calculator.dart';",
    "import '../workout_fatigue_analytics.dart';\nimport '../workout_plate_calculator.dart';",
    1,
)
text = text.replace(
    '  final List<WorkoutSession> history;\n  final int defaultRestSeconds;',
    '  final List<WorkoutSession> history;\n  final List<BodyLog> bodyLogs;\n  final int defaultRestSeconds;',
    1,
)
text = text.replace(
    '    this.history = const [],\n    required this.defaultRestSeconds,',
    '    this.history = const [],\n    this.bodyLogs = const [],\n    required this.defaultRestSeconds,',
    3,
)
text = text.replace(
    '  late WorkoutSession session;\n  Timer? _restTimer;',
    '  late WorkoutSession session;\n  late List<BodyLog> _bodyLogs;\n  Timer? _restTimer;',
    1,
)

readiness_helpers = r'''  FatigueReadinessReport _readinessForExercise(
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
  }'''
text = sub_once(
    text,
    r"  ProgressionDecision _progressionDecisionFor\(WorkoutExercise exercise\) \{.*?\n  \}",
    readiness_helpers,
    'active readiness helpers',
)

readiness_sheet = r'''  Future<void> _showReadinessDetails(WorkoutExercise exercise) async {
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
                      label: Text(
                        '${report.hoursSinceLastStimulus}h recupero',
                      ),
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
                    Chip(
                      label: Text(
                        'Check-in ${report.selfReadiness}/10',
                      ),
                    ),
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
    final loadReduction = ((1 - report.recommendedLoadMultiplier) * 100).round();
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
            (set.weight * report.recommendedLoadMultiplier * 2).roundToDouble() /
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

'''
text = text.replace('  double _deloadWeight(double weight) {', readiness_sheet + '  double _deloadWeight(double weight) {', 1)

old_prefill = '''    final progressionDecision = previousExercise == null
        ? null
        : buildProgressionDecision(
            exercise: previousExercise,
            history: widget.history,
            excludeSessionId: previousSession?.id,
          );'''
new_prefill = '''    ProgressionDecision? progressionDecision;
    if (previousExercise != null) {
      final baseDecision = buildProgressionDecision(
        exercise: previousExercise,
        history: widget.history,
        excludeSessionId: previousSession?.id,
      );
      final readiness = buildExerciseReadinessReport(
        history: widget.history,
        bodyLogs: _bodyLogs,
        exerciseName: previousExercise.name,
        muscleGroup: previousExercise.muscleGroup,
        now: DateTime.now(),
      );
      progressionDecision = applyReadinessToProgression(
        decision: baseDecision,
        readiness: readiness,
      );
    }'''
if old_prefill not in text:
    raise RuntimeError('progression prefill anchor not found')
text = text.replace(old_prefill, new_prefill, 1)

load_method = r'''  Future<void> _loadReadinessBodyLogs() async {
    final bundle = await AppDataStore.loadBundle();
    if (!mounted || _bodyLogs.isNotEmpty) return;
    setState(() {
      _bodyLogs = List<BodyLog>.from(bundle.bodyLogs);
    });
  }

'''
text = text.replace('  @override\n  void initState() {', load_method + '  @override\n  void initState() {', 1)
text = text.replace(
    '''  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);''',
    '''  void initState() {
    super.initState();
    _bodyLogs = List<BodyLog>.from(widget.bodyLogs);
    if (_bodyLogs.isEmpty) {
      _loadReadinessBodyLogs();
    }
    WidgetsBinding.instance.addObserver(this);''',
    1,
)

text = text.replace(
    '''    final activeRestSeconds = activeRestExercise == null
        ? null
        : _restSecondsByExerciseId[activeRestExercise.id];''',
    '''    final activeRestSeconds = activeRestExercise == null
        ? null
        : _restSecondsByExerciseId[activeRestExercise.id];
    final workoutReadiness = _workoutReadiness();''',
    1,
)
text = text.replace(
    '''                child: Text(
                  _saveStatusLabel(),''',
    '''                child: Text(
                  '${_saveStatusLabel()} · Readiness ${workoutReadiness.score}/100 ${workoutReadiness.status.label}', ''',
    1,
)

history_chip = '''                          ActionChip(
                            key: ValueKey('exercise-history-${exercise.id}'),
                            avatar: const Icon(Icons.history, size: 18),
                            label: const Text('Storico'),
                            visualDensity: VisualDensity.compact,
                            onPressed: () => _showExerciseHistory(exercise),
                          ),'''
readiness_chip = history_chip + '''
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
                          ),'''
if history_chip not in text:
    raise RuntimeError('history chip anchor not found')
text = text.replace(history_chip, readiness_chip, 1)

# Add readiness chip to the progression explanation sheet.
text = text.replace(
    '''    final decision = _progressionDecisionFor(exercise);
    final theme = Theme.of(context);''',
    '''    final decision = _progressionDecisionFor(exercise);
    final readiness = _readinessForExercise(exercise);
    final theme = Theme.of(context);''',
    1,
)
text = text.replace(
    '''                  if (decision.effectiveRir != null)
                    Chip(''',
    '''                  Chip(
                    label: Text(
                      'Readiness ${readiness.score}/100 · ${readiness.status.label}',
                    ),
                  ),
                  if (decision.effectiveRir != null)
                    Chip(''',
    1,
)
path.write_text(text)


# ---------------------------------------------------------------------------
# Home: pass body logs to workout routes + show computed readiness.
# ---------------------------------------------------------------------------
home_path = Path('lib/screens/home.dart')
home = home_path.read_text()
home = home.replace(
    "import '../top_set_backoff.dart';",
    "import '../top_set_backoff.dart';\nimport '../workout_fatigue_analytics.dart';",
    1,
)
home = home.replace(
    '''          history: history,
          defaultRestSeconds: _defaultRestSeconds,''',
    '''          history: history,
          bodyLogs: bodyLogs,
          defaultRestSeconds: _defaultRestSeconds,''',
)
home = home.replace(
    '''                                      history: history,
                                      defaultRestSeconds: _defaultRestSeconds,''',
    '''                                      history: history,
                                      bodyLogs: bodyLogs,
                                      defaultRestSeconds: _defaultRestSeconds,''',
)
home = home.replace(
    '''    final planned = _nextPlannedWorkout();
    final latestBody = _latestBodyLog();''',
    '''    final planned = _nextPlannedWorkout();
    final latestBody = _latestBodyLog();
    final computedReadiness = buildGlobalReadinessReport(
      history: history,
      bodyLogs: bodyLogs,
    );''',
    1,
)
home = home.replace(
    '''                    value: latestBody?.readiness?.toString() ?? '--',
                    label: 'readiness',''',
    '''                    value: '${computedReadiness.score}',
                    label: '${computedReadiness.status.label.toLowerCase()} /100',''',
    1,
)
home_path.write_text(home)


# ---------------------------------------------------------------------------
# AI context: expose deterministic readiness and gate progression explanations.
# ---------------------------------------------------------------------------
context_path = Path('lib/ai_coach/training_context_builder.dart')
context = context_path.read_text()
context = context.replace(
    "import '../workout_progression_analytics.dart';",
    "import '../workout_fatigue_analytics.dart';\nimport '../workout_progression_analytics.dart';",
    1,
)
context = context.replace(
    '''        'progression_recommendations': _progressionRecommendations(
          analyticsHistory,
        ),''',
    '''        'fatigue_readiness': buildGlobalReadinessReport(
          history: analyticsHistory,
          bodyLogs: bodyLogs,
          now: _now,
        ).toJson(),
        'progression_recommendations': _progressionRecommendations(
          analyticsHistory,
          bodyLogs,
        ),''',
    1,
)
context = context.replace(
    '''  List<Map<String, dynamic>> _progressionRecommendations(
    List<WorkoutSession> history,
  ) {''',
    '''  List<Map<String, dynamic>> _progressionRecommendations(
    List<WorkoutSession> history,
    List<BodyLog> bodyLogs,
  ) {''',
    1,
)
old_decision = '''      final decision = buildProgressionDecision(
        exercise: exercise,
        history: previous,
      );
      return {'exercise': exercise.name, ...decision.toJson()};'''
new_decision = '''      final baseDecision = buildProgressionDecision(
        exercise: exercise,
        history: previous,
      );
      final readiness = buildExerciseReadinessReport(
        history: previous,
        bodyLogs: bodyLogs,
        exerciseName: exercise.name,
        muscleGroup: exercise.muscleGroup,
        now: _now,
        currentExercise: exercise,
      );
      final decision = applyReadinessToProgression(
        decision: baseDecision,
        readiness: readiness,
      );
      return {
        'exercise': exercise.name,
        ...decision.toJson(),
        'readiness': readiness.toJson(),
      };'''
if old_decision not in context:
    raise RuntimeError('AI progression decision anchor not found')
context = context.replace(old_decision, new_decision, 1)
context_path.write_text(context)

prompt_path = Path('lib/ai_coach/ai_coach_prompts.dart')
prompt = prompt_path.read_text()
prompt = prompt.replace(
    '- Treat deterministic progression recommendations as authoritative constraints: explain them, but do not contradict or replace their action with a different progression action.',
    '- Treat deterministic progression recommendations and fatigue_readiness as authoritative constraints: explain them, but do not contradict, override, or invent a different load/fatigue decision.',
    1,
)
prompt_path.write_text(prompt)
