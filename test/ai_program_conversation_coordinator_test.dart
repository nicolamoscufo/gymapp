import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gymapp/ai_coach/ai_action_protocol.dart';
import 'package:gymapp/ai_coach/ai_coach_models.dart';
import 'package:gymapp/ai_coach/ai_program_conversation_coordinator.dart';
import 'package:gymapp/ai_coach/ai_program_draft_service.dart';
import 'package:gymapp/ai_coach/chat_conversation.dart';
import 'package:gymapp/ai_coach/local_llm_engine.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('normal coaching question is left to the regular chat path', () async {
    final engine = _Engine(jsonEncode(_proposalJson()));
    final coordinator = AiProgramConversationCoordinator(
      draftService: AiProgramDraftService(engine: engine),
    );

    final result = await coordinator.handle(
      userRequest: 'Come sta andando la mia panca?',
      history: const [],
      schedules: const [],
    );

    expect(result.isProgramActionIntent, isFalse);
    expect(result.assistantMessage, isNull);
    expect(engine.calls, 0);
  });

  test('program mutation request becomes a persisted-action capable message', () async {
    final engine = _Engine(jsonEncode(_proposalJson()));
    final coordinator = AiProgramConversationCoordinator(
      draftService: AiProgramDraftService(engine: engine),
    );

    final result = await coordinator.handle(
      userRequest: 'Fammi una nuova scheda upper lower',
      history: const [],
      schedules: const [],
    );

    expect(result.isProgramActionIntent, isTrue);
    expect(result.hasDraft, isTrue);
    expect(engine.calls, 1);
    final message = result.assistantMessage!;
    expect(message.role, 'assistant');
    final proposal = programDraftFromMessage(message);
    expect(proposal, isNotNull);
    expect(proposal!.kind, AiProgramActionKind.proposeProgram);
    expect(proposal.schedules.single.title, 'Upper A');
  });

  test('invalid generated draft is handled but never exposed as actionable', () async {
    final invalid = _proposalJson();
    final schedule = Map<String, dynamic>.from(
      ((invalid['program_draft'] as Map)['schedules'] as List).single as Map,
    );
    schedule['exercises'] = [
      {
        ...Map<String, dynamic>.from((schedule['exercises'] as List).single as Map),
        'sets': 0,
      },
    ];
    (invalid['program_draft'] as Map)['schedules'] = [schedule];
    final engine = _Engine(jsonEncode(invalid));
    final coordinator = AiProgramConversationCoordinator(
      draftService: AiProgramDraftService(engine: engine),
    );

    final result = await coordinator.handle(
      userRequest: 'Creami una scheda nuova',
      history: const [],
      schedules: const [],
    );

    expect(result.isProgramActionIntent, isTrue);
    expect(result.hasDraft, isFalse);
    expect(result.assistantMessage, isNull);
    expect(result.validationErrors.any((e) => e.endsWith(':invalid_sets')), isTrue);
  });
}

Map<String, dynamic> _proposalJson() => {
  'action': 'propose_program',
  'summary': 'Upper A',
  'rationale': 'Bozza basata sulla richiesta.',
  'evidence': const [],
  'confidence': 'medium',
  'requires_user_confirmation': true,
  'program_draft': {
    'schedules': [
      {
        'draft_key': 'upper_a',
        'base_schedule_id': '',
        'base_version_id': '',
        'title': 'Upper A',
        'goal': 'Ipertrofia',
        'mesocycle_weeks': 8,
        'deload_every_weeks': 4,
        'training_weekdays': [1],
        'program_block': '',
        'cycle_notes': '',
        'exercises': [
          {
            'source_exercise_id': '',
            'name': 'Panca',
            'sets': 3,
            'reps': 8,
            'weight': 80,
            'notes': '',
            'muscle_group': 'chest',
            'equipment': 'bilanciere',
            'movement_pattern': 'spinta',
            'target_min_reps': 6,
            'target_max_reps': 10,
            'technique': 'none',
            'backoff_reps': null,
            'backoff_reduction_percent': 10,
            'rest_seconds': 120,
            'superset_group': null,
            'progression_kg_step': 2.5,
            'progression_rep_step': 1,
            'progression_scheme': 'doubleProgression',
          },
        ],
      },
    ],
  },
};

class _Engine implements LocalLlmEngine {
  final String response;
  int calls = 0;

  _Engine(this.response);

  @override
  Future<void> initialize() async {}

  @override
  Future<void> dispose() async {}

  @override
  Future<String> generateStructuredJson(
    String prompt,
    Map<String, dynamic> schema,
  ) async {
    calls += 1;
    return response;
  }

  @override
  Future<String> generateStructuredJsonWithImages(
    String prompt,
    Map<String, dynamic> schema,
    List<AiCoachImageInput> images,
  ) async => generateStructuredJson(prompt, schema);

  @override
  Future<String> generateText(String prompt) async => response;

  @override
  Future<String> generateChatText({
    required String systemPrompt,
    required List<ChatMessage> messages,
    List<AiCoachImageInput> newImages = const [],
  }) async => response;
}
