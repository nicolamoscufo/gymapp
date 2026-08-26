import 'dart:convert';

import '../models/body_log.dart';
import '../models/schedule.dart';
import '../models/schedule_version.dart';
import '../models/workout.dart';
import 'ai_action_protocol.dart';
import 'ai_coach_memory.dart';
import 'ai_coach_models.dart';
import 'ai_coach_user_profile.dart';
import 'local_llm_engine.dart';
import 'training_context_builder.dart';

class AiProgramDraftService {
  final LocalLlmEngine engine;
  final LocalLlmEngine? fallbackEngine;
  final bool allowFallback;
  final TrainingContextBuilder contextBuilder;

  const AiProgramDraftService({
    this.engine = const FlutterGemmaLocalLlmEngine(),
    this.fallbackEngine,
    this.allowFallback = false,
    this.contextBuilder = const TrainingContextBuilder(),
  });

  Future<AiProgramActionProposal> generate({
    required String userRequest,
    required List<WorkoutSession> history,
    required List<Schedule> schedules,
    List<ScheduleVersion> scheduleVersions = const [],
    List<BodyLog> bodyLogs = const [],
    AiCoachUserProfile profile = const AiCoachUserProfile(),
    AiCoachMemory memory = const AiCoachMemory(),
  }) async {
    final request = userRequest.trim();
    if (request.isEmpty) {
      throw const FormatException('Program draft request cannot be empty.');
    }

    final context = contextBuilder.recent(
      history: history,
      schedules: schedules,
      scheduleVersions: scheduleVersions,
      bodyLogs: bodyLogs,
      profile: profile,
      memory: memory,
    );
    context['program_action_request'] = {
      'user_request': request,
      'allowed_actions': const ['propose_program', 'modify_program'],
      'requires_user_confirmation': true,
    };

    final raw = await _generate(
      _prompt(context, strictRetry: false),
      _schema,
    );
    try {
      return AiProgramActionProposal.fromJson(decodeJsonObject(raw));
    } catch (_) {
      final retryRaw = await _generate(
        _prompt(context, strictRetry: true),
        _schema,
      );
      return AiProgramActionProposal.fromJson(decodeJsonObject(retryRaw));
    }
  }

  Future<String> _generate(
    String prompt,
    Map<String, dynamic> schema,
  ) async {
    await engine.initialize();
    try {
      return await engine.generateStructuredJson(prompt, schema);
    } catch (_) {
      final fallback = fallbackEngine;
      if (!allowFallback || fallback == null) rethrow;
      await fallback.initialize();
      return fallback.generateStructuredJson(prompt, schema);
    }
  }

  String _prompt(
    Map<String, dynamic> context, {
    required bool strictRetry,
  }) {
    final retry = strictRetry
        ? 'Previous output was invalid. Return ONLY one valid JSON object matching the schema exactly.'
        : 'Return ONLY one valid JSON object. No markdown and no prose outside JSON.';
    return '''
You are the program-building action component of FitFlow AI Coach.
Your job is to propose a complete editable workout-program draft. You NEVER save or apply anything yourself.

TASK: program_draft

Rules:
- Use only the supplied context and user request. Never invent past workout data.
- The output is a DRAFT that always requires explicit user confirmation before persistence.
- Choose action=propose_program when the user asks for a new program/routine/split.
- Choose action=modify_program when the user asks to change one or more existing active plans.
- A program may contain multiple schedule drafts. A 4-day program should normally contain four schedule drafts, not one schedule repeated four times, unless the user explicitly asks for that.
- Each schedule draft represents one reusable workout session.
- training_weekdays uses ISO weekday numbers: Monday=1 ... Sunday=7.
- For propose_program: base_schedule_id, base_version_id and every source_exercise_id MUST be empty strings. The app will generate identifiers after confirmation.
- For modify_program: when editing an existing schedule, copy base_schedule_id exactly from active_plans.id and base_version_id exactly from active_plans.currentVersionId. Do not invent identifiers.
- For modify_program: existing exercises that remain in the final schedule MUST copy source_exercise_id exactly from active_plans.exercises.id. New exercises MUST use an empty source_exercise_id.
- For a modified existing schedule, output the COMPLETE final exercise list for that schedule. Omitting an existing exercise means proposing its removal.
- Do not archive or delete whole schedules in this protocol version. Only propose modified existing schedules and/or additional new schedules.
- Respect user_profile preferences, equipment, available days, session duration and avoided exercises when provided.
- Use program_history and deterministic_analytics as evidence. Do not contradict deterministic progression/recovery facts without explicitly preserving the uncertainty in rationale.
- Use safe realistic numeric values. Do not prescribe medical treatment.
- confidence must be low, medium, or high.
- Every schedule needs a unique stable draft_key such as day_1, upper_a, lower_b. draft_key is only local draft metadata, never a database id.
- muscle_group must be one of: ${MuscleGroup.values.map((e) => e.name).join(', ')}.
- technique must be one of: ${IntensityTechnique.values.map((e) => e.name).join(', ')}.
- progression_scheme must be one of: ${ProgressionScheme.values.map((e) => e.name).join(', ')}.
- Use null for optional numeric fields when not needed.
- $retry

JSON schema shape:
${jsonEncode(_schema)}

<context_json>
${jsonEncode(context)}
</context_json>
''';
  }

  static const Map<String, dynamic> _schema = {
    'action': 'propose_program|modify_program',
    'summary': 'string',
    'rationale': 'string',
    'evidence': ['string'],
    'confidence': 'low|medium|high',
    'requires_user_confirmation': true,
    'program_draft': {
      'schedules': [
        {
          'draft_key': 'string_unique_within_this_draft',
          'base_schedule_id': 'exact_existing_id_or_empty',
          'base_version_id': 'exact_existing_current_version_id_or_empty',
          'title': 'string',
          'goal': 'string',
          'mesocycle_weeks': 'number',
          'deload_every_weeks': 'number_or_zero',
          'training_weekdays': ['number_1_to_7'],
          'program_block': 'string',
          'cycle_notes': 'string',
          'exercises': [
            {
              'source_exercise_id': 'exact_existing_id_or_empty',
              'name': 'string',
              'sets': 'number',
              'reps': 'number',
              'weight': 'number',
              'notes': 'string',
              'muscle_group': 'enum_name',
              'equipment': 'string',
              'movement_pattern': 'string',
              'target_min_reps': 'number_or_null',
              'target_max_reps': 'number_or_null',
              'technique': 'enum_name',
              'backoff_reps': 'number_or_null',
              'backoff_reduction_percent': 'number',
              'rest_seconds': 'number_or_null',
              'superset_group': 'number_or_null',
              'progression_kg_step': 'number',
              'progression_rep_step': 'number',
              'progression_scheme': 'enum_name',
            },
          ],
        },
      ],
    },
  };
}
