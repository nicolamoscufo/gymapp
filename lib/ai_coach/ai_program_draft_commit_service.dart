import '../app_data_store.dart';
import '../models/schedule.dart';
import '../models/schedule_version.dart';
import 'ai_action_protocol.dart';

class AiProgramDraftCommitResult {
  final bool saved;
  final int createdSchedules;
  final int modifiedSchedules;
  final List<String> errors;
  final List<Schedule> schedules;

  const AiProgramDraftCommitResult({
    required this.saved,
    this.createdSchedules = 0,
    this.modifiedSchedules = 0,
    this.errors = const [],
    this.schedules = const [],
  });
}

class AiProgramDraftCommitService {
  final AiActionProtocolService actionProtocolService;

  const AiProgramDraftCommitService({
    this.actionProtocolService = const AiActionProtocolService(),
  });

  Future<AiProgramDraftCommitResult> commit(
    AiProgramActionProposal proposal,
  ) async {
    final latest = await AppDataStore.loadBundle();
    final working = latest.schedules
        .map((schedule) => Schedule.fromJson(schedule.toJson()))
        .toList();

    final validation = actionProtocolService.validate(proposal, working);
    if (!validation.isValid) {
      return AiProgramDraftCommitResult(
        saved: false,
        errors: validation.errors,
        schedules: working,
      );
    }

    final applyResult = actionProtocolService.apply(working, proposal);
    if (!applyResult.applied) {
      return AiProgramDraftCommitResult(
        saved: false,
        errors: applyResult.errors,
        schedules: working,
      );
    }

    await AppDataStore.saveSchedules(
      working,
      source: ScheduleVersionSource.aiCoach,
      reason: 'AI Coach program draft approved by user',
    );
    final persisted = await AppDataStore.loadBundle();

    return AiProgramDraftCommitResult(
      saved: true,
      createdSchedules: applyResult.createdSchedules,
      modifiedSchedules: applyResult.modifiedSchedules,
      schedules: persisted.schedules,
    );
  }
}
