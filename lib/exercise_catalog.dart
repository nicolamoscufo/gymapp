import 'dart:convert';

import 'package:flutter/services.dart';

import 'models/exercise.dart';

const exerciseCatalogAssetPath = 'esercizi2_en_fields_minified.json';

class ExerciseCatalogEntry {
  final String id;
  final String name;
  final MuscleGroup muscleGroup;
  final String equipment;
  final String movementPattern;
  final String bodyPart;
  final String target;
  final List<String> secondaryMuscles;
  final List<String> instructions;
  final String gifUrl;

  const ExerciseCatalogEntry({
    required this.id,
    required this.name,
    required this.muscleGroup,
    required this.equipment,
    required this.movementPattern,
    required this.bodyPart,
    required this.target,
    required this.secondaryMuscles,
    required this.instructions,
    required this.gifUrl,
  });

  factory ExerciseCatalogEntry.fromJson(Map<String, dynamic> json) {
    final bodyPart = json['bodyPart']?.toString().trim() ?? '';
    final target = json['target']?.toString().trim() ?? '';
    final secondaryMuscles = (json['secondaryMuscles'] as List? ?? const [])
        .map((value) => value.toString().trim())
        .where((value) => value.isNotEmpty)
        .toList();

    return ExerciseCatalogEntry(
      id: json['id']?.toString().trim() ?? '',
      name: json['name']?.toString().trim() ?? '',
      muscleGroup: muscleGroupFromCatalog(
        bodyPart: bodyPart,
        target: target,
        secondaryMuscles: secondaryMuscles,
      ),
      equipment: json['equipment']?.toString().trim() ?? '',
      movementPattern: _movementPatternFor(bodyPart: bodyPart, target: target),
      bodyPart: bodyPart,
      target: target,
      secondaryMuscles: secondaryMuscles,
      instructions: (json['instructions'] as List? ?? const [])
          .map((value) => value.toString().trim())
          .where((value) => value.isNotEmpty)
          .toList(),
      gifUrl: json['gifUrl']?.toString().trim() ?? '',
    );
  }

  String get subtitle {
    final parts = [
      if (target.isNotEmpty) target,
      if (equipment.isNotEmpty) equipment,
    ];
    return parts.join(' - ');
  }

  bool matches(String query) {
    final normalizedQuery = _normalize(query);
    if (normalizedQuery.isEmpty) {
      return true;
    }

    return _normalize(name).contains(normalizedQuery) ||
        _normalize(target).contains(normalizedQuery) ||
        _normalize(bodyPart).contains(normalizedQuery) ||
        _normalize(equipment).contains(normalizedQuery) ||
        secondaryMuscles.any(
          (muscle) => _normalize(muscle).contains(normalizedQuery),
        );
  }
}

List<ExerciseCatalogEntry>? _cachedExerciseCatalog;

Future<List<ExerciseCatalogEntry>> loadExerciseCatalog({
  AssetBundle? bundle,
}) async {
  if (bundle == null && _cachedExerciseCatalog != null) {
    return _cachedExerciseCatalog!;
  }

  final jsonText = await (bundle ?? rootBundle).loadString(
    exerciseCatalogAssetPath,
  );
  final catalog = parseExerciseCatalog(jsonText);

  if (bundle == null) {
    _cachedExerciseCatalog = catalog;
  }

  return catalog;
}

List<ExerciseCatalogEntry> parseExerciseCatalog(String jsonText) {
  final decoded = jsonDecode(jsonText) as List<dynamic>;
  final catalog = decoded
      .whereType<Map>()
      .map(
        (entry) =>
            ExerciseCatalogEntry.fromJson(Map<String, dynamic>.from(entry)),
      )
      .where((entry) => entry.name.isNotEmpty)
      .toList();

  catalog.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  return catalog;
}

ExerciseCatalogEntry? catalogEntryByName(
  Iterable<ExerciseCatalogEntry> catalog,
  String name,
) {
  final normalized = _normalize(name);
  for (final entry in catalog) {
    if (_normalize(entry.name) == normalized) {
      return entry;
    }
  }
  return null;
}

List<ExerciseCatalogEntry> filterExerciseCatalog(
  Iterable<ExerciseCatalogEntry> catalog, {
  required String query,
  MuscleGroup? muscleGroup,
  int limit = 30,
}) {
  final normalizedQuery = _normalize(query);
  final hasGroup = muscleGroup != null && muscleGroup != MuscleGroup.unassigned;
  final matches = catalog.where((entry) {
    final groupMatches = !hasGroup || entry.muscleGroup == muscleGroup;
    return groupMatches && entry.matches(query);
  }).toList();

  matches.sort((a, b) {
    if (normalizedQuery.isNotEmpty) {
      final aName = _normalize(a.name);
      final bName = _normalize(b.name);
      final aStarts = aName.startsWith(normalizedQuery);
      final bStarts = bName.startsWith(normalizedQuery);
      if (aStarts != bStarts) {
        return aStarts ? -1 : 1;
      }
    }

    return a.name.toLowerCase().compareTo(b.name.toLowerCase());
  });

  if (matches.length <= limit) {
    return matches;
  }
  return matches.take(limit).toList();
}

List<ExerciseCatalogEntry> suggestedCatalogEntries(
  Iterable<ExerciseCatalogEntry> catalog,
  MuscleGroup? muscleGroup, {
  int limit = 8,
}) {
  if (muscleGroup == null || muscleGroup == MuscleGroup.unassigned) {
    return const [];
  }

  return filterExerciseCatalog(
    catalog,
    query: '',
    muscleGroup: muscleGroup,
    limit: limit,
  );
}

MuscleGroup muscleGroupFromCatalog({
  required String bodyPart,
  required String target,
  required List<String> secondaryMuscles,
}) {
  final targetGroup = _muscleGroupForValues([target]);
  if (targetGroup != null) return targetGroup;

  final bodyPartGroup = _muscleGroupForValues([bodyPart]);
  if (bodyPartGroup != null) return bodyPartGroup;

  return _muscleGroupForValues(secondaryMuscles) ?? MuscleGroup.unassigned;
}

MuscleGroup? _muscleGroupForValues(Iterable<String> rawValues) {
  final values = rawValues.map(_normalize).toList();

  bool containsAny(List<String> needles) {
    return values.any((value) => needles.any(value.contains));
  }

  if (containsAny(['pec', 'pectoral', 'petto', 'chest', 'serratus anterior'])) {
    return MuscleGroup.chest;
  }
  if (containsAny([
    'lats',
    'latrat',
    'dorso',
    'schiena',
    'spina dorsale',
    'back',
    'spine',
  ])) {
    return MuscleGroup.back;
  }
  if (containsAny(['quad', 'quadruped'])) return MuscleGroup.quadriceps;
  if (containsAny([
    'hamstring',
    'tendini del ginocchio',
    'bicipiti femorali',
  ])) {
    return MuscleGroup.hamstrings;
  }
  if (containsAny(['glute'])) return MuscleGroup.glutes;
  if (containsAny(['calf', 'calves', 'polpacc'])) return MuscleGroup.calves;
  if (containsAny(['biceps', 'bicipit'])) return MuscleGroup.biceps;
  if (containsAny(['triceps', 'tricipit'])) return MuscleGroup.triceps;
  if (containsAny(['forearm', 'lower arms', 'avambracc', 'bracci inferiori'])) {
    return MuscleGroup.forearms;
  }
  if (containsAny(['upper arms', 'braccia superiori'])) return MuscleGroup.arms;
  if (containsAny(['delt', 'shoulder', 'spalle'])) return MuscleGroup.shoulders;
  if (containsAny(['traps', 'trappol'])) return MuscleGroup.traps;
  if (containsAny([
    'abs',
    'abdominal',
    'addominal',
    'waist',
    'obliqu',
    'core',
    'nucleo',
  ])) {
    return MuscleGroup.abs;
  }
  if (containsAny(['cardio', 'cardiovascular'])) return MuscleGroup.cardio;
  if (containsAny(['neck', 'levator scapulae', 'collo'])) {
    return MuscleGroup.neck;
  }
  if (containsAny([
    'adductor',
    'abductor',
    'adduttor',
    'rapitor',
    'upper legs',
  ])) {
    return MuscleGroup.legs;
  }

  return null;
}

String _movementPatternFor({required String bodyPart, required String target}) {
  final group = muscleGroupFromCatalog(
    bodyPart: bodyPart,
    target: target,
    secondaryMuscles: const [],
  );

  return switch (group) {
    MuscleGroup.chest => 'Spinta',
    MuscleGroup.back => 'Tirata',
    MuscleGroup.quadriceps ||
    MuscleGroup.hamstrings ||
    MuscleGroup.glutes ||
    MuscleGroup.calves ||
    MuscleGroup.legs => 'Gambe',
    MuscleGroup.biceps ||
    MuscleGroup.triceps ||
    MuscleGroup.arms ||
    MuscleGroup.forearms => 'Braccia',
    MuscleGroup.shoulders || MuscleGroup.traps => 'Spalle',
    MuscleGroup.abs => 'Core',
    MuscleGroup.cardio => 'Cardio',
    MuscleGroup.neck => 'Collo',
    MuscleGroup.unassigned => target,
  };
}

String _normalize(String value) {
  return value.trim().toLowerCase();
}
