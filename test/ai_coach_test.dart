import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gymapp/ai_coach/ai_coach_model_manager.dart';
import 'package:gymapp/ai_coach/ai_coach_memory.dart';
import 'package:gymapp/ai_coach/ai_coach_models.dart';
import 'package:gymapp/ai_coach/ai_coach_prompts.dart';
import 'package:gymapp/ai_coach/ai_coach_user_profile.dart';
import 'package:gymapp/ai_coach/chat_conversation.dart';
import 'package:gymapp/ai_coach/local_ai_coach_service.dart';
import 'package:gymapp/ai_coach/local_llm_engine.dart';
import 'package:gymapp/ai_coach/training_context_builder.dart';
import 'package:gymapp/models/body_log.dart';
import 'package:gymapp/models/exercise.dart';
import 'package:gymapp/models/schedule.dart';
import 'package:gymapp/models/workout.dart';
import 'package:gymapp/screens/ai_coach.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('prompt asks for local JSON-only conservative analysis', () {
    final prompt = AiCoachPrompts.buildStructuredPrompt(
      task: AiCoachTask.weeklyReport,
      context: const {'workouts': []},
      schema: AiCoachPromptSchemas.weeklyReport,
    );

    expect(prompt, contains('TASK: weekly_report'));
    expect(prompt, contains('Return ONLY one valid JSON object'));
    expect(prompt, contains('do not diagnose'));
    expect(prompt, contains('Use only the provided context'));
  });

  test('parses workout recap JSON safely', () {
    final recap = WorkoutRecap.fromJson(
      decodeJsonObject('''
{
  "summary": "Buona seduta",
  "positive_points": ["Panca stabile"],
  "negative_points": [],
  "note_summary": "No critical notes",
  "warnings": [],
  "next_session_focus": ["Keep technique stable"]
}
'''),
    );

    expect(recap.summary, 'Buona seduta');
    expect(recap.positivePoints.single, 'Panca stabile');
  });

  test('parses JSON object from fenced model output', () {
    final decoded = decodeJsonObject('''
```json
{"summary":"ok"}
```
''');

    expect(decoded['summary'], 'ok');
  });

  test('context includes full plan details, user profile and analytics', () {
    final context = TrainingContextBuilder(now: DateTime(2026, 6, 10)).recent(
      history: [
        _session(DateTime(2026, 6, 3), weight: 70),
        _session(DateTime(2026, 6, 10), weight: 80),
      ],
      schedules: [
        Schedule(
          title: 'Push',
          week: 1,
          createdAt: DateTime(2026, 6, 1),
          goal: 'Ipertrofia',
          exercises: [
            Exercise(
              name: 'Panca',
              reps: 8,
              set: 4,
              notes: 'Focus petto',
              weight: 80,
              muscleGroup: MuscleGroup.chest,
              technique: IntensityTechnique.none,
            ),
          ],
        ),
      ],
      profile: const AiCoachUserProfile(
        primaryGoal: 'massa',
        experienceLevel: 'intermedio',
      ),
    );

    final activePlan = (context['active_plans'] as List).single as Map;
    expect(activePlan['exercises'], isNotEmpty);
    expect(context['user_profile'], containsPair('primary_goal', 'massa'));
    expect(context['deterministic_analytics'], contains('exercise_progress'));
  });

  test('empty history returns useful insufficient data error', () async {
    final service = LocalAiCoachService(
      contextBuilder: TrainingContextBuilder(now: DateTime(2026, 6, 10)),
    );

    expect(
      () =>
          service.generateWorkoutRecap(history: const [], schedules: const []),
      throwsA(isA<AiCoachInsufficientDataException>()),
    );
  });

  test('malformed model output falls back to safe local report', () async {
    final service = LocalAiCoachService(
      engine: const _MalformedEngine(),
      fallbackEngine: const HeuristicLocalLlmEngine(),
      allowFallback: true,
      contextBuilder: TrainingContextBuilder(now: DateTime(2026, 6, 10)),
    );

    final report = await service.generateWeeklyReport(
      history: [_session(DateTime(2026, 6, 10), weight: 80)],
      schedules: const [],
    );

    expect(report.sessionsCompleted, 1);
    expect(report.summary, contains('1 completed sessions'));
  });

  testWidgets('chat screen shows input and suggestion chips', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AiCoachScreen(
          history: [
            _session(DateTime(2026, 6, 3), weight: 70),
            _session(DateTime(2026, 6, 10), weight: 80),
          ],
          schedules: const [],
          service: const _FakeSuggestionService(),
          modelInstaller: const _FakeModelInstaller(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('Il tuo coach AI personale'), findsOneWidget);
    expect(find.text('Riassumi ultimo allenamento'), findsOneWidget);
    expect(find.text('Report settimanale'), findsOneWidget);
    expect(find.text('Suggerimenti'), findsOneWidget);
  });


}

WorkoutSession _session(DateTime start, {required double weight}) {
  return WorkoutSession(
    scheduleTitle: 'Push',
    startTime: start,
    endTime: start.add(const Duration(minutes: 60)),
    exercises: [
      WorkoutExercise(
        name: 'Panca',
        notes: weight >= 80 ? 'Good energy' : 'Shoulder a bit uncomfortable',
        muscleGroup: MuscleGroup.chest,
        technique: IntensityTechnique.none,
        sets: [ExerciseSet(weight: weight, reps: 8, isCompleted: true, rir: 2)],
      ),
    ],
  );
}

class _MalformedEngine implements LocalLlmEngine {
  const _MalformedEngine();

  @override
  Future<void> initialize() async {}

  @override
  Future<void> dispose() async {}

  @override
  Future<String> generateText(String prompt) async => 'mock text';

  @override
  Future<String> generateChatText({
    required String systemPrompt,
    required List<ChatMessage> messages,
    List<AiCoachImageInput> newImages = const [],
  }) async {
    return 'Test chat response';
  }

  @override
  Future<String> generateStructuredJson(
    String prompt,
    Map<String, dynamic> schema,
  ) async {
    return 'not json';
  }

  @override
  Future<String> generateStructuredJsonWithImages(
    String prompt,
    Map<String, dynamic> schema,
    List<AiCoachImageInput> images,
  ) async {
    return 'not json';
  }
}

class _FakeSuggestionService extends LocalAiCoachService {
  const _FakeSuggestionService();

  @override
  Future<SuggestedAdjustmentReport> suggestWorkoutAdjustments({
    required List<WorkoutSession> history,
    required List<Schedule> schedules,
    List<BodyLog> bodyLogs = const [],
    AiCoachUserProfile profile = const AiCoachUserProfile(),
    AiCoachMemory memory = const AiCoachMemory(),
  }) async {
    return const SuggestedAdjustmentReport(
      suggestions: [
        SuggestedAdjustment(
          type: 'load_progression',
          target: 'Squat',
          suggestion: 'Increase by 2.5 kg next session',
          reason: 'Last session was stable.',
          evidence: ['Completed all work sets with RIR 2'],
          confidence: 'medium',
          requiresUserConfirmation: true,
        ),
      ],
    );
  }
}

class _FakeModelInstaller implements AiCoachModelInstaller {
  const _FakeModelInstaller();

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
