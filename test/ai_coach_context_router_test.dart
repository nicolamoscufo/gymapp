import 'package:flutter_test/flutter_test.dart';
import 'package:gymapp/ai_coach/ai_coach_context_router.dart';

void main() {
  const router = AiCoachContextRouter();

  test('classifies common coaching intents deterministically', () {
    expect(
      router.classify('Come posso migliorare la tecnica in panca?'),
      AiCoachChatIntent.technique,
    );
    expect(
      router.classify('Sto stallando: aumento il peso o le reps?'),
      AiCoachChatIntent.progression,
    );
    expect(
      router.classify('Ho dormito poco, come gestisco il recupero?'),
      AiCoachChatIntent.recovery,
    );
    expect(
      router.classify('Come sono andati i miei progressi nell ultimo mese?'),
      AiCoachChatIntent.progress,
    );
    expect(
      router.classify('Come cambieresti la mia scheda upper lower?'),
      AiCoachChatIntent.program,
    );
  });

  test('technique route drops unrelated recovery and program-history payloads', () {
    final routed = router.route(
      _context(),
      intent: AiCoachChatIntent.technique,
      keepProgramHistory: false,
    );

    expect(routed['body_logs'], isEmpty);
    expect(routed.containsKey('program_history'), isFalse);
    expect(routed.containsKey('program_change_effectiveness'), isFalse);
    final analytics = routed['deterministic_analytics'] as Map;
    expect(analytics.containsKey('exercise_progress'), isTrue);
    expect(analytics.containsKey('fatigue_readiness'), isFalse);
  });

  test('recovery route keeps readiness and removes unrelated analytics', () {
    final routed = router.route(
      _context(),
      intent: AiCoachChatIntent.recovery,
      keepProgramHistory: false,
    );

    final analytics = routed['deterministic_analytics'] as Map;
    expect(analytics.containsKey('fatigue_readiness'), isTrue);
    expect(analytics.containsKey('exercise_progress'), isFalse);
    expect((routed['active_plans'] as List), hasLength(1));
  });

  test('program route can preserve verified longitudinal context', () {
    final routed = router.route(
      _context(),
      intent: AiCoachChatIntent.program,
      keepProgramHistory: true,
    );

    expect(routed.containsKey('program_history'), isTrue);
    expect(routed.containsKey('program_change_effectiveness'), isTrue);
  });
}

Map<String, dynamic> _context() => {
  'user_profile': {'primary_goal': 'massa'},
  'memory': {'recurring_preferences': ['manubri']},
  'workouts': [1, 2, 3, 4, 5],
  'body_logs': [1, 2, 3, 4, 5, 6, 7, 8, 9],
  'notes': List.generate(10, (i) => 'note-$i'),
  'active_plans': [
    {'id': 'a'},
    {'id': 'b'},
    {'id': 'c'},
  ],
  'program_history': {'items': [1]},
  'program_change_effectiveness': {'items': [1]},
  'metrics': {'sessions': 5},
  'deterministic_analytics': {
    'progress_analytics': {'trend': 'up'},
    'exercise_progress': {'bench': 'up'},
    'fatigue_readiness': {'status': 'ready'},
    'progression_recommendations': {'bench': '+2.5'},
    'session_count': 5,
    'latest_session_at': '2026-09-01T10:00:00.000',
  },
};
