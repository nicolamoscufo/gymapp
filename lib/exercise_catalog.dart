import 'models/exercise.dart';

class ExerciseCatalogEntry {
  final String name;
  final MuscleGroup muscleGroup;
  final String equipment;
  final String movementPattern;

  const ExerciseCatalogEntry({
    required this.name,
    required this.muscleGroup,
    required this.equipment,
    required this.movementPattern,
  });
}

const exerciseCatalog = [
  ExerciseCatalogEntry(
    name: 'Panca piana',
    muscleGroup: MuscleGroup.chest,
    equipment: 'Bilanciere',
    movementPattern: 'Spinta orizzontale',
  ),
  ExerciseCatalogEntry(
    name: 'Panca inclinata manubri',
    muscleGroup: MuscleGroup.chest,
    equipment: 'Manubri',
    movementPattern: 'Spinta inclinata',
  ),
  ExerciseCatalogEntry(
    name: 'Trazioni',
    muscleGroup: MuscleGroup.back,
    equipment: 'Corpo libero',
    movementPattern: 'Tirata verticale',
  ),
  ExerciseCatalogEntry(
    name: 'Lat machine',
    muscleGroup: MuscleGroup.back,
    equipment: 'Macchina',
    movementPattern: 'Tirata verticale',
  ),
  ExerciseCatalogEntry(
    name: 'Rematore bilanciere',
    muscleGroup: MuscleGroup.back,
    equipment: 'Bilanciere',
    movementPattern: 'Tirata orizzontale',
  ),
  ExerciseCatalogEntry(
    name: 'Squat',
    muscleGroup: MuscleGroup.legs,
    equipment: 'Bilanciere',
    movementPattern: 'Squat',
  ),
  ExerciseCatalogEntry(
    name: 'Leg press',
    muscleGroup: MuscleGroup.quadriceps,
    equipment: 'Macchina',
    movementPattern: 'Squat',
  ),
  ExerciseCatalogEntry(
    name: 'Leg curl',
    muscleGroup: MuscleGroup.hamstrings,
    equipment: 'Macchina',
    movementPattern: 'Flessione ginocchio',
  ),
  ExerciseCatalogEntry(
    name: 'Stacco rumeno',
    muscleGroup: MuscleGroup.hamstrings,
    equipment: 'Bilanciere',
    movementPattern: 'Hinge',
  ),
  ExerciseCatalogEntry(
    name: 'Military press',
    muscleGroup: MuscleGroup.shoulders,
    equipment: 'Bilanciere',
    movementPattern: 'Spinta verticale',
  ),
  ExerciseCatalogEntry(
    name: 'Alzate laterali',
    muscleGroup: MuscleGroup.shoulders,
    equipment: 'Manubri',
    movementPattern: 'Abduzione spalla',
  ),
  ExerciseCatalogEntry(
    name: 'Curl bilanciere',
    muscleGroup: MuscleGroup.biceps,
    equipment: 'Bilanciere',
    movementPattern: 'Curl',
  ),
  ExerciseCatalogEntry(
    name: 'Pushdown cavo',
    muscleGroup: MuscleGroup.triceps,
    equipment: 'Cavo',
    movementPattern: 'Estensione gomito',
  ),
  ExerciseCatalogEntry(
    name: 'Plank',
    muscleGroup: MuscleGroup.abs,
    equipment: 'Corpo libero',
    movementPattern: 'Core anti-estensione',
  ),
];

ExerciseCatalogEntry? catalogEntryByName(String name) {
  final normalized = name.trim().toLowerCase();
  for (final entry in exerciseCatalog) {
    if (entry.name.toLowerCase() == normalized) {
      return entry;
    }
  }
  return null;
}
