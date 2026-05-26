import 'model_id.dart';

enum MuscleGroup {
  unassigned,
  chest,
  back,
  quadriceps,
  hamstrings,
  legs,
  biceps,
  triceps,
  arms,
  shoulders,
  abs,
}

const selectableMuscleGroups = [
  MuscleGroup.chest,
  MuscleGroup.back,
  MuscleGroup.quadriceps,
  MuscleGroup.hamstrings,
  MuscleGroup.legs,
  MuscleGroup.biceps,
  MuscleGroup.triceps,
  MuscleGroup.arms,
  MuscleGroup.shoulders,
  MuscleGroup.abs,
];

extension MuscleGroupLabel on MuscleGroup {
  String get label {
    return switch (this) {
      MuscleGroup.unassigned => 'Non assegnato',
      MuscleGroup.chest => 'Petto',
      MuscleGroup.back => 'Dorso',
      MuscleGroup.quadriceps => 'Quadricipiti',
      MuscleGroup.hamstrings => 'Bicipiti femorali',
      MuscleGroup.legs => 'Gambe (Quadricipiti + bicipiti femorali)',
      MuscleGroup.biceps => 'Bicipiti',
      MuscleGroup.triceps => 'Tricipiti',
      MuscleGroup.arms => 'Braccia (Bicipiti + Tricipiti)',
      MuscleGroup.shoulders => 'Spalle',
      MuscleGroup.abs => 'Addome',
    };
  }
}

MuscleGroup muscleGroupFromJson(Object? value) {
  if (value == null) {
    return MuscleGroup.unassigned;
  }

  final normalized = value.toString().trim();
  for (final group in MuscleGroup.values) {
    if (group.name == normalized || group.label == normalized) {
      return group;
    }
  }

  return MuscleGroup.unassigned;
}

// Definiamo un enum con le tecniche di intensità più comuni
enum IntensityTechnique {
  none, // Nessuna tecnica (serie normale)
  dropSet, // Stripping / Drop Set
  restPause, // Rest-Pause
  superSet, // Superset
  cluster, // Cluster Set
  isometric, // Isometria
  negative, // Ripetizioni negative
  forcedReps, // Ripetizioni forzate
  topsetBackoff, // Top Set + Back off
}

class Exercise {
  final String id;
  String name;
  int reps;
  int set;
  String notes;
  double weight;
  MuscleGroup muscleGroup;
  String equipment;
  String movementPattern;
  int? targetMinReps;
  int? targetMaxReps;
  IntensityTechnique technique; // Aggiornato per usare l'enum
  int? backoffReps;
  int? restSeconds;

  Exercise({
    String? id,
    required this.name,
    required this.reps,
    required this.set,
    required this.notes,
    required this.weight,
    this.muscleGroup = MuscleGroup.unassigned,
    this.equipment = '',
    this.movementPattern = '',
    this.targetMinReps,
    this.targetMaxReps,
    required this.technique,
    this.backoffReps,
    this.restSeconds,
  }) : id = id ?? newModelId('exercise');

  String get targetRepsLabel {
    if (targetMinReps != null && targetMaxReps != null) {
      if (targetMinReps == targetMaxReps) {
        return '$targetMaxReps reps';
      }
      return '$targetMinReps-$targetMaxReps reps';
    }
    return '$reps reps';
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'reps': reps,
    'set': set,
    'notes': notes,
    'weight': weight,
    'muscleGroup': muscleGroup.name,
    'equipment': equipment,
    'movementPattern': movementPattern,
    'targetMinReps': targetMinReps,
    'targetMaxReps': targetMaxReps,
    'technique': technique.name, // Salviamo l'enum come Stringa (es: "dropSet")
    'backoffReps': backoffReps,
    'restSeconds': restSeconds,
  };

  factory Exercise.fromJson(Map<String, dynamic> json) {
    // Gestione sicura del parsing dell'enum
    IntensityTechnique parsedTechnique = IntensityTechnique.none;
    if (json['technique'] != null) {
      try {
        parsedTechnique = IntensityTechnique.values.byName(json['technique']);
      } catch (e) {
        // Fallback in caso di valore non valido nel JSON
        parsedTechnique = IntensityTechnique.none;
      }
    }

    return Exercise(
      id: json['id'] as String?,
      name: json['name'],
      reps: json['reps'],
      set: json['set'],
      notes: json['notes'],
      weight: json['weight'] is int
          ? (json['weight'] as int).toDouble()
          : (json['weight'] ?? 0.0), // Aggiunto fallback per evitare null
      muscleGroup: muscleGroupFromJson(json['muscleGroup']),
      equipment: json['equipment'] as String? ?? '',
      movementPattern: json['movementPattern'] as String? ?? '',
      targetMinReps: json['targetMinReps'] as int?,
      targetMaxReps: json['targetMaxReps'] as int?,
      technique: parsedTechnique, // Ripristiniamo l'enum
      backoffReps: json['backoffReps'] as int?,
      restSeconds: json['restSeconds'] as int?,
    );
  }
}
