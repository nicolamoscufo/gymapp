import '../exercise_catalog.dart';
import '../models/exercise.dart';

typedef ExerciseCatalogLoader = Future<List<ExerciseCatalogEntry>> Function();

enum ExerciseCatalogRetrievalMode { question, programDraft }

class ExerciseCatalogMatch {
  final ExerciseCatalogEntry entry;
  final double score;

  const ExerciseCatalogMatch({required this.entry, required this.score});

  Map<String, dynamic> toContextJson({required bool includeInstructions}) => {
    'catalog_id': entry.id,
    'name': entry.name,
    'muscle_group': entry.muscleGroup.name,
    'equipment': entry.equipment,
    'movement_pattern': entry.movementPattern,
    'body_part': entry.bodyPart,
    'target': entry.target,
    'secondary_muscles': entry.secondaryMuscles,
    if (includeInstructions)
      'instructions': entry.instructions.take(6).toList(),
  };
}

class ExerciseCatalogContext {
  final String query;
  final ExerciseCatalogRetrievalMode mode;
  final List<ExerciseCatalogMatch> matches;

  const ExerciseCatalogContext({
    required this.query,
    required this.mode,
    required this.matches,
  });

  bool get isEmpty => matches.isEmpty;

  Map<String, dynamic> toJson() => {
    'source': 'local_exercise_catalog',
    'query': query,
    'retrieval_mode': mode.name,
    'result_count': matches.length,
    'matches': matches
        .map(
          (match) => match.toContextJson(
            includeInstructions: mode == ExerciseCatalogRetrievalMode.question,
          ),
        )
        .toList(),
    'contract': {
      'results_are_retrieved_not_exhaustive': true,
      'catalog_metadata_is_authoritative_for_catalog_fields': true,
      'user_training_data_remains_separate': true,
    },
  };
}

class ExerciseCatalogRetriever {
  final ExerciseCatalogLoader? catalogLoader;

  const ExerciseCatalogRetriever({this.catalogLoader});

  Future<ExerciseCatalogContext> retrieveForQuestion({
    required String query,
    Iterable<String> preferredExerciseNames = const [],
    int limit = 8,
  }) async {
    final catalog = await _load();
    final matches = _rank(
      catalog,
      query: query,
      preferredExerciseNames: preferredExerciseNames,
      mode: ExerciseCatalogRetrievalMode.question,
      limit: limit,
    );
    return ExerciseCatalogContext(
      query: query.trim(),
      mode: ExerciseCatalogRetrievalMode.question,
      matches: matches,
    );
  }

  Future<ExerciseCatalogContext> retrieveForProgram({
    required String query,
    Iterable<String> preferredExerciseNames = const [],
    int limit = 28,
  }) async {
    final catalog = await _load();
    final matches = _rank(
      catalog,
      query: query,
      preferredExerciseNames: preferredExerciseNames,
      mode: ExerciseCatalogRetrievalMode.programDraft,
      limit: limit,
    );
    return ExerciseCatalogContext(
      query: query.trim(),
      mode: ExerciseCatalogRetrievalMode.programDraft,
      matches: matches,
    );
  }

  Future<ExerciseCatalogEntry?> byId(String catalogId) async {
    final id = catalogId.trim();
    if (id.isEmpty) return null;
    final catalog = await _load();
    for (final entry in catalog) {
      if (entry.id == id) return entry;
    }
    return null;
  }

  Future<ExerciseCatalogEntry?> resolveExercise({
    required String name,
    String equipment = '',
    MuscleGroup? muscleGroup,
  }) async {
    final catalog = await _load();
    final normalizedName = _normalize(name);
    if (normalizedName.isEmpty) return null;

    for (final entry in catalog) {
      if (_normalize(entry.name) == normalizedName) return entry;
    }

    final requestedNameTokens = _tokens(normalizedName);
    if (requestedNameTokens.isEmpty) return null;

    final candidates = <({ExerciseCatalogEntry entry, double overlap, double score})>[];
    for (final entry in catalog) {
      final entryNameTokens = _tokens(entry.name);
      final union = {...requestedNameTokens, ...entryNameTokens};
      if (union.isEmpty) continue;
      final intersection = requestedNameTokens.intersection(entryNameTokens);
      final overlap = intersection.length / union.length;
      if (overlap < 0.60) continue;

      var score = overlap * 100;
      if (equipment.trim().isNotEmpty &&
          _normalize(entry.equipment).contains(_normalize(equipment))) {
        score += 18;
      }
      if (muscleGroup != null &&
          muscleGroup != MuscleGroup.unassigned &&
          entry.muscleGroup == muscleGroup) {
        score += 18;
      }
      candidates.add((entry: entry, overlap: overlap, score: score));
    }

    candidates.sort((a, b) => b.score.compareTo(a.score));
    if (candidates.isEmpty) return null;
    final best = candidates.first;
    final secondScore = candidates.length > 1 ? candidates[1].score : 0.0;
    final separated = best.score - secondScore >= 10;
    if (best.overlap >= 0.80 || (best.overlap >= 0.67 && separated)) {
      return best.entry;
    }
    return null;
  }

  Future<List<ExerciseCatalogEntry>> _load() {
    final loader = catalogLoader;
    return loader != null ? loader() : loadExerciseCatalog();
  }

  List<ExerciseCatalogMatch> _rank(
    List<ExerciseCatalogEntry> catalog, {
    required String query,
    required Iterable<String> preferredExerciseNames,
    required ExerciseCatalogRetrievalMode mode,
    required int limit,
  }) {
    if (limit <= 0) return const [];
    final normalizedQuery = _normalize(query);
    if (normalizedQuery.isEmpty) return const [];

    final queryTerms = _expandedTerms(normalizedQuery, mode: mode);
    final preferred = preferredExerciseNames
        .map(_normalize)
        .where((value) => value.isNotEmpty)
        .toSet();

    final scored = <ExerciseCatalogMatch>[];
    for (final entry in catalog) {
      final score = _scoreEntry(
        entry,
        normalizedQuery: normalizedQuery,
        queryTerms: queryTerms,
        preferredExerciseNames: preferred,
      );
      if (score > 0) {
        scored.add(ExerciseCatalogMatch(entry: entry, score: score));
      }
    }

    scored.sort((a, b) {
      final scoreOrder = b.score.compareTo(a.score);
      if (scoreOrder != 0) return scoreOrder;
      return a.entry.name.toLowerCase().compareTo(b.entry.name.toLowerCase());
    });

    if (mode == ExerciseCatalogRetrievalMode.question) {
      return scored.take(limit).toList();
    }

    // Program generation benefits from a diversified shortlist instead of 20
    // near-duplicates for one muscle. Keep ranking deterministic while capping
    // each mapped muscle group before filling any remaining slots.
    final diversified = <ExerciseCatalogMatch>[];
    final perGroup = <MuscleGroup, int>{};
    for (final match in scored) {
      final group = match.entry.muscleGroup;
      final count = perGroup[group] ?? 0;
      if (count >= 4) continue;
      diversified.add(match);
      perGroup[group] = count + 1;
      if (diversified.length == limit) break;
    }
    if (diversified.length < limit) {
      for (final match in scored) {
        if (diversified.any((item) => item.entry.id == match.entry.id)) continue;
        diversified.add(match);
        if (diversified.length == limit) break;
      }
    }
    return diversified;
  }

  double _scoreEntry(
    ExerciseCatalogEntry entry, {
    required String normalizedQuery,
    required Set<String> queryTerms,
    required Set<String> preferredExerciseNames,
  }) {
    final name = _normalize(entry.name);
    final target = _normalize(entry.target);
    final bodyPart = _normalize(entry.bodyPart);
    final equipment = _normalize(entry.equipment);
    final movement = _normalize(entry.movementPattern);
    final groupName = _normalize(entry.muscleGroup.name);
    final groupLabel = _normalize(entry.muscleGroup.label);
    final secondary = entry.secondaryMuscles.map(_normalize).join(' ');

    var score = 0.0;
    if (name == normalizedQuery) score += 240;
    if (normalizedQuery.length >= 4 && name.contains(normalizedQuery)) score += 100;
    if (normalizedQuery.length >= 4 && normalizedQuery.contains(name)) score += 70;

    final preferredMentioned = preferredExerciseNames.any(
      (preferredName) =>
          preferredName == name && normalizedQuery.contains(preferredName),
    );
    if (preferredMentioned) score += 90;

    var matchedTerms = 0;
    for (final term in queryTerms) {
      if (term.length < 2) continue;
      var matched = false;
      if (_fieldContains(name, term)) {
        score += 28;
        matched = true;
      }
      if (_fieldContains(target, term)) {
        score += 20;
        matched = true;
      }
      if (_fieldContains(groupName, term) || _fieldContains(groupLabel, term)) {
        score += 20;
        matched = true;
      }
      if (_fieldContains(bodyPart, term)) {
        score += 18;
        matched = true;
      }
      if (_fieldContains(equipment, term)) {
        score += 18;
        matched = true;
      }
      if (_fieldContains(movement, term)) {
        score += 14;
        matched = true;
      }
      if (_fieldContains(secondary, term)) {
        score += 10;
        matched = true;
      }
      if (matched) matchedTerms += 1;
    }

    if (queryTerms.isNotEmpty && matchedTerms == queryTerms.length) score += 35;
    return score;
  }
}

Set<String> _expandedTerms(
  String normalizedQuery, {
  required ExerciseCatalogRetrievalMode mode,
}) {
  final rawTokens = _tokens(normalizedQuery);
  final expanded = <String>{...rawTokens};
  for (final token in rawTokens) {
    expanded.addAll(_aliases[token] ?? const <String>[]);
  }

  void addAll(Iterable<String> values) {
    for (final value in values) {
      expanded
        ..add(_normalize(value))
        ..addAll(_aliases[_normalize(value)] ?? const <String>[]);
    }
  }

  if (normalizedQuery.contains('upper') ||
      normalizedQuery.contains('parte superiore')) {
    addAll(['chest', 'back', 'shoulders', 'biceps', 'triceps']);
  }
  if (normalizedQuery.contains('lower') ||
      normalizedQuery.contains('parte inferiore')) {
    addAll(['quadriceps', 'hamstrings', 'glutes', 'calves']);
  }
  if (normalizedQuery.contains('full body') ||
      normalizedQuery.contains('total body') ||
      normalizedQuery.contains('corpo intero')) {
    addAll([
      'chest',
      'back',
      'shoulders',
      'quadriceps',
      'hamstrings',
      'glutes',
      'biceps',
      'triceps',
    ]);
  }

  if (mode == ExerciseCatalogRetrievalMode.programDraft &&
      expanded.length <= 3 &&
      RegExp(r'\b(scheda|programma|routine|split|program)\b')
          .hasMatch(normalizedQuery)) {
    addAll(['chest', 'back', 'shoulders', 'quadriceps', 'hamstrings', 'glutes']);
  }

  return expanded.where((term) => term.isNotEmpty).toSet();
}

const Map<String, Set<String>> _aliases = {
  'petto': {'chest', 'pectorals', 'pec'},
  'chest': {'petto', 'pectorals', 'pec'},
  'dorso': {'back', 'lats'},
  'schiena': {'back', 'lats'},
  'back': {'dorso', 'schiena', 'lats'},
  'spalle': {'shoulders', 'deltoid', 'delts'},
  'shoulders': {'spalle', 'deltoid', 'delts'},
  'bicipiti': {'biceps'},
  'biceps': {'bicipiti'},
  'tricipiti': {'triceps'},
  'triceps': {'tricipiti'},
  'quadricipiti': {'quadriceps', 'quads'},
  'quadriceps': {'quadricipiti', 'quads'},
  'femorali': {'hamstrings'},
  'hamstrings': {'femorali'},
  'glutei': {'glutes'},
  'glutes': {'glutei'},
  'polpacci': {'calves', 'calf'},
  'calves': {'polpacci', 'calf'},
  'addome': {'abs', 'core', 'abdominals'},
  'addominali': {'abs', 'core', 'abdominals'},
  'abs': {'addome', 'addominali', 'core'},
  'cavi': {'cable'},
  'cavo': {'cable'},
  'cable': {'cavi', 'cavo'},
  'manubri': {'dumbbell'},
  'manubrio': {'dumbbell'},
  'dumbbell': {'manubri', 'manubrio'},
  'bilanciere': {'barbell'},
  'barbell': {'bilanciere'},
  'macchina': {'machine'},
  'macchine': {'machine'},
  'machine': {'macchina', 'macchine'},
  'corpo': {'body'},
  'libero': {'weight'},
  'bodyweight': {'body', 'weight'},
  'tirata': {'pull'},
  'pull': {'tirata'},
  'spinta': {'push', 'press'},
  'push': {'spinta', 'press'},
};

bool _fieldContains(String field, String term) {
  if (field.isEmpty || term.isEmpty) return false;
  return field == term || field.contains(term);
}

Set<String> _tokens(String value) {
  return RegExp(r'[a-z0-9]+')
      .allMatches(_normalize(value))
      .map((match) => match.group(0)!)
      .where((token) => !_stopWords.contains(token))
      .toSet();
}

String _normalize(String value) {
  return value
      .trim()
      .toLowerCase()
      .replaceAll('à', 'a')
      .replaceAll('è', 'e')
      .replaceAll('é', 'e')
      .replaceAll('ì', 'i')
      .replaceAll('ò', 'o')
      .replaceAll('ù', 'u');
}

const Set<String> _stopWords = {
  'a',
  'ad',
  'ai',
  'al',
  'alla',
  'alle',
  'con',
  'da',
  'dei',
  'del',
  'della',
  'di',
  'e',
  'gli',
  'i',
  'il',
  'in',
  'la',
  'le',
  'lo',
  'mi',
  'per',
  'un',
  'una',
  'the',
  'for',
  'with',
  'and',
  'to',
  'of',
};
