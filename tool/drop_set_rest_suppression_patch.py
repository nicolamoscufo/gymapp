from pathlib import Path


def replace_once(path: Path, old: str, new: str, label: str) -> None:
    text = path.read_text()
    count = text.count(old)
    if count != 1:
        raise SystemExit(f'{label}: expected 1 occurrence, found {count}')
    path.write_text(text.replace(old, new, 1))


manager = Path('lib/active_workout_exercise_manager.dart')
replace_once(
    manager,
    '''  bool shouldStartRestAfterSet(WorkoutExercise exercise) {
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
''',
    '''  bool hasPendingDropContinuation(
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
''',
    'exercise manager rest semantics',
)

screen = Path('lib/screens/active_workout.dart')
replace_once(
    screen,
    '''  bool _shouldStartRestAfterSet(WorkoutExercise exercise) {
    return _exerciseManager.shouldStartRestAfterSet(exercise);
  }

  void _advanceSupersetNavigation(WorkoutExercise exercise) {
    final next = _exerciseManager.nextSupersetMember(exercise);
''',
    '''  bool _shouldStartRestAfterSet(
    WorkoutExercise exercise,
    int completedSetIndex,
  ) {
    return _exerciseManager.shouldStartRestAfterSet(
      exercise,
      completedSetIndex: completedSetIndex,
    );
  }

  void _advanceSupersetNavigation(
    WorkoutExercise exercise,
    int completedSetIndex,
  ) {
    final next = _exerciseManager.nextSupersetMemberAfterSet(
      exercise,
      completedSetIndex,
    );
''',
    'screen rest/superset wrappers',
)
replace_once(
    screen,
    '''    if (exercise.technique == IntensityTechnique.topsetBackoff &&
        setIndex == 0) {
''',
    '''    if (_exerciseManager.hasPendingDropContinuation(exercise, setIndex)) {
      return 'Prossimo: drop set, senza recupero.';
    }

    if (exercise.technique == IntensityTechnique.topsetBackoff &&
        setIndex == 0) {
''',
    'drop set next hint',
)
replace_once(
    screen,
    '''      if (_shouldStartRestAfterSet(exercise)) {
        _startRestForExercise(exercise);
      }
      _advanceSupersetNavigation(exercise);
''',
    '''      if (_shouldStartRestAfterSet(exercise, setIndex)) {
        _startRestForExercise(exercise);
      }
      _advanceSupersetNavigation(exercise, setIndex);
''',
    'toggle rest/navigation call',
)
replace_once(
    screen,
    '''                                    InkWell(
                                      onTap: () => _toggleSetCompleted(
''',
    '''                                    InkWell(
                                      key: ValueKey('complete-${exSet.id}'),
                                      onTap: () => _toggleSetCompleted(
''',
    'completion test key',
)

manager_test = Path('test/active_workout_exercise_manager_test.dart')
text = manager_test.read_text()
marker = '''  test('superset navigation and rest semantics follow session order', () {
'''
if marker not in text:
    raise SystemExit('manager test insertion anchor not found')
new_tests = '''  test('drop continuation suppresses rest until the drop chain ends', () {
    final exercise = _workoutExercise('Lateral raise');
    exercise.sets = [
      ExerciseSet(weight: 12, reps: 12),
      ExerciseSet(weight: 9, reps: 10, type: SetType.drop),
      ExerciseSet(weight: 6, reps: 10, type: SetType.drop),
    ];
    final current = _session(exercises: [exercise]);
    final manager = _manager(current);

    expect(manager.hasPendingDropContinuation(exercise, 0), isTrue);
    expect(manager.hasPendingDropContinuation(exercise, 1), isTrue);
    expect(manager.hasPendingDropContinuation(exercise, 2), isFalse);
    expect(
      manager.shouldStartRestAfterSet(exercise, completedSetIndex: 0),
      isFalse,
    );
    expect(
      manager.shouldStartRestAfterSet(exercise, completedSetIndex: 1),
      isFalse,
    );
    expect(
      manager.shouldStartRestAfterSet(exercise, completedSetIndex: 2),
      isTrue,
    );

    exercise.sets[1].isCompleted = true;
    expect(manager.hasPendingDropContinuation(exercise, 0), isFalse);
  });

  test('drop continuation takes priority over superset rest and navigation', () {
    final partner = _workoutExercise('Curl', supersetGroup: 11);
    final dropExercise = _workoutExercise('Pushdown', supersetGroup: 11);
    dropExercise.sets = [
      ExerciseSet(weight: 30, reps: 10),
      ExerciseSet(weight: 22.5, reps: 10, type: SetType.drop),
    ];
    final current = _session(exercises: [partner, dropExercise]);
    final manager = _manager(current);

    // Pushdown is the last superset member, so the legacy rule would rest here.
    expect(
      manager.shouldStartRestAfterSet(dropExercise, completedSetIndex: 0),
      isFalse,
    );
    expect(manager.nextSupersetMemberAfterSet(dropExercise, 0), isNull);

    // After the final drop, the normal superset cycle resumes.
    expect(
      manager.shouldStartRestAfterSet(dropExercise, completedSetIndex: 1),
      isTrue,
    );
    expect(manager.nextSupersetMemberAfterSet(dropExercise, 1)?.id, partner.id);
  });

'''
manager_test.write_text(text.replace(marker, new_tests + marker, 1))

screen_test = Path('test/active_workout_screen_test.dart')
text = screen_test.read_text()
closing = '\n}\n'
if not text.endswith(closing):
    raise SystemExit('screen test final brace not found')
widget_test = '''
  testWidgets('drop set skips automatic rest until the drop chain ends', (
    tester,
  ) async {
    final session = WorkoutSession(
      id: 'drop_session',
      scheduleTitle: 'Drop workout',
      startTime: DateTime(2026, 8, 26, 10),
      endTime: DateTime(2026, 8, 26, 10),
      exercises: [
        WorkoutExercise(
          id: 'drop_exercise',
          name: 'Alzate laterali',
          notes: '',
          technique: IntensityTechnique.none,
          restSeconds: 90,
          sets: [
            ExerciseSet(id: 'normal_set', weight: 12, reps: 12),
            ExerciseSet(
              id: 'drop_set',
              weight: 9,
              reps: 10,
              type: SetType.drop,
            ),
          ],
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ActiveWorkoutScreen.resume(
          resumedSession: session,
          history: const [],
          defaultRestSeconds: 90,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final normalComplete = find.byKey(const ValueKey('complete-normal_set'));
    await tester.ensureVisible(normalComplete);
    await tester.tap(normalComplete);
    await tester.pump();

    expect(find.text('Prossimo: drop set, senza recupero.'), findsOneWidget);
    expect(find.textContaining('Recupero 01:'), findsNothing);

    final dropComplete = find.byKey(const ValueKey('complete-drop_set'));
    await tester.ensureVisible(dropComplete);
    await tester.tap(dropComplete);
    await tester.pump();

    expect(find.textContaining('Recupero 01:'), findsOneWidget);
  });
'''
screen_test.write_text(text[:-len(closing)] + widget_test + closing)

for path, forbidden in (
    (screen, '_shouldStartRestAfterSet(exercise)'),
    (screen, '_advanceSupersetNavigation(exercise);'),
):
    content = path.read_text()
    if forbidden in content:
        raise SystemExit(f'unexpected leftover {forbidden}')
