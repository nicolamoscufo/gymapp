import 'package:flutter_test/flutter_test.dart';
import 'package:gymapp/models/workout.dart';
import 'package:gymapp/workout_plate_calculator.dart';

void main() {
  group('workout set types', () {
    test('round-trips normal, warm-up, drop and failure types', () {
      for (final type in SetType.values) {
        final original = ExerciseSet(weight: 80, reps: 8, type: type);
        final restored = ExerciseSet.fromJson(original.toJson());
        expect(restored.type, type);
        expect(restored.isWarmup, type == SetType.warmup);
      }
    });

    test('loads legacy isWarmup backups', () {
      final restored = ExerciseSet.fromJson({
        'id': 'legacy',
        'weight': 40,
        'reps': 10,
        'isCompleted': false,
        'isWarmup': true,
      });
      expect(restored.type, SetType.warmup);
      expect(restored.isWarmup, isTrue);
    });
  });

  group('plate calculator', () {
    test('calculates plates per side for 100 kg on a 20 kg bar', () {
      final result = calculatePlatesPerSide(
        targetWeight: 100,
        barWeight: 20,
      );
      expect(result.platesPerSide, [20, 20]);
      expect(result.loadedWeight, 100);
      expect(result.remainder, closeTo(0, 0.001));
    });

    test('reports remainder when target cannot be loaded exactly', () {
      final result = calculatePlatesPerSide(
        targetWeight: 101,
        barWeight: 20,
      );
      expect(result.loadedWeight, 100);
      expect(result.remainder, closeTo(1, 0.001));
    });
  });
}
