import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gymapp/ai_coach/ai_coach_handoff.dart';
import 'package:gymapp/ai_coach/ai_coach_memory.dart';
import 'package:gymapp/ai_coach/ai_coach_model_manager.dart';
import 'package:gymapp/ai_coach/ai_coach_models.dart';
import 'package:gymapp/ai_coach/ai_coach_user_profile.dart';
import 'package:gymapp/ai_coach/chat_conversation.dart';
import 'package:gymapp/ai_coach/local_ai_coach_service.dart';
import 'package:gymapp/ai_coach/local_llm_engine.dart';
import 'package:gymapp/models/body_log.dart';
import 'package:gymapp/models/exercise.dart';
import 'package:gymapp/models/schedule.dart';
import 'package:gymapp/models/workout.dart';
import 'package:gymapp/screens/ai_coach.dart';
import 'package:gymapp/screens/ai_coach_entry.dart';
import 'package:gymapp/screens/session_summary.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('post-workout handoff carries the exact session and debrief context', () {
    final previous = _session(
      id: 'previous',
      start: DateTime(2026, 8, 19, 18),
      weight: 80,
      reps: 8,
      rir: 2,
      note: 'Controllo buono',
    );
    final current = _session(
      id: 'current',
      start: DateTime(2026, 8, 26, 18),
      weight: 82.5,
      reps: 9,
      rir: 2,
      rpe: 8,
      note: 'Ultima rep lenta ma pulita',
    );

    final launch = AiCoachLaunchContext.postWorkout(
      session: current,
      history: [previous],
    );

    final focus = launch.focusContext;
    expect(focus['type'], 'post_workout_debrief');
    expect(focus['target_session_id'], 'current');
    expect(focus['same_schedule_history_count'], 1);

    final target = Map<String, dynamic>.from(focus['target_session'] as Map);
    final exercises = target['exercises'] as List;
    final exercise = Map<String, dynamic>.from(exercises.single as Map);
    final sets = exercise['sets'] as List;
    final set = Map<String, dynamic>.from(sets.single as Map);
    expect(set['weight'], 82.5);
    expect(set['reps'], 9);
    expect(set['rir'], 2);
    expect(set['rpe'], 8);
    expect(set['notes'], 'Ultima rep lenta ma pulita');

    final debrief = Map<String, dynamic>.from(
      focus['deterministic_debrief'] as Map,
    );
    expect(debrief['session_id'], 'current');
    expect(debrief['previous_comparable_session_id'], 'previous');
    expect(debrief['exercises'], isNotEmpty);

    final contract = Map<String, dynamic>.from(
      focus['context_contract'] as Map,
    );
    expect(contract['target_session_is_authoritative'], isTrue);
    expect(contract['deterministic_metrics_are_authoritative'], isTrue);
  });

  test('chat service injects focus context into the model system prompt', () async {
    final engine = _CaptureEngine();
    final service = LocalAiCoachService(engine: engine);

    await service.generateChatResponse(
      history: [
        _session(
          id: 'current',
          start: DateTime(2026, 8, 26, 18),
          weight: 82.5,
          reps: 9,
          rir: 2,
          note: 'Exact focus note',
        ),
      ],
      schedules: const [],
      messages: [ChatMessage(role: 'user', content: 'Analizza la seduta')],
      focusContext: const {
        'type': 'post_workout_debrief',
        'target_session_id': 'current',
        'authoritative_marker': 'EXACT_FOCUS_CONTEXT',
      },
    );

    expect(engine.lastSystemPrompt, contains('focus_context'));
    expect(engine.lastSystemPrompt, contains('EXACT_FOCUS_CONTEXT'));
    expect(engine.lastSystemPrompt, contains('authoritative scope'));
  });

  testWidgets('launch handoff auto-starts a focused coach conversation', (
    tester,
  ) async {
    final service = _FocusCapturingService();
    final launch = AiCoachLaunchContext(
      source: 'post_workout_debrief',
      conversationTitle: 'Debrief · Push',
      userPrompt: 'Analizza questa seduta completa.',
      focusContext: const {
        'type': 'post_workout_debrief',
        'target_session_id': 'current',
        'authoritative_marker': 'handoff-visible-to-service',
      },
    );

    await tester.pumpWidget(
      MaterialApp(
        home: AiCoachScreen(
          history: [
            _session(
              id: 'current',
              start: DateTime(2026, 8, 26, 18),
              weight: 82.5,
              reps: 9,
              rir: 2,
              note: 'Seduta focus',
            ),
          ],
          schedules: const [],
          service: service,
          modelInstaller: const _InstalledModel(),
          launchContext: launch,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('ai-focus-context-banner')), findsOneWidget);
    expect(find.text('Analizza questa seduta completa.'), findsOneWidget);
    expect(find.text('Coach focus ok'), findsOneWidget);
    expect(service.lastFocus?['target_session_id'], 'current');
    expect(
      service.lastFocus?['authoritative_marker'],
      'handoff-visible-to-service',
    );
  });

  testWidgets('session summary exposes the one-tap Coach handoff', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(900, 1200);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final current = _session(
      id: 'current',
      start: DateTime(2026, 8, 26, 18),
      weight: 82.5,
      reps: 9,
      rir: 2,
      note: 'Seduta focus',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: SessionSummaryScreen(session: current, previousHistory: const []),
      ),
    );
    await tester.pumpAndSettle();

    final button = find.byKey(const ValueKey('ask-coach-debrief'));
    expect(button, findsOneWidget);
    expect(find.text('Chiedi al Coach'), findsOneWidget);

    await tester.tap(button);
    await tester.pump();
    expect(find.byType(AiCoachEntryScreen), findsOneWidget);
  });
}

WorkoutSession _session({
  required String id,
  required DateTime start,
  required double weight,
  required int reps,
  required int rir,
  double? rpe,
  required String note,
}) {
  return WorkoutSession(
    id: id,
    scheduleId: 'push-plan',
    scheduleTitle: 'Push',
    startTime: start,
    endTime: start.add(const Duration(minutes: 60)),
    exercises: [
      WorkoutExercise(
        id: 'bench-$id',
        sourceExerciseId: 'bench-plan',
        name: 'Panca',
        notes: 'Focus tecnica',
        muscleGroup: MuscleGroup.chest,
        equipment: 'Bilanciere',
        movementPattern: 'Spinta orizzontale',
        targetMinReps: 8,
        targetMaxReps: 10,
        technique: IntensityTechnique.none,
        restSeconds: 120,
        progressionKgStep: 2.5,
        progressionRepStep: 1,
        progressionScheme: ProgressionScheme.doubleProgression,
        sets: [
          ExerciseSet(
            id: 'set-$id',
            weight: weight,
            reps: reps,
            isCompleted: true,
            rpe: rpe,
            rir: rir,
            notes: note,
          ),
        ],
      ),
    ],
  );
}

class _CaptureEngine implements LocalLlmEngine {
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

class _FocusCapturingService extends LocalAiCoachService {
  Map<String, dynamic>? lastFocus;

  @override
  Future<String> generateChatResponse({
    required List<WorkoutSession> history,
    required List<Schedule> schedules,
    required List<ChatMessage> messages,
    List<BodyLog> bodyLogs = const [],
    AiCoachUserProfile profile = const AiCoachUserProfile(),
    AiCoachMemory memory = const AiCoachMemory(),
    List<AiCoachImageInput> newImages = const [],
    Map<String, dynamic>? focusContext,
  }) async {
    lastFocus = focusContext;
    return 'Coach focus ok';
  }
}

class _InstalledModel implements AiCoachModelInstaller {
  const _InstalledModel();

  @override
  String get modelName => 'Fake Gemma';

  @override
  String get modelFileName => 'fake.litertlm';

  @override
  String get modelUrl => 'https://example.com/fake.litertlm';

  @override
  String get modelSizeLabel => '0 MB';

  @override
  Future<void> initialize() async {}

  @override
  Future<bool> isInstalled() async => true;

  @override
  Future<void> install({void Function(int progress)? onProgress}) async {
    onProgress?.call(100);
  }

  @override
  Future<void> activateInstalledModel() async {}
}
