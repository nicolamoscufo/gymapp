import 'dart:convert';

import '../models/schedule.dart';
import '../models/schedule_version.dart';
import '../models/workout.dart';
import '../workout_progression_analytics.dart';

/// Builds a compact, deterministic longitudinal program record for the Coach.
///
/// The first version of each schedule carries a baseline snapshot. Later
/// versions carry only their diff from the previous version, so the full
/// program history remains reconstructable without repeating every snapshot.
/// Workout outcomes are attributed only through an exact `scheduleVersionId`.
Map<String, dynamic> buildProgramHistoryContext({
  required List<ScheduleVersion> scheduleVersions,
  required List<WorkoutSession> history,
  required List<Schedule> schedules,
}) {
  final versionsBySchedule = <String, List<ScheduleVersion>>{};
  for (final version in scheduleVersions) {
    versionsBySchedule.putIfAbsent(version.scheduleId, () => []).add(version);
  }

  final currentById = {for (final schedule in schedules) schedule.id: schedule};
  final sessionsByVersion = <String, List<WorkoutSession>>{};
  final unresolved = <WorkoutSession>[];
  var linkedWorkoutCount = 0;

  for (final session in history) {
    final versionId = session.scheduleVersionId;
    if (versionId == null || versionId.trim().isEmpty) {
      unresolved.add(session);
      continue;
    }
    sessionsByVersion.putIfAbsent(versionId, () => []).add(session);
    linkedWorkoutCount += 1;
  }

  final scheduleIds = versionsBySchedule.keys.toList()..sort();
  final programs = <Map<String, dynamic>>[];

  for (final scheduleId in scheduleIds) {
    final versions = versionsBySchedule[scheduleId]!
      ..sort(_compareVersions);
    final current = currentById[scheduleId];
    final latest = versions.last;
    final title = _stringValue(latest.snapshot['title']) ?? current?.title ?? '';
    final versionEntries = <Map<String, dynamic>>[];

    for (var index = 0; index < versions.length; index += 1) {
      final version = versions[index];
      final previous = index == 0 ? null : versions[index - 1];
      final linkedSessions = sessionsByVersion[version.id] ?? const <WorkoutSession>[];
      versionEntries.add({
        'version_id': version.id,
        'version_number': version.versionNumber,
        'changed_at': version.createdAt.toIso8601String(),
        'source': version.source.name,
        'reason': version.reason,
        'parent_version_id': version.parentVersionId,
        'is_current': current?.currentVersionId == version.id,
        if (previous == null)
          'baseline': _compactBaseline(version.snapshot)
        else
          'changes_from_previous': _snapshotDiff(
            previous.snapshot,
            version.snapshot,
          ),
        'performance': _performanceSummary(linkedSessions),
      });
    }

    programs.add({
      'schedule_id': scheduleId,
      'title': title,
      'is_present_in_current_plans': current != null,
      'is_archived': current?.isArchived,
      'current_version_id': current?.currentVersionId,
      'current_version_number': current?.currentVersionNumber,
      'versions': versionEntries,
    });
  }

  final unresolvedSummary = _unresolvedSummary(unresolved);
  final totalWorkouts = history.length;
  return {
    'contract': {
      'version_links_are_authoritative': true,
      'null_version_link_means_unknown': true,
      'do_not_infer_legacy_version_links': true,
      'version_performance_uses_exact_links_only': true,
      'timeline_is_deterministic': true,
      'representation':
          'first version is a baseline; later versions are diffs from the previous stored version',
    },
    'coverage': {
      'program_count': programs.length,
      'version_count': scheduleVersions.length,
      'workout_count': totalWorkouts,
      'exactly_linked_workouts': linkedWorkoutCount,
      'unresolved_legacy_workouts': unresolved.length,
      'exact_link_coverage': totalWorkouts == 0
          ? null
          : linkedWorkoutCount / totalWorkouts,
    },
    'programs': programs,
    'unresolved_legacy': unresolvedSummary,
  };
}

int _compareVersions(ScheduleVersion a, ScheduleVersion b) {
  final byNumber = a.versionNumber.compareTo(b.versionNumber);
  if (byNumber != 0) return byNumber;
  final byDate = a.createdAt.compareTo(b.createdAt);
  if (byDate != 0) return byDate;
  return a.id.compareTo(b.id);
}

Map<String, dynamic> _compactBaseline(Map<String, dynamic> snapshot) {
  final result = <String, dynamic>{};
  for (final entry in snapshot.entries) {
    if (entry.key == 'currentVersionId' ||
        entry.key == 'currentVersionNumber') {
      continue;
    }
    result[entry.key] = _deepCopy(entry.value);
  }
  return result;
}

Map<String, dynamic> _snapshotDiff(
  Map<String, dynamic> previous,
  Map<String, dynamic> current,
) {
  final scheduleChanges = <Map<String, dynamic>>[];
  final keys = <String>{...previous.keys, ...current.keys}
    ..remove('exercises')
    ..remove('currentVersionId')
    ..remove('currentVersionNumber');
  final sortedKeys = keys.toList()..sort();

  for (final key in sortedKeys) {
    final before = previous[key];
    final after = current[key];
    if (_sameJson(before, after)) continue;
    scheduleChanges.add({
      'field': key,
      'from': _deepCopy(before),
      'to': _deepCopy(after),
    });
  }

  final previousExercises = _exerciseMap(previous['exercises']);
  final currentExercises = _exerciseMap(current['exercises']);
  final ids = <String>{...previousExercises.keys, ...currentExercises.keys}.toList()
    ..sort();
  final exerciseChanges = <Map<String, dynamic>>[];

  for (final id in ids) {
    final before = previousExercises[id];
    final after = currentExercises[id];
    if (before == null && after != null) {
      exerciseChanges.add({
        'type': 'added',
        'exercise_id': id,
        'name': after['name'],
        'exercise': _deepCopy(after),
      });
      continue;
    }
    if (before != null && after == null) {
      exerciseChanges.add({
        'type': 'removed',
        'exercise_id': id,
        'name': before['name'],
        'exercise': _deepCopy(before),
      });
      continue;
    }
    if (before == null || after == null) continue;

    final fieldChanges = <Map<String, dynamic>>[];
    final fields = <String>{...before.keys, ...after.keys}.toList()..sort();
    for (final field in fields) {
      if (field == 'id') continue;
      final oldValue = before[field];
      final newValue = after[field];
      if (_sameJson(oldValue, newValue)) continue;
      fieldChanges.add({
        'field': field,
        'from': _deepCopy(oldValue),
        'to': _deepCopy(newValue),
      });
    }
    if (fieldChanges.isNotEmpty) {
      exerciseChanges.add({
        'type': 'modified',
        'exercise_id': id,
        'name': after['name'] ?? before['name'],
        'fields': fieldChanges,
      });
    }
  }

  return {
    'schedule_fields': scheduleChanges,
    'exercises': exerciseChanges,
    'change_count': scheduleChanges.length + exerciseChanges.length,
  };
}

Map<String, Map<String, dynamic>> _exerciseMap(dynamic raw) {
  final result = <String, Map<String, dynamic>>{};
  if (raw is! List) return result;
  for (var index = 0; index < raw.length; index += 1) {
    final item = raw[index];
    if (item is! Map) continue;
    final exercise = Map<String, dynamic>.from(item);
    final id = exercise['id']?.toString().trim();
    // Current models have stable IDs. The fallback keeps malformed/very old
    // snapshots deterministic without pretending the generated key is stable.
    final key = id == null || id.isEmpty ? '__legacy_index_$index' : id;
    result[key] = exercise;
  }
  return result;
}

Map<String, dynamic> _performanceSummary(List<WorkoutSession> sessions) {
  if (sessions.isEmpty) {
    return const {
      'session_count': 0,
      'first_session_at': null,
      'last_session_at': null,
      'completed_work_sets': 0,
      'total_volume': 0.0,
      'exercise_outcomes': <Map<String, dynamic>>[],
    };
  }

  final sorted = [...sessions]..sort((a, b) => a.startTime.compareTo(b.startTime));
  var completedWorkSets = 0;
  var totalVolume = 0.0;
  final outcomes = <String, _ExerciseOutcomeAccumulator>{};

  for (final session in sorted) {
    final seenInSession = <String>{};
    for (final exercise in session.exercises) {
      final workSets = exercise.sets
          .where((set) => set.isCompleted && !set.isWarmup)
          .toList();
      if (workSets.isEmpty) continue;
      completedWorkSets += workSets.length;
      final normalized = exercise.name.trim().toLowerCase();
      final accumulator = outcomes.putIfAbsent(
        normalized,
        () => _ExerciseOutcomeAccumulator(exercise.name),
      );
      if (seenInSession.add(normalized)) accumulator.sessionCount += 1;
      for (final set in workSets) {
        final volume = set.weight * set.reps;
        totalVolume += volume;
        accumulator.totalVolume += volume;
      }
      final e1rm = bestEstimatedOneRepMaxForSets(workSets);
      if (e1rm != null &&
          (accumulator.bestEstimatedOneRepMax == null ||
              e1rm > accumulator.bestEstimatedOneRepMax!)) {
        accumulator.bestEstimatedOneRepMax = e1rm;
      }
    }
  }

  final exerciseOutcomes = outcomes.values.toList()
    ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  return {
    'session_count': sorted.length,
    'first_session_at': sorted.first.startTime.toIso8601String(),
    'last_session_at': sorted.last.startTime.toIso8601String(),
    'completed_work_sets': completedWorkSets,
    'total_volume': totalVolume,
    'exercise_outcomes': exerciseOutcomes
        .map(
          (entry) => {
            'exercise': entry.name,
            'sessions': entry.sessionCount,
            'total_volume': entry.totalVolume,
            'best_estimated_1rm': entry.bestEstimatedOneRepMax,
          },
        )
        .toList(),
  };
}

Map<String, dynamic> _unresolvedSummary(List<WorkoutSession> sessions) {
  if (sessions.isEmpty) {
    return const {
      'count': 0,
      'first_session_at': null,
      'last_session_at': null,
      'by_schedule': <Map<String, dynamic>>[],
    };
  }
  final sorted = [...sessions]..sort((a, b) => a.startTime.compareTo(b.startTime));
  final counts = <String, int>{};
  for (final session in sorted) {
    final key = session.scheduleTitle.trim().isEmpty
        ? '(unknown schedule)'
        : session.scheduleTitle.trim();
    counts.update(key, (value) => value + 1, ifAbsent: () => 1);
  }
  final names = counts.keys.toList()..sort();
  return {
    'count': sorted.length,
    'first_session_at': sorted.first.startTime.toIso8601String(),
    'last_session_at': sorted.last.startTime.toIso8601String(),
    'by_schedule': names
        .map((name) => {'schedule_title': name, 'sessions': counts[name]})
        .toList(),
  };
}

bool _sameJson(dynamic a, dynamic b) => jsonEncode(a) == jsonEncode(b);

dynamic _deepCopy(dynamic value) {
  if (value == null || value is num || value is bool || value is String) {
    return value;
  }
  return jsonDecode(jsonEncode(value));
}

String? _stringValue(dynamic value) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? null : text;
}

class _ExerciseOutcomeAccumulator {
  final String name;
  int sessionCount = 0;
  double totalVolume = 0;
  double? bestEstimatedOneRepMax;

  _ExerciseOutcomeAccumulator(this.name);
}
