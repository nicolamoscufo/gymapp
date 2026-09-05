import 'package:flutter_test/flutter_test.dart';
import 'package:gymapp/ai_coach/ai_coach_context_capsule.dart';
import 'package:gymapp/ai_coach/ai_coach_context_router.dart';

void main() {
  group('AiCoachContextCapsuleBuilder', () {
    test('compresses a plan into dense human-readable training facts', () {
      final capsule = const AiCoachContextCapsuleBuilder().build(
        context: {
          'active_plans': [
            {
              'title': 'Petto',
              'week': 3,
              'goal': 'Ipertrofia',
              'exercises': [
                {
                  'name': 'Panca piana',
                  'set': 4,
                  'weight': 80.0,
                  'targetMinReps': 6,
                  'targetMaxReps': 8,
                  'restSeconds': 180,
                },
              ],
            },
          ],
        },
        intent: AiCoachChatIntent.program,
        charBudget: 900,
      );

      expect(capsule.length, lessThanOrEqualTo(900));
      expect(capsule, contains('USER_DATA_AVAILABLE=true'));
      expect(capsule, contains('PLAN Petto'));
      expect(capsule, contains('goal=Ipertrofia'));
      expect(capsule, contains('EX Panca piana'));
      expect(capsule, contains('sets=4'));
      expect(capsule, contains('reps=6-8'));
      expect(capsule, contains('kg=80.0'));
      expect(capsule, contains('rest=180s'));
    });

    test('progression mode prioritizes verified facts before raw sessions', () {
      final capsule = const AiCoachContextCapsuleBuilder().build(
        context: {
          'verified_evidence': {
            'coverage': {'sessions': 6},
            'progression': {
              'recommendations': [
                {'exercise': 'Panca', 'decision': 'increase_load'},
              ],
            },
          },
          'workouts': [
            {
              'name': 'Push',
              'start_time': '2026-09-04T18:00:00',
              'exercises': [
                {
                  'name': 'Panca',
                  'sets': [
                    {
                      'weight': 80,
                      'reps': 8,
                      'completed': true,
                      'warmup': false,
                      'rir': 2,
                    },
                  ],
                },
              ],
            },
          ],
        },
        intent: AiCoachChatIntent.progression,
        charBudget: 1200,
      );

      final factIndex = capsule.indexOf('FACT progression=');
      final sessionIndex = capsule.indexOf('SESSION 2026-09-04 Push');
      expect(factIndex, greaterThanOrEqualTo(0));
      expect(sessionIndex, greaterThan(factIndex));
      expect(capsule, contains('DO Panca: 80x8@RIR2'));
    });

    test('catalog-only context is reference data, not user training history', () {
      final capsule = const AiCoachContextCapsuleBuilder().build(
        context: {
          'exercise_catalog': {
            'matches': [
              {
                'catalog_id': 'cable_fly',
                'name': 'cable standing fly',
                'target': 'pectorals',
                'equipment': 'cable',
                'instructions': [
                  'Set the pulleys.',
                  'Bring the handles together.',
                ],
              },
            ],
          },
        },
        intent: AiCoachChatIntent.technique,
        charBudget: 1000,
      );

      expect(capsule, contains('USER_DATA_AVAILABLE=false'));
      expect(capsule, contains('REFERENCE_DATA_AVAILABLE=true'));
      expect(capsule, contains('CAT cable_fly'));
      expect(capsule, contains('Bring the handles together.'));
    });

    test('hard budget never expands to fit verbose notes', () {
      final capsule = const AiCoachContextCapsuleBuilder().build(
        context: {
          'memory': {
            'notes': List.filled(200, 'nota molto lunga').join(' '),
          },
          'active_plans': [
            {
              'title': 'Push',
              'exercises': [
                {'name': 'Panca', 'set': 4, 'reps': 8, 'weight': 80},
              ],
            },
          ],
        },
        intent: AiCoachChatIntent.general,
        charBudget: 420,
      );

      expect(capsule.length, lessThanOrEqualTo(420));
      expect(capsule, contains('PLAN Push'));
      expect(capsule, contains('EX Panca'));
    });
  });
}
