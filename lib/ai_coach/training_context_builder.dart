import '../models/body_log.dart';
import '../models/schedule.dart';
import '../models/workout.dart';
import 'ai_coach_memory.dart';
import 'ai_coach_user_profile.dart';

class TrainingContextBuilder {
  final DateTime? now;

  const TrainingContextBuilder({this.now});

  Map<String, dynamic> latestWorkout({
    required List<WorkoutSession> history,
    required List<Schedule> schedules,
    List<BodyLog> bodyLogs = const [],
    AiCoachUserProfile profile = const AiCoachUserProfile(),
    AiCoachMemory memory = const AiCoachMemory(),
  }) {
    final sorted = _sortedHistory(history);
    return _build(
      history: sorted.isEmpty ? const [] : [sorted.last],
      analyticsHistory: sorted,
      schedules: schedules,
      bodyLogs: bodyLogs,
      profile: profile,
      memory: memory,
      period: 'latest_workout',
    );
  }

  Map<String, dynamic> weekly({
    required List<WorkoutSession> history,
    required List<Schedule> schedules,
    List<BodyLog> bodyLogs = const [],
    AiCoachUserProfile profile = const AiCoachUserProfile(),
    AiCoachMemory memory = const AiCoachMemory(),
  }) {
    final reference = now ?? DateTime.now();
    final from = reference.subtract(const Duration(days: 7));
    final selected = _sortedHistory(
      history.where((session) => !session.startTime.isBefore(from)).toList(),
    );
    return _build(
      history: selected,
      analyticsHistory: _sortedHistory(history),
      schedules: schedules,
      bodyLogs: bodyLogs,
      profile: profile,
      memory: memory,
      period: 'last_7_days',
    );
  }

  Map<String, dynamic> recent({
    required List<WorkoutSession> history,
    required List<Schedule> schedules,
    List<BodyLog> bodyLogs = const [],
    AiCoachUserProfile profile = const AiCoachUserProfile(),
    AiCoachMemory memory = const AiCoachMemory(),
  }) {
    final reference = now ?? DateTime.now();
    final from = reference.subtract(const Duration(days: 56));
    final selected = _sortedHistory(
      history.where((session) => !session.startTime.isBefore(from)).toList(),
    );
    return _build(
      history: selected,
      analyticsHistory: selected,
      schedules: schedules,
      bodyLogs: bodyLogs,
      profile: profile,
      memory: memory,
      period: 'last_8_weeks',
    );
  }

  Map<String, dynamic> notes({
    required List<WorkoutSession> history,
    required List<Schedule> schedules,
    List<BodyLog> bodyLogs = const [],
    AiCoachUserProfile profile = const AiCoachUserProfile(),
    AiCoachMemory memory = const AiCoachMemory(),
  }) {
    return _build(
      history: _sortedHistory(history),
      analyticsHistory: _sortedHistory(history),
      schedules: schedules,
      bodyLogs: bodyLogs,
      profile: profile,
      memory: memory,
      period: 'training_notes',
    );
  }

  Map<String, dynamic> _build({
    required List<WorkoutSession> history,
    required List<WorkoutSession> analyticsHistory,
    required List<Schedule> schedules,
    required List<BodyLog> bodyLogs,
    required AiCoachUserProfile profile,
    required AiCoachMemory memory,
    required String period,
  }) {
    final metrics = _metrics(history);
    return {
      'generated_at': (now ?? DateTime.now()).toIso8601String(),
      'period': period,
      'workouts': history.map((session) => session.toJson()).toList(),
      'active_plans': schedules
          .where((schedule) => !schedule.isArchived)
          .map((schedule) => schedule.toJson())
          .toList(),
      'body_logs': bodyLogs.map((log) => log.toJson()).toList(),
      'user_profile': profile.toJson(),
      'coach_memory': memory.toJson(),
      'notes': _notes(history),
      'metrics': metrics,
      'deterministic_analytics': {
        ...metrics,
        'exercise_progress': _exerciseProgress(analyticsHistory),
      },
    };
  }

  List<WorkoutSession> _sortedHistory(List<WorkoutSession> history) {
    final sorted = [...history];
    sorted.sort((a, b) => a.startTime.compareTo(b.startTime));
    return sorted;
  }

  Map<String, dynamic> _metrics(List<WorkoutSession> history) {
    var totalVolume = 0.0;
    final exerciseVolume = <String, double>{};
    final muscleGroupVolume = <String, double>{};
    for (final session in history) {
      for (final exercise in session.exercises) {
        for (final set in exercise.sets.where((set) => set.isCompleted)) {
          final volume = set.weight * set.reps;
          totalVolume += volume;
          exerciseVolume.update(
            exercise.name,
            (value) => value + volume,
            ifAbsent: () => volume,
          );
          muscleGroupVolume.update(
            exercise.muscleGroup.name,
            (value) => value + volume,
            ifAbsent: () => volume,
          );
        }
      }
    }
    return {
      'sessions': history.length,
      'total_volume': totalVolume,
      'exercise_volume': exerciseVolume,
      'muscle_group_volume': muscleGroupVolume,
    };
  }

  Map<String, dynamic> _exerciseProgress(List<WorkoutSession> history) {
    final observations = <String, List<Map<String, dynamic>>>{};
    for (final session in history) {
      for (final exercise in session.exercises) {
        final completed = exercise.sets.where((set) => set.isCompleted).toList();
        if (completed.isEmpty) continue;
        final bestWeight = completed
            .map((set) => set.weight)
            .reduce((a, b) => a > b ? a : b);
        final volume = completed.fold<double>(
          0,
          (sum, set) => sum + set.weight * set.reps,
        );
        observations.putIfAbsent(exercise.name, () => []).add({
          'date': session.startTime.toIso8601String(),
          'best_weight': bestWeight,
          'volume': volume,
        });
      }
    }
    return observations.map((name, values) {
      final first = values.first;
      final last = values.last;
      return MapEntry(name, {
        'sessions': values.length,
        'first_best_weight': first['best_weight'],
        'latest_best_weight': last['best_weight'],
        'first_volume': first['volume'],
        'latest_volume': last['volume'],
      });
    });
  }

  List<String> _notes(List<WorkoutSession> history) {
    final notes = <String>[];
    for (final session in history) {
      for (final exercise in session.exercises) {
        final exerciseNote = exercise.notes.trim();
        if (exerciseNote.isNotEmpty) {
          notes.add('${exercise.name}: $exerciseNote');
        }
        for (final set in exercise.sets) {
          final setNote = set.notes.trim();
          if (setNote.isNotEmpty) notes.add('${exercise.name}: $setNote');
        }
      }
    }
    return notes;
  }
}
