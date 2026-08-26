import '../models/body_log.dart';
import '../models/schedule.dart';
import '../models/schedule_version.dart';
import '../models/workout.dart';
import 'ai_action_protocol.dart';
import 'ai_coach_memory.dart';
import 'ai_coach_user_profile.dart';
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

    final proposal = await draftService.generate(
      userRequest: userRequest,
      history: history,
      schedules: schedules,
      scheduleVersions: scheduleVersions,
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

AiProgramActionProposal? programDraftFromMessage(ChatMessage message) {
  final payload = message.actionPayload;
  if (payload == null || payload.isEmpty) return null;
  try {
    return AiProgramActionProposal.fromActionPayload(payload);
  } catch (_) {
    return null;
  }
}
