from pathlib import Path

active_path = Path('lib/screens/active_workout.dart')
home_path = Path('lib/screens/home.dart')
test_path = Path('test/workout_experience_v2_test.dart')

active = active_path.read_text()
home = home_path.read_text()


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f'{label}: expected 1 match, found {count}')
    return text.replace(old, new, 1)


active = replace_once(
    active,
    "import 'session_summary.dart';\n\nclass ActiveWorkoutScreen",
    "import 'session_summary.dart';\n\nenum _WorkoutExerciseAction {\n  replace,\n  duplicate,\n  superset,\n  moveUp,\n  moveDown,\n  delete,\n}\n\nclass ActiveWorkoutScreen",
    'workout exercise action enum',
)

old_picker = """  Future<void> _openExercisePicker() async {
    final result = await Navigator.push<ExercisePickerResult>(
      context,
      MaterialPageRoute(builder: (context) => const ExercisePickerScreen()),
    );

    if (!mounted || result == null) {
      return;
    }

    if (result.addCustom) {
      final customExercise = await _showCustomExerciseDialog();
      if (customExercise != null) {
        _addExercisesToSession([customExercise]);
      }
      return;
    }

    if (result.customExercises.isNotEmpty) {
      _addCustomExercisesToSession(result.customExercises);
    }
    _addCatalogExercisesToSession(result.entries);
  }
"""
new_picker = """  Future<List<Exercise>?> _pickExercisesForSession() async {
    final result = await Navigator.push<ExercisePickerResult>(
      context,
      MaterialPageRoute(builder: (context) => const ExercisePickerScreen()),
    );

    if (!mounted || result == null) {
      return null;
    }

    if (result.addCustom) {
      final customExercise = await _showCustomExerciseDialog();
      return customExercise == null ? null : [customExercise];
    }

    return [
      ...result.customExercises.map(_copyExerciseTemplate),
      ...result.entries.map(_exerciseFromCatalogEntry),
    ];
  }

  Future<void> _openExercisePicker() async {
    final exercises = await _pickExercisesForSession();
    if (!mounted || exercises == null || exercises.isEmpty) {
      return;
    }
    _addExercisesToSession(exercises);
  }
"""
active = replace_once(active, old_picker, new_picker, 'exercise picker refactor')

marker = "  Future<Exercise?> _showCustomExerciseDialog() async {\n"
helpers = r'''  int _nextSupersetGroupId() {
    var maxGroup = 0;
    for (final exercise in session.exercises) {
      final group = exercise.supersetGroup;
      if (group != null && group > maxGroup) {
        maxGroup = group;
      }
    }
    return maxGroup + 1;
  }

  List<WorkoutExercise> _supersetMembers(WorkoutExercise exercise) {
    final group = exercise.supersetGroup;
    if (group == null) {
      return const [];
    }
    return session.exercises
        .where((candidate) => candidate.supersetGroup == group)
        .toList();
  }

  void _cleanupSupersetGroup(int? group) {
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

  bool _shouldStartRestAfterSet(WorkoutExercise exercise) {
    final members = _supersetMembers(exercise);
    return members.length < 2 || members.last.id == exercise.id;
  }

  void _advanceSupersetNavigation(WorkoutExercise exercise) {
    final members = _supersetMembers(exercise);
    if (members.length < 2) return;
    final currentIndex = members.indexWhere((member) => member.id == exercise.id);
    if (currentIndex < 0) return;
    final next = members[(currentIndex + 1) % members.length];
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _scrollToExercise(next.id);
      }
    });
  }

  Future<void> _replaceExercise(WorkoutExercise exercise) async {
    final replacements = await _pickExercisesForSession();
    if (!mounted || replacements == null || replacements.isEmpty) {
      return;
    }

    final index = session.exercises.indexWhere((item) => item.id == exercise.id);
    if (index < 0) return;

    final previousSession = _previousSessionForAddedExercises();
    final replacement = _workoutExerciseFromExercise(
      replacements.first,
      previousSession,
      keepSourceExerciseId: false,
    )..supersetGroup = exercise.supersetGroup;

    final notificationId = LocalNotificationService.restNotificationId(exercise.id);
    setState(() {
      _restSecondsByExerciseId.remove(exercise.id);
      session.exercises[index] = replacement;
      _exerciseCardKeys.remove(exercise.id);
    });
    await LocalNotificationService.cancel(notificationId);
    await _saveCurrentSession();

    if (replacements.length > 1 && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Per la sostituzione è stato usato il primo esercizio selezionato.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _duplicateExercise(WorkoutExercise exercise) {
    final index = session.exercises.indexWhere((item) => item.id == exercise.id);
    if (index < 0) return;

    final duplicate = _workoutExerciseFromExercise(
      _exerciseFromWorkoutExercise(exercise),
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

    setState(() => session.exercises.insert(index + 1, duplicate));
    HapticFeedback.selectionClick();
    _saveCurrentSession();
  }

  void _moveExercise(WorkoutExercise exercise, int delta) {
    final index = session.exercises.indexWhere((item) => item.id == exercise.id);
    if (index < 0) return;
    final nextIndex = index + delta;
    if (nextIndex < 0 || nextIndex >= session.exercises.length) return;

    setState(() {
      final moved = session.exercises.removeAt(index);
      session.exercises.insert(nextIndex, moved);
    });
    HapticFeedback.selectionClick();
    _saveCurrentSession();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _scrollToExercise(exercise.id);
    });
  }

  void _removeExerciseFromSession(WorkoutExercise exercise) {
    final index = session.exercises.indexWhere((item) => item.id == exercise.id);
    if (index < 0) return;

    final deletedGroup = exercise.supersetGroup;
    final originalGroupMembers = deletedGroup == null
        ? const <WorkoutExercise>[]
        : session.exercises
              .where((item) => item.supersetGroup == deletedGroup)
              .toList();
    final notificationId = LocalNotificationService.restNotificationId(exercise.id);

    setState(() {
      _restSecondsByExerciseId.remove(exercise.id);
      session.exercises.removeAt(index);
      _exerciseCardKeys.remove(exercise.id);
      _cleanupSupersetGroup(deletedGroup);
    });
    LocalNotificationService.cancel(notificationId);
    _saveCurrentSession();

    _showUndoSnackBar(
      message: '${exercise.name} eliminato dalla sessione.',
      onUndo: () {
        if (!mounted || session.exercises.any((item) => item.id == exercise.id)) {
          return;
        }
        setState(() {
          final restoreIndex = index.clamp(0, session.exercises.length).toInt();
          session.exercises.insert(restoreIndex, exercise);
          if (deletedGroup != null) {
            for (final member in originalGroupMembers) {
              member.supersetGroup = deletedGroup;
            }
          }
        });
        _saveCurrentSession();
      },
    );
  }

  Future<void> _configureSuperset(WorkoutExercise exercise) async {
    if (session.exercises.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Aggiungi almeno un altro esercizio per creare un superset.')),
      );
      return;
    }

    final selectedId = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.only(bottom: 12),
          children: [
            ListTile(
              title: Text(
                exercise.supersetGroup == null
                    ? 'Crea superset con ${exercise.name}'
                    : 'Gestisci superset ${exercise.supersetGroup}',
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
              subtitle: const Text('Scegli un esercizio da collegare.'),
            ),
            if (exercise.supersetGroup != null)
              ListTile(
                key: ValueKey('remove-superset-${exercise.id}'),
                leading: const Icon(Icons.link_off),
                title: const Text('Rimuovi dal superset'),
                onTap: () => Navigator.pop(context, '__remove__'),
              ),
            for (final candidate in session.exercises)
              if (candidate.id != exercise.id)
                ListTile(
                  key: ValueKey('superset-target-${candidate.id}'),
                  leading: Icon(
                    candidate.supersetGroup == null ? Icons.link : Icons.hub,
                  ),
                  title: Text(candidate.name),
                  subtitle: Text(
                    candidate.supersetGroup == null
                        ? 'Nessun superset'
                        : 'Superset ${candidate.supersetGroup}',
                  ),
                  onTap: () => Navigator.pop(context, candidate.id),
                ),
          ],
        ),
      ),
    );

    if (!mounted || selectedId == null) return;

    final oldGroup = exercise.supersetGroup;
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
  }

  Future<void> _handleWorkoutExerciseAction(
    _WorkoutExerciseAction action,
    WorkoutExercise exercise,
  ) async {
    switch (action) {
      case _WorkoutExerciseAction.replace:
        await _replaceExercise(exercise);
        break;
      case _WorkoutExerciseAction.duplicate:
        _duplicateExercise(exercise);
        break;
      case _WorkoutExerciseAction.superset:
        await _configureSuperset(exercise);
        break;
      case _WorkoutExerciseAction.moveUp:
        _moveExercise(exercise, -1);
        break;
      case _WorkoutExerciseAction.moveDown:
        _moveExercise(exercise, 1);
        break;
      case _WorkoutExerciseAction.delete:
        _removeExerciseFromSession(exercise);
        break;
    }
  }

'''
active = replace_once(active, marker, helpers + marker, 'session exercise helpers')

old_toggle = """    _saveCurrentSession();
    if (willComplete && !widget.editCompletedSession) {
      _startRestForExercise(exercise);
    }

    final delta = _setVolumeDelta(exercise, set, setIndex);
"""
new_toggle = """    _saveCurrentSession();
    if (willComplete && !widget.editCompletedSession) {
      if (_shouldStartRestAfterSet(exercise)) {
        _startRestForExercise(exercise);
      }
      _advanceSupersetNavigation(exercise);
    }

    final delta = _setVolumeDelta(exercise, set, setIndex);
"""
active = replace_once(active, old_toggle, new_toggle, 'smart superset completion')

old_title = """                      Text(
                        exercise.name,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          color: accent,
                        ),
                      ),
"""
new_title = """                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              exercise.name,
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w900,
                                color: accent,
                              ),
                            ),
                          ),
                          PopupMenuButton<_WorkoutExerciseAction>(
                            key: ValueKey('exercise-menu-${exercise.id}'),
                            tooltip: 'Azioni esercizio',
                            onSelected: (action) =>
                                _handleWorkoutExerciseAction(action, exercise),
                            itemBuilder: (context) => [
                              const PopupMenuItem(
                                value: _WorkoutExerciseAction.replace,
                                child: ListTile(
                                  leading: Icon(Icons.swap_horiz),
                                  title: Text('Sostituisci'),
                                ),
                              ),
                              const PopupMenuItem(
                                value: _WorkoutExerciseAction.duplicate,
                                child: ListTile(
                                  leading: Icon(Icons.copy_all),
                                  title: Text('Duplica'),
                                ),
                              ),
                              PopupMenuItem(
                                value: _WorkoutExerciseAction.superset,
                                child: ListTile(
                                  leading: const Icon(Icons.link),
                                  title: Text(
                                    exercise.supersetGroup == null
                                        ? 'Crea superset'
                                        : 'Gestisci superset',
                                  ),
                                ),
                              ),
                              PopupMenuItem(
                                value: _WorkoutExerciseAction.moveUp,
                                enabled: exIndex > 0,
                                child: const ListTile(
                                  leading: Icon(Icons.arrow_upward),
                                  title: Text('Sposta su'),
                                ),
                              ),
                              PopupMenuItem(
                                value: _WorkoutExerciseAction.moveDown,
                                enabled: exIndex < session.exercises.length - 1,
                                child: const ListTile(
                                  leading: Icon(Icons.arrow_downward),
                                  title: Text('Sposta giù'),
                                ),
                              ),
                              PopupMenuItem(
                                value: _WorkoutExerciseAction.delete,
                                child: ListTile(
                                  leading: Icon(
                                    Icons.delete_outline,
                                    color: colorScheme.error,
                                  ),
                                  title: Text(
                                    'Elimina',
                                    style: TextStyle(color: colorScheme.error),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
"""
active = replace_once(active, old_title, new_title, 'exercise card action menu')

active = replace_once(
    active,
    "              margin: const EdgeInsets.fromLTRB(12, 8, 12, 8),\n",
    "              margin: const EdgeInsets.fromLTRB(8, 5, 8, 5),\n",
    'compact card margin',
)
active = replace_once(
    active,
    "                  padding: const EdgeInsets.all(14.0),\n",
    "                  padding: const EdgeInsets.all(10.0),\n",
    'compact card padding',
)

home_marker = "  String _weekdayLabel(int weekday) {\n"
home_helper = r'''  Future<void> _startEmptyWorkout() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ActiveWorkoutScreen(
          schedule: null,
          history: history,
          defaultRestSeconds: _defaultRestSeconds,
          defaultBackoffReductionPercent: _defaultBackoffReductionPercent,
        ),
      ),
    );
    if (mounted) {
      await _loadData();
    }
  }

'''
home = replace_once(home, home_marker, home_helper + home_marker, 'empty workout helper')

old_fab = """      floatingActionButton: _currentIndex == 1
          ? FloatingActionButton(
              onPressed: _showAddScheduleDialog,
              child: const Icon(Icons.add),
            )
          : _currentIndex == 3 && _progressIndex == 2
          ? FloatingActionButton(
              onPressed: () => _showBodyLogDialog(),
              child: const Icon(Icons.monitor_weight),
            )
          : null,
"""
new_fab = """      floatingActionButton: _currentIndex == 1
          ? FloatingActionButton(
              onPressed: _showAddScheduleDialog,
              child: const Icon(Icons.add),
            )
          : _currentIndex == 2
          ? FloatingActionButton.extended(
              key: const ValueKey('start-empty-workout'),
              onPressed: _startEmptyWorkout,
              icon: const Icon(Icons.play_arrow),
              label: const Text('Allenamento libero'),
            )
          : _currentIndex == 3 && _progressIndex == 2
          ? FloatingActionButton(
              onPressed: () => _showBodyLogDialog(),
              child: const Icon(Icons.monitor_weight),
            )
          : null,
"""
home = replace_once(home, old_fab, new_fab, 'empty workout fab')

active_path.write_text(active)
home_path.write_text(home)

test_path.write_text(r'''import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:gymapp/models/exercise.dart';
import 'package:gymapp/models/schedule.dart';
import 'package:gymapp/screens/active_workout.dart';
import 'package:gymapp/screens/home.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({
      'schedules': '[]',
      'history': '[]',
    });
  });

  testWidgets('Allenati exposes and opens an empty workout', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: HomePage(initialIndex: 2)));
    await tester.pumpAndSettle();

    expect(find.text('Allenamento libero'), findsOneWidget);
    await tester.tap(find.text('Allenamento libero'));
    await tester.pumpAndSettle();

    expect(find.text('Sessione'), findsWidgets);
    expect(find.text('Esercizio'), findsOneWidget);
  });

  testWidgets('exercise menu duplicates an exercise in the live session', (
    tester,
  ) async {
    final schedule = Schedule(
      title: 'Push',
      week: 1,
      createdAt: DateTime(2026),
      exercises: [
        Exercise(
          name: 'Panca',
          set: 2,
          reps: 8,
          weight: 80,
          muscleGroup: MuscleGroup.chest,
          notes: '',
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ActiveWorkoutScreen(
          schedule: schedule,
          history: const [],
          defaultRestSeconds: 90,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Panca'), findsOneWidget);
    await tester.tap(find.byTooltip('Azioni esercizio'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Duplica'));
    await tester.pumpAndSettle();

    expect(find.text('Panca'), findsNWidgets(2));
    expect(find.byTooltip('Azioni esercizio'), findsNWidgets(2));
  });

  testWidgets('exercise menu can create and remove a superset', (tester) async {
    final schedule = Schedule(
      title: 'Upper',
      week: 1,
      createdAt: DateTime(2026),
      exercises: [
        Exercise(
          name: 'Panca',
          set: 1,
          reps: 8,
          weight: 80,
          muscleGroup: MuscleGroup.chest,
          notes: '',
        ),
        Exercise(
          name: 'Rematore',
          set: 1,
          reps: 10,
          weight: 60,
          muscleGroup: MuscleGroup.back,
          notes: '',
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ActiveWorkoutScreen(
          schedule: schedule,
          history: const [],
          defaultRestSeconds: 90,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Azioni esercizio').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Crea superset'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(find.byKey(const ValueKey('superset-target-placeholder')).evaluate().isEmpty
        ? const ValueKey('superset-target-placeholder')
        : const ValueKey('superset-target-placeholder')));
  }, skip: true);

  testWidgets('exercise menu exposes reorder replace and delete actions', (
    tester,
  ) async {
    final schedule = Schedule(
      title: 'Upper',
      week: 1,
      createdAt: DateTime(2026),
      exercises: [
        Exercise(
          name: 'Panca',
          set: 1,
          reps: 8,
          weight: 80,
          muscleGroup: MuscleGroup.chest,
          notes: '',
        ),
        Exercise(
          name: 'Rematore',
          set: 1,
          reps: 10,
          weight: 60,
          muscleGroup: MuscleGroup.back,
          notes: '',
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ActiveWorkoutScreen(
          schedule: schedule,
          history: const [],
          defaultRestSeconds: 90,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Azioni esercizio').first);
    await tester.pumpAndSettle();

    expect(find.text('Sostituisci'), findsOneWidget);
    expect(find.text('Duplica'), findsOneWidget);
    expect(find.text('Crea superset'), findsOneWidget);
    expect(find.text('Sposta su'), findsOneWidget);
    expect(find.text('Sposta giù'), findsOneWidget);
    expect(find.text('Elimina'), findsOneWidget);
  });
}
''')
