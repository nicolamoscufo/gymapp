import 'package:flutter_test/flutter_test.dart';
import 'package:gymapp/ai_coach/ai_coach_context_router.dart';
import 'package:gymapp/ai_coach/ai_coach_exercise_context.dart';

void main() {
  const resolver = AiCoachExerciseContextResolver();
  const filter = AiCoachExerciseContextFilter();

  group('exercise focus resolver', () {
    test('resolves a specific exercise mention deterministically', () {
      final focus = resolver.resolve(
        query: 'Come sto andando sulla panca piana?',
        candidates: const [
          AiCoachExerciseCandidate(
            name: 'Panca piana',
            sourceExerciseId: 'bench-flat',
            catalogId: 'bench-flat-catalog',
          ),
          AiCoachExerciseCandidate(
            name: 'Panca inclinata manubri',
            sourceExerciseId: 'bench-incline',
            catalogId: 'bench-incline-catalog',
          ),
        ],
      );

      expect(focus, isNotNull);
      expect(focus!.primaryName, 'Panca piana');
      expect(focus.sourceExerciseIds, contains('bench-flat'));
      expect(focus.catalogIds, contains('bench-flat-catalog'));
      expect(focus.matchedTerms, containsAll(['bench', 'flat']));
    });

    test('generic family mention stays broad when multiple exercises match', () {
      final focus = resolver.resolve(
        query: 'Come sta andando la panca?',
        candidates: const [
          AiCoachExerciseCandidate(name: 'Panca piana'),
          AiCoachExerciseCandidate(name: 'Panca inclinata manubri'),
        ],
      );

      expect(focus, isNull);
    });

    test('single strong English alias can resolve an Italian exercise', () {
      final focus = resolver.resolve(
        query: 'How is my bench going?',
        candidates: const [
          AiCoachExerciseCandidate(name: 'Panca piana'),
          AiCoachExerciseCandidate(name: 'Squat'),
        ],
      );

      expect(focus, isNotNull);
      expect(focus!.primaryName, 'Panca piana');
    });

    test('muscle-group question never narrows to one exercise', () {
      final focus = resolver.resolve(
        query: 'Come stanno andando i progressi del petto?',
        candidates: const [
          AiCoachExerciseCandidate(name: 'Chest Press'),
          AiCoachExerciseCandidate(name: 'Cable Fly'),
        ],
      );

      expect(focus, isNull);
    });

    test('equipment disambiguates two exercises from the same family', () {
      final focus = resolver.resolve(
        query: 'Come va la bench press con bilanciere?',
        candidates: const [
          AiCoachExerciseCandidate(name: 'Barbell Bench Press'),
          AiCoachExerciseCandidate(name: 'Dumbbell Bench Press'),
        ],
      );

      expect(focus, isNotNull);
      expect(focus!.primaryName, 'Barbell Bench Press');
      expect(focus.matchedTerms, contains('barbell'));
    });
  });

  group('exercise context filter', () {
    const focus = AiCoachExerciseFocus(
      names: ['Panca piana'],
      sourceExerciseIds: {'bench-flat'},
      catalogIds: {'bench-flat-catalog'},
      matchedTerms: ['bench', 'flat'],
    );

    test('keeps only relevant workout evidence and per-exercise analytics', () {
      final context = <String, dynamic>{
        'workouts': [
          {
            'id': 'w1',
            'exercises': [
              {
                'source_exercise_id': 'bench-flat',
                'catalog_id': 'bench-flat-catalog',
                'name': 'Panca piana',
                'sets': [
                  {'weight': 80, 'reps': 8, 'completed': true},
                ],
              },
              {
                'source_exercise_id': 'squat',
                'catalog_id': 'squat-catalog',
                'name': 'Squat',
                'sets': [
                  {'weight': 120, 'reps': 5, 'completed': true},
                ],
              },
            ],
          },
          {
            'id': 'w2',
            'exercises': [
              {'source_exercise_id': 'row', 'name': 'Rematore'},
            ],
          },
        ],
        'active_plans': [
          {
            'title': 'Upper',
            'exercises': [
              {
                'id': 'bench-flat',
                'catalogId': 'bench-flat-catalog',
                'name': 'Panca piana',
              },
              {'id': 'row', 'name': 'Rematore'},
            ],
          },
        ],
        'notes': ['Panca piana: buona pausa', 'Squat: stance stretta'],
        'metrics': {
          'sessions': 2,
          'total_volume': 9999,
          'exercise_volume': {'Panca piana': 3200, 'Squat': 4800},
          'muscle_group_volume': {'chest': 3200, 'quadriceps': 4800},
        },
        'deterministic_analytics': {
          'exercise_progress': {
            'Panca piana': [
              {'best_weight': 80},
            ],
            'Squat': [
              {'best_weight': 120},
            ],
          },
          'progression_recommendations': [
            {'exercise': 'Panca piana', 'action': 'hold'},
            {'exercise': 'Squat', 'action': 'increase'},
          ],
          'progress_analytics': {
            'exercises': [
              {'exercise': 'Panca piana', 'best_weight': 80},
              {'exercise': 'Squat', 'best_weight': 120},
            ],
            'personal_records': [
              {'exercise': 'Panca piana', 'kind': 'weight'},
              {'exercise': 'Squat', 'kind': 'weight'},
            ],
            'consistency': {'workouts_30d': 8},
          },
          'fatigue_readiness': {'score': 80},
        },
        'exercise_catalog': {
          'result_count': 2,
          'matches': [
            {'catalog_id': 'bench-flat-catalog', 'name': 'Panca piana'},
            {'catalog_id': 'bench-incline-catalog', 'name': 'Incline press'},
          ],
        },
      };

      final result = filter.apply(
        context,
        focus: focus,
        intent: AiCoachChatIntent.progress,
      );

      final workouts = result['workouts'] as List;
      expect(workouts, hasLength(1));
      final workout = workouts.single as Map;
      final workoutExercises = workout['exercises'] as List;
      expect(workoutExercises, hasLength(1));
      expect((workoutExercises.single as Map)['name'], 'Panca piana');

      final plans = result['active_plans'] as List;
      expect(plans, hasLength(1));
      expect(((plans.single as Map)['exercises'] as List), hasLength(1));
      expect(result['notes'], ['Panca piana: buona pausa']);

      final metrics = result['metrics'] as Map;
      expect(metrics['sessions_containing_exercise'], 1);
      expect(metrics.containsKey('total_volume'), isFalse);
      expect((metrics['exercise_volume'] as Map).keys, ['Panca piana']);

      final analytics = result['deterministic_analytics'] as Map;
      expect((analytics['exercise_progress'] as Map).keys, ['Panca piana']);
      expect(
        (analytics['progression_recommendations'] as List),
        hasLength(1),
      );
      final progress = analytics['progress_analytics'] as Map;
      expect(progress.containsKey('consistency'), isFalse);
      expect(progress['exercises'], hasLength(1));
      expect(progress['personal_records'], hasLength(1));
      expect(analytics['fatigue_readiness'], {'score': 80});

      final catalog = result['exercise_catalog'] as Map;
      expect(catalog['result_count'], 1);
      expect(catalog['matches'], hasLength(1));
      expect(result['exercise_focus'], isA<Map<String, dynamic>>());
    });

    test('program questions retain the complete active plan for trade-offs', () {
      final context = <String, dynamic>{
        'workouts': const [],
        'active_plans': [
          {
            'title': 'Upper',
            'exercises': [
              {'id': 'bench-flat', 'name': 'Panca piana'},
              {'id': 'row', 'name': 'Rematore'},
            ],
          },
        ],
      };

      final result = filter.apply(
        context,
        focus: focus,
        intent: AiCoachChatIntent.program,
      );

      final exercises = ((result['active_plans'] as List).single as Map)['exercises']
          as List;
      expect(exercises, hasLength(2));
      expect(result['exercise_focus'], isNotNull);
    });
  });
}
