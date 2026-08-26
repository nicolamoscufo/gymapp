import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gymapp/ai_coach/ai_coach_models.dart';
import 'package:gymapp/ai_coach/ai_program_draft_service.dart';
import 'package:gymapp/ai_coach/chat_conversation.dart';
import 'package:gymapp/ai_coach/exercise_catalog_retriever.dart';
import 'package:gymapp/ai_coach/local_llm_engine.dart';
import 'package:gymapp/exercise_catalog.dart';
import 'package:gymapp/models/exercise.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('Program Builder receives compact local catalog shortlist', () async {
    final engine = _CapturingEngine(jsonEncode(_proposal()));
    final service = AiProgramDraftService(
      engine: engine,
      exerciseCatalogRetriever: ExerciseCatalogRetriever(
        catalogLoader: _catalogLoader,
      ),
    );

    final result = await service.generate(
      userRequest: 'Fammi una scheda upper lower con manubri e cavi',
      history: const [],
      schedules: const [],
    );

    expect(result.schedules, hasLength(1));
    expect(engine.lastPrompt, contains('exercise_catalog'));
    expect(engine.lastPrompt, contains('cable_fly'));
    expect(engine.lastPrompt, contains('db_row'));
    expect(engine.lastPrompt, isNot(contains('barbell_squat')));
    expect(engine.lastPrompt, isNot(contains('Set the pulleys.')));
  });
}

Map<String, dynamic> _proposal() => {
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
            'name': 'cable standing fly',
            'sets': 3,
            'reps': 10,
            'weight': 0,
            'notes': '',
            'muscle_group': 'chest',
            'equipment': 'cable',
            'movement_pattern': 'Spinta',
            'target_min_reps': 8,
            'target_max_reps': 12,
            'technique': 'none',
            'backoff_reps': null,
            'backoff_reduction_percent': 10,
            'rest_seconds': 90,
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

Future<List<ExerciseCatalogEntry>> _catalogLoader() async => const [
  ExerciseCatalogEntry(
    id: 'cable_fly',
    name: 'cable standing fly',
    muscleGroup: MuscleGroup.chest,
    equipment: 'cable',
    movementPattern: 'Spinta',
    bodyPart: 'chest',
    target: 'pectorals',
    secondaryMuscles: ['deltoids'],
    instructions: ['Set the pulleys.'],
    gifUrl: '',
  ),
  ExerciseCatalogEntry(
    id: 'db_row',
    name: 'dumbbell row',
    muscleGroup: MuscleGroup.back,
    equipment: 'dumbbell',
    movementPattern: 'Tirata',
    bodyPart: 'back',
    target: 'lats',
    secondaryMuscles: ['biceps'],
    instructions: ['Row the dumbbell.'],
    gifUrl: '',
  ),
  ExerciseCatalogEntry(
    id: 'barbell_squat',
    name: 'barbell squat',
    muscleGroup: MuscleGroup.quadriceps,
    equipment: 'barbell',
    movementPattern: 'Gambe',
    bodyPart: 'upper legs',
    target: 'quadriceps',
    secondaryMuscles: ['glutes'],
    instructions: ['Squat under control.'],
    gifUrl: '',
  ),
];

class _CapturingEngine implements LocalLlmEngine {
  final String response;
  String lastPrompt = '';

  _CapturingEngine(this.response);

  @override
  Future<void> initialize() async {}

  @override
  Future<void> dispose() async {}

  @override
  Future<String> generateStructuredJson(
    String prompt,
    Map<String, dynamic> schema,
  ) async {
    lastPrompt = prompt;
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
