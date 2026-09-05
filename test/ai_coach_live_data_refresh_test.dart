import 'package:flutter_test/flutter_test.dart';
import 'package:gymapp/ai_coach/ai_coach_context_budget.dart';
import 'package:gymapp/ai_coach/ai_coach_models.dart';
import 'package:gymapp/ai_coach/chat_conversation.dart';
import 'package:gymapp/ai_coach/local_ai_coach_service.dart';
import 'package:gymapp/ai_coach/local_llm_engine.dart';
import 'package:gymapp/app_data_store.dart';
import 'package:gymapp/models/exercise.dart';
import 'package:gymapp/models/schedule.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('real local runtime refreshes persisted user data before inference', () async {
    final persisted = _schedule(
      id: 'persisted-plan',
      title: 'Petto Persistito',
      exerciseName: 'Panca persistita',
    );
    await AppDataStore.saveSchedules([persisted]);

    final staleRouteCopy = _schedule(
      id: 'stale-plan',
      title: 'Scheda Stale',
      exerciseName: 'Esercizio stale',
    );
    final engine = _CapturingGemmaEngine();
    final service = LocalAiCoachService(engine: engine);

    final response = await service.generateChatResponse(
      history: const [],
      schedules: [staleRouteCopy],
      messages: [
        ChatMessage(
          role: 'user',
          content: 'Riesci a vedere la mia scheda? Dimmi cosa contiene.',
        ),
      ],
    );

    expect(response, 'ok');
    expect(engine.capturedSystemPrompt, contains('Petto Persistito'));
    expect(engine.capturedSystemPrompt, contains('Panca persistita'));
    expect(engine.capturedSystemPrompt, isNot(contains('Scheda Stale')));

    final diagnostics = AiCoachContextBudget.lastDiagnostics;
    expect(diagnostics, isNotNull);
    expect(diagnostics!.planTitles, contains('Petto Persistito'));
    expect(diagnostics.exerciseNames, contains('Panca persistita'));
  });
}

Schedule _schedule({
  required String id,
  required String title,
  required String exerciseName,
}) {
  return Schedule(
    id: id,
    title: title,
    week: 1,
    createdAt: DateTime(2026, 9, 1),
    exercises: [
      Exercise(
        id: '$id-exercise',
        name: exerciseName,
        reps: 8,
        set: 4,
        notes: '',
        weight: 80,
        muscleGroup: MuscleGroup.chest,
        technique: IntensityTechnique.none,
      ),
    ],
  );
}

class _CapturingGemmaEngine extends FlutterGemmaLocalLlmEngine {
  String capturedSystemPrompt = '';

  @override
  Future<void> initialize() async {}

  @override
  Future<String> generateChatText({
    required String systemPrompt,
    required List<ChatMessage> messages,
    List<AiCoachImageInput> newImages = const [],
  }) async {
    capturedSystemPrompt = systemPrompt;
    return 'ok';
  }
}
