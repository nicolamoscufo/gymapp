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

  test('specific exercise question removes unrelated exercise evidence', () async {
    final engine = _CapturingEngine();
    final service = LocalAiCoachService(
      engine: engine,
      exerciseCatalogRetriever: ExerciseCatalogRetriever(
        catalogLoader: () async => const [],
      ),
    );
    final schedules = [_scheduleWithFlatBenchAndSquat()];
    final history = [_sessionWithFlatBenchAndSquat()];

    await service.generateChatResponse(
      history: history,
      schedules: schedules,
      messages: [
        ChatMessage(
          role: 'user',
          content: 'Come sta andando la mia panca piana?',
        ),
      ],
    );

    expect(engine.lastSystemPrompt, contains('"exercise_focus"'));
    expect(engine.lastSystemPrompt, contains('Panca piana'));
    expect(engine.lastSystemPrompt, contains('bench-flat'));
    expect(engine.lastSystemPrompt, isNot(contains('Squat')));
  });

  test('ambiguous exercise family keeps the broader context', () async {
    final engine = _CapturingEngine();
    final service = LocalAiCoachService(
      engine: engine,
      exerciseCatalogRetriever: ExerciseCatalogRetriever(
        catalogLoader: () async => const [],
      ),
    );
    final schedule = Schedule(
      id: 'upper',
      title: 'Upper',
      week: 1,
      createdAt: DateTime(2026, 8, 1),
      exercises: [
        _exercise('bench-flat', 'Panca piana'),
        _exercise('bench-incline', 'Panca inclinata manubri'),
      ],
    );

    await service.generateChatResponse(
      history: const [],
      schedules: [schedule],
      messages: [
        ChatMessage(role: 'user', content: 'Come sta andando la panca?'),
      ],
    );

    expect(engine.lastSystemPrompt, isNot(contains('"exercise_focus"')));
    expect(engine.lastSystemPrompt, contains('Panca piana'));
    expect(engine.lastSystemPrompt, contains('Panca inclinata manubri'));
  });
}

Schedule _scheduleWithFlatBenchAndSquat() => Schedule(
      id: 'upper',
      title: 'Upper',
      week: 1,
      createdAt: DateTime(2026, 8, 1),
      exercises: [
        _exercise('bench-flat', 'Panca piana', catalogId: 'bench-catalog'),
        _exercise('squat', 'Squat', catalogId: 'squat-catalog'),
      ],
    );

Exercise _exercise(String id, String name, {String? catalogId}) => Exercise(
      id: id,
      catalogId: catalogId,
      name: name,
      reps: 8,
      set: 3,
      notes: '',
      weight: name == 'Squat' ? 120 : 80,
      muscleGroup:
          name == 'Squat' ? MuscleGroup.quadriceps : MuscleGroup.chest,
      technique: IntensityTechnique.none,
    );

WorkoutSession _sessionWithFlatBenchAndSquat() => WorkoutSession(
      id: 'session-1',
      scheduleId: 'upper',
      scheduleTitle: 'Upper',
      startTime: DateTime(2026, 9, 1, 18),
      endTime: DateTime(2026, 9, 1, 19),
      exercises: [
        _workoutExercise(
          'bench-flat',
          'Panca piana',
          80,
          catalogId: 'bench-catalog',
        ),
        _workoutExercise(
          'squat',
          'Squat',
          120,
          catalogId: 'squat-catalog',
        ),
      ],
    );

WorkoutExercise _workoutExercise(
  String sourceId,
  String name,
  double weight, {
  String? catalogId,
}) =>
    WorkoutExercise(
      id: 'runtime-$sourceId',
      sourceExerciseId: sourceId,
      catalogId: catalogId,
      name: name,
      notes: '',
      muscleGroup:
          name == 'Squat' ? MuscleGroup.quadriceps : MuscleGroup.chest,
      technique: IntensityTechnique.none,
      sets: [
        ExerciseSet(weight: weight, reps: 8, isCompleted: true),
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
