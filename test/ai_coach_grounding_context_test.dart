import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gymapp/ai_coach/ai_coach_context_budget.dart';
import 'package:gymapp/ai_coach/ai_coach_generation_profile.dart';

void main() {
  group('AI Coach grounding context', () {
    test('keeps the active program under severe context pressure', () {
      final source = _largeGroundedContext();

      final encoded = AiCoachContextBudget.encode(
        source,
        charBudget: 7000,
        keepProgramHistory: false,
      );

      // The public service still asks for a 7000-char budget, but the encoder
      // must enforce a substantially smaller model-safe payload for Gemma's
      // 4096-token total context window.
      expect(encoded.length, lessThanOrEqualTo(3600));

      final decoded = jsonDecode(encoded) as Map<String, dynamic>;
      final plans = decoded['active_plans'] as List? ?? const <dynamic>[];
      expect(plans, isNotEmpty);
      expect((plans.first as Map)['title'], 'Petto');

      final exercises = (plans.first as Map)['exercises'] as List? ?? const [];
      expect(exercises, isNotEmpty);
      expect((exercises.first as Map)['name'], 'Panca piana');
    });

    test('exposes exactly what survived the context budget', () {
      final encoded = AiCoachContextBudget.encode(
        _largeGroundedContext(),
        charBudget: 7000,
        keepProgramHistory: false,
      );
      final diagnostics = AiCoachContextBudget.lastDiagnostics;

      expect(diagnostics, isNotNull);
      expect(diagnostics!.encodedChars, encoded.length);
      expect(diagnostics.budgetChars, 3600);
      expect(diagnostics.activePlanCount, greaterThan(0));
      expect(diagnostics.planTitles, contains('Petto'));
      expect(diagnostics.exerciseNames, contains('Panca piana'));
      expect(diagnostics.topLevelKeys, contains('active_plans'));
    });

    test('drops bulky catalog metadata before dropping the user plan', () {
      final source = <String, dynamic>{
        'generated_at': '2026-09-05T19:00:00.000',
        'active_plans': [_chestPlan()],
        'exercise_catalog': {
          'items': List.generate(
            50,
            (index) => {
              'name': 'Catalog exercise $index',
              'instructions': _repeat('catalog metadata ', 40),
            },
          ),
        },
      };

      final encoded = AiCoachContextBudget.encode(
        source,
        charBudget: 1800,
        keepProgramHistory: false,
      );
      final decoded = jsonDecode(encoded) as Map<String, dynamic>;

      expect(encoded.length, lessThanOrEqualTo(1800));
      expect(decoded.containsKey('exercise_catalog'), isFalse);
      final plans = decoded['active_plans'] as List? ?? const <dynamic>[];
      expect(plans, isNotEmpty);
      expect((plans.first as Map)['title'], 'Petto');
    });

    test('generation profiles do not reserve a quarter of the KV cache', () {
      expect(AiCoachGenerationProfiles.chat.tokenBuffer, 256);
      expect(AiCoachGenerationProfiles.structuredReport.tokenBuffer, 256);
      expect(AiCoachGenerationProfiles.visionStructured.tokenBuffer, 256);
      expect(AiCoachGenerationProfiles.programBuilder.tokenBuffer, 384);

      expect(AiCoachGenerationProfiles.chat.maxOutputTokens, 512);
      expect(AiCoachGenerationProfiles.programBuilder.maxOutputTokens, 1024);
    });
  });
}

Map<String, dynamic> _largeGroundedContext() {
  return <String, dynamic>{
    'generated_at': '2026-09-05T19:00:00.000',
    'user_profile': {
      'goal': 'ipertrofia',
      'notes': _repeat('profilo utente ', 30),
    },
    'memory': {
      'preferences': [_repeat('preferenza ', 40)],
      'constraints': [_repeat('vincolo ', 30)],
    },
    'active_plans': [_chestPlan()],
    'workouts': List.generate(
      12,
      (sessionIndex) => {
        'id': 'session-$sessionIndex',
        'name': 'Sessione $sessionIndex',
        'notes': _repeat('nota allenamento ', 50),
        'exercises': List.generate(
          8,
          (exerciseIndex) => {
            'name': 'Exercise $exerciseIndex',
            'sets': List.generate(
              5,
              (setIndex) => {
                'weight': 80 + setIndex,
                'reps': 8,
                'completed': true,
                'notes': _repeat('set note ', 20),
              },
            ),
          },
        ),
      },
    ),
    'body_logs': List.generate(
      10,
      (index) => {
        'bodyWeight': 78.0 + (index / 10),
        'notes': _repeat('body note ', 30),
      },
    ),
    'notes': List.generate(20, (index) => _repeat('training note $index ', 25)),
    'deterministic_analytics': {
      'progress_analytics': {'summary': _repeat('analytics ', 80)},
      'exercise_progress': {
        for (var index = 0; index < 20; index++)
          'Exercise $index': List.generate(
            8,
            (entry) => {
              'date': '2026-08-${entry + 1}',
              'estimated_1rm': 100 + entry,
            },
          ),
      },
      'progression_recommendations': List.generate(
        20,
        (index) => {
          'exercise': 'Exercise $index',
          'reason': _repeat('progression evidence ', 30),
        },
      ),
    },
    'verified_evidence': {
      'source': 'deterministic_analytics',
      'contract': {'derived_values_authoritative': true},
      'coverage': {'sessions': 12},
      'strength': {
        'exercises': List.generate(
          15,
          (index) => {'exercise': 'Exercise $index', 'e1rm': 100 + index},
        ),
        'recent_prs': List.generate(
          15,
          (index) => {'exercise': 'Exercise $index', 'value': 100 + index},
        ),
      },
      'volume_frequency': {
        'muscles': List.generate(
          15,
          (index) => {'muscle': 'Group $index', 'volume': index * 1000},
        ),
      },
      'progression': {
        'recommendations': List.generate(
          15,
          (index) => {
            'exercise': 'Exercise $index',
            'reason': _repeat('verified progression ', 15),
          },
        ),
      },
    },
    'exercise_catalog': {
      'items': List.generate(
        40,
        (index) => {
          'name': 'Catalog $index',
          'instructions': _repeat('catalog instructions ', 35),
        },
      ),
    },
  };
}

Map<String, dynamic> _chestPlan() {
  return <String, dynamic>{
    'id': 'schedule-chest',
    'title': 'Petto',
    'week': 1,
    'goal': 'Ipertrofia',
    'programBlock': 'Mesociclo A',
    'cycleNumber': 1,
    'currentVersionId': 'version-1',
    'currentVersionNumber': 1,
    'exercises': [
      {
        'id': 'bench',
        'name': 'Panca piana',
        'set': 4,
        'reps': 8,
        'weight': 80.0,
        'targetMinReps': 6,
        'targetMaxReps': 8,
        'restSeconds': 180,
        'progressionScheme': 'doubleProgression',
      },
      for (var index = 0; index < 14; index++)
        {
          'id': 'chest-$index',
          'name': 'Petto exercise $index',
          'set': 3,
          'reps': 10,
          'weight': 30.0 + index,
          'targetMinReps': 8,
          'targetMaxReps': 12,
          'restSeconds': 120,
          'progressionScheme': 'doubleProgression',
        },
    ],
  };
}

String _repeat(String value, int times) => List.filled(times, value).join();
