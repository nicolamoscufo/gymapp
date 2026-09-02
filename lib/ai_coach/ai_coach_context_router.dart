enum AiCoachChatIntent {
  technique,
  progression,
  recovery,
  progress,
  program,
  general,
}

class AiCoachContextRouter {
  const AiCoachContextRouter();

  AiCoachChatIntent classify(String query) {
    final lower = query.toLowerCase();

    if (_containsAny(lower, _recoveryMarkers)) {
      return AiCoachChatIntent.recovery;
    }
    if (_containsAny(lower, _techniqueMarkers)) {
      return AiCoachChatIntent.technique;
    }
    if (_containsAny(lower, _progressionMarkers)) {
      return AiCoachChatIntent.progression;
    }
    if (_containsAny(lower, _programMarkers)) {
      return AiCoachChatIntent.program;
    }
    if (_containsAny(lower, _progressMarkers)) {
      return AiCoachChatIntent.progress;
    }
    return AiCoachChatIntent.general;
  }

  Map<String, dynamic> route(
    Map<String, dynamic> source, {
    required AiCoachChatIntent intent,
    required bool keepProgramHistory,
  }) {
    final result = Map<String, dynamic>.from(source);
    final analytics = _analytics(result['deterministic_analytics']);

    switch (intent) {
      case AiCoachChatIntent.technique:
        result['workouts'] = _tail(result['workouts'], 2);
        result['body_logs'] = const <dynamic>[];
        result.remove('metrics');
        result['notes'] = _tail(result['notes'], 6);
        _keepAnalytics(
          analytics,
          const {'exercise_progress', 'progression_recommendations'},
        );
        result.remove('program_history');
        result.remove('program_change_effectiveness');
        break;
      case AiCoachChatIntent.progression:
        result['workouts'] = _tail(result['workouts'], 4);
        result['body_logs'] = _tail(result['body_logs'], 4);
        result['notes'] = _tail(result['notes'], 8);
        _keepAnalytics(
          analytics,
          const {
            'exercise_progress',
            'progression_recommendations',
            'fatigue_readiness',
            'latest_session_at',
          },
        );
        result.remove('program_history');
        result.remove('program_change_effectiveness');
        break;
      case AiCoachChatIntent.recovery:
        result['workouts'] = _tail(result['workouts'], 3);
        result['body_logs'] = _tail(result['body_logs'], 8);
        result['notes'] = _tail(result['notes'], 8);
        result['active_plans'] = _head(result['active_plans'], 1);
        _keepAnalytics(
          analytics,
          const {'fatigue_readiness', 'latest_session_at', 'session_count'},
        );
        result.remove('program_history');
        result.remove('program_change_effectiveness');
        break;
      case AiCoachChatIntent.progress:
        result['workouts'] = _tail(result['workouts'], 4);
        result['body_logs'] = _tail(result['body_logs'], 8);
        result['active_plans'] = _head(result['active_plans'], 2);
        _keepAnalytics(
          analytics,
          const {
            'progress_analytics',
            'exercise_progress',
            'latest_session_at',
            'session_count',
          },
        );
        result.remove('program_history');
        result.remove('program_change_effectiveness');
        break;
      case AiCoachChatIntent.program:
        result['workouts'] = _tail(result['workouts'], 2);
        result['body_logs'] = _tail(result['body_logs'], 4);
        result['notes'] = _tail(result['notes'], 6);
        _keepAnalytics(
          analytics,
          const {
            'progress_analytics',
            'exercise_progress',
            'fatigue_readiness',
            'progression_recommendations',
          },
        );
        if (!keepProgramHistory) {
          result.remove('program_history');
          result.remove('program_change_effectiveness');
        }
        break;
      case AiCoachChatIntent.general:
        result['workouts'] = _tail(result['workouts'], 3);
        result['body_logs'] = _tail(result['body_logs'], 4);
        result['notes'] = _tail(result['notes'], 6);
        result['active_plans'] = _head(result['active_plans'], 2);
        _keepAnalytics(
          analytics,
          const {
            'progress_analytics',
            'fatigue_readiness',
            'progression_recommendations',
            'latest_session_at',
          },
        );
        if (!keepProgramHistory) {
          result.remove('program_history');
          result.remove('program_change_effectiveness');
        }
        break;
    }

    if (analytics.isEmpty) {
      result.remove('deterministic_analytics');
    } else {
      result['deterministic_analytics'] = analytics;
    }
    return result;
  }

  String promptHint(AiCoachChatIntent intent) {
    switch (intent) {
      case AiCoachChatIntent.technique:
        return 'Technique question: prioritize the named exercise and visible execution details. Give a small number of concrete cues; do not invent faults that are not supported by text, history, catalog metadata, or the attached image.';
      case AiCoachChatIntent.progression:
        return 'Progression question: anchor the answer to deterministic progression recommendations, recent completed work sets, effort data, and readiness. Do not recommend a specific load increase unless the supplied data supports it.';
      case AiCoachChatIntent.recovery:
        return 'Recovery question: prioritize fatigue_readiness, recent training density, effort, sleep/body logs when present, and the next planned session. Separate training-load advice from medical concerns.';
      case AiCoachChatIntent.progress:
        return 'Progress question: compare the user against their own prior training, using deterministic trends and concrete dates or values when present. Do not use generic population benchmarks unless the user explicitly asks for them.';
      case AiCoachChatIntent.program:
        return 'Programming question: reason from the active plan, goal, preferences, limitations, schedule constraints, and verified historical changes. Discuss trade-offs before proposing structural changes.';
      case AiCoachChatIntent.general:
        return 'General coaching question: answer the request directly, then use only the minimum relevant training evidence needed to personalize it.';
    }
  }

  Map<String, dynamic> _analytics(Object? raw) {
    if (raw is! Map) return <String, dynamic>{};
    return Map<String, dynamic>.from(raw);
  }

  void _keepAnalytics(Map<String, dynamic> analytics, Set<String> allowed) {
    analytics.removeWhere((key, _) => !allowed.contains(key));
  }

  List<dynamic> _tail(Object? raw, int count) {
    final list = raw is List ? raw : const <dynamic>[];
    if (list.length <= count) return List<dynamic>.from(list);
    return List<dynamic>.from(list.sublist(list.length - count));
  }

  List<dynamic> _head(Object? raw, int count) {
    final list = raw is List ? raw : const <dynamic>[];
    if (list.length <= count) return List<dynamic>.from(list);
    return List<dynamic>.from(list.take(count));
  }

  bool _containsAny(String input, List<String> markers) =>
      markers.any(input.contains);

  static const List<String> _techniqueMarkers = [
    'tecnica',
    'esecuzione',
    'forma del movimento',
    'form check',
    'my form',
    'setup',
    'assetto',
    'presa',
    'stance',
    'range of motion',
    'come eseguo',
    'come faccio questo esercizio',
  ];

  static const List<String> _progressionMarkers = [
    'progressione',
    'aumentare il peso',
    'aumento il peso',
    'aumentare i kg',
    'aumento i kg',
    'più reps',
    'piu reps',
    'carico',
    'stallo',
    'stallando',
    'plateau',
    'rir',
    'rpe',
    'deload',
  ];

  static const List<String> _recoveryMarkers = [
    'recuper',
    'stanco',
    'stanchezza',
    'fatica',
    'readiness',
    'sonno',
    'dormito',
    'riposo',
    'doms',
    'dolore',
    'fastidio',
  ];

  static const List<String> _progressMarkers = [
    'progressi',
    'migliorato',
    'migliorando',
    'trend',
    'andamento',
    'pr ',
    'record',
    'e1rm',
    '1rm',
    'volume nel tempo',
    'ultime settimane',
    'ultimo mese',
    'foto progressi',
    'progress photo',
  ];

  static const List<String> _programMarkers = [
    'scheda',
    'programma',
    'split',
    'mesociclo',
    'volume settimanale',
    'frequenza di allenamento',
    'frequenza settimanale',
    'giorni a settimana',
    'upper lower',
    'push pull',
    'full body',
    'routine',
  ];
}
