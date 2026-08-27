import '../models/exercise.dart';
import '../models/schedule.dart';

enum AiProgramActionKind { proposeProgram, modifyProgram }

extension AiProgramActionKindWire on AiProgramActionKind {
  String get wireName => switch (this) {
    AiProgramActionKind.proposeProgram => 'propose_program',
    AiProgramActionKind.modifyProgram => 'modify_program',
  };

  static AiProgramActionKind? parse(Object? value) {
    return switch (value?.toString().trim()) {
      'propose_program' => AiProgramActionKind.proposeProgram,
      'modify_program' => AiProgramActionKind.modifyProgram,
      _ => null,
    };
  }
}

class AiProgramDraftExercise {
  final String sourceExerciseId;
  final String name;
  final int sets;
  final int reps;
  final double weight;
  final String notes;
  final String muscleGroup;
  final String equipment;
  final String movementPattern;
  final int? targetMinReps;
  final int? targetMaxReps;
  final String technique;
  final int? backoffReps;
  final double backoffReductionPercent;
  final int? restSeconds;
  final int? supersetGroup;
  final double progressionKgStep;
  final int progressionRepStep;
  final String progressionScheme;

  const AiProgramDraftExercise({
    this.sourceExerciseId = '',
    required this.name,
    required this.sets,
    required this.reps,
    required this.weight,
    this.notes = '',
    this.muscleGroup = 'unassigned',
    this.equipment = '',
    this.movementPattern = '',
    this.targetMinReps,
    this.targetMaxReps,
    this.technique = 'none',
    this.backoffReps,
    this.backoffReductionPercent = 10,
    this.restSeconds,
    this.supersetGroup,
    this.progressionKgStep = 2.5,
    this.progressionRepStep = 1,
    this.progressionScheme = 'doubleProgression',
  });

  factory AiProgramDraftExercise.fromJson(Map<String, dynamic> json) {
    return AiProgramDraftExercise(
      sourceExerciseId: _string(json['source_exercise_id']),
      name: _string(json['name']),
      sets: _int(json['sets']),
      reps: _int(json['reps']),
      weight: _double(json['weight']),
      notes: _string(json['notes']),
      muscleGroup: _string(json['muscle_group'], fallback: 'unassigned'),
      equipment: _string(json['equipment']),
      movementPattern: _string(json['movement_pattern']),
      targetMinReps: _nullableInt(json['target_min_reps']),
      targetMaxReps: _nullableInt(json['target_max_reps']),
      technique: _string(json['technique'], fallback: 'none'),
      backoffReps: _nullableInt(json['backoff_reps']),
      backoffReductionPercent: _double(
        json['backoff_reduction_percent'],
        fallback: 10,
      ),
      restSeconds: _nullableInt(json['rest_seconds']),
      supersetGroup: _nullableInt(json['superset_group']),
      progressionKgStep: _double(json['progression_kg_step'], fallback: 2.5),
      progressionRepStep: _int(json['progression_rep_step'], fallback: 1),
      progressionScheme: _string(
        json['progression_scheme'],
        fallback: 'doubleProgression',
      ),
    );
  }

  Map<String, dynamic> toJson() => {
    'source_exercise_id': sourceExerciseId,
    'name': name,
    'sets': sets,
    'reps': reps,
    'weight': weight,
    'notes': notes,
    'muscle_group': muscleGroup,
    'equipment': equipment,
    'movement_pattern': movementPattern,
    'target_min_reps': targetMinReps,
    'target_max_reps': targetMaxReps,
    'technique': technique,
    'backoff_reps': backoffReps,
    'backoff_reduction_percent': backoffReductionPercent,
    'rest_seconds': restSeconds,
    'superset_group': supersetGroup,
    'progression_kg_step': progressionKgStep,
    'progression_rep_step': progressionRepStep,
    'progression_scheme': progressionScheme,
  };

  AiProgramDraftExercise copyWith({
    String? sourceExerciseId,
    String? name,
    int? sets,
    int? reps,
    double? weight,
    String? notes,
    String? muscleGroup,
    String? equipment,
    String? movementPattern,
    int? targetMinReps,
    bool clearTargetMinReps = false,
    int? targetMaxReps,
    bool clearTargetMaxReps = false,
    String? technique,
    int? backoffReps,
    bool clearBackoffReps = false,
    double? backoffReductionPercent,
    int? restSeconds,
    bool clearRestSeconds = false,
    int? supersetGroup,
    bool clearSupersetGroup = false,
    double? progressionKgStep,
    int? progressionRepStep,
    String? progressionScheme,
  }) {
    return AiProgramDraftExercise(
      sourceExerciseId: sourceExerciseId ?? this.sourceExerciseId,
      name: name ?? this.name,
      sets: sets ?? this.sets,
      reps: reps ?? this.reps,
      weight: weight ?? this.weight,
      notes: notes ?? this.notes,
      muscleGroup: muscleGroup ?? this.muscleGroup,
      equipment: equipment ?? this.equipment,
      movementPattern: movementPattern ?? this.movementPattern,
      targetMinReps: clearTargetMinReps
          ? null
          : targetMinReps ?? this.targetMinReps,
      targetMaxReps: clearTargetMaxReps
          ? null
          : targetMaxReps ?? this.targetMaxReps,
      technique: technique ?? this.technique,
      backoffReps: clearBackoffReps ? null : backoffReps ?? this.backoffReps,
      backoffReductionPercent:
          backoffReductionPercent ?? this.backoffReductionPercent,
      restSeconds: clearRestSeconds ? null : restSeconds ?? this.restSeconds,
      supersetGroup: clearSupersetGroup
          ? null
          : supersetGroup ?? this.supersetGroup,
      progressionKgStep: progressionKgStep ?? this.progressionKgStep,
      progressionRepStep: progressionRepStep ?? this.progressionRepStep,
      progressionScheme: progressionScheme ?? this.progressionScheme,
    );
  }
}

class AiProgramScheduleDraft {
  final String draftKey;
  final String baseScheduleId;
  final String baseVersionId;
  final String title;
  final String goal;
  final int mesocycleWeeks;
  final int deloadEveryWeeks;
  final List<int> trainingWeekdays;
  final String programBlock;
  final String cycleNotes;
  final List<AiProgramDraftExercise> exercises;

  const AiProgramScheduleDraft({
    required this.draftKey,
    this.baseScheduleId = '',
    this.baseVersionId = '',
    required this.title,
    this.goal = '',
    this.mesocycleWeeks = 8,
    this.deloadEveryWeeks = 4,
    this.trainingWeekdays = const [],
    this.programBlock = '',
    this.cycleNotes = '',
    required this.exercises,
  });

  factory AiProgramScheduleDraft.fromJson(Map<String, dynamic> json) {
    return AiProgramScheduleDraft(
      draftKey: _string(json['draft_key']),
      baseScheduleId: _string(json['base_schedule_id']),
      baseVersionId: _string(json['base_version_id']),
      title: _string(json['title']),
      goal: _string(json['goal']),
      mesocycleWeeks: _int(json['mesocycle_weeks'], fallback: 8),
      deloadEveryWeeks: _int(json['deload_every_weeks'], fallback: 4),
      trainingWeekdays: (json['training_weekdays'] as List? ?? const [])
          .whereType<num>()
          .map((entry) => entry.toInt())
          .toList(),
      programBlock: _string(json['program_block']),
      cycleNotes: _string(json['cycle_notes']),
      exercises: (json['exercises'] as List? ?? const [])
          .whereType<Map>()
          .map(
            (entry) => AiProgramDraftExercise.fromJson(
              Map<String, dynamic>.from(entry),
            ),
          )
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
    'draft_key': draftKey,
    'base_schedule_id': baseScheduleId,
    'base_version_id': baseVersionId,
    'title': title,
    'goal': goal,
    'mesocycle_weeks': mesocycleWeeks,
    'deload_every_weeks': deloadEveryWeeks,
    'training_weekdays': trainingWeekdays,
    'program_block': programBlock,
    'cycle_notes': cycleNotes,
    'exercises': exercises.map((entry) => entry.toJson()).toList(),
  };

  AiProgramScheduleDraft copyWith({
    String? draftKey,
    String? baseScheduleId,
    String? baseVersionId,
    String? title,
    String? goal,
    int? mesocycleWeeks,
    int? deloadEveryWeeks,
    List<int>? trainingWeekdays,
    String? programBlock,
    String? cycleNotes,
    List<AiProgramDraftExercise>? exercises,
  }) {
    return AiProgramScheduleDraft(
      draftKey: draftKey ?? this.draftKey,
      baseScheduleId: baseScheduleId ?? this.baseScheduleId,
      baseVersionId: baseVersionId ?? this.baseVersionId,
      title: title ?? this.title,
      goal: goal ?? this.goal,
      mesocycleWeeks: mesocycleWeeks ?? this.mesocycleWeeks,
      deloadEveryWeeks: deloadEveryWeeks ?? this.deloadEveryWeeks,
      trainingWeekdays: trainingWeekdays ?? this.trainingWeekdays,
      programBlock: programBlock ?? this.programBlock,
      cycleNotes: cycleNotes ?? this.cycleNotes,
      exercises: exercises ?? this.exercises,
    );
  }
}

class AiProgramActionProposal {
  static const payloadType = 'program_draft';

  final AiProgramActionKind kind;
  final String summary;
  final String rationale;
  final List<String> evidence;
  final String confidence;
  final List<AiProgramScheduleDraft> schedules;

  const AiProgramActionProposal({
    required this.kind,
    required this.summary,
    required this.rationale,
    this.evidence = const [],
    this.confidence = 'low',
    required this.schedules,
  });

  factory AiProgramActionProposal.fromJson(Map<String, dynamic> json) {
    final kind = AiProgramActionKindWire.parse(json['action']);
    if (kind == null) {
      throw const FormatException('Unsupported AI program action.');
    }
    final draft = json['program_draft'];
    final draftMap = draft is Map
        ? Map<String, dynamic>.from(draft)
        : <String, dynamic>{};
    return AiProgramActionProposal(
      kind: kind,
      summary: _string(json['summary']),
      rationale: _string(json['rationale']),
      evidence: _stringList(json['evidence']),
      confidence: _string(json['confidence'], fallback: 'low'),
      schedules: (draftMap['schedules'] as List? ?? const [])
          .whereType<Map>()
          .map(
            (entry) => AiProgramScheduleDraft.fromJson(
              Map<String, dynamic>.from(entry),
            ),
          )
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
    'payload_type': payloadType,
    'action': kind.wireName,
    'summary': summary,
    'rationale': rationale,
    'evidence': evidence,
    'confidence': confidence,
    'requires_user_confirmation': true,
    'program_draft': {
      'schedules': schedules.map((entry) => entry.toJson()).toList(),
    },
  };

  factory AiProgramActionProposal.fromActionPayload(Map<String, dynamic> json) {
    if (_string(json['payload_type']) != payloadType) {
      throw const FormatException('Not a program draft payload.');
    }
    return AiProgramActionProposal.fromJson(json);
  }

  AiProgramActionProposal copyWith({
    AiProgramActionKind? kind,
    String? summary,
    String? rationale,
    List<String>? evidence,
    String? confidence,
    List<AiProgramScheduleDraft>? schedules,
  }) {
    return AiProgramActionProposal(
      kind: kind ?? this.kind,
      summary: summary ?? this.summary,
      rationale: rationale ?? this.rationale,
      evidence: evidence ?? this.evidence,
      confidence: confidence ?? this.confidence,
      schedules: schedules ?? this.schedules,
    );
  }
}

class AiProgramDraftValidationResult {
  final List<String> errors;

  const AiProgramDraftValidationResult(this.errors);

  bool get isValid => errors.isEmpty;
}

class AiProgramApplyResult {
  final bool applied;
  final int createdSchedules;
  final int modifiedSchedules;
  final List<String> errors;

  const AiProgramApplyResult({
    required this.applied,
    this.createdSchedules = 0,
    this.modifiedSchedules = 0,
    this.errors = const [],
  });
}

class AiActionProtocolService {
  const AiActionProtocolService();

  AiProgramDraftValidationResult validate(
    AiProgramActionProposal proposal,
    List<Schedule> currentSchedules,
  ) {
    final errors = <String>[];
    if (proposal.summary.trim().length > 500) {
      errors.add('summary_too_long');
    }
    if (proposal.rationale.trim().isEmpty) {
      errors.add('missing_rationale');
    }
    if (!const {'low', 'medium', 'high'}.contains(proposal.confidence)) {
      errors.add('invalid_confidence');
    }
    if (proposal.schedules.isEmpty || proposal.schedules.length > 14) {
      errors.add('invalid_schedule_count');
      return AiProgramDraftValidationResult(errors);
    }

    final draftKeys = <String>{};
    final baseScheduleIds = <String>{};
    final currentById = {
      for (final schedule in currentSchedules) schedule.id: schedule,
    };

    for (final draft in proposal.schedules) {
      final prefix = draft.draftKey.trim().isEmpty
          ? 'schedule'
          : draft.draftKey.trim();
      if (draft.draftKey.trim().isEmpty || !draftKeys.add(draft.draftKey)) {
        errors.add('$prefix:invalid_or_duplicate_draft_key');
      }
      if (draft.title.trim().isEmpty || draft.title.trim().length > 80) {
        errors.add('$prefix:invalid_title');
      }
      if (draft.goal.length > 240 ||
          draft.programBlock.length > 160 ||
          draft.cycleNotes.length > 500) {
        errors.add('$prefix:text_field_too_long');
      }
      if (draft.mesocycleWeeks < 1 || draft.mesocycleWeeks > 52) {
        errors.add('$prefix:invalid_mesocycle_weeks');
      }
      if (draft.deloadEveryWeeks < 0 || draft.deloadEveryWeeks > 52) {
        errors.add('$prefix:invalid_deload_weeks');
      }
      final weekdays = draft.trainingWeekdays.toSet();
      if (weekdays.length != draft.trainingWeekdays.length ||
          weekdays.any((day) => day < 1 || day > 7)) {
        errors.add('$prefix:invalid_training_weekdays');
      }
      if (draft.exercises.isEmpty || draft.exercises.length > 30) {
        errors.add('$prefix:invalid_exercise_count');
      }

      Schedule? base;
      if (proposal.kind == AiProgramActionKind.proposeProgram) {
        if (draft.baseScheduleId.isNotEmpty || draft.baseVersionId.isNotEmpty) {
          errors.add('$prefix:proposed_program_cannot_reference_base_schedule');
        }
      } else if (draft.baseScheduleId.isNotEmpty) {
        base = currentById[draft.baseScheduleId];
        if (base == null) {
          errors.add('$prefix:unknown_base_schedule');
        } else {
          if (!baseScheduleIds.add(base.id)) {
            errors.add('$prefix:duplicate_base_schedule');
          }
          final currentVersion = base.currentVersionId ?? '';
          if (currentVersion != draft.baseVersionId) {
            errors.add('$prefix:stale_base_version');
          }
        }
      }

      final sourceIds = <String>{};
      final knownExerciseIds = {
        for (final exercise in base?.exercises ?? const <Exercise>[])
          exercise.id,
      };
      for (var index = 0; index < draft.exercises.length; index += 1) {
        final exercise = draft.exercises[index];
        final ep = '$prefix:exercise_$index';
        if (exercise.name.trim().isEmpty || exercise.name.trim().length > 80) {
          errors.add('$ep:invalid_name');
        }
        if (exercise.sets < 1 || exercise.sets > 20) {
          errors.add('$ep:invalid_sets');
        }
        if (exercise.reps < 1 || exercise.reps > 100) {
          errors.add('$ep:invalid_reps');
        }
        if (!exercise.weight.isFinite ||
            exercise.weight < 0 ||
            exercise.weight > 1000) {
          errors.add('$ep:invalid_weight');
        }
        if (exercise.notes.length > 500 ||
            exercise.equipment.length > 100 ||
            exercise.movementPattern.length > 100) {
          errors.add('$ep:text_field_too_long');
        }
        if (!_validEnum(MuscleGroup.values, exercise.muscleGroup)) {
          errors.add('$ep:invalid_muscle_group');
        }
        if (!_validEnum(IntensityTechnique.values, exercise.technique)) {
          errors.add('$ep:invalid_technique');
        }
        if (!_validEnum(ProgressionScheme.values, exercise.progressionScheme)) {
          errors.add('$ep:invalid_progression_scheme');
        }
        final minReps = exercise.targetMinReps;
        final maxReps = exercise.targetMaxReps;
        if ((minReps != null && (minReps < 1 || minReps > 100)) ||
            (maxReps != null && (maxReps < 1 || maxReps > 100)) ||
            (minReps != null && maxReps != null && minReps > maxReps)) {
          errors.add('$ep:invalid_target_rep_range');
        }
        if (exercise.restSeconds != null &&
            (exercise.restSeconds! < 0 || exercise.restSeconds! > 900)) {
          errors.add('$ep:invalid_rest_seconds');
        }
        if (exercise.backoffReps != null &&
            (exercise.backoffReps! < 0 || exercise.backoffReps! > 100)) {
          errors.add('$ep:invalid_backoff_reps');
        }
        if (!exercise.backoffReductionPercent.isFinite ||
            exercise.backoffReductionPercent < 0 ||
            exercise.backoffReductionPercent > 100) {
          errors.add('$ep:invalid_backoff_reduction');
        }
        if (!exercise.progressionKgStep.isFinite ||
            exercise.progressionKgStep < 0 ||
            exercise.progressionKgStep > 100) {
          errors.add('$ep:invalid_progression_kg_step');
        }
        if (exercise.progressionRepStep < 0 ||
            exercise.progressionRepStep > 20) {
          errors.add('$ep:invalid_progression_rep_step');
        }

        final sourceId = exercise.sourceExerciseId.trim();
        if (proposal.kind == AiProgramActionKind.proposeProgram) {
          if (sourceId.isNotEmpty) {
            errors.add('$ep:proposed_program_cannot_reference_exercise');
          }
        } else if (sourceId.isNotEmpty) {
          if (base == null || !knownExerciseIds.contains(sourceId)) {
            errors.add('$ep:unknown_source_exercise');
          } else if (!sourceIds.add(sourceId)) {
            errors.add('$ep:duplicate_source_exercise');
          }
        }
      }
    }

    return AiProgramDraftValidationResult(errors);
  }

  AiProgramApplyResult apply(
    List<Schedule> currentSchedules,
    AiProgramActionProposal proposal, {
    DateTime? now,
  }) {
    final validation = validate(proposal, currentSchedules);
    if (!validation.isValid) {
      return AiProgramApplyResult(applied: false, errors: validation.errors);
    }

    final timestamp = now ?? DateTime.now();
    final currentById = {
      for (final schedule in currentSchedules) schedule.id: schedule,
    };
    final replacements = <String, Schedule>{};
    final additions = <Schedule>[];

    for (final draft in proposal.schedules) {
      final base = draft.baseScheduleId.isEmpty
          ? null
          : currentById[draft.baseScheduleId];
      if (base == null) {
        additions.add(_materializeNew(draft, timestamp));
      } else {
        replacements[base.id] = _materializeReplacement(base, draft);
      }
    }

    // Atomic mutation: no caller-owned state is touched until every draft has
    // validated and every replacement/new schedule has been materialized.
    for (var index = 0; index < currentSchedules.length; index += 1) {
      final replacement = replacements[currentSchedules[index].id];
      if (replacement != null) currentSchedules[index] = replacement;
    }
    currentSchedules.addAll(additions);

    return AiProgramApplyResult(
      applied: true,
      createdSchedules: additions.length,
      modifiedSchedules: replacements.length,
    );
  }

  Schedule _materializeNew(AiProgramScheduleDraft draft, DateTime now) {
    return Schedule(
      title: draft.title.trim(),
      week: 1,
      createdAt: now,
      exercises: draft.exercises.map((entry) => _exercise(entry)).toList(),
      mesocycleWeeks: draft.mesocycleWeeks,
      deloadEveryWeeks: draft.deloadEveryWeeks,
      goal: draft.goal.trim(),
      trainingWeekdays: [...draft.trainingWeekdays]..sort(),
      programBlock: draft.programBlock.trim(),
      cycleNumber: 1,
      cycleNotes: draft.cycleNotes.trim(),
    );
  }

  Schedule _materializeReplacement(
    Schedule base,
    AiProgramScheduleDraft draft,
  ) {
    final existingById = {
      for (final exercise in base.exercises) exercise.id: exercise,
    };
    return Schedule(
      id: base.id,
      title: draft.title.trim(),
      week: base.week,
      createdAt: base.createdAt,
      exercises: draft.exercises
          .map(
            (entry) => _exercise(
              entry,
              id: entry.sourceExerciseId.isEmpty
                  ? null
                  : existingById[entry.sourceExerciseId]?.id,
            ),
          )
          .toList(),
      isArchived: base.isArchived,
      mesocycleWeeks: draft.mesocycleWeeks,
      deloadEveryWeeks: draft.deloadEveryWeeks,
      goal: draft.goal.trim(),
      trainingWeekdays: [...draft.trainingWeekdays]..sort(),
      programBlock: draft.programBlock.trim(),
      cycleNumber: base.cycleNumber,
      cycleNotes: draft.cycleNotes.trim(),
      currentVersionId: base.currentVersionId,
      currentVersionNumber: base.currentVersionNumber,
    );
  }

  Exercise _exercise(AiProgramDraftExercise draft, {String? id}) {
    return Exercise(
      id: id,
      name: draft.name.trim(),
      reps: draft.reps,
      set: draft.sets,
      notes: draft.notes.trim(),
      weight: draft.weight,
      muscleGroup: MuscleGroup.values.byName(draft.muscleGroup),
      equipment: draft.equipment.trim(),
      movementPattern: draft.movementPattern.trim(),
      targetMinReps: draft.targetMinReps,
      targetMaxReps: draft.targetMaxReps,
      technique: IntensityTechnique.values.byName(draft.technique),
      backoffReps: draft.backoffReps,
      backoffReductionPercent: draft.backoffReductionPercent,
      restSeconds: draft.restSeconds,
      supersetGroup: draft.supersetGroup,
      progressionKgStep: draft.progressionKgStep,
      progressionRepStep: draft.progressionRepStep,
      progressionScheme: ProgressionScheme.values.byName(
        draft.progressionScheme,
      ),
    );
  }
}

bool looksLikeProgramActionIntent(String text) {
  final normalized = text.trim().toLowerCase();
  if (normalized.isEmpty) return false;
  final programTerms = <String>[
    'scheda',
    'programma',
    'routine',
    'workout plan',
    'training plan',
    'split',
  ];
  final actionTerms = <String>[
    'crea',
    'fammi',
    'genera',
    'nuova',
    'rifai',
    'modifica',
    'cambia',
    'sostituisci',
    'aggiorna',
    'create',
    'make',
    'build',
    'generate',
    'new',
    'modify',
    'change',
    'replace',
    'update',
  ];
  return programTerms.any(normalized.contains) &&
      actionTerms.any(normalized.contains);
}

bool _validEnum<T extends Enum>(List<T> values, String raw) {
  return values.any((entry) => entry.name == raw);
}

String _string(Object? value, {String fallback = ''}) {
  final text = value?.toString().trim() ?? '';
  return text.isEmpty ? fallback : text;
}

int _int(Object? value, {int fallback = 0}) {
  if (value is int) return value;
  if (value is num) return value.round();
  return double.tryParse(value?.toString().replaceAll(',', '.') ?? '')?.round() ??
      fallback;
}

int? _nullableInt(Object? value) {
  if (value == null || value.toString().trim().isEmpty) return null;
  if (value is int) return value;
  if (value is num) return value.round();
  return double.tryParse(value.toString().replaceAll(',', '.'))?.round();
}

double _double(Object? value, {double fallback = 0}) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString().replaceAll(',', '.') ?? '') ??
      fallback;
}

List<String> _stringList(Object? value) {
  if (value is! List) return const [];
  return value
      .map((entry) => entry.toString().trim())
      .where((entry) => entry.isNotEmpty)
      .toList();
}
