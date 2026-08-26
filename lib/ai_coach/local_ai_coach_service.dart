import 'dart:convert';

import '../models/body_log.dart';
import '../models/schedule.dart';
import '../models/workout.dart';
import 'ai_coach_memory.dart';
import 'ai_coach_models.dart';
import 'ai_coach_prompts.dart';
import 'ai_coach_user_profile.dart';
import 'chat_conversation.dart';
import 'local_llm_engine.dart';
import 'training_context_builder.dart';

const systemCoachingPrompt = '''
You are FitFlow AI Coach, an on-device personal training assistant. Your role is to help the user with their fitness journey by analyzing their workout data, providing coaching advice, answering training questions, and keeping them motivated.

Guidelines:
- Use the provided training context to give personalized advice.
- Be supportive but honest - celebrate wins and give constructive feedback.
- Never invent workout data, loads, reps, symptoms, or medical diagnoses.
- When discussing exercises or technique, suggest consulting a professional for pain or injuries.
- Keep responses concise, practical, and actionable.
- Answer in Italian unless the user writes in another language.
- You can discuss: workout analysis, training programs, exercise technique, nutrition basics, recovery, motivation, progress tracking.
- You cannot: diagnose injuries, prescribe medical treatment, provide specific medical nutrition plans.
- For photo analysis, discuss only visible training-related changes and photo quality caveats.
- Suggest specific changes as ideas that require user confirmation - never claim changes were applied.
''';

class LocalAiCoachService {
  final LocalLlmEngine engine;
  final LocalLlmEngine? fallbackEngine;
  final bool allowFallback;
  final TrainingContextBuilder contextBuilder;

  const LocalAiCoachService({
    this.engine = const FlutterGemmaLocalLlmEngine(),
    this.fallbackEngine,
    this.allowFallback = false,
    this.contextBuilder = const TrainingContextBuilder(),
  });

  Future<WorkoutRecap> generateWorkoutRecap({
    required List<WorkoutSession> history,
    required List<Schedule> schedules,
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
    List<BodyLog> bodyLogs = const [],
    AiCoachUserProfile profile = const AiCoachUserProfile(),
    AiCoachMemory memory = const AiCoachMemory(),
    List<AiCoachImageInput> newImages = const [],
    Map<String, dynamic>? focusContext,
  }) async {
    final context = contextBuilder.recent(
      history: history,
      schedules: schedules,
      bodyLogs: bodyLogs,
      profile: profile,
      memory: memory,
    );
    if (focusContext != null && focusContext.isNotEmpty) {
      context['focus_context'] = focusContext;
    }

    final contextJson = jsonEncode(context);
    final systemPrompt =
        '''$systemCoachingPrompt

Training context (JSON):
$contextJson

Answer naturally as a supportive but honest coach. Use the context to inform your answers.
If focus_context exists, it is the authoritative scope for the current discussion: use the exact target session and deterministic debrief values first, then enrich the explanation with the broader training context. Do not contradict deterministic metrics or recommendations without explicitly explaining the evidence and uncertainty.
Never invent workout data, loads, reps, or medical information.
Keep responses concise and practical.
Answer in Italian unless the user writes in another language.''';

    await engine.initialize();
    return engine.generateChatText(
      systemPrompt: systemPrompt,
      messages: messages,
      newImages: newImages,
    );
  }

  Future<Map<String, dynamic>> _generateJson({
    required AiCoachTask task,
    required Map<String, dynamic> context,
    List<AiCoachImageInput> images = const [],
  }) async {
    final schema = AiCoachPromptSchemas.forTask(task);
    final prompt = AiCoachPrompts.buildStructuredPrompt(
      task: task,
      context: context,
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
          context: context,
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
}
