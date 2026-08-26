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

  const AiProgramConversationCoordinator({
    this.draftService = const AiProgramDraftService(),
    this.actionProtocolService = const AiActionProtocolService(),
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

    // Some callers (notably the Home AI Coach tab) historically did not pass
    // scheduleVersions. Program drafting needs the persisted version graph for
    // longitudinal context and safe modification proposals, so hydrate it only
    // when the caller has not supplied an explicit snapshot.
    final resolvedScheduleVersions = scheduleVersions.isNotEmpty
        ? scheduleVersions
        : await AppDataStore.loadScheduleVersions();

    final proposal = await draftService.generate(
      userRequest: userRequest,
      history: history,
      schedules: schedules,
      scheduleVersions: resolvedScheduleVersions,
      bodyLogs: bodyLogs,
      profile: profile,
      memory: memory,
    );
    final validation = actionProtocolService.validate(proposal, schedules);
    if (!validation.isValid) {
      return AiProgramConversationResult(
        isProgramActionIntent: true,
        validationErrors: validation.errors,
      );
    }

    // Identity belongs to this concrete proposal card, not to its semantic
    // content. This makes repeated taps idempotent while still allowing a new
    // conversation to intentionally create an identical program later.
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
