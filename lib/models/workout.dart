import 'model_id.dart';
import 'exercise.dart';
import '../top_set_backoff.dart';

enum SetType { normal, warmup, drop, failure }

extension SetTypeLabel on SetType {
  String get label => switch (this) {
    SetType.normal => 'Normale',
    SetType.warmup => 'Warm-up',
    SetType.drop => 'Drop',
    SetType.failure => 'Failure',
  };

  String get shortLabel => switch (this) {
    SetType.normal => 'N',
    SetType.warmup => 'W',
    SetType.drop => 'D',
    SetType.failure => 'F',
  };
}

class ExerciseSet {
  final String id;
  double weight;
  int reps;
  bool isCompleted;
  SetType type;
  double? rpe;
  int? rir;
  String notes;

  ExerciseSet({
    String? id,
    required this.weight,
    required this.reps,
    this.isCompleted = false,
    bool isWarmup = false,
    SetType? type,
    this.rpe,
    this.rir,
    this.notes = '',
  }) : id = id ?? newModelId('set'),
       type = type ?? (isWarmup ? SetType.warmup : SetType.normal);

  bool get isWarmup => type == SetType.warmup;

  set isWarmup(bool value) {
    if (value) {
      type = SetType.warmup;
    } else if (type == SetType.warmup) {
      type = SetType.normal;
    }
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'weight': weight,
    'reps': reps,
    'isCompleted': isCompleted,
    'type': type.name,
    // Kept for backwards/forwards compatibility with older backups.
    'isWarmup': isWarmup,
    'rpe': rpe,
    'rir': rir,
    'notes': notes,
  };

  factory ExerciseSet.fromJson(Map<String, dynamic> json) {
    SetType? parsedType;
    final rawType = json['type'];
    if (rawType is String) {
      try {
        parsedType = SetType.values.byName(rawType);
      } catch (_) {
        parsedType = null;
      }
    }

    return ExerciseSet(
      id: json['id'] as String?,
      weight: (json['weight'] as num).toDouble(),
      reps: json['reps'] as int,
      isCompleted: json['isCompleted'] as bool? ?? false,
      isWarmup: json['isWarmup'] as bool? ?? false,
      type: parsedType,
      rpe: (json['rpe'] as num?)?.toDouble(),
      rir: json['rir'] as int?,
      notes: json['notes'] as String? ?? '',
    );
  }
}

class WorkoutExercise {
  final String id;
  String? sourceExerciseId;
  String? catalogId;
  String name;
  String notes;
  MuscleGroup muscleGroup;
  String equipment;
  String movementPattern;
  int? targetMinReps;
  int? targetMaxReps;
  IntensityTechnique technique;
  double backoffReductionPercent;
  int? restSeconds;
  int? activeRestSeconds;
  DateTime? activeRestStartedAt;
  int? supersetGroup;
  double progressionKgStep;
  int progressionRepStep;
  ProgressionScheme progressionScheme;
  List<ExerciseSet> sets;
  List<double> previousWeights;
  List<int> previousReps;

  WorkoutExercise({
    String? id,
    this.sourceExerciseId,
    this.catalogId,
    required this.name,
    required this.notes,
    this.muscleGroup = MuscleGroup.unassigned,
    this.equipment = '',
    this.movementPattern = '',
    this.targetMinReps,
    this.targetMaxReps,
    required this.technique,
    this.backoffReductionPercent = defaultBackoffReductionPercent,
    this.restSeconds,
    this.activeRestSeconds,
    this.activeRestStartedAt,
    this.supersetGroup,
    this.progressionKgStep = 2.5,
    this.progressionRepStep = 1,
    this.progressionScheme = ProgressionScheme.doubleProgression,
    required this.sets,
    this.previousWeights = const [],
    this.previousReps = const [],
  }) : id = id ?? newModelId('workout_exercise');

  Map<String, dynamic> toJson() => {
    'id': id,
    'sourceExerciseId': sourceExerciseId,
    'catalogId': catalogId,
    'name': name,
    'notes': notes,
    'muscleGroup': muscleGroup.name,
    'equipment': equipment,
    'movementPattern': movementPattern,
    'targetMinReps': targetMinReps,
    'targetMaxReps': targetMaxReps,
    'technique': technique.name,
    'backoffReductionPercent': backoffReductionPercent,
    'restSeconds': restSeconds,
    'activeRestSeconds': activeRestSeconds,
    'activeRestStartedAt': activeRestStartedAt?.toIso8601String(),
    'supersetGroup': supersetGroup,
    'progressionKgStep': progressionKgStep,
    'progressionRepStep': progressionRepStep,
    'progressionScheme': progressionScheme.name,
    'sets': sets.map((e) => e.toJson()).toList(),
    'previousWeights': previousWeights,
    'previousReps': previousReps,
  };

  factory WorkoutExercise.fromJson(Map<String, dynamic> json) {
    IntensityTechnique parsedTechnique = IntensityTechnique.none;
    if (json['technique'] != null) {
      try {
        parsedTechnique = IntensityTechnique.values.byName(json['technique']);
      } catch (e) {
        parsedTechnique = IntensityTechnique.none;
      }
    }

    return WorkoutExercise(
      id: json['id'] as String?,
      sourceExerciseId: json['sourceExerciseId'] as String?,
      catalogId: json['catalogId'] as String?,
      name: json['name'] as String,
      notes: json['notes'] as String? ?? '',
      muscleGroup: muscleGroupFromJson(json['muscleGroup']),
      equipment: json['equipment'] as String? ?? '',
      movementPattern: json['movementPattern'] as String? ?? '',
      targetMinReps: json['targetMinReps'] as int?,
      targetMaxReps: json['targetMaxReps'] as int?,
      technique: parsedTechnique,
      backoffReductionPercent:
          (json['backoffReductionPercent'] as num?)?.toDouble() ??
          defaultBackoffReductionPercent,
      restSeconds: json['restSeconds'] as int?,
      activeRestSeconds: json['activeRestSeconds'] as int?,
      activeRestStartedAt: json['activeRestStartedAt'] == null
          ? null
          : DateTime.tryParse(json['activeRestStartedAt'] as String),
      supersetGroup: json['supersetGroup'] as int?,
      progressionKgStep: (json['progressionKgStep'] as num?)?.toDouble() ?? 2.5,
      progressionRepStep: json['progressionRepStep'] as int? ?? 1,
      progressionScheme: progressionSchemeFromJson(json['progressionScheme']),
      sets: (json['sets'] as List)
          .map((e) => ExerciseSet.fromJson(e as Map<String, dynamic>))
          .toList(),
      previousWeights: (json['previousWeights'] as List? ?? [])
          .whereType<num>()
          .map((weight) => weight.toDouble())
          .toList(),
      previousReps: (json['previousReps'] as List? ?? [])
          .whereType<num>()
          .map((reps) => reps.toInt())
          .toList(),
    );
  }
}

class WorkoutSession {
  final String id;
  String? scheduleId;
  String? scheduleVersionId;
  String scheduleTitle;
  DateTime startTime;
  DateTime endTime;
  List<WorkoutExercise> exercises;

  WorkoutSession({
    String? id,
    this.scheduleId,
    this.scheduleVersionId,
    required this.scheduleTitle,
    required this.startTime,
    required this.endTime,
    required this.exercises,
  }) : id = id ?? newModelId('workout_session');

  Map<String, dynamic> toJson() => {
    'id': id,
    'scheduleId': scheduleId,
    'scheduleVersionId': scheduleVersionId,
    'scheduleTitle': scheduleTitle,
    'startTime': startTime.toIso8601String(),
    'endTime': endTime.toIso8601String(),
    'exercises': exercises.map((e) => e.toJson()).toList(),
  };

  factory WorkoutSession.fromJson(Map<String, dynamic> json) => WorkoutSession(
    id: json['id'] as String?,
    scheduleId: json['scheduleId'] as String?,
    scheduleVersionId: json['scheduleVersionId'] as String?,
    scheduleTitle: json['scheduleTitle'] as String,
    startTime: DateTime.parse(json['startTime'] as String),
    endTime: DateTime.parse(json['endTime'] as String),
    exercises: (json['exercises'] as List)
        .map((e) => WorkoutExercise.fromJson(e as Map<String, dynamic>))
        .toList(),
  );
}
