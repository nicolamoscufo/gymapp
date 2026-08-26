import 'package:flutter_test/flutter_test.dart';
import 'package:gymapp/models/exercise.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('catalogId roundtrips through Exercise JSON', () {
    final exercise = Exercise(
      id: 'bench-instance',
      catalogId: 'catalog-bench',
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

    final restored = Exercise.fromJson(exercise.toJson());

    expect(restored.id, 'bench-instance');
    expect(restored.catalogId, 'catalog-bench');
  });

  test('legacy Exercise JSON without catalogId remains compatible', () {
    final restored = Exercise.fromJson({
      'id': 'legacy',
      'name': 'Panca',
      'reps': 8,
      'set': 3,
      'notes': '',
      'weight': 80.0,
      'muscleGroup': 'chest',
      'equipment': 'barbell',
      'movementPattern': 'Spinta',
      'technique': 'none',
    });

    expect(restored.catalogId, isNull);
    expect(restored.name, 'Panca');
  });
}
