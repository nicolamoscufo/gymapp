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
    "import '../active_workout_session_controller.dart';\n",
    "import '../active_workout_session_controller.dart';\nimport '../active_workout_set_manager.dart';\n",
    'set manager import',
)
replace_once(
    "import '../top_set_backoff.dart' as top_set_backoff;\n",
    "",
    'obsolete top set backoff import',
)

replace_once(
    '''  ActiveWorkoutScheduleSync get _scheduleSync => ActiveWorkoutScheduleSync(
    session: session,
    sessionBuilder: _sessionBuilder,
  );
''',
    '''  ActiveWorkoutScheduleSync get _scheduleSync => ActiveWorkoutScheduleSync(
    session: session,
    sessionBuilder: _sessionBuilder,
  );

  ActiveWorkoutSetManager get _setManager =>
      ActiveWorkoutSetManager(session: session);
''',
    'set manager getter',
)

backoff_helpers = re.compile(
    r"  double\? _backoffReductionFor\(WorkoutExercise exercise, int setIndex\) \{\n"
    r".*?"
    r"  \}\n\n"
    r"  String\? _backoffHintFor",
    re.S,
)
match = backoff_helpers.search(text)
if not match:
    raise SystemExit('backoff helper block not found')
text = text[:match.start()] + '  String? _backoffHintFor' + text[match.end():]
text = text.replace(
    '_backoffReductionFor(exercise, setIndex)',
    '_setManager.backoffReductionFor(exercise, setIndex)',
)
text = text.replace(
    '_recommendedBackoffWeightFor(exercise, setIndex)',
    '_setManager.recommendedBackoffWeightFor(exercise, setIndex)',
)
text = text.replace(
    '''_recommendedBackoffWeightFor(
        exercise,
        setIndex + 1,
      )''',
    '''_setManager.recommendedBackoffWeightFor(
        exercise,
        setIndex + 1,
      )''',
)

set_mutations = re.compile(
    r"  void _addSet\(WorkoutExercise exercise, \{bool isWarmup = false\}\) \{\n"
    r".*?"
    r"  List<String> _sessionValidationProblems\(\) \{\n"
    r".*?"
    r"  \}\n\n"
    r"  Future<void> _showValidationProblems",
    re.S,
)
match = set_mutations.search(text)
if not match:
    raise SystemExit('add/copy/validation block not found')
set_replacement = '''  void _addSet(WorkoutExercise exercise, {bool isWarmup = false}) {
    setState(() => _setManager.addSet(exercise, isWarmup: isWarmup));
    _saveCurrentSession();
  }

  void _copySet(WorkoutExercise exercise, int setIndex) {
    ExerciseSet? copy;
    setState(() => copy = _setManager.copySet(exercise, setIndex));
    if (copy == null) return;
    _saveCurrentSession();
  }

  List<String> _sessionValidationProblems() =>
      _setManager.validationProblems();

  Future<void> _showValidationProblems'''
text = text[:match.start()] + set_replacement + text[match.end():]

apply_backoff = re.compile(
    r"  void _applyRecommendedBackoffWeight\(WorkoutExercise exercise, int setIndex\) \{\n"
    r".*?"
    r"  \}\n\n"
    r"  Future<void> _showExerciseHistory",
    re.S,
)
match = apply_backoff.search(text)
if not match:
    raise SystemExit('apply backoff block not found')
apply_replacement = '''  void _applyRecommendedBackoffWeight(WorkoutExercise exercise, int setIndex) {
    var applied = false;
    setState(() {
      applied = _setManager.applyRecommendedBackoffWeight(exercise, setIndex);
    });
    if (!applied) return;
    _saveCurrentSession();
  }

  Future<void> _showExerciseHistory'''
text = text[:match.start()] + apply_replacement + text[match.end():]

warmup_block = re.compile(
    r"  List<ExerciseSet> _warmupSetsFor\(WorkoutExercise exercise\) \{\n"
    r".*?"
    r"  void _insertWarmupPlan\(WorkoutExercise exercise\) \{\n"
    r".*?"
    r"  \}\n\n"
    r"  void _showWarmupPlan",
    re.S,
)
match = warmup_block.search(text)
if not match:
    raise SystemExit('warmup block not found')
warmup_replacement = '''  List<ExerciseSet> _warmupSetsFor(WorkoutExercise exercise) =>
      _setManager.warmupSetsFor(exercise);

  void _insertWarmupPlan(WorkoutExercise exercise) {
    setState(() => _setManager.insertWarmupPlan(exercise));
    _saveCurrentSession();
  }

  void _showWarmupPlan'''
text = text[:match.start()] + warmup_replacement + text[match.end():]

toggle_block = re.compile(
    r"  void _toggleSetCompleted\(\n"
    r"    WorkoutExercise exercise,\n"
    r"    ExerciseSet set,\n"
    r"    int setIndex,\n"
    r"  \) \{\n"
    r"    final willComplete = !set\.isCompleted;\n"
    r"    setState\(\(\) \{\n"
    r"      set\.isCompleted = !set\.isCompleted;\n"
    r"    \}\);",
    re.S,
)
match = toggle_block.search(text)
if not match:
    raise SystemExit('toggle completion prefix not found')
text = text[:match.start()] + '''  void _toggleSetCompleted(
    WorkoutExercise exercise,
    ExerciseSet set,
    int setIndex,
  ) {
    var willComplete = false;
    setState(() {
      willComplete = _setManager.toggleSetCompleted(set);
    });''' + text[match.end():]

remove_stats = re.compile(
    r"  void _removeSet\(WorkoutExercise exercise, int index\) \{\n"
    r".*?"
    r"  \}\n\n"
    r"  \(\{int completedSets, int totalSets, double volume, int exercises\}\)\n"
    r"  get _workoutStats \{\n"
    r".*?"
    r"  \}\n\n"
    r"  Widget _summaryRow",
    re.S,
)
match = remove_stats.search(text)
if not match:
    raise SystemExit('remove set/stats block not found')
remove_stats_replacement = '''  void _removeSet(WorkoutExercise exercise, int index) {
    RemovedExerciseSet? removal;
    setState(() {
      removal = _setManager.removeSet(exercise, index);
    });
    if (removal == null) return;
    _saveCurrentSession();

    _showUndoSnackBar(
      message: 'Set eliminato.',
      onUndo: () {
        if (!mounted) return;
        var restored = false;
        setState(() {
          restored = _setManager.restoreRemovedSet(exercise, removal!);
        });
        if (restored) {
          _saveCurrentSession();
        }
      },
    );
  }

  ActiveWorkoutStats get _workoutStats => _setManager.workoutStats;

  Widget _summaryRow'''
text = text[:match.start()] + remove_stats_replacement + text[match.end():]

for forbidden in (
    '_backoffReductionFor(',
    '_recommendedBackoffWeightFor(',
    'top_set_backoff.',
    'buildAdaptiveWarmupPlan(',
):
    if forbidden in text:
        lines = [
            f'{i}: {line}'
            for i, line in enumerate(text.splitlines(), 1)
            if forbidden in line
        ]
        raise SystemExit(f'unexpected leftover {forbidden}: ' + ' | '.join(lines[:10]))

path.write_text(text)
