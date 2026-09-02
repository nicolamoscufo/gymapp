import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gymapp/ai_coach/ai_coach_model_manager.dart';
import 'package:gymapp/ai_coach/ai_coach_models.dart';
import 'package:gymapp/ai_coach/chat_conversation.dart';
import 'package:gymapp/ai_coach/exercise_catalog_retriever.dart';
import 'package:gymapp/ai_coach/local_ai_coach_service.dart';
import 'package:gymapp/ai_coach/local_llm_engine.dart';
import 'package:gymapp/exercise_catalog.dart';
import 'package:gymapp/screens/ai_coach.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('user can type and send a free-form Coach message', (tester) async {
    final engine = _CapturingEngine();

    await tester.pumpWidget(
      MaterialApp(
        home: AiCoachScreen(
          history: const [],
          schedules: const [],
          service: LocalAiCoachService(
            engine: engine,
            exerciseCatalogRetriever: ExerciseCatalogRetriever(
              catalogLoader: _emptyCatalog,
            ),
          ),
          modelInstaller: const _InstalledModel(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final sendFinder = find.byKey(const ValueKey('ai-chat-send'));
    final inputFinder = find.byKey(const ValueKey('ai-chat-input'));

    expect(sendFinder, findsOneWidget);
    expect(inputFinder, findsOneWidget);
    expect(
      tester.widget<IconButton>(sendFinder).onPressed,
      isNull,
      reason: 'An empty composer must not send an empty turn.',
    );

    await tester.enterText(
      inputFinder,
      'Come posso migliorare la mia tecnica in panca?',
    );
    await tester.pump();

    expect(
      tester.widget<IconButton>(sendFinder).onPressed,
      isNotNull,
      reason: 'Typing free text must immediately enable Send.',
    );

    await tester.tap(sendFinder);
    await tester.pump();
    for (var i = 0; i < 20 && engine.messages.isEmpty; i += 1) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(engine.messages, hasLength(1));
    expect(
      engine.messages.single.content,
      'Come posso migliorare la mia tecnica in panca?',
    );

    for (var i = 0;
        i < 10 && find.text('Risposta libera del Coach').evaluate().isEmpty;
        i += 1) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('Risposta libera del Coach'), findsOneWidget);
  });

  testWidgets('free chat keeps photo attachment and optional shortcuts visible', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AiCoachScreen(
          history: const [],
          schedules: const [],
          service: LocalAiCoachService(
            engine: _CapturingEngine(),
            exerciseCatalogRetriever: ExerciseCatalogRetriever(
              catalogLoader: _emptyCatalog,
            ),
          ),
          modelInstaller: const _InstalledModel(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('ai-chat-photo')), findsOneWidget);
    expect(find.text('Spunti rapidi (facoltativi)'), findsOneWidget);
    expect(
      find.textContaining('Scrivi liberamente nella chat'),
      findsOneWidget,
    );
  });
}

Future<List<ExerciseCatalogEntry>> _emptyCatalog() async => const [];

class _CapturingEngine implements LocalLlmEngine {
  List<ChatMessage> messages = const [];

  @override
  Future<void> initialize() async {}

  @override
  Future<void> dispose() async {}

  @override
  Future<String> generateText(String prompt) async => 'Risposta libera del Coach';

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
    this.messages = List<ChatMessage>.of(messages);
    return 'Risposta libera del Coach';
  }
}

class _InstalledModel implements AiCoachModelInstaller {
  const _InstalledModel();

  @override
  String get modelName => 'Fake Gemma';

  @override
  String get modelFileName => 'fake.litertlm';

  @override
  String get modelUrl => 'https://example.invalid/fake.litertlm';

  @override
  String get modelSizeLabel => '1 MB';

  @override
  Future<void> initialize() async {}

  @override
  Future<bool> isInstalled() async => true;

  @override
  Future<void> install({void Function(int progress)? onProgress}) async {}

  @override
  Future<void> activateInstalledModel() async {}
}
