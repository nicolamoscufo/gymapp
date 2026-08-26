import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gymapp/exercise_catalog.dart';
import 'package:gymapp/exercise_catalog_identity.dart';
import 'package:gymapp/models/exercise.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    clearExerciseCatalogIdentityRegistryForTesting();
  });

  test('parsed canonical catalog entry is inherited by picker-style Exercise', () {
    parseExerciseCatalog(
      jsonEncode([
        {
          'id': 'cable_fly',
          'name': 'cable standing fly',
          'bodyPart': 'chest',
          'target': 'pectorals',
          'equipment': 'cable',
          'secondaryMuscles': ['deltoids'],
          'instructions': ['Bring the handles together.'],
          'gifUrl': '',
        },
      ]),
    );

    final exercise = Exercise(
      name: '  Cable Standing Fly  ',
      reps: 10,
      set: 3,
      notes: '',
      weight: 0,
      muscleGroup: MuscleGroup.chest,
      equipment: 'cable',
      movementPattern: 'Spinta',
      technique: IntensityTechnique.none,
    );

    expect(exercise.catalogId, 'cable_fly');
  });

  test('persisted exercise ids are not silently backfilled from registry', () {
    registerExerciseCatalogIdentity(
      name: 'barbell bench press',
      catalogId: 'bench_catalog',
    );

    final restored = Exercise(
      id: 'persisted-bench',
      name: 'barbell bench press',
      reps: 8,
      set: 3,
      notes: '',
      weight: 80,
      muscleGroup: MuscleGroup.chest,
      equipment: 'barbell',
      movementPattern: 'Spinta',
      technique: IntensityTechnique.none,
    );

    expect(restored.catalogId, isNull);
  });

  test('ambiguous duplicate canonical names are not auto-linked', () {
    parseExerciseCatalog(
      jsonEncode([
        {
          'id': 'row_a',
          'name': 'dumbbell row',
          'bodyPart': 'back',
          'target': 'lats',
          'equipment': 'dumbbell',
          'secondaryMuscles': ['biceps'],
          'instructions': [],
          'gifUrl': '',
        },
        {
          'id': 'row_b',
          'name': 'dumbbell row',
          'bodyPart': 'back',
          'target': 'lats',
          'equipment': 'dumbbell',
          'secondaryMuscles': ['biceps'],
          'instructions': [],
          'gifUrl': '',
        },
      ]),
    );

    final exercise = Exercise(
      name: 'dumbbell row',
      reps: 10,
      set: 3,
      notes: '',
      weight: 0,
      technique: IntensityTechnique.none,
    );

    expect(exercise.catalogId, isNull);
  });

  test('custom names remain unlinked and explicit catalogId wins', () {
    registerExerciseCatalogIdentity(
      name: 'barbell bench press',
      catalogId: 'bench_catalog',
    );

    final custom = Exercise(
      name: 'My custom press',
      reps: 8,
      set: 3,
      notes: '',
      weight: 50,
      technique: IntensityTechnique.none,
    );
    final explicit = Exercise(
      catalogId: 'manual_override',
      name: 'barbell bench press',
      reps: 8,
      set: 3,
      notes: '',
      weight: 80,
      technique: IntensityTechnique.none,
    );

    expect(custom.catalogId, isNull);
    expect(explicit.catalogId, 'manual_override');
  });
}
