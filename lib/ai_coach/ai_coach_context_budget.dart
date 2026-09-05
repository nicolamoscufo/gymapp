import 'dart:convert';

class AiCoachContextBudget {
  const AiCoachContextBudget._();

  /// Keep enough headroom for the stable system contract, the current user
  /// turn and the generated reply inside Gemma's 4096-token KV cache.
  ///
  /// The previous 7000-character JSON allowance was only a character cap, not
  /// a token cap. Dense JSON can consume substantially more tokens than plain
  /// prose, so the model could lose the earliest grounding instructions/context
  /// and then answer as if it had no access to the user's data.
  static const int _modelSafeCharBudget = 3600;

  static String encode(
    Map<String, dynamic> source, {
    required int charBudget,
    required bool keepProgramHistory,
  }) {
    if (charBudget < 32) {
      return '{}';
    }

    final budget = charBudget > _modelSafeCharBudget
        ? _modelSafeCharBudget
        : charBudget;
    final context = Map<String, dynamic>.from(source);

    // Active plans are one of the highest-value grounding sources for a coach.
    // Compact them immediately instead of dropping them later under pressure.
    context['active_plans'] = _compactActivePlans(
      context['active_plans'],
      maxPlans: 2,
      maxExercises: 10,
    );

    String encoded = jsonEncode(context);
    if (encoded.length <= budget) return encoded;

    context['workouts'] = _tail(context['workouts'], 2);
    context['body_logs'] = _tail(context['body_logs'], 4);
    context['notes'] = _tail(context['notes'], 6);
    final verifiedEvidence = context['verified_evidence'];
    if (verifiedEvidence is Map) {
      context['verified_evidence'] = _compactVerifiedEvidence(verifiedEvidence);
    }
    encoded = jsonEncode(context);
    if (encoded.length <= budget) return encoded;

    // Exercise catalog rows are useful metadata, but they are lower priority
    // than actual user history, active plans and verified derived evidence.
    context.remove('exercise_catalog');
    encoded = jsonEncode(context);
    if (encoded.length <= budget) return encoded;

    if (!keepProgramHistory) {
      context.remove('program_change_effectiveness');
      context.remove('program_history');
      encoded = jsonEncode(context);
      if (encoded.length <= budget) return encoded;
    }

    final analytics = context['deterministic_analytics'];
    if (analytics is Map) {
      final compactAnalytics = Map<String, dynamic>.from(analytics);
      compactAnalytics.remove('exercise_progress');
      compactAnalytics.remove('progression_recommendations');
      context['deterministic_analytics'] = compactAnalytics;
    }
    encoded = jsonEncode(context);
    if (encoded.length <= budget) return encoded;

    context['active_plans'] = _compactActivePlans(
      context['active_plans'],
      maxPlans: 1,
      maxExercises: 8,
    );
    encoded = jsonEncode(context);
    if (encoded.length <= budget) return encoded;

    // Prefer concise verified evidence over duplicated long-form raw payloads.
    context.remove('notes');
    encoded = jsonEncode(context);
    if (encoded.length <= budget) return encoded;

    context.remove('body_logs');
    encoded = jsonEncode(context);
    if (encoded.length <= budget) return encoded;

    context['workouts'] = _tail(context['workouts'], 1);
    encoded = jsonEncode(context);
    if (encoded.length <= budget) return encoded;

    // When longitudinal history is explicitly requested, sacrifice raw workout
    // details before removing program history. Otherwise program history has
    // already been removed above.
    if (keepProgramHistory) {
      context.remove('workouts');
      encoded = jsonEncode(context);
      if (encoded.length <= budget) return encoded;

      context.remove('program_change_effectiveness');
      encoded = jsonEncode(context);
      if (encoded.length <= budget) return encoded;

      context.remove('program_history');
      encoded = jsonEncode(context);
      if (encoded.length <= budget) return encoded;
    } else {
      context.remove('workouts');
      encoded = jsonEncode(context);
      if (encoded.length <= budget) return encoded;
    }

    context.remove('deterministic_analytics');
    encoded = jsonEncode(context);
    if (encoded.length <= budget) return encoded;

    // Build a high-signal grounding core before generic clipping. The key
    // invariant is that a non-empty active plan is not silently discarded just
    // because another payload is verbose.
    final groundingCore = <String, dynamic>{
      'generated_at': context['generated_at'],
      'user_profile': context['user_profile'],
      'memory': context['memory'],
      'active_plans': _compactActivePlans(
        context['active_plans'],
        maxPlans: 1,
        maxExercises: 6,
      ),
      'verified_evidence': context['verified_evidence'],
    }..removeWhere((_, value) => value == null);

    encoded = jsonEncode(groundingCore);
    if (encoded.length <= budget) return encoded;

    final verified = groundingCore['verified_evidence'];
    if (verified is Map) {
      final compact = _compactVerifiedEvidence(verified);
      groundingCore['verified_evidence'] = compact;
      encoded = jsonEncode(groundingCore);
      if (encoded.length <= budget) return encoded;

      for (final family in const [
        'strength',
        'volume_frequency',
        'progression',
        'readiness',
      ]) {
        compact.remove(family);
        encoded = jsonEncode(groundingCore);
        if (encoded.length <= budget) return encoded;
      }
    }

    groundingCore['active_plans'] = _compactActivePlans(
      groundingCore['active_plans'],
      maxPlans: 1,
      maxExercises: 4,
    );
    encoded = jsonEncode(groundingCore);
    if (encoded.length <= budget) return encoded;

    groundingCore.remove('user_profile');
    encoded = jsonEncode(groundingCore);
    if (encoded.length <= budget) return encoded;

    groundingCore.remove('memory');
    encoded = jsonEncode(groundingCore);
    if (encoded.length <= budget) return encoded;

    // If there is an active plan, preserve at least a compact plan snapshot so
    // questions such as "riesci a vedere la mia scheda?" cannot degrade into a
    // false no-data answer solely because the broader context was too large.
    final planOnly = <String, dynamic>{
      'context_truncated': true,
      'active_plans': _compactActivePlans(
        groundingCore['active_plans'],
        maxPlans: 1,
        maxExercises: 3,
      ),
    };
    if ((planOnly['active_plans'] as List).isNotEmpty) {
      encoded = jsonEncode(planOnly);
      if (encoded.length <= budget) return encoded;
    }

    // Last-resort clipping keeps the payload valid JSON. This protects the
    // model context window even if a future field contains unexpectedly large
    // user text.
    for (final stringLimit in const [256, 128, 64, 32]) {
      final clipped = _clipValue(
        groundingCore,
        stringLimit: stringLimit,
        listLimit: stringLimit >= 128 ? 4 : 2,
        mapLimit: stringLimit >= 128 ? 20 : 10,
        depth: 0,
      );
      encoded = jsonEncode(clipped);
      if (encoded.length <= budget) return encoded;
    }

    const fallback = '{"context_truncated":true}';
    return fallback.length <= budget ? fallback : '{}';
  }

  static Map<String, dynamic> _compactVerifiedEvidence(Map raw) {
    final evidence = Map<String, dynamic>.from(raw);
    final strength = evidence['strength'];
    if (strength is Map) {
      final compact = Map<String, dynamic>.from(strength);
      compact['exercises'] = _head(compact['exercises'], 6);
      compact['recent_prs'] = _head(compact['recent_prs'], 8);
      evidence['strength'] = compact;
    }
    final volumeFrequency = evidence['volume_frequency'];
    if (volumeFrequency is Map) {
      final compact = Map<String, dynamic>.from(volumeFrequency);
      compact['muscles'] = _head(compact['muscles'], 8);
      evidence['volume_frequency'] = compact;
    }
    final progression = evidence['progression'];
    if (progression is Map) {
      final compact = Map<String, dynamic>.from(progression);
      compact['recommendations'] = _head(compact['recommendations'], 8);
      evidence['progression'] = compact;
    }
    return evidence;
  }

  static List<dynamic> _compactActivePlans(
    Object? raw, {
    required int maxPlans,
    required int maxExercises,
  }) {
    final plans = raw is List ? raw : const <dynamic>[];
    return plans.whereType<Map>().take(maxPlans).map((rawPlan) {
      final plan = Map<String, dynamic>.from(rawPlan);
      final exercises = (plan['exercises'] as List? ?? const <dynamic>[])
          .whereType<Map>()
          .take(maxExercises)
          .map((rawExercise) {
            final exercise = Map<String, dynamic>.from(rawExercise);
            final result = <String, dynamic>{};
            for (final key in const [
              'id',
              'catalogId',
              'name',
              'set',
              'reps',
              'weight',
              'targetMinReps',
              'targetMaxReps',
              'technique',
              'backoffReps',
              'backoffReductionPercent',
              'restSeconds',
              'progressionKgStep',
              'progressionRepStep',
              'progressionScheme',
            ]) {
              if (exercise.containsKey(key)) {
                result[key] = exercise[key];
              }
            }
            return result;
          })
          .toList();

      final result = <String, dynamic>{};
      for (final key in const [
        'id',
        'title',
        'week',
        'goal',
        'programBlock',
        'cycleNumber',
        'currentVersionId',
        'currentVersionNumber',
      ]) {
        if (plan.containsKey(key)) {
          result[key] = plan[key];
        }
      }
      result['exercises'] = exercises;
      return result;
    }).toList();
  }

  static List<dynamic> _tail(Object? raw, int count) {
    final list = raw is List ? raw : const <dynamic>[];
    if (list.length <= count) return List<dynamic>.from(list);
    return List<dynamic>.from(list.sublist(list.length - count));
  }

  static List<dynamic> _head(Object? raw, int count) {
    final list = raw is List ? raw : const <dynamic>[];
    if (list.length <= count) return List<dynamic>.from(list);
    return List<dynamic>.from(list.take(count));
  }

  static Object? _clipValue(
    Object? value, {
    required int stringLimit,
    required int listLimit,
    required int mapLimit,
    required int depth,
  }) {
    if (depth >= 8) return '<truncated>';
    if (value is String) {
      if (value.length <= stringLimit) return value;
      return '${value.substring(0, stringLimit)}…';
    }
    if (value is List) {
      return value
          .take(listLimit)
          .map(
            (entry) => _clipValue(
              entry,
              stringLimit: stringLimit,
              listLimit: listLimit,
              mapLimit: mapLimit,
              depth: depth + 1,
            ),
          )
          .toList();
    }
    if (value is Map) {
      final result = <String, dynamic>{};
      for (final entry in value.entries.take(mapLimit)) {
        result[entry.key.toString()] = _clipValue(
          entry.value,
          stringLimit: stringLimit,
          listLimit: listLimit,
          mapLimit: mapLimit,
          depth: depth + 1,
        );
      }
      return result;
    }
    return value;
  }
}
