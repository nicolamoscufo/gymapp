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

  test('chat inference sends only the active user turn to the runtime', () async {
    final engine = _CapturingEngine();
    final service = LocalAiCoachService(engine: engine);

    final response = await service.generateChatResponse(
      history: const [],
      schedules: const [],
      messages: [
        ChatMessage(role: 'user', content: 'Messaggio precedente'),
        ChatMessage(role: 'assistant', content: 'Risposta precedente'),
        ChatMessage(role: 'user', content: 'Domanda corrente'),
      ],
    );

    expect(response, 'ok');
    expect(engine.initializeCalls, 1);
    expect(engine.generateChatCalls, 1);
    expect(engine.messages, hasLength(1));
    expect(engine.messages.single.role, 'user');
    expect(engine.messages.single.content, 'Domanda corrente');
    expect(engine.newImages, isEmpty);

    final prompt = engine.systemPrompt ?? '';
    expect(prompt, contains('Messaggio precedente'));
    expect(prompt, contains('Risposta precedente'));
    expect(prompt, contains('Recent conversation for continuity only'));
  });

  test('conversation reference is bounded before reaching the runtime', () async {
    final engine = _CapturingEngine();
    final service = LocalAiCoachService(engine: engine);
    final messages = <ChatMessage>[];

    for (var i = 0; i < 12; i++) {
      messages.add(
        ChatMessage(
          role: i.isEven ? 'user' : 'assistant',
          content: 'turn-$i ${'x' * 900}',
        ),
      );
    }
    messages.add(ChatMessage(role: 'user', content: 'Domanda finale'));

    await service.generateChatResponse(
      history: const [],
      schedules: const [],
      messages: messages,
    );

    expect(engine.messages, hasLength(1));
    expect(engine.messages.single.content, 'Domanda finale');

    final prompt = engine.systemPrompt ?? '';
    expect(prompt.length, lessThan(12000));
    expect(prompt, contains('turn-11'));
    expect(prompt, isNot(contains('turn-0')));
  });
}

class _CapturingEngine implements LocalLlmEngine {
  int initializeCalls = 0;
  int generateChatCalls = 0;
  String? systemPrompt;
  List<ChatMessage> messages = const [];
  List<AiCoachImageInput> newImages = const [];

  @override
  Future<void> initialize() async {
    initializeCalls += 1;
  }

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
    generateChatCalls += 1;
    this.systemPrompt = systemPrompt;
    this.messages = List<ChatMessage>.of(messages);
    this.newImages = List<AiCoachImageInput>.of(newImages);
    return 'ok';
  }
}
