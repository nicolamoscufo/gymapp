import 'package:flutter_test/flutter_test.dart';
import 'package:gymapp/ai_coach/ai_coach_models.dart';
import 'package:gymapp/ai_coach/chat_conversation.dart';
import 'package:gymapp/ai_coach/exercise_catalog_retriever.dart';
import 'package:gymapp/ai_coach/local_ai_coach_service.dart';
import 'package:gymapp/ai_coach/local_llm_engine.dart';
import 'package:gymapp/models/exercise.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('explicit preference persists and personalizes a later chat', () async {
    final engine = _CapturingEngine();
    final service = LocalAiCoachService(
      engine: engine,
      exerciseCatalogRetriever: ExerciseCatalogRetriever(
        catalogLoader: _emptyCatalog,
      ),
    );

    await service.generateChatResponse(
      history: const [],
      schedules: const [],
      messages: [
        ChatMessage(role: 'user', content: 'Preferisco i manubri per il petto.'),
      ],
    );

    await service.generateChatResponse(
      history: const [],
      schedules: const [],
      messages: [
        ChatMessage(
          role: 'user',
          content: 'Cosa mi consiglieresti per allenare il petto oggi?',
        ),
      ],
    );

    expect(engine.lastSystemPrompt, contains('i manubri per il petto'));
    expect(engine.lastSystemPrompt, contains('memory'));
  });

  test('recovery question receives recovery-specific coaching mode', () async {
    final engine = _CapturingEngine();
    final service = LocalAiCoachService(
      engine: engine,
      exerciseCatalogRetriever: ExerciseCatalogRetriever(
        catalogLoader: _emptyCatalog,
      ),
    );

    await service.generateChatResponse(
      history: const [],
      schedules: const [],
      messages: [
        ChatMessage(
          role: 'user',
          content: 'Ho dormito poco e sono stanco: come gestisco il recupero?',
        ),
      ],
    );

    expect(engine.lastSystemPrompt, contains('Coaching mode: recovery'));
    expect(engine.lastSystemPrompt, contains('fatigue_readiness'));
    expect(engine.lastSystemPrompt, contains('training density'));
  });
}

Future<List<ExerciseCatalogEntry>> _emptyCatalog() async => const [];

class _CapturingEngine implements LocalLlmEngine {
  String lastSystemPrompt = '';

  @override
  Future<void> initialize() async {}

  @override
  Future<void> dispose() async {}

  @override
  Future<String> generateText(String prompt) async => 'ok';

  @override
  Future<String> generateChatText({
    required String systemPrompt,
    required List<ChatMessage> messages,
    List<AiCoachImageInput> newImages = const [],
  }) async {
    lastSystemPrompt = systemPrompt;
    return 'ok';
  }

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
}
