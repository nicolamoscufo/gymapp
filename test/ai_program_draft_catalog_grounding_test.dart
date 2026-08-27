import 'package:flutter_test/flutter_test.dart';
import 'package:gymapp/ai_coach/ai_action_protocol.dart';
import 'package:gymapp/ai_coach/ai_program_draft_commit_service.dart';
import 'package:gymapp/ai_coach/exercise_catalog_retriever.dart';
import 'package:gymapp/app_data_store.dart';
import 'package:gymapp/exercise_catalog.dart';
import 'package:gymapp/models/exercise.dart';
import 'package:gymapp/models/schedule.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('new AI exercise is grounded to canonical catalog metadata', () async {
    final service = AiProgramDraftCommitService(
      exerciseCatalogRetriever: ExerciseCatalogRetriever(
        catalogLoader: _catalogLoader,
      ),
    );

    final result = await service.commit(
      AiProgramActionProposal(
        kind: AiProgramActionKind.proposeProgram,
        summary: 'Upper',
        rationale: 'Test grounding.',
        confidence: 'high',
        schedules: const [
          AiProgramScheduleDraft(
            draftKey: 'upper',
            title: 'Upper',
            exercises: [
              AiProgramDraftExercise(
                name: 'incline dumbbell press',
                sets: 3,
                reps: 8,
                weight: 24,
                muscleGroup: 'chest',
                equipment: 'dumbbell',
                movementPattern: 'Spinta',
              ),
            ],
          ),
        ],
      ),
    );

    expect(result.saved, isTrue);
    final bundle = await AppDataStore.loadBundle();
    final exercise = bundle.schedules.single.exercises.single;
    expect(exercise.catalogId, 'incline_db_press');
    expect(exercise.name, 'dumbbell incline press');
    expect(exercise.equipment, 'dumbbell');
    expect(exercise.muscleGroup, MuscleGroup.chest);
  });

  test('existing catalog link survives prescription-only AI modification', () async {
    final schedule = Schedule(
      id: 'push',
      title: 'Push',
      week: 1,
      createdAt: DateTime(2026, 8, 1),
      exercises: [
        Exercise(
          id: 'bench-instance',
          catalogId: 'incline_db_press',
          name: 'dumbbell incline press',
          reps: 8,
          set: 3,
          notes: '',
          weight: 24,
          muscleGroup: MuscleGroup.chest,
          equipment: 'dumbbell',
          movementPattern: 'Spinta',
          technique: IntensityTechnique.none,
        ),
      ],
    );
    await AppDataStore.saveSchedules([schedule]);
    final stored = (await AppDataStore.loadBundle()).schedules.single;

    final service = AiProgramDraftCommitService(
      exerciseCatalogRetriever: ExerciseCatalogRetriever(
        catalogLoader: _catalogLoader,
      ),
    );
    final result = await service.commit(
      AiProgramActionProposal(
        kind: AiProgramActionKind.modifyProgram,
        summary: 'Progressione',
        rationale: 'Aumenta il carico.',
        confidence: 'high',
        schedules: [
          AiProgramScheduleDraft(
            draftKey: 'push',
            baseScheduleId: stored.id,
            baseVersionId: stored.currentVersionId!,
            title: stored.title,
            goal: stored.goal,
            mesocycleWeeks: stored.mesocycleWeeks,
            deloadEveryWeeks: stored.deloadEveryWeeks,
            trainingWeekdays: stored.trainingWeekdays,
            programBlock: stored.programBlock,
            cycleNotes: stored.cycleNotes,
            exercises: const [
              AiProgramDraftExercise(
                sourceExerciseId: 'bench-instance',
                name: 'dumbbell incline press',
                sets: 3,
                reps: 8,
                weight: 26,
                muscleGroup: 'chest',
                equipment: 'dumbbell',
                movementPattern: 'Spinta',
              ),
            ],
          ),
        ],
      ),
    );

    expect(result.saved, isTrue);
    final updated = (await AppDataStore.loadBundle()).schedules.single;
    expect(updated.exercises.single.catalogId, 'incline_db_press');
    expect(updated.exercises.single.id, 'bench-instance');
    expect(updated.exercises.single.weight, 26);
  });

  test('ambiguous exact catalog name remains ungrounded', () async {
    final service = AiProgramDraftCommitService(
      exerciseCatalogRetriever: ExerciseCatalogRetriever(
        catalogLoader: _ambiguousCatalogLoader,
      ),
    );

    final result = await service.commit(
      AiProgramActionProposal(
        kind: AiProgramActionKind.proposeProgram,
        summary: 'Pull',
        rationale: 'Ambiguous grounding test.',
        confidence: 'medium',
        schedules: const [
          AiProgramScheduleDraft(
            draftKey: 'pull',
            title: 'Pull',
            exercises: [
              AiProgramDraftExercise(
                name: 'dumbbell row',
                sets: 3,
                reps: 10,
                weight: 20,
                muscleGroup: 'back',
                equipment: 'dumbbell',
                movementPattern: 'Tirata',
              ),
            ],
          ),
        ],
      ),
    );

    expect(result.saved, isTrue);
    final exercise = (await AppDataStore.loadBundle())
        .schedules
        .single
        .exercises
        .single;
    expect(exercise.catalogId, isNull);
    expect(exercise.name, 'dumbbell row');
  });
}

Future<List<ExerciseCatalogEntry>> _catalogLoader() async => const [
  ExerciseCatalogEntry(
    id: 'incline_db_press',
    name: 'dumbbell incline press',
    muscleGroup: MuscleGroup.chest,
    equipment: 'dumbbell',
    movementPattern: 'Spinta',
    bodyPart: 'chest',
    target: 'pectorals',
    secondaryMuscles: ['triceps', 'deltoids'],
    instructions: ['Press the dumbbells upward.'],
    gifUrl: '',
  ),
];

Future<List<ExerciseCatalogEntry>> _ambiguousCatalogLoader() async => const [
  ExerciseCatalogEntry(
    id: 'row_a',
    name: 'dumbbell row',
    muscleGroup: MuscleGroup.back,
    equipment: 'dumbbell',
    movementPattern: 'Tirata',
    bodyPart: 'back',
    target: 'lats',
    secondaryMuscles: ['biceps'],
    instructions: [],
    gifUrl: '',
  ),
  ExerciseCatalogEntry(
    id: 'row_b',
    name: 'dumbbell row',
    muscleGroup: MuscleGroup.back,
    equipment: 'dumbbell',
    movementPattern: 'Tirata',
    bodyPart: 'back',
    target: 'upper back',
    secondaryMuscles: ['biceps'],
    instructions: [],
    gifUrl: '',
  ),
];
