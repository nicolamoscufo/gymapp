import 'package:flutter/material.dart';

import 'models/workout.dart';

/// Owns focus navigation and scroll anchors for the active workout screen.
///
/// The screen keeps workout mutations and persistence; this controller only
/// tracks which exercise is focused and where exercise/set rows live in the
/// scrollable viewport.
class ActiveWorkoutFocusController {
  final Map<String, GlobalKey> _exerciseCardKeys = <String, GlobalKey>{};
  final Map<String, GlobalKey> _setRowKeys = <String, GlobalKey>{};

  final ScrollController scrollController;
  String? focusedExerciseId;

  ActiveWorkoutFocusController({ScrollController? scrollController})
    : scrollController = scrollController ?? ScrollController();

  GlobalKey exerciseCardKey(String exerciseId) {
    return _exerciseCardKeys.putIfAbsent(exerciseId, GlobalKey.new);
  }

  GlobalKey setRowKey(String setId) {
    return _setRowKeys.putIfAbsent(setId, GlobalKey.new);
  }

  void removeExercise(String exerciseId) {
    _exerciseCardKeys.remove(exerciseId);
    if (focusedExerciseId == exerciseId) {
      focusedExerciseId = null;
    }
  }

  String? effectiveFocusedExerciseId(
    List<WorkoutExercise> exercises, {
    required bool editCompletedSession,
  }) {
    if (editCompletedSession) return null;

    final explicitId = focusedExerciseId;
    if (explicitId != null &&
        exercises.any((exercise) => exercise.id == explicitId)) {
      return explicitId;
    }

    for (final exercise in exercises) {
      if (exercise.sets.any((set) => !set.isCompleted)) {
        return exercise.id;
      }
    }

    return exercises.isEmpty ? null : exercises.last.id;
  }

  Future<void> scrollToSet({
    required List<WorkoutExercise> exercises,
    required String exerciseId,
    required String setId,
  }) async {
    var setContext = _setRowKeys[setId]?.currentContext;
    if (setContext != null && setContext.mounted) {
      await Scrollable.ensureVisible(
        setContext,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
        alignment: 0.28,
      );
      return;
    }

    final exerciseContext = _exerciseCardKeys[exerciseId]?.currentContext;
    if (exerciseContext != null && exerciseContext.mounted) {
      await Scrollable.ensureVisible(
        exerciseContext,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
        alignment: 0.08,
      );
      await Future<void>.delayed(const Duration(milliseconds: 24));
      setContext = _setRowKeys[setId]?.currentContext;
      if (setContext != null && setContext.mounted) {
        await Scrollable.ensureVisible(
          setContext,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          alignment: 0.28,
        );
      }
      return;
    }

    if (!scrollController.hasClients || exercises.isEmpty) return;

    final exerciseIndex = exercises.indexWhere(
      (exercise) => exercise.id == exerciseId,
    );
    if (exerciseIndex < 0) return;

    final position = scrollController.position;
    final fraction = exercises.length <= 1
        ? 0.0
        : exerciseIndex / (exercises.length - 1);
    await scrollController.animateTo(
      position.maxScrollExtent * fraction,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
    await Future<void>.delayed(const Duration(milliseconds: 24));

    final revealedExerciseContext =
        _exerciseCardKeys[exerciseId]?.currentContext;
    if (revealedExerciseContext != null && revealedExerciseContext.mounted) {
      await Scrollable.ensureVisible(
        revealedExerciseContext,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        alignment: 0.08,
      );
    }
    await Future<void>.delayed(const Duration(milliseconds: 24));

    setContext = _setRowKeys[setId]?.currentContext;
    if (setContext != null && setContext.mounted) {
      await Scrollable.ensureVisible(
        setContext,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        alignment: 0.28,
      );
    }
  }

  void scrollToExercise(String exerciseId) {
    final context = _exerciseCardKeys[exerciseId]?.currentContext;
    if (context == null || !context.mounted) return;
    Scrollable.ensureVisible(
      context,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      alignment: 0.08,
    );
  }

  void dispose() {
    scrollController.dispose();
  }
}
