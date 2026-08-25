import 'package:flutter_test/flutter_test.dart';
import 'package:gymapp/models/body_log.dart';
import 'package:gymapp/models/exercise.dart';
import 'package:gymapp/models/workout.dart';
import 'package:gymapp/workout_fatigue_analytics.dart';
import 'package:gymapp/workout_progression_analytics.dart';

WorkoutExercise _exercise({
  required String name,
  required MuscleGroup muscle,
  required double weight,
  required int reps,
  int? rir,
  double? rpe,
}) {
  return WorkoutExercise(
    name: name,
    notes: '',
    muscleGroup: muscle,
    targetMinReps: 6,
    targetMaxReps: 8,
    technique: IntensityTechnique.none,
    sets: [
      ExerciseSet(
        weight: weight,
        reps: reps,
        isCompleted: true,
        rir: rir,
        rpe: rpe,
      ),
      ExerciseSet(
        weight: weight,
        reps: reps,
        isCompleted: true,
        rir: rir,
        rpe: rpe,
      ),
    ],
  );
}

WorkoutSession _session(DateTime end, WorkoutExercise exercise, {String? id}) {
  return WorkoutSession(
    id: id,
    scheduleTitle: 'Test',
    startTime: end.subtract(const Duration(hours: 1)),
    endTime: end,
    exercises: [exercise],
  );
}

void main() {
  group('fatigue readiness', () {
    test('high readiness and long recovery produce ready/fresh score', () {
      final now = DateTime(2026, 8, 25, 18);
      final report = buildExerciseReadinessReport(
        history: [
          _session(
            now.subtract(const Duration(days: 4)),
            _exercise(
              name: 'Panca',
              muscle: MuscleGroup.chest,
              weight: 100,
              reps: 8,
              rir: 3,
            ),
          ),
        ],
        bodyLogs: [
          BodyLog(
            date: now.subtract(const Duration(hours: 8)),
            readiness: 9,
            sleepHours: 8,
          ),
        ],
        exerciseName: 'Panca',
        muscleGroup: MuscleGroup.chest,
        now: now,
      );

      expect(report.score, greaterThanOrEqualTo(70));
      expect(
        report.status,
        anyOf(ReadinessStatus.ready, ReadinessStatus.fresh),
      );
      expect(report.recommendedLoadMultiplier, 1.0);
    });

    test('short recovery, failure effort and poor sleep flag recovery', () {
      final now = DateTime(2026, 8, 25, 18);
      final history = <WorkoutSession>[];
      for (var i = 1; i <= 5; i++) {
        history.add(
          _session(
            now.subtract(Duration(hours: i * 12)),
            _exercise(
              name: 'Squat',
              muscle: MuscleGroup.quadriceps,
              weight: 140,
              reps: 5,
              rir: 0,
              rpe: 10,
            ),
          ),
        );
      }

      final report = buildExerciseReadinessReport(
        history: history,
        bodyLogs: [
          BodyLog(
            date: now.subtract(const Duration(hours: 4)),
            readiness: 2,
            sleepHours: 4,
          ),
        ],
        exerciseName: 'Squat',
        muscleGroup: MuscleGroup.quadriceps,
        now: now,
      );

      expect(report.score, lessThan(40));
      expect(report.status, ReadinessStatus.recovery);
      expect(report.adaptation, SessionAdaptation.reduceVolumeAndIntensity);
      expect(report.recommendedLoadMultiplier, 0.90);
      expect(report.recommendedSetReduction, 1);
    });

    test('readiness gates unsafe load progression', () {
      const baseDecision = ProgressionDecision(
        action: ProgressionAction.increaseLoad,
        confidence: ProgressionConfidence.high,
        reasons: ['Range completato.'],
        suggestedWeightDelta: 2.5,
        suggestedRepDelta: null,
        suggestedWeightMultiplier: null,
        currentEstimatedOneRepMax: 120,
        estimatedOneRepMaxChangePercent: 1,
        volumeChangePercent: 3,
        effectiveRir: 2,
        completedWorkSets: 3,
        plannedWorkSets: 3,
        allWorkSetsCompleted: true,
        allAtTop: true,
        anyBelowMin: false,
      );
      const readiness = FatigueReadinessReport(
        score: 50,
        status: ReadinessStatus.fatigued,
        adaptation: SessionAdaptation.reduceIntensity,
        reasons: ['Fatica elevata.'],
        sessionsLast7Days: 4,
        hoursSinceLastStimulus: 24,
        averageRir: 1,
        averageRpe: 9,
        acuteVolumeRatio: 1.3,
        estimatedOneRepMaxTrendPercent: -2,
        selfReadiness: 5,
        sleepHours: 6,
        recommendedLoadMultiplier: 0.95,
        recommendedSetReduction: 1,
      );

      final gated = applyReadinessToProgression(
        decision: baseDecision,
        readiness: readiness,
      );

      expect(gated.action, ProgressionAction.maintain);
      expect(gated.suggestedWeightDelta, isNull);
      expect(gated.reasons.last, contains('Fatica'));
    });

    test('recovery state converts automatic progression into deload', () {
      const baseDecision = ProgressionDecision(
        action: ProgressionAction.increaseReps,
        confidence: ProgressionConfidence.high,
        reasons: ['Dentro il range.'],
        suggestedWeightDelta: null,
        suggestedRepDelta: 1,
        suggestedWeightMultiplier: null,
        currentEstimatedOneRepMax: 120,
        estimatedOneRepMaxChangePercent: -1,
        volumeChangePercent: 1,
        effectiveRir: 2,
        completedWorkSets: 3,
        plannedWorkSets: 3,
        allWorkSetsCompleted: true,
        allAtTop: false,
        anyBelowMin: false,
      );
      const readiness = FatigueReadinessReport(
        score: 30,
        status: ReadinessStatus.recovery,
        adaptation: SessionAdaptation.reduceVolumeAndIntensity,
        reasons: ['Recupero prioritario.'],
        sessionsLast7Days: 5,
        hoursSinceLastStimulus: 12,
        averageRir: 0.5,
        averageRpe: 9.5,
        acuteVolumeRatio: 1.8,
        estimatedOneRepMaxTrendPercent: -6,
        selfReadiness: 3,
        sleepHours: 5,
        recommendedLoadMultiplier: 0.90,
        recommendedSetReduction: 1,
      );

      final gated = applyReadinessToProgression(
        decision: baseDecision,
        readiness: readiness,
      );

      expect(gated.action, ProgressionAction.deload);
      expect(gated.suggestedWeightMultiplier, 0.90);
    });
  });
}
