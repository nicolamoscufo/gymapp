import 'package:flutter_test/flutter_test.dart';
import 'package:gymapp/ai_coach/ai_coach_models.dart';
import 'package:gymapp/ai_coach/ai_plan_action_service.dart';
import 'package:gymapp/models/exercise.dart';
import 'package:gymapp/models/schedule.dart';

void main() {
  test('validates and applies id-bound AI plan actions', () {
    final exercise = Exercise(
      id: 'bench',
      name: 'Panca',
      reps: 8,
      set: 3,
      notes: '',
      weight: 80,
      technique: IntensityTechnique.none,
    );
    final schedule = Schedule(
      id: 'push',
      title: 'Push',
      week: 1,
      createdAt: DateTime(2026, 8, 1),
      exercises: [exercise],
    );
    const report = SuggestedAdjustmentReport(
      suggestions: [
        SuggestedAdjustment(
          type: 'load_progression',
          target: 'Panca',
          suggestion: 'Aumenta il carico',
          reason: 'Progressione deterministica positiva',
          evidence: ['RIR stabile'],
          confidence: 'high',
          requiresUserConfirmation: true,
          proposedActions: [
            ProposedPlanAction(
              action: 'increase_load',
              target: 'Panca',
              field: 'weight',
              currentValue: '999',
              suggestedValue: '82.5',
              rationale: 'Piccolo incremento',
              scheduleId: 'push',
              exerciseId: 'bench',
            ),
          ],
        ),
      ],
    );

    const service = AiPlanActionService();
    final actions = service.validate(report, [schedule]);
    expect(actions, hasLength(1));
    expect(actions.single.currentValue, '80');
    expect(actions.single.suggestedValue, '82.5');

    final result = service.apply([schedule], actions);
    expect(result.applied, 1);
    expect(exercise.weight, 82.5);
  });

  test('rejects ambiguous name-only and unsafe actions', () {
    final schedules = [
      for (final id in ['a', 'b'])
        Schedule(
          id: id,
          title: id,
          week: 1,
          createdAt: DateTime(2026, 8, 1),
          exercises: [
            Exercise(
              name: 'Panca',
              reps: 8,
              set: 3,
              notes: '',
              weight: 80,
              technique: IntensityTechnique.none,
            ),
          ],
        ),
    ];
    const report = SuggestedAdjustmentReport(
      suggestions: [
        SuggestedAdjustment(
          type: 'load_progression',
          target: 'Panca',
          suggestion: '',
          reason: '',
          evidence: [],
          confidence: 'low',
          requiresUserConfirmation: true,
          proposedActions: [
            ProposedPlanAction(
              action: 'increase_load',
              target: 'Panca',
              field: 'weight',
              currentValue: '80',
              suggestedValue: '5000',
              rationale: '',
            ),
          ],
        ),
      ],
    );
    expect(const AiPlanActionService().validate(report, schedules), isEmpty);
  });

  test('stale diff is skipped instead of overwriting a newer edit', () {
    final exercise = Exercise(
      id: 'bench',
      name: 'Panca',
      reps: 8,
      set: 3,
      notes: '',
      weight: 80,
      technique: IntensityTechnique.none,
    );
    final schedule = Schedule(
      id: 'push',
      title: 'Push',
      week: 1,
      createdAt: DateTime(2026, 8, 1),
      exercises: [exercise],
    );
    const report = SuggestedAdjustmentReport(
      suggestions: [
        SuggestedAdjustment(
          type: 'load_progression',
          target: 'Panca',
          suggestion: '',
          reason: '',
          evidence: [],
          confidence: 'medium',
          requiresUserConfirmation: true,
          proposedActions: [
            ProposedPlanAction(
              action: 'increase_load',
              target: 'Panca',
              field: 'weight',
              currentValue: '80',
              suggestedValue: '82.5',
              rationale: '',
              scheduleId: 'push',
              exerciseId: 'bench',
            ),
          ],
        ),
      ],
    );
    const service = AiPlanActionService();
    final actions = service.validate(report, [schedule]);
    exercise.weight = 81;
    final result = service.apply([schedule], actions);
    expect(result.applied, 0);
    expect(result.skipped, 1);
    expect(exercise.weight, 81);
  });
}
