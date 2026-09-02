import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gymapp/ai_coach/ai_coach_models.dart';
import 'package:gymapp/ai_coach/chat_conversation.dart';
import 'package:gymapp/ai_coach/local_ai_coach_service.dart';
import 'package:gymapp/ai_coach/local_llm_engine.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('image-only chat turn receives a useful visual instruction', () async {
    final engine = _CapturingEngine();
    final service = LocalAiCoachService(engine: engine);
    final bytes = Uint8List.fromList([1, 2, 3, 4]);

    await service.generateChatResponse(
      history: const [],
      schedules: const [],
      messages: [
        ChatMessage(
          role: 'user',
          content: '',
          imageBytes: [bytes],
          imageLabels: const ['progress.jpg'],
        ),
      ],
      newImages: [AiCoachImageInput(label: 'progress.jpg', bytes: bytes)],
    );

    expect(engine.messages, hasLength(1));
    expect(engine.messages.single.imageBytes, hasLength(1));
    expect(
      engine.messages.single.content,
      contains('Analizza le immagini allegate'),
    );
    expect(engine.systemPrompt, contains('Attached images are optional visual context'));
  });
}

class _CapturingEngine implements LocalLlmEngine {
  List<ChatMessage> messages = const [];
  String systemPrompt = '';

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
    this.systemPrompt = systemPrompt;
    this.messages = List<ChatMessage>.of(messages);
    return 'ok';
  }
}
