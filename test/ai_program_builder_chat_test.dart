import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gymapp/ai_coach/ai_action_protocol.dart';
import 'package:gymapp/ai_coach/ai_coach_memory.dart';
import 'package:gymapp/ai_coach/ai_coach_model_manager.dart';
import 'package:gymapp/ai_coach/ai_coach_user_profile.dart';
import 'package:gymapp/ai_coach/ai_program_conversation_coordinator.dart';
import 'package:gymapp/ai_coach/chat_conversation.dart';
import 'package:gymapp/app_data_store.dart';
import 'package:gymapp/models/body_log.dart';
import 'package:gymapp/models/exercise.dart';
import 'package:gymapp/models/schedule.dart';
import 'package:gymapp/models/schedule_version.dart';
import 'package:gymapp/models/workout.dart';
import 'package:gymapp/screens/ai_coach.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets(
    'program request becomes persistent draft and saves only after confirmation',
    (tester) async {
      final schedules = <Schedule>[];
      final versions = <ScheduleVersion>[];

      await tester.pumpWidget(
        MaterialApp(
          home: AiCoachScreen(
            history: const [],
            schedules: schedules,
            scheduleVersions: versions,
            modelInstaller: const _InstalledModel(),
            programConversationCoordinator: const _FakeProgramCoordinator(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('ai-chat-input')),
        'Fammi una nuova scheda di quattro giorni',
      );
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('ai-program-draft-card')),
        findsOneWidget,
      );
      expect(find.text('Upper A'), findsOneWidget);
      expect(find.text('Lower A'), findsOneWidget);

      final before = await AppDataStore.loadBundle();
      expect(before.schedules, isEmpty);

      final saveFinder = find.byKey(
        const ValueKey('save-ai-program-draft'),
      );
      await tester.ensureVisible(saveFinder);
      await tester.tap(saveFinder);
      await _pumpUntilSaved(tester);

      final after = await AppDataStore.loadBundle();
      expect(after.schedules, hasLength(2));
      expect(after.scheduleVersions, hasLength(2));
      expect(
        after.scheduleVersions.every(
          (version) => version.source == ScheduleVersionSource.aiCoach,
        ),
        isTrue,
      );
      expect(schedules, hasLength(2));
      expect(versions, hasLength(2));

      final saveButton = tester.widget<FilledButton>(saveFinder);
      expect(saveButton.onPressed, isNull);
      expect(find.text('Salvato'), findsOneWidget);

      final conversations = await const ChatConversationStore().loadAll();
      final assistant = conversations.first.messages.last;
      expect(assistant.role, 'assistant');
      expect(assistant.actionPayload?['ui_status'], 'saved');
    },
  );

  testWidgets('existing program modification preserves persistent ids', (
    tester,
  ) async {
    final base = Schedule(
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
    await AppDataStore.saveSchedules(
      [base],
      source: ScheduleVersionSource.user,
      reason: 'Seed program',
    );
    final seeded = await AppDataStore.loadBundle();
    final schedules = <Schedule>[...seeded.schedules];
    final versions = <ScheduleVersion>[...seeded.scheduleVersions];
    expect(schedules.single.currentVersionId, isNotNull);
    expect(versions, hasLength(1));

    await tester.pumpWidget(
      MaterialApp(
        home: AiCoachScreen(
          history: const [],
          schedules: schedules,
          scheduleVersions: versions,
          modelInstaller: const _InstalledModel(),
          programConversationCoordinator:
              const _FakeModifyProgramCoordinator(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('ai-chat-input')),
      'Modifica la mia scheda Push',
    );
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pumpAndSettle();

    expect(find.text('Modifica programmazione'), findsOneWidget);
    final saveFinder = find.byKey(
      const ValueKey('save-ai-program-draft'),
    );
    await tester.ensureVisible(saveFinder);
    await tester.tap(saveFinder);
    await _pumpUntilSaved(tester);

    final after = await AppDataStore.loadBundle();
    expect(after.schedules, hasLength(1));
    final updated = after.schedules.single;
    expect(updated.id, 'push');
    expect(updated.exercises, hasLength(1));
    expect(updated.exercises.single.id, 'bench');
    expect(updated.exercises.single.weight, 82.5);
    expect(updated.currentVersionNumber, 2);
    expect(after.scheduleVersions, hasLength(2));
    expect(
      after.scheduleVersions.any(
        (version) => version.source == ScheduleVersionSource.aiCoach,
      ),
      isTrue,
    );
  });

  testWidgets('program draft opens the local editor from the same chat', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AiCoachScreen(
          history: const [],
          schedules: <Schedule>[],
          scheduleVersions: <ScheduleVersion>[],
          modelInstaller: const _InstalledModel(),
          programConversationCoordinator: const _FakeProgramCoordinator(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('ai-chat-input')),
      'Creami una nuova scheda',
    );
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pumpAndSettle();

    final editFinder = find.byKey(const ValueKey('edit-ai-program-draft'));
    await tester.ensureVisible(editFinder);
    await tester.tap(editFinder);
    await tester.pumpAndSettle();

    expect(find.text('Rivedi proposta AI'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('ai-draft-title-upper_a')),
      findsOneWidget,
    );
  });
}

Future<void> _pumpUntilSaved(WidgetTester tester) async {
  await tester.runAsync(() async {
    for (var attempt = 0; attempt < 100; attempt++) {
      final conversations = await const ChatConversationStore().loadAll();
      final saved = conversations.any(
        (conversation) => conversation.messages.any(
          (message) => message.actionPayload?['ui_status'] == 'saved',
        ),
      );
      if (saved) return;
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    fail('Program draft was not persisted as saved.');
  });
  await tester.pump();
}

class _FakeProgramCoordinator extends AiProgramConversationCoordinator {
  const _FakeProgramCoordinator();

  @override
  Future<AiProgramConversationResult> handle({
    required String userRequest,
    required List<WorkoutSession> history,
    required List<Schedule> schedules,
    List<ScheduleVersion> scheduleVersions = const [],
    List<BodyLog> bodyLogs = const [],
    AiCoachUserProfile profile = const AiCoachUserProfile(),
    AiCoachMemory memory = const AiCoachMemory(),
  }) async {
    final proposal = _proposal();
    return AiProgramConversationResult(
      isProgramActionIntent: true,
      assistantMessage: ChatMessage(
        role: 'assistant',
        content: proposal.summary,
        actionPayload: proposal.toJson(),
      ),
    );
  }
}

class _FakeModifyProgramCoordinator extends AiProgramConversationCoordinator {
  const _FakeModifyProgramCoordinator();

  @override
  Future<AiProgramConversationResult> handle({
    required String userRequest,
    required List<WorkoutSession> history,
    required List<Schedule> schedules,
    List<ScheduleVersion> scheduleVersions = const [],
    List<BodyLog> bodyLogs = const [],
    AiCoachUserProfile profile = const AiCoachUserProfile(),
    AiCoachMemory memory = const AiCoachMemory(),
  }) async {
    final base = schedules.single;
    final exercise = base.exercises.single;
    final proposal = AiProgramActionProposal(
      kind: AiProgramActionKind.modifyProgram,
      summary: 'Progressione Push',
      rationale: 'Piccolo aumento di carico mantenendo la struttura.',
      confidence: 'high',
      schedules: [
        AiProgramScheduleDraft(
          draftKey: 'push_update',
          baseScheduleId: base.id,
          baseVersionId: base.currentVersionId ?? '',
          title: base.title,
          goal: base.goal,
          mesocycleWeeks: base.mesocycleWeeks,
          deloadEveryWeeks: base.deloadEveryWeeks,
          trainingWeekdays: base.trainingWeekdays,
          programBlock: base.programBlock,
          cycleNotes: base.cycleNotes,
          exercises: [
            AiProgramDraftExercise(
              sourceExerciseId: exercise.id,
              name: exercise.name,
              sets: exercise.set,
              reps: exercise.reps,
              weight: 82.5,
              notes: exercise.notes,
              muscleGroup: exercise.muscleGroup.name,
              equipment: exercise.equipment,
              movementPattern: exercise.movementPattern,
              targetMinReps: exercise.targetMinReps,
              targetMaxReps: exercise.targetMaxReps,
              technique: exercise.technique.name,
              backoffReps: exercise.backoffReps,
              backoffReductionPercent: exercise.backoffReductionPercent,
              restSeconds: exercise.restSeconds,
              supersetGroup: exercise.supersetGroup,
              progressionKgStep: exercise.progressionKgStep,
              progressionRepStep: exercise.progressionRepStep,
              progressionScheme: exercise.progressionScheme.name,
            ),
          ],
        ),
      ],
    );
    return AiProgramConversationResult(
      isProgramActionIntent: true,
      assistantMessage: ChatMessage(
        role: 'assistant',
        content: proposal.summary,
        actionPayload: proposal.toJson(),
      ),
    );
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

AiProgramActionProposal _proposal() => const AiProgramActionProposal(
  kind: AiProgramActionKind.proposeProgram,
  summary: 'Upper / Lower 4D',
  rationale: 'Bozza multi-day costruita sui dati del Coach.',
  confidence: 'high',
  schedules: [
    AiProgramScheduleDraft(
      draftKey: 'upper_a',
      title: 'Upper A',
      goal: 'Ipertrofia',
      trainingWeekdays: [1, 4],
      exercises: [
        AiProgramDraftExercise(
          name: 'Panca',
          sets: 3,
          reps: 8,
          weight: 80,
          targetMinReps: 6,
          targetMaxReps: 10,
          muscleGroup: 'chest',
        ),
      ],
    ),
    AiProgramScheduleDraft(
      draftKey: 'lower_a',
      title: 'Lower A',
      goal: 'Ipertrofia',
      trainingWeekdays: [2, 5],
      exercises: [
        AiProgramDraftExercise(
          name: 'Squat',
          sets: 3,
          reps: 8,
          weight: 100,
          targetMinReps: 6,
          targetMaxReps: 10,
          muscleGroup: 'quadriceps',
        ),
      ],
    ),
  ],
);
