import 'dart:convert';

import '../models/body_log.dart';
import '../models/schedule.dart';
import '../models/schedule_version.dart';
import '../models/workout.dart';
import 'ai_coach_context_router.dart';
import 'ai_coach_memory.dart';
import 'ai_coach_memory_updater.dart';
import 'ai_coach_models.dart';
import 'ai_coach_prompts.dart';
import 'ai_coach_user_profile.dart';
import 'chat_conversation.dart';
import 'exercise_catalog_retriever.dart';
import 'local_llm_engine.dart';
import 'training_context_builder.dart';

const systemCoachingPrompt = '''
You are FitFlow AI Coach, an on-device personal training assistant.

Coaching contract:
- Answer the user's actual question first. Avoid generic motivational filler, long disclaimers, and restating the entire training context.
- Personalize only from supplied app data and user-declared memory. Never invent loads, reps, symptoms, preferences, exercise history, or goals.
- When a concrete recommendation depends on missing data, name the missing data instead of guessing.
- Prefer comparisons against the user's own verified history over generic population norms.
- Deterministic analytics are authoritative calculations. Use their exact direction and values when relevant; do not silently override them with model intuition.
- Separate observed facts from interpretation. Use calibrated language when evidence is limited or mixed.
- Historical schedule links are authoritative only when schedule_version_id resolves to a stored version. Never guess unresolved links.
- When focus_context is present, treat it as the authoritative scope before broader context.
- program_change_effectiveness reports associations only; it never proves causation. If evidence is sparse or links are unresolved, say insufficient data.
- exercise_catalog is metadata about exercise identity, muscles, equipment, and execution. It is not evidence that the user performed an exercise.
- memory contains only user-declared preferences, constraints, or notes. Respect it, but do not treat it as performance evidence.
- Give a small number of high-value actions. If useful, explain why using the user's own data.
- Suggestions never count as program changes until the user confirms them through the app.
- Do not diagnose injuries or prescribe medical treatment. For persistent or concerning pain, recommend evaluation by a qualified professional.
- Attached images are optional visual context. Answer the explicit training question about what is visibly shown. For physique/progress photos, discuss only visible training-related differences and image-comparison limitations; never infer diagnoses, health status, or sensitive traits.
- Answer in Italian unless the user writes in another language.
''';

class LocalAiCoachService {
  static const int _chatContextCharBudget = 7000;
  static const int _conversationReferenceCharBudget = 2200;

  final LocalLlmEngine engine;
  final LocalLlmEngine? fallbackEngine;
  final bool allowFallback;
  final TrainingContextBuilder contextBuilder;
  final ExerciseCatalogRetriever exerciseCatalogRetriever;
  final AiCoachContextRouter contextRouter;
  final AiCoachMemoryUpdater memoryUpdater;

  const LocalAiCoachService({
    this.engine = const FlutterGemmaLocalLlmEngine(),
    this.fallbackEngine,
    this.allowFallback = false,
    this.contextBuilder = const TrainingContextBuilder(),
    this.exerciseCatalogRetriever = const ExerciseCatalogRetriever(),
    this.contextRouter = const AiCoachContextRouter(),
    this.memoryUpdater = const AiCoachMemoryUpdater(),
  });

  Future<WorkoutRecap> generateWorkoutRecap({
    required List<WorkoutSession> history,
    required List<Schedule> schedules,
    List<ScheduleVersion> scheduleVersions = const [],
    List<BodyLog> bodyLogs = const [],
    AiCoachUserProfile profile = const AiCoachUserProfile(),
    AiCoachMemory memory = const AiCoachMemory(),
  }) async {
    if (history.isEmpty) {
      throw const AiCoachInsufficientDataException(
        'Complete at least one workout to generate a recap.',
      );
    }
    final context = contextBuilder.latestWorkout(
      history: history,
      schedules: schedules,
      scheduleVersions: scheduleVersions,
      bodyLogs: bodyLogs,
      profile: profile,
      memory: memory,
    );
    final json = await _generateJson(
      task: AiCoachTask.workoutRecap,
      context: context,
    );
    return WorkoutRecap.fromJson(json);
  }

  Future<WeeklyTrainingReport> generateWeeklyReport({
    required List<WorkoutSession> history,
    required List<Schedule> schedules,
    List<ScheduleVersion> scheduleVersions = const [],
    List<BodyLog> bodyLogs = const [],
    AiCoachUserProfile profile = const AiCoachUserProfile(),
    AiCoachMemory memory = const AiCoachMemory(),
  }) async {
    if (history.isEmpty) {
      throw const AiCoachInsufficientDataException(
        'Add at least 1-2 workouts to generate a weekly report.',
      );
    }
    final context = contextBuilder.weekly(
      history: history,
      schedules: schedules,
      scheduleVersions: scheduleVersions,
      bodyLogs: bodyLogs,
      profile: profile,
      memory: memory,
    );
    final json = await _generateJson(
      task: AiCoachTask.weeklyReport,
      context: context,
    );
    return WeeklyTrainingReport.fromJson(json);
  }

  Future<WeakPointAnalysis> analyzeWeakPoints({
    required List<WorkoutSession> history,
    required List<Schedule> schedules,
    List<ScheduleVersion> scheduleVersions = const [],
    List<BodyLog> bodyLogs = const [],
    AiCoachUserProfile profile = const AiCoachUserProfile(),
    AiCoachMemory memory = const AiCoachMemory(),
  }) async {
    if (history.length < 2) {
      throw const AiCoachInsufficientDataException(
        'At least 2-3 workouts are required to identify useful weak points.',
      );
    }
    final context = contextBuilder.recent(
      history: history,
      schedules: schedules,
      scheduleVersions: scheduleVersions,
      bodyLogs: bodyLogs,
      profile: profile,
      memory: memory,
    );
    final json = await _generateJson(
      task: AiCoachTask.weakPointAnalysis,
      context: context,
    );
    return WeakPointAnalysis.fromJson(json);
  }

  Future<NotesSummary> summarizeTrainingNotes({
    required List<WorkoutSession> history,
    required List<Schedule> schedules,
    List<ScheduleVersion> scheduleVersions = const [],
    List<BodyLog> bodyLogs = const [],
    AiCoachUserProfile profile = const AiCoachUserProfile(),
    AiCoachMemory memory = const AiCoachMemory(),
  }) async {
    final hasNotes = history
        .expand((session) => session.exercises)
        .any(
          (exercise) =>
              exercise.notes.trim().isNotEmpty ||
              exercise.sets.any((set) => set.notes.trim().isNotEmpty),
        );
    if (!hasNotes) {
      throw const AiCoachInsufficientDataException(
        'There are no notes to summarize. Add notes to sets or exercises.',
      );
    }
    final context = contextBuilder.notes(
      history: history,
      schedules: schedules,
      scheduleVersions: scheduleVersions,
      bodyLogs: bodyLogs,
      profile: profile,
      memory: memory,
    );
    final json = await _generateJson(
      task: AiCoachTask.notesSummary,
      context: context,
    );
    return NotesSummary.fromJson(json);
  }

  Future<SuggestedAdjustmentReport> suggestWorkoutAdjustments({
    required List<WorkoutSession> history,
    required List<Schedule> schedules,
    List<ScheduleVersion> scheduleVersions = const [],
    List<BodyLog> bodyLogs = const [],
    AiCoachUserProfile profile = const AiCoachUserProfile(),
    AiCoachMemory memory = const AiCoachMemory(),
  }) async {
    if (history.length < 2) {
      throw const AiCoachInsufficientDataException(
        'At least 2 workouts are required to suggest sensible adjustments.',
      );
    }
    final context = contextBuilder.recent(
      history: history,
      schedules: schedules,
      scheduleVersions: scheduleVersions,
      bodyLogs: bodyLogs,
      profile: profile,
      memory: memory,
    );
    final json = await _generateJson(
      task: AiCoachTask.suggestedAdjustments,
      context: context,
    );
    final report = SuggestedAdjustmentReport.fromJson(json);
    return SuggestedAdjustmentReport(
      suggestions: report.suggestions
          .map(
            (suggestion) => SuggestedAdjustment(
              type: suggestion.type,
              target: suggestion.target,
              suggestion: suggestion.suggestion,
              reason: suggestion.reason,
              evidence: suggestion.evidence,
              confidence: suggestion.confidence,
              requiresUserConfirmation: true,
              proposedActions: suggestion.proposedActions,
            ),
          )
          .toList(),
    );
  }

  Future<BodyPhotoAnalysis> analyzeBodyPhotos({
    required List<WorkoutSession> history,
    required List<Schedule> schedules,
    required List<AiCoachImageInput> images,
    List<ScheduleVersion> scheduleVersions = const [],
    List<BodyLog> bodyLogs = const [],
    AiCoachUserProfile profile = const AiCoachUserProfile(),
    AiCoachMemory memory = const AiCoachMemory(),
  }) async {
    if (images.length < 2) {
      throw const AiCoachInsufficientDataException(
        'Upload at least two progress photos to compare changes.',
      );
    }
    final context = contextBuilder.recent(
      history: history,
      schedules: schedules,
      scheduleVersions: scheduleVersions,
      bodyLogs: bodyLogs,
      profile: profile,
      memory: memory,
    );
    context['photo_inputs'] = images
        .map((image) => image.toContextJson())
        .toList();
    final json = await _generateJson(
      task: AiCoachTask.bodyPhotoAnalysis,
      context: context,
      images: images,
    );
    return BodyPhotoAnalysis.fromJson(json);
  }

  Future<String> generateChatResponse({
    required List<WorkoutSession> history,
    required List<Schedule> schedules,
    required List<ChatMessage> messages,
    List<ScheduleVersion> scheduleVersions = const [],
    List<BodyLog> bodyLogs = const [],
    AiCoachUserProfile profile = const AiCoachUserProfile(),
    AiCoachMemory memory = const AiCoachMemory(),
    List<AiCoachImageInput> newImages = const [],
    Map<String, dynamic>? focusContext,
  }) async {
    final latestUser = _latestUserMessage(messages);
    if (latestUser == null) {
      throw const AiCoachInsufficientDataException(
        'Scrivi una domanda prima di avviare il Coach.',
      );
    }
    final latestUserQuery = latestUser.content.trim();
    final resolvedMemory = await memoryUpdater.updateFromUserText(
      latestUserQuery,
      current: memory,
    );

    final context = contextBuilder.recent(
      history: history,
      schedules: schedules,
      scheduleVersions: scheduleVersions,
      bodyLogs: bodyLogs,
      profile: profile,
      memory: resolvedMemory,
    );
    if (focusContext != null && focusContext.isNotEmpty) {
      context['focus_context'] = focusContext;
    }

    if (latestUserQuery.isNotEmpty) {
      final catalogContext = await exerciseCatalogRetriever.retrieveForQuestion(
        query: latestUserQuery,
        preferredExerciseNames: schedules.expand(
          (schedule) => schedule.exercises.map((exercise) => exercise.name),
        ),
      );
      if (!catalogContext.isEmpty) {
        context['exercise_catalog'] = catalogContext.toJson();
      }
    }

    final longitudinal = _looksLongitudinal(latestUserQuery);
    final intent = contextRouter.classify(latestUserQuery);
    final compactContext = _compactContext(
      context,
      keepProgramHistory: longitudinal,
      maxWorkouts: longitudinal ? 2 : 4,
    );
    final routedContext = contextRouter.route(
      compactContext,
      intent: intent,
      keepProgramHistory: longitudinal,
    );
    final contextJson = _encodeBoundedContext(
      routedContext,
      keepProgramHistory: longitudinal,
    );
    final conversationReference = _conversationReference(
      messages,
      currentMessage: latestUser,
    );

    final systemPrompt = '''$systemCoachingPrompt
Coaching mode: ${intent.name}
${contextRouter.promptHint(intent)}

Training context (JSON):
$contextJson
${conversationReference.isEmpty ? '' : '\nRecent conversation for continuity only:\n$conversationReference\n'}
Response policy:
- Start with a direct answer, not a summary of the context.
- Ground personalized claims in the supplied data. Mention exact values only when they exist in the context.
- Give 1-4 prioritized actions rather than a long generic checklist.
- If evidence is insufficient, say what is missing and give the safest useful next step.
- Use focus_context first when present. Use program_history only when present.
- If exercise_catalog exists, use it only for exercise identity, target muscles, equipment, and execution instructions.''';

    final hasCurrentImages = latestUser.hasImages || newImages.isNotEmpty;
    final messageForInference = latestUserQuery.isEmpty && hasCurrentImages
        ? latestUser.copyWith(
            content:
                'Analizza le immagini allegate come contesto visivo per il mio allenamento. Descrivi solo ciò che è effettivamente visibile, segnala i limiti di una singola immagine e dammi indicazioni pratiche senza fare diagnosi.',
          )
        : latestUser;

    final currentMessage = newImages.isEmpty
        ? messageForInference
        : messageForInference.copyWith(
            imageBytes: newImages.map((image) => image.bytes).toList(),
            imageLabels: newImages.map((image) => image.label).toList(),
          );

    await engine.initialize();
    return engine.generateChatText(
      systemPrompt: systemPrompt,
      messages: [currentMessage],
      newImages: const [],
    );
  }

  Future<Map<String, dynamic>> _generateJson({
    required AiCoachTask task,
    required Map<String, dynamic> context,
    List<AiCoachImageInput> images = const [],
  }) async {
    final schema = AiCoachPromptSchemas.forTask(task);
    final compactContext = _compactContext(
      context,
      keepProgramHistory: false,
      maxWorkouts: 6,
    );
    final prompt = AiCoachPrompts.buildStructuredPrompt(
      task: task,
      context: compactContext,
      schema: schema,
    );

    await engine.initialize();
    try {
      final raw = images.isEmpty
          ? await engine.generateStructuredJson(prompt, schema)
          : await engine.generateStructuredJsonWithImages(
              prompt,
              schema,
              images,
            );
      return decodeJsonObject(raw);
    } catch (_) {
      try {
        final retryPrompt = AiCoachPrompts.buildStructuredPrompt(
          task: task,
          context: compactContext,
          schema: schema,
          strictRetry: true,
        );
        final raw = images.isEmpty
            ? await engine.generateStructuredJson(retryPrompt, schema)
            : await engine.generateStructuredJsonWithImages(
                retryPrompt,
                schema,
                images,
              );
        return decodeJsonObject(raw);
      } catch (_) {
        final fallback = fallbackEngine;
        if (allowFallback && fallback != null) {
          final fallbackRaw = await fallback.generateStructuredJson(
            prompt,
            schema,
          );
          return decodeJsonObject(fallbackRaw);
        }
        rethrow;
      }
    }
  }

  ChatMessage? _latestUserMessage(List<ChatMessage> messages) {
    for (final message in messages.reversed) {
      if (message.role == 'user') return message;
    }
    return null;
  }

  bool _looksLongitudinal(String query) {
    final lower = query.toLowerCase();
    const markers = [
      'programma',
      'scheda',
      'mesociclo',
      'cambiato',
      'cambiamento',
      'prima',
      'dopo',
      'storia',
      'storico',
      'versione',
      'progressione nel tempo',
    ];
    return markers.any(lower.contains);
  }

  Map<String, dynamic> _compactContext(
    Map<String, dynamic> source, {
    required bool keepProgramHistory,
    required int maxWorkouts,
  }) {
    final result = Map<String, dynamic>.from(source);

    result['workouts'] = _tail(result['workouts'], maxWorkouts);
    result['body_logs'] = _tail(result['body_logs'], 8);
    result['notes'] = _tail(result['notes'], 12);

    final plans = (result['active_plans'] as List? ?? const [])
        .whereType<Map>()
        .take(3)
        .map((plan) => _compactPlan(Map<String, dynamic>.from(plan)))
        .toList();
    result['active_plans'] = plans;

    if (!keepProgramHistory) {
      result.remove('program_history');
      result.remove('program_change_effectiveness');
    }

    return result;
  }

  Map<String, dynamic> _compactPlan(Map<String, dynamic> plan) {
    final exercises = (plan['exercises'] as List? ?? const [])
        .whereType<Map>()
        .map((exercise) {
          final item = Map<String, dynamic>.from(exercise);
          return {
            'id': item['id'],
            'catalogId': item['catalogId'],
            'name': item['name'],
            'set': item['set'],
            'reps': item['reps'],
            'weight': item['weight'],
            'targetMinReps': item['targetMinReps'],
            'targetMaxReps': item['targetMaxReps'],
            'technique': item['technique'],
            'backoffReps': item['backoffReps'],
            'backoffReductionPercent': item['backoffReductionPercent'],
            'restSeconds': item['restSeconds'],
            'progressionKgStep': item['progressionKgStep'],
            'progressionRepStep': item['progressionRepStep'],
            'progressionScheme': item['progressionScheme'],
          };
        })
        .toList();

    return {
      'id': plan['id'],
      'title': plan['title'],
      'week': plan['week'],
      'goal': plan['goal'],
      'programBlock': plan['programBlock'],
      'cycleNumber': plan['cycleNumber'],
      'currentVersionId': plan['currentVersionId'],
      'currentVersionNumber': plan['currentVersionNumber'],
      'exercises': exercises,
    };
  }

  List<dynamic> _tail(Object? raw, int count) {
    final list = raw is List ? raw : const <dynamic>[];
    if (list.length <= count) return List<dynamic>.from(list);
    return List<dynamic>.from(list.sublist(list.length - count));
  }

  String _encodeBoundedContext(
    Map<String, dynamic> original, {
    required bool keepProgramHistory,
  }) {
    final context = Map<String, dynamic>.from(original);
    var encoded = jsonEncode(context);
    if (encoded.length <= _chatContextCharBudget) return encoded;

    context['workouts'] = _tail(context['workouts'], 2);
    context['body_logs'] = _tail(context['body_logs'], 4);
    context['notes'] = _tail(context['notes'], 6);
    encoded = jsonEncode(context);
    if (encoded.length <= _chatContextCharBudget) return encoded;

    final analytics = context['deterministic_analytics'];
    if (analytics is Map) {
      final compactAnalytics = Map<String, dynamic>.from(analytics);
      compactAnalytics.remove('exercise_progress');
      compactAnalytics.remove('progression_recommendations');
      context['deterministic_analytics'] = compactAnalytics;
    }
    encoded = jsonEncode(context);
    if (encoded.length <= _chatContextCharBudget) return encoded;

    if (keepProgramHistory) {
      context.remove('workouts');
      context.remove('body_logs');
      context.remove('notes');
    } else {
      context.remove('active_plans');
    }
    encoded = jsonEncode(context);
    if (encoded.length <= _chatContextCharBudget) return encoded;

    context.remove('program_change_effectiveness');
    context.remove('program_history');
    encoded = jsonEncode(context);
    if (encoded.length <= _chatContextCharBudget) return encoded;

    context.remove('deterministic_analytics');
    return jsonEncode(context);
  }

  String _conversationReference(
    List<ChatMessage> messages, {
    required ChatMessage currentMessage,
  }) {
    final newestFirst = <String>[];
    var usedChars = 0;
    var skippedCurrent = false;

    for (final message in messages.reversed) {
      if (!skippedCurrent && identical(message, currentMessage)) {
        skippedCurrent = true;
        continue;
      }
      if (message.content.trim().isEmpty) continue;

      var text = message.content.trim().replaceAll(RegExp(r'\s+'), ' ');
      if (text.length > 600) text = '${text.substring(0, 600)}…';
      final line = '${message.role}: $text\n';
      if (usedChars + line.length > _conversationReferenceCharBudget) break;

      newestFirst.add(line);
      usedChars += line.length;
      if (newestFirst.length == 4) break;
    }

    return newestFirst.reversed.join().trim();
  }
}
