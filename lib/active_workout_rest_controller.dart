import 'dart:async';

import 'local_notifications.dart';
import 'models/workout.dart';

typedef RestNotificationScheduler = Future<void> Function({
  required int id,
  required DateTime endTime,
  required String exerciseName,
});
typedef RestNotificationCanceler = Future<void> Function(int id);
typedef RestStateChanged = void Function();
typedef RestFinished = void Function(String exerciseId, String? exerciseName);

/// Owns active-workout rest countdown state and notification scheduling.
///
/// UI effects (haptics, snackbars and session persistence) stay outside this
/// controller through [onFinished] and [onChanged]. This keeps the timer state
/// machine independently testable while preserving the screen's behavior.
class ActiveWorkoutRestController {
  ActiveWorkoutRestController({
    required List<WorkoutExercise> Function() exercises,
    required int Function(WorkoutExercise exercise) restSecondsFor,
    RestStateChanged? onChanged,
    RestFinished? onFinished,
    RestNotificationScheduler? scheduleNotification,
    RestNotificationCanceler? cancelNotification,
    DateTime Function()? now,
    this.tickInterval = const Duration(seconds: 1),
  }) : _exercises = exercises,
       _restSecondsFor = restSecondsFor,
       _onChanged = onChanged,
       _onFinished = onFinished,
       _scheduleNotification =
           scheduleNotification ?? LocalNotificationService.scheduleRestFinished,
       _cancelNotification = cancelNotification ?? LocalNotificationService.cancel,
       _now = now ?? DateTime.now;

  final List<WorkoutExercise> Function() _exercises;
  final int Function(WorkoutExercise exercise) _restSecondsFor;
  final RestStateChanged? _onChanged;
  final RestFinished? _onFinished;
  final RestNotificationScheduler _scheduleNotification;
  final RestNotificationCanceler _cancelNotification;
  final DateTime Function() _now;
  final Duration tickInterval;

  final Map<String, int> _remainingByExerciseId = {};
  Timer? _timer;

  bool get hasActiveRest => _remainingByExerciseId.isNotEmpty;

  int? remainingFor(String exerciseId) => _remainingByExerciseId[exerciseId];

  bool isActive(String exerciseId) =>
      _remainingByExerciseId.containsKey(exerciseId);

  WorkoutExercise? activeExercise() {
    for (final exercise in _exercises()) {
      if (isActive(exercise.id)) {
        return exercise;
      }
    }
    return null;
  }

  bool start(WorkoutExercise exercise) {
    final restSeconds = _restSecondsFor(exercise);
    if (restSeconds <= 0) return false;

    final startedAt = _now();
    _remainingByExerciseId[exercise.id] = restSeconds;
    exercise.activeRestSeconds = restSeconds;
    exercise.activeRestStartedAt = startedAt;
    _onChanged?.call();
    unawaited(
      _scheduleNotification(
        id: LocalNotificationService.restNotificationId(exercise.id),
        endTime: startedAt.add(Duration(seconds: restSeconds)),
        exerciseName: exercise.name,
      ),
    );
    _ensureTimerRunning();
    return true;
  }

  bool addThirtySeconds(WorkoutExercise exercise) {
    final currentSeconds = remainingFor(exercise.id);
    if (currentSeconds == null) {
      return start(exercise);
    }

    final nextSeconds = currentSeconds + 30;
    final startedAt = _now();
    _remainingByExerciseId[exercise.id] = nextSeconds;
    exercise.activeRestSeconds = nextSeconds;
    exercise.activeRestStartedAt = startedAt;
    _onChanged?.call();
    unawaited(
      _scheduleNotification(
        id: LocalNotificationService.restNotificationId(exercise.id),
        endTime: startedAt.add(Duration(seconds: nextSeconds)),
        exerciseName: exercise.name,
      ),
    );
    _ensureTimerRunning();
    return true;
  }

  bool subtractThirtySeconds(WorkoutExercise exercise) {
    final currentSeconds = remainingFor(exercise.id);
    if (currentSeconds == null) return false;

    final nextSeconds = (currentSeconds - 30).clamp(1, 1 << 31).toInt();
    final startedAt = _now();
    _remainingByExerciseId[exercise.id] = nextSeconds;
    exercise.activeRestSeconds = nextSeconds;
    exercise.activeRestStartedAt = startedAt;
    _onChanged?.call();
    final notificationId = LocalNotificationService.restNotificationId(
      exercise.id,
    );
    unawaited(_cancelNotification(notificationId));
    unawaited(
      _scheduleNotification(
        id: notificationId,
        endTime: startedAt.add(Duration(seconds: nextSeconds)),
        exerciseName: exercise.name,
      ),
    );
    return true;
  }

  bool stop(WorkoutExercise exercise) {
    if (!isActive(exercise.id) &&
        exercise.activeRestSeconds == null &&
        exercise.activeRestStartedAt == null) {
      return false;
    }

    _remainingByExerciseId.remove(exercise.id);
    exercise.activeRestSeconds = null;
    exercise.activeRestStartedAt = null;
    _onChanged?.call();
    unawaited(
      _cancelNotification(
        LocalNotificationService.restNotificationId(exercise.id),
      ),
    );
    _stopTimerIfIdle();
    return true;
  }

  bool updateConfiguredRest(WorkoutExercise exercise, int seconds) {
    final normalizedSeconds = seconds.clamp(0, 3600).toInt();
    final wasActive = isActive(exercise.id);
    exercise.restSeconds = normalizedSeconds;

    if (wasActive && normalizedSeconds == 0) {
      _remainingByExerciseId.remove(exercise.id);
      exercise.activeRestSeconds = null;
      exercise.activeRestStartedAt = null;
      _onChanged?.call();
      unawaited(
        _cancelNotification(
          LocalNotificationService.restNotificationId(exercise.id),
        ),
      );
      _stopTimerIfIdle();
      return true;
    }

    if (wasActive) {
      final startedAt = _now();
      _remainingByExerciseId[exercise.id] = normalizedSeconds;
      exercise.activeRestSeconds = normalizedSeconds;
      exercise.activeRestStartedAt = startedAt;
      final notificationId = LocalNotificationService.restNotificationId(
        exercise.id,
      );
      unawaited(_cancelNotification(notificationId));
      unawaited(
        _scheduleNotification(
          id: notificationId,
          endTime: startedAt.add(Duration(seconds: normalizedSeconds)),
          exerciseName: exercise.name,
        ),
      );
    }

    _onChanged?.call();
    return true;
  }

  void restore({bool notifyExpired = false}) {
    final now = _now();
    final expiredExerciseIds = <String>[];
    _remainingByExerciseId.clear();

    for (final exercise in _exercises()) {
      final startedAt = exercise.activeRestStartedAt;
      final duration = exercise.activeRestSeconds;
      if (startedAt == null || duration == null) continue;

      final remaining = duration - now.difference(startedAt).inSeconds;
      if (remaining > 0) {
        _remainingByExerciseId[exercise.id] = remaining;
        unawaited(
          _scheduleNotification(
            id: LocalNotificationService.restNotificationId(exercise.id),
            endTime: now.add(Duration(seconds: remaining)),
            exerciseName: exercise.name,
          ),
        );
      } else {
        exercise.activeRestStartedAt = null;
        exercise.activeRestSeconds = null;
        if (notifyExpired) expiredExerciseIds.add(exercise.id);
      }
    }

    if (_remainingByExerciseId.isNotEmpty) {
      _ensureTimerRunning();
    } else {
      _stopTimerIfIdle();
    }
    _onChanged?.call();

    for (final exerciseId in expiredExerciseIds) {
      _completeExpired(exerciseId);
    }
  }

  Future<void> cancelAll() async {
    _timer?.cancel();
    _timer = null;
    final exerciseIds = <String>{
      ..._remainingByExerciseId.keys,
      ..._exercises()
          .where(
            (exercise) =>
                exercise.activeRestStartedAt != null ||
                exercise.activeRestSeconds != null,
          )
          .map((exercise) => exercise.id),
    };

    _remainingByExerciseId.clear();
    for (final exercise in _exercises()) {
      exercise.activeRestSeconds = null;
      exercise.activeRestStartedAt = null;
    }
    _onChanged?.call();

    for (final exerciseId in exerciseIds) {
      await _cancelNotification(
        LocalNotificationService.restNotificationId(exerciseId),
      );
    }
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
  }

  void _ensureTimerRunning() {
    if (_timer != null) return;
    _timer = Timer.periodic(tickInterval, (_) => _tick());
  }

  void _tick() {
    final updatedCountdowns = <String, int>{};
    final finishedExerciseIds = <String>[];

    _remainingByExerciseId.forEach((exerciseId, remainingSeconds) {
      if (remainingSeconds > 1) {
        updatedCountdowns[exerciseId] = remainingSeconds - 1;
      } else {
        finishedExerciseIds.add(exerciseId);
      }
    });

    _remainingByExerciseId
      ..clear()
      ..addAll(updatedCountdowns);
    _onChanged?.call();
    _stopTimerIfIdle();

    for (final exerciseId in finishedExerciseIds) {
      _completeExpired(exerciseId);
    }
  }

  void _completeExpired(String exerciseId) {
    String? exerciseName;
    for (final exercise in _exercises()) {
      if (exercise.id == exerciseId) {
        exerciseName = exercise.name;
        exercise.activeRestSeconds = null;
        exercise.activeRestStartedAt = null;
        break;
      }
    }
    unawaited(
      _cancelNotification(LocalNotificationService.restNotificationId(exerciseId)),
    );
    _onFinished?.call(exerciseId, exerciseName);
  }

  void _stopTimerIfIdle() {
    if (_remainingByExerciseId.isNotEmpty) return;
    _timer?.cancel();
    _timer = null;
  }
}
