import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'ai_coach_context_router.dart';

class AiCoachContextCapsuleDiagnostics {
  final int encodedChars;
  final int budgetChars;
  final bool userDataAvailable;
  final bool referenceDataAvailable;
  final int activePlanCount;
  final int workoutCount;
  final int bodyLogCount;
  final List<String> planTitles;
  final List<String> exerciseNames;

  const AiCoachContextCapsuleDiagnostics({
    required this.encodedChars,
    required this.budgetChars,
    required this.userDataAvailable,
    required this.referenceDataAvailable,
    required this.activePlanCount,
    required this.workoutCount,
    required this.bodyLogCount,
    required this.planTitles,
    required this.exerciseNames,
  });

  String toLogLine() {
    final titles = planTitles.isEmpty ? '-' : planTitles.join('|');
    final exercises = exerciseNames.isEmpty ? '-' : exerciseNames.join('|');
    return 'chars=$encodedChars/$budgetChars '
        'user_data=$userDataAvailable reference_data=$referenceDataAvailable '
        'plans=$activePlanCount workouts=$workoutCount body_logs=$bodyLogCount '
        'plan_titles=$titles exercises=$exercises';
  }
}

/// Deterministically distills the routed app context into a compact, dense
/// representation for small on-device models.
///
/// This is deliberately not an LLM summary: every value comes from structured
/// app state or deterministic analytics, so compression cannot hallucinate a
/// workout, load, symptom, plan, or trend that was not already present.
class AiCoachContextCapsuleBuilder {
  static const int defaultCharBudget = 2200;
  static const int _minimumBudget = 160;

  /// Developer-only diagnostics for the last capsule built in this process.
  static AiCoachContextCapsuleDiagnostics? lastDiagnostics;

  const AiCoachContextCapsuleBuilder();

  String build({
    required Map<String, dynamic> context,
    required AiCoachChatIntent intent,
    int charBudget = defaultCharBudget,
  }) {
    final budget = charBudget < _minimumBudget ? _minimumBudget : charBudget;
    final userDataAvailable = _hasUserData(context);
    final referenceDataAvailable = _hasReferenceData(context);

    final header = <String>[
      'USER_DATA_AVAILABLE=$userDataAvailable',
      'REFERENCE_DATA_AVAILABLE=$referenceDataAvailable',
      'INTENT=${intent.name}',
    ];

    final focus = _focusLines(context);
    final plans = _planLines(context, intent: intent);
    final verified = _verifiedLines(context);
    final analytics = _analyticsLines(context);
    final workouts = _workoutLines(context, intent: intent);
    final bodyLogs = _bodyLogLines(context);
    final profile = _profileLines(context);
    final memory = _memoryLines(context);
    final catalog = _catalogLines(context);

    final ordered = <String>[...header];
    switch (intent) {
      case AiCoachChatIntent.technique:
        ordered.addAll(focus);
        ordered.addAll(plans);
        ordered.addAll(workouts);
        ordered.addAll(catalog);
        ordered.addAll(verified);
        ordered.addAll(analytics);
        break;
      case AiCoachChatIntent.progression:
        ordered.addAll(focus);
        ordered.addAll(verified);
        ordered.addAll(analytics);
        ordered.addAll(workouts);
        ordered.addAll(plans);
        ordered.addAll(bodyLogs);
        ordered.addAll(profile);
        ordered.addAll(memory);
        break;
      case AiCoachChatIntent.recovery:
        ordered.addAll(focus);
        ordered.addAll(analytics);
        ordered.addAll(bodyLogs);
        ordered.addAll(workouts);
        ordered.addAll(verified);
        ordered.addAll(plans);
        ordered.addAll(profile);
        ordered.addAll(memory);
        break;
      case AiCoachChatIntent.progress:
        ordered.addAll(focus);
        ordered.addAll(verified);
        ordered.addAll(analytics);
        ordered.addAll(workouts);
        ordered.addAll(bodyLogs);
        ordered.addAll(plans);
        ordered.addAll(profile);
        ordered.addAll(memory);
        break;
      case AiCoachChatIntent.program:
        ordered.addAll(focus);
        ordered.addAll(plans);
        ordered.addAll(verified);
        ordered.addAll(analytics);
        ordered.addAll(workouts);
        ordered.addAll(profile);
        ordered.addAll(memory);
        ordered.addAll(bodyLogs);
        break;
      case AiCoachChatIntent.general:
        ordered.addAll(focus);
        ordered.addAll(plans);
        ordered.addAll(verified);
        ordered.addAll(analytics);
        ordered.addAll(workouts);
        ordered.addAll(bodyLogs);
        ordered.addAll(profile);
        ordered.addAll(memory);
        ordered.addAll(catalog);
        break;
    }

    final encoded = _fitLines(ordered, budget);
    final diagnostics = _diagnostics(
      encoded: encoded,
      budget: budget,
      context: context,
      userDataAvailable: userDataAvailable,
      referenceDataAvailable: referenceDataAvailable,
    );
    lastDiagnostics = diagnostics;
    if (kDebugMode) {
      debugPrint('[AI_COACH_CAPSULE] ${diagnostics.toLogLine()}');
    }
    return encoded;
  }

  bool _hasUserData(Map<String, dynamic> context) {
    return _nonEmptyList(context['active_plans']) ||
        _nonEmptyList(context['workouts']) ||
        _nonEmptyList(context['body_logs']) ||
        _nonEmptyMap(context['focus_context']) ||
        _nonEmptyMap(context['verified_evidence']) ||
        _nonEmptyMap(context['deterministic_analytics']) ||
        _nonEmptyMap(context['user_profile']) ||
        _nonEmptyMap(context['memory']);
  }

  bool _hasReferenceData(Map<String, dynamic> context) =>
      _nonEmptyMap(context['exercise_catalog']);

  bool _nonEmptyList(Object? value) => value is List && value.isNotEmpty;
  bool _nonEmptyMap(Object? value) => value is Map && value.isNotEmpty;

  List<String> _focusLines(Map<String, dynamic> context) {
    final raw = context['focus_context'];
    if (raw is! Map || raw.isEmpty) return const [];
    return ['FOCUS ${_compactJson(raw, stringLimit: 96, listLimit: 4)}'];
  }

  List<String> _planLines(
    Map<String, dynamic> context, {
    required AiCoachChatIntent intent,
  }) {
    final plans = (context['active_plans'] as List? ?? const <dynamic>[])
        .whereType<Map>()
        .take(intent == AiCoachChatIntent.program ? 3 : 2);
    final lines = <String>[];
    for (final rawPlan in plans) {
      final plan = Map<String, dynamic>.from(rawPlan);
      final title = _text(plan['title'], fallback: 'Senza titolo');
      final goal = _text(plan['goal']);
      final week = _text(plan['week']);
      final exercises = (plan['exercises'] as List? ?? const <dynamic>[])
          .whereType<Map>()
          .take(intent == AiCoachChatIntent.program ? 14 : 10)
          .toList();
      lines.add(
        'PLAN $title${goal.isEmpty ? '' : ' goal=$goal'}'
        '${week.isEmpty ? '' : ' week=$week'} exercises=${exercises.length}',
      );
      for (final rawExercise in exercises) {
        final exercise = Map<String, dynamic>.from(rawExercise);
        final name = _text(exercise['name'], fallback: 'Esercizio');
        final sets = _text(exercise['set']);
        final reps = _repRange(exercise);
        final weight = _text(exercise['weight']);
        final rest = _text(exercise['restSeconds']);
        final technique = _text(exercise['technique']);
        final parts = <String>[
          if (sets.isNotEmpty) 'sets=$sets',
          if (reps.isNotEmpty) 'reps=$reps',
          if (weight.isNotEmpty) 'kg=$weight',
          if (rest.isNotEmpty) 'rest=${rest}s',
          if (technique.isNotEmpty && technique != 'none') 'tech=$technique',
        ];
        lines.add('EX $name${parts.isEmpty ? '' : ' | ${parts.join(' ')}'}');
      }
    }
    return lines;
  }

  String _repRange(Map<String, dynamic> exercise) {
    final min = _text(exercise['targetMinReps']);
    final max = _text(exercise['targetMaxReps']);
    if (min.isNotEmpty && max.isNotEmpty) {
      return min == max ? min : '$min-$max';
    }
    return _text(exercise['reps']);
  }

  List<String> _verifiedLines(Map<String, dynamic> context) {
    final raw = context['verified_evidence'];
    if (raw is! Map || raw.isEmpty) return const [];
    final evidence = Map<String, dynamic>.from(raw);
    final lines = <String>[];
    final coverage = evidence['coverage'];
    if (coverage is Map && coverage.isNotEmpty) {
      lines.add('FACT coverage=${_compactJson(coverage, stringLimit: 64)}');
    }
    for (final key in const [
      'strength',
      'volume_frequency',
      'progression',
      'readiness',
    ]) {
      final value = evidence[key];
      if (value == null) continue;
      lines.add(
        'FACT $key=${_compactJson(value, stringLimit: 72, listLimit: 4)}',
      );
    }
    return lines;
  }

  List<String> _analyticsLines(Map<String, dynamic> context) {
    final raw = context['deterministic_analytics'];
    if (raw is! Map || raw.isEmpty) return const [];
    final analytics = Map<String, dynamic>.from(raw);
    final lines = <String>[];
    for (final key in const [
      'fatigue_readiness',
      'progression_recommendations',
      'progress_analytics',
      'exercise_progress',
      'latest_session_at',
      'session_count',
    ]) {
      if (!analytics.containsKey(key)) continue;
      lines.add(
        'AN $key=${_compactJson(analytics[key], stringLimit: 72, listLimit: 3)}',
      );
    }
    return lines;
  }

  List<String> _workoutLines(
    Map<String, dynamic> context, {
    required AiCoachChatIntent intent,
  }) {
    final workouts = (context['workouts'] as List? ?? const <dynamic>[])
        .whereType<Map>()
        .toList();
    if (workouts.isEmpty) return const [];
    final take = intent == AiCoachChatIntent.progression ||
            intent == AiCoachChatIntent.progress
        ? 4
        : 3;
    final selected = workouts.length <= take
        ? workouts
        : workouts.sublist(workouts.length - take);
    final lines = <String>[];
    for (final rawWorkout in selected) {
      final workout = Map<String, dynamic>.from(rawWorkout);
      final date = _shortDate(_text(workout['start_time']));
      final name = _text(workout['name'], fallback: 'Allenamento');
      lines.add('SESSION $date $name');
      final exercises = (workout['exercises'] as List? ?? const <dynamic>[])
          .whereType<Map>()
          .take(8);
      for (final rawExercise in exercises) {
        final exercise = Map<String, dynamic>.from(rawExercise);
        final exerciseName = _text(exercise['name'], fallback: 'Esercizio');
        final sets = (exercise['sets'] as List? ?? const <dynamic>[])
            .whereType<Map>()
            .where((set) => set['completed'] == true && set['warmup'] != true)
            .take(5)
            .map(_compactSet)
            .where((value) => value.isNotEmpty)
            .toList();
        if (sets.isNotEmpty) {
          lines.add('DO $exerciseName: ${sets.join(',')}');
        }
      }
    }
    return lines;
  }

  String _compactSet(Map rawSet) {
    final set = Map<String, dynamic>.from(rawSet);
    final weight = _text(set['weight']);
    final reps = _text(set['reps']);
    if (weight.isEmpty && reps.isEmpty) return '';
    final effort = <String>[];
    final rir = _text(set['rir']);
    final rpe = _text(set['rpe']);
    if (rir.isNotEmpty) effort.add('RIR$rir');
    if (rpe.isNotEmpty) effort.add('RPE$rpe');
    return '$weight${weight.isNotEmpty && reps.isNotEmpty ? 'x' : ''}$reps'
        '${effort.isEmpty ? '' : '@${effort.join('/')}'}';
  }

  List<String> _bodyLogLines(Map<String, dynamic> context) {
    final logs = (context['body_logs'] as List? ?? const <dynamic>[])
        .whereType<Map>()
        .toList();
    if (logs.isEmpty) return const [];
    final selected = logs.length <= 3 ? logs : logs.sublist(logs.length - 3);
    return selected.map((rawLog) {
      final log = Map<String, dynamic>.from(rawLog);
      final fields = <String>[
        if (_text(log['bodyWeight']).isNotEmpty)
          'kg=${_text(log['bodyWeight'])}',
        if (_text(log['sleepHours']).isNotEmpty)
          'sleep=${_text(log['sleepHours'])}h',
        if (_text(log['readiness']).isNotEmpty)
          'readiness=${_text(log['readiness'])}',
      ];
      final notes = _text(log['notes']);
      if (notes.isNotEmpty) fields.add('note=${_clip(notes, 80)}');
      return 'BODY ${_shortDate(_text(log['date']))} ${fields.join(' ')}'.trim();
    }).toList();
  }

  List<String> _profileLines(Map<String, dynamic> context) {
    final raw = context['user_profile'];
    if (raw is! Map || raw.isEmpty) return const [];
    final compact = _compactNamedFields(raw, const [
      'experienceLevel',
      'primaryGoal',
      'daysAvailable',
      'sessionMinutes',
      'equipment',
      'preferredExercises',
      'avoidedExercises',
      'limitations',
      'notes',
      'experience_level',
      'primary_goal',
      'days_available',
      'session_minutes',
    ]);
    return compact.isEmpty ? const [] : ['PROFILE $compact'];
  }

  List<String> _memoryLines(Map<String, dynamic> context) {
    final raw = context['memory'];
    if (raw is! Map || raw.isEmpty) return const [];
    return ['MEMORY ${_compactJson(raw, stringLimit: 80, listLimit: 4)}'];
  }

  List<String> _catalogLines(Map<String, dynamic> context) {
    final raw = context['exercise_catalog'];
    if (raw is! Map || raw.isEmpty) return const [];
    final catalog = Map<String, dynamic>.from(raw);
    final matches = (catalog['matches'] as List? ?? const <dynamic>[])
        .whereType<Map>()
        .take(3);
    final lines = <String>[];
    for (final rawMatch in matches) {
      final match = Map<String, dynamic>.from(rawMatch);
      final id = _text(match['catalog_id']);
      final name = _text(match['name']);
      final target = _text(match['target']);
      final equipment = _text(match['equipment']);
      final instructions = (match['instructions'] as List? ?? const <dynamic>[])
          .map((value) => _clip(value.toString(), 96))
          .take(3)
          .join(' / ');
      lines.add(
        'CAT ${id.isEmpty ? name : id}${name.isEmpty ? '' : ' name=$name'}'
        '${target.isEmpty ? '' : ' target=$target'}'
        '${equipment.isEmpty ? '' : ' equipment=$equipment'}'
        '${instructions.isEmpty ? '' : ' cues=$instructions'}',
      );
    }
    return lines;
  }

  String _compactNamedFields(Map raw, List<String> keys) {
    final parts = <String>[];
    for (final key in keys) {
      if (!raw.containsKey(key)) continue;
      final value = _text(raw[key]);
      if (value.isEmpty || value == '[]' || value == '{}') continue;
      parts.add('$key=${_clip(value, 96)}');
    }
    return parts.join(' ');
  }

  String _compactJson(
    Object? value, {
    int stringLimit = 80,
    int listLimit = 4,
    int mapLimit = 14,
  }) {
    final clipped = _clipValue(
      value,
      stringLimit: stringLimit,
      listLimit: listLimit,
      mapLimit: mapLimit,
      depth: 0,
    );
    return jsonEncode(clipped);
  }

  Object? _clipValue(
    Object? value, {
    required int stringLimit,
    required int listLimit,
    required int mapLimit,
    required int depth,
  }) {
    if (depth >= 6) return '<cut>';
    if (value is String) return _clip(value, stringLimit);
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

  String _fitLines(List<String> lines, int budget) {
    final buffer = StringBuffer();
    for (final rawLine in lines) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;
      final separator = buffer.isEmpty ? '' : '\n';
      final needed = separator.length + line.length;
      if (buffer.length + needed <= budget) {
        buffer.write(separator);
        buffer.write(line);
        continue;
      }

      final remaining = budget - buffer.length - separator.length;
      if (remaining >= 24) {
        buffer.write(separator);
        buffer.write(_clip(line, remaining));
      }
      break;
    }
    return buffer.toString();
  }

  AiCoachContextCapsuleDiagnostics _diagnostics({
    required String encoded,
    required int budget,
    required Map<String, dynamic> context,
    required bool userDataAvailable,
    required bool referenceDataAvailable,
  }) {
    final plans = (context['active_plans'] as List? ?? const <dynamic>[])
        .whereType<Map>()
        .toList();
    final planTitles = <String>[];
    final exerciseNames = <String>[];
    for (final rawPlan in plans.take(3)) {
      final plan = Map<String, dynamic>.from(rawPlan);
      final title = _text(plan['title']);
      if (title.isNotEmpty) planTitles.add(title);
      for (final rawExercise
          in (plan['exercises'] as List? ?? const <dynamic>[]).whereType<Map>()) {
        final name = _text(rawExercise['name']);
        if (name.isNotEmpty && exerciseNames.length < 16) {
          exerciseNames.add(name);
        }
      }
    }
    return AiCoachContextCapsuleDiagnostics(
      encodedChars: encoded.length,
      budgetChars: budget,
      userDataAvailable: userDataAvailable,
      referenceDataAvailable: referenceDataAvailable,
      activePlanCount: plans.length,
      workoutCount:
          (context['workouts'] as List? ?? const <dynamic>[]).length,
      bodyLogCount:
          (context['body_logs'] as List? ?? const <dynamic>[]).length,
      planTitles: planTitles,
      exerciseNames: exerciseNames,
    );
  }

  String _shortDate(String value) {
    if (value.length >= 10) return value.substring(0, 10);
    return value;
  }

  String _text(Object? value, {String fallback = ''}) {
    if (value == null) return fallback;
    final text = value.toString().trim();
    return text.isEmpty || text == 'null' ? fallback : text;
  }

  String _clip(String value, int limit) {
    if (limit <= 1) return value.isEmpty ? '' : value.substring(0, 1);
    if (value.length <= limit) return value;
    return '${value.substring(0, limit - 1)}…';
  }
}
