import 'package:flutter_test/flutter_test.dart';
import 'package:gymapp/ai_coach/ai_action_protocol.dart';
import 'package:gymapp/ai_coach/ai_program_draft_commit_service.dart';
import 'package:gymapp/ai_coach/ai_program_draft_instance.dart';
import 'package:gymapp/app_data_store.dart';
import 'package:gymapp/models/exercise.dart';
import 'package:gymapp/models/schedule.dart';
import 'package:gymapp/models/schedule_version.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('approved new program is persisted and versioned as AI Coach', () async {
    final proposal = _newProgramProposal();

    final result = await const AiProgramDraftCommitService().commit(proposal);
    expect(result.saved, isTrue);
    expect(result.createdSchedules, 2);

    final bundle = await AppDataStore.loadBundle();
    expect(bundle.schedules, hasLength(2));
    expect(bundle.scheduleVersions, hasLength(2));
    expect(
      bundle.scheduleVersions.every(
        (version) => version.source == ScheduleVersionSource.aiCoach,
      ),
      isTrue,
    );
    expect(
      bundle.schedules.every(
        (schedule) =>
            schedule.currentVersionId != null &&
            schedule.currentVersionNumber == 1,
      ),
      isTrue,
    );
  });

  test('same persisted draft card cannot be applied twice', () async {
    final proposal = InstancedAiProgramActionProposal.fromProposal(
      _newProgramProposal(),
      'draft-card-1',
    );
    const service = AiProgramDraftCommitService();

    final first = await service.commit(proposal);
    final second = await service.commit(proposal);

    expect(first.saved, isTrue);
    expect(second.saved, isFalse);
    expect(second.errors, contains('already_applied'));

    final bundle = await AppDataStore.loadBundle();
    expect(bundle.schedules, hasLength(2));
    expect(bundle.scheduleVersions, hasLength(2));
  });

  test('identical content from a different draft card is allowed', () async {
    final firstProposal = InstancedAiProgramActionProposal.fromProposal(
      _newProgramProposal(),
      'draft-card-1',
    );
    final secondProposal = InstancedAiProgramActionProposal.fromProposal(
      _newProgramProposal(),
      'draft-card-2',
    );
    const service = AiProgramDraftCommitService();

    final first = await service.commit(firstProposal);
    final second = await service.commit(secondProposal);

    expect(first.saved, isTrue);
    expect(second.saved, isTrue);
    expect(second.createdSchedules, 2);

    final bundle = await AppDataStore.loadBundle();
    expect(bundle.schedules, hasLength(4));
    expect(bundle.scheduleVersions, hasLength(4));
  });

  test('stale modify draft is rejected after persisted schedule changes', () async {
    final original = _baseSchedule();
    await AppDataStore.saveSchedules([original]);
    var latest = await AppDataStore.loadBundle();
    final stored = latest.schedules.single;
    final baseVersionId = stored.currentVersionId!;

    final proposal = AiProgramActionProposal(
      kind: AiProgramActionKind.modifyProgram,
      summary: 'Progressione Push',
      rationale: 'Aumento controllato.',
      confidence: 'medium',
      schedules: [
        AiProgramScheduleDraft(
          draftKey: 'push',
          baseScheduleId: stored.id,
          baseVersionId: baseVersionId,
          title: stored.title,
          goal: stored.goal,
          mesocycleWeeks: stored.mesocycleWeeks,
          deloadEveryWeeks: stored.deloadEveryWeeks,
          trainingWeekdays: stored.trainingWeekdays,
          exercises: [
            AiProgramDraftExercise(
              sourceExerciseId: stored.exercises.single.id,
              name: stored.exercises.single.name,
              sets: 3,
              reps: 8,
              weight: 82.5,
              muscleGroup: 'chest',
              technique: 'none',
              progressionScheme: 'doubleProgression',
            ),
          ],
        ),
      ],
    );

    stored.exercises.single.weight = 85;
    await AppDataStore.saveSchedules(
      latest.schedules,
      source: ScheduleVersionSource.user,
      reason: 'Manual change while AI draft was open',
    );
    latest = await AppDataStore.loadBundle();
    expect(latest.schedules.single.currentVersionId, isNot(baseVersionId));

    final result = await const AiProgramDraftCommitService().commit(proposal);
    expect(result.saved, isFalse);
    expect(
      result.errors.any((error) => error.endsWith(':stale_base_version')),
      isTrue,
    );

    final after = await AppDataStore.loadBundle();
    expect(after.schedules.single.exercises.single.weight, 85);
  });
}

AiProgramActionProposal _newProgramProposal() => AiProgramActionProposal(
  kind: AiProgramActionKind.proposeProgram,
  summary: 'Upper Lower',
  rationale: 'Programma di prova.',
  confidence: 'high',
  schedules: [
    _newScheduleDraft('upper_a', 'Upper A', 1),
    _newScheduleDraft('lower_a', 'Lower A', 2),
  ],
);

AiProgramScheduleDraft _newScheduleDraft(
  String key,
  String title,
  int weekday,
) => AiProgramScheduleDraft(
  draftKey: key,
  title: title,
  goal: 'Ipertrofia',
  trainingWeekdays: [weekday],
  exercises: const [
    AiProgramDraftExercise(
      name: 'Panca',
      sets: 3,
      reps: 8,
      weight: 80,
      muscleGroup: 'chest',
      technique: 'none',
      progressionScheme: 'doubleProgression',
    ),
  ],
);

Schedule _baseSchedule() => Schedule(
  id: 'push',
  title: 'Push',
  week: 1,
  createdAt: DateTime(2026, 8, 1),
  goal: 'Ipertrofia',
  exercises: [
    Exercise(
      id: 'bench',
      name: 'Panca',
      reps: 8,
      set: 3,
      notes: '',
      weight: 80,
      muscleGroup: MuscleGroup.chest,
      technique: IntensityTechnique.none,
    ),
  ],
);
