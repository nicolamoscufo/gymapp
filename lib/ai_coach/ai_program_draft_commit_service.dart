import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

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
  static const _appliedNewProgramDraftsKey =
      'aiCoachAppliedNewProgramDraftFingerprints';
  static const _maxRememberedDrafts = 40;

  final AiActionProtocolService actionProtocolService;

  const AiProgramDraftCommitService({
    this.actionProtocolService = const AiActionProtocolService(),
  });

  Future<AiProgramDraftCommitResult> commit(
    AiProgramActionProposal proposal,
  ) async {
    // Modification drafts are naturally idempotent because their base version
    // becomes stale after a successful save. New-program drafts have no base
    // version, so remember successful exact proposals to prevent an old chat
    // card (or a UI race while switching conversations) from creating the same
    // program twice.
    if (await _wasNewProgramDraftApplied(proposal)) {
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
    await _rememberAppliedNewProgramDraft(proposal);
    final persisted = await AppDataStore.loadBundle();

    return AiProgramDraftCommitResult(
      saved: true,
      createdSchedules: applyResult.createdSchedules,
      modifiedSchedules: applyResult.modifiedSchedules,
      schedules: persisted.schedules,
    );
  }

  Future<bool> _wasNewProgramDraftApplied(
    AiProgramActionProposal proposal,
  ) async {
    if (proposal.kind != AiProgramActionKind.proposeProgram) return false;
    final prefs = await SharedPreferences.getInstance();
    final remembered =
        prefs.getStringList(_appliedNewProgramDraftsKey) ?? const <String>[];
    return remembered.contains(_proposalFingerprint(proposal));
  }

  Future<void> _rememberAppliedNewProgramDraft(
    AiProgramActionProposal proposal,
  ) async {
    if (proposal.kind != AiProgramActionKind.proposeProgram) return;
    final prefs = await SharedPreferences.getInstance();
    final fingerprint = _proposalFingerprint(proposal);
    final remembered = <String>[
      ...(prefs.getStringList(_appliedNewProgramDraftsKey) ?? const <String>[]),
    ]..remove(fingerprint);
    remembered.add(fingerprint);
    if (remembered.length > _maxRememberedDrafts) {
      remembered.removeRange(0, remembered.length - _maxRememberedDrafts);
    }
    await prefs.setStringList(_appliedNewProgramDraftsKey, remembered);
  }

  String _proposalFingerprint(AiProgramActionProposal proposal) =>
      jsonEncode(proposal.toJson());
}
