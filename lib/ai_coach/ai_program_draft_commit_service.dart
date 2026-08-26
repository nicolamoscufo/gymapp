import 'package:shared_preferences/shared_preferences.dart';

import '../app_data_store.dart';
import '../models/exercise.dart';
import '../models/schedule.dart';
import '../models/schedule_version.dart';
import 'ai_action_protocol.dart';
import 'ai_program_draft_instance.dart';
import 'exercise_catalog_retriever.dart';

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
  final ExerciseCatalogRetriever exerciseCatalogRetriever;

  const AiProgramDraftCommitService({
    this.actionProtocolService = const AiActionProtocolService(),
    this.exerciseCatalogRetriever = const ExerciseCatalogRetriever(),
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
    final existingExercises = <String, Exercise>{
      for (final schedule in latest.schedules)
        for (final exercise in schedule.exercises)
          exercise.id: Exercise.fromJson(exercise.toJson()),
    };
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

    await _groundExercises(working, existingExercises);

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

  Future<void> _groundExercises(
    List<Schedule> schedules,
    Map<String, Exercise> existingExercises,
  ) async {
    for (final schedule in schedules) {
      for (final exercise in schedule.exercises) {
        final previous = existingExercises[exercise.id];
        final identityUnchanged = previous != null &&
            _sameExerciseIdentity(previous, exercise);
        final previousCatalogId = previous?.catalogId?.trim() ?? '';

        if (identityUnchanged && previousCatalogId.isNotEmpty) {
          exercise.catalogId = previousCatalogId;
          continue;
        }

        final resolved = await exerciseCatalogRetriever.resolveExercise(
          name: exercise.name,
          equipment: exercise.equipment,
          muscleGroup: exercise.muscleGroup,
        );
        if (resolved == null) {
          exercise.catalogId = identityUnchanged ? previous?.catalogId : null;
          continue;
        }

        exercise.catalogId = resolved.id;
        if (previous == null || !identityUnchanged) {
          exercise.name = resolved.name;
          exercise.muscleGroup = resolved.muscleGroup;
          exercise.equipment = resolved.equipment;
          exercise.movementPattern = resolved.movementPattern;
        }
      }
    }
  }

  bool _sameExerciseIdentity(Exercise a, Exercise b) {
    return a.name.trim().toLowerCase() == b.name.trim().toLowerCase() &&
        a.muscleGroup == b.muscleGroup &&
        a.equipment.trim().toLowerCase() == b.equipment.trim().toLowerCase() &&
        a.movementPattern.trim().toLowerCase() ==
            b.movementPattern.trim().toLowerCase();
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
