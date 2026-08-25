from pathlib import Path
import re

path = Path('lib/screens/active_workout.dart')
text = path.read_text()


def replace_once(old: str, new: str, label: str) -> None:
    global text
    count = text.count(old)
    if count != 1:
        raise SystemExit(f'{label}: expected 1 occurrence, found {count}')
    text = text.replace(old, new, 1)


replace_once(
    "import '../active_workout_rest_controller.dart';\n",
    "import '../active_workout_rest_controller.dart';\nimport '../active_workout_session_builder.dart';\n",
    'builder import',
)

replace_once(
    '''  ActiveWorkoutInsights get _workoutInsights => ActiveWorkoutInsights(
    history: widget.history,
    currentSessionId: session.id,
  );
''',
    '''  ActiveWorkoutInsights get _workoutInsights => ActiveWorkoutInsights(
    history: widget.history,
    currentSessionId: session.id,
  );

  ActiveWorkoutSessionBuilder get _sessionBuilder =>
      ActiveWorkoutSessionBuilder(
        history: widget.history,
        bodyLogs: _bodyLogs,
      );
''',
    'builder getter',
)

# Previous-session lookup and previous-set extraction become builder internals.
lookup_pattern = re.compile(
    r"  String _normalizeExerciseName\(String name\) => name\.trim\(\)\.toLowerCase\(\);\n\n"
    r"  WorkoutSession\? _latestSessionForSchedule\(Schedule schedule\) \{\n"
    r".*?"
    r"  List<int> _previousRepsFor\(WorkoutExercise\? previousExercise\) \{\n"
    r".*?"
    r"  \}\n\n"
    r"  String _progressionConfidenceLabel",
    re.S,
)
match = lookup_pattern.search(text)
if not match:
    raise SystemExit('previous-session lookup block not found')
text = text[:match.start()] + '  String _progressionConfidenceLabel' + text[match.end():]

# Weight/reps/set construction moves into ActiveWorkoutSessionBuilder. Keep only
# the small delegates that are used by unrelated live-workout flows.
builder_pattern = re.compile(
    r"  double _deloadWeight\(double weight\) \{\n"
    r".*?"
    r"  WorkoutExercise _workoutExerciseFromExercise\(\n"
    r".*?"
    r"  \}\n\n"
    r"  Exercise _exerciseFromCatalogEntry",
    re.S,
)
match = builder_pattern.search(text)
if not match:
    raise SystemExit('session construction block not found')
replacement = '''  double _deloadWeight(double weight) => _sessionBuilder.deloadWeight(weight);

  WorkoutExercise _workoutExerciseFromExercise(
    Exercise exercise,
    WorkoutSession? previousSession, {
    bool keepSourceExerciseId = true,
  }) {
    return _sessionBuilder.workoutExerciseFromExercise(
      exercise,
      previousSession,
      keepSourceExerciseId: keepSourceExerciseId,
    );
  }

  Exercise _exerciseFromCatalogEntry'''
text = text[:match.start()] + replacement + text[match.end():]

exercise_conversion_pattern = re.compile(
    r"  Exercise _exerciseFromWorkoutExercise\(WorkoutExercise exercise\) \{\n"
    r".*?"
    r"  \}\n\n"
    r"  void _applyDeloadToSession\(\) \{\n"
    r".*?"
    r"  \}\n\n"
    r"  void _notifyRestControllerChanged",
    re.S,
)
match = exercise_conversion_pattern.search(text)
if not match:
    raise SystemExit('exercise conversion/deload block not found')
replacement = '''  Exercise _exerciseFromWorkoutExercise(WorkoutExercise exercise) {
    return _sessionBuilder.exerciseFromWorkoutExercise(exercise);
  }

  void _applyDeloadToSession() {
    _sessionBuilder.applyDeloadToSession(session);
  }

  void _notifyRestControllerChanged'''
text = text[:match.start()] + replacement + text[match.end():]

schedule_init = '''    } else if (widget.schedule != null) {
      final previousSession = _latestSessionForSchedule(widget.schedule!);
      session = WorkoutSession(
        scheduleId: widget.schedule!.id,
        scheduleTitle: widget.schedule!.title,
        startTime: DateTime.now(),
        endTime: DateTime.now(),
        exercises: widget.schedule!.exercises
            .map(
              (exercise) =>
                  _workoutExerciseFromExercise(exercise, previousSession),
            )
            .toList(),
      );
      if (widget.schedule!.isDeloadWeek()) {
        _applyDeloadToSession();
      }
      _restoreRestTimersFromSession();
      _restoreIfNeeded();
    } else {
      session = WorkoutSession(
        scheduleTitle: 'Sessione',
        startTime: DateTime.now(),
        endTime: DateTime.now(),
        exercises: [],
      );
    }
'''
schedule_replacement = '''    } else if (widget.schedule != null) {
      session = _sessionBuilder.buildFromSchedule(widget.schedule!);
      _restoreRestTimersFromSession();
      _restoreIfNeeded();
    } else {
      session = _sessionBuilder.buildEmptySession();
    }
'''
replace_once(schedule_init, schedule_replacement, 'session init')

# These implementation details should now live only in the builder.
for forbidden in (
    '_weightForSet(',
    '_repsForSet(',
    '_setsForExercise(',
    '_latestSessionForSchedule(',
    '_previousExerciseFor(',
    '_previousWeightsFor(',
    '_previousRepsFor(',
    '_normalizeExerciseName(',
):
    if forbidden in text:
        lines = [
            f'{i}: {line}'
            for i, line in enumerate(text.splitlines(), 1)
            if forbidden in line
        ]
        raise SystemExit(f'unexpected leftover {forbidden}: ' + ' | '.join(lines[:10]))

path.write_text(text)
