import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'ai_coach_context_capsule.dart';
import 'ai_coach_context_router.dart';

class AiCoachContextDiagnostics {
  final int encodedChars;
  final int budgetChars;
  final int activePlanCount;
  final int workoutCount;
  final int bodyLogCount;
  final bool hasVerifiedEvidence;
  final bool truncated;
  final List<String> topLevelKeys;
  final List<String> planTitles;
  final List<String> exerciseNames;

  const AiCoachContextDiagnostics({
    required this.encodedChars,
    required this.budgetChars,
    required this.activePlanCount,
    required this.workoutCount,
    required this.bodyLogCount,
    required this.hasVerifiedEvidence,
    required this.truncated,
    required this.topLevelKeys,
    required this.planTitles,
    required this.exerciseNames,
  });

  String toLogLine() {
    final titles = planTitles.isEmpty ? '-' : planTitles.join('|');
    final exercises = exerciseNames.isEmpty ? '-' : exerciseNames.join('|');
    return 'chars=$encodedChars/$budgetChars '
        'plans=$activePlanCount workouts=$workoutCount body_logs=$bodyLogCount '
        'verified=$hasVerifiedEvidence truncated=$truncated '
        'plan_titles=$titles exercises=$exercises '
        'keys=${topLevelKeys.join('|')}';
  }
}

/// Final prompt-budget boundary for the on-device coach.
///
/// Instead of trying to preserve a large JSON tree until the very last byte,
/// this layer now always distills routed data into a deterministic mobile
/// capsule. The capsule is dense plain text generated only from app state and
/// deterministic analytics; no second LLM is involved in compression.
class AiCoachContextBudget {
  const AiCoachContextBudget._();

  static AiCoachContextDiagnostics? lastDiagnostics;

  /// The full Gemma runtime has a 4096-token context window. Dense JSON has a
  /// poor token/character ratio, so keep the final context envelope small even
  /// when callers request the historical 7000-character allowance.
  static const int _modelSafeCharBudget = 2600;
  static const int _capsuleMaxChars = 2200;

  static String encode(
    Map<String, dynamic> source, {
    required int charBudget,
    required bool keepProgramHistory,
  }) {
    if (charBudget < 64) return '{}';

    final budget = charBudget > _modelSafeCharBudget
        ? _modelSafeCharBudget
        : charBudget;
    if (budget < 180) {
      const fallback = '{"context_truncated":true}';
      return fallback.length <= budget ? fallback : '{}';
    }

    final routed = Map<String, dynamic>.from(source);
    if (!keepProgramHistory) {
      routed.remove('program_history');
      routed.remove('program_change_effectiveness');
    }

    // Reserve space for JSON envelope keys/escaping. A second pass below
    // handles unusually escape-heavy strings deterministically.
    var capsuleBudget = (budget - 260).clamp(160, _capsuleMaxChars).toInt();
    var capsule = const AiCoachContextCapsuleBuilder().build(
      context: routed,
      intent: AiCoachChatIntent.general,
      charBudget: capsuleBudget,
    );

    String? longitudinal;
    if (keepProgramHistory) {
      longitudinal = _longitudinalCapsule(routed, maxChars: 360);
    }

    var encoded = _encodeEnvelope(
      capsule: capsule,
      longitudinal: longitudinal,
      source: routed,
    );

    if (encoded.length > budget) {
      final overflow = encoded.length - budget;
      capsuleBudget = (capsuleBudget - overflow - 48).clamp(160, capsuleBudget).toInt();
      capsule = const AiCoachContextCapsuleBuilder().build(
        context: routed,
        intent: AiCoachChatIntent.general,
        charBudget: capsuleBudget,
      );
      if (longitudinal != null && longitudinal.length > 180) {
        longitudinal = _clip(longitudinal, 180);
      }
      encoded = _encodeEnvelope(
        capsule: capsule,
        longitudinal: longitudinal,
        source: routed,
      );
    }

    if (encoded.length > budget) {
      longitudinal = null;
      encoded = _encodeEnvelope(
        capsule: capsule,
        longitudinal: null,
        source: routed,
      );
    }

    if (encoded.length > budget) {
      final allowedCapsule = (capsule.length - (encoded.length - budget) - 24)
          .clamp(80, capsule.length)
          .toInt();
      capsule = _clip(capsule, allowedCapsule);
      encoded = _encodeEnvelope(
        capsule: capsule,
        longitudinal: null,
        source: routed,
      );
    }

    if (encoded.length > budget) {
      const fallback = '{"context_truncated":true}';
      encoded = fallback.length <= budget ? fallback : '{}';
    }

    final diagnostics = _buildDiagnostics(
      encoded: encoded,
      budget: budget,
      source: routed,
    );
    lastDiagnostics = diagnostics;
    if (kDebugMode) {
      debugPrint('[AI_COACH_CONTEXT] ${diagnostics.toLogLine()}');
    }
    return encoded;
  }

  static String _encodeEnvelope({
    required String capsule,
    required String? longitudinal,
    required Map<String, dynamic> source,
  }) {
    final capsuleDiagnostics = AiCoachContextCapsuleBuilder.lastDiagnostics;
    return jsonEncode({
      'context_format': 'mobile_capsule_v1',
      'user_data_available':
          capsuleDiagnostics?.userDataAvailable ?? _hasUserData(source),
      'reference_data_available':
          capsuleDiagnostics?.referenceDataAvailable ??
          (source['exercise_catalog'] is Map &&
              (source['exercise_catalog'] as Map).isNotEmpty),
      'capsule': capsule,
      if (longitudinal != null && longitudinal.isNotEmpty)
        'longitudinal': longitudinal,
    });
  }

  static bool _hasUserData(Map<String, dynamic> source) {
    bool nonEmptyList(String key) =>
        source[key] is List && (source[key] as List).isNotEmpty;
    bool nonEmptyMap(String key) =>
        source[key] is Map && (source[key] as Map).isNotEmpty;
    return nonEmptyList('active_plans') ||
        nonEmptyList('workouts') ||
        nonEmptyList('body_logs') ||
        nonEmptyMap('focus_context') ||
        nonEmptyMap('verified_evidence') ||
        nonEmptyMap('deterministic_analytics') ||
        nonEmptyMap('user_profile') ||
        nonEmptyMap('memory');
  }

  static String? _longitudinalCapsule(
    Map<String, dynamic> source, {
    required int maxChars,
  }) {
    final parts = <String>[];
    final history = source['program_history'];
    if (history != null) {
      parts.add('PROGRAM_HISTORY=${_compactJson(history)}');
    }
    final effectiveness = source['program_change_effectiveness'];
    if (effectiveness != null) {
      parts.add('CHANGE_EFFECT=${_compactJson(effectiveness)}');
    }
    if (parts.isEmpty) return null;
    return _clip(parts.join('\n'), maxChars);
  }

  static String _compactJson(Object? value) {
    return jsonEncode(_clipValue(value, depth: 0));
  }

  static Object? _clipValue(Object? value, {required int depth}) {
    if (depth >= 4) return '<cut>';
    if (value is String) return _clip(value, 72);
    if (value is List) {
      return value
          .take(3)
          .map((entry) => _clipValue(entry, depth: depth + 1))
          .toList();
    }
    if (value is Map) {
      final result = <String, dynamic>{};
      for (final entry in value.entries.take(10)) {
        result[entry.key.toString()] = _clipValue(
          entry.value,
          depth: depth + 1,
        );
      }
      return result;
    }
    return value;
  }

  static AiCoachContextDiagnostics _buildDiagnostics({
    required String encoded,
    required int budget,
    required Map<String, dynamic> source,
  }) {
    final plans = (source['active_plans'] as List? ?? const <dynamic>[])
        .whereType<Map>()
        .toList();
    final planTitles = <String>[];
    final exerciseNames = <String>[];
    for (final rawPlan in plans.take(3)) {
      final plan = Map<String, dynamic>.from(rawPlan);
      final title = plan['title']?.toString().trim() ?? '';
      if (title.isNotEmpty) planTitles.add(title);
      for (final rawExercise
          in (plan['exercises'] as List? ?? const <dynamic>[]).whereType<Map>()) {
        final name = rawExercise['name']?.toString().trim() ?? '';
        if (name.isNotEmpty && exerciseNames.length < 16) {
          exerciseNames.add(name);
        }
      }
    }

    final decoded = _tryDecode(encoded);
    return AiCoachContextDiagnostics(
      encodedChars: encoded.length,
      budgetChars: budget,
      activePlanCount: plans.length,
      workoutCount: (source['workouts'] as List? ?? const <dynamic>[]).length,
      bodyLogCount: (source['body_logs'] as List? ?? const <dynamic>[]).length,
      hasVerifiedEvidence:
          source['verified_evidence'] is Map &&
          (source['verified_evidence'] as Map).isNotEmpty,
      truncated: decoded['context_truncated'] == true,
      topLevelKeys: decoded.keys.toList(),
      planTitles: planTitles,
      exerciseNames: exerciseNames,
    );
  }

  static Map<String, dynamic> _tryDecode(String encoded) {
    try {
      final decoded = jsonDecode(encoded);
      return decoded is Map ? Map<String, dynamic>.from(decoded) : const {};
    } catch (_) {
      return const {};
    }
  }

  static String _clip(String value, int limit) {
    if (limit <= 0) return '';
    if (value.length <= limit) return value;
    if (limit == 1) return value.substring(0, 1);
    return '${value.substring(0, limit - 1)}…';
  }
}
