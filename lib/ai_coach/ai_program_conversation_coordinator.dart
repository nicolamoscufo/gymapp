import '../app_data_store.dart';
import '../models/body_log.dart';
import '../models/schedule.dart';
import '../models/schedule_version.dart';
import '../models/workout.dart';
import 'ai_action_protocol.dart';
import 'ai_coach_memory.dart';
import 'ai_coach_user_profile.dart';
import 'ai_program_draft_instance.dart';
import 'ai_program_draft_service.dart';
import 'chat_conversation.dart';

class AiProgramConversationResult {
  final bool isProgramActionIntent;
  final ChatMessage? assistantMessage;
  final List<String> validationErrors;

  const AiProgramConversationResult({
    required this.isProgramActionIntent,
    this.assistantMessage,
    this.validationErrors = const [],
  });

  bool get hasDraft => assistantMessage?.hasActionPayload == true;
}

class AiProgramConversationCoordinator {
  final AiProgramDraftService draftService;
  final AiActionProtocolService actionProtocolService;
  final AiCoachMemoryStore memoryStore;

  const AiProgramConversationCoordinator({
    this.draftService = const AiProgramDraftService(),
    this.actionProtocolService = const AiActionProtocolService(),
    this.memoryStore = const AiCoachMemoryStore(),
  });

  Future<AiProgramConversationResult> handle({
    required String userRequest,
    required List<WorkoutSession> history,
    required List<Schedule> schedules,
    List<ScheduleVersion> scheduleVersions = const [],
    List<BodyLog> bodyLogs = const [],
    AiCoachUserProfile profile = const AiCoachUserProfile(),
    AiCoachMemory memory = const AiCoachMemory(),
  }) async {
    if (!looksLikeProgramActionIntent(userRequest)) {
      return const AiProgramConversationResult(isProgramActionIntent: false);
    }

    final resolvedScheduleVersions = scheduleVersions.isNotEmpty
        ? scheduleVersions
        : await AppDataStore.loadScheduleVersions();

    // Chat memory can change after the screen was built. When the memory store
    // has an explicit value, including an intentionally cleared empty value,
    // that persisted snapshot is authoritative for Program Builder too.
    final hasPersistedMemory = await memoryStore.hasStoredValue();
    final resolvedMemory = hasPersistedMemory ? await memoryStore.load() : memory;

    final proposal = await draftService.generate(
      userRequest: userRequest,
      history: history,
      schedules: schedules,
      scheduleVersions: resolvedScheduleVersions,
      bodyLogs: bodyLogs,
      profile: profile,
      memory: resolvedMemory,
    );
    final validation = actionProtocolService.validate(proposal, schedules);
    if (!validation.isValid) {
      return AiProgramConversationResult(
        isProgramActionIntent: true,
        validationErrors: validation.errors,
      );
    }

    final instancedProposal = InstancedAiProgramActionProposal.fromProposal(
      proposal,
      generateConversationId(),
    );

    return AiProgramConversationResult(
      isProgramActionIntent: true,
      assistantMessage: ChatMessage(
        role: 'assistant',
        content: proposal.summary,
        actionPayload: instancedProposal.toJson(),
      ),
    );
  }
}

AiProgramActionProposal? programDraftFromMessage(ChatMessage message) {
  final payload = message.actionPayload;
  if (payload == null || payload.isEmpty) return null;
  try {
    final proposal = AiProgramActionProposal.fromActionPayload(payload);
    return restoreProgramDraftInstance(proposal, payload);
  } catch (_) {
    return null;
  }
}
