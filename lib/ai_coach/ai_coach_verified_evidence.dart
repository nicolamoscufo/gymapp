class AiCoachVerifiedEvidenceBuilder {
  const AiCoachVerifiedEvidenceBuilder();

  Map<String, dynamic> build(Map<String, dynamic> context) {
    final deterministic = _map(context['deterministic_analytics']);
    final progress = _map(deterministic['progress_analytics']);
    final metrics = _map(context['metrics']);

    final exercises = _maps(
      progress['exercises'],
    ).map(_compactExercise).where((entry) => entry.isNotEmpty).toList();
    final personalRecords = _maps(progress['personal_records'])
        .take(12)
        .map(_compactPersonalRecord)
        .where((entry) => entry.isNotEmpty)
        .toList();
    final muscles = _maps(
      progress['muscles'],
    ).map(_compactMuscle).where((entry) => entry.isNotEmpty).toList();
    final consistency = _pick(_map(progress['consistency']), const [
      'workouts_30d',
      'trained_days_30d',
      'current_active_week_streak',
      'longest_active_week_streak',
      'average_workouts_per_week_8w',
      'most_active_weekday',
    ]);
    final progression = _maps(
      deterministic['progression_recommendations'],
    ).map(_compactProgression).where((entry) => entry.isNotEmpty).toList();
    final readiness = _compactReadiness(
      _map(deterministic['fatigue_readiness']),
    );

    final evidence = <String, dynamic>{
      'source': 'deterministic_app_analytics',
      'contract': const {
        'derived_values_authoritative': true,
        'model_role': 'interpret_only',
        'raw_sets_are_supporting_evidence_only': true,
        'must_not_recalculate': [
          'personal_records',
          'estimated_1rm',
          'estimated_1rm_trend',
          'training_volume',
          'training_frequency',
          'progression_decision',
          'fatigue_readiness',
        ],
      },
      'coverage': {
        'session_count': deterministic['session_count'] ?? metrics['sessions'],
        'latest_session_at': deterministic['latest_session_at'],
        'exercise_summaries': exercises.length,
        'recent_pr_events': personalRecords.length,
      },
    };

    if (exercises.isNotEmpty || personalRecords.isNotEmpty) {
      evidence['strength'] = {
        'exercises': exercises,
        'recent_prs': personalRecords,
      };
    }

    if (muscles.isNotEmpty || consistency.isNotEmpty || metrics.isNotEmpty) {
      evidence['volume_frequency'] = {
        if (metrics.isNotEmpty)
          'context_window': _pick(metrics, const ['sessions', 'total_volume']),
        if (muscles.isNotEmpty) 'muscles': muscles,
        if (consistency.isNotEmpty) 'consistency': consistency,
      };
    }

    if (progression.isNotEmpty) {
      evidence['progression'] = {'recommendations': progression};
    }
    if (readiness.isNotEmpty) {
      evidence['readiness'] = readiness;
    }

    return evidence;
  }

  Map<String, dynamic> _compactExercise(Map<String, dynamic> input) =>
      _pick(input, const [
        'exercise',
        'muscle_group',
        'sessions',
        'completed_sets',
        'total_reps',
        'total_volume',
        'best_weight',
        'best_reps',
        'best_estimated_1rm',
        'latest_estimated_1rm',
        'estimated_1rm_trend_percent',
        'last_trained_at',
      ]);

  Map<String, dynamic> _compactPersonalRecord(Map<String, dynamic> input) =>
      _pick(input, const [
        'exercise',
        'muscle_group',
        'kind',
        'date',
        'value',
        'weight',
        'reps',
      ]);

  Map<String, dynamic> _compactMuscle(Map<String, dynamic> input) =>
      _pick(input, const [
        'muscle_group',
        'sets_7d',
        'sets_30d',
        'volume_7d',
        'volume_30d',
        'sessions_30d',
        'set_share_30d',
      ]);

  Map<String, dynamic> _compactProgression(Map<String, dynamic> input) {
    final output = _pick(input, const [
      'exercise',
      'action',
      'confidence',
      'reasons',
      'suggested_weight_delta',
      'suggested_rep_delta',
      'suggested_weight_multiplier',
      'current_estimated_1rm',
      'estimated_1rm_change_percent',
      'volume_change_percent',
      'effective_rir',
      'completed_work_sets',
      'planned_work_sets',
      'all_work_sets_completed',
      'all_at_top',
      'any_below_min',
    ]);
    final readiness = _compactReadiness(_map(input['readiness']));
    if (readiness.isNotEmpty) output['readiness'] = readiness;
    return output;
  }

  Map<String, dynamic> _compactReadiness(Map<String, dynamic> input) =>
      _pick(input, const [
        'score',
        'status',
        'adaptation',
        'reasons',
        'sessions_last_7_days',
        'hours_since_last_stimulus',
        'average_rir',
        'average_rpe',
        'acute_volume_ratio',
        'estimated_1rm_trend_percent',
        'self_readiness',
        'sleep_hours',
        'recommended_load_multiplier',
        'recommended_set_reduction',
      ]);

  Map<String, dynamic> _pick(Map<String, dynamic> source, List<String> keys) {
    final output = <String, dynamic>{};
    for (final key in keys) {
      if (source.containsKey(key) && source[key] != null) {
        output[key] = source[key];
      }
    }
    return output;
  }

  Map<String, dynamic> _map(Object? raw) {
    if (raw is! Map) return <String, dynamic>{};
    return Map<String, dynamic>.from(raw);
  }

  Iterable<Map<String, dynamic>> _maps(Object? raw) sync* {
    if (raw is! List) return;
    for (final item in raw) {
      if (item is Map) yield Map<String, dynamic>.from(item);
    }
  }
}
