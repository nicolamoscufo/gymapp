import 'package:shared_preferences/shared_preferences.dart';

import '../app_data_store.dart';
import '../models/schedule.dart';
import '../models/schedule_version.dart';
import 'ai_action_protocol.dart';
import 'ai_program_draft_instance.dart';

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
  static const _appliedDraftInstancesKey =
      'aiCoachAppliedProgramDraftInstanceIds';
  static const _maxRememberedDrafts = 80;

  final AiActionProtocolService actionProtocolService;

  const AiProgramDraftCommitService({
    this.actionProtocolService = const AiActionProtocolService(),
  });

  Future<AiProgramDraftCommitResult> commit(
    AiProgramActionProposal proposal,
  ) async {
    final instanceId = proposal is InstancedAiProgramActionProposal
        ? proposal.draftInstanceId.trim()
        : '';
    if (instanceId.isNotEmpty && await _wasDraftInstanceApplied(instanceId)) {
      final latest = await AppDataStore.loadBundle();
      return AiProgramDraftCommitResult(
        saved: false,
        errors: const ['already_applied'],
        schedules: latest.schedules,
      );
    }

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
    if (instanceId.isNotEmpty) {
      await _rememberAppliedDraftInstance(instanceId);
    }
    final persisted = await AppDataStore.loadBundle();

    return AiProgramDraftCommitResult(
      saved: true,
      createdSchedules: applyResult.createdSchedules,
      modifiedSchedules: applyResult.modifiedSchedules,
      schedules: persisted.schedules,
    );
  }

  Future<bool> _wasDraftInstanceApplied(String instanceId) async {
    final prefs = await SharedPreferences.getInstance();
    final remembered =
        prefs.getStringList(_appliedDraftInstancesKey) ?? const <String>[];
    return remembered.contains(instanceId);
  }

  Future<void> _rememberAppliedDraftInstance(String instanceId) async {
    final prefs = await SharedPreferences.getInstance();
    final remembered = <String>[
      ...(prefs.getStringList(_appliedDraftInstancesKey) ?? const <String>[]),
    ]..remove(instanceId);
    remembered.add(instanceId);
    if (remembered.length > _maxRememberedDrafts) {
      remembered.removeRange(0, remembered.length - _maxRememberedDrafts);
    }
    await prefs.setStringList(_appliedDraftInstancesKey, remembered);
  }
}
