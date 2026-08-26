import 'active_workout_schedule_sync.dart';
import 'active_workout_session_builder.dart';
import 'models/exercise.dart';
import 'models/schedule.dart';
import 'models/workout.dart';
import 'workout_progression_analytics.dart';

class NextSessionPlanFieldChange {
  final String field;
  final Object currentValue;
  final Object suggestedValue;

  const NextSessionPlanFieldChange({
    required this.field,
    required this.currentValue,
    required this.suggestedValue,
  });

  String get label => switch (field) {
    'weight' => 'Carico',
    'reps' => 'Ripetizioni',
    _ => field,
  };

  String get currentLabel => _displayValue(currentValue);
  String get suggestedLabel => _displayValue(suggestedValue);

  String _displayValue(Object value) {
    if (field == 'weight') {
      final weight = (value as num).toDouble();
      final text = weight == weight.roundToDouble()
          ? weight.toStringAsFixed(0)
          : weight
                .toStringAsFixed(2)
                .replaceFirst(RegExp(r'0+$'), '')
                .replaceFirst(RegExp(r'\.$'), '');
      return '$text kg';
    }
    return value.toString();
  }
}

class NextSessionPlanAction {
  final String scheduleId;
  final String scheduleTitle;
  final String exerciseId;
  final String exerciseName;
  final ProgressionDecision decision;
  final List<NextSessionPlanFieldChange> changes;

  const NextSessionPlanAction({
    required this.scheduleId,
    required this.scheduleTitle,
    required this.exerciseId,
    required this.exerciseName,
    required this.decision,
    required this.changes,
  });

  String get id => '$scheduleId|$exerciseId|${decision.action.name}';

  bool get defaultSelected => decision.confidence != ProgressionConfidence.low;

  String get actionLabel => progressionActionLabel(decision);

  String get confidenceLabel => switch (decision.confidence) {
    ProgressionConfidence.low => 'bassa',
    ProgressionConfidence.medium => 'media',
    ProgressionConfidence.high => 'alta',
  };
}

class NextSessionPlan {
  final String scheduleId;
  final String scheduleTitle;
  final List<NextSessionPlanAction> actions;

  const NextSessionPlan({
    required this.scheduleId,
    required this.scheduleTitle,
    required this.actions,
  });

  bool get hasActions => actions.isNotEmpty;
  int get defaultSelectedCount =>
      actions.where((action) => action.defaultSelected).length;
}

class NextSessionPlanApplyResult {
  final int applied;
  final int skipped;

  const NextSessionPlanApplyResult({
    required this.applied,
    required this.skipped,
  });
}

NextSessionPlan? buildNextSessionPlan({
  required WorkoutSession session,
  required List<WorkoutSession> history,
  required List<Schedule> schedules,
  Set<String> skipSourceExerciseIds = const <String>{},
}) {
  final storedSchedule = _resolveSchedule(session, schedules);
  if (storedSchedule == null) return null;

  final simulatedSchedule = Schedule.fromJson(storedSchedule.toJson());
  final sessionBuilder = ActiveWorkoutSessionBuilder(
    history: history,
    bodyLogs: const [],
  );
  final sync = ActiveWorkoutScheduleSync(
    session: session,
    sessionBuilder: sessionBuilder,
  );
  sync.applyProgressionToSchedule(
    storedSchedule: simulatedSchedule,
    history: history,
    skipSourceExerciseIds: skipSourceExerciseIds,
  );

  final actions = <NextSessionPlanAction>[];
  for (final completedExercise in session.exercises) {
    final sourceId = completedExercise.sourceExerciseId;
    if (sourceId != null && skipSourceExerciseIds.contains(sourceId)) {
      continue;
    }

    final originalExercise = _resolveExercise(
      completedExercise,
      storedSchedule,
    );
    if (originalExercise == null) continue;
    final simulatedExercise = simulatedSchedule.exercises
        .where((exercise) => exercise.id == originalExercise.id)
        .firstOrNull;
    if (simulatedExercise == null) continue;

    final changes = <NextSessionPlanFieldChange>[];
    if (!_sameNumber(originalExercise.weight, simulatedExercise.weight)) {
      changes.add(
        NextSessionPlanFieldChange(
          field: 'weight',
          currentValue: originalExercise.weight,
          suggestedValue: simulatedExercise.weight,
        ),
      );
    }
    if (originalExercise.reps != simulatedExercise.reps) {
      changes.add(
        NextSessionPlanFieldChange(
          field: 'reps',
          currentValue: originalExercise.reps,
          suggestedValue: simulatedExercise.reps,
        ),
      );
    }
    if (changes.isEmpty) continue;

    final decision = buildProgressionDecision(
      exercise: completedExercise,
      history: history,
      excludeSessionId: session.id,
    );
    if (decision.action == ProgressionAction.maintain ||
        decision.action == ProgressionAction.manual) {
      continue;
    }

    actions.add(
      NextSessionPlanAction(
        scheduleId: storedSchedule.id,
        scheduleTitle: storedSchedule.title,
        exerciseId: originalExercise.id,
        exerciseName: originalExercise.name,
        decision: decision,
        changes: changes,
      ),
    );
  }

  return NextSessionPlan(
    scheduleId: storedSchedule.id,
    scheduleTitle: storedSchedule.title,
    actions: actions,
  );
}

NextSessionPlanApplyResult applyNextSessionPlan({
  required List<Schedule> schedules,
  required List<NextSessionPlanAction> actions,
}) {
  var applied = 0;
  var skipped = 0;

  for (final action in actions) {
    final schedule = schedules
        .where((candidate) => candidate.id == action.scheduleId)
        .firstOrNull;
    final exercise = schedule?.exercises
        .where((candidate) => candidate.id == action.exerciseId)
        .firstOrNull;
    if (exercise == null) {
      skipped += 1;
      continue;
    }

    final stillCurrent = action.changes.every(
      (change) => _matchesCurrentValue(exercise, change),
    );
    if (!stillCurrent) {
      skipped += 1;
      continue;
    }

    for (final change in action.changes) {
      switch (change.field) {
        case 'weight':
          exercise.weight = (change.suggestedValue as num).toDouble();
          break;
        case 'reps':
          exercise.reps = (change.suggestedValue as num).toInt();
          break;
      }
    }
    applied += 1;
  }

  return NextSessionPlanApplyResult(applied: applied, skipped: skipped);
}

Schedule? _resolveSchedule(WorkoutSession session, List<Schedule> schedules) {
  final scheduleId = session.scheduleId;
  if (scheduleId != null && scheduleId.isNotEmpty) {
    final matches = schedules.where((schedule) => schedule.id == scheduleId);
    return matches.length == 1 ? matches.single : null;
  }

  final normalizedTitle = session.scheduleTitle.trim().toLowerCase();
  final matches = schedules.where(
    (schedule) => schedule.title.trim().toLowerCase() == normalizedTitle,
  );
  return matches.length == 1 ? matches.single : null;
}

Exercise? _resolveExercise(
  WorkoutExercise completedExercise,
  Schedule schedule,
) {
  final sourceId = completedExercise.sourceExerciseId;
  if (sourceId != null && sourceId.isNotEmpty) {
    final matches = schedule.exercises.where(
      (exercise) => exercise.id == sourceId,
    );
    return matches.length == 1 ? matches.single : null;
  }

  final normalizedName = completedExercise.name.trim().toLowerCase();
  final matches = schedule.exercises.where(
    (exercise) => exercise.name.trim().toLowerCase() == normalizedName,
  );
  return matches.length == 1 ? matches.single : null;
}

bool _matchesCurrentValue(
  Exercise exercise,
  NextSessionPlanFieldChange change,
) {
  return switch (change.field) {
    'weight' => _sameNumber(exercise.weight, change.currentValue as num),
    'reps' => exercise.reps == (change.currentValue as num).toInt(),
    _ => false,
  };
}

bool _sameNumber(num left, num right) =>
    (left.toDouble() - right.toDouble()).abs() < 0.000001;

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
