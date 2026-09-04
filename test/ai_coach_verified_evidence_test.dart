import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gymapp/ai_coach/ai_coach_context_budget.dart';
import 'package:gymapp/ai_coach/ai_coach_context_router.dart';
import 'package:gymapp/ai_coach/ai_coach_exercise_context.dart';
import 'package:gymapp/ai_coach/ai_coach_verified_evidence.dart';

void main() {
  const builder = AiCoachVerifiedEvidenceBuilder();

  test(
    'verified evidence preserves deterministic values without recalculation',
    () {
      final evidence = builder.build(_context());

      expect(evidence['source'], 'deterministic_app_analytics');
      final contract = evidence['contract'] as Map;
      expect(contract['derived_values_authoritative'], isTrue);
      expect(contract['model_role'], 'interpret_only');

      final strength = evidence['strength'] as Map;
      final exercises = strength['exercises'] as List;
      final bench = exercises.first as Map;
      expect(bench['exercise'], 'Panca piana');
      expect(bench['latest_estimated_1rm'], 101.3);
      expect(bench['estimated_1rm_trend_percent'], 4.25);

      final volumeFrequency = evidence['volume_frequency'] as Map;
      final chest = (volumeFrequency['muscles'] as List).first as Map;
      expect(chest['sets_7d'], 9);
      expect(chest['volume_30d'], 12400.0);
      expect(
        (volumeFrequency['consistency'] as Map)['average_workouts_per_week_8w'],
        4.0,
      );

      final progression = evidence['progression'] as Map;
      final recommendation =
          (progression['recommendations'] as List).first as Map;
      expect(recommendation['action'], 'increaseLoad');
      expect(recommendation['suggested_weight_delta'], 2.5);

      final readiness = evidence['readiness'] as Map;
      expect(readiness['score'], 78);
      expect(readiness['status'], 'ready');
    },
  );

  test('intent routing keeps only the relevant verified evidence families', () {
    final source = <String, dynamic>{
      ..._context(),
      'verified_evidence': builder.build(_context()),
    };
    const router = AiCoachContextRouter();

    final progress = router.route(
      source,
      intent: AiCoachChatIntent.progress,
      keepProgramHistory: false,
    );
    final progressEvidence = progress['verified_evidence'] as Map;
    expect(progressEvidence, contains('strength'));
    expect(progressEvidence, contains('volume_frequency'));
    expect(progressEvidence, isNot(contains('progression')));
    expect(progressEvidence, isNot(contains('readiness')));
    expect(progressEvidence, contains('contract'));

    final recovery = router.route(
      source,
      intent: AiCoachChatIntent.recovery,
      keepProgramHistory: false,
    );
    final recoveryEvidence = recovery['verified_evidence'] as Map;
    expect(recoveryEvidence, contains('readiness'));
    expect(recoveryEvidence, contains('volume_frequency'));
    expect(recoveryEvidence, isNot(contains('strength')));
    expect(recoveryEvidence, isNot(contains('progression')));
  });

  test('exercise focus removes unrelated verified exercise evidence', () {
    final source = <String, dynamic>{
      ..._context(),
      'workouts': const [],
      'notes': const [],
      'active_plans': const [],
      'verified_evidence': builder.build(_context()),
    };
    const focus = AiCoachExerciseFocus(
      names: ['Panca piana'],
      sourceExerciseIds: {'bench-flat'},
      catalogIds: {'bench-catalog'},
      matchedTerms: ['bench', 'flat'],
    );

    final result = const AiCoachExerciseContextFilter().apply(
      source,
      focus: focus,
      intent: AiCoachChatIntent.progress,
    );
    final evidence = result['verified_evidence'] as Map;
    final strength = evidence['strength'] as Map;
    final exercises = strength['exercises'] as List;
    expect(exercises, hasLength(1));
    expect((exercises.single as Map)['exercise'], 'Panca piana');
    expect((strength['recent_prs'] as List), hasLength(1));

    final volume = evidence['volume_frequency'] as Map;
    final muscles = volume['muscles'] as List;
    expect(muscles, hasLength(1));
    expect((muscles.single as Map)['muscle_group'], 'chest');
  });

  test('context budget preserves verified evidence ahead of raw analytics', () {
    final context = <String, dynamic>{
      ..._context(),
      'verified_evidence': builder.build(_context()),
      'workouts': List.generate(
        8,
        (index) => {'id': 'w$index', 'notes': 'x' * 900},
      ),
      'notes': List.generate(20, (index) => 'note-$index-${'y' * 200}'),
      'active_plans': List.generate(
        3,
        (index) => {'id': 'p$index', 'title': 'Plan $index'},
      ),
    };

    final encoded = AiCoachContextBudget.encode(
      context,
      charBudget: 2600,
      keepProgramHistory: false,
    );
    final decoded = jsonDecode(encoded) as Map<String, dynamic>;

    expect(decoded, contains('verified_evidence'));
    final evidence = decoded['verified_evidence'] as Map;
    expect(evidence['source'], 'deterministic_app_analytics');
    expect(evidence, contains('contract'));
  });
}

Map<String, dynamic> _context() => {
  'metrics': {'sessions': 8, 'total_volume': 18320.0},
  'deterministic_analytics': {
    'session_count': 8,
    'latest_session_at': '2026-09-04T18:00:00.000',
    'progress_analytics': {
      'exercises': [
        {
          'exercise': 'Panca piana',
          'muscle_group': 'chest',
          'sessions': 6,
          'completed_sets': 18,
          'total_reps': 142,
          'total_volume': 9680.0,
          'best_weight': 85.0,
          'best_reps': 10,
          'best_estimated_1rm': 104.0,
          'latest_estimated_1rm': 101.3,
          'estimated_1rm_trend_percent': 4.25,
          'last_trained_at': '2026-09-04T18:00:00.000',
          'timeline': [
            {'volume': 3200.0},
          ],
        },
        {
          'exercise': 'Squat',
          'muscle_group': 'quadriceps',
          'sessions': 4,
          'completed_sets': 12,
          'total_reps': 72,
          'total_volume': 13200.0,
          'best_weight': 130.0,
          'best_reps': 6,
          'best_estimated_1rm': 151.0,
          'latest_estimated_1rm': 148.0,
          'estimated_1rm_trend_percent': -1.2,
          'last_trained_at': '2026-09-03T18:00:00.000',
        },
      ],
      'personal_records': [
        {
          'exercise': 'Panca piana',
          'muscle_group': 'chest',
          'kind': 'estimatedOneRepMax',
          'date': '2026-09-04T18:00:00.000',
          'value': 104.0,
          'weight': 85.0,
          'reps': 7,
        },
        {
          'exercise': 'Squat',
          'muscle_group': 'quadriceps',
          'kind': 'weight',
          'date': '2026-09-03T18:00:00.000',
          'value': 130.0,
          'weight': 130.0,
          'reps': 5,
        },
      ],
      'muscles': [
        {
          'muscle_group': 'chest',
          'sets_7d': 9,
          'sets_30d': 34,
          'volume_7d': 3600.0,
          'volume_30d': 12400.0,
          'sessions_30d': 8,
          'set_share_30d': 0.24,
          'weekly': [],
        },
        {
          'muscle_group': 'quadriceps',
          'sets_7d': 6,
          'sets_30d': 24,
          'volume_7d': 5100.0,
          'volume_30d': 19800.0,
          'sessions_30d': 6,
          'set_share_30d': 0.18,
          'weekly': [],
        },
      ],
      'consistency': {
        'workouts_30d': 17,
        'trained_days_30d': 16,
        'current_active_week_streak': 7,
        'longest_active_week_streak': 11,
        'average_workouts_per_week_8w': 4.0,
        'most_active_weekday': 'Monday',
      },
    },
    'progression_recommendations': [
      {
        'exercise': 'Panca piana',
        'action': 'increaseLoad',
        'confidence': 'high',
        'reasons': ['Top range completed with reserve.'],
        'suggested_weight_delta': 2.5,
        'suggested_rep_delta': null,
        'current_estimated_1rm': 101.3,
        'estimated_1rm_change_percent': 4.25,
        'volume_change_percent': 3.0,
        'effective_rir': 2.0,
        'completed_work_sets': 3,
        'planned_work_sets': 3,
        'all_work_sets_completed': true,
        'readiness': {
          'score': 82,
          'status': 'ready',
          'adaptation': 'normal',
          'recommended_load_multiplier': 1.0,
          'recommended_set_reduction': 0,
        },
      },
      {
        'exercise': 'Squat',
        'action': 'maintain',
        'confidence': 'medium',
        'reasons': ['Recent performance is stable.'],
      },
    ],
    'fatigue_readiness': {
      'score': 78,
      'status': 'ready',
      'adaptation': 'normal',
      'reasons': ['Recovery adequate.'],
      'sessions_last_7_days': 4,
      'hours_since_last_stimulus': 48,
      'average_rir': 2.1,
      'average_rpe': 7.9,
      'acute_volume_ratio': 1.0,
      'estimated_1rm_trend_percent': 2.2,
      'self_readiness': 8,
      'sleep_hours': 8,
      'recommended_load_multiplier': 1.0,
      'recommended_set_reduction': 0,
    },
  },
};
