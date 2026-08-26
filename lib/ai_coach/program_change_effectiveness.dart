import 'dart:convert';

import '../models/workout.dart';
import '../workout_progression_analytics.dart';

enum ProgramChangeEffectivenessStatus {
  improved,
  stable,
  declined,
  mixed,
  insufficient,
}

const _performanceRelevantFields = <String>{
  'weight',
  'reps',
  'set',
  'targetMinReps',
  'targetMaxReps',
  'technique',
  'backoffReps',
  'backoffReductionPercent',
  'restSeconds',
  'supersetGroup',
  'progressionKgStep',
  'progressionRepStep',
  'progressionScheme',
  'equipment',
};

Map<String, dynamic> buildProgramChangeEffectiveness({
  required Map<String, dynamic> previousSnapshot,
  required Map<String, dynamic> currentSnapshot,
  required List<WorkoutSession> previousVersionSessions,
  required List<WorkoutSession> currentVersionSessions,
  int comparisonWindow = 3,
}) {
  final previousExercises = _exerciseMap(previousSnapshot['exercises']);
  final currentExercises = _exerciseMap(currentSnapshot['exercises']);
  final exerciseIds = <String>{
    ...previousExercises.keys,
    ...currentExercises.keys,
  }.toList()..sort();

  final signals = <Map<String, dynamic>>[];
  for (final exerciseId in exerciseIds) {
    final before = previousExercises[exerciseId];
    final after = currentExercises[exerciseId];
    if (before == null && after != null) {
      signals.add({
        'exercise_id': exerciseId,
        'exercise': after['name'],
        'change_type': 'added',
        'changed_fields': const <String>['exercise_added'],
        'status': ProgramChangeEffectivenessStatus.insufficient.name,
        'primary_metric': null,
        'reason': 'exercise_added_without_pre_change_baseline',
        'previous_sessions': 0,
        'current_sessions': _exerciseSessionMetrics(
          currentVersionSessions,
          exerciseId,
        ).length,
      });
      continue;
    }
    if (before != null && after == null) {
      signals.add({
        'exercise_id': exerciseId,
        'exercise': before['name'],
        'change_type': 'removed',
        'changed_fields': const <String>['exercise_removed'],
        'status': ProgramChangeEffectivenessStatus.insufficient.name,
        'primary_metric': null,
        'reason': 'exercise_removed_without_post_change_outcome',
        'previous_sessions': _exerciseSessionMetrics(
          previousVersionSessions,
          exerciseId,
        ).length,
        'current_sessions': 0,
      });
      continue;
    }
    if (before == null || after == null || _sameJson(before, after)) {
      continue;
    }

    final changedFields = _changedPerformanceFields(before, after);
    if (changedFields.isEmpty) {
      continue;
    }

    final previousMetrics = _exerciseSessionMetrics(
      previousVersionSessions,
      exerciseId,
    );
    final currentMetrics = _exerciseSessionMetrics(
      currentVersionSessions,
      exerciseId,
    );
    final previousWindow = previousMetrics.length <= comparisonWindow
        ? previousMetrics
        : previousMetrics.sublist(previousMetrics.length - comparisonWindow);
    final currentWindow = currentMetrics.take(comparisonWindow).toList();

    signals.add(
      _compareExerciseChange(
        exerciseId: exerciseId,
        exerciseName:
            after['name']?.toString() ?? before['name']?.toString() ?? '',
        changedFields: changedFields,
        previousWindow: previousWindow,
        currentWindow: currentWindow,
      ),
    );
  }

  final statuses = signals
      .map((signal) => signal['status'] as String?)
      .whereType<String>()
      .where(
        (status) =>
            status != ProgramChangeEffectivenessStatus.insufficient.name,
      )
      .toList();
  final improved = statuses
      .where(
        (status) => status == ProgramChangeEffectivenessStatus.improved.name,
      )
      .length;
  final stable = statuses
      .where((status) => status == ProgramChangeEffectivenessStatus.stable.name)
      .length;
  final declined = statuses
      .where(
        (status) => status == ProgramChangeEffectivenessStatus.declined.name,
      )
      .length;
  final insufficient = signals.length - statuses.length;

  ProgramChangeEffectivenessStatus overall;
  if (statuses.isEmpty) {
    overall = ProgramChangeEffectivenessStatus.insufficient;
  } else if (improved > 0 && declined > 0) {
    overall = ProgramChangeEffectivenessStatus.mixed;
  } else if (declined > 0) {
    overall = ProgramChangeEffectivenessStatus.declined;
  } else if (improved > 0) {
    overall = ProgramChangeEffectivenessStatus.improved;
  } else {
    overall = ProgramChangeEffectivenessStatus.stable;
  }

  return {
    'contract': {
      'association_only': true,
      'does_not_prove_causality': true,
      'exact_schedule_version_links_only': true,
      'exact_source_exercise_id_only': true,
      'prescription_changes_only': true,
      'comparison_window': comparisonWindow,
      'minimum_sessions_per_side': 2,
      'e1rm_change_threshold_percent': 2.0,
      'volume_change_threshold_percent': 5.0,
      'window_semantics':
          'last sessions of previous version vs first sessions of current version',
    },
    'status': overall.name,
    'summary': {
      'improved': improved,
      'stable': stable,
      'declined': declined,
      'insufficient': insufficient,
      'evaluable_exercises': statuses.length,
      'changed_exercises': signals.length,
    },
    'exercise_signals': signals,
  };
}

Map<String, dynamic> _compareExerciseChange({
  required String exerciseId,
  required String exerciseName,
  required List<String> changedFields,
  required List<_ExerciseSessionMetric> previousWindow,
  required List<_ExerciseSessionMetric> currentWindow,
}) {
  if (previousWindow.length < 2 || currentWindow.length < 2) {
    return {
      'exercise_id': exerciseId,
      'exercise': exerciseName,
      'change_type': 'modified',
      'changed_fields': changedFields,
      'status': ProgramChangeEffectivenessStatus.insufficient.name,
      'primary_metric': null,
      'reason': 'requires_at_least_two_exact_sessions_per_side',
      'previous_sessions': previousWindow.length,
      'current_sessions': currentWindow.length,
      'e1rm_change_percent': null,
      'volume_per_session_change_percent': null,
    };
  }

  final previousE1rm = previousWindow
      .map((metric) => metric.estimatedOneRepMax)
      .whereType<double>()
      .toList();
  final currentE1rm = currentWindow
      .map((metric) => metric.estimatedOneRepMax)
      .whereType<double>()
      .toList();
  final e1rmChange = previousE1rm.length >= 2 && currentE1rm.length >= 2
      ? _percentChange(_mean(previousE1rm), _mean(currentE1rm))
      : null;
  final previousVolume = _mean(
    previousWindow.map((metric) => metric.volume).toList(),
  );
  final currentVolume = _mean(
    currentWindow.map((metric) => metric.volume).toList(),
  );
  final volumeChange = _percentChange(previousVolume, currentVolume);

  ProgramChangeEffectivenessStatus status;
  String primaryMetric;
  double? primaryChange;
  if (e1rmChange != null) {
    primaryMetric = 'mean_estimated_1rm';
    primaryChange = e1rmChange;
    status = _classify(e1rmChange, threshold: 2.0);
  } else if (volumeChange != null) {
    primaryMetric = 'mean_volume_per_session';
    primaryChange = volumeChange;
    status = _classify(volumeChange, threshold: 5.0);
  } else {
    primaryMetric = 'none';
    primaryChange = null;
    status = ProgramChangeEffectivenessStatus.insufficient;
  }

  return {
    'exercise_id': exerciseId,
    'exercise': exerciseName,
    'change_type': 'modified',
    'changed_fields': changedFields,
    'status': status.name,
    'primary_metric': primaryMetric,
    'primary_change_percent': primaryChange,
    'previous_sessions': previousWindow.length,
    'current_sessions': currentWindow.length,
    'e1rm_change_percent': e1rmChange,
    'volume_per_session_change_percent': volumeChange,
    'previous_mean_e1rm': previousE1rm.length >= 2 ? _mean(previousE1rm) : null,
    'current_mean_e1rm': currentE1rm.length >= 2 ? _mean(currentE1rm) : null,
    'previous_mean_volume_per_session': previousVolume,
    'current_mean_volume_per_session': currentVolume,
    if (primaryMetric == 'mean_volume_per_session')
      'caveat':
          'volume can change because the prescription itself changed; interpret as work-capacity/exposure association, not causal proof',
  };
}

ProgramChangeEffectivenessStatus _classify(
  double changePercent, {
  required double threshold,
}) {
  if (changePercent > threshold) {
    return ProgramChangeEffectivenessStatus.improved;
  }
  if (changePercent < -threshold) {
    return ProgramChangeEffectivenessStatus.declined;
  }
  return ProgramChangeEffectivenessStatus.stable;
}

List<_ExerciseSessionMetric> _exerciseSessionMetrics(
  List<WorkoutSession> sessions,
  String exerciseId,
) {
  final sorted = [...sessions]
    ..sort((a, b) => a.startTime.compareTo(b.startTime));
  final result = <_ExerciseSessionMetric>[];
  for (final session in sorted) {
    final exercises = session.exercises.where(
      (exercise) => exercise.sourceExerciseId?.trim() == exerciseId,
    );
    final workSets = exercises
        .expand((exercise) => exercise.sets)
        .where((set) => set.isCompleted && !set.isWarmup)
        .toList();
    if (workSets.isEmpty) continue;
    final volume = workSets.fold<double>(
      0,
      (sum, set) => sum + set.weight * set.reps,
    );
    result.add(
      _ExerciseSessionMetric(
        volume: volume,
        estimatedOneRepMax: bestEstimatedOneRepMaxForSets(workSets),
      ),
    );
  }
  return result;
}

List<String> _changedPerformanceFields(
  Map<String, dynamic> before,
  Map<String, dynamic> after,
) {
  final changed = <String>[];
  for (final field in _performanceRelevantFields) {
    if (!_sameJson(before[field], after[field])) {
      changed.add(field);
    }
  }
  changed.sort();
  return changed;
}

Map<String, Map<String, dynamic>> _exerciseMap(dynamic raw) {
  final result = <String, Map<String, dynamic>>{};
  if (raw is! List) return result;
  for (final item in raw) {
    if (item is! Map) continue;
    final exercise = Map<String, dynamic>.from(item);
    final id = exercise['id']?.toString().trim();
    if (id == null || id.isEmpty) continue;
    result[id] = exercise;
  }
  return result;
}

bool _sameJson(dynamic a, dynamic b) => jsonEncode(a) == jsonEncode(b);

double _mean(List<double> values) =>
    values.fold<double>(0, (sum, value) => sum + value) / values.length;

double? _percentChange(double previous, double current) {
  if (previous <= 0) return null;
  return ((current - previous) / previous) * 100;
}

class _ExerciseSessionMetric {
  final double volume;
  final double? estimatedOneRepMax;

  const _ExerciseSessionMetric({
    required this.volume,
    required this.estimatedOneRepMax,
  });
}
