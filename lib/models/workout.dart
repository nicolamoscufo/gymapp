import 'model_id.dart';
import 'exercise.dart';

class ExerciseSet {
  final String id;
  double weight;
  int reps;
  bool isCompleted;
  bool isWarmup;
  double? rpe;
  int? rir;
  String notes;

  ExerciseSet({
    String? id,
    required this.weight,
    required this.reps,
    this.isCompleted = false,
    this.isWarmup = false,
    this.rpe,
    this.rir,
    this.notes = '',
  }) : id = id ?? newModelId('set');

  Map<String, dynamic> toJson() => {
    'id': id,
    'weight': weight,
    'reps': reps,
    'isCompleted': isCompleted,
    'isWarmup': isWarmup,
    'rpe': rpe,
    'rir': rir,
    'notes': notes,
  };

  factory ExerciseSet.fromJson(Map<String, dynamic> json) => ExerciseSet(
    id: json['id'] as String?,
    weight: (json['weight'] as num).toDouble(),
    reps: json['reps'] as int,
    isCompleted: json['isCompleted'] as bool? ?? false,
    isWarmup: json['isWarmup'] as bool? ?? false,
    rpe: (json['rpe'] as num?)?.toDouble(),
    rir: json['rir'] as int?,
    notes: json['notes'] as String? ?? '',
  );
}

class WorkoutExercise {
  final String id;
  String name;
  String notes;
  MuscleGroup muscleGroup;
  String equipment;
  String movementPattern;
  int? targetMinReps;
  int? targetMaxReps;
  IntensityTechnique technique;
  int? restSeconds;
  List<ExerciseSet> sets;
  List<double> previousWeights;
  List<int> previousReps;

  WorkoutExercise({
    String? id,
    required this.name,
    required this.notes,
    this.muscleGroup = MuscleGroup.unassigned,
    this.equipment = '',
    this.movementPattern = '',
    this.targetMinReps,
    this.targetMaxReps,
    required this.technique,
    this.restSeconds,
    required this.sets,
    this.previousWeights = const [],
    this.previousReps = const [],
  }) : id = id ?? newModelId('workout_exercise');

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'notes': notes,
    'muscleGroup': muscleGroup.name,
    'equipment': equipment,
    'movementPattern': movementPattern,
    'targetMinReps': targetMinReps,
    'targetMaxReps': targetMaxReps,
    'technique': technique.name,
    'restSeconds': restSeconds,
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
      name: json['name'] as String,
      notes: json['notes'] as String? ?? '',
      muscleGroup: muscleGroupFromJson(json['muscleGroup']),
      equipment: json['equipment'] as String? ?? '',
      movementPattern: json['movementPattern'] as String? ?? '',
      targetMinReps: json['targetMinReps'] as int?,
      targetMaxReps: json['targetMaxReps'] as int?,
      technique: parsedTechnique,
      restSeconds: json['restSeconds'] as int?,
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
  String scheduleTitle;
  DateTime startTime;
  DateTime endTime;
  List<WorkoutExercise> exercises;

  WorkoutSession({
    String? id,
    required this.scheduleTitle,
    required this.startTime,
    required this.endTime,
    required this.exercises,
  }) : id = id ?? newModelId('workout_session');

  Map<String, dynamic> toJson() => {
    'id': id,
    'scheduleTitle': scheduleTitle,
    'startTime': startTime.toIso8601String(),
    'endTime': endTime.toIso8601String(),
    'exercises': exercises.map((e) => e.toJson()).toList(),
  };

  factory WorkoutSession.fromJson(Map<String, dynamic> json) => WorkoutSession(
    id: json['id'] as String?,
    scheduleTitle: json['scheduleTitle'] as String,
    startTime: DateTime.parse(json['startTime'] as String),
    endTime: DateTime.parse(json['endTime'] as String),
    exercises: (json['exercises'] as List)
        .map((e) => WorkoutExercise.fromJson(e as Map<String, dynamic>))
        .toList(),
  );
}
