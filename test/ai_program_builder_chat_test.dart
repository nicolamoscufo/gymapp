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
      await tester.pumpAndSettle();

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
