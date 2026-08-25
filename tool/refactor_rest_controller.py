from pathlib import Path
import re

path = Path('lib/screens/active_workout.dart')
text = path.read_text()
controller_path = Path('lib/active_workout_rest_controller.dart')
controller_text = controller_path.read_text()


def replace_once(old: str, new: str, label: str) -> None:
    global text
    count = text.count(old)
    if count != 1:
        raise SystemExit(f'{label}: expected 1 occurrence, found {count}')
    text = text.replace(old, new, 1)


controller_anchor = '''  bool isActive(String exerciseId) =>
      _remainingByExerciseId.containsKey(exerciseId);

  WorkoutExercise? activeExercise() {'''
controller_replacement = '''  bool isActive(String exerciseId) =>
      _remainingByExerciseId.containsKey(exerciseId);

  int configuredSecondsFor(WorkoutExercise exercise) => _restSecondsFor(exercise);

  WorkoutExercise? activeExercise() {'''
if controller_text.count(controller_anchor) != 1:
    raise SystemExit('configured rest getter anchor not found')
controller_text = controller_text.replace(
    controller_anchor,
    controller_replacement,
    1,
)
controller_path.write_text(controller_text)

replace_once(
    "import '../active_workout_insights.dart';\n",
    "import '../active_workout_insights.dart';\nimport '../active_workout_rest_controller.dart';\n",
    'rest controller import',
)

replace_once(
    "  Timer? _restTimer;\n"
    "  Timer? _durationTimer;\n"
    "  int _elapsedSeconds = 0;\n"
    "  final Map<String, int> _restSecondsByExerciseId = {};\n",
    "  Timer? _durationTimer;\n"
    "  int _elapsedSeconds = 0;\n",
    'rest state fields',
)

replace_once(
    "  final ActiveWorkoutSessionController _sessionPersistence =\n"
    "      ActiveWorkoutSessionController();\n",
    "  final ActiveWorkoutSessionController _sessionPersistence =\n"
    "      ActiveWorkoutSessionController();\n"
    "  late final ActiveWorkoutRestController _restController =\n"
    "      ActiveWorkoutRestController(\n"
    "        exercises: () => session.exercises,\n"
    "        restSecondsFor: (exercise) =>\n"
    "            exercise.restSeconds ?? widget.defaultRestSeconds,\n"
    "        onChanged: _notifyRestControllerChanged,\n"
    "        onFinished: _handleRestFinished,\n"
    "      );\n",
    'rest controller field',
)

active_rest_pattern = re.compile(
    r"  WorkoutExercise\? _activeRestExercise\(\) \{\n"
    r".*?"
    r"  \}\n\n"
    r"  String\? _nextSetHintFor",
    re.S,
)
match = active_rest_pattern.search(text)
if not match:
    raise SystemExit('active rest exercise method not found')
text = text[:match.start()] + (
    "  WorkoutExercise? _activeRestExercise() => _restController.activeExercise();\n\n"
    "  String? _nextSetHintFor"
) + text[match.end():]

rest_block_pattern = re.compile(
    r"  int _restSecondsFor\(WorkoutExercise exercise\) \{\n"
    r".*?"
    r"  void _restoreRestTimersFromSession\(\{bool notifyExpired = false\}\) \{\n"
    r".*?"
    r"  \}\n\n"
    r"  @override\n"
    r"  void didChangeAppLifecycleState",
    re.S,
)
match = rest_block_pattern.search(text)
if not match:
    raise SystemExit('rest timer implementation block not found')

replacement = '''  void _notifyRestControllerChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  void _handleRestFinished(String exerciseId, String? exerciseName) {
    _saveCurrentSession();
    HapticFeedback.mediumImpact();
    SystemSound.play(SystemSoundType.alert);
    LocalNotificationService.showRestFinished(exerciseName ?? '');

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          exerciseName == null
              ? 'Recupero finito.'
              : 'Recupero finito: $exerciseName.',
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _startRestForExercise(WorkoutExercise exercise) {
    if (_restController.start(exercise)) {
      _saveCurrentSession();
    }
  }

  void _addThirtySeconds(WorkoutExercise exercise) {
    if (_restController.addThirtySeconds(exercise)) {
      _saveCurrentSession();
    }
  }

  void _subtractThirtySeconds(WorkoutExercise exercise) {
    if (_restController.subtractThirtySeconds(exercise)) {
      _saveCurrentSession();
    }
  }

  void _stopRestForExercise(WorkoutExercise exercise) {
    if (_restController.stop(exercise)) {
      _saveCurrentSession();
    }
  }

  Future<void> _cancelAllRestTimers() => _restController.cancelAll();

  void _updateExerciseRestSeconds(WorkoutExercise exercise, String value) {
    final parsedSeconds = parseIntInput(value);
    if (parsedSeconds == null) return;
    if (_restController.updateConfiguredRest(exercise, parsedSeconds)) {
      _saveCurrentSession();
    }
  }

  void _restoreRestTimersFromSession({bool notifyExpired = false}) {
    _restController.restore(notifyExpired: notifyExpired);
  }

  @override
  void didChangeAppLifecycleState'''
text = text[:match.start()] + replacement + text[match.end():]

# Remaining references are read-only UI lookups.
text = re.sub(
    r'_restSecondsByExerciseId\[([^\]]+)\]',
    r'_restController.remainingFor(\1)',
    text,
)
text = text.replace(
    '_restSecondsByExerciseId.containsKey(',
    '_restController.isActive(',
)
text = text.replace(
    '_restSecondsByExerciseId.isNotEmpty',
    '_restController.hasActiveRest',
)
text = text.replace(
    '_restSecondsByExerciseId.isEmpty',
    '!_restController.hasActiveRest',
)
text = re.sub(
    r'_restSecondsFor\(\s*exercise\s*\)',
    r'_restController.configuredSecondsFor(exercise)',
    text,
)

# The only remaining direct timer cancellation should be State.dispose().
rest_cancel_count = text.count('    _restTimer?.cancel();\n')
if rest_cancel_count != 1:
    raise SystemExit(
        f'dispose rest timer cancellation: expected 1, found {rest_cancel_count}'
    )
text = text.replace(
    '    _restTimer?.cancel();\n',
    '    _restController.dispose();\n',
    1,
)

for forbidden in ('_restSecondsByExerciseId', '_restTimer', '_restSecondsFor('):
    if forbidden in text:
        leftovers = [
            f'{index}: {line}'
            for index, line in enumerate(text.splitlines(), 1)
            if forbidden in line
        ]
        raise SystemExit(
            f'unexpected leftover {forbidden}: ' + ' | '.join(leftovers[:10])
        )

path.write_text(text)
