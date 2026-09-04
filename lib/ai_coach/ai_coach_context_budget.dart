import 'dart:convert';

class AiCoachContextBudget {
  const AiCoachContextBudget._();

  static String encode(
    Map<String, dynamic> source, {
    required int charBudget,
    required bool keepProgramHistory,
  }) {
    if (charBudget < 32) {
      return '{}';
    }

    final context = Map<String, dynamic>.from(source);
    String encoded = jsonEncode(context);
    if (encoded.length <= charBudget) return encoded;

    context['workouts'] = _tail(context['workouts'], 2);
    context['body_logs'] = _tail(context['body_logs'], 4);
    context['notes'] = _tail(context['notes'], 6);
    final verifiedEvidence = context['verified_evidence'];
    if (verifiedEvidence is Map) {
      context['verified_evidence'] = _compactVerifiedEvidence(verifiedEvidence);
    }
    encoded = jsonEncode(context);
    if (encoded.length <= charBudget) return encoded;

    final analytics = context['deterministic_analytics'];
    if (analytics is Map) {
      final compactAnalytics = Map<String, dynamic>.from(analytics);
      compactAnalytics.remove('exercise_progress');
      compactAnalytics.remove('progression_recommendations');
      context['deterministic_analytics'] = compactAnalytics;
    }
    encoded = jsonEncode(context);
    if (encoded.length <= charBudget) return encoded;

    if (keepProgramHistory) {
      context.remove('workouts');
      context.remove('body_logs');
      context.remove('notes');
    } else {
      context.remove('active_plans');
    }
    encoded = jsonEncode(context);
    if (encoded.length <= charBudget) return encoded;

    context.remove('program_change_effectiveness');
    context.remove('program_history');
    encoded = jsonEncode(context);
    if (encoded.length <= charBudget) return encoded;

    context.remove('deterministic_analytics');
    encoded = jsonEncode(context);
    if (encoded.length <= charBudget) return encoded;

    // From here on the input is abnormally large. Drop lower-priority payloads
    // deterministically while preserving focus and user-declared context as
    // long as possible.
    context.remove('notes');
    encoded = jsonEncode(context);
    if (encoded.length <= charBudget) return encoded;

    context.remove('body_logs');
    encoded = jsonEncode(context);
    if (encoded.length <= charBudget) return encoded;

    context['workouts'] = _tail(context['workouts'], 1);
    encoded = jsonEncode(context);
    if (encoded.length <= charBudget) return encoded;

    context.remove('workouts');
    encoded = jsonEncode(context);
    if (encoded.length <= charBudget) return encoded;

    context['active_plans'] = _head(context['active_plans'], 1);
    encoded = jsonEncode(context);
    if (encoded.length <= charBudget) return encoded;

    context.remove('active_plans');
    encoded = jsonEncode(context);
    if (encoded.length <= charBudget) return encoded;

    context.remove('exercise_catalog');
    encoded = jsonEncode(context);
    if (encoded.length <= charBudget) return encoded;

    // Derived training facts are more valuable than duplicated raw logs when
    // the prompt is under severe pressure. Preserve the verified evidence
    // contract before falling back to generic clipping.
    final verified = context['verified_evidence'];
    if (verified is Map) {
      final evidenceOnly = <String, dynamic>{
        'verified_evidence': _compactVerifiedEvidence(verified),
      };
      encoded = jsonEncode(evidenceOnly);
      if (encoded.length <= charBudget) return encoded;

      final compact = Map<String, dynamic>.from(
        evidenceOnly['verified_evidence'] as Map,
      );
      for (final family in const [
        'strength',
        'volume_frequency',
        'progression',
        'readiness',
      ]) {
        compact.remove(family);
        encoded = jsonEncode({'verified_evidence': compact});
        if (encoded.length <= charBudget) return encoded;
      }

      final minimumEnvelope = <String, dynamic>{
        'source': compact['source'],
        'contract': compact['contract'],
        'coverage': compact['coverage'],
      }..removeWhere((_, value) => value == null);
      encoded = jsonEncode({'verified_evidence': minimumEnvelope});
      if (encoded.length <= charBudget) return encoded;

      for (final stringLimit in const [256, 128, 64, 32]) {
        final clippedEvidence = _clipValue(
          {'verified_evidence': minimumEnvelope},
          stringLimit: stringLimit,
          listLimit: 3,
          mapLimit: 16,
          depth: 0,
        );
        encoded = jsonEncode(clippedEvidence);
        if (encoded.length <= charBudget) return encoded;
      }
    }

    // Last-resort clipping keeps the payload valid JSON. This protects the
    // model context window even if a future field contains unexpectedly large
    // user text. The final fallback is deliberately tiny and explicit.
    for (final stringLimit in const [512, 256, 128, 64, 32]) {
      final clipped = _clipValue(
        context,
        stringLimit: stringLimit,
        listLimit: stringLimit >= 256 ? 6 : 3,
        mapLimit: stringLimit >= 128 ? 24 : 12,
        depth: 0,
      );
      encoded = jsonEncode(clipped);
      if (encoded.length <= charBudget) return encoded;
    }

    const fallback = '{"context_truncated":true}';
    return fallback.length <= charBudget ? fallback : '{}';
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
