import 'active_workout_session_builder.dart';
import 'models/exercise.dart';
import 'models/workout.dart';

class RemovedWorkoutExercise {
  const RemovedWorkoutExercise({
    required this.exercise,
    required this.index,
    required this.originalSupersetGroup,
    required this.originalSupersetMemberIds,
  });

  final WorkoutExercise exercise;
  final int index;
  final int? originalSupersetGroup;
  final Set<String> originalSupersetMemberIds;
}

/// Owns structural mutations of the active workout session.
///
/// UI concerns such as pickers, haptics, scrolling, snackbars and rest-timer
/// cancellation intentionally stay in the screen. This manager only mutates the
/// session graph and returns enough information for those UI effects.
class ActiveWorkoutExerciseManager {
  ActiveWorkoutExerciseManager({
    required this.session,
    required this.sessionBuilder,
  });

  final WorkoutSession session;
  final ActiveWorkoutSessionBuilder sessionBuilder;

  WorkoutSession? previousSessionForAddedExercises() {
    WorkoutSession? latestSession;
    for (final candidate in sessionBuilder.history) {
      if (candidate.id == session.id ||
          !candidate.endTime.isBefore(session.endTime)) {
        continue;
      }

      final sameSchedule =
          (session.scheduleId != null &&
              candidate.scheduleId == session.scheduleId) ||
          (candidate.scheduleId == null &&
              candidate.scheduleTitle == session.scheduleTitle);
      if (!sameSchedule) continue;

      if (latestSession == null ||
          candidate.endTime.isAfter(latestSession.endTime)) {
        latestSession = candidate;
      }
    }
    return latestSession;
  }

  List<WorkoutExercise> addExercises(List<Exercise> exercises) {
    if (exercises.isEmpty) return const [];
    final previousSession = previousSessionForAddedExercises();
    final added = exercises
        .map(
          (exercise) => sessionBuilder.workoutExerciseFromExercise(
            exercise,
            previousSession,
            keepSourceExerciseId: false,
          ),
        )
        .toList();
    session.exercises.addAll(added);
    return added;
  }

  WorkoutExercise? replaceExercise(
    WorkoutExercise exercise,
    Exercise replacementTemplate,
  ) {
    final index = _indexOf(exercise);
    if (index < 0) return null;

    final replacement = sessionBuilder.workoutExerciseFromExercise(
      replacementTemplate,
      previousSessionForAddedExercises(),
      keepSourceExerciseId: false,
    )..supersetGroup = exercise.supersetGroup;
    session.exercises[index] = replacement;
    return replacement;
  }

  WorkoutExercise? duplicateExercise(WorkoutExercise exercise) {
    final index = _indexOf(exercise);
    if (index < 0) return null;

    final duplicate = sessionBuilder.workoutExerciseFromExercise(
      sessionBuilder.exerciseFromWorkoutExercise(exercise),
      null,
      keepSourceExerciseId: false,
    )..supersetGroup = null;

    duplicate.sets = exercise.sets
        .map(
          (set) => ExerciseSet(
            weight: set.weight,
            reps: set.reps,
            type: set.type,
            rpe: set.rpe,
            rir: set.rir,
            notes: set.notes,
          ),
        )
        .toList();
    duplicate.previousWeights = List<double>.from(exercise.previousWeights);
    duplicate.previousReps = List<int>.from(exercise.previousReps);

    session.exercises.insert(index + 1, duplicate);
    return duplicate;
  }

  bool moveExercise(WorkoutExercise exercise, int delta) {
    final index = _indexOf(exercise);
    if (index < 0) return false;
    final nextIndex = index + delta;
    if (nextIndex < 0 || nextIndex >= session.exercises.length) return false;

    final moved = session.exercises.removeAt(index);
    session.exercises.insert(nextIndex, moved);
    return true;
  }

  RemovedWorkoutExercise? removeExercise(WorkoutExercise exercise) {
    final index = _indexOf(exercise);
    if (index < 0) return null;

    final group = exercise.supersetGroup;
    final memberIds = group == null
        ? <String>{}
        : session.exercises
              .where((candidate) => candidate.supersetGroup == group)
              .map((candidate) => candidate.id)
              .toSet();

    session.exercises.removeAt(index);
    cleanupSupersetGroup(group);

    return RemovedWorkoutExercise(
      exercise: exercise,
      index: index,
      originalSupersetGroup: group,
      originalSupersetMemberIds: memberIds,
    );
  }

  bool restoreRemoved(RemovedWorkoutExercise removal) {
    if (session.exercises.any((item) => item.id == removal.exercise.id)) {
      return false;
    }

    final restoreIndex = removal.index
        .clamp(0, session.exercises.length)
        .toInt();
    session.exercises.insert(restoreIndex, removal.exercise);

    final group = removal.originalSupersetGroup;
    if (group != null) {
      for (final member in session.exercises) {
        if (removal.originalSupersetMemberIds.contains(member.id)) {
          member.supersetGroup = group;
        }
      }
    }
    return true;
  }

  int nextSupersetGroupId() {
    var maxGroup = 0;
    for (final exercise in session.exercises) {
      final group = exercise.supersetGroup;
      if (group != null && group > maxGroup) maxGroup = group;
    }
    return maxGroup + 1;
  }

  List<WorkoutExercise> supersetMembers(WorkoutExercise exercise) {
    final group = exercise.supersetGroup;
    if (group == null) return const [];
    return session.exercises
        .where((candidate) => candidate.supersetGroup == group)
        .toList();
  }

  bool hasPendingDropContinuation(
    WorkoutExercise exercise,
    int completedSetIndex,
  ) {
    if (completedSetIndex < 0 ||
        completedSetIndex >= exercise.sets.length - 1) {
      return false;
    }

    final nextSet = exercise.sets[completedSetIndex + 1];
    return nextSet.type == SetType.drop && !nextSet.isCompleted;
  }

  bool shouldStartRestAfterSet(
    WorkoutExercise exercise, {
    int? completedSetIndex,
  }) {
    if (completedSetIndex != null &&
        hasPendingDropContinuation(exercise, completedSetIndex)) {
      return false;
    }

    final members = supersetMembers(exercise);
    return members.length < 2 || members.last.id == exercise.id;
  }

  WorkoutExercise? nextSupersetMember(WorkoutExercise exercise) {
    final members = supersetMembers(exercise);
    if (members.length < 2) return null;
    final currentIndex = members.indexWhere(
      (member) => member.id == exercise.id,
    );
    if (currentIndex < 0) return null;
    return members[(currentIndex + 1) % members.length];
  }

  WorkoutExercise? nextSupersetMemberAfterSet(
    WorkoutExercise exercise,
    int completedSetIndex,
  ) {
    if (hasPendingDropContinuation(exercise, completedSetIndex)) {
      return null;
    }
    return nextSupersetMember(exercise);
  }

  bool removeFromSuperset(WorkoutExercise exercise) {
    if (_indexOf(exercise) < 0 || exercise.supersetGroup == null) return false;
    final oldGroup = exercise.supersetGroup;
    exercise.supersetGroup = null;
    cleanupSupersetGroup(oldGroup);
    return true;
  }

  bool linkSuperset(WorkoutExercise exercise, WorkoutExercise target) {
    if (exercise.id == target.id ||
        _indexOf(exercise) < 0 ||
        _indexOf(target) < 0) {
      return false;
    }

    final oldGroup = exercise.supersetGroup;
    final group = target.supersetGroup ?? oldGroup ?? nextSupersetGroupId();
    exercise.supersetGroup = group;
    target.supersetGroup = group;
    if (oldGroup != null && oldGroup != group) {
      cleanupSupersetGroup(oldGroup);
    }
    return true;
  }

  void cleanupSupersetGroup(int? group) {
    if (group == null) return;
    final members = session.exercises
        .where((exercise) => exercise.supersetGroup == group)
        .toList();
    if (members.length < 2) {
      for (final member in members) {
        member.supersetGroup = null;
      }
    }
  }

  int _indexOf(WorkoutExercise exercise) {
    return session.exercises.indexWhere((item) => item.id == exercise.id);
  }
}
