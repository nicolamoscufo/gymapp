from pathlib import Path
import re


def sub_once(text: str, pattern: str, replacement: str, label: str) -> str:
    updated, count = re.subn(pattern, replacement, text, count=1, flags=re.S)
    if count != 1:
        raise RuntimeError(f'{label}: expected 1 replacement, got {count}')
    return updated


Path('lib/active_workout_insights.dart').write_text(r'''import 'models/workout.dart';
import 'workout_progression_analytics.dart';

/// Pure, UI-independent analytics used while logging an active workout.
///
/// Keeping historical comparisons here prevents the workout screen from
/// owning both rendering and PR/domain logic, and makes the behavior directly
/// unit-testable.
class ActiveWorkoutInsights {
  final List<WorkoutSession> history;
  final String currentSessionId;

  const ActiveWorkoutInsights({
    required this.history,
    required this.currentSessionId,
  });

  Iterable<WorkoutSession> get comparisonHistory => history.where(
    (session) => session.id != currentSessionId,
  );

  double setVolume(ExerciseSet set) => set.weight * set.reps;

  double completedExerciseVolume(WorkoutExercise exercise) {
    return exercise.sets
        .where((set) => set.isCompleted && !set.isWarmup)
        .fold<double>(0, (total, set) => total + setVolume(set));
  }

  Iterable<WorkoutExercise> historicalExercisesFor(WorkoutExercise exercise) {
    final exerciseName = _normalizeExerciseName(exercise.name);
    return comparisonHistory.expand((historySession) {
      return historySession.exercises.where(
        (historicalExercise) =>
            _normalizeExerciseName(historicalExercise.name) == exerciseName,
      );
    });
  }

  Iterable<ExerciseSet> historicalWorkSetsFor(WorkoutExercise exercise) {
    return historicalExercisesFor(exercise)
        .expand((historicalExercise) => historicalExercise.sets)
        .where((set) => set.isCompleted && !set.isWarmup);
  }

  double? maxHistoricalWeightFor(WorkoutExercise exercise) {
    double? maxWeight;
    for (final set in historicalWorkSetsFor(exercise)) {
      if (maxWeight == null || set.weight > maxWeight) {
        maxWeight = set.weight;
      }
    }
    return maxWeight;
  }

  int? maxHistoricalRepsFor(WorkoutExercise exercise) {
    int? maxReps;
    for (final set in historicalWorkSetsFor(exercise)) {
      if (maxReps == null || set.reps > maxReps) {
        maxReps = set.reps;
      }
    }
    return maxReps;
  }

  double? bestHistoricalSetVolumeFor(WorkoutExercise exercise) {
    double? bestVolume;
    for (final set in historicalWorkSetsFor(exercise)) {
      final volume = setVolume(set);
      if (bestVolume == null || volume > bestVolume) {
        bestVolume = volume;
      }
    }
    return bestVolume;
  }

  double? bestHistoricalExerciseVolumeFor(WorkoutExercise exercise) {
    double? bestVolume;
    for (final historicalExercise in historicalExercisesFor(exercise)) {
      final volume = completedExerciseVolume(historicalExercise);
      if (volume <= 0) {
        continue;
      }
      if (bestVolume == null || volume > bestVolume) {
        bestVolume = volume;
      }
    }
    return bestVolume;
  }

  int? lastCompletedWorkSetIndex(WorkoutExercise exercise) {
    for (var index = exercise.sets.length - 1; index >= 0; index--) {
      final set = exercise.sets[index];
      if (set.isCompleted && !set.isWarmup) {
        return index;
      }
    }
    return null;
  }

  List<String> personalRecordLabelsFor(
    WorkoutExercise exercise,
    ExerciseSet set,
    int setIndex,
  ) {
    if (!set.isCompleted || set.isWarmup) {
      return const [];
    }

    final labels = <String>[];
    final maxWeight = maxHistoricalWeightFor(exercise);
    if (maxWeight != null && set.weight > maxWeight) {
      labels.add('PR kg');
    }

    final maxReps = maxHistoricalRepsFor(exercise);
    if (maxReps != null && set.reps > maxReps) {
      labels.add('PR reps');
    }

    final bestSetVolume = bestHistoricalSetVolumeFor(exercise);
    if (bestSetVolume != null && setVolume(set) > bestSetVolume) {
      labels.add('PR set');
    }

    final setEstimatedOneRepMax = estimateOneRepMax(set.weight, set.reps);
    final historicalEstimatedOneRepMax = historicalBestEstimatedOneRepMax(
      history: history,
      exerciseName: exercise.name,
      excludeSessionId: currentSessionId,
    );
    if (setEstimatedOneRepMax != null &&
        historicalEstimatedOneRepMax != null &&
        setEstimatedOneRepMax > historicalEstimatedOneRepMax + 0.05) {
      labels.add('PR e1RM');
    }

    final bestExerciseVolume = bestHistoricalExerciseVolumeFor(exercise);
    if (bestExerciseVolume != null &&
        lastCompletedWorkSetIndex(exercise) == setIndex &&
        completedExerciseVolume(exercise) > bestExerciseVolume) {
      labels.add('PR volume');
    }

    return labels;
  }

  int sessionPrCount(WorkoutSession session) {
    var count = 0;
    for (final exercise in session.exercises) {
      for (var index = 0; index < exercise.sets.length; index++) {
        if (personalRecordLabelsFor(
          exercise,
          exercise.sets[index],
          index,
        ).isNotEmpty) {
          count++;
        }
      }
    }
    return count;
  }

  String _normalizeExerciseName(String name) => name.trim().toLowerCase();
}
''')

Path('lib/home_data_policy.dart').write_text(r'''import 'app_preferences.dart';
import 'models/exercise.dart';
import 'models/schedule.dart';
import 'models/workout.dart';

/// Pure data-normalization and ordering rules shared by the Home screen.
class HomeDataPolicy {
  const HomeDataPolicy._();

  static bool applyBackoffReductionToExercises(
    List<Exercise> exercises,
    double reductionPercent,
  ) {
    var changed = false;
    final normalized = AppPreferences.normalizeBackoffReductionPercent(
      reductionPercent,
    );
    for (final exercise in exercises) {
      if (exercise.backoffReductionPercent != normalized) {
        exercise.backoffReductionPercent = normalized;
        changed = true;
      }
    }
    return changed;
  }

  static bool applyBackoffReductionToWorkoutExercises(
    List<WorkoutExercise> exercises,
    double reductionPercent,
  ) {
    var changed = false;
    final normalized = AppPreferences.normalizeBackoffReductionPercent(
      reductionPercent,
    );
    for (final exercise in exercises) {
      if (exercise.backoffReductionPercent != normalized) {
        exercise.backoffReductionPercent = normalized;
        changed = true;
      }
    }
    return changed;
  }

  static bool applyBackoffReductionToSchedules(
    List<Schedule> schedules,
    double reductionPercent,
  ) {
    var changed = false;
    for (final schedule in schedules) {
      changed |= applyBackoffReductionToExercises(
        schedule.exercises,
        reductionPercent,
      );
    }
    return changed;
  }

  static bool applyBackoffReductionToSession(
    WorkoutSession? session,
    double reductionPercent,
  ) {
    if (session == null) {
      return false;
    }
    return applyBackoffReductionToWorkoutExercises(
      session.exercises,
      reductionPercent,
    );
  }

  static bool applyBackoffReductionToHistory(
    List<WorkoutSession> history,
    double reductionPercent,
  ) {
    var changed = false;
    for (final session in history) {
      changed |= applyBackoffReductionToSession(session, reductionPercent);
    }
    return changed;
  }

  static void sortSchedules(List<Schedule> schedules) {
    schedules.sort((a, b) {
      if (a.isArchived != b.isArchived) {
        return a.isArchived ? 1 : -1;
      }

      final weekCompare = a.currentWeek().compareTo(b.currentWeek());
      if (weekCompare != 0) {
        return weekCompare;
      }

      return a.title.toLowerCase().compareTo(b.title.toLowerCase());
    });
  }
}
''')

Path('test/refactor_foundations_test.dart').write_text(r'''import 'package:flutter_test/flutter_test.dart';
import 'package:gymapp/active_workout_insights.dart';
import 'package:gymapp/home_data_policy.dart';
import 'package:gymapp/models/exercise.dart';
import 'package:gymapp/models/schedule.dart';
import 'package:gymapp/models/workout.dart';

WorkoutExercise workoutExercise({
  required String id,
  required String name,
  required double weight,
  required int reps,
  SetType type = SetType.normal,
}) {
  return WorkoutExercise(
    id: id,
    name: name,
    notes: '',
    technique: IntensityTechnique.none,
    sets: [
      ExerciseSet(
        id: '${id}_set',
        weight: weight,
        reps: reps,
        isCompleted: true,
        type: type,
      ),
    ],
  );
}

WorkoutSession workoutSession({
  required String id,
  required WorkoutExercise exercise,
}) {
  return WorkoutSession(
    id: id,
    scheduleTitle: 'Test',
    startTime: DateTime(2026, 8, 1, 10),
    endTime: DateTime(2026, 8, 1, 11),
    exercises: [exercise],
  );
}

Exercise planExercise(String id, double reduction) {
  return Exercise(
    id: id,
    name: 'Panca piana',
    reps: 8,
    set: 3,
    notes: '',
    weight: 80,
    technique: IntensityTechnique.topsetBackoff,
    backoffReductionPercent: reduction,
  );
}

void main() {
  test('active workout insights preserve PR detection outside the widget', () {
    final historical = workoutExercise(
      id: 'historical_bench',
      name: 'Panca piana',
      weight: 80,
      reps: 5,
    );
    final current = workoutExercise(
      id: 'current_bench',
      name: 'Panca piana',
      weight: 82.5,
      reps: 5,
    );
    final insights = ActiveWorkoutInsights(
      history: [workoutSession(id: 'old_session', exercise: historical)],
      currentSessionId: 'current_session',
    );

    final labels = insights.personalRecordLabelsFor(
      current,
      current.sets.single,
      0,
    );

    expect(labels, contains('PR kg'));
    expect(labels, contains('PR set'));
    expect(labels, contains('PR e1RM'));
    expect(labels, contains('PR volume'));

    final currentSession = workoutSession(
      id: 'current_session',
      exercise: current,
    );
    expect(insights.sessionPrCount(currentSession), 1);
  });

  test('active workout insights ignore warm-up sets for PRs', () {
    final historical = workoutExercise(
      id: 'historical_bench',
      name: 'Panca piana',
      weight: 80,
      reps: 5,
    );
    final warmup = workoutExercise(
      id: 'warmup_bench',
      name: 'Panca piana',
      weight: 100,
      reps: 20,
      type: SetType.warmup,
    );
    final insights = ActiveWorkoutInsights(
      history: [workoutSession(id: 'old_session', exercise: historical)],
      currentSessionId: 'current_session',
    );

    expect(
      insights.personalRecordLabelsFor(warmup, warmup.sets.single, 0),
      isEmpty,
    );
  });

  test('home data policy applies backoff defaults across persisted graphs', () {
    final scheduleExercise = planExercise('plan_exercise', 10);
    final schedule = Schedule(
      id: 'schedule',
      title: 'Push',
      week: 1,
      createdAt: DateTime(2026, 8, 24),
      exercises: [scheduleExercise],
    );
    final historicalExercise = workoutExercise(
      id: 'history_exercise',
      name: 'Panca piana',
      weight: 80,
      reps: 5,
    )..backoffReductionPercent = 10;
    final history = [
      workoutSession(id: 'history_session', exercise: historicalExercise),
    ];
    final currentExercise = workoutExercise(
      id: 'current_exercise',
      name: 'Panca piana',
      weight: 80,
      reps: 5,
    )..backoffReductionPercent = 10;
    final currentSession = workoutSession(
      id: 'current_session',
      exercise: currentExercise,
    );

    expect(
      HomeDataPolicy.applyBackoffReductionToSchedules([schedule], 25),
      isTrue,
    );
    expect(HomeDataPolicy.applyBackoffReductionToHistory(history, 25), isTrue);
    expect(
      HomeDataPolicy.applyBackoffReductionToSession(currentSession, 25),
      isTrue,
    );
    expect(scheduleExercise.backoffReductionPercent, 25);
    expect(historicalExercise.backoffReductionPercent, 25);
    expect(currentExercise.backoffReductionPercent, 25);
  });

  test('home data policy keeps active schedules ordered before archived ones', () {
    final createdAt = DateTime(2026, 8, 24);
    Schedule schedule(String id, String title, {bool archived = false}) {
      return Schedule(
        id: id,
        title: title,
        week: 1,
        createdAt: createdAt,
        exercises: const [],
        isArchived: archived,
      );
    }

    final schedules = [
      schedule('archived', 'Archived', archived: true),
      schedule('b', 'Beta'),
      schedule('a', 'Alpha'),
    ];

    HomeDataPolicy.sortSchedules(schedules);

    expect(schedules.map((item) => item.id), ['a', 'b', 'archived']);
  });
}
''')

active = Path('lib/screens/active_workout.dart').read_text()
active = active.replace(
    "import '../app_data_store.dart';\n",
    "import '../active_workout_insights.dart';\nimport '../app_data_store.dart';\n",
    1,
)
active = sub_once(
    active,
    r"\n  Iterable<WorkoutSession> get _comparisonHistory \{.*?\n  \}\n\n  String _formatDuration",
    "\n  String _formatDuration",
    'remove comparison history from active workout widget',
)
active_metrics = r'''  ActiveWorkoutInsights get _workoutInsights => ActiveWorkoutInsights(
    history: widget.history,
    currentSessionId: session.id,
  );

  double _setVolume(ExerciseSet set) => _workoutInsights.setVolume(set);

  List<String> _personalRecordLabelsFor(
    WorkoutExercise exercise,
    ExerciseSet set,
    int setIndex,
  ) {
    return _workoutInsights.personalRecordLabelsFor(exercise, set, setIndex);
  }

  int _sessionPrCount() => _workoutInsights.sessionPrCount(session);

  String? _previousSetLabelFor'''
active = sub_once(
    active,
    r"  double _setVolume\(ExerciseSet set\) => set\.weight \* set\.reps;.*?  String\? _previousSetLabelFor",
    active_metrics,
    'extract active workout PR analytics',
)
Path('lib/screens/active_workout.dart').write_text(active)

home = Path('lib/screens/home.dart').read_text()
home = home.replace(
    "import '../dialog_form.dart';\n",
    "import '../dialog_form.dart';\nimport '../home_data_policy.dart';\n",
    1,
)
home_policy_delegates = r'''  bool _applyBackoffReductionToExercises(
    List<Exercise> exercises,
    double reductionPercent,
  ) {
    return HomeDataPolicy.applyBackoffReductionToExercises(
      exercises,
      reductionPercent,
    );
  }

  bool _applyBackoffReductionToSchedules(double reductionPercent) {
    return HomeDataPolicy.applyBackoffReductionToSchedules(
      schedules,
      reductionPercent,
    );
  }

  bool _applyBackoffReductionToSession(
    WorkoutSession? session,
    double reductionPercent,
  ) {
    return HomeDataPolicy.applyBackoffReductionToSession(
      session,
      reductionPercent,
    );
  }

  bool _applyBackoffReductionToHistory(double reductionPercent) {
    return HomeDataPolicy.applyBackoffReductionToHistory(
      history,
      reductionPercent,
    );
  }

  Future<void> _saveBackoffReductionPercent'''
home = sub_once(
    home,
    r"  bool _applyBackoffReductionToExercises\(.*?  Future<void> _saveBackoffReductionPercent",
    home_policy_delegates,
    'extract home backoff policy',
)
home = sub_once(
    home,
    r"  void _sortSchedules\(\) \{.*?\n  \}\n\n  Future<void> _deleteHistory",
    "  void _sortSchedules() => HomeDataPolicy.sortSchedules(schedules);\n\n  Future<void> _deleteHistory",
    'extract home schedule ordering',
)
Path('lib/screens/home.dart').write_text(home)
