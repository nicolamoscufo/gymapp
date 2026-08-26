import 'package:flutter_test/flutter_test.dart';
import 'package:gymapp/ai_coach/ai_coach_models.dart';
import 'package:gymapp/ai_coach/chat_conversation.dart';
import 'package:gymapp/ai_coach/exercise_catalog_retriever.dart';
import 'package:gymapp/ai_coach/local_ai_coach_service.dart';
import 'package:gymapp/ai_coach/local_llm_engine.dart';
import 'package:gymapp/exercise_catalog.dart';
import 'package:gymapp/models/exercise.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('chat injects relevant local catalog record and instructions', () async {
    final engine = _CapturingEngine();
    final service = LocalAiCoachService(
      engine: engine,
      exerciseCatalogRetriever: ExerciseCatalogRetriever(
        catalogLoader: _catalogLoader,
      ),
    );

    await service.generateChatResponse(
      history: const [],
      schedules: const [],
      messages: [
        ChatMessage(
          role: 'user',
          content: 'Come eseguo il cable standing fly per il petto?',
        ),
      ],
    );

    expect(engine.lastSystemPrompt, contains('exercise_catalog'));
    expect(engine.lastSystemPrompt, contains('cable_fly'));
    expect(engine.lastSystemPrompt, contains('Bring the handles together'));
    expect(engine.lastSystemPrompt, isNot(contains('barbell_squat')));
  });

  test('unrelated chat does not inject arbitrary catalog rows', () async {
    final engine = _CapturingEngine();
    final service = LocalAiCoachService(
      engine: engine,
      exerciseCatalogRetriever: ExerciseCatalogRetriever(
        catalogLoader: _catalogLoader,
      ),
    );

    await service.generateChatResponse(
      history: const [],
      schedules: const [],
      messages: [
        ChatMessage(role: 'user', content: 'Come sto andando questa settimana?'),
      ],
    );

    expect(engine.lastSystemPrompt, isNot(contains('"exercise_catalog"')));
  });
}

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
    instructions: ['Set the pulleys.', 'Bring the handles together.'],
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
  String lastSystemPrompt = '';

  @override
  Future<void> initialize() async {}

  @override
  Future<void> dispose() async {}

  @override
  Future<String> generateText(String prompt) async => 'ok';

  @override
  Future<String> generateStructuredJson(
    String prompt,
    Map<String, dynamic> schema,
  ) async => '{}';

  @override
  Future<String> generateStructuredJsonWithImages(
    String prompt,
    Map<String, dynamic> schema,
    List<AiCoachImageInput> images,
  ) async => '{}';

  @override
  Future<String> generateChatText({
    required String systemPrompt,
    required List<ChatMessage> messages,
    List<AiCoachImageInput> newImages = const [],
  }) async {
    lastSystemPrompt = systemPrompt;
    return 'ok';
  }
}
