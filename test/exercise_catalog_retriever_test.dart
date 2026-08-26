import 'package:flutter_test/flutter_test.dart';
import 'package:gymapp/ai_coach/exercise_catalog_retriever.dart';
import 'package:gymapp/exercise_catalog.dart';
import 'package:gymapp/models/exercise.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('Italian muscle and equipment query retrieves matching exercise', () async {
    final retriever = ExerciseCatalogRetriever(catalogLoader: _catalogLoader);

    final context = await retriever.retrieveForQuestion(
      query: 'esercizi per il petto ai cavi',
      limit: 3,
    );

    expect(context.matches, isNotEmpty);
    expect(context.matches.first.entry.id, 'cable_fly');
    final json = context.toJson();
    expect(json['source'], 'local_exercise_catalog');
    expect(
      ((json['matches'] as List).first as Map)['instructions'],
      isNotEmpty,
    );
  });

  test('program retrieval diversifies upper-lower candidates', () async {
    final retriever = ExerciseCatalogRetriever(catalogLoader: _catalogLoader);

    final context = await retriever.retrieveForProgram(
      query: 'fammi una scheda upper lower',
      limit: 8,
    );

    final groups = context.matches.map((match) => match.entry.muscleGroup).toSet();
    expect(groups, contains(MuscleGroup.chest));
    expect(groups, contains(MuscleGroup.back));
    expect(groups, contains(MuscleGroup.quadriceps));
    expect(groups, contains(MuscleGroup.hamstrings));
    final json = context.toJson();
    expect(
      ((json['matches'] as List).first as Map).containsKey('instructions'),
      isFalse,
    );
  });

  test('resolveExercise accepts canonical name and safe token reordering', () async {
    final retriever = ExerciseCatalogRetriever(catalogLoader: _catalogLoader);

    final exact = await retriever.resolveExercise(name: 'cable standing fly');
    final reordered = await retriever.resolveExercise(
      name: 'incline dumbbell press',
      equipment: 'dumbbell',
      muscleGroup: MuscleGroup.chest,
    );

    expect(exact?.id, 'cable_fly');
    expect(reordered?.id, 'incline_db_press');
  });

  test('resolveExercise fails closed for an ambiguous custom exercise', () async {
    final retriever = ExerciseCatalogRetriever(catalogLoader: _catalogLoader);

    final result = await retriever.resolveExercise(name: 'press special');

    expect(result, isNull);
  });
}

Future<List<ExerciseCatalogEntry>> _catalogLoader() async => const [
  ExerciseCatalogEntry(
    id: 'cable_fly',
    name: 'cable standing fly',
    muscleGroup: MuscleGroup.chest,
    equipment: 'cable',
    movementPattern: 'Spinta',
    bodyPart: 'chest',
    target: 'pectorals',
    secondaryMuscles: ['deltoids'],
    instructions: ['Set the pulleys.', 'Bring the handles together.'],
    gifUrl: '',
  ),
  ExerciseCatalogEntry(
    id: 'incline_db_press',
    name: 'dumbbell incline press',
    muscleGroup: MuscleGroup.chest,
    equipment: 'dumbbell',
    movementPattern: 'Spinta',
    bodyPart: 'chest',
    target: 'pectorals',
    secondaryMuscles: ['triceps', 'deltoids'],
    instructions: ['Press the dumbbells upward.'],
    gifUrl: '',
  ),
  ExerciseCatalogEntry(
    id: 'row',
    name: 'cable seated row',
    muscleGroup: MuscleGroup.back,
    equipment: 'cable',
    movementPattern: 'Tirata',
    bodyPart: 'back',
    target: 'lats',
    secondaryMuscles: ['biceps'],
    instructions: ['Pull the handle toward the torso.'],
    gifUrl: '',
  ),
  ExerciseCatalogEntry(
    id: 'squat',
    name: 'barbell squat',
    muscleGroup: MuscleGroup.quadriceps,
    equipment: 'barbell',
    movementPattern: 'Gambe',
    bodyPart: 'upper legs',
    target: 'quadriceps',
    secondaryMuscles: ['glutes', 'hamstrings'],
    instructions: ['Squat under control.'],
    gifUrl: '',
  ),
  ExerciseCatalogEntry(
    id: 'rdl',
    name: 'barbell romanian deadlift',
    muscleGroup: MuscleGroup.hamstrings,
    equipment: 'barbell',
    movementPattern: 'Gambe',
    bodyPart: 'upper legs',
    target: 'hamstrings',
    secondaryMuscles: ['glutes'],
    instructions: ['Hinge at the hips.'],
    gifUrl: '',
  ),
  ExerciseCatalogEntry(
    id: 'lateral_raise',
    name: 'dumbbell lateral raise',
    muscleGroup: MuscleGroup.shoulders,
    equipment: 'dumbbell',
    movementPattern: 'Spalle',
    bodyPart: 'shoulders',
    target: 'deltoids',
    secondaryMuscles: [],
    instructions: ['Raise the dumbbells laterally.'],
    gifUrl: '',
  ),
  ExerciseCatalogEntry(
    id: 'curl',
    name: 'dumbbell biceps curl',
    muscleGroup: MuscleGroup.biceps,
    equipment: 'dumbbell',
    movementPattern: 'Braccia',
    bodyPart: 'upper arms',
    target: 'biceps',
    secondaryMuscles: [],
    instructions: ['Curl the dumbbells.'],
    gifUrl: '',
  ),
  ExerciseCatalogEntry(
    id: 'pushdown',
    name: 'cable triceps pushdown',
    muscleGroup: MuscleGroup.triceps,
    equipment: 'cable',
    movementPattern: 'Braccia',
    bodyPart: 'upper arms',
    target: 'triceps',
    secondaryMuscles: [],
    instructions: ['Extend the elbows.'],
    gifUrl: '',
  ),
];
