from pathlib import Path


def replace_once(text: str, old: str, new: str, label: str) -> str:
    if text.count(old) != 1:
        raise RuntimeError(f'{label}: expected exactly one anchor, found {text.count(old)}')
    return text.replace(old, new, 1)


# TrainingContextBuilder: compute analytics once, then publish compact verified evidence.
path = Path('lib/ai_coach/training_context_builder.dart')
text = path.read_text()
text = replace_once(
    text,
    "import 'ai_coach_user_profile.dart';\n",
    "import 'ai_coach_user_profile.dart';\nimport 'ai_coach_verified_evidence.dart';\n",
    'training import',
)
old = """    final totalVolume = _totalVolume(history);
    final exerciseVolume = _exerciseVolume(history);
    final muscleGroupVolume = _muscleGroupVolume(history);
    final notes = _collectNotes(history);

    return {
"""
new = """    final totalVolume = _totalVolume(history);
    final exerciseVolume = _exerciseVolume(history);
    final muscleGroupVolume = _muscleGroupVolume(history);
    final notes = _collectNotes(history);
    final metrics = <String, dynamic>{
      'sessions': history.length,
      'total_volume': totalVolume,
      'exercise_volume': exerciseVolume,
      'muscle_group_volume': muscleGroupVolume,
    };
    final progressAnalytics = buildProgressAnalytics(
      history: analyticsHistory,
      now: _now,
    );
    final fatigueReadiness = buildGlobalReadinessReport(
      history: analyticsHistory,
      bodyLogs: bodyLogs,
      now: _now,
    );
    final progressionRecommendations = _progressionRecommendations(
      analyticsHistory,
      bodyLogs,
    );
    final deterministicAnalytics = <String, dynamic>{
      'progress_analytics': progressAnalytics.toJson(),
      'exercise_progress': _exerciseProgress(history),
      'fatigue_readiness': fatigueReadiness.toJson(),
      'progression_recommendations': progressionRecommendations,
      'session_count': history.length,
      'latest_session_at': history.isEmpty
          ? null
          : history
                .map((e) => e.startTime)
                .reduce((a, b) => a.isAfter(b) ? a : b)
                .toIso8601String(),
    };
    final verifiedEvidence = const AiCoachVerifiedEvidenceBuilder().build({
      'metrics': metrics,
      'deterministic_analytics': deterministicAnalytics,
    });

    return {
"""
text = replace_once(text, old, new, 'training pre-return')
old = """      'metrics': {
        'sessions': history.length,
        'total_volume': totalVolume,
        'exercise_volume': exerciseVolume,
        'muscle_group_volume': muscleGroupVolume,
      },
      'deterministic_analytics': {
        'progress_analytics': buildProgressAnalytics(
          history: analyticsHistory,
          now: _now,
        ).toJson(),
        'exercise_progress': _exerciseProgress(history),
        'fatigue_readiness': buildGlobalReadinessReport(
          history: analyticsHistory,
          bodyLogs: bodyLogs,
          now: _now,
        ).toJson(),
        'progression_recommendations': _progressionRecommendations(
          analyticsHistory,
          bodyLogs,
        ),
        'session_count': history.length,
        'latest_session_at': history.isEmpty
            ? null
            : history
                  .map((e) => e.startTime)
                  .reduce((a, b) => a.isAfter(b) ? a : b)
                  .toIso8601String(),
      },
"""
new = """      'metrics': metrics,
      'deterministic_analytics': deterministicAnalytics,
      'verified_evidence': verifiedEvidence,
"""
text = replace_once(text, old, new, 'training analytics return')
path.write_text(text)


# Intent router: keep only the evidence families relevant to each coaching mode.
path = Path('lib/ai_coach/ai_coach_context_router.dart')
text = path.read_text()
text = replace_once(
    text,
    "    final analytics = _analytics(result['deterministic_analytics']);\n",
    "    final analytics = _analytics(result['deterministic_analytics']);\n    final evidence = _evidence(result['verified_evidence']);\n",
    'router evidence init',
)
replacements = [
    ("""        _keepAnalytics(
          analytics,
          const {'exercise_progress', 'progression_recommendations'},
        );
""", """        _keepAnalytics(
          analytics,
          const {'exercise_progress', 'progression_recommendations'},
        );
        _keepEvidence(evidence, const {'strength', 'progression'});
""", 'router technique'),
    ("""        _keepAnalytics(
          analytics,
          const {
            'exercise_progress',
            'progression_recommendations',
            'fatigue_readiness',
            'latest_session_at',
          },
        );
""", """        _keepAnalytics(
          analytics,
          const {
            'exercise_progress',
            'progression_recommendations',
            'fatigue_readiness',
            'latest_session_at',
          },
        );
        _keepEvidence(
          evidence,
          const {'strength', 'volume_frequency', 'progression', 'readiness'},
        );
""", 'router progression'),
    ("""        _keepAnalytics(
          analytics,
          const {'fatigue_readiness', 'latest_session_at', 'session_count'},
        );
""", """        _keepAnalytics(
          analytics,
          const {'fatigue_readiness', 'latest_session_at', 'session_count'},
        );
        _keepEvidence(evidence, const {'volume_frequency', 'readiness'});
""", 'router recovery'),
    ("""        _keepAnalytics(
          analytics,
          const {
            'progress_analytics',
            'exercise_progress',
            'latest_session_at',
            'session_count',
          },
        );
""", """        _keepAnalytics(
          analytics,
          const {
            'progress_analytics',
            'exercise_progress',
            'latest_session_at',
            'session_count',
          },
        );
        _keepEvidence(evidence, const {'strength', 'volume_frequency'});
""", 'router progress'),
    ("""        _keepAnalytics(
          analytics,
          const {
            'progress_analytics',
            'exercise_progress',
            'fatigue_readiness',
            'progression_recommendations',
          },
        );
""", """        _keepAnalytics(
          analytics,
          const {
            'progress_analytics',
            'exercise_progress',
            'fatigue_readiness',
            'progression_recommendations',
          },
        );
        _keepEvidence(
          evidence,
          const {'strength', 'volume_frequency', 'progression', 'readiness'},
        );
""", 'router program'),
    ("""        _keepAnalytics(
          analytics,
          const {
            'progress_analytics',
            'fatigue_readiness',
            'progression_recommendations',
            'latest_session_at',
          },
        );
""", """        _keepAnalytics(
          analytics,
          const {
            'progress_analytics',
            'fatigue_readiness',
            'progression_recommendations',
            'latest_session_at',
          },
        );
        _keepEvidence(
          evidence,
          const {'strength', 'volume_frequency', 'progression', 'readiness'},
        );
""", 'router general'),
]
for old, new, label in replacements:
    text = replace_once(text, old, new, label)
text = replace_once(
    text,
    """    if (analytics.isEmpty) {
      result.remove('deterministic_analytics');
    } else {
      result['deterministic_analytics'] = analytics;
    }
    return result;
""",
    """    if (analytics.isEmpty) {
      result.remove('deterministic_analytics');
    } else {
      result['deterministic_analytics'] = analytics;
    }
    if (evidence.isEmpty) {
      result.remove('verified_evidence');
    } else {
      result['verified_evidence'] = evidence;
    }
    return result;
""",
    'router result',
)
text = replace_once(
    text,
    """  Map<String, dynamic> _analytics(Object? raw) {
    if (raw is! Map) return <String, dynamic>{};
    return Map<String, dynamic>.from(raw);
  }

  void _keepAnalytics(Map<String, dynamic> analytics, Set<String> allowed) {
""",
    """  Map<String, dynamic> _analytics(Object? raw) {
    if (raw is! Map) return <String, dynamic>{};
    return Map<String, dynamic>.from(raw);
  }

  Map<String, dynamic> _evidence(Object? raw) {
    if (raw is! Map) return <String, dynamic>{};
    return Map<String, dynamic>.from(raw);
  }

  void _keepEvidence(Map<String, dynamic> evidence, Set<String> allowed) {
    const alwaysKeep = {'source', 'contract', 'coverage'};
    evidence.removeWhere(
      (key, _) => !alwaysKeep.contains(key) && !allowed.contains(key),
    );
  }

  void _keepAnalytics(Map<String, dynamic> analytics, Set<String> allowed) {
""",
    'router helpers',
)
path.write_text(text)


# Exercise focus: filter the compact evidence contract as well as legacy analytics.
path = Path('lib/ai_coach/ai_coach_exercise_context.dart')
text = path.read_text()
text = replace_once(
    text,
    """      result['deterministic_analytics'] = analytics;
    }

    final catalog = _map(result['exercise_catalog']);
""",
    """      result['deterministic_analytics'] = analytics;
    }

    final verifiedEvidence = _map(result['verified_evidence']);
    if (verifiedEvidence.isNotEmpty) {
      result['verified_evidence'] = _filterVerifiedEvidence(
        verifiedEvidence,
        focus,
      );
    }

    final catalog = _map(result['exercise_catalog']);
""",
    'exercise evidence call',
)
text = replace_once(
    text,
    """  List<dynamic> _filterWorkouts(Object? raw, AiCoachExerciseFocus focus) {
""",
    """  Map<String, dynamic> _filterVerifiedEvidence(
    Map<String, dynamic> source,
    AiCoachExerciseFocus focus,
  ) {
    final output = Map<String, dynamic>.from(source);
    final matchedMuscleGroups = <String>{};

    final strength = _map(output['strength']);
    if (strength.isNotEmpty) {
      final exercises = _filterNamedList(
        strength['exercises'],
        focus,
        key: 'exercise',
      );
      final records = _filterNamedList(
        strength['recent_prs'],
        focus,
        key: 'exercise',
      );
      for (final exercise in exercises) {
        final muscleGroup = exercise['muscle_group']?.toString();
        if (muscleGroup != null && muscleGroup.isNotEmpty) {
          matchedMuscleGroups.add(muscleGroup);
        }
      }
      if (exercises.isEmpty && records.isEmpty) {
        output.remove('strength');
      } else {
        output['strength'] = {
          if (exercises.isNotEmpty) 'exercises': exercises,
          if (records.isNotEmpty) 'recent_prs': records,
        };
      }
    }

    final progression = _map(output['progression']);
    if (progression.isNotEmpty) {
      final recommendations = _filterNamedList(
        progression['recommendations'],
        focus,
        key: 'exercise',
      );
      if (recommendations.isEmpty) {
        output.remove('progression');
      } else {
        output['progression'] = {'recommendations': recommendations};
      }
    }

    final volumeFrequency = _map(output['volume_frequency']);
    if (volumeFrequency.isNotEmpty && matchedMuscleGroups.isNotEmpty) {
      final muscles = _list(volumeFrequency['muscles'])
          .where((item) {
            if (item is! Map) return false;
            return matchedMuscleGroups.contains(item['muscle_group']?.toString());
          })
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList();
      if (muscles.isEmpty) {
        volumeFrequency.remove('muscles');
      } else {
        volumeFrequency['muscles'] = muscles;
      }
      output['volume_frequency'] = volumeFrequency;
    }

    return output;
  }

  List<dynamic> _filterWorkouts(Object? raw, AiCoachExerciseFocus focus) {
""",
    'exercise evidence helper',
)
path.write_text(text)


# Budgeting: compact verified evidence early and preserve it after raw analytics.
path = Path('lib/ai_coach/ai_coach_context_budget.dart')
text = path.read_text()
text = replace_once(
    text,
    """    context['notes'] = _tail(context['notes'], 6);
    encoded = jsonEncode(context);
    if (encoded.length <= charBudget) return encoded;

    final analytics = context['deterministic_analytics'];
""",
    """    context['notes'] = _tail(context['notes'], 6);
    final verifiedEvidence = context['verified_evidence'];
    if (verifiedEvidence is Map) {
      context['verified_evidence'] = _compactVerifiedEvidence(verifiedEvidence);
    }
    encoded = jsonEncode(context);
    if (encoded.length <= charBudget) return encoded;

    final analytics = context['deterministic_analytics'];
""",
    'budget compact evidence',
)
text = replace_once(
    text,
    """  static List<dynamic> _tail(Object? raw, int count) {
""",
    """  static Map<String, dynamic> _compactVerifiedEvidence(Map raw) {
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
""",
    'budget evidence helper',
)
path.write_text(text)


# Chat prompt: make the deterministic-first contract explicit.
path = Path('lib/ai_coach/local_ai_coach_service.dart')
text = path.read_text()
text = replace_once(
    text,
    "- Deterministic analytics are authoritative calculations. Use their exact direction and values when relevant; do not silently override them with model intuition.\n",
    "- verified_evidence is the compact authoritative layer for derived training facts. Interpret it; do not recalculate PRs, e1RM, trends, volume, frequency, progression, or readiness from raw sets.\n- Deterministic analytics are authoritative calculations. Use their exact direction and values when relevant; do not silently override them with model intuition.\n",
    'chat system evidence',
)
text = replace_once(
    text,
    "- Ground personalized claims in the supplied data. Mention exact values only when they exist in the context.\n",
    "- Ground personalized claims in the supplied data. Mention exact values only when they exist in the context.\n- Read verified_evidence before raw workouts or deterministic_analytics for derived metrics; raw sets may illustrate a fact but must not be used to replace app-calculated derived values.\n",
    'chat response evidence',
)
path.write_text(text)


# Structured prompt: same contract for reports and adjustments.
path = Path('lib/ai_coach/ai_coach_prompts.dart')
text = path.read_text()
text = replace_once(
    text,
    "- Use user_profile, deterministic_analytics, coach_memory, and image labels when present.\n",
    "- Use user_profile, verified_evidence, deterministic_analytics, coach_memory, and image labels when present.\n- verified_evidence is the first source for derived training facts. Do not recalculate PRs, e1RM, trends, volume, frequency, progression, or readiness from raw sets when verified_evidence contains them.\n",
    'structured evidence',
)
path.write_text(text)


# Program Builder should use the same evidence hierarchy.
path = Path('lib/ai_coach/ai_program_draft_service.dart')
text = path.read_text()
text = replace_once(
    text,
    "- Use program_history and deterministic_analytics as evidence. Do not contradict deterministic progression/recovery facts without explicitly preserving the uncertainty in rationale.\n",
    "- Use verified_evidence first for derived training facts, then program_history and deterministic_analytics for supporting detail. Never recalculate or contradict app-derived PR, e1RM, trend, volume, frequency, progression, or readiness values from raw sets.\n",
    'program evidence',
)
path.write_text(text)
