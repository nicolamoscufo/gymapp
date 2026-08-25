import '../models/exercise.dart';
import '../models/schedule.dart';
import 'ai_coach_models.dart';

class ValidatedPlanAction {
  final ProposedPlanAction source;
  final String suggestionReason;
  final String confidence;
  final String scheduleId;
  final String scheduleTitle;
  final String exerciseId;
  final String exerciseName;
  final String field;
  final String currentValue;
  final String suggestedValue;
  final Object parsedValue;

  const ValidatedPlanAction({
    required this.source,
    required this.suggestionReason,
    required this.confidence,
    required this.scheduleId,
    required this.scheduleTitle,
    required this.exerciseId,
    required this.exerciseName,
    required this.field,
    required this.currentValue,
    required this.suggestedValue,
    required this.parsedValue,
  });

  String get title => '$exerciseName · ${fieldLabel(field)}';

  static String fieldLabel(String field) => switch (field) {
    'weight' => 'Carico',
    'sets' => 'Serie',
    'reps' => 'Ripetizioni',
    'target_min_reps' => 'Reps minime',
    'target_max_reps' => 'Reps massime',
    'rest_seconds' => 'Recupero',
    'notes' => 'Note',
    _ => field,
  };
}

class PlanApplyResult {
  final int applied;
  final int skipped;

  const PlanApplyResult({required this.applied, required this.skipped});
}

class AiPlanActionService {
  const AiPlanActionService();

  List<ValidatedPlanAction> validate(
    SuggestedAdjustmentReport report,
    List<Schedule> schedules,
  ) {
    final result = <ValidatedPlanAction>[];
    final seen = <String>{};

    for (final suggestion in report.suggestions) {
      for (final action in suggestion.proposedActions) {
        if (action.action == 'keep') continue;
        final resolved = _resolveTarget(action, schedules);
        if (resolved == null) continue;
        final schedule = resolved.$1;
        final exercise = resolved.$2;
        final parsed = _parseSuggestedValue(
          action.field,
          action.suggestedValue,
        );
        if (parsed == null) continue;
        if (!_isSemanticallyValid(action, exercise, parsed)) continue;

        final key = '${schedule.id}|${exercise.id}|${action.field}';
        if (!seen.add(key)) continue;
        final current = _currentValue(exercise, action.field);
        if (current == null) continue;
        final suggested = _displayValue(action.field, parsed);
        if (current == suggested) continue;

        result.add(
          ValidatedPlanAction(
            source: action,
            suggestionReason: suggestion.reason,
            confidence: suggestion.confidence,
            scheduleId: schedule.id,
            scheduleTitle: schedule.title,
            exerciseId: exercise.id,
            exerciseName: exercise.name,
            field: action.field,
            currentValue: current,
            suggestedValue: suggested,
            parsedValue: parsed,
          ),
        );
      }
    }
    return result;
  }

  PlanApplyResult apply(
    List<Schedule> schedules,
    List<ValidatedPlanAction> actions,
  ) {
    var applied = 0;
    var skipped = 0;

    for (final action in actions) {
      final schedule = schedules
          .where((s) => s.id == action.scheduleId)
          .firstOrNull;
      final exercise = schedule?.exercises
          .where((e) => e.id == action.exerciseId)
          .firstOrNull;
      if (exercise == null) {
        skipped += 1;
        continue;
      }

      // Optimistic concurrency guard: never apply a stale AI diff silently.
      if (_currentValue(exercise, action.field) != action.currentValue) {
        skipped += 1;
        continue;
      }

      switch (action.field) {
        case 'weight':
          exercise.weight = action.parsedValue as double;
          break;
        case 'sets':
          exercise.set = action.parsedValue as int;
          break;
        case 'reps':
          exercise.reps = action.parsedValue as int;
          break;
        case 'target_min_reps':
          exercise.targetMinReps = action.parsedValue as int;
          break;
        case 'target_max_reps':
          exercise.targetMaxReps = action.parsedValue as int;
          break;
        case 'rest_seconds':
          exercise.restSeconds = action.parsedValue as int;
          break;
        case 'notes':
          exercise.notes = action.parsedValue as String;
          break;
        default:
          skipped += 1;
          continue;
      }
      applied += 1;
    }

    return PlanApplyResult(applied: applied, skipped: skipped);
  }

  (Schedule, Exercise)? _resolveTarget(
    ProposedPlanAction action,
    List<Schedule> schedules,
  ) {
    Schedule? schedule;
    if (action.scheduleId.isNotEmpty) {
      schedule = schedules.where((s) => s.id == action.scheduleId).firstOrNull;
      if (schedule == null) return null;
    }

    if (action.exerciseId.isNotEmpty) {
      final matches = <(Schedule, Exercise)>[];
      for (final candidateSchedule
          in schedule == null ? schedules : [schedule]) {
        for (final candidate in candidateSchedule.exercises) {
          if (candidate.id == action.exerciseId) {
            matches.add((candidateSchedule, candidate));
          }
        }
      }
      if (matches.length != 1) return null;
      return matches.single;
    }

    // Backward-compatible fallback for older local-model outputs. Names must be
    // globally unambiguous; otherwise the action is rejected.
    final target = action.target.trim().toLowerCase();
    if (target.isEmpty) return null;
    final matches = <(Schedule, Exercise)>[];
    for (final candidateSchedule in schedule == null ? schedules : [schedule]) {
      for (final candidate in candidateSchedule.exercises) {
        if (candidate.name.trim().toLowerCase() == target) {
          matches.add((candidateSchedule, candidate));
        }
      }
    }
    return matches.length == 1 ? matches.single : null;
  }

  Object? _parseSuggestedValue(String field, String raw) {
    final value = raw.trim();
    switch (field) {
      case 'weight':
        return double.tryParse(value.replaceAll(',', '.'));
      case 'sets':
      case 'reps':
      case 'target_min_reps':
      case 'target_max_reps':
      case 'rest_seconds':
        final numeric = double.tryParse(value.replaceAll(',', '.'));
        return numeric?.round();
      case 'notes':
        return value;
      default:
        return null;
    }
  }

  bool _isSemanticallyValid(
    ProposedPlanAction action,
    Exercise exercise,
    Object value,
  ) {
    switch (action.field) {
      case 'weight':
        final weight = value as double;
        if (!weight.isFinite || weight < 0 || weight > 1000) return false;
        if (action.action == 'increase_load' && weight <= exercise.weight) {
          return false;
        }
        if ((action.action == 'reduce_load' || action.action == 'deload') &&
            weight >= exercise.weight) {
          return false;
        }
        return true;
      case 'sets':
        final sets = value as int;
        return sets >= 1 && sets <= 20;
      case 'reps':
      case 'target_min_reps':
      case 'target_max_reps':
        final reps = value as int;
        return reps >= 1 && reps <= 100;
      case 'rest_seconds':
        final seconds = value as int;
        return seconds >= 0 && seconds <= 900;
      case 'notes':
        return (value as String).length <= 500;
      default:
        return false;
    }
  }

  String? _currentValue(Exercise exercise, String field) => switch (field) {
    'weight' => _formatDouble(exercise.weight),
    'sets' => exercise.set.toString(),
    'reps' => exercise.reps.toString(),
    'target_min_reps' => exercise.targetMinReps?.toString() ?? '',
    'target_max_reps' => exercise.targetMaxReps?.toString() ?? '',
    'rest_seconds' => exercise.restSeconds?.toString() ?? '0',
    'notes' => exercise.notes,
    _ => null,
  };

  String _displayValue(String field, Object value) {
    if (field == 'weight') return _formatDouble(value as double);
    return value.toString();
  }

  String _formatDouble(double value) {
    if (value == value.roundToDouble()) return value.toStringAsFixed(0);
    return value
        .toStringAsFixed(2)
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
