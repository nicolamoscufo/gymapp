import 'models/workout.dart';
import 'workout_progression_analytics.dart';

class ExerciseDebrief {
  final String exerciseId;
  final String exerciseName;
  final ProgressionDecision progression;

  const ExerciseDebrief({
    required this.exerciseId,
    required this.exerciseName,
    required this.progression,
  });

  String get nextStep => progressionActionLabel(progression);
}

class PostWorkoutDebrief {
  final WorkoutSession session;
  final WorkoutSession? previousComparableSession;
  final double totalVolume;
  final double? volumeChangePercent;
  final int completedWorkSets;
  final int? completedWorkSetDelta;
  final double densityKgPerMinute;
  final double? densityChangePercent;
  final List<ExerciseDebrief> exercises;

  const PostWorkoutDebrief({
    required this.session,
    required this.previousComparableSession,
    required this.totalVolume,
    required this.volumeChangePercent,
    required this.completedWorkSets,
    required this.completedWorkSetDelta,
    required this.densityKgPerMinute,
    required this.densityChangePercent,
    required this.exercises,
  });

  bool get hasComparableSession => previousComparableSession != null;

  int get readyToProgressCount => exercises.where((entry) {
    return entry.progression.action == ProgressionAction.increaseLoad ||
        entry.progression.action == ProgressionAction.increaseReps;
  }).length;

  int get maintainCount => exercises
      .where((entry) => entry.progression.action == ProgressionAction.maintain)
      .length;

  int get deloadCount => exercises
      .where((entry) => entry.progression.action == ProgressionAction.deload)
      .length;
}

PostWorkoutDebrief buildPostWorkoutDebrief({
  required WorkoutSession session,
  required List<WorkoutSession> history,
}) {
  final previous = _latestComparableSession(session, history);
  final currentVolume = _sessionVolume(session);
  final currentSets = _completedWorkSets(session);
  final currentDensity = _trainingDensity(session, currentVolume);

  final previousVolume = previous == null ? null : _sessionVolume(previous);
  final previousSets = previous == null ? null : _completedWorkSets(previous);
  final previousDensity = previous == null
      ? null
      : _trainingDensity(previous, previousVolume!);

  final exerciseDebriefs = session.exercises
      .where(
        (exercise) =>
            exercise.sets.any((set) => set.isCompleted && !set.isWarmup),
      )
      .map(
        (exercise) => ExerciseDebrief(
          exerciseId: exercise.id,
          exerciseName: exercise.name,
          progression: buildProgressionDecision(
            exercise: exercise,
            history: history,
            excludeSessionId: session.id,
          ),
        ),
      )
      .toList();

  return PostWorkoutDebrief(
    session: session,
    previousComparableSession: previous,
    totalVolume: currentVolume,
    volumeChangePercent: _percentChange(currentVolume, previousVolume),
    completedWorkSets: currentSets,
    completedWorkSetDelta: previousSets == null
        ? null
        : currentSets - previousSets,
    densityKgPerMinute: currentDensity,
    densityChangePercent: _percentChange(currentDensity, previousDensity),
    exercises: exerciseDebriefs,
  );
}

WorkoutSession? _latestComparableSession(
  WorkoutSession session,
  List<WorkoutSession> history,
) {
  WorkoutSession? latest;
  final normalizedTitle = session.scheduleTitle.trim().toLowerCase();

  for (final candidate in history) {
    if (candidate.id == session.id ||
        !candidate.endTime.isBefore(session.endTime)) {
      continue;
    }

    final sameSchedule = session.scheduleId != null
        ? candidate.scheduleId == session.scheduleId
        : candidate.scheduleId == null &&
              candidate.scheduleTitle.trim().toLowerCase() == normalizedTitle;
    if (!sameSchedule) continue;

    if (latest == null || candidate.endTime.isAfter(latest.endTime)) {
      latest = candidate;
    }
  }
  return latest;
}

double _sessionVolume(WorkoutSession session) {
  return session.exercises
      .expand((exercise) => exercise.sets)
      .where((set) => set.isCompleted && !set.isWarmup)
      .fold<double>(0, (sum, set) => sum + set.weight * set.reps);
}

int _completedWorkSets(WorkoutSession session) {
  return session.exercises
      .expand((exercise) => exercise.sets)
      .where((set) => set.isCompleted && !set.isWarmup)
      .length;
}

double _trainingDensity(WorkoutSession session, double volume) {
  final minutes = session.endTime.difference(session.startTime).inSeconds / 60;
  return volume / (minutes <= 0 ? 1 : minutes);
}

double? _percentChange(double current, double? previous) {
  if (previous == null || previous <= 0) return null;
  return ((current - previous) / previous) * 100;
}
