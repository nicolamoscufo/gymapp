import 'dart:math' as math;

import 'models/exercise.dart';
import 'models/workout.dart';

enum HomeHistoryRangeFilter { all, last30, last90 }

class HomePrSummary {
  final String exerciseName;
  final String scheduleTitle;
  final DateTime date;

  const HomePrSummary({
    required this.exerciseName,
    required this.scheduleTitle,
    required this.date,
  });
}

class HomeExerciseProgressSummary {
  final String name;
  final DateTime latestDate;
  final double latestVolume;
  final double previousVolume;
  final double volumeDelta;
  final double latestBestSetVolume;
  final double previousBestSetVolume;
  final double bestSetVolumeDelta;

  const HomeExerciseProgressSummary({
    required this.name,
    required this.latestDate,
    required this.latestVolume,
    required this.previousVolume,
    required this.volumeDelta,
    required this.latestBestSetVolume,
    required this.previousBestSetVolume,
    required this.bestSetVolumeDelta,
  });

  bool get isImproved => volumeDelta > 0 || bestSetVolumeDelta > 0;
}

class HomeHistoryAnalytics {
  final List<WorkoutSession> history;

  const HomeHistoryAnalytics(this.history);

  String normalizeExerciseName(String name) => name.trim().toLowerCase();

  double setVolume(ExerciseSet set) => set.weight * set.reps;

  double exerciseVolume(WorkoutExercise exercise) {
    var volume = 0.0;
    for (final set in exercise.sets) {
      if (set.isCompleted && !set.isWarmup) {
        volume += setVolume(set);
      }
    }
    return volume;
  }

  double bestSetVolume(WorkoutExercise exercise) {
    var bestVolume = 0.0;
    for (final set in exercise.sets) {
      if (!set.isCompleted || set.isWarmup) continue;
      bestVolume = math.max(bestVolume, setVolume(set));
    }
    return bestVolume;
  }

  int completedWorkSets(WorkoutExercise exercise) {
    return exercise.sets
        .where((set) => set.isCompleted && !set.isWarmup)
        .length;
  }

  WorkoutExercise? previousExerciseBefore(
    WorkoutSession session,
    WorkoutExercise exercise,
  ) {
    final exerciseName = normalizeExerciseName(exercise.name);
    final olderSessions = List<WorkoutSession>.from(history)
      ..sort((a, b) => b.endTime.compareTo(a.endTime));

    for (final candidateSession in olderSessions) {
      if (!candidateSession.endTime.isBefore(session.endTime)) continue;

      for (final candidateExercise in candidateSession.exercises) {
        if (normalizeExerciseName(candidateExercise.name) == exerciseName &&
            completedWorkSets(candidateExercise) > 0) {
          return candidateExercise;
        }
      }
    }

    return null;
  }

  bool exerciseHasPrAtSession(
    WorkoutSession session,
    WorkoutExercise exercise,
  ) {
    final exerciseName = normalizeExerciseName(exercise.name);
    final previousExercises = history
        .where(
          (candidateSession) =>
              candidateSession.endTime.isBefore(session.endTime),
        )
        .expand((candidateSession) => candidateSession.exercises)
        .where(
          (candidateExercise) =>
              normalizeExerciseName(candidateExercise.name) == exerciseName,
        )
        .toList();
    if (previousExercises.isEmpty) return false;

    double bestWeight = 0;
    int bestReps = 0;
    double bestSet = 0;
    double bestExercise = 0;
    for (final previousExercise in previousExercises) {
      bestExercise = math.max(bestExercise, exerciseVolume(previousExercise));
      for (final set in previousExercise.sets) {
        if (!set.isCompleted || set.isWarmup) continue;
        bestWeight = math.max(bestWeight, set.weight);
        bestReps = math.max(bestReps, set.reps);
        bestSet = math.max(bestSet, setVolume(set));
      }
    }

    for (final set in exercise.sets) {
      if (!set.isCompleted || set.isWarmup) continue;
      if (set.weight > bestWeight ||
          set.reps > bestReps ||
          setVolume(set) > bestSet) {
        return true;
      }
    }

    return exerciseVolume(exercise) > bestExercise;
  }

  bool sessionHasPr(WorkoutSession session) {
    return session.exercises.any(
      (exercise) => exerciseHasPrAtSession(session, exercise),
    );
  }

  List<WorkoutSession> filteredSessions(
    List<WorkoutSession> sortedHistory, {
    required HomeHistoryRangeFilter range,
    required String query,
    required bool onlyPr,
    DateTime? now,
  }) {
    final reference = now ?? DateTime.now();
    final minDate = switch (range) {
      HomeHistoryRangeFilter.all => null,
      HomeHistoryRangeFilter.last30 => reference.subtract(
        const Duration(days: 30),
      ),
      HomeHistoryRangeFilter.last90 => reference.subtract(
        const Duration(days: 90),
      ),
    };
    final normalizedQuery = query.trim().toLowerCase();

    return sortedHistory.where((session) {
      if (minDate != null && session.endTime.isBefore(minDate)) return false;
      if (onlyPr && !sessionHasPr(session)) return false;
      if (normalizedQuery.isEmpty) return true;

      return session.scheduleTitle.toLowerCase().contains(normalizedQuery) ||
          session.exercises.any((exercise) {
            return exercise.name.toLowerCase().contains(normalizedQuery) ||
                exercise.muscleGroup.label.toLowerCase().contains(
                  normalizedQuery,
                );
          });
    }).toList();
  }

  List<HomePrSummary> buildRecentPrSummaries({int limit = 8}) {
    final summaries = <HomePrSummary>[];
    final sortedHistory = List<WorkoutSession>.from(history)
      ..sort((a, b) => b.endTime.compareTo(a.endTime));

    for (final session in sortedHistory) {
      for (final exercise in session.exercises) {
        if (exerciseHasPrAtSession(session, exercise)) {
          summaries.add(
            HomePrSummary(
              exerciseName: exercise.name,
              scheduleTitle: session.scheduleTitle,
              date: session.endTime,
            ),
          );
        }
      }
      if (summaries.length >= limit) break;
    }

    return summaries.take(limit).toList();
  }

  List<HomeExerciseProgressSummary> buildExerciseProgressSummaries() {
    final occurrencesByExercise =
        <String, List<({WorkoutSession session, WorkoutExercise exercise})>>{};
    final sortedHistory = List<WorkoutSession>.from(history)
      ..sort((a, b) => a.endTime.compareTo(b.endTime));

    for (final session in sortedHistory) {
      for (final exercise in session.exercises) {
        if (completedWorkSets(exercise) == 0) continue;
        final key = normalizeExerciseName(exercise.name);
        occurrencesByExercise.putIfAbsent(key, () => []).add((
          session: session,
          exercise: exercise,
        ));
      }
    }

    final summaries = <HomeExerciseProgressSummary>[];
    for (final occurrences in occurrencesByExercise.values) {
      if (occurrences.length < 2) continue;

      final latest = occurrences.last;
      final previous = occurrences[occurrences.length - 2];
      final latestVolume = exerciseVolume(latest.exercise);
      final previousVolume = exerciseVolume(previous.exercise);
      final latestBestSetVolume = bestSetVolume(latest.exercise);
      final previousBestSetVolume = bestSetVolume(previous.exercise);
      summaries.add(
        HomeExerciseProgressSummary(
          name: latest.exercise.name,
          latestDate: latest.session.endTime,
          latestVolume: latestVolume,
          previousVolume: previousVolume,
          volumeDelta: latestVolume - previousVolume,
          latestBestSetVolume: latestBestSetVolume,
          previousBestSetVolume: previousBestSetVolume,
          bestSetVolumeDelta: latestBestSetVolume - previousBestSetVolume,
        ),
      );
    }

    summaries.sort((a, b) {
      if (a.isImproved != b.isImproved) return a.isImproved ? -1 : 1;
      return b.volumeDelta.compareTo(a.volumeDelta);
    });
    return summaries;
  }
}
