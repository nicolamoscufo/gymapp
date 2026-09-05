import 'dart:convert';

import 'models/body_log.dart';
import 'models/exercise.dart';
import 'models/schedule.dart';
import 'models/schedule_version.dart';
import 'models/workout.dart';

/// A decoded persistence snapshot plus enough metadata for a caller to decide
/// whether optional collections were actually present in an imported backup.
class PersistenceRecoverySnapshot {
  final List<Schedule> schedules;
  final List<ScheduleVersion> scheduleVersions;
  final List<WorkoutSession> history;
  final WorkoutSession? currentSession;
  final List<BodyLog> bodyLogs;
  final List<Exercise> customExercises;
  final Set<String> favoriteExerciseIds;
  final bool recoveredFromCorruption;
  final bool rootCorruption;
  final bool includesCustomExercises;
  final bool includesFavoriteExerciseIds;
  final int? version;

  const PersistenceRecoverySnapshot({
    required this.schedules,
    required this.scheduleVersions,
    required this.history,
    required this.currentSession,
    required this.bodyLogs,
    required this.customExercises,
    required this.favoriteExerciseIds,
    required this.recoveredFromCorruption,
    required this.rootCorruption,
    required this.includesCustomExercises,
    required this.includesFavoriteExerciseIds,
    required this.version,
  });

  bool get hasAnyData =>
      schedules.isNotEmpty ||
      scheduleVersions.isNotEmpty ||
      history.isNotEmpty ||
      currentSession != null ||
      bodyLogs.isNotEmpty ||
      customExercises.isNotEmpty ||
      favoriteExerciseIds.isNotEmpty;
}

/// Fault-tolerant decoder used only at persistence boundaries.
///
/// Domain model parsers intentionally remain strict. This layer isolates bad
/// records, keeps valid siblings, and fails closed on ambiguous duplicate IDs.
class PersistenceRecoveryDecoder {
  static const int currentBackupVersion = 6;

  const PersistenceRecoveryDecoder._();

  static PersistenceRecoverySnapshot decodeBackupText(String rawText) {
    final decoded = jsonDecode(rawText);
    return decodeBackupValue(decoded);
  }

  static PersistenceRecoverySnapshot decodeBackupValue(Object? decoded) {
    if (decoded is List) {
      final context = _RecoveryContext();
      final schedules = _decodeSchedules(decoded, context, 'legacy_import');
      return _snapshot(
        context: context,
        schedules: schedules,
        scheduleVersions: const [],
        history: const [],
        currentSession: null,
        bodyLogs: const [],
        customExercises: const [],
        favoriteExerciseIds: const <String>{},
        includesCustomExercises: false,
        includesFavoriteExerciseIds: false,
        version: null,
      );
    }
    if (decoded is! Map) {
      throw const FormatException('Formato backup non supportato.');
    }

    final map = Map<String, dynamic>.from(decoded);
    final version = _parseBackupVersion(map['version']);
    final context = _RecoveryContext();
    final schedules = _decodeSchedules(
      _collectionValue(map, 'schedules', context),
      context,
      'backup_schedule',
    );
    final versions = _decodeScheduleVersions(
      _collectionValue(map, 'scheduleVersions', context),
      context,
      'backup_version',
    );
    final history = _decodeSessions(
      _collectionValue(map, 'history', context),
      context,
      'backup_history',
      allowPartial: false,
    );
    final bodyLogs = _decodeBodyLogs(
      _collectionValue(map, 'bodyLogs', context),
      context,
      'backup_body',
    );
    final includesCustom = map.containsKey('customExercises');
    final custom = _decodeCustomExercises(
      includesCustom
          ? _collectionValue(map, 'customExercises', context)
          : const <dynamic>[],
      context,
      'backup_custom',
    );
    final includesFavorites = map.containsKey('favoriteExerciseIds');
    final favorites = _decodeFavoriteIds(
      includesFavorites
          ? _collectionValue(map, 'favoriteExerciseIds', context)
          : const <dynamic>[],
      context,
    );

    WorkoutSession? current;
    if (map['currentSession'] != null) {
      current = _decodeSession(
        map['currentSession'],
        0,
        context,
        'backup_current',
        allowPartial: true,
        currentSession: true,
      );
      if (current == null) context.recovered = true;
    }

    return _snapshot(
      context: context,
      schedules: schedules,
      scheduleVersions: versions,
      history: history,
      currentSession: current,
      bodyLogs: bodyLogs,
      customExercises: custom,
      favoriteExerciseIds: favorites,
      includesCustomExercises: includesCustom,
      includesFavoriteExerciseIds: includesFavorites,
      version: version,
    );
  }

  /// Decodes the raw values read from SharedPreferences. Values are deliberately
  /// accepted as Object? so a preference stored under the wrong runtime type is
  /// treated as corruption instead of throwing from getString/getInt casts.
  static PersistenceRecoverySnapshot decodeLegacyStorage(
    Map<String, Object?> values,
  ) {
    final context = _RecoveryContext(missingIdsAreCorruption: false);

    Object? decode(String key, Object? fallback) {
      final raw = values[key];
      if (raw == null) return fallback;
      if (raw is! String) {
        context.recovered = true;
        context.rootCorruption = true;
        return fallback;
      }
      if (raw.trim().isEmpty) return fallback;
      try {
        return jsonDecode(raw);
      } catch (_) {
        context.recovered = true;
        context.rootCorruption = true;
        return fallback;
      }
    }

    final schedules = _decodeSchedules(
      decode('schedules', const <dynamic>[]),
      context,
      'legacy_schedule',
    );
    final versions = _decodeScheduleVersions(
      decode('schedule_versions', const <dynamic>[]),
      context,
      'legacy_version',
    );
    final history = _decodeSessions(
      decode('history', const <dynamic>[]),
      context,
      'legacy_history',
      allowPartial: false,
    );
    final bodyLogs = _decodeBodyLogs(
      decode('body_logs', const <dynamic>[]),
      context,
      'legacy_body',
    );
    final custom = _decodeCustomExercises(
      decode('custom_exercises', const <dynamic>[]),
      context,
      'legacy_custom',
    );
    final favorites = _decodeFavoriteIds(
      decode('favorite_exercise_ids', const <dynamic>[]),
      context,
    );

    WorkoutSession? current;
    final currentValue = decode('current_session', null);
    if (currentValue != null) {
      current = _decodeSession(
        currentValue,
        0,
        context,
        'legacy_current',
        allowPartial: true,
        currentSession: true,
      );
      if (current == null) context.recovered = true;
    }

    return _snapshot(
      context: context,
      schedules: schedules,
      scheduleVersions: versions,
      history: history,
      currentSession: current,
      bodyLogs: bodyLogs,
      customExercises: custom,
      favoriteExerciseIds: favorites,
      includesCustomExercises: values.containsKey('custom_exercises'),
      includesFavoriteExerciseIds: values.containsKey('favorite_exercise_ids'),
      version: null,
    );
  }

  static int? _parseBackupVersion(Object? value) {
    if (value == null) return null;
    if (value is! num || !value.isFinite || value != value.roundToDouble()) {
      throw const FormatException('Versione backup non valida.');
    }
    final version = value.toInt();
    if (version < 1) {
      throw const FormatException('Versione backup non valida.');
    }
    if (version > currentBackupVersion) {
      throw UnsupportedError(
        'Backup versione $version non supportato: questa app legge fino alla versione $currentBackupVersion.',
      );
    }
    return version;
  }

  static Object _collectionValue(
    Map<String, dynamic> map,
    String key,
    _RecoveryContext context,
  ) {
    final value = map[key];
    if (value == null) return const <dynamic>[];
    if (value is List) return value;
    context.recovered = true;
    context.rootCorruption = true;
    return const <dynamic>[];
  }

  static List<Schedule> _decodeSchedules(
    Object? value,
    _RecoveryContext context,
    String prefix,
  ) {
    if (value is! List) {
      context.recovered = true;
      context.rootCorruption = true;
      return [];
    }
    final result = <Schedule>[];
    for (var index = 0; index < value.length; index += 1) {
      final raw = value[index];
      if (raw is! Map) {
        context.recovered = true;
        continue;
      }
      final map = Map<String, dynamic>.from(raw);
      final id = _stableId(map['id'], '${prefix}_$index', context);
      if (context.scheduleIds.contains(id)) {
        context.recovered = true;
        continue;
      }
      final base = Map<String, dynamic>.from(map)
        ..['id'] = id
        ..['exercises'] = const <dynamic>[];
      _normalizeInt(base, 'week');
      try {
        final schedule = Schedule.fromJson(base);
        context.scheduleIds.add(id);
        final exercises = <Exercise>[];
        final rawExercises = map['exercises'];
        if (rawExercises == null) {
          schedule.exercises = exercises;
        } else if (rawExercises is List) {
          for (
            var exerciseIndex = 0;
            exerciseIndex < rawExercises.length;
            exerciseIndex += 1
          ) {
            final exercise = _decodeExercise(
              rawExercises[exerciseIndex],
              exerciseIndex,
              context,
              '${id}_exercise',
              context.scheduleExerciseIds,
            );
            if (exercise != null) exercises.add(exercise);
          }
          schedule.exercises = exercises;
        } else {
          context.recovered = true;
          schedule.exercises = exercises;
        }
        result.add(schedule);
      } catch (_) {
        context.recovered = true;
      }
    }
    return result;
  }

  static Exercise? _decodeExercise(
    Object? raw,
    int index,
    _RecoveryContext context,
    String prefix,
    Set<String> ids,
  ) {
    if (raw is! Map) {
      context.recovered = true;
      return null;
    }
    final map = Map<String, dynamic>.from(raw);
    final id = _stableId(map['id'], '${prefix}_$index', context);
    if (ids.contains(id)) {
      context.recovered = true;
      return null;
    }
    map['id'] = id;
    _normalizeInt(map, 'reps');
    _normalizeInt(map, 'set');
    _normalizeInt(map, 'targetMinReps');
    _normalizeInt(map, 'targetMaxReps');
    _normalizeInt(map, 'backoffReps');
    _normalizeInt(map, 'restSeconds');
    _normalizeInt(map, 'supersetGroup');
    _normalizeInt(map, 'progressionRepStep');
    try {
      final exercise = Exercise.fromJson(map);
      ids.add(id);
      return exercise;
    } catch (_) {
      context.recovered = true;
      return null;
    }
  }

  static List<WorkoutSession> _decodeSessions(
    Object? value,
    _RecoveryContext context,
    String prefix, {
    required bool allowPartial,
  }) {
    if (value is! List) {
      context.recovered = true;
      context.rootCorruption = true;
      return [];
    }
    final result = <WorkoutSession>[];
    for (var index = 0; index < value.length; index += 1) {
      final session = _decodeSession(
        value[index],
        index,
        context,
        prefix,
        allowPartial: allowPartial,
        currentSession: false,
      );
      if (session != null) result.add(session);
    }
    return result;
  }

  static WorkoutSession? _decodeSession(
    Object? raw,
    int index,
    _RecoveryContext context,
    String prefix, {
    required bool allowPartial,
    required bool currentSession,
  }) {
    if (raw is! Map) {
      context.recovered = true;
      return null;
    }
    final map = Map<String, dynamic>.from(raw);
    final id = _stableId(map['id'], '${prefix}_$index', context);
    final idSet = currentSession
        ? context.currentSessionIds
        : context.historySessionIds;
    if (idSet.contains(id)) {
      context.recovered = true;
      return null;
    }

    final base = Map<String, dynamic>.from(map)
      ..['id'] = id
      ..['exercises'] = const <dynamic>[];

    if (allowPartial) {
      final rawStart = base['startTime'];
      final start = rawStart is String ? DateTime.tryParse(rawStart) : null;
      if (start == null) {
        context.recovered = true;
        return null;
      }
      if (base['scheduleTitle'] is! String ||
          (base['scheduleTitle'] as String).trim().isEmpty) {
        base['scheduleTitle'] = 'Allenamento recuperato';
        context.recovered = true;
      }
      final rawEnd = base['endTime'];
      if (rawEnd is! String || DateTime.tryParse(rawEnd) == null) {
        base['endTime'] = start.toIso8601String();
        context.recovered = true;
      }
    }

    try {
      final session = WorkoutSession.fromJson(base);
      idSet.add(id);
      final exercises = <WorkoutExercise>[];
      final rawExercises = map['exercises'];
      if (rawExercises == null) {
        // Missing exercise arrays are supported by older persisted sessions.
      } else if (rawExercises is List) {
        for (
          var exerciseIndex = 0;
          exerciseIndex < rawExercises.length;
          exerciseIndex += 1
        ) {
          final exercise = _decodeWorkoutExercise(
            rawExercises[exerciseIndex],
            exerciseIndex,
            context,
            '${id}_exercise',
          );
          if (exercise != null) exercises.add(exercise);
        }
      } else if (rawExercises != null) {
        context.recovered = true;
      }
      session.exercises = exercises;
      return session;
    } catch (_) {
      context.recovered = true;
      return null;
    }
  }

  static WorkoutExercise? _decodeWorkoutExercise(
    Object? raw,
    int index,
    _RecoveryContext context,
    String prefix,
  ) {
    if (raw is! Map) {
      context.recovered = true;
      return null;
    }
    final map = Map<String, dynamic>.from(raw);
    final id = _stableId(map['id'], '${prefix}_$index', context);
    if (context.workoutExerciseIds.contains(id)) {
      context.recovered = true;
      return null;
    }
    final base = Map<String, dynamic>.from(map)
      ..['id'] = id
      ..['sets'] = const <dynamic>[];
    _normalizeInt(base, 'targetMinReps');
    _normalizeInt(base, 'targetMaxReps');
    _normalizeInt(base, 'restSeconds');
    _normalizeInt(base, 'activeRestSeconds');
    _normalizeInt(base, 'supersetGroup');
    _normalizeInt(base, 'progressionRepStep');
    try {
      final exercise = WorkoutExercise.fromJson(base);
      context.workoutExerciseIds.add(id);
      final sets = <ExerciseSet>[];
      final rawSets = map['sets'];
      if (rawSets == null) {
        // Missing set arrays are supported by older persisted exercises.
      } else if (rawSets is List) {
        for (var setIndex = 0; setIndex < rawSets.length; setIndex += 1) {
          final set = _decodeSet(
            rawSets[setIndex],
            setIndex,
            context,
            '${id}_set',
          );
          if (set != null) sets.add(set);
        }
      } else {
        context.recovered = true;
      }
      exercise.sets = sets;
      return exercise;
    } catch (_) {
      context.recovered = true;
      return null;
    }
  }

  static ExerciseSet? _decodeSet(
    Object? raw,
    int index,
    _RecoveryContext context,
    String prefix,
  ) {
    if (raw is! Map) {
      context.recovered = true;
      return null;
    }
    final map = Map<String, dynamic>.from(raw);
    final id = _stableId(map['id'], '${prefix}_$index', context);
    if (context.setIds.contains(id)) {
      context.recovered = true;
      return null;
    }
    map['id'] = id;
    _normalizeInt(map, 'reps');
    _normalizeInt(map, 'rir');
    try {
      final set = ExerciseSet.fromJson(map);
      context.setIds.add(id);
      return set;
    } catch (_) {
      context.recovered = true;
      return null;
    }
  }

  static List<ScheduleVersion> _decodeScheduleVersions(
    Object? value,
    _RecoveryContext context,
    String prefix,
  ) {
    if (value is! List) {
      context.recovered = true;
      context.rootCorruption = true;
      return [];
    }
    final result = <ScheduleVersion>[];
    for (var index = 0; index < value.length; index += 1) {
      final raw = value[index];
      if (raw is! Map) {
        context.recovered = true;
        continue;
      }
      final map = Map<String, dynamic>.from(raw);
      if (map['snapshot'] != null && map['snapshot'] is! Map) {
        context.recovered = true;
        continue;
      }
      _normalizeInt(map, 'versionNumber');
      try {
        final version = ScheduleVersion.fromJson(map);
        final id = _stableId(
          map['id'],
          '${prefix}_${version.scheduleId}_${version.versionNumber}_$index',
          context,
        );
        final pair = '${version.scheduleId}::${version.versionNumber}';
        if (context.scheduleVersionIds.contains(id) ||
            context.scheduleVersionNumbers.contains(pair)) {
          context.recovered = true;
          continue;
        }
        final normalized = ScheduleVersion(
          id: id,
          scheduleId: version.scheduleId,
          versionNumber: version.versionNumber,
          createdAt: version.createdAt,
          source: version.source,
          parentVersionId: version.parentVersionId,
          reason: version.reason,
          snapshot: version.snapshot,
        );
        context.scheduleVersionIds.add(id);
        context.scheduleVersionNumbers.add(pair);
        result.add(normalized);
      } catch (_) {
        context.recovered = true;
      }
    }
    return result;
  }

  static List<BodyLog> _decodeBodyLogs(
    Object? value,
    _RecoveryContext context,
    String prefix,
  ) {
    if (value is! List) {
      context.recovered = true;
      context.rootCorruption = true;
      return [];
    }
    final result = <BodyLog>[];
    for (var index = 0; index < value.length; index += 1) {
      final raw = value[index];
      if (raw is! Map) {
        context.recovered = true;
        continue;
      }
      final map = Map<String, dynamic>.from(raw);
      final id = _stableId(map['id'], '${prefix}_$index', context);
      if (context.bodyLogIds.contains(id)) {
        context.recovered = true;
        continue;
      }
      map['id'] = id;
      _normalizeInt(map, 'sleepHours');
      _normalizeInt(map, 'readiness');
      try {
        final log = BodyLog.fromJson(map);
        context.bodyLogIds.add(id);
        result.add(log);
      } catch (_) {
        context.recovered = true;
      }
    }
    return result;
  }

  static List<Exercise> _decodeCustomExercises(
    Object? value,
    _RecoveryContext context,
    String prefix,
  ) {
    if (value is! List) {
      context.recovered = true;
      context.rootCorruption = true;
      return [];
    }
    final result = <Exercise>[];
    for (var index = 0; index < value.length; index += 1) {
      final exercise = _decodeExercise(
        value[index],
        index,
        context,
        prefix,
        context.customExerciseIds,
      );
      if (exercise != null) result.add(exercise);
    }
    return result;
  }

  static Set<String> _decodeFavoriteIds(
    Object? value,
    _RecoveryContext context,
  ) {
    if (value is! List) {
      context.recovered = true;
      context.rootCorruption = true;
      return <String>{};
    }
    final result = <String>{};
    for (final raw in value) {
      if (raw is! String || raw.trim().isEmpty) {
        context.recovered = true;
        continue;
      }
      result.add(raw.trim());
    }
    return result;
  }

  static void _normalizeInt(Map<String, dynamic> map, String key) {
    final value = map[key];
    if (value is num && value.isFinite) map[key] = value.toInt();
  }

  static String _stableId(
    Object? raw,
    String fallback,
    _RecoveryContext context,
  ) {
    if (raw is String && raw.trim().isNotEmpty) return raw.trim();
    if (context.missingIdsAreCorruption) context.recovered = true;
    return fallback;
  }

  static PersistenceRecoverySnapshot _snapshot({
    required _RecoveryContext context,
    required List<Schedule> schedules,
    required List<ScheduleVersion> scheduleVersions,
    required List<WorkoutSession> history,
    required WorkoutSession? currentSession,
    required List<BodyLog> bodyLogs,
    required List<Exercise> customExercises,
    required Set<String> favoriteExerciseIds,
    required bool includesCustomExercises,
    required bool includesFavoriteExerciseIds,
    required int? version,
  }) {
    return PersistenceRecoverySnapshot(
      schedules: schedules,
      scheduleVersions: scheduleVersions,
      history: history,
      currentSession: currentSession,
      bodyLogs: bodyLogs,
      customExercises: customExercises,
      favoriteExerciseIds: favoriteExerciseIds,
      recoveredFromCorruption: context.recovered,
      rootCorruption: context.rootCorruption,
      includesCustomExercises: includesCustomExercises,
      includesFavoriteExerciseIds: includesFavoriteExerciseIds,
      version: version,
    );
  }
}

class _RecoveryContext {
  final bool missingIdsAreCorruption;

  _RecoveryContext({this.missingIdsAreCorruption = true});

  bool recovered = false;
  bool rootCorruption = false;

  final Set<String> scheduleIds = <String>{};
  final Set<String> scheduleExerciseIds = <String>{};
  final Set<String> scheduleVersionIds = <String>{};
  final Set<String> scheduleVersionNumbers = <String>{};
  final Set<String> historySessionIds = <String>{};
  final Set<String> currentSessionIds = <String>{};
  final Set<String> workoutExerciseIds = <String>{};
  final Set<String> setIds = <String>{};
  final Set<String> bodyLogIds = <String>{};
  final Set<String> customExerciseIds = <String>{};
}
