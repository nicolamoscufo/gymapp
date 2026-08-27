import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gymapp/ai_coach/ai_action_protocol.dart';
import 'package:gymapp/ai_coach/ai_coach_models.dart';
import 'package:gymapp/ai_coach/ai_program_draft_service.dart';
import 'package:gymapp/ai_coach/chat_conversation.dart';
import 'package:gymapp/ai_coach/local_llm_engine.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('generates a typed multi-session draft with the full Coach context', () async {
    final engine = _DraftEngine([jsonEncode(_validDraftJson())]);
    final service = AiProgramDraftService(engine: engine);

    final proposal = await service.generate(
      userRequest: 'Fammi una scheda upper lower 4 giorni',
      history: const [],
      schedules: const [],
    );

    expect(proposal.kind, AiProgramActionKind.proposeProgram);
    expect(proposal.schedules, hasLength(2));
    expect(proposal.schedules.first.title, 'Upper A');
    expect(engine.initializeCalls, 1);
    expect(engine.prompts.single, contains('TASK: program_draft'));
    expect(engine.prompts.single, contains('Fammi una scheda upper lower 4 giorni'));
    expect(engine.prompts.single, contains('program_action_request'));
    expect(engine.prompts.single, contains('program_history'));
    expect(engine.prompts.single, contains('You NEVER save or apply anything yourself'));
    expect(engine.schemas.single['action'], 'propose_program|modify_program');
  });

  test('retries once when the first local model output is invalid', () async {
    final engine = _DraftEngine([
      'not-json',
      jsonEncode(_validDraftJson()),
    ]);
    final service = AiProgramDraftService(engine: engine);

    final proposal = await service.generate(
      userRequest: 'Crea una nuova routine',
      history: const [],
      schedules: const [],
    );

    expect(proposal.schedules, hasLength(2));
    expect(engine.prompts, hasLength(2));
    expect(
      engine.prompts.last,
      contains('Previous output was invalid'),
    );
  });

  test('empty action request is rejected before invoking the model', () async {
    final engine = _DraftEngine([jsonEncode(_validDraftJson())]);
    final service = AiProgramDraftService(engine: engine);

    await expectLater(
      service.generate(
        userRequest: '   ',
        history: const [],
        schedules: const [],
      ),
      throwsA(isA<FormatException>()),
    );
    expect(engine.initializeCalls, 0);
  });
}

Map<String, dynamic> _validDraftJson() => {
  'action': 'propose_program',
  'summary': 'Upper / Lower',
  'rationale': 'Distribuisce il volume su più sedute.',
  'evidence': ['profilo utente'],
  'confidence': 'medium',
  'requires_user_confirmation': true,
  'program_draft': {
    'schedules': [
      _scheduleJson('upper_a', 'Upper A', 1, 'Panca', 'chest'),
      _scheduleJson('lower_a', 'Lower A', 2, 'Squat', 'quadriceps'),
    ],
  },
};

Map<String, dynamic> _scheduleJson(
  String key,
  String title,
  int weekday,
  String exercise,
  String muscleGroup,
) => {
  'draft_key': key,
  'base_schedule_id': '',
  'base_version_id': '',
  'title': title,
  'goal': 'Ipertrofia',
  'mesocycle_weeks': 8,
  'deload_every_weeks': 4,
  'training_weekdays': [weekday],
  'program_block': 'Accumulo',
  'cycle_notes': '',
  'exercises': [
    {
      'source_exercise_id': '',
      'name': exercise,
      'sets': 3,
      'reps': 8,
      'weight': 80,
      'notes': '',
      'muscle_group': muscleGroup,
      'equipment': 'bilanciere',
      'movement_pattern': 'compound',
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
};

class _DraftEngine implements LocalLlmEngine {
  final List<String> responses;
  final List<String> prompts = [];
  final List<Map<String, dynamic>> schemas = [];
  int initializeCalls = 0;
  int _index = 0;

  _DraftEngine(this.responses);

  @override
  Future<void> initialize() async {
    initializeCalls += 1;
  }

  @override
  Future<void> dispose() async {}

  @override
  Future<String> generateStructuredJson(
    String prompt,
    Map<String, dynamic> schema,
  ) async {
    prompts.add(prompt);
    schemas.add(schema);
    final index = _index < responses.length ? _index : responses.length - 1;
    _index += 1;
    return responses[index];
  }

  @override
  Future<String> generateStructuredJsonWithImages(
    String prompt,
    Map<String, dynamic> schema,
    List<AiCoachImageInput> images,
  ) async => generateStructuredJson(prompt, schema);

  @override
  Future<String> generateText(String prompt) async =>
      generateStructuredJson(prompt, const {});

  @override
  Future<String> generateChatText({
    required String systemPrompt,
    required List<ChatMessage> messages,
    List<AiCoachImageInput> newImages = const [],
  }) async => responses.first;
}
