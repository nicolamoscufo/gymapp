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
    "import '../active_workout_rest_controller.dart';\nimport '../active_workout_schedule_sync.dart';\n",
    'schedule sync import',
)

replace_once(
    '''  ActiveWorkoutExerciseManager get _exerciseManager =>
      ActiveWorkoutExerciseManager(
        session: session,
        sessionBuilder: _sessionBuilder,
      );
''',
    '''  ActiveWorkoutExerciseManager get _exerciseManager =>
      ActiveWorkoutExerciseManager(
        session: session,
        sessionBuilder: _sessionBuilder,
      );

  ActiveWorkoutScheduleSync get _scheduleSync => ActiveWorkoutScheduleSync(
    session: session,
    sessionBuilder: _sessionBuilder,
  );
''',
    'schedule sync getter',
)

replace_once(
    "  double _deloadWeight(double weight) => _sessionBuilder.deloadWeight(weight);\n\n",
    "",
    'obsolete deload delegate',
)

exercise_conversion = re.compile(
    r"  Exercise _exerciseFromWorkoutExercise\(WorkoutExercise exercise\) \{\n"
    r"    return _sessionBuilder\.exerciseFromWorkoutExercise\(exercise\);\n"
    r"  \}\n\n"
)
text, count = exercise_conversion.subn('', text, count=1)
if count != 1:
    raise SystemExit(f'obsolete workout conversion delegate: expected 1 occurrence, found {count}')

sync_block = re.compile(
    r"  Schedule\? _storedScheduleForSession\(List<Schedule> schedules\) \{\n"
    r".*?"
    r"  Future<void> _applyProgressionToSchedule\(\) async \{\n"
    r".*?"
    r"  \}\n\n"
    r"  @override\n  void dispose\(\)",
    re.S,
)
match = sync_block.search(text)
if not match:
    raise SystemExit('schedule sync block not found')

replacement = '''  Future<bool> _confirmSaveAddedExercises(Schedule? schedule) async {
    if (schedule == null || !mounted) {
      return false;
    }

    final newExercises = _scheduleSync.newExercisesForSchedule(schedule);
    if (newExercises.isEmpty) {
      return false;
    }

    final count = newExercises.length;
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          count == 1 ? 'Salvare nuovo esercizio?' : 'Salvare nuovi esercizi?',
        ),
        content: Text(
          count == 1
              ? 'Hai aggiunto ${newExercises.first.name}. Vuoi sovrascrivere la scheda ${schedule.title} con questo esercizio?'
              : 'Hai aggiunto $count esercizi. Vuoi sovrascrivere la scheda ${schedule.title} con questi esercizi?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Solo sessione'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sovrascrivi scheda'),
          ),
        ],
      ),
    );

    return result == true;
  }

  Future<void> _saveAddedExercisesToSchedule() async {
    final bundle = await AppDataStore.loadBundle();
    final storedSchedule = _scheduleSync.storedScheduleForSession(
      bundle.schedules,
      liveSchedule: widget.schedule,
    );
    if (storedSchedule == null) return;

    final addedIds = _scheduleSync.addNewExercisesToSchedule(storedSchedule);
    if (addedIds.isEmpty) return;
    _exerciseIdsAddedToScheduleThisFinish.addAll(addedIds);
    _scheduleSync.syncLiveSchedule(
      storedSchedule: storedSchedule,
      liveSchedule: widget.schedule,
    );
    await AppDataStore.saveSchedules(bundle.schedules);
  }

  Future<void> _applyProgressionToSchedule() async {
    final bundle = await AppDataStore.loadBundle();
    final storedSchedule = _scheduleSync.storedScheduleForSession(
      bundle.schedules,
      liveSchedule: widget.schedule,
    );
    if (storedSchedule == null) return;

    _scheduleSync.applyProgressionToSchedule(
      storedSchedule: storedSchedule,
      history: bundle.history,
      skipSourceExerciseIds: _exerciseIdsAddedToScheduleThisFinish,
    );
    await AppDataStore.saveSchedules(bundle.schedules);
  }

  @override
  void dispose()'''
text = text[:match.start()] + replacement + text[match.end():]

replace_once(
    '''    final saveAddedExercises = await _confirmSaveAddedExercises(
      _storedScheduleForSession(bundle.schedules),
    );
''',
    '''    final saveAddedExercises = await _confirmSaveAddedExercises(
      _scheduleSync.storedScheduleForSession(
        bundle.schedules,
        liveSchedule: widget.schedule,
      ),
    );
''',
    'finish schedule lookup',
)

for forbidden in (
    '_storedScheduleForSession(',
    '_workoutExerciseExistsInSchedule(',
    '_newExercisesForSchedule(',
    '_exerciseFromWorkoutExercise(',
    '_deloadWeight(',
):
    if forbidden in text:
        lines = [
            f'{i}: {line}'
            for i, line in enumerate(text.splitlines(), 1)
            if forbidden in line
        ]
        raise SystemExit(f'unexpected leftover {forbidden}: ' + ' | '.join(lines[:10]))

path.write_text(text)
