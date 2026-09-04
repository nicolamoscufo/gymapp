import 'package:flutter_test/flutter_test.dart';
import 'package:gymapp/ai_coach/ai_coach_models.dart';
import 'package:gymapp/ai_coach/chat_conversation.dart';
import 'package:gymapp/ai_coach/exercise_catalog_retriever.dart';
import 'package:gymapp/ai_coach/local_ai_coach_service.dart';
import 'package:gymapp/ai_coach/local_llm_engine.dart';
import 'package:gymapp/models/exercise.dart';
import 'package:gymapp/models/schedule.dart';
import 'package:gymapp/models/workout.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('chat prompt exposes deterministic verified evidence before interpretation', () async {
    final engine = _CapturingEngine();
    final service = LocalAiCoachService(
      engine: engine,
      exerciseCatalogRetriever: ExerciseCatalogRetriever(
        catalogLoader: () async => const [],
      ),
    );

    await service.generateChatResponse(
      history: [_olderBenchSession(), _latestBenchSession()],
      schedules: [_benchSchedule()],
      messages: [
        ChatMessage(
          role: 'user',
          content: 'Come stanno andando i miei progressi sulla panca piana?',
        ),
      ],
    );

    expect(engine.lastSystemPrompt, contains('"verified_evidence"'));
    expect(
      engine.lastSystemPrompt,
      contains('"source":"deterministic_app_analytics"'),
    );
    expect(engine.lastSystemPrompt, contains('"model_role":"interpret_only"'));
    expect(engine.lastSystemPrompt, contains('"latest_estimated_1rm"'));
    expect(engine.lastSystemPrompt, contains('"estimated_1rm_trend_percent"'));
    expect(engine.lastSystemPrompt, contains('Read verified_evidence before raw workouts'));
  });
}

Schedule _benchSchedule() => Schedule(
      id: 'push',
      title: 'Push',
      week: 1,
      createdAt: DateTime(2026, 8, 1),
      exercises: [
        Exercise(
          id: 'bench-flat',
          catalogId: 'bench-catalog',
          name: 'Panca piana',
          reps: 8,
          set: 3,
          notes: '',
          weight: 82.5,
          muscleGroup: MuscleGroup.chest,
          technique: IntensityTechnique.none,
        ),
      ],
    );

WorkoutSession _olderBenchSession() => WorkoutSession(
      id: 'old',
      scheduleId: 'push',
      scheduleTitle: 'Push',
      startTime: DateTime(2026, 8, 28, 18),
      endTime: DateTime(2026, 8, 28, 19),
      exercises: [
        WorkoutExercise(
          id: 'runtime-old',
          sourceExerciseId: 'bench-flat',
          catalogId: 'bench-catalog',
          name: 'Panca piana',
          notes: '',
          muscleGroup: MuscleGroup.chest,
          technique: IntensityTechnique.none,
          sets: [
            ExerciseSet(weight: 77.5, reps: 8, isCompleted: true, rir: 2),
            ExerciseSet(weight: 77.5, reps: 8, isCompleted: true, rir: 2),
            ExerciseSet(weight: 77.5, reps: 8, isCompleted: true, rir: 2),
          ],
        ),
      ],
    );

WorkoutSession _latestBenchSession() => WorkoutSession(
      id: 'latest',
      scheduleId: 'push',
      scheduleTitle: 'Push',
      startTime: DateTime(2026, 9, 4, 18),
      endTime: DateTime(2026, 9, 4, 19),
      exercises: [
        WorkoutExercise(
          id: 'runtime-latest',
          sourceExerciseId: 'bench-flat',
          catalogId: 'bench-catalog',
          name: 'Panca piana',
          notes: '',
          muscleGroup: MuscleGroup.chest,
          technique: IntensityTechnique.none,
          sets: [
            ExerciseSet(weight: 82.5, reps: 8, isCompleted: true, rir: 2),
            ExerciseSet(weight: 82.5, reps: 8, isCompleted: true, rir: 2),
            ExerciseSet(weight: 82.5, reps: 8, isCompleted: true, rir: 2),
          ],
        ),
      ],
    );

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
