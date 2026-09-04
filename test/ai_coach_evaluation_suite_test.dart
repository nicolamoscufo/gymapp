import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gymapp/ai_coach/ai_coach_context_router.dart';
import 'package:gymapp/ai_coach/ai_coach_memory.dart';
import 'package:gymapp/ai_coach/ai_coach_memory_updater.dart';
import 'package:gymapp/ai_coach/ai_coach_models.dart';
import 'package:gymapp/ai_coach/ai_coach_user_profile.dart';
import 'package:gymapp/ai_coach/ai_program_intent_gate.dart';
import 'package:gymapp/ai_coach/chat_conversation.dart';
import 'package:gymapp/ai_coach/exercise_catalog_retriever.dart';
import 'package:gymapp/ai_coach/local_ai_coach_service.dart';
import 'package:gymapp/ai_coach/local_llm_engine.dart';
import 'package:gymapp/ai_coach/training_context_builder.dart';
import 'package:gymapp/models/body_log.dart';
import 'package:gymapp/models/schedule.dart';
import 'package:gymapp/models/schedule_version.dart';
import 'package:gymapp/models/workout.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fixtures/ai_coach_eval_corpus.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('AI Coach eval corpus', () {
    test('contains a broad, balanced and uniquely identified benchmark', () {
      expect(aiCoachEvalCorpus.length, greaterThanOrEqualTo(80));
      expect(
        aiCoachEvalCorpus.map((entry) => entry.id).toSet().length,
        aiCoachEvalCorpus.length,
      );

      for (final intent in AiCoachChatIntent.values) {
        final count = aiCoachEvalCorpus
            .where((entry) => entry.intent == intent)
            .length;
        expect(count, greaterThanOrEqualTo(8), reason: 'coverage for $intent');
      }
      expect(
        aiCoachEvalCorpus.where((entry) => entry.tags.contains('medical')).length,
        greaterThanOrEqualTo(3),
      );
      expect(
        aiCoachEvalCorpus.where((entry) => entry.tags.contains('image')).length,
        greaterThanOrEqualTo(2),
      );
      expect(
        aiCoachEvalCorpus.where((entry) => entry.programMutation).length,
        greaterThanOrEqualTo(10),
      );
    });

    for (final eval in aiCoachEvalCorpus) {
      test('${eval.id} routes to ${eval.intent.name}', () {
        expect(
          const AiCoachContextRouter().classify(eval.query),
          eval.intent,
          reason: eval.query,
        );
      });

      test('${eval.id} program mutation gate is ${eval.programMutation}', () {
        expect(
          const AiProgramIntentGate().isMutationRequest(eval.query),
          eval.programMutation,
          reason: eval.query,
        );
      });
    }
  });

  group('AI Coach prompt contract', () {
    test('hard safety and grounding invariants stay in the system prompt', () {
      final prompt = systemCoachingPrompt.toLowerCase();
      expect(prompt, contains('never invent loads, reps, symptoms'));
      expect(prompt, contains('missing data'));
      expect(prompt, contains('never proves causation'));
      expect(prompt, contains('insufficient data'));
      expect(prompt, contains('do not diagnose injuries'));
      expect(prompt, contains('qualified professional'));
      expect(prompt, contains('suggestions never count as program changes'));
      expect(prompt, contains('user confirms them through the app'));
      expect(prompt, contains('attached images are optional visual context'));
      expect(prompt, contains('never infer diagnoses'));
      expect(prompt, contains('sensitive traits'));
    });

    test('each routing mode keeps only its relevant context family', () {
      final router = const AiCoachContextRouter();
      final source = _fixtureContext();

      final technique = router.route(
        source,
        intent: AiCoachChatIntent.technique,
        keepProgramHistory: false,
      );
      expect(technique['body_logs'], isEmpty);
      expect(technique.containsKey('metrics'), isFalse);
      expect(technique.containsKey('program_history'), isFalse);
      expect(
        (technique['deterministic_analytics'] as Map).keys.toSet(),
        {'exercise_progress', 'progression_recommendations'},
      );

      final recovery = router.route(
        _fixtureContext(),
        intent: AiCoachChatIntent.recovery,
        keepProgramHistory: false,
      );
      expect((recovery['body_logs'] as List).length, 8);
      expect((recovery['active_plans'] as List).length, 1);
      expect(
        (recovery['deterministic_analytics'] as Map).keys.toSet(),
        {'fatigue_readiness', 'latest_session_at', 'session_count'},
      );

      final program = router.route(
        _fixtureContext(),
        intent: AiCoachChatIntent.program,
        keepProgramHistory: true,
      );
      expect(program.containsKey('program_history'), isTrue);
      expect(program.containsKey('program_change_effectiveness'), isTrue);

      final general = router.route(
        _fixtureContext(),
        intent: AiCoachChatIntent.general,
        keepProgramHistory: false,
      );
      expect(general.containsKey('program_history'), isFalse);
      expect((general['workouts'] as List).length, 3);
      expect((general['body_logs'] as List).length, 4);
    });

    test('real chat prompt exposes the selected mode and only current user turn', () async {
      for (final eval in [
        aiCoachEvalCorpus.firstWhere((entry) => entry.id == 'tech-01'),
        aiCoachEvalCorpus.firstWhere((entry) => entry.id == 'prog-05'),
        aiCoachEvalCorpus.firstWhere((entry) => entry.id == 'recovery-04'),
        aiCoachEvalCorpus.firstWhere((entry) => entry.id == 'progress-07'),
        aiCoachEvalCorpus.firstWhere((entry) => entry.id == 'program-discuss-01'),
        aiCoachEvalCorpus.firstWhere((entry) => entry.id == 'general-04'),
      ]) {
        final engine = _CaptureEngine();
        final service = _service(engine, context: _fixtureContext());
        final current = ChatMessage(role: 'user', content: eval.query);
        await service.generateChatResponse(
          history: const [],
          schedules: const [],
          messages: [
            ChatMessage(role: 'user', content: 'Messaggio precedente'),
            ChatMessage(role: 'assistant', content: 'Risposta precedente'),
            current,
          ],
        );

        expect(engine.systemPrompt, contains('Coaching mode: ${eval.intent.name}'));
        expect(engine.messages, hasLength(1));
        expect(engine.messages.single.content, eval.query);
        expect(engine.newImages, isEmpty);
      }
    });

    test('context and conversation references remain inside their hard budgets', () async {
      final engine = _CaptureEngine();
      final huge = _fixtureContext(huge: true);
      final service = _service(engine, context: huge);
      final messages = <ChatMessage>[
        for (var i = 0; i < 12; i += 1)
          ChatMessage(
            role: i.isEven ? 'user' : 'assistant',
            content: 'history-$i ${'x' * 900}',
          ),
        ChatMessage(role: 'user', content: 'Mi dai un consiglio?'),
      ];

      await service.generateChatResponse(
        history: const [],
        schedules: const [],
        messages: messages,
      );

      final contextJson = _extractContextJson(engine.systemPrompt!);
      final conversation = _extractConversationReference(engine.systemPrompt!);
      expect(contextJson.length, lessThanOrEqualTo(7000));
      expect(conversation.length, lessThanOrEqualTo(2200));
      expect(engine.messages, hasLength(1));
      expect(engine.messages.single.content, 'Mi dai un consiglio?');
      expect(conversation, contains('history-11'));
      expect(conversation, isNot(contains('history-0')));
    });

    test('focus context is retained and explicitly takes precedence', () async {
      final engine = _CaptureEngine();
      final service = _service(engine, context: _fixtureContext());
      await service.generateChatResponse(
        history: const [],
        schedules: const [],
        messages: [ChatMessage(role: 'user', content: 'Come faccio bene la panca?')],
        focusContext: const {
          'session_id': 'session-live',
          'exercise_id': 'bench-id',
          'set_id': 'set-2',
        },
      );

      final context = jsonDecode(_extractContextJson(engine.systemPrompt!)) as Map;
      expect(context['focus_context']['exercise_id'], 'bench-id');
      expect(engine.systemPrompt, contains('Use focus_context first'));
    });

    test('image-only turns get a bounded neutral visual instruction', () async {
      final engine = _CaptureEngine();
      final service = _service(engine, context: _fixtureContext());
      final bytes = Uint8List.fromList([1, 2, 3, 4]);

      await service.generateChatResponse(
        history: const [],
        schedules: const [],
        messages: [
          ChatMessage(
            role: 'user',
            content: '',
            imageBytes: [bytes],
            imageLabels: const ['panca.jpg'],
          ),
        ],
      );

      expect(engine.messages, hasLength(1));
      expect(engine.messages.single.imageBytes, hasLength(1));
      expect(
        engine.messages.single.content,
        contains('Descrivi solo ciò che è effettivamente visibile'),
      );
      expect(engine.messages.single.content.toLowerCase(), contains('senza fare diagnosi'));
    });

    test('text and newly attached photos travel in one current turn only', () async {
      final engine = _CaptureEngine();
      final service = _service(engine, context: _fixtureContext());
      final image = AiCoachImageInput(
        label: 'setup.jpg',
        bytes: Uint8List.fromList([7, 8, 9]),
      );

      await service.generateChatResponse(
        history: const [],
        schedules: const [],
        messages: [
          ChatMessage(role: 'assistant', content: 'Contesto precedente'),
          ChatMessage(
            role: 'user',
            content: 'La posizione dei gomiti in panca è corretta?',
          ),
        ],
        newImages: [image],
      );

      expect(engine.messages, hasLength(1));
      expect(engine.messages.single.content, contains('gomiti'));
      expect(engine.messages.single.imageBytes, hasLength(1));
      expect(engine.messages.single.imageLabels, ['setup.jpg']);
      expect(engine.newImages, isEmpty);
      expect(engine.systemPrompt, contains('Coaching mode: technique'));
    });
  });

  group('AI Coach memory evals', () {
    test('explicit preferences, limitations and notes are captured separately', () async {
      final memory = await const AiCoachMemoryUpdater().updateFromUserText(
        'Preferisco i manubri; non voglio fare stacchi; ricorda che mi alleno la sera.',
      );

      expect(memory.recurringPreferences, contains('i manubri'));
      expect(memory.recurringLimitations, contains('stacchi'));
      expect(memory.coachingNotes, contains('mi alleno la sera'));
    });

    test('ordinary chat is not silently promoted to persistent memory', () async {
      final memory = await const AiCoachMemoryUpdater().updateFromUserText(
        'Oggi mi sento bene e penso che la panca sia andata forte.',
      );
      expect(memory.isEmpty, isTrue);
    });

    test('clear command removes persisted Coach memory', () async {
      final updater = const AiCoachMemoryUpdater();
      await updater.updateFromUserText('Preferisco allenarmi con i manubri.');
      final cleared = await updater.updateFromUserText(
        'Cancella tutta la memoria del coach.',
      );
      expect(cleared.isEmpty, isTrue);
      expect((await const AiCoachMemoryStore().load()).isEmpty, isTrue);
    });
  });

  group('AI Coach insufficient-data evals', () {
    test('structured recap fails closed with no workout history', () async {
      final service = LocalAiCoachService(
        engine: _CaptureEngine(),
        exerciseCatalogRetriever: ExerciseCatalogRetriever(
          catalogLoader: () async => const [],
        ),
      );
      expect(
        () => service.generateWorkoutRecap(history: const [], schedules: const []),
        throwsA(isA<AiCoachInsufficientDataException>()),
      );
    });

    test('body photo comparison requires at least two images', () async {
      final service = LocalAiCoachService(
        engine: _CaptureEngine(),
        exerciseCatalogRetriever: ExerciseCatalogRetriever(
          catalogLoader: () async => const [],
        ),
      );
      expect(
        () => service.analyzeBodyPhotos(
          history: const [],
          schedules: const [],
          images: [
            AiCoachImageInput(
              label: 'single.jpg',
              bytes: Uint8List.fromList([1]),
            ),
          ],
        ),
        throwsA(isA<AiCoachInsufficientDataException>()),
      );
    });
  });
}

LocalAiCoachService _service(
  _CaptureEngine engine, {
  required Map<String, dynamic> context,
}) {
  return LocalAiCoachService(
    engine: engine,
    contextBuilder: _FixtureContextBuilder(context),
    exerciseCatalogRetriever: ExerciseCatalogRetriever(
      catalogLoader: () async => const [],
    ),
    memoryUpdater: const _NoopMemoryUpdater(),
  );
}

Map<String, dynamic> _fixtureContext({bool huge = false}) {
  final payload = huge ? 'z' * 1800 : 'ok';
  return {
    'workouts': [
      for (var i = 0; i < 10; i += 1)
        {'id': 'workout-$i', 'note': '$payload-$i'},
    ],
    'body_logs': [
      for (var i = 0; i < 10; i += 1)
        {'date': '2026-08-${i + 1}', 'note': '$payload-$i'},
    ],
    'notes': [for (var i = 0; i < 20; i += 1) 'note-$i $payload'],
    'metrics': {'private_metric': payload},
    'active_plans': [
      for (var i = 0; i < 4; i += 1)
        {
          'id': 'plan-$i',
          'title': 'Plan $i',
          'week': 2,
          'goal': 'strength',
          'programBlock': 'block',
          'cycleNumber': 1,
          'currentVersionId': 'v$i',
          'currentVersionNumber': i + 1,
          'exercises': [
            {
              'id': 'exercise-$i',
              'name': 'Exercise $i',
              'set': 3,
              'reps': 8,
              'weight': 80,
              'notes': payload,
            },
          ],
        },
    ],
    'deterministic_analytics': {
      'progress_analytics': {'marker': payload},
      'exercise_progress': [payload],
      'progression_recommendations': [payload],
      'fatigue_readiness': {'score': 5, 'note': payload},
      'latest_session_at': '2026-09-04',
      'session_count': 10,
      'unrelated_payload': payload,
    },
    'program_history': [
      {'version': 1, 'payload': payload},
      {'version': 2, 'payload': payload},
    ],
    'program_change_effectiveness': {'association': payload},
    'memory': {
      'recurring_preferences': ['manubri'],
      'recurring_limitations': ['stacchi'],
    },
  };
}

String _extractContextJson(String prompt) {
  final match = RegExp(
    r'Training context \(JSON\):\n([\s\S]*?)(?:\n\nRecent conversation for continuity only:|\nResponse policy:)',
  ).firstMatch(prompt);
  expect(match, isNotNull);
  return match!.group(1)!.trim();
}

String _extractConversationReference(String prompt) {
  final match = RegExp(
    r'Recent conversation for continuity only:\n([\s\S]*?)\nResponse policy:',
  ).firstMatch(prompt);
  return match?.group(1)?.trim() ?? '';
}

class _FixtureContextBuilder extends TrainingContextBuilder {
  final Map<String, dynamic> fixture;

  _FixtureContextBuilder(this.fixture);

  @override
  Map<String, dynamic> recent({
    required List<WorkoutSession> history,
    required List<Schedule> schedules,
    List<ScheduleVersion> scheduleVersions = const [],
    List<BodyLog> bodyLogs = const [],
    AiCoachUserProfile profile = const AiCoachUserProfile(),
    AiCoachMemory memory = const AiCoachMemory(),
  }) {
    return Map<String, dynamic>.from(
      jsonDecode(jsonEncode(fixture)) as Map<String, dynamic>,
    );
  }
}

class _NoopMemoryUpdater extends AiCoachMemoryUpdater {
  const _NoopMemoryUpdater();

  @override
  Future<AiCoachMemory> updateFromUserText(
    String text, {
    AiCoachMemory current = const AiCoachMemory(),
  }) async => current;
}

class _CaptureEngine implements LocalLlmEngine {
  String? systemPrompt;
  List<ChatMessage> messages = const [];
  List<AiCoachImageInput> newImages = const [];

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
    this.messages = List.of(messages);
    this.newImages = List.of(newImages);
    return 'ok';
  }
}
