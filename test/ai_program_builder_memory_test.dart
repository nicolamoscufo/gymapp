import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gymapp/ai_coach/ai_coach_memory.dart';
import 'package:gymapp/ai_coach/ai_program_conversation_coordinator.dart';
import 'package:gymapp/ai_coach/ai_program_draft_service.dart';
import 'package:gymapp/ai_coach/chat_conversation.dart';
import 'package:gymapp/ai_coach/local_llm_engine.dart';
import 'package:gymapp/ai_coach/ai_coach_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('Program Builder receives the latest persisted Coach memory', () async {
    await const AiCoachMemoryStore().save(
      const AiCoachMemory(
        recurringPreferences: ['manubri per le spinte del petto'],
      ),
    );

    final engine = _CapturingProgramEngine();
    final coordinator = AiProgramConversationCoordinator(
      draftService: AiProgramDraftService(engine: engine),
    );

    final result = await coordinator.handle(
      userRequest: 'Creami una nuova scheda upper lower',
      history: const [],
      schedules: const [],
      memory: const AiCoachMemory(
        recurringPreferences: ['questa memoria è vecchia'],
      ),
    );

    expect(result.hasDraft, isTrue);
    expect(engine.lastPrompt, contains('manubri per le spinte del petto'));
    expect(engine.lastPrompt, isNot(contains('questa memoria è vecchia')));
  });

  test('Program Builder captures explicit preferences in the same request', () async {
    final engine = _CapturingProgramEngine();
    final coordinator = AiProgramConversationCoordinator(
      draftService: AiProgramDraftService(engine: engine),
    );

    final result = await coordinator.handle(
      userRequest:
          'Creami una nuova scheda upper lower, preferisco i manubri per il petto.',
      history: const [],
      schedules: const [],
    );

    expect(result.hasDraft, isTrue);
    expect(engine.lastPrompt, contains('i manubri per il petto'));
    final persisted = await const AiCoachMemoryStore().load();
    expect(
      persisted.recurringPreferences,
      contains('i manubri per il petto'),
    );
  });
}

class _CapturingProgramEngine implements LocalLlmEngine {
  String lastPrompt = '';

  @override
  Future<void> initialize() async {}

  @override
  Future<void> dispose() async {}

  @override
  Future<String> generateText(String prompt) async => _response;

  @override
  Future<String> generateChatText({
    required String systemPrompt,
    required List<ChatMessage> messages,
    List<AiCoachImageInput> newImages = const [],
  }) async => _response;

  @override
  Future<String> generateStructuredJson(
    String prompt,
    Map<String, dynamic> schema,
  ) async {
    lastPrompt = prompt;
    return _response;
  }

  @override
  Future<String> generateStructuredJsonWithImages(
    String prompt,
    Map<String, dynamic> schema,
    List<AiCoachImageInput> images,
  ) async => generateStructuredJson(prompt, schema);
}

final String _response = jsonEncode({
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
});
