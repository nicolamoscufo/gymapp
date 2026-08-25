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
    "import '../active_workout_insights.dart';\n",
    "import '../active_workout_exercise_manager.dart';\nimport '../active_workout_insights.dart';\n",
    'manager import',
)

replace_once(
    "  ActiveWorkoutSessionBuilder get _sessionBuilder =>\n      ActiveWorkoutSessionBuilder(history: widget.history, bodyLogs: _bodyLogs);\n",
    "  ActiveWorkoutSessionBuilder get _sessionBuilder =>\n      ActiveWorkoutSessionBuilder(history: widget.history, bodyLogs: _bodyLogs);\n\n  ActiveWorkoutExerciseManager get _exerciseManager =>\n      ActiveWorkoutExerciseManager(\n        session: session,\n        sessionBuilder: _sessionBuilder,\n      );\n",
    'manager getter',
)

workout_from_exercise = re.compile(
    r"  WorkoutExercise _workoutExerciseFromExercise\(\n"
    r".*?"
    r"  \}\n\n"
    r"  Exercise _exerciseFromCatalogEntry",
    re.S,
)
match = workout_from_exercise.search(text)
if not match:
    raise SystemExit('workout exercise conversion delegate not found')
text = text[:match.start()] + '  Exercise _exerciseFromCatalogEntry' + text[match.end():]

previous_added = re.compile(
    r"  WorkoutSession\? _previousSessionForAddedExercises\(\) \{\n"
    r".*?"
    r"  \}\n\n"
    r"  void _addExercisesToSession",
    re.S,
)
match = previous_added.search(text)
if not match:
    raise SystemExit('previous added-exercise session helper not found')
text = text[:match.start()] + '  void _addExercisesToSession' + text[match.end():]

replace_once(
    '''  void _addExercisesToSession(List<Exercise> exercises) {
    if (exercises.isEmpty) {
      return;
    }

    final previousSession = _previousSessionForAddedExercises();
    setState(() {
      session.exercises.addAll(
        exercises.map(
          (exercise) => _workoutExerciseFromExercise(
            exercise,
            previousSession,
            keepSourceExerciseId: false,
          ),
        ),
      );
    });
    _saveCurrentSession();
  }
''',
    '''  void _addExercisesToSession(List<Exercise> exercises) {
    if (exercises.isEmpty) return;
    setState(() => _exerciseManager.addExercises(exercises));
    _saveCurrentSession();
  }
''',
    'add exercises',
)

superset_helpers = re.compile(
    r"  int _nextSupersetGroupId\(\) \{\n"
    r".*?"
    r"  void _advanceSupersetNavigation\(WorkoutExercise exercise\) \{\n"
    r".*?"
    r"  \}\n\n"
    r"  Future<void> _replaceExercise",
    re.S,
)
match = superset_helpers.search(text)
if not match:
    raise SystemExit('superset helper block not found')
superset_replacement = '''  bool _shouldStartRestAfterSet(WorkoutExercise exercise) {
    return _exerciseManager.shouldStartRestAfterSet(exercise);
  }

  void _advanceSupersetNavigation(WorkoutExercise exercise) {
    final next = _exerciseManager.nextSupersetMember(exercise);
    if (next == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _scrollToExercise(next.id);
      }
    });
  }

  Future<void> _replaceExercise'''
text = text[:match.start()] + superset_replacement + text[match.end():]

replace_pattern = re.compile(
    r"  Future<void> _replaceExercise\(WorkoutExercise exercise\) async \{\n"
    r".*?"
    r"  \}\n\n"
    r"  void _duplicateExercise",
    re.S,
)
match = replace_pattern.search(text)
if not match:
    raise SystemExit('replace exercise block not found')
replace_replacement = '''  Future<void> _replaceExercise(WorkoutExercise exercise) async {
    final replacements = await _pickExercisesForSession();
    if (!mounted || replacements == null || replacements.isEmpty) {
      return;
    }

    _restController.stop(exercise);
    WorkoutExercise? replacement;
    setState(() {
      replacement = _exerciseManager.replaceExercise(
        exercise,
        replacements.first,
      );
      if (replacement != null) {
        _exerciseCardKeys.remove(exercise.id);
      }
    });
    if (replacement == null) return;
    await _saveCurrentSession();

    if (replacements.length > 1 && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Per la sostituzione è stato usato il primo esercizio selezionato.',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _duplicateExercise'''
text = text[:match.start()] + replace_replacement + text[match.end():]

duplicate_pattern = re.compile(
    r"  void _duplicateExercise\(WorkoutExercise exercise\) \{\n"
    r".*?"
    r"  \}\n\n"
    r"  void _moveExercise",
    re.S,
)
match = duplicate_pattern.search(text)
if not match:
    raise SystemExit('duplicate exercise block not found')
duplicate_replacement = '''  void _duplicateExercise(WorkoutExercise exercise) {
    WorkoutExercise? duplicate;
    setState(() {
      duplicate = _exerciseManager.duplicateExercise(exercise);
    });
    if (duplicate == null) return;
    HapticFeedback.selectionClick();
    _saveCurrentSession();
  }

  void _moveExercise'''
text = text[:match.start()] + duplicate_replacement + text[match.end():]

move_pattern = re.compile(
    r"  void _moveExercise\(WorkoutExercise exercise, int delta\) \{\n"
    r".*?"
    r"  \}\n\n"
    r"  void _removeExerciseFromSession",
    re.S,
)
match = move_pattern.search(text)
if not match:
    raise SystemExit('move exercise block not found')
move_replacement = '''  void _moveExercise(WorkoutExercise exercise, int delta) {
    var moved = false;
    setState(() {
      moved = _exerciseManager.moveExercise(exercise, delta);
    });
    if (!moved) return;
    HapticFeedback.selectionClick();
    _saveCurrentSession();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _scrollToExercise(exercise.id);
    });
  }

  void _removeExerciseFromSession'''
text = text[:match.start()] + move_replacement + text[match.end():]

remove_pattern = re.compile(
    r"  void _removeExerciseFromSession\(WorkoutExercise exercise\) \{\n"
    r".*?"
    r"  \}\n\n"
    r"  Future<void> _configureSuperset",
    re.S,
)
match = remove_pattern.search(text)
if not match:
    raise SystemExit('remove exercise block not found')
remove_replacement = '''  void _removeExerciseFromSession(WorkoutExercise exercise) {
    _restController.stop(exercise);
    RemovedWorkoutExercise? removal;
    setState(() {
      removal = _exerciseManager.removeExercise(exercise);
      if (removal != null) {
        _exerciseCardKeys.remove(exercise.id);
      }
    });
    if (removal == null) return;
    _saveCurrentSession();

    _showUndoSnackBar(
      message: '${exercise.name} eliminato dalla sessione.',
      onUndo: () {
        if (!mounted) return;
        var restored = false;
        setState(() {
          restored = _exerciseManager.restoreRemoved(removal!);
        });
        if (restored) {
          _saveCurrentSession();
        }
      },
    );
  }

  Future<void> _configureSuperset'''
text = text[:match.start()] + remove_replacement + text[match.end():]

old_selection = '''    final oldGroup = exercise.supersetGroup;
    if (selectedId == '__remove__') {
      setState(() {
        exercise.supersetGroup = null;
        _cleanupSupersetGroup(oldGroup);
      });
      _saveCurrentSession();
      return;
    }

    final targetIndex = session.exercises.indexWhere(
      (candidate) => candidate.id == selectedId,
    );
    if (targetIndex < 0) return;
    final target = session.exercises[targetIndex];

    setState(() {
      final group = target.supersetGroup ?? oldGroup ?? _nextSupersetGroupId();
      exercise.supersetGroup = group;
      target.supersetGroup = group;
      if (oldGroup != null && oldGroup != group) {
        _cleanupSupersetGroup(oldGroup);
      }
    });
    HapticFeedback.selectionClick();
    _saveCurrentSession();
'''
new_selection = '''    if (selectedId == '__remove__') {
      var changed = false;
      setState(() {
        changed = _exerciseManager.removeFromSuperset(exercise);
      });
      if (changed) {
        _saveCurrentSession();
      }
      return;
    }

    final targetIndex = session.exercises.indexWhere(
      (candidate) => candidate.id == selectedId,
    );
    if (targetIndex < 0) return;
    final target = session.exercises[targetIndex];

    var changed = false;
    setState(() {
      changed = _exerciseManager.linkSuperset(exercise, target);
    });
    if (!changed) return;
    HapticFeedback.selectionClick();
    _saveCurrentSession();
'''
replace_once(old_selection, new_selection, 'configure superset mutation')

for forbidden in (
    '_previousSessionForAddedExercises(',
    '_nextSupersetGroupId(',
    '_cleanupSupersetGroup(',
    '_workoutExerciseFromExercise(',
    '_supersetMembers(',
):
    if forbidden in text:
        lines = [
            f'{i}: {line}'
            for i, line in enumerate(text.splitlines(), 1)
            if forbidden in line
        ]
        raise SystemExit(f'unexpected leftover {forbidden}: ' + ' | '.join(lines[:10]))

path.write_text(text)
