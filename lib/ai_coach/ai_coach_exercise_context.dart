import 'ai_coach_context_router.dart';

class AiCoachExerciseCandidate {
  final String name;
  final String? sourceExerciseId;
  final String? catalogId;

  const AiCoachExerciseCandidate({
    required this.name,
    this.sourceExerciseId,
    this.catalogId,
  });
}

class AiCoachExerciseFocus {
  final List<String> names;
  final Set<String> sourceExerciseIds;
  final Set<String> catalogIds;
  final List<String> matchedTerms;

  const AiCoachExerciseFocus({
    required this.names,
    required this.sourceExerciseIds,
    required this.catalogIds,
    required this.matchedTerms,
  });

  String get primaryName => names.isEmpty ? '' : names.first;

  Map<String, dynamic> toJson() => {
        'source': 'deterministic_exercise_mention_resolution',
        'primary_name': primaryName,
        'names': names,
        'source_exercise_ids': sourceExerciseIds.toList()..sort(),
        'catalog_ids': catalogIds.toList()..sort(),
        'matched_terms': matchedTerms,
        'contract': {
          'scope_only_when_unambiguous': true,
          'fallback_to_broad_context_when_ambiguous': true,
        },
      };
}

class AiCoachExerciseContextResolver {
  const AiCoachExerciseContextResolver();

  AiCoachExerciseFocus? resolve({
    required String query,
    required Iterable<AiCoachExerciseCandidate> candidates,
  }) {
    final queryNormalized = _normalize(query);
    if (queryNormalized.isEmpty) return null;

    final entities = _groupCandidates(candidates);
    if (entities.isEmpty) return null;

    final queryTokens = _focusTokens(queryNormalized);
    if (queryTokens.isEmpty) return null;

    final scored = <_ScoredEntity>[];
    for (final entity in entities) {
      final entityTokens = <String>{
        for (final name in entity.names) ..._focusTokens(_normalize(name)),
      };
      final matched = queryTokens.intersection(entityTokens);
      final exactPhrase = entity.names.any((name) {
        final normalizedName = _normalize(name);
        return normalizedName.split(' ').length >= 2 &&
            _containsPhrase(queryNormalized, normalizedName);
      });
      if (matched.isEmpty && !exactPhrase) continue;

      scored.add(
        _ScoredEntity(
          entity: entity,
          matched: matched,
          exactPhrase: exactPhrase,
        ),
      );
    }

    if (scored.isEmpty) return null;
    scored.sort((a, b) {
      if (a.exactPhrase != b.exactPhrase) return a.exactPhrase ? -1 : 1;
      final count = b.matched.length.compareTo(a.matched.length);
      if (count != 0) return count;
      return a.entity.primaryName.compareTo(b.entity.primaryName);
    });

    final best = scored.first;
    final tied = scored.where((candidate) {
      return candidate.exactPhrase == best.exactPhrase &&
          candidate.matched.length == best.matched.length;
    }).toList();

    if (best.exactPhrase && tied.length == 1) {
      return best.toFocus();
    }

    if (best.matched.length >= 2 && tied.length == 1) {
      return best.toFocus();
    }

    if (best.matched.length == 1 && scored.length == 1) {
      final onlyTerm = best.matched.single;
      if (_strongSingleExerciseTerms.contains(onlyTerm)) {
        return best.toFocus();
      }
    }

    return null;
  }

  List<_ExerciseEntity> _groupCandidates(
    Iterable<AiCoachExerciseCandidate> candidates,
  ) {
    final grouped = <String, _ExerciseEntityBuilder>{};
    for (final candidate in candidates) {
      final name = candidate.name.trim();
      if (name.isEmpty) continue;
      final catalogId = candidate.catalogId?.trim();
      final sourceId = candidate.sourceExerciseId?.trim();
      final key = catalogId != null && catalogId.isNotEmpty
          ? 'catalog:$catalogId'
          : sourceId != null && sourceId.isNotEmpty
              ? 'source:$sourceId'
              : 'name:${_normalize(name)}';
      final builder = grouped.putIfAbsent(key, _ExerciseEntityBuilder.new);
      builder.names.add(name);
      if (catalogId != null && catalogId.isNotEmpty) {
        builder.catalogIds.add(catalogId);
      }
      if (sourceId != null && sourceId.isNotEmpty) {
        builder.sourceExerciseIds.add(sourceId);
      }
    }

    return grouped.values.map((builder) => builder.build()).toList();
  }
}

class AiCoachExerciseContextFilter {
  const AiCoachExerciseContextFilter();

  Map<String, dynamic> apply(
    Map<String, dynamic> source, {
    required AiCoachExerciseFocus focus,
    required AiCoachChatIntent intent,
  }) {
    final result = Map<String, dynamic>.from(source);
    result['exercise_focus'] = focus.toJson();

    result['workouts'] = _filterWorkouts(result['workouts'], focus);
    result['notes'] = _filterNotes(result['notes'], focus);

    if (intent != AiCoachChatIntent.program) {
      result['active_plans'] = _filterPlans(result['active_plans'], focus);
    }

    final metrics = _map(result['metrics']);
    if (metrics.isNotEmpty) {
      final exerciseVolume = _map(metrics['exercise_volume']);
      exerciseVolume.removeWhere((name, _) => !_matchesName(name, focus));
      result['metrics'] = {
        'sessions_containing_exercise':
            (result['workouts'] as List?)?.length ?? 0,
        if (exerciseVolume.isNotEmpty) 'exercise_volume': exerciseVolume,
      };
    }

    final analytics = _map(result['deterministic_analytics']);
    if (analytics.isNotEmpty) {
      final exerciseProgress = _map(analytics['exercise_progress']);
      exerciseProgress.removeWhere((name, _) => !_matchesName(name, focus));
      if (exerciseProgress.isEmpty) {
        analytics.remove('exercise_progress');
      } else {
        analytics['exercise_progress'] = exerciseProgress;
      }

      final recommendations = _list(analytics['progression_recommendations'])
          .where((item) {
            if (item is! Map) return false;
            return _matchesName(item['exercise']?.toString() ?? '', focus);
          })
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList();
      if (recommendations.isEmpty) {
        analytics.remove('progression_recommendations');
      } else {
        analytics['progression_recommendations'] = recommendations;
      }

      final progressAnalytics = _map(analytics['progress_analytics']);
      if (progressAnalytics.isNotEmpty) {
        final exercises = _filterNamedList(
          progressAnalytics['exercises'],
          focus,
          key: 'exercise',
        );
        final records = _filterNamedList(
          progressAnalytics['personal_records'],
          focus,
          key: 'exercise',
        );
        analytics['progress_analytics'] = {
          if (exercises.isNotEmpty) 'exercises': exercises,
          if (records.isNotEmpty) 'personal_records': records,
        };
      }

      result['deterministic_analytics'] = analytics;
    }

    final catalog = _map(result['exercise_catalog']);
    if (catalog.isNotEmpty && focus.catalogIds.isNotEmpty) {
      final matches = _list(catalog['matches'])
          .where((item) {
            if (item is! Map) return false;
            final id = item['catalog_id']?.toString() ?? '';
            return focus.catalogIds.contains(id);
          })
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList();
      if (matches.isNotEmpty) {
        catalog['matches'] = matches;
        catalog['result_count'] = matches.length;
        result['exercise_catalog'] = catalog;
      }
    }

    return result;
  }

  List<dynamic> _filterWorkouts(Object? raw, AiCoachExerciseFocus focus) {
    final output = <dynamic>[];
    for (final item in _list(raw)) {
      if (item is! Map) continue;
      final workout = Map<String, dynamic>.from(item);
      final exercises = _list(workout['exercises'])
          .where((exercise) => exercise is Map && _matchesExercise(exercise, focus))
          .map((exercise) => Map<String, dynamic>.from(exercise as Map))
          .toList();
      if (exercises.isEmpty) continue;
      workout['exercises'] = exercises;
      output.add(workout);
    }
    return output;
  }

  List<dynamic> _filterPlans(Object? raw, AiCoachExerciseFocus focus) {
    final output = <dynamic>[];
    for (final item in _list(raw)) {
      if (item is! Map) continue;
      final plan = Map<String, dynamic>.from(item);
      final exercises = _list(plan['exercises'])
          .where((exercise) => exercise is Map && _matchesExercise(exercise, focus))
          .map((exercise) => Map<String, dynamic>.from(exercise as Map))
          .toList();
      if (exercises.isEmpty) continue;
      plan['exercises'] = exercises;
      output.add(plan);
    }
    return output;
  }

  List<dynamic> _filterNotes(Object? raw, AiCoachExerciseFocus focus) {
    return _list(raw).where((item) {
      final text = item?.toString() ?? '';
      final separator = text.indexOf(':');
      final exerciseName = separator < 0 ? text : text.substring(0, separator);
      return _matchesName(exerciseName, focus);
    }).toList();
  }

  List<Map<String, dynamic>> _filterNamedList(
    Object? raw,
    AiCoachExerciseFocus focus, {
    required String key,
  }) {
    return _list(raw)
        .where((item) {
          if (item is! Map) return false;
          return _matchesName(item[key]?.toString() ?? '', focus);
        })
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();
  }

  bool _matchesExercise(Map exercise, AiCoachExerciseFocus focus) {
    final sourceId = (exercise['source_exercise_id'] ??
            exercise['sourceExerciseId'] ??
            exercise['id'])
        ?.toString();
    if (sourceId != null && focus.sourceExerciseIds.contains(sourceId)) {
      return true;
    }

    final catalogId =
        (exercise['catalog_id'] ?? exercise['catalogId'])?.toString();
    if (catalogId != null && focus.catalogIds.contains(catalogId)) {
      return true;
    }

    return _matchesName(exercise['name']?.toString() ?? '', focus);
  }

  bool _matchesName(String value, AiCoachExerciseFocus focus) {
    final normalized = _normalize(value);
    return focus.names.any((name) => _normalize(name) == normalized);
  }

  Map<String, dynamic> _map(Object? raw) {
    if (raw is! Map) return <String, dynamic>{};
    return Map<String, dynamic>.from(raw);
  }

  List<dynamic> _list(Object? raw) =>
      raw is List ? List<dynamic>.from(raw) : const <dynamic>[];
}

class _ExerciseEntityBuilder {
  final Set<String> names = {};
  final Set<String> sourceExerciseIds = {};
  final Set<String> catalogIds = {};

  _ExerciseEntity build() {
    final sortedNames = names.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return _ExerciseEntity(
      names: sortedNames,
      sourceExerciseIds: Set<String>.from(sourceExerciseIds),
      catalogIds: Set<String>.from(catalogIds),
    );
  }
}

class _ExerciseEntity {
  final List<String> names;
  final Set<String> sourceExerciseIds;
  final Set<String> catalogIds;

  const _ExerciseEntity({
    required this.names,
    required this.sourceExerciseIds,
    required this.catalogIds,
  });

  String get primaryName => names.first;
}

class _ScoredEntity {
  final _ExerciseEntity entity;
  final Set<String> matched;
  final bool exactPhrase;

  const _ScoredEntity({
    required this.entity,
    required this.matched,
    required this.exactPhrase,
  });

  AiCoachExerciseFocus toFocus() => AiCoachExerciseFocus(
        names: entity.names,
        sourceExerciseIds: entity.sourceExerciseIds,
        catalogIds: entity.catalogIds,
        matchedTerms: matched.toList()..sort(),
      );
}

String _normalize(String value) {
  var normalized = value.toLowerCase();
  const replacements = {
    'à': 'a',
    'á': 'a',
    'è': 'e',
    'é': 'e',
    'ì': 'i',
    'í': 'i',
    'ò': 'o',
    'ó': 'o',
    'ù': 'u',
    'ú': 'u',
  };
  for (final entry in replacements.entries) {
    normalized = normalized.replaceAll(entry.key, entry.value);
  }
  normalized = normalized
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  return normalized;
}

bool _containsPhrase(String input, String phrase) {
  if (phrase.isEmpty) return false;
  return ' $input '.contains(' $phrase ');
}

Set<String> _focusTokens(String normalized) {
  var input = normalized;
  for (final entry in _phraseAliases.entries) {
    input = input.replaceAll(entry.key, entry.value);
  }
  final output = <String>{};
  for (final raw in input.split(' ')) {
    if (raw.isEmpty) continue;
    final canonical = _tokenAliases[raw] ?? raw;
    if (_ignoredFocusTokens.contains(canonical)) continue;
    output.add(canonical);
  }
  return output;
}

const Map<String, String> _phraseAliases = {
  'pull up': ' pullup ',
  'pull ups': ' pullup ',
  'lat machine': ' latpulldown ',
  'lat pulldown': ' latpulldown ',
  'military press': ' overheadpress ',
  'overhead press': ' overheadpress ',
  'leg press': ' legpress ',
  'hip thrust': ' hipthrust ',
  'lateral raise': ' lateralraise ',
  'lateral raises': ' lateralraise ',
  'alzate laterali': ' lateralraise ',
};

const Map<String, String> _tokenAliases = {
  'panca': 'bench',
  'bench': 'bench',
  'piana': 'flat',
  'flat': 'flat',
  'inclinata': 'incline',
  'inclinato': 'incline',
  'incline': 'incline',
  'inclined': 'incline',
  'manubri': 'dumbbell',
  'manubrio': 'dumbbell',
  'dumbbell': 'dumbbell',
  'dumbbells': 'dumbbell',
  'bilanciere': 'barbell',
  'barbell': 'barbell',
  'stacco': 'deadlift',
  'stacchi': 'deadlift',
  'deadlift': 'deadlift',
  'rematore': 'row',
  'rematori': 'row',
  'row': 'row',
  'rows': 'row',
  'trazioni': 'pullup',
  'trazione': 'pullup',
  'pullup': 'pullup',
  'pulldown': 'latpulldown',
  'curl': 'curl',
  'affondi': 'lunge',
  'affondo': 'lunge',
  'lunge': 'lunge',
  'lunges': 'lunge',
  'croci': 'fly',
  'fly': 'fly',
  'flyes': 'fly',
  'squat': 'squat',
};

const Set<String> _ignoredFocusTokens = {
  'come',
  'sto',
  'sta',
  'stanno',
  'andando',
  'andata',
  'andamento',
  'mio',
  'mia',
  'mie',
  'miei',
  'il',
  'lo',
  'la',
  'i',
  'gli',
  'le',
  'un',
  'una',
  'con',
  'sulla',
  'sul',
  'della',
  'del',
  'di',
  'per',
  'in',
  'the',
  'my',
  'how',
  'is',
  'going',
  'progress',
  'progressi',
  'progressione',
  'tecnica',
  'esecuzione',
  'peso',
  'kg',
  'reps',
  'ripetizioni',
  'petto',
  'chest',
  'schiena',
  'dorso',
  'back',
  'spalle',
  'shoulders',
  'gambe',
  'legs',
  'quadricipiti',
  'quadriceps',
  'bicipiti',
  'biceps',
  'tricipiti',
  'triceps',
  'glutei',
  'glutes',
};

const Set<String> _strongSingleExerciseTerms = {
  'bench',
  'squat',
  'deadlift',
  'row',
  'pullup',
  'latpulldown',
  'curl',
  'legpress',
  'lunge',
  'hipthrust',
  'lateralraise',
  'fly',
};
