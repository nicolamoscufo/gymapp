import '../models/body_log.dart';
import '../models/schedule.dart';
import '../models/workout.dart';
import '../workout_progression_analytics.dart';
import 'ai_coach_memory.dart';
import 'ai_coach_user_profile.dart';

class TrainingContextBuilder {
  final DateTime? now;

  const TrainingContextBuilder({this.now});

  DateTime get _now => now ?? DateTime.now();

  Map<String, dynamic> latestWorkout({
    required List<WorkoutSession> history,
    required List<Schedule> schedules,
    List<BodyLog> bodyLogs = const [],
    AiCoachUserProfile profile = const AiCoachUserProfile(),
    AiCoachMemory memory = const AiCoachMemory(),
  }) {
    final sorted = [...history]
      ..sort((a, b) => a.startTime.compareTo(b.startTime));
    final latest = sorted.isEmpty ? <WorkoutSession>[] : [sorted.last];
    return _build(
      history: latest,
      analyticsHistory: sorted,
      schedules: schedules,
      bodyLogs: bodyLogs,
      profile: profile,
      memory: memory,
    );
  }

  Map<String, dynamic> weekly({
    required List<WorkoutSession> history,
    required List<Schedule> schedules,
    List<BodyLog> bodyLogs = const [],
    AiCoachUserProfile profile = const AiCoachUserProfile(),
    AiCoachMemory memory = const AiCoachMemory(),
  }) {
    final cutoff = _now.subtract(const Duration(days: 7));
    final weeklyHistory = history
        .where((entry) => !entry.startTime.isBefore(cutoff))
        .toList();
    return _build(
      history: weeklyHistory,
      analyticsHistory: weeklyHistory,
      schedules: schedules,
      bodyLogs: bodyLogs,
      profile: profile,
      memory: memory,
    );
  }

  Map<String, dynamic> recent({
    required List<WorkoutSession> history,
    required List<Schedule> schedules,
    List<BodyLog> bodyLogs = const [],
    AiCoachUserProfile profile = const AiCoachUserProfile(),
    AiCoachMemory memory = const AiCoachMemory(),
  }) {
    final sorted = [...history]
      ..sort((a, b) => b.startTime.compareTo(a.startTime));
    final recentHistory = sorted.take(12).toList().reversed.toList();
    return _build(
      history: recentHistory,
      analyticsHistory: recentHistory,
      schedules: schedules,
      bodyLogs: bodyLogs,
      profile: profile,
      memory: memory,
    );
  }

  Map<String, dynamic> notes({
    required List<WorkoutSession> history,
    required List<Schedule> schedules,
    List<BodyLog> bodyLogs = const [],
    AiCoachUserProfile profile = const AiCoachUserProfile(),
    AiCoachMemory memory = const AiCoachMemory(),
  }) => recent(
    history: history,
    schedules: schedules,
    bodyLogs: bodyLogs,
    profile: profile,
    memory: memory,
  );

  Map<String, dynamic> _build({
    required List<WorkoutSession> history,
    required List<WorkoutSession> analyticsHistory,
    required List<Schedule> schedules,
    required List<BodyLog> bodyLogs,
    required AiCoachUserProfile profile,
    required AiCoachMemory memory,
  }) {
    final workouts = history.map(_workoutJson).toList();
    final activePlans = schedules
        .where((schedule) => !schedule.isArchived)
        .map((schedule) => schedule.toJson())
        .toList();
    final totalVolume = _totalVolume(history);
    final exerciseVolume = _exerciseVolume(history);
    final muscleGroupVolume = _muscleGroupVolume(history);
    final notes = _collectNotes(history);

    return {
      'generated_at': _now.toIso8601String(),
      'user_profile': profile.toJson(),
      'memory': memory.toJson(),
      'active_plans': activePlans,
      'workouts': workouts,
      'body_logs': bodyLogs.map((entry) => entry.toJson()).toList(),
      'notes': notes,
      'metrics': {
        'sessions': history.length,
        'total_volume': totalVolume,
        'exercise_volume': exerciseVolume,
        'muscle_group_volume': muscleGroupVolume,
      },
      'deterministic_analytics': {
        'exercise_progress': _exerciseProgress(history),
        'progression_recommendations': _progressionRecommendations(
          analyticsHistory,
        ),
        'session_count': history.length,
        'latest_session_at': history.isEmpty
            ? null
            : history
                  .map((e) => e.startTime)
                  .reduce((a, b) => a.isAfter(b) ? a : b)
                  .toIso8601String(),
      },
    };
  }

  Map<String, dynamic> _workoutJson(WorkoutSession session) => {
    'id': session.id,
    'name': session.scheduleTitle,
    'start_time': session.startTime.toIso8601String(),
    'end_time': session.endTime.toIso8601String(),
    'duration_minutes': session.endTime.difference(session.startTime).inMinutes,
    'exercises': session.exercises
        .map(
          (exercise) => {
            'name': exercise.name,
            'notes': exercise.notes,
            'muscle_group': exercise.muscleGroup.name,
            'equipment': exercise.equipment,
            'movement_pattern': exercise.movementPattern,
            'sets': exercise.sets
                .map(
                  (set) => {
                    'weight': set.weight,
                    'reps': set.reps,
                    'completed': set.isCompleted,
                    'warmup': set.isWarmup,
                    'rpe': set.rpe,
                    'rir': set.rir,
                    'notes': set.notes,
                  },
                )
                .toList(),
          },
        )
        .toList(),
  };

  double _totalVolume(List<WorkoutSession> history) {
    var total = 0.0;
    for (final session in history) {
      for (final exercise in session.exercises) {
        for (final set in exercise.sets) {
          if (set.isCompleted && !set.isWarmup) {
            total += set.weight * set.reps;
          }
        }
      }
    }
    return total;
  }

  Map<String, double> _exerciseVolume(List<WorkoutSession> history) {
    final result = <String, double>{};
    for (final session in history) {
      for (final exercise in session.exercises) {
        var volume = 0.0;
        for (final set in exercise.sets) {
          if (set.isCompleted && !set.isWarmup) {
            volume += set.weight * set.reps;
          }
        }
        result.update(
          exercise.name,
          (value) => value + volume,
          ifAbsent: () => volume,
        );
      }
    }
    return result;
  }

  Map<String, double> _muscleGroupVolume(List<WorkoutSession> history) {
    final result = <String, double>{};
    for (final session in history) {
      for (final exercise in session.exercises) {
        var volume = 0.0;
        for (final set in exercise.sets) {
          if (set.isCompleted && !set.isWarmup) {
            volume += set.weight * set.reps;
          }
        }
        final key = exercise.muscleGroup.name;
        result.update(key, (value) => value + volume, ifAbsent: () => volume);
      }
    }
    return result;
  }

  List<String> _collectNotes(List<WorkoutSession> history) {
    final notes = <String>[];
    for (final session in history) {
      for (final exercise in session.exercises) {
        final exerciseNote = exercise.notes.trim();
        if (exerciseNote.isNotEmpty) {
          notes.add('${exercise.name}: $exerciseNote');
        }
        for (final set in exercise.sets) {
          final setNote = set.notes.trim();
          if (setNote.isNotEmpty) {
            notes.add('${exercise.name}: $setNote');
          }
        }
      }
    }
    return notes;
  }

  Map<String, dynamic> _exerciseProgress(List<WorkoutSession> history) {
    final result = <String, List<Map<String, dynamic>>>{};
    for (final session in history) {
      for (final exercise in session.exercises) {
        final workingSets = exercise.sets
            .where((set) => set.isCompleted && !set.isWarmup)
            .toList();
        if (workingSets.isEmpty) {
          continue;
        }
        final bestWeight = workingSets
            .map((set) => set.weight)
            .reduce((a, b) => a > b ? a : b);
        final totalReps = workingSets.fold<int>(
          0,
          (sum, set) => sum + set.reps,
        );
        final volume = workingSets.fold<double>(
          0,
          (sum, set) => sum + set.weight * set.reps,
        );
        final estimatedOneRepMax = bestEstimatedOneRepMaxForSets(workingSets);
        result.putIfAbsent(exercise.name, () => []).add({
          'date': session.startTime.toIso8601String(),
          'best_weight': bestWeight,
          'total_reps': totalReps,
          'volume': volume,
          'estimated_1rm': estimatedOneRepMax,
        });
      }
    }
    return result;
  }

  List<Map<String, dynamic>> _progressionRecommendations(
    List<WorkoutSession> history,
  ) {
    if (history.isEmpty) {
      return const [];
    }

    final sorted = [...history]
      ..sort((a, b) => a.startTime.compareTo(b.startTime));
    final latest = sorted.last;
    final previous = sorted.where((session) => session.id != latest.id).toList();

    return latest.exercises.map((exercise) {
      final decision = buildProgressionDecision(
        exercise: exercise,
        history: previous,
      );
      return {
        'exercise': exercise.name,
        ...decision.toJson(),
      };
    }).toList();
  }
}
